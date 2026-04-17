function varargout = FermiViewer()
%FERMION  Standalone electron microscopy image viewer and analysis tool.
%
% ── Syntax ────────────────────────────────────────────────────────────────
%
%   FermiViewer()
%   api = FermiViewer()
%
% ── Description ───────────────────────────────────────────────────────────
%
%   Interactive uifigure GUI for viewing and analysing electron microscopy
%   images.  Supports TIFF (.tif/.tiff) and headerless RAW binary files.
%   Images are displayed with calibrated pixel coordinates, mouse-hover
%   intensity readout, zoom controls, and a metadata inspector.
%
%   The GUI follows the same monolithic-function architecture as
%   BosonPlotter.m: all mutable state lives in the appData struct, all
%   callbacks are nested functions sharing closure over appData and widget
%   handles, and a programmatic API struct is returned when called with an
%   output argument.
%
% ── Supported File Formats ────────────────────────────────────────────────
%
%   Extension(s)      Parser              Description
%   ──────────────    ──────────────────  ─────────────────────────────────
%   .tif / .tiff      importTIFF          TIFF images (8/16/32-bit, FEI)
%   .raw              importRawImage      Headerless binary (user dims)
%   .dm3 / .dm4       importDM3           Gatan DigitalMicrograph v3/v4
%
% ── GUI Layout ────────────────────────────────────────────────────────────
%
%   +------------------------------------------------------------------+
%   | Toolbar: [Open Files...] [Remove] | [Fit] [1:1] | filename       |
%   +------------------------------------------------------------------+
%   |            |                                  |                   |
%   | Image List |     Main Image Display           | Tools Panel       |
%   | (listbox)  |     (uiaxes + imagesc)           |                   |
%   |            |                                  | -- Contrast --    |
%   |            |                                  | -- Histogram --   |
%   |            |                                  | -- Measurement -- |
%   |            |                                  | -- Processing --  |
%   |            |                                  | -- Metadata --    |
%   |            |                                  | [metadata text]   |
%   +------------------------------------------------------------------+
%   | Status: 2048x2048 px | 16-bit | 2.4 nm/px | (512, 384) = 1547   |
%   +------------------------------------------------------------------+
%
% ── Programmatic API ──────────────────────────────────────────────────────
%
%   api = FermiViewer() returns a struct of function handles:
%
%   api.fig                          — figure handle
%   api.loadImages(paths)            — load a cell array of file paths
%   api.getImages()                  — return loaded image data structs
%   api.getActiveIdx()               — index of active image (0 = none)
%   api.setActiveIdx(idx)            — switch to image at index idx
%   api.setContrast(low, high)       — set Low/High contrast window
%   api.autoContrast()               — auto-stretch to [2nd, 98th] percentile
%   api.getLineProfile(x1,y1,x2,y2) — extract line profile
%   api.applyFilter(type, params)    — type='gaussian' (params.Sigma) or 'median' (params.WindowSize)
%   api.computeFFT()                 — compute FFT; returns struct with .magnitude/.phase
%   api.exportImage(path)            — save current displayImg to PNG or TIFF
%   api.close()                      — close figure
%
%   Headless usage (e.g. in test_em_gui_harness.m):
%     api = FermiViewer();
%     api.fig.Visible = 'off';
%     api.loadImages({'sem_image.tif'});
%     imgs = api.getImages();
%     api.close();
%
% ── Requirements ──────────────────────────────────────────────────────────
%
%   MATLAB R2021b+ (arguments blocks, uifigure, uilistbox Multiselect).
%   No external toolboxes required.
%
% ── See Also ──────────────────────────────────────────────────────────────
%
%   parser.importTIFF, parser.importRawImage, parser.importAuto,
%   BosonPlotter, test_em_gui_harness

    % ════════════════════════════════════════════════════════════════════
    %  SHARED APPLICATION STATE
    % ════════════════════════════════════════════════════════════════════
    % Mirror BosonPlotter's session-scoped warning suppression — see the
    % corresponding block in BosonPlotter.m for rationale.
    warning('off', 'MATLAB:Axes:NegativeDataInLogAxis');
    warning('off', 'MATLAB:print:ReplacingTransparentBackgroundWithDefaultColor');

    appData.transformToolbarBtns = gobjects(0);  % icon toolbar above image (populated by buildTransformToolbar)
    appData.images         = {};    % cell array of loaded data structs (from parsers)
    appData.activeIdx      = 0;    % index of currently displayed image (0 = none)
    appData.rawPixels      = [];   % original pixels from parser (reset on undo)
    appData.preCropPixels  = [];   % snapshot of rawPixels before crop (for undo)
    appData.filteredPixels = [];   % pixels after filters, before contrast
    appData.displayImg     = [];   % final [0,1] image shown via CData
    appData.imgHandle      = [];   % handle to the imagesc graphics object
    appData.overlays   = struct( ...
        'scalebar',     [], ...      % struct with .bar and .label handles from addScaleBar
        'scalebarL',    [], ...      % compare-mode left scale bar
        'scalebarR',    [], ...      % compare-mode right scale bar
        'lines',        {{}}, ...   % cell array of line graphics handles
        'clickMarkers', {{}}, ...   % cell array of click-marker graphics handles
        'distLabels',   {{}}, ...   % cell array of text graphics handles
        'measurements', {{}}, ...   % cell array of measurement structs (for draggable endpoints)
        'textAnnotations', {{}});  % cell array of text annotation structs
    appData.lastProfile   = struct('dist', [], 'intensity', [], 'unit', 'px');
    appData.captureMode   = '';     % '' | 'profile' | 'distance' | 'zoom' | 'crop' | 'savecrop' | 'annotation' | 'angle' | 'polyline' | 'roistats' | 'scalebar' | 'dspacing' | 'roiellipse' | 'roipoly' | 'arrow' | 'annotline' | 'annotrect' | 'annotcircle' | 'lattice' | 'gpa'
    appData.captureClicks = [];     % [Nx2] accumulated click coords (x y per row)
    appData.selectedMeasIdx = 0;    % index into overlays.measurements; 0 = none selected
    appData.lastDir       = '';     % last browsed directory for file open dialog

    % Comparison mode state
    appData.compareMode        = false;   % true when side-by-side is active
    appData.compareIdxL        = 0;       % left panel image index
    appData.compareIdxR        = 0;       % right panel image index
    appData.compareActivePanel = 'L';     % 'L' or 'R' — which panel arrows control

    % EDS multi-channel composite mode
    appData.edsMode        = false;      % true when EDS composite is active
    appData.edsChannels    = {};         % cell array of structs: .imageIdx, .label, .color, .visible, .intensity
    appData.edsComposite   = [];         % [H x W x 3] double RGB composite

    % EELS mode
    appData.eelsMode       = false;
    appData.eelsData       = [];      % spectrumData struct from importDM3
    appData.eelsCube       = [];      % [Ny x Nx x nE] spectrum image cube
    appData.eelsEnergyAxis = [];      % [nE x 1] energy axis (eV)
    appData.eelsFig        = [];      % handle to spectrum figure
    appData.eelsSSD        = [];      % single-scattering distribution from Fourier-log
    appData.eelsKKResult   = [];      % Kramers-Kronig result struct
    appData.eelsSVDResult  = [];      % SVD decomposition result struct

    % Diffraction indexing
    appData.diffMode       = false;
    appData.diffSpots      = [];      % [N x 2] spot positions [row, col]
    appData.diffResults    = [];      % indexDiffraction result struct
    appData.diffCameraLen  = NaN;     % camera length in mm
    appData.diffAccVoltage = 200;     % kV

    % EDS quantification
    appData.edsQuantified  = false;
    appData.edsElements    = {};      % cell of element symbols
    appData.edsAtomicPct   = {};      % cell of [HxW] atomic% maps
    appData.edsWeightPct   = {};      % cell of [HxW] weight% maps

    % Annotation defaults
    appData.annotationColor = [1 1 1];    % white
    appData.scaleBarColor   = 'white';    % 'white' | 'black' — SSoT for scale bar colour

    % Box-zoom state (image axes rubber-band drag)
    appData.zoomStartXY     = [];   % [x y] in data coords at drag start
    appData.zoomRect        = [];   % rectangle handle used for live preview
    appData.prevMotionFcn   = '';   % saved WindowButtonMotionFcn during box-zoom
    appData.prevUpFcn       = '';   % saved WindowButtonUpFcn during box-zoom
    appData.lastClickTick   = 0;    % manual double-click detection (uifigure/Mac fallback)

    % Context menus (reapplied to imgHandle on each displayImage; Mac uifigure
    % does not reliably deliver right-clicks to the parent axes)
    appData.cmImage         = [];   % uicontextmenu for image axes / image object
    appData.cmList          = [];   % uicontextmenu for thumbnail list

    % Undo stack (cap at 5 entries)
    appData.undoStack     = {};    % cell array of {rawPixels, filteredPixels} snapshots
    appData.undoStackMax  = 5;

    % Stack navigator state (multi-frame TIFF)
    appData.stackFrames   = {};    % cell array of 2D matrices (one per frame)
    appData.stackIdx      = 0;     % current frame index (0 = not a stack)

    % Recent files
    appData.recentFiles   = {};    % cell array of file paths (most recent first)

    % Gamma
    appData.gamma         = 1.0;   % gamma correction exponent

    % Contrast transform and invert
    appData.contrastTransform = 'linear';   % 'linear' | 'log' | 'sqrt' | 'power'
    appData.contrastInvert    = false;       % true = invert image after contrast

    % Per-image contrast/gamma state cache — parallel to appData.images.
    % Saved when switching away from an image and restored when returning,
    % so contrast tweaks persist across file toggles within one session.
    % State dies with the figure (no disk persistence), which is deliberate:
    % closing the viewer resets everything to defaults.
    appData.imageContrastState = {};
    appData.lastDisplayedIdx   = 0;   % tracks the PREVIOUS displayImage() target

    % Render mode & display buffer
    %   'hq'   — area-averaged downsample to axes pixel size (DM-style;
    %            preserves atomic detail on downsample; contrast pipeline
    %            runs on the downsampled buffer → 10-30× faster on 2k/4k)
    %   'fast' — no preprocessing; pipeline runs on native filteredPixels
    % displayPixels is rebuilt on: image load, filter/crop/rotate/undo,
    % axes zoom (via XLim/YLim PostSet listeners), and renderMode toggle.
    appData.renderMode     = 'hq';
    appData.displayPixels  = [];
    appData.displayRegion  = [];   % [x0, y0, x1, y1] bounds the displayPixels buffer covers

    % Theme
    appData.darkMode      = true;  % true = dark (default), false = light

    % Preferences (persisted to .emviewer_prefs.mat)
    appData.prefs = struct( ...
        'defaultColormap', 'gray', ...
        'autoContrastLow', 2, ...        % percentile
        'autoContrastHigh', 98, ...      % percentile
        'exportDPI', 300, ...
        'pixelInspectorSize', 7);        % NxN neighborhood

    % Measurement log for export
    appData.measurementLog = {};   % cell array of structs: {type, value, unit, ...}

    % Session state
    appData.sessionFile = '';

    % Panel drag-resize state
    appData.panelResizeDir   = '';    % '' | 'v_col12' | 'v_col23'
    appData.panelResizeStart = [];   % [x y] fig-pixel at drag start
    appData.panelResizeOrig  = [];   % panel dimension (px) at drag start
    appData.leftPanelWidth   = 160;  % user-resized left panel width (px)
    appData.toolsPanelWidth  = 276;  % user-resized tools panel width (px)
    appData.listPanelHeight  = 0;    % (legacy — export panel moved to tools)
    MIN_LEFT_W  = 100;
    MIN_TOOLS_W = 180;
    SNAP_PX     = 5;

    % Load recent files from persistent storage
    recentFilePath = fullfile(fileparts(mfilename('fullpath')), '.emviewer_recent.mat');
    try
        if isfile(recentFilePath)
            tmp = load(recentFilePath, 'recentFiles');
            if isfield(tmp, 'recentFiles')
                appData.recentFiles = tmp.recentFiles;
            end
        end
    catch
        % Ignore errors loading recent files
    end

    % Load persisted preferences
    prefsFilePath = fullfile(fileparts(mfilename('fullpath')), '.emviewer_prefs.mat');
    try
        if isfile(prefsFilePath)
            tmp = load(prefsFilePath, 'prefs');
            if isfield(tmp, 'prefs')
                flds = fieldnames(tmp.prefs);
                for fj = 1:numel(flds)
                    appData.prefs.(flds{fj}) = tmp.prefs.(flds{fj});
                end
            end
        end
    catch
    end

    % ════════════════════════════════════════════════════════════════════
    %  SEMANTIC BUTTON COLOUR PALETTE
    % ════════════════════════════════════════════════════════════════════
    bp_ = styles.buttonPalette();
    BTN_PRIMARY   = bp_.primary;   % green  — primary actions
    BTN_DANGER    = bp_.danger;    % red    — destructive actions
    BTN_TOOL      = bp_.tool;     % gray   — secondary tools
    BTN_EXPORT    = bp_.export;    % slate  — export actions
    BTN_FG        = bp_.fg;       % white text on dark buttons
    OVERLAY_COLOR = [0 1 1];            % cyan   — measurement overlays

    % ════════════════════════════════════════════════════════════════════
    %  FIGURE
    % ════════════════════════════════════════════════════════════════════
    fig = uifigure('Name', 'FermiViewer — Electron Microscopy Image Viewer', ...
                   'Position', [100 100 1200 720], ...
                   'AutoResizeChildren', 'off');
    fig.CloseRequestFcn = @onFigureClose;

    % Drag-and-drop file loading (requires MATLAB R2022b+)
    try
        fig.DropFcn = @onFileDrop;
    catch
        % DropFcn not supported on older MATLAB versions — ignore
    end

    % ── Help menu (Report a Bug) ─────────────────────────────────────────
    helpMenu = uimenu(fig, 'Text', '&Help');
    uimenu(helpMenu, 'Text', 'Report a Bug...', ...
        'MenuSelectedFcn', @(~,~) bugReport.reportBug(Source="FermiViewer"));

    % ════════════════════════════════════════════════════════════════════
    %  ROOT GRID: 3 rows x 1 col
    %    Row 1 (30px):  Toolbar
    %    Row 2 (1x):    Main content area
    %    Row 3 (22px):  Status bar
    % ════════════════════════════════════════════════════════════════════
    rootGL = uigridlayout(fig, [3 1], ...
        'RowHeight',    {30, '1x', 22}, ...
        'ColumnWidth',  {'1x'}, ...
        'Padding',      [6 6 6 6], ...
        'RowSpacing',   4, ...
        'ColumnSpacing', 0);

    % ════════════════════════════════════════════════════════════════════
    %  ROW 1: TOOLBAR
    %  [Open Files...] [Remove] | gap | [Fit] [1:1] | filename label
    % ════════════════════════════════════════════════════════════════════
    % Toolbar: 11 columns — separators replaced by extra ColumnSpacing
    %   Col 1 (80):  Open...
    %   Col 2 (120): Recent files dropdown
    %   Col 3 (55):  Remove
    %   Col 4 (35):  Fit
    %   Col 5 (35):  1:1
    %   Col 6 (60):  Compare
    %   Col 7 (35):  Grid
    %   Col 8 (35):  EDS
    %   Col 9 (32):  Prefs (gear)
    %   Col 10 (32): Theme toggle
    %   Col 11 (1x): Filename label
    toolbarGL = uigridlayout(rootGL, [1 11], ...
        'ColumnWidth', {80, 120, 55, 35, 35, 60, 35, 35, 32, 32, '1x'}, ...
        'RowHeight',   {'1x'}, ...
        'Padding',     [4 2 4 2], ...
        'ColumnSpacing', 6);
    toolbarGL.Layout.Row = 1;
    toolbarGL.Layout.Column = 1;

    btnOpen = uibutton(toolbarGL, 'Text', 'Open...', ...
        'ButtonPushedFcn', @onOpenFiles, ...
        'BackgroundColor', BTN_PRIMARY, ...
        'FontColor', BTN_FG, ...
        'FontWeight', 'bold', ...
        'Tooltip', 'Browse for TIFF or RAW image files to load');
    btnOpen.Layout.Row = 1; btnOpen.Layout.Column = 1;

    ddRecent = uidropdown(toolbarGL, ...
        'Items', {'(recent files)'}, ...
        'Value', '(recent files)', ...
        'ValueChangedFcn', @onRecentFileSelected, ...
        'BackgroundColor', BTN_TOOL, ...
        'FontColor', BTN_FG, ...
        'Tooltip', 'Open a recently loaded file');
    ddRecent.Layout.Row = 1; ddRecent.Layout.Column = 2;

    btnRemove = uibutton(toolbarGL, 'Text', 'Remove', ...
        'ButtonPushedFcn', @onRemoveImage, ...
        'BackgroundColor', BTN_DANGER, ...
        'FontColor', BTN_FG, ...
        'Tooltip', 'Remove the selected image(s) from the list');
    btnRemove.Layout.Row = 1; btnRemove.Layout.Column = 3;

    btnZoomFit = uibutton(toolbarGL, 'Text', 'Fit', ...
        'ButtonPushedFcn', @onZoomFit, ...
        'BackgroundColor', BTN_TOOL, ...
        'FontColor', BTN_FG, ...
        'Tooltip', 'Zoom to fit the entire image in the axes');
    btnZoomFit.Layout.Row = 1; btnZoomFit.Layout.Column = 4;

    btnZoomActual = uibutton(toolbarGL, 'Text', '1:1', ...
        'ButtonPushedFcn', @onZoomActual, ...
        'BackgroundColor', BTN_TOOL, ...
        'FontColor', BTN_FG, ...
        'Tooltip', 'Zoom to actual pixels (100% — one image pixel = one screen pixel)');
    btnZoomActual.Layout.Row = 1; btnZoomActual.Layout.Column = 5;

    btnCompare = uibutton(toolbarGL, 'state', 'Text', 'Compare', ...
        'ValueChangedFcn', @onCompareToggle, ...
        'BackgroundColor', BTN_TOOL, ...
        'FontColor', BTN_FG, ...
        'Enable', 'off', ...
        'Tooltip', 'Side-by-side comparison (Tab to switch active panel, arrows to scroll)');
    btnCompare.Layout.Row = 1; btnCompare.Layout.Column = 6;

    btnGrid = uibutton(toolbarGL, 'Text', 'Grid', ...
        'ButtonPushedFcn', @onThumbnailGrid, ...
        'BackgroundColor', BTN_TOOL, ...
        'FontColor', BTN_FG, ...
        'Enable', 'off', ...
        'Tooltip', 'Show thumbnail grid of all loaded images');
    btnGrid.Layout.Row = 1; btnGrid.Layout.Column = 7;

    btnEDSToolbar = uibutton(toolbarGL, 'state', 'Text', 'EDS', ...
        'ValueChangedFcn', @onEDSToolbarToggle, ...
        'BackgroundColor', BTN_TOOL, ...
        'FontColor', BTN_FG, ...
        'Enable', 'off', ...
        'Tooltip', 'Enter/exit multi-channel EDS false-color composite mode');
    btnEDSToolbar.Layout.Row = 1; btnEDSToolbar.Layout.Column = 8;

    btnPrefs = uibutton(toolbarGL, 'Text', char(9881), ...
        'ButtonPushedFcn', @onPreferences, ...
        'BackgroundColor', BTN_TOOL, ...
        'FontColor', BTN_FG, ...
        'Tooltip', 'Preferences — default colormap, percentiles, export settings');
    btnPrefs.Layout.Row = 1; btnPrefs.Layout.Column = 9;

    btnThemeToggle = uibutton(toolbarGL, 'Text', char(9790), ...
        'ButtonPushedFcn', @onThemeToggle, ...
        'BackgroundColor', BTN_TOOL, ...
        'FontColor', BTN_FG, ...
        'Tooltip', 'Toggle dark / light mode');
    btnThemeToggle.Layout.Row = 1; btnThemeToggle.Layout.Column = 10;

    lblFilename = uilabel(toolbarGL, 'Text', '(no image loaded)', ...
        'FontSize', 11, ...
        'FontColor', [0.85 0.85 0.85], ...
        'HorizontalAlignment', 'left');
    lblFilename.Layout.Row = 1; lblFilename.Layout.Column = 11;

    % ════════════════════════════════════════════════════════════════════
    %  ROW 2: MAIN CONTENT — 3 columns
    %    Col 1 (180px):  Image list panel
    %    Col 2 (1x):     Image display (uiaxes)
    %    Col 3 (240px):  Tools panel (scrollable)
    % ════════════════════════════════════════════════════════════════════
    mainGL = uigridlayout(rootGL, [1 3], ...
        'ColumnWidth', {184, '1x', 276}, ...
        'RowHeight',   {'1x'}, ...
        'Padding',     [0 0 0 0], ...
        'ColumnSpacing', 6);
    mainGL.Layout.Row = 2;
    mainGL.Layout.Column = 1;

    % ── Col 1: Image list ────────────────────────────────────────────────
    listPanel = uipanel(mainGL, 'Title', 'Images', 'FontSize', 11);
    listPanel.Layout.Row = 1;
    listPanel.Layout.Column = 1;

    listGL = uigridlayout(listPanel, [1 1], ...
        'RowHeight', {'1x'}, ...
        'Padding', [4 4 4 4], ...
        'RowSpacing', 4);

    lbImages = uilistbox(listGL, ...
        'Items', {'(no images loaded)'}, ...
        'ItemsData', {0}, ...
        'Multiselect', 'on', ...
        'ValueChangedFcn', @onSelectImage, ...
        'Tooltip', 'Loaded images — click to display; Ctrl+click for multi-select');
    lbImages.Layout.Row = 1;

    % ── Col 2: Image display axes ────────────────────────────────────────
    axPanel = uipanel(mainGL, 'Title', '', 'BorderType', 'none');
    axPanel.Layout.Row = 1;
    axPanel.Layout.Column = 2;

    axGL = uigridlayout(axPanel, [3 1], ...
        'RowHeight', {28, '1x', 0}, ...
        'Padding', [2 2 2 2], ...
        'RowSpacing', 2);

    % ── Row 1: transform toolbar (icon-only buttons above the image) ────
    % Eight small icons for the most common transforms so they stay one
    % click away regardless of which Tools-panel tab is visible. Every
    % button delegates to a callback that already exists on the Transform
    % tab — no transform logic is duplicated here.
    %
    % Icons live in <toolboxRoot>/icons/fermiviewer/*.png (generated by
    % build_icons.m). If any file is missing, the button falls back to
    % a short text label so the GUI never silently breaks.
    toolbarGL = uigridlayout(axGL, [1 9], ...
        'ColumnWidth', {32, 32, 32, 32, 32, 32, 32, 32, '1x'}, ...
        'RowHeight',   {24}, ...
        'Padding',     [2 2 2 2], ...
        'ColumnSpacing', 3);
    toolbarGL.Layout.Row = 1;

    iconDir = fullfile(fileparts(mfilename('fullpath')), ...
                       'icons', 'fermiviewer');

    % Reset-all reuses setActiveIdxAPI(current) which re-reads the original
    % pixels from appData.images{idx}, rebuilding rawPixels/filteredPixels
    % from scratch — effectively a full transform undo for the active image.
    %
    % getActiveIdxAPI() is called at click time (not at toolbar-build time)
    % so the callback sees the live activeIdx rather than the 0 that was
    % in scope when the toolbar was constructed at startup.
    resetAllFcn = @(~,~) setActiveIdxAPI(getActiveIdxAPI());

    tbSpecs = {
        'rot_cw.png',    'CW',    'Rotate 90° clockwise',                                     @(~,~) onRotateFlip('rot90cw');
        'rot_ccw.png',   'CCW',   'Rotate 90° counter-clockwise',                             @(~,~) onRotateFlip('rot90ccw');
        'flip_h.png',    'FH',    'Flip horizontally (left-right mirror)',                    @(~,~) onRotateFlip('fliph');
        'flip_v.png',    'FV',    'Flip vertically (top-bottom mirror)',                      @(~,~) onRotateFlip('flipv');
        'zoom.png',      'Z',     'Zoom to box (Esc to cancel)',                              @onZoomBox;
        'fit.png',       'Fit',   'Fit image to window (reset zoom)',                         @onResetZoom;
        'reset_all.png', 'Reset', 'Reset all transforms (reload original image)',             resetAllFcn;
        'crop.png',      'Crop',  'Crop to rectangle (destructive — Undo Filters reverts)',   @onCropImage;
    };

    tbBtns = gobjects(1, size(tbSpecs, 1));
    for tbK = 1:size(tbSpecs, 1)
        tbIconPath = fullfile(iconDir, tbSpecs{tbK, 1});
        if isfile(tbIconPath)
            tbBtns(tbK) = uibutton(toolbarGL, ...
                'Icon',            tbIconPath, ...
                'Text',            '', ...
                'IconAlignment',   'center', ...
                'BackgroundColor', [0.96 0.96 0.97], ...
                'Tooltip',         tbSpecs{tbK, 3}, ...
                'ButtonPushedFcn', tbSpecs{tbK, 4}, ...
                'Enable',          'off');
        else
            tbBtns(tbK) = uibutton(toolbarGL, ...
                'Text',            tbSpecs{tbK, 2}, ...
                'FontSize',        9, ...
                'BackgroundColor', [0.96 0.96 0.97], ...
                'Tooltip',         tbSpecs{tbK, 3}, ...
                'ButtonPushedFcn', tbSpecs{tbK, 4}, ...
                'Enable',          'off');
        end
        tbBtns(tbK).Layout.Row = 1;
        tbBtns(tbK).Layout.Column = tbK;
    end
    appData.transformToolbarBtns = tbBtns;

    ax = uiaxes(axGL);
    ax.Layout.Row = 2;
    ax.Box = 'on';

    % Zoom/pan listener — rebuilds the HQ downsample buffer on viewport
    % change and pushes the new CData. No-op in Fast mode.
    addlistener(ax, 'XLim', 'PostSet', @(~,~) prepareDisplayBuffer(true));
    addlistener(ax, 'YLim', 'PostSet', @(~,~) prepareDisplayBuffer(true));
    ax.XTick = [];
    ax.YTick = [];
    title(ax, 'Open an image file to begin', 'Interpreter', 'none');
    xlabel(ax, '');
    ylabel(ax, '');
    colormap(ax, gray(256));
    ax.Toolbar.Visible = 'off';
    % Disable built-in uiaxes interactions so our ButtonDownFcn + ContextMenu
    % actually fire. Without this, uifigure's default pan/zoom/datatip layer
    % swallows mouse events on macOS before they reach our handlers.
    try
        disableDefaultInteractivity(ax);
    catch
    end
    ax.Interactions = [];
    ax.ButtonDownFcn = @onAxesMouseDown;

    % Stack navigator controls (row 3 of axGL, hidden until a stack is loaded)
    stackGL = uigridlayout(axGL, [1 5], ...
        'ColumnWidth', {40, 40, '1x', 40, 80}, ...
        'RowHeight', {24}, ...
        'Padding', [4 0 4 0], ...
        'ColumnSpacing', 4);
    stackGL.Layout.Row = 3;

    btnStackPrev = uibutton(stackGL, 'Text', '<', ...
        'ButtonPushedFcn', @(~,~) onStackNav(-1), ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, ...
        'Tooltip', 'Previous frame');
    btnStackPrev.Layout.Column = 1;

    btnStackNext = uibutton(stackGL, 'Text', '>', ...
        'ButtonPushedFcn', @(~,~) onStackNav(1), ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, ...
        'Tooltip', 'Next frame');
    btnStackNext.Layout.Column = 2;

    sldStackFrame = uislider(stackGL, ...
        'Value', 1, 'Limits', [1 2], ...
        'ValueChangedFcn', @onStackSlider, ...
        'Tooltip', 'Scroll through frames');
    sldStackFrame.Layout.Column = 3;
    sldStackFrame.MajorTicks = [];
    sldStackFrame.MinorTicks = [];

    btnStackMIP = uibutton(stackGL, 'Text', 'MIP', ...
        'ButtonPushedFcn', @onStackMIP, ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, ...
        'Tooltip', 'Maximum Intensity Projection across all frames');
    btnStackMIP.Layout.Column = 4;

    lblStackFrame = uilabel(stackGL, 'Text', '1 / 1', ...
        'FontSize', 10, 'HorizontalAlignment', 'center', ...
        'FontColor', [0.7 0.7 0.7]);
    lblStackFrame.Layout.Column = 5;

    % Comparison mode axes (created/destroyed dynamically)
    compareGL = [];   % uigridlayout replacing axGL when in compare mode
    axL       = [];   % left uiaxes
    axR       = [];   % right uiaxes
    compareLinkedZoom = true;  % whether to sync zoom between compare panels

    % Mouse hover tracking via figure-level motion callback
    fig.WindowButtonMotionFcn = @onMouseMotion;

    % Idle-mode mouse-down: starts panel resize if near a border
    fig.WindowButtonDownFcn = @onIdleMouseDown;

    % Keyboard: Escape cancels any in-progress two-click capture
    fig.KeyPressFcn = @onKeyPress;

    % ── Col 3: Tools panel ───────────────────────────────────────────────
    toolsPanel = uipanel(mainGL, 'Title', 'Tools', 'FontSize', 11, ...
        'Scrollable', 'on');
    toolsPanel.Layout.Row = 1;
    toolsPanel.Layout.Column = 3;

    % ── Collapsible section configuration ────────────────────────────────
    % Sections: {name, headerRow, panelRow, openHeight, defaultCollapsed}
    SECT_CONTRAST   = struct('name','Contrast',    'headerRow',1, 'panelRow',2,  'openHeight',250, 'collapsed',false);
    SECT_HISTOGRAM  = struct('name','Histogram',   'headerRow',3, 'panelRow',4,  'openHeight',80,  'collapsed',true);
    SECT_MEASURE    = struct('name','Measurement', 'headerRow',5, 'panelRow',6,  'openHeight',400, 'collapsed',true);
    SECT_PROCESS    = struct('name','Processing',  'headerRow',7, 'panelRow',8,  'openHeight',230, 'collapsed',true);
    SECT_ANNOT      = struct('name','Annotations',  'headerRow',9,  'panelRow',10, 'openHeight',145, 'collapsed',true);
    SECT_EDS        = struct('name','EDS Channels', 'headerRow',11, 'panelRow',12, 'openHeight',520, 'collapsed',true);
    SECT_META       = struct('name','Metadata',     'headerRow',13, 'panelRow',14, 'openHeight',120, 'collapsed',true);
    SECT_EXPORT     = struct('name','Export & Style','headerRow',19, 'panelRow',20, 'openHeight',370, 'collapsed',false);
    SECT_EELS       = struct('name','EELS Spectrum','headerRow',15, 'panelRow',16, 'openHeight',470, 'collapsed',true);
    SECT_DIFF       = struct('name','Diffraction',  'headerRow',17, 'panelRow',18, 'openHeight',380, 'collapsed',true);

    % Compute initial row heights: collapsed sections get 0
    initH = {22, 230, 22, 0, 22, 0, 22, 0, 22, 0, 22, 0, 22, 0, 22, 0, 22, 0, 22, 370};
    % (Histogram=0, Measurement=0, Processing=0, Annotations=0, EDS=0, Metadata=0, EELS=0, Diff=0 on startup; Export open)

    toolsGL = uigridlayout(toolsPanel, [20 1], ...
        'RowHeight', initH, ...
        'ColumnWidth', {'1x'}, ...
        'Padding', [4 4 4 4], ...
        'RowSpacing', 1);

    % ── Section 1: Contrast ───────────────────────────────────────────────
    ARROW_OPEN = char(9660);   % ▼
    ARROW_SHUT = char(9654);   % ►
    HDR_BG   = [0.92 0.92 0.92];
    HDR_FG   = [0.15 0.15 0.15];

    btnContrastHeader = uibutton(toolsGL, 'Text', [ARROW_OPEN ' Contrast'], ...
        'HorizontalAlignment', 'left', ...
        'BackgroundColor', HDR_BG, 'FontColor', HDR_FG, ...
        'FontWeight', 'bold', 'FontSize', 11, ...
        'ButtonPushedFcn', @(~,~) toggleSection(SECT_CONTRAST));
    btnContrastHeader.Layout.Row = 1;

    pnlContrast = uipanel(toolsGL, 'BorderType', 'line');
    pnlContrast.Layout.Row = 2;

    % Inner grid: Low label+edit on row 1, Low slider on row 2, High on
    % 3-4, Gamma on 9-10. Label rows are 20 px tall so they can host a
    % small uieditfield next to the label for typed numeric entry.
    contrastInnerGL = uigridlayout(pnlContrast, [13 2], ...
        'RowHeight',   {20, 20, 20, 20, 2, 20, 20, 18, 20, 20, 18, 20, 18}, ...
        'ColumnWidth', {'1x', '1x'}, ...
        'Padding',     [3 2 3 2], ...
        'RowSpacing',  1, ...
        'ColumnSpacing', 3);

    lblLow = uilabel(contrastInnerGL, 'Text', 'Low', ...
        'FontSize', 8, 'HorizontalAlignment', 'left');
    lblLow.Layout.Row = 1; lblLow.Layout.Column = 1;

    efLow = uieditfield(contrastInnerGL, 'numeric', ...
        'Value', 0, 'FontSize', 9, ...
        'ValueDisplayFormat', '%.4g', ...
        'ValueChangedFcn', @onContrastEditChanged, ...
        'Tooltip', 'Type exact low-contrast value (matches slider)');
    efLow.Layout.Row = 1; efLow.Layout.Column = 2;

    sldLow = uislider(contrastInnerGL, ...
        'Value', 0, 'Limits', [0 1], ...
        'ValueChangedFcn', @onContrastChanged, ...
        'Tooltip', 'Lower contrast bound (dark clipping point)');
    sldLow.Layout.Row = 2; sldLow.Layout.Column = [1 2];
    sldLow.MajorTicks = [];
    sldLow.MinorTicks = [];

    lblHigh = uilabel(contrastInnerGL, 'Text', 'High', ...
        'FontSize', 8, 'HorizontalAlignment', 'left');
    lblHigh.Layout.Row = 3; lblHigh.Layout.Column = 1;

    efHigh = uieditfield(contrastInnerGL, 'numeric', ...
        'Value', 1, 'FontSize', 9, ...
        'ValueDisplayFormat', '%.4g', ...
        'ValueChangedFcn', @onContrastEditChanged, ...
        'Tooltip', 'Type exact high-contrast value (matches slider)');
    efHigh.Layout.Row = 3; efHigh.Layout.Column = 2;

    sldHigh = uislider(contrastInnerGL, ...
        'Value', 1, 'Limits', [0 1], ...
        'ValueChangedFcn', @onContrastChanged, ...
        'Tooltip', 'Upper contrast bound (bright clipping point)');
    sldHigh.Layout.Row = 4; sldHigh.Layout.Column = [1 2];
    sldHigh.MajorTicks = [];
    sldHigh.MinorTicks = [];

    % Gap row 5 is just spacing

    btnAutoContrast = uibutton(contrastInnerGL, 'Text', 'Auto', ...
        'ButtonPushedFcn', @onAutoContrast, ...
        'BackgroundColor', BTN_TOOL, ...
        'FontColor', BTN_FG, ...
        'Tooltip', 'Auto-stretch contrast to [2nd, 98th] percentile');
    btnAutoContrast.Layout.Row = 6; btnAutoContrast.Layout.Column = 1;

    btnResetContrast = uibutton(contrastInnerGL, 'Text', 'Reset', ...
        'ButtonPushedFcn', @onResetContrast, ...
        'BackgroundColor', BTN_TOOL, ...
        'FontColor', BTN_FG, ...
        'Tooltip', 'Reset contrast to full pixel range AND gamma to 1.0');
    btnResetContrast.Layout.Row = 6; btnResetContrast.Layout.Column = 2;

    ddColormap = uidropdown(contrastInnerGL, ...
        'Items', {'gray', 'parula', 'hot', 'jet', 'bone'}, ...
        'Value', 'gray', ...
        'ValueChangedFcn', @onColormapChanged, ...
        'Tooltip', 'Select colormap for image display');
    ddColormap.Layout.Row = 7; ddColormap.Layout.Column = [1 2];

    cbColorbar = uicheckbox(contrastInnerGL, ...
        'Text',    'Show Colorbar', ...
        'Value',   false, ...
        'Enable',  'off', ...
        'ValueChangedFcn', @onColorbarToggle, ...
        'Tooltip', 'Show/hide a colorbar next to the image');
    cbColorbar.Layout.Row = 8; cbColorbar.Layout.Column = [1 2];

    hColorbar = [];   % handle to colorbar object (created/deleted dynamically)

    % Row 9-10: Gamma label + editable value on row 9; slider on row 10.
    lblGamma = uilabel(contrastInnerGL, 'Text', 'Gamma', ...
        'FontSize', 8, 'HorizontalAlignment', 'left');
    lblGamma.Layout.Row = 9; lblGamma.Layout.Column = 1;

    efGamma = uieditfield(contrastInnerGL, 'numeric', ...
        'Value', 1, 'FontSize', 9, ...
        'Limits', [0.1 5.0], ...
        'ValueDisplayFormat', '%.2f', ...
        'ValueChangedFcn', @onContrastEditChanged, ...
        'Tooltip', 'Type exact gamma value (1.0 = linear; Reset button restores 1.0)');
    efGamma.Layout.Row = 9; efGamma.Layout.Column = 2;

    sldGamma = uislider(contrastInnerGL, ...
        'Value', 1, 'Limits', [0.1 5.0], ...
        'ValueChangedFcn', @onGammaChanged, ...
        'Tooltip', 'Non-linear intensity mapping (1.0 = linear, <1 = brighten darks, >1 = darken)');
    sldGamma.Layout.Row = 10; sldGamma.Layout.Column = [1 2];
    sldGamma.MajorTicks = [0.1 1.0 2.0 3.0 5.0];
    sldGamma.MinorTicks = [];

    % Row 11: Minimap toggle
    cbMinimap = uicheckbox(contrastInnerGL, ...
        'Text',    'Show Minimap', ...
        'Value',   false, ...
        'Enable',  'off', ...
        'ValueChangedFcn', @onMinimapToggle, ...
        'Tooltip', 'Show overview inset with zoomed viewport rectangle');
    cbMinimap.Layout.Row = 11; cbMinimap.Layout.Column = [1 2];

    % Row 12: Contrast transform dropdown
    ddContrastTransform = uidropdown(contrastInnerGL, ...
        'Items', {'linear', 'log', 'sqrt', 'power'}, ...
        'Value', 'linear', ...
        'ValueChangedFcn', @onContrastTransformChanged, ...
        'Tooltip', 'Display transform applied before contrast window (log for FFT/diffraction)');
    ddContrastTransform.Layout.Row = 12; ddContrastTransform.Layout.Column = [1 2];

    % Row 13: Invert checkbox (col 1) + render-mode dropdown (col 2)
    cbInvert = uicheckbox(contrastInnerGL, ...
        'Text',    'Invert', ...
        'Value',   false, ...
        'ValueChangedFcn', @onInvertToggle, ...
        'Tooltip', 'Invert image contrast (bright-field / dark-field toggle)');
    cbInvert.Layout.Row = 13; cbInvert.Layout.Column = 1;

    % Render quality selector. 'HQ' = DM-style area-averaged downsample
    % (preserves atomic detail when image > axes size). 'Fast' skips the
    % downsample step and renders the full-resolution buffer with
    % nearest-neighbor — use this if the HQ path is slow on very large
    % images or when exact per-pixel inspection is needed.
    ddRenderMode = uidropdown(contrastInnerGL, ...
        'Items',     {'HQ', 'Fast'}, ...
        'ItemsData', {'hq', 'fast'}, ...
        'Value',     'hq', ...
        'ValueChangedFcn', @onContrastEditChanged, ...
        'Tooltip',   'HQ = DM-style area-averaged downsample; Fast = raw pixels + nearest-neighbor');
    ddRenderMode.Layout.Row = 13; ddRenderMode.Layout.Column = 2;

    hMinimap     = [];   % handle to minimap axes (created/deleted dynamically)
    hMinimapRect = [];   % handle to viewport rectangle on minimap

    % ── Section 2: Histogram ──────────────────────────────────────────────
    btnHistogramHeader = uibutton(toolsGL, 'Text', [ARROW_SHUT ' Histogram'], ...
        'HorizontalAlignment', 'left', ...
        'BackgroundColor', HDR_BG, 'FontColor', HDR_FG, ...
        'FontWeight', 'bold', 'FontSize', 11, ...
        'ButtonPushedFcn', @(~,~) toggleSection(SECT_HISTOGRAM));
    btnHistogramHeader.Layout.Row = 3;

    pnlHistogram = uipanel(toolsGL, 'BorderType', 'line');
    pnlHistogram.Layout.Row = 4;

    histInnerGL = uigridlayout(pnlHistogram, [1 1], ...
        'Padding', [2 2 2 2]);

    histAx = uiaxes(histInnerGL);
    histAx.XTick = [];
    histAx.YTick = [];
    histAx.XColor = [0.5 0.5 0.5];
    histAx.YColor = [0.5 0.5 0.5];
    histAx.FontSize = 8;
    histAx.Box = 'on';
    histAx.XLim = [0 1];
    histAx.YLim = [0 1];
    histAx.Toolbar.Visible = 'off';
    title(histAx, '');
    xlabel(histAx, '');
    ylabel(histAx, '');

    % ── Section 3: Measurement ────────────────────────────────────────────
    btnMeasureHeader = uibutton(toolsGL, 'Text', [ARROW_SHUT ' Measurement'], ...
        'HorizontalAlignment', 'left', ...
        'BackgroundColor', HDR_BG, 'FontColor', HDR_FG, ...
        'FontWeight', 'bold', 'FontSize', 11, ...
        'ButtonPushedFcn', @(~,~) toggleSection(SECT_MEASURE));
    btnMeasureHeader.Layout.Row = 5;

    pnlMeasure = uipanel(toolsGL, 'BorderType', 'line');
    pnlMeasure.Layout.Row = 6;

    % 19-row grid inside the measurement panel:
    %   Row 1:  Scale bar checkbox
    %   Row 2:  Scale bar options — color toggle + font size spinner
    %   Row 3:  (separator gap)
    %   Row 4:  Line Profile button
    %   Row 5:  Distance button
    %   Row 6:  Angle button
    %   Row 7:  Polyline button
    %   Row 8:  Clear All button
    %   Row 9:  Tilt correction checkbox + tilt angle spinner
    %   Row 10: Tilt geometry dropdown (Cross-section / Surface)
    %   Rows 11-19: export table, ROI/bar/d-spacing/inversion/stats/etc.
    % Note: adding row 10 (geometry dropdown) shifted every widget after
    % the old row 9 down by one.
    measureInnerGL = uigridlayout(pnlMeasure, [20 2], ...
        'RowHeight',   {18, 20, 22, 20, 20, 20, 20, 20, 22, 22, 20, 20, 20, 20, 20, 20, 2, 20, 20, 20}, ...
        'ColumnWidth', {'1x', '1x'}, ...
        'Padding',     [3 2 3 2], ...
        'RowSpacing',  2, ...
        'ColumnSpacing', 3);

    cbScaleBar = uicheckbox(measureInnerGL, ...
        'Text',    'Scale Bar', ...
        'Value',   false, ...
        'Enable',  'off', ...
        'ValueChangedFcn', @onScaleBarToggle, ...
        'Tooltip', 'Overlay a draggable scale bar (requires pixel size calibration)');
    cbScaleBar.Layout.Row = 1; cbScaleBar.Layout.Column = [1 2];

    % Scale bar options row: color toggle + font size
    btnScaleBarColor = uibutton(measureInnerGL, 'Text', 'White', ...
        'ButtonPushedFcn', @onScaleBarColorToggle, ...
        'BackgroundColor', [0.25 0.25 0.25], ...
        'FontColor',       [1 1 1], ...
        'Enable',          'off', ...
        'Tooltip',         'Toggle scale bar colour between white and black');
    btnScaleBarColor.Layout.Row = 2; btnScaleBarColor.Layout.Column = 1;

    spnScaleBarFont = uispinner(measureInnerGL, ...
        'Value', 30, 'Limits', [6 72], 'Step', 1, ...
        'ValueChangedFcn', @onScaleBarFontChange, ...
        'Enable', 'off', ...
        'Tooltip', 'Scale bar label font size (pt)');
    spnScaleBarFont.Layout.Row = 2; spnScaleBarFont.Layout.Column = 2;

    % Row 3: explicit length + unit (0 = auto)
    efScaleBarLen = uieditfield(measureInnerGL, 'numeric', ...
        'Value', 0, 'Limits', [0 Inf], ...
        'ValueDisplayFormat', '%g', ...
        'Placeholder', 'auto', ...
        'Enable', 'off', ...
        'ValueChangedFcn', @onScaleBarFontChange, ...
        'Tooltip', 'Override scale bar length (0 = auto-pick a nice round value)');
    efScaleBarLen.Layout.Row = 3; efScaleBarLen.Layout.Column = 1;

    ddScaleBarUnit = uidropdown(measureInnerGL, ...
        'Items', {'auto', 'nm', 'μm', 'Å', 'mm', 'pm'}, ...
        'ItemsData', {'auto', 'nm', 'um', 'A', 'mm', 'pm'}, ...
        'Value', 'auto', ...
        'Enable', 'off', ...
        'ValueChangedFcn', @onScaleBarFontChange, ...
        'Tooltip', 'Unit for the length override; "auto" uses the image calibration unit');
    ddScaleBarUnit.Layout.Row = 3; ddScaleBarUnit.Layout.Column = 2;

    btnLineProfile = uibutton(measureInnerGL, 'Text', 'Line Profile', ...
        'ButtonPushedFcn', @onLineProfile, ...
        'BackgroundColor', BTN_TOOL, ...
        'FontColor',       BTN_FG, ...
        'Enable',          'off', ...
        'Tooltip',         'Click two points to extract an intensity profile (Esc to cancel)');
    btnLineProfile.Layout.Row = 4; btnLineProfile.Layout.Column = [1 2];

    btnDistance = uibutton(measureInnerGL, 'Text', 'Distance', ...
        'ButtonPushedFcn', @onDistance, ...
        'BackgroundColor', BTN_TOOL, ...
        'FontColor',       BTN_FG, ...
        'Enable',          'off', ...
        'Tooltip',         'Click two points to measure distance (Esc to cancel)');
    btnDistance.Layout.Row = 5; btnDistance.Layout.Column = [1 2];

    btnExportProfile = uibutton(measureInnerGL, 'Text', 'Export CSV', ...
        'ButtonPushedFcn', @onExportProfile, ...
        'BackgroundColor', BTN_EXPORT, ...
        'FontColor',       BTN_FG, ...
        'Enable',          'off', ...
        'Tooltip',         'Save the last line profile to a CSV file');
    btnExportProfile.Layout.Row = 7; btnExportProfile.Layout.Column = [1 2];

    btnAngle = uibutton(measureInnerGL, 'Text', 'Angle', ...
        'ButtonPushedFcn', @onAngleMeasure, ...
        'BackgroundColor', BTN_TOOL, ...
        'FontColor',       BTN_FG, ...
        'Enable',          'off', ...
        'Tooltip',         'Click 3 points (vertex, ray1, ray2) to measure angle (Esc to cancel)');
    btnAngle.Layout.Row = 6; btnAngle.Layout.Column = 1;

    btnPolyline = uibutton(measureInnerGL, 'Text', 'Polyline', ...
        'ButtonPushedFcn', @onPolylineMeasure, ...
        'BackgroundColor', BTN_TOOL, ...
        'FontColor',       BTN_FG, ...
        'Enable',          'off', ...
        'Tooltip',         'Click points to measure total path length; double-click to finish (Esc to cancel)');
    btnPolyline.Layout.Row = 6; btnPolyline.Layout.Column = 2;

    btnClearOverlays = uibutton(measureInnerGL, 'Text', 'Clear All', ...
        'ButtonPushedFcn', @onClearOverlays, ...
        'BackgroundColor', BTN_DANGER, ...
        'FontColor',       BTN_FG, ...
        'Enable',          'off', ...
        'Tooltip',         'Remove all measurement overlays from the image');
    btnClearOverlays.Layout.Row = 8; btnClearOverlays.Layout.Column = [1 2];

    % Row 9: SEM/FIB tilt correction — auto-populated from image metadata
    % when present (FEI StageT / Bruker Tilt). When active, Distance, Line
    % Profile, Polyline, and Angle measurements are rescaled along the
    % foreshortened axis. The trig factor depends on the Geometry
    % dropdown on Row 10: 1/sin(θ) for cross-section (default), or
    % 1/cos(θ) for plan-view surface imaging.
    cbTiltCorrect = uicheckbox(measureInnerGL, ...
        'Text',            'Tilt corr.', ...
        'Value',           false, ...
        'Enable',          'off', ...
        'Tooltip',         ['Rescale the foreshortened axis of distance / ' ...
                            'profile / polyline / angle measurements to ' ...
                            'recover true sample-frame lengths. Factor ' ...
                            'depends on Geometry: 1/sin(θ) for cross-' ...
                            'section, 1/cos(θ) for plan-view surface. ' ...
                            'Auto-detected from SEM metadata.']);
    cbTiltCorrect.Layout.Row = 9; cbTiltCorrect.Layout.Column = 1;

    spnTiltAngle = uispinner(measureInnerGL, ...
        'Value',           0, ...
        'Limits',          [-89.9 89.9], ...
        'Step',            1, ...
        'ValueDisplayFormat', '%.1f°', ...
        'Enable',          'off', ...
        'Tooltip',         ['Stage tilt angle θ in degrees (override the ' ...
                            'metadata-detected value). Applied as 1/sin(θ) ' ...
                            'for cross-section geometry, 1/cos(θ) for ' ...
                            'surface geometry.']);
    spnTiltAngle.Layout.Row = 9; spnTiltAngle.Layout.Column = 2;

    % Row 10: Tilt geometry selector. Default = Cross-section (matches the
    % standard FIB cross-section workflow). Switch to Surface for plan-view
    % SEM of a stage-tilted top surface.
    ddTiltGeometry = uidropdown(measureInnerGL, ...
        'Items',           {'Cross-section', 'Surface'}, ...
        'ItemsData',       {'CrossSection', 'Surface'}, ...
        'Value',           'CrossSection', ...
        'Enable',          'off', ...
        'Tooltip',         ['Cross-section: FIB cross-section viewed at tilt ' ...
                            'θ — true depth recovered via 1/sin(θ). ' ...
                            'Surface: plan-view SEM of tilted top surface ' ...
                            '— true lateral length recovered via 1/cos(θ). ' ...
                            'See docs/theory/imaging.md for the derivation.']);
    ddTiltGeometry.Layout.Row = 10; ddTiltGeometry.Layout.Column = [1 2];

    % Row 11: Export Measurements / Diff Rings
    btnExportMeasure = uibutton(measureInnerGL, 'Text', 'Export Table', ...
        'ButtonPushedFcn', @onExportMeasurements, ...
        'BackgroundColor', BTN_EXPORT, ...
        'FontColor',       BTN_FG, ...
        'Enable',          'off', ...
        'Tooltip',         'Export all measurements (distances, angles, ROI stats) to CSV');
    btnExportMeasure.Layout.Row = 11; btnExportMeasure.Layout.Column = 1;

    btnDiffRings = uibutton(measureInnerGL, 'Text', 'Diff Rings...', ...
        'ButtonPushedFcn', @onDiffRings, ...
        'BackgroundColor', BTN_TOOL, ...
        'FontColor',       BTN_FG, ...
        'Enable',          'off', ...
        'Tooltip',         'Overlay calibrated diffraction rings (d-spacing)');
    btnDiffRings.Layout.Row = 11; btnDiffRings.Layout.Column = 2;

    % Row 12: ROI Manager
    btnROIManager = uibutton(measureInnerGL, 'Text', 'ROI Manager...', ...
        'ButtonPushedFcn', @onROIManager, ...
        'BackgroundColor', BTN_TOOL, ...
        'FontColor',       BTN_FG, ...
        'Enable',          'off', ...
        'Tooltip',         'Manage saved ROIs with properties table and CSV export');
    btnROIManager.Layout.Row = 12; btnROIManager.Layout.Column = [1 2];

    % Row 13: Calibrate from Scale Bar
    btnCalibrateBar = uibutton(measureInnerGL, 'Text', 'Calibrate Bar...', ...
        'ButtonPushedFcn', @onCalibrateBar, ...
        'BackgroundColor', BTN_TOOL, ...
        'FontColor',       BTN_FG, ...
        'Enable',          'off', ...
        'Tooltip', 'Draw along a scale bar in the image to calibrate pixel size; auto-detect available');
    btnCalibrateBar.Layout.Row = 13; btnCalibrateBar.Layout.Column = [1 2];

    % Row 14: d-Spacing measurement + Profile width spinner
    btnDSpacing = uibutton(measureInnerGL, 'Text', 'd-Spacing', ...
        'ButtonPushedFcn', @onDSpacing, ...
        'BackgroundColor', BTN_TOOL, ...
        'FontColor',       BTN_FG, ...
        'Enable',          'off', ...
        'Tooltip',         'Click FFT spots to measure d-spacing (requires calibration)');
    btnDSpacing.Layout.Row = 14; btnDSpacing.Layout.Column = 1;

    % Row 14 col 2: Profile width spinner
    spnProfileWidth = uispinner(measureInnerGL, ...
        'Value', 1, 'Limits', [1 50], 'Step', 2, ...
        'Enable', 'off', ...
        'Tooltip', 'Line profile averaging width (px) — 1 = single pixel');
    spnProfileWidth.Layout.Row = 14; spnProfileWidth.Layout.Column = 2;

    % Row 15: Ellipse ROI / Polygon ROI
    btnEllipseROI = uibutton(measureInnerGL, 'Text', 'Circle ROI', ...
        'ButtonPushedFcn', @onEllipseROI, ...
        'BackgroundColor', BTN_TOOL, ...
        'FontColor',       BTN_FG, ...
        'Enable',          'off', ...
        'Tooltip',         'Click center then edge to define a circular ROI; reports statistics');
    btnEllipseROI.Layout.Row = 15; btnEllipseROI.Layout.Column = 1;

    btnPolygonROI = uibutton(measureInnerGL, 'Text', 'Polygon ROI', ...
        'ButtonPushedFcn', @onPolygonROI, ...
        'BackgroundColor', BTN_TOOL, ...
        'FontColor',       BTN_FG, ...
        'Enable',          'off', ...
        'Tooltip',         'Click vertices to define polygon ROI; double-click to close');
    btnPolygonROI.Layout.Row = 15; btnPolygonROI.Layout.Column = 2;

    % Row 16: Image Inversion
    btnInvertImg = uibutton(measureInnerGL, 'Text', 'Invert Image', ...
        'ButtonPushedFcn', @onInvertImage, ...
        'BackgroundColor', BTN_TOOL, ...
        'FontColor',       BTN_FG, ...
        'Enable',          'off', ...
        'Tooltip',         'Invert pixel values: img = max - img (bright-field / dark-field)');
    btnInvertImg.Layout.Row = 16; btnInvertImg.Layout.Column = [1 2];

    % Row 17: separator
    % Row 18-19: Measurement Statistics / Batch Measurement / Export to BosonPlotter

    btnMeasStats = uibutton(measureInnerGL, 'Text', 'Meas Stats', ...
        'ButtonPushedFcn', @onMeasurementStats, ...
        'BackgroundColor', BTN_EXPORT, ...
        'FontColor', BTN_FG, ...
        'Enable', 'off', ...
        'Tooltip', 'Show statistics for all measurements (mean, std, histogram)');
    btnMeasStats.Layout.Row = 18; btnMeasStats.Layout.Column = 1;

    btnBatchMeas = uibutton(measureInnerGL, 'Text', 'Batch Meas', ...
        'ButtonPushedFcn', @onBatchMeasurement, ...
        'BackgroundColor', BTN_EXPORT, ...
        'FontColor', BTN_FG, ...
        'Enable', 'off', ...
        'Tooltip', 'Apply measurement template across all loaded images');
    btnBatchMeas.Layout.Row = 18; btnBatchMeas.Layout.Column = 2;

    btnExportToDP = uibutton(measureInnerGL, 'Text', 'Profile → BosonPlotter', ...
        'ButtonPushedFcn', @onExportProfileToDP, ...
        'BackgroundColor', BTN_EXPORT, ...
        'FontColor', BTN_FG, ...
        'Enable', 'off', ...
        'Tooltip', 'Send last line profile to BosonPlotter as standard data struct');
    btnExportToDP.Layout.Row = 19; btnExportToDP.Layout.Column = [1 2];

    lblMeasLabelFont = uilabel(measureInnerGL, 'Text', 'Label font:', ...
        'HorizontalAlignment', 'right', 'FontSize', 9);
    lblMeasLabelFont.Layout.Row = 20; lblMeasLabelFont.Layout.Column = 1;

    spnMeasLabelFont = uispinner(measureInnerGL, ...
        'Value', 13, 'Limits', [6 72], 'Step', 1, ...
        'FontSize', 9, ...
        'Tooltip', 'Font size for all distance measurement labels', ...
        'ValueChangedFcn', @(src,~) onMeasLabelFontChange(src.Value), ...
        'Enable', 'off');
    spnMeasLabelFont.Layout.Row = 20; spnMeasLabelFont.Layout.Column = 2;

    % ROI Manager state
    appData.roiList = {};   % cell array of ROI structs: {name, xMin, xMax, yMin, yMax, stats}

    % ── Section 4: Processing ────────────────────────────────────────────
    btnProcessHeader = uibutton(toolsGL, 'Text', [ARROW_SHUT ' Processing'], ...
        'HorizontalAlignment', 'left', ...
        'BackgroundColor', HDR_BG, 'FontColor', HDR_FG, ...
        'FontWeight', 'bold', 'FontSize', 11, ...
        'ButtonPushedFcn', @(~,~) toggleSection(SECT_PROCESS));
    btnProcessHeader.Layout.Row = 7;

    pnlProcess = uipanel(toolsGL, 'BorderType', 'line');
    pnlProcess.Layout.Row = 8;

    % Wrapper grid hosting a 5-tab uitabgroup. Tabs split 55 controls into
    % discoverable categories so the panel stays ~230 px tall regardless of
    % how many tools exist. Every button's variable name is preserved so
    % setToolsEnabled, callbacks, and the rest of the file are unaffected.
    processInnerGL = uigridlayout(pnlProcess, [1 1], ...
        'Padding', [2 2 2 2], ...
        'RowHeight', {'1x'}, 'ColumnWidth', {'1x'});

    processTabGroup = uitabgroup(processInnerGL);
    processTabGroup.Layout.Row = 1; processTabGroup.Layout.Column = 1;

    tabDef = struct( ...
        'RowHeight',   {repmat({22}, 1, 6)}, ...
        'ColumnWidth', {{'1x','1x'}}, ...
        'Padding',     [3 3 3 3], ...
        'RowSpacing',  3, ...
        'ColumnSpacing', 3);

    % ── Tab 1: Transform ─────────────────────────────────────────────────
    tabTransform = uitab(processTabGroup, 'Title', 'Transform');
    transformGL = uigridlayout(tabTransform, [6 2], ...
        'RowHeight', tabDef.RowHeight, 'ColumnWidth', tabDef.ColumnWidth, ...
        'Padding', tabDef.Padding, 'RowSpacing', tabDef.RowSpacing, ...
        'ColumnSpacing', tabDef.ColumnSpacing);

    btnRotCW = uibutton(transformGL, 'Text', 'Rot 90 CW', ...
        'ButtonPushedFcn', @(~,~) onRotateFlip('rot90cw'), ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, 'Enable', 'off', ...
        'Tooltip', 'Rotate image 90° clockwise');
    btnRotCW.Layout.Row = 1; btnRotCW.Layout.Column = 1;

    btnRotCCW = uibutton(transformGL, 'Text', 'Rot 90 CCW', ...
        'ButtonPushedFcn', @(~,~) onRotateFlip('rot90ccw'), ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, 'Enable', 'off', ...
        'Tooltip', 'Rotate image 90° counter-clockwise');
    btnRotCCW.Layout.Row = 1; btnRotCCW.Layout.Column = 2;

    btnFlipH = uibutton(transformGL, 'Text', 'Flip H', ...
        'ButtonPushedFcn', @(~,~) onRotateFlip('fliph'), ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, 'Enable', 'off', ...
        'Tooltip', 'Flip image horizontally (left-right mirror)');
    btnFlipH.Layout.Row = 2; btnFlipH.Layout.Column = 1;

    btnFlipV = uibutton(transformGL, 'Text', 'Flip V', ...
        'ButtonPushedFcn', @(~,~) onRotateFlip('flipv'), ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, 'Enable', 'off', ...
        'Tooltip', 'Flip image vertically (top-bottom mirror)');
    btnFlipV.Layout.Row = 2; btnFlipV.Layout.Column = 2;

    btnZoomBox = uibutton(transformGL, 'Text', 'Zoom Box', ...
        'ButtonPushedFcn', @onZoomBox, ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, 'Enable', 'off', ...
        'Tooltip', 'Draw a rectangle to zoom into a region (Esc to cancel)');
    btnZoomBox.Layout.Row = 3; btnZoomBox.Layout.Column = 1;

    btnResetZoom = uibutton(transformGL, 'Text', 'Reset Zoom', ...
        'ButtonPushedFcn', @onResetZoom, ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, 'Enable', 'off', ...
        'Tooltip', 'Reset zoom to show the full image');
    btnResetZoom.Layout.Row = 3; btnResetZoom.Layout.Column = 2;

    btnCropImage = uibutton(transformGL, 'Text', 'Crop', ...
        'ButtonPushedFcn', @onCropImage, ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, 'Enable', 'off', ...
        'Tooltip', 'Draw a rectangle to crop the image (destructive — use Undo Filters to revert)');
    btnCropImage.Layout.Row = 4; btnCropImage.Layout.Column = 1;

    btnSaveCrop = uibutton(transformGL, 'Text', 'Save Crop...', ...
        'ButtonPushedFcn', @onSaveCrop, ...
        'BackgroundColor', BTN_EXPORT, 'FontColor', BTN_FG, 'Enable', 'off', ...
        'Tooltip', 'Save a cropped region to file (draw box, then save)');
    btnSaveCrop.Layout.Row = 4; btnSaveCrop.Layout.Column = 2;

    btnBatchCrop = uibutton(transformGL, 'Text', 'Batch Crop', ...
        'ButtonPushedFcn', @onBatchCrop, ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, 'Enable', 'off', ...
        'Tooltip', 'Define crop region, apply to all loaded images');
    btnBatchCrop.Layout.Row = 5; btnBatchCrop.Layout.Column = 1;

    btnBinImage = uibutton(transformGL, 'Text', 'Bin Image...', ...
        'ButtonPushedFcn', @onBinImage, ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, 'Enable', 'off', ...
        'Tooltip', 'Spatial binning (2x2, 4x4, 8x8) — sum or average mode');
    btnBinImage.Layout.Row = 5; btnBinImage.Layout.Column = 2;

    btnSetPixelSize = uibutton(transformGL, 'Text', 'Set Pixel Size...', ...
        'ButtonPushedFcn', @onSetPixelSize, ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, 'Enable', 'off', ...
        'Tooltip', 'Manually set or override pixel size calibration (nm/px, µm/px, etc.)');
    btnSetPixelSize.Layout.Row = 6; btnSetPixelSize.Layout.Column = [1 2];

    % ── Tab 2: Filter ────────────────────────────────────────────────────
    tabFilter = uitab(processTabGroup, 'Title', 'Filter');
    filterGL = uigridlayout(tabFilter, [6 2], ...
        'RowHeight', tabDef.RowHeight, 'ColumnWidth', tabDef.ColumnWidth, ...
        'Padding', tabDef.Padding, 'RowSpacing', tabDef.RowSpacing, ...
        'ColumnSpacing', tabDef.ColumnSpacing);

    btnGaussian = uibutton(filterGL, 'Text', 'Gaussian...', ...
        'ButtonPushedFcn', @onGaussianFilter, ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, 'Enable', 'off', ...
        'Tooltip', 'Apply Gaussian blur — prompts for sigma value');
    btnGaussian.Layout.Row = 1; btnGaussian.Layout.Column = 1;

    btnMedian = uibutton(filterGL, 'Text', 'Median...', ...
        'ButtonPushedFcn', @onMedianFilter, ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, 'Enable', 'off', ...
        'Tooltip', 'Apply median filter — prompts for window size (3/5/7)');
    btnMedian.Layout.Row = 1; btnMedian.Layout.Column = 2;

    btnCLAHE = uibutton(filterGL, 'Text', 'CLAHE...', ...
        'ButtonPushedFcn', @onCLAHE, ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, 'Enable', 'off', ...
        'Tooltip', 'Contrast-Limited Adaptive Histogram Equalization — prompts for tile size and clip limit');
    btnCLAHE.Layout.Row = 2; btnCLAHE.Layout.Column = 1;

    btnSharpen = uibutton(filterGL, 'Text', 'Sharpen...', ...
        'ButtonPushedFcn', @onSharpen, ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, 'Enable', 'off', ...
        'Tooltip', 'Unsharp mask sharpening — prompts for sigma and amount');
    btnSharpen.Layout.Row = 2; btnSharpen.Layout.Column = 2;

    btnMorphOp = uibutton(filterGL, 'Text', 'Morph Op...', ...
        'ButtonPushedFcn', @onMorphOp, ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, 'Enable', 'off', ...
        'Tooltip', 'Morphological operations (erode/dilate/open/close) on binary images');
    btnMorphOp.Layout.Row = 3; btnMorphOp.Layout.Column = 1;

    btnButterworth = uibutton(filterGL, 'Text', 'Butterworth...', ...
        'ButtonPushedFcn', @onButterworth, ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, 'Enable', 'off', ...
        'Tooltip', 'Butterworth bandpass filter — smooth frequency-domain filtering');
    btnButterworth.Layout.Row = 3; btnButterworth.Layout.Column = 2;

    btnFFTMask = uibutton(filterGL, 'Text', 'FFT Mask...', ...
        'ButtonPushedFcn', @onFFTMask, ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, 'Enable', 'off', ...
        'Tooltip', 'Draw masks on FFT to remove periodic noise; apply inverse FFT');
    btnFFTMask.Layout.Row = 4; btnFFTMask.Layout.Column = 1;

    btnLiveThresh = uibutton(filterGL, 'Text', 'Threshold...', ...
        'ButtonPushedFcn', @onLiveThreshold, ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, 'Enable', 'off', ...
        'Tooltip', 'Interactive threshold preview with live overlay; Otsu auto-threshold');
    btnLiveThresh.Layout.Row = 4; btnLiveThresh.Layout.Column = 2;

    btnMultiOtsu = uibutton(filterGL, 'Text', 'Multi-Thresh...', ...
        'ButtonPushedFcn', @onMultiOtsu, ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, 'Enable', 'off', ...
        'Tooltip', 'N-class segmentation via multi-level Otsu threshold (2-5 classes)');
    btnMultiOtsu.Layout.Row = 5; btnMultiOtsu.Layout.Column = 1;

    btnUndoFilters = uibutton(filterGL, 'Text', 'Undo Filters', ...
        'ButtonPushedFcn', @onUndoFilters, ...
        'BackgroundColor', BTN_DANGER, 'FontColor', BTN_FG, 'Enable', 'off', ...
        'Tooltip', 'Revert to the original unfiltered image');
    btnUndoFilters.Layout.Row = 5; btnUndoFilters.Layout.Column = 2;

    cbPixelInspector = uicheckbox(filterGL, ...
        'Text', 'Pixel Inspector', 'Value', false, 'Enable', 'off', ...
        'ValueChangedFcn', @onPixelInspectorToggle, ...
        'Tooltip', 'Show NxN pixel neighborhood with intensity values near cursor');
    cbPixelInspector.Layout.Row = 6; cbPixelInspector.Layout.Column = [1 2];

    % ── Tab 3: FFT & Analysis ────────────────────────────────────────────
    tabAnalysis = uitab(processTabGroup, 'Title', 'FFT & Analysis');
    analysisGL = uigridlayout(tabAnalysis, [6 2], ...
        'RowHeight', tabDef.RowHeight, 'ColumnWidth', tabDef.ColumnWidth, ...
        'Padding', tabDef.Padding, 'RowSpacing', tabDef.RowSpacing, ...
        'ColumnSpacing', tabDef.ColumnSpacing);

    btnShowFFT = uibutton(analysisGL, 'Text', 'Show FFT', ...
        'ButtonPushedFcn', @onShowFFT, ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, 'Enable', 'off', ...
        'Tooltip', 'Display 2D FFT magnitude in a new figure window');
    btnShowFFT.Layout.Row = 1; btnShowFFT.Layout.Column = 1;

    btnLiveFFT = uibutton(analysisGL, 'state', 'Text', 'Live FFT', ...
        'ValueChangedFcn', @onLiveFFTToggle, ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, 'Enable', 'off', ...
        'Tooltip', 'Show persistent FFT panel that updates with filters');
    btnLiveFFT.Layout.Row = 1; btnLiveFFT.Layout.Column = 2;

    btnRadialProfile = uibutton(analysisGL, 'Text', 'Radial Profile', ...
        'ButtonPushedFcn', @onRadialProfile, ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, 'Enable', 'off', ...
        'Tooltip', 'Compute radial average/max profile from FFT or diffraction pattern');
    btnRadialProfile.Layout.Row = 2; btnRadialProfile.Layout.Column = 1;

    btnAzIntegrate = uibutton(analysisGL, 'Text', 'Az Integrate', ...
        'ButtonPushedFcn', @onAzIntegrate, ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, 'Enable', 'off', ...
        'Tooltip', 'Full azimuthal integration of 2D pattern → 1D powder pattern');
    btnAzIntegrate.Layout.Row = 2; btnAzIntegrate.Layout.Column = 2;

    btnLatticeMeasure = uibutton(analysisGL, 'Text', 'Lattice...', ...
        'ButtonPushedFcn', @onLatticeMeasure, ...
        'BackgroundColor', [0.20 0.50 0.35], 'FontColor', BTN_FG, 'Enable', 'off', ...
        'Tooltip', ['Click two FFT spots to measure lattice parameters. ' ...
                    'Reports a, b, ' char(947) ', d-spacings, and overlays unit cell.']);
    btnLatticeMeasure.Layout.Row = 3; btnLatticeMeasure.Layout.Column = 1;

    btnGPA = uibutton(analysisGL, 'Text', 'GPA Strain...', ...
        'ButtonPushedFcn', @onGPA, ...
        'BackgroundColor', [0.20 0.50 0.35], 'FontColor', BTN_FG, 'Enable', 'off', ...
        'Tooltip', 'Geometric Phase Analysis: compute 2D strain maps from HRTEM lattice images');
    btnGPA.Layout.Row = 3; btnGPA.Layout.Column = 2;

    btnCTF = uibutton(analysisGL, 'Text', 'CTF Estimate...', ...
        'ButtonPushedFcn', @onCTFEstimate, ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, 'Enable', 'off', ...
        'Tooltip', 'Estimate defocus from Thon rings in the power spectrum (TEM/cryo-EM)');
    btnCTF.Layout.Row = 4; btnCTF.Layout.Column = 1;

    btnNoiseEstimate = uibutton(analysisGL, 'Text', 'Noise Est.', ...
        'ButtonPushedFcn', @onNoiseEstimate, ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, 'Enable', 'off', ...
        'Tooltip', 'Characterize image noise and suggest optimal filter parameters');
    btnNoiseEstimate.Layout.Row = 4; btnNoiseEstimate.Layout.Column = 2;

    btnTemplateMatch = uibutton(analysisGL, 'Text', 'Template Match', ...
        'ButtonPushedFcn', @onTemplateMatch, ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, 'Enable', 'off', ...
        'Tooltip', 'Find repeated features by selecting a template region');
    btnTemplateMatch.Layout.Row = 5; btnTemplateMatch.Layout.Column = 1;

    btnROIStats = uibutton(analysisGL, 'Text', 'ROI Stats', ...
        'ButtonPushedFcn', @onROIStats, ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, 'Enable', 'off', ...
        'Tooltip', 'Draw a rectangle to compute region statistics (mean, std, min, max)');
    btnROIStats.Layout.Row = 5; btnROIStats.Layout.Column = 2;

    btnInterfaceFit = uibutton(analysisGL, 'Text', 'Interface Fit', ...
        'ButtonPushedFcn', @onInterfaceFit, ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, 'Enable', 'off', ...
        'Tooltip', 'Fit erf/sigmoid to a line profile for interface width measurement (10-90%)');
    btnInterfaceFit.Layout.Row = 6; btnInterfaceFit.Layout.Column = 1;

    btnDefectCount = uibutton(analysisGL, 'Text', 'Defect Count...', ...
        'ButtonPushedFcn', @onDefectCount, ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, 'Enable', 'off', ...
        'Tooltip', 'Estimate dislocation density via stereological line intersection counting');
    btnDefectCount.Layout.Row = 6; btnDefectCount.Layout.Column = 2;

    % ── Tab 4: Surface & Stack ───────────────────────────────────────────
    tabSurface = uitab(processTabGroup, 'Title', 'Surface & Stack');
    surfaceGL = uigridlayout(tabSurface, [6 2], ...
        'RowHeight', tabDef.RowHeight, 'ColumnWidth', tabDef.ColumnWidth, ...
        'Padding', tabDef.Padding, 'RowSpacing', tabDef.RowSpacing, ...
        'ColumnSpacing', tabDef.ColumnSpacing);

    btnPlaneLevel = uibutton(surfaceGL, 'Text', 'Plane Level...', ...
        'ButtonPushedFcn', @onPlaneLevel, ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, 'Enable', 'off', ...
        'Tooltip', 'Subtract a best-fit polynomial surface (1st/2nd/3rd order) for AFM/SPM leveling');
    btnPlaneLevel.Layout.Row = 1; btnPlaneLevel.Layout.Column = 1;

    btnRoughness = uibutton(surfaceGL, 'Text', 'Roughness...', ...
        'ButtonPushedFcn', @onRoughness, ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, 'Enable', 'off', ...
        'Tooltip', 'Compute surface roughness: Ra, Rq, Rz, skewness, kurtosis, bearing ratio');
    btnRoughness.Layout.Row = 1; btnRoughness.Layout.Column = 2;

    btn3DSurface = uibutton(surfaceGL, 'Text', '3D Surface', ...
        'ButtonPushedFcn', @on3DSurface, ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, 'Enable', 'off', ...
        'Tooltip', 'Render image as 3D height map (AFM/STM/topography)');
    btn3DSurface.Layout.Row = 2; btn3DSurface.Layout.Column = 1;

    btnSurfacePlot = uibutton(surfaceGL, 'Text', 'Surface Plot', ...
        'ButtonPushedFcn', @onSurfacePlot, ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, 'Enable', 'off', ...
        'Tooltip', 'Render image intensity as a 3D surface plot in a new figure');
    btnSurfacePlot.Layout.Row = 2; btnSurfacePlot.Layout.Column = 2;

    btnBackProject = uibutton(surfaceGL, 'Text', 'Back-Project...', ...
        'ButtonPushedFcn', @onBackProject, ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, 'Enable', 'off', ...
        'Tooltip', 'Filtered back-projection preview from a tilt-series sinogram');
    btnBackProject.Layout.Row = 3; btnBackProject.Layout.Column = 1;

    btnParticles = uibutton(surfaceGL, 'Text', 'Particles...', ...
        'ButtonPushedFcn', @onParticleCount, ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, 'Enable', 'off', ...
        'Tooltip', 'Threshold + count particles; show size distribution');
    btnParticles.Layout.Row = 3; btnParticles.Layout.Column = 2;

    btnWatershed = uibutton(surfaceGL, 'Text', 'Watershed...', ...
        'ButtonPushedFcn', @onWatershed, ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, 'Enable', 'off', ...
        'Tooltip', 'Watershed segmentation to split touching particles (no toolbox)');
    btnWatershed.Layout.Row = 4; btnWatershed.Layout.Column = 1;

    btnAlignStack = uibutton(surfaceGL, 'Text', 'Align Stack', ...
        'ButtonPushedFcn', @onAlignStack, ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, 'Enable', 'off', ...
        'Tooltip', 'Cross-correlation drift correction for loaded image stack');
    btnAlignStack.Layout.Row = 4; btnAlignStack.Layout.Column = 2;

    btnStitchImages = uibutton(surfaceGL, 'Text', 'Stitch...', ...
        'ButtonPushedFcn', @onStitchImages, ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, 'Enable', 'off', ...
        'Tooltip', 'Stitch overlapping images into a panoramic mosaic');
    btnStitchImages.Layout.Row = 5; btnStitchImages.Layout.Column = 1;

    btnMontage = uibutton(surfaceGL, 'Text', 'Montage / Stitch...', ...
        'ButtonPushedFcn', @onMontage, ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, 'Enable', 'off', ...
        'Tooltip', 'Grid-based tiled image stitching with overlap cross-correlation');
    btnMontage.Layout.Row = 5; btnMontage.Layout.Column = 2;

    % Per-tab grids exposed for theming (see setTheme)
    processTabGrids = {transformGL, filterGL, analysisGL, surfaceGL};

    hPixelInspector = [];   % handle to pixel inspector axes overlay

    % ── Section 5: Annotations ──────────────────────────────────────────
    btnAnnotHeader = uibutton(toolsGL, 'Text', [ARROW_SHUT ' Annotations'], ...
        'HorizontalAlignment', 'left', ...
        'BackgroundColor', HDR_BG, 'FontColor', HDR_FG, ...
        'FontWeight', 'bold', 'FontSize', 11, ...
        'ButtonPushedFcn', @(~,~) toggleSection(SECT_ANNOT));
    btnAnnotHeader.Layout.Row = 9;

    pnlAnnot = uipanel(toolsGL, 'BorderType', 'line');
    pnlAnnot.Layout.Row = 10;

    annotInnerGL = uigridlayout(pnlAnnot, [6 2], ...
        'RowHeight',   {20, 20, 20, 20, 20, 20}, ...
        'ColumnWidth', {'1x', '1x'}, ...
        'Padding',     [3 2 3 2], ...
        'RowSpacing',  2, ...
        'ColumnSpacing', 3);

    % Row 1: Text input field (spans both columns)
    efAnnotText = uieditfield(annotInnerGL, 'text', ...
        'Value', 'Label', ...
        'Tooltip', 'Text to place on the image');
    efAnnotText.Layout.Row = 1; efAnnotText.Layout.Column = [1 2];

    % Row 2: Font size spinner + Colour dropdown
    spnAnnotFont = uispinner(annotInnerGL, ...
        'Value', 18, 'Limits', [6 72], 'Step', 1, ...
        'Tooltip', 'Font size for annotation text');
    spnAnnotFont.Layout.Row = 2; spnAnnotFont.Layout.Column = 1;

    % Annotation colour — converted from click-to-cycle button to uidropdown
    % (proper discrete-choice UX when >= 3 options). Each item is prefixed
    % with a Unicode filled square (U+25A0) as a visual swatch; the dropdown
    % FontColor is also updated on change so the displayed value is rendered
    % in the selected colour — closest native analogue to a colour picker
    % without HTML interpreter hacks or an external colour-chooser toolbox.
    sq = char(9632);   % ■ Unicode filled square
    ddAnnotColor = uidropdown(annotInnerGL, ...
        'Items',     {[sq ' White'], [sq ' Cyan'], [sq ' Yellow'], ...
                      [sq ' Red'],   [sq ' Black']}, ...
        'ItemsData', {'White', 'Cyan', 'Yellow', 'Red', 'Black'}, ...
        'Value',           'White', ...
        'ValueChangedFcn', @onAnnotColorChange, ...
        'BackgroundColor', [0.25 0.25 0.25], ...
        'FontColor',       [1 1 1], ...
        'Enable',  'off', ...
        'Tooltip', 'Text colour: White / Cyan / Yellow / Red / Black');
    ddAnnotColor.Layout.Row = 2; ddAnnotColor.Layout.Column = 2;

    % Row 3: Place Text button
    btnPlaceAnnot = uibutton(annotInnerGL, 'Text', 'Place Text', ...
        'ButtonPushedFcn', @onPlaceAnnotation, ...
        'BackgroundColor', BTN_TOOL, ...
        'FontColor', BTN_FG, ...
        'Enable', 'off', ...
        'Tooltip', 'Click on image to place text annotation (Esc to cancel)');
    btnPlaceAnnot.Layout.Row = 3; btnPlaceAnnot.Layout.Column = [1 2];

    % Row 4: Clear Annotations button
    btnClearAnnot = uibutton(annotInnerGL, 'Text', 'Clear Text', ...
        'ButtonPushedFcn', @onClearAnnotations, ...
        'BackgroundColor', BTN_DANGER, ...
        'FontColor', BTN_FG, ...
        'Enable', 'off', ...
        'Tooltip', 'Remove all text annotations from the image');
    btnClearAnnot.Layout.Row = 4; btnClearAnnot.Layout.Column = [1 2];

    % Row 5: Arrow / Line shape annotations
    btnPlaceArrow = uibutton(annotInnerGL, 'Text', 'Arrow', ...
        'ButtonPushedFcn', @onPlaceArrow, ...
        'BackgroundColor', BTN_TOOL, ...
        'FontColor', BTN_FG, ...
        'Enable', 'off', ...
        'Tooltip', 'Click start → end to draw an arrow annotation');
    btnPlaceArrow.Layout.Row = 5; btnPlaceArrow.Layout.Column = 1;

    btnPlaceLine = uibutton(annotInnerGL, 'Text', 'Line', ...
        'ButtonPushedFcn', @onPlaceLine, ...
        'BackgroundColor', BTN_TOOL, ...
        'FontColor', BTN_FG, ...
        'Enable', 'off', ...
        'Tooltip', 'Click two points to draw a line annotation');
    btnPlaceLine.Layout.Row = 5; btnPlaceLine.Layout.Column = 2;

    % Row 6: Rect / Circle shape + line width
    btnPlaceRect = uibutton(annotInnerGL, 'Text', 'Rect', ...
        'ButtonPushedFcn', @onPlaceRect, ...
        'BackgroundColor', BTN_TOOL, ...
        'FontColor', BTN_FG, ...
        'Enable', 'off', ...
        'Tooltip', 'Click two corners to draw a rectangle annotation');
    btnPlaceRect.Layout.Row = 6; btnPlaceRect.Layout.Column = 1;

    btnPlaceCircle = uibutton(annotInnerGL, 'Text', 'Circle', ...
        'ButtonPushedFcn', @onPlaceCircle, ...
        'BackgroundColor', BTN_TOOL, ...
        'FontColor', BTN_FG, ...
        'Enable', 'off', ...
        'Tooltip', 'Click center then edge to draw a circle annotation');
    btnPlaceCircle.Layout.Row = 6; btnPlaceCircle.Layout.Column = 2;

    % ── Section 6: EDS Channels ──────────────────────────────────────────
    btnEDSHeader = uibutton(toolsGL, 'Text', [ARROW_SHUT ' EDS Channels'], ...
        'HorizontalAlignment', 'left', ...
        'BackgroundColor', HDR_BG, 'FontColor', HDR_FG, ...
        'FontWeight', 'bold', 'FontSize', 11, ...
        'ButtonPushedFcn', @(~,~) toggleSection(SECT_EDS));
    btnEDSHeader.Layout.Row = 11;

    pnlEDS = uipanel(toolsGL, 'BorderType', 'line');
    pnlEDS.Layout.Row = 12;

    edsInnerGL = uigridlayout(pnlEDS, [14 2], ...
        'RowHeight', {28, 28, 100, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28}, ...
        'ColumnWidth', {'1x', '1x'}, ...
        'Padding', [4 4 4 4], ...
        'RowSpacing', 3);

    btnEnterEDS = uibutton(edsInnerGL, 'Text', 'Enter EDS Mode', ...
        'ButtonPushedFcn', @onEnterEDS, ...
        'BackgroundColor', BTN_PRIMARY, ...
        'FontColor', BTN_FG, ...
        'FontWeight', 'bold', ...
        'Enable', 'off', ...
        'Tooltip', 'Enter multi-channel EDS false-color composite mode');
    btnEnterEDS.Layout.Row = 1; btnEnterEDS.Layout.Column = [1 2];

    btnAddChannel = uibutton(edsInnerGL, 'Text', 'Add Channel', ...
        'ButtonPushedFcn', @onAddEDSChannel, ...
        'BackgroundColor', BTN_TOOL, ...
        'FontColor', BTN_FG, ...
        'Enable', 'off', ...
        'Tooltip', 'Add active image as an EDS channel');
    btnAddChannel.Layout.Row = 2; btnAddChannel.Layout.Column = 1;

    btnRemoveChannel = uibutton(edsInnerGL, 'Text', 'Remove', ...
        'ButtonPushedFcn', @onRemoveEDSChannel, ...
        'BackgroundColor', BTN_DANGER, ...
        'FontColor', BTN_FG, ...
        'Enable', 'off', ...
        'Tooltip', 'Remove selected channel from composite');
    btnRemoveChannel.Layout.Row = 2; btnRemoveChannel.Layout.Column = 2;

    lbEDSChannels = uilistbox(edsInnerGL, ...
        'Items', {'(no channels)'}, ...
        'ItemsData', 0, ...
        'ValueChangedFcn', @onEDSChannelSelected, ...
        'FontSize', 10);
    lbEDSChannels.Layout.Row = 3; lbEDSChannels.Layout.Column = [1 2];

    EDS_COLORS = {'red', 'green', 'blue', 'cyan', 'magenta', 'yellow', 'white'};

    lblEDSColor = uilabel(edsInnerGL, 'Text', 'Color:', ...
        'FontSize', 10, 'HorizontalAlignment', 'right');
    lblEDSColor.Layout.Row = 4; lblEDSColor.Layout.Column = 1;

    ddChannelColor = uidropdown(edsInnerGL, ...
        'Items', EDS_COLORS, ...
        'Value', 'red', ...
        'ValueChangedFcn', @onChannelColorChanged, ...
        'Enable', 'off', ...
        'Tooltip', 'Pseudo-color for this channel');
    ddChannelColor.Layout.Row = 4; ddChannelColor.Layout.Column = 2;

    cbChannelVisible = uicheckbox(edsInnerGL, ...
        'Text', 'Visible', ...
        'Value', true, ...
        'ValueChangedFcn', @onChannelVisibilityChanged, ...
        'Enable', 'off');
    cbChannelVisible.Layout.Row = 5; cbChannelVisible.Layout.Column = 1;

    lblEDSIntensity = uilabel(edsInnerGL, 'Text', 'Int: 1.00', ...
        'FontSize', 10, 'HorizontalAlignment', 'center');
    lblEDSIntensity.Layout.Row = 5; lblEDSIntensity.Layout.Column = 2;

    sldChannelIntensity = uislider(edsInnerGL, ...
        'Limits', [0 1], ...
        'Value', 1, ...
        'ValueChangedFcn', @onChannelIntensityChanged, ...
        'Enable', 'off');
    sldChannelIntensity.Layout.Row = 6; sldChannelIntensity.Layout.Column = [1 2];

    efChannelLabel = uieditfield(edsInnerGL, 'text', ...
        'Value', '', ...
        'ValueChangedFcn', @onChannelLabelChanged, ...
        'Enable', 'off', ...
        'Placeholder', 'Channel label');
    efChannelLabel.Layout.Row = 7; efChannelLabel.Layout.Column = [1 2];

    btnExportComposite = uibutton(edsInnerGL, 'Text', 'Export RGB...', ...
        'ButtonPushedFcn', @onExportEDSComposite, ...
        'BackgroundColor', BTN_EXPORT, ...
        'FontColor', BTN_FG, ...
        'Enable', 'off', ...
        'Tooltip', 'Save the blended RGB composite to PNG/TIFF');
    btnExportComposite.Layout.Row = 8; btnExportComposite.Layout.Column = [1 2];

    % EDS Quantification controls (rows 9-12)
    btnAssignElements = uibutton(edsInnerGL, 'Text', 'Assign Elements', ...
        'ButtonPushedFcn', @onAssignElements, ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, ...
        'Enable', 'off', ...
        'Tooltip', 'Assign element symbols to EDS channels');
    btnAssignElements.Layout.Row = 9; btnAssignElements.Layout.Column = [1 2];

    btnQuantifyCL = uibutton(edsInnerGL, 'Text', 'Quantify (Cliff-Lorimer)', ...
        'ButtonPushedFcn', @onQuantifyCL, ...
        'BackgroundColor', BTN_PRIMARY, 'FontColor', BTN_FG, ...
        'FontWeight', 'bold', ...
        'Enable', 'off', ...
        'Tooltip', 'Compute atomic% and weight% maps using Cliff-Lorimer method');
    btnQuantifyCL.Layout.Row = 10; btnQuantifyCL.Layout.Column = [1 2];

    btnCompositionProfile = uibutton(edsInnerGL, 'Text', 'Composition Profile', ...
        'ButtonPushedFcn', @onCompositionProfile, ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, ...
        'Enable', 'off', ...
        'Tooltip', 'Click two points for a line composition profile');
    btnCompositionProfile.Layout.Row = 11; btnCompositionProfile.Layout.Column = [1 2];

    btnROIComposition = uibutton(edsInnerGL, 'Text', 'ROI Composition', ...
        'ButtonPushedFcn', @onROIComposition, ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, ...
        'Enable', 'off', ...
        'Tooltip', 'Click two corners for mean composition in ROI');
    btnROIComposition.Layout.Row = 12; btnROIComposition.Layout.Column = [1 2];

    % Row 13: Thickness + Take-off angle for ZAF
    edtEDSThickness = uieditfield(edsInnerGL, 'text', ...
        'Value', '100', 'Placeholder', 't (nm)');
    edtEDSThickness.Layout.Row = 13; edtEDSThickness.Layout.Column = 1;

    edtEDSTakeOff = uieditfield(edsInnerGL, 'text', ...
        'Value', '20', 'Placeholder', 'angle (deg)');
    edtEDSTakeOff.Layout.Row = 13; edtEDSTakeOff.Layout.Column = 2;

    % Row 14: Quantify ZAF button
    btnQuantifyZAF = uibutton(edsInnerGL, 'Text', 'Quantify ZAF', ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, ...
        'Tooltip', 'ZAF-corrected quantification (thick specimens)', ...
        'Enable', 'off', ...
        'ButtonPushedFcn', @(~,~) onQuantifyZAF());
    btnQuantifyZAF.Layout.Row = 14; btnQuantifyZAF.Layout.Column = [1 2];

    % ── Section 7: Metadata (moved here from rows 19-20) ────────────────
    btnMetaHeader = uibutton(toolsGL, 'Text', [ARROW_SHUT ' Metadata'], ...
        'HorizontalAlignment', 'left', ...
        'BackgroundColor', HDR_BG, 'FontColor', HDR_FG, ...
        'FontWeight', 'bold', 'FontSize', 11, ...
        'ButtonPushedFcn', @(~,~) toggleSection(SECT_META));
    btnMetaHeader.Layout.Row = 13;

    pnlMeta = uipanel(toolsGL, 'BorderType', 'none');
    pnlMeta.Layout.Row = 14;
    metaInnerGL = uigridlayout(pnlMeta, [2 1], ...
        'RowHeight', {'1x', 28}, 'Padding', 0, 'RowSpacing', 2);
    taMetadata = uitextarea(metaInnerGL, ...
        'Value', {'(no image loaded)'}, ...
        'Editable', 'off', ...
        'FontName', 'Courier New', ...
        'FontSize', 10);
    btnEditMetadata = uibutton(metaInnerGL, 'Text', 'Edit Metadata...', ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, ...
        'Tooltip', 'Override image metadata (sample name, pixel size, etc.)', ...
        'ButtonPushedFcn', @(~,~) onEditMetadata());

    % ── Section 8: EELS Spectrum ──────────────────────────────────────────
    btnEELSHeader = uibutton(toolsGL, 'Text', [ARROW_SHUT ' EELS Spectrum'], ...
        'HorizontalAlignment', 'left', ...
        'BackgroundColor', HDR_BG, 'FontColor', HDR_FG, ...
        'FontWeight', 'bold', 'FontSize', 11, ...
        'ButtonPushedFcn', @(~,~) toggleSection(SECT_EELS));
    btnEELSHeader.Layout.Row = 15;

    pnlEELS = uipanel(toolsGL, 'BorderType', 'line');
    pnlEELS.Layout.Row = 16;

    eelsInnerGL = uigridlayout(pnlEELS, [12 2], ...
        'RowHeight', {28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28}, ...
        'ColumnWidth', {'1x', '1x'}, ...
        'Padding', [4 4 4 4], ...
        'RowSpacing', 3);

    btnEnterEELS = uibutton(eelsInnerGL, 'Text', 'Enter EELS', ...
        'ButtonPushedFcn', @onEnterEELS, ...
        'BackgroundColor', BTN_PRIMARY, ...
        'FontColor', BTN_FG, ...
        'FontWeight', 'bold', ...
        'Enable', 'off', ...
        'Tooltip', 'Enter EELS spectrum analysis mode');
    btnEnterEELS.Layout.Row = 1; btnEnterEELS.Layout.Column = [1 2];

    lblEELSPreEdge = uilabel(eelsInnerGL, 'Text', 'Pre-edge Window:', ...
        'FontSize', 10, 'HorizontalAlignment', 'left');
    lblEELSPreEdge.Layout.Row = 2; lblEELSPreEdge.Layout.Column = 1;

    eelsPreEdgeGL = uigridlayout(eelsInnerGL, [1 2], ...
        'RowHeight', {'1x'}, 'ColumnWidth', {'1x','1x'}, ...
        'Padding', [0 0 0 0], 'RowSpacing', 0, 'ColumnSpacing', 2);
    eelsPreEdgeGL.Layout.Row = 2; eelsPreEdgeGL.Layout.Column = 2;

    edtEELSPreEdgeStart = uieditfield(eelsPreEdgeGL, 'text', ...
        'Value', '100', 'Placeholder', 'E1 eV', 'FontSize', 9);
    edtEELSPreEdgeStart.Layout.Row = 1; edtEELSPreEdgeStart.Layout.Column = 1;

    edtEELSPreEdgeEnd = uieditfield(eelsPreEdgeGL, 'text', ...
        'Value', '700', 'Placeholder', 'E2 eV', 'FontSize', 9);
    edtEELSPreEdgeEnd.Layout.Row = 1; edtEELSPreEdgeEnd.Layout.Column = 2;

    btnEELSFitBG = uibutton(eelsInnerGL, 'Text', 'Fit Background', ...
        'ButtonPushedFcn', @onEELSFitBackground, ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, ...
        'Enable', 'off', ...
        'Tooltip', 'Fit and subtract pre-edge background');
    btnEELSFitBG.Layout.Row = 3; btnEELSFitBG.Layout.Column = 1;

    ddEELSMethod = uidropdown(eelsInnerGL, ...
        'Items', {'powerlaw', 'exponential'}, ...
        'Value', 'powerlaw', ...
        'Enable', 'off', ...
        'Tooltip', 'Background fitting model');
    ddEELSMethod.Layout.Row = 3; ddEELSMethod.Layout.Column = 2;

    chkShowEdges = uicheckbox(eelsInnerGL, 'Text', 'Show Edges', ...
        'Value', false, ...
        'ValueChangedFcn', @onEELSShowEdges, ...
        'Enable', 'off');
    chkShowEdges.Layout.Row = 4; chkShowEdges.Layout.Column = 1;

    ddEdgeFilter = uidropdown(eelsInnerGL, ...
        'Items', {'All'}, ...
        'Value', 'All', ...
        'Enable', 'off', ...
        'Tooltip', 'Filter edges by element');
    ddEdgeFilter.Layout.Row = 4; ddEdgeFilter.Layout.Column = 2;

    lblEELSSigWin = uilabel(eelsInnerGL, 'Text', 'Signal Window:', ...
        'FontSize', 10, 'HorizontalAlignment', 'left');
    lblEELSSigWin.Layout.Row = 5; lblEELSSigWin.Layout.Column = 1;

    eelsSigWinGL = uigridlayout(eelsInnerGL, [1 2], ...
        'RowHeight', {'1x'}, 'ColumnWidth', {'1x','1x'}, ...
        'Padding', [0 0 0 0], 'RowSpacing', 0, 'ColumnSpacing', 2);
    eelsSigWinGL.Layout.Row = 5; eelsSigWinGL.Layout.Column = 2;

    edtEELSSignalStart = uieditfield(eelsSigWinGL, 'text', ...
        'Value', '700', 'Placeholder', 'E1 eV', 'FontSize', 9);
    edtEELSSignalStart.Layout.Row = 1; edtEELSSignalStart.Layout.Column = 1;

    edtEELSSignalEnd = uieditfield(eelsSigWinGL, 'text', ...
        'Value', '750', 'Placeholder', 'E2 eV', 'FontSize', 9);
    edtEELSSignalEnd.Layout.Row = 1; edtEELSSignalEnd.Layout.Column = 2;

    btnEELSExtractMap = uibutton(eelsInnerGL, 'Text', 'Extract Map', ...
        'ButtonPushedFcn', @onEELSExtractMap, ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, ...
        'Enable', 'off', ...
        'Tooltip', 'Extract EELS elemental map from spectrum image');
    btnEELSExtractMap.Layout.Row = 6; btnEELSExtractMap.Layout.Column = 1;

    btnEELSThickness = uibutton(eelsInnerGL, 'Text', 'Thickness Map', ...
        'ButtonPushedFcn', @onEELSThicknessMap, ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, ...
        'Enable', 'off', ...
        'Tooltip', 'Compute t/lambda thickness map from log-ratio');
    btnEELSThickness.Layout.Row = 6; btnEELSThickness.Layout.Column = 2;

    btnEELSAlignZLP = uibutton(eelsInnerGL, 'Text', 'Align ZLP', ...
        'ButtonPushedFcn', @onEELSAlignZLP, ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, ...
        'Enable', 'off', ...
        'Tooltip', 'Align zero-loss peak across spectrum image frames');
    btnEELSAlignZLP.Layout.Row = 7; btnEELSAlignZLP.Layout.Column = [1 2];

    % Row 8: Deconvolve (Fourier-Log)
    btnEELSDeconvolve = uibutton(eelsInnerGL, 'Text', 'Deconvolve', ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, ...
        'Tooltip', 'Fourier-log plural scattering removal', ...
        'Enable', 'off', ...
        'ButtonPushedFcn', @(~,~) onEELSDeconvolve());
    btnEELSDeconvolve.Layout.Row = 8; btnEELSDeconvolve.Layout.Column = [1 2];

    % Row 9: ELNES extraction
    btnEELSELNES = uibutton(eelsInnerGL, 'Text', 'ELNES', ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, ...
        'Tooltip', 'Extract near-edge fine structure', ...
        'Enable', 'off', ...
        'ButtonPushedFcn', @(~,~) onEELSExtractELNES());
    btnEELSELNES.Layout.Row = 9; btnEELSELNES.Layout.Column = 1;

    edtEELSEdgeOnset = uieditfield(eelsInnerGL, 'text', ...
        'Value', '708', 'Placeholder', 'Onset eV', ...
        'Tooltip', 'Edge onset energy for ELNES');
    edtEELSEdgeOnset.Layout.Row = 9; edtEELSEdgeOnset.Layout.Column = 2;

    % Row 10: Kramers-Kronig
    btnEELSKK = uibutton(eelsInnerGL, 'Text', 'Kramers-Kronig', ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, ...
        'Tooltip', 'Compute dielectric function from low-loss EELS', ...
        'Enable', 'off', ...
        'ButtonPushedFcn', @(~,~) onEELSKramersKronig());
    btnEELSKK.Layout.Row = 10; btnEELSKK.Layout.Column = [1 2];

    % Row 11: Navigate pixel (spectrum image)
    btnEELSNavigate = uibutton(eelsInnerGL, 'state', 'Text', 'Navigate Pixel', ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, ...
        'Tooltip', 'Click on image to show pixel spectrum', ...
        'Enable', 'off', ...
        'ValueChangedFcn', @(src,~) onEELSNavigateToggle(src));
    btnEELSNavigate.Layout.Row = 11; btnEELSNavigate.Layout.Column = [1 2];

    % Row 12: SVD / MSA decomposition
    btnEELSSVD = uibutton(eelsInnerGL, 'Text', 'SVD Decompose', ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, ...
        'Tooltip', 'Multivariate decomposition of spectrum image (eigenspectra + score maps)', ...
        'Enable', 'off', ...
        'ButtonPushedFcn', @(~,~) onEELSSVD());
    btnEELSSVD.Layout.Row = 12; btnEELSSVD.Layout.Column = [1 2];

    % ── Section 9: Diffraction Indexing ──────────────────────────────────
    btnDiffHeader = uibutton(toolsGL, 'Text', [ARROW_SHUT ' Diffraction'], ...
        'HorizontalAlignment', 'left', ...
        'BackgroundColor', HDR_BG, 'FontColor', HDR_FG, ...
        'FontWeight', 'bold', 'FontSize', 11, ...
        'ButtonPushedFcn', @(~,~) toggleSection(SECT_DIFF));
    btnDiffHeader.Layout.Row = 17;

    pnlDiff = uipanel(toolsGL, 'BorderType', 'line');
    pnlDiff.Layout.Row = 18;

    diffInnerGL = uigridlayout(pnlDiff, [9 2], ...
        'RowHeight', {28, 28, 28, 28, 28, 28, '1x', 28, 28}, ...
        'ColumnWidth', {'1x', '1x'}, ...
        'Padding', [4 4 4 4], ...
        'RowSpacing', 3);

    btnAutoDetectSpots = uibutton(diffInnerGL, 'Text', 'Auto-detect Spots', ...
        'ButtonPushedFcn', @onAutoDetectSpots, ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, ...
        'Enable', 'off', ...
        'Tooltip', 'Automatically find diffraction spots');
    btnAutoDetectSpots.Layout.Row = 1; btnAutoDetectSpots.Layout.Column = 1;

    btnClickDiffSpot = uibutton(diffInnerGL, 'Text', 'Click Spots', ...
        'ButtonPushedFcn', @onClickDiffSpot, ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, ...
        'Enable', 'off', ...
        'Tooltip', 'Click to manually mark diffraction spots');
    btnClickDiffSpot.Layout.Row = 1; btnClickDiffSpot.Layout.Column = 2;

    btnClearDiffSpots = uibutton(diffInnerGL, 'Text', 'Clear Spots', ...
        'ButtonPushedFcn', @onClearDiffSpots, ...
        'BackgroundColor', BTN_DANGER, 'FontColor', BTN_FG, ...
        'Enable', 'off', ...
        'Tooltip', 'Remove all diffraction spot markers');
    btnClearDiffSpots.Layout.Row = 2; btnClearDiffSpots.Layout.Column = 1;

    lblSpotCount = uilabel(diffInnerGL, 'Text', '0 spots', ...
        'FontSize', 10, 'HorizontalAlignment', 'center');
    lblSpotCount.Layout.Row = 2; lblSpotCount.Layout.Column = 2;

    lblCameraLen = uilabel(diffInnerGL, 'Text', 'Camera Length (mm):', ...
        'FontSize', 9, 'HorizontalAlignment', 'left');
    lblCameraLen.Layout.Row = 3; lblCameraLen.Layout.Column = 1;

    edtCameraLen = uieditfield(diffInnerGL, 'text', ...
        'Value', '', 'Placeholder', 'e.g. 200', 'FontSize', 9);
    edtCameraLen.Layout.Row = 3; edtCameraLen.Layout.Column = 2;

    lblAccVoltage = uilabel(diffInnerGL, 'Text', 'Voltage (kV):', ...
        'FontSize', 10, 'HorizontalAlignment', 'left');
    lblAccVoltage.Layout.Row = 4; lblAccVoltage.Layout.Column = 1;

    ddAccVoltage = uidropdown(diffInnerGL, ...
        'Items', {'80 kV', '100 kV', '120 kV', '200 kV', '300 kV'}, ...
        'Value', '200 kV', ...
        'Enable', 'off', ...
        'Tooltip', 'Electron accelerating voltage');
    ddAccVoltage.Layout.Row = 4; ddAccVoltage.Layout.Column = 2;

    btnMatchDiffraction = uibutton(diffInnerGL, 'Text', 'Match Phases', ...
        'ButtonPushedFcn', @onMatchDiffraction, ...
        'BackgroundColor', BTN_PRIMARY, 'FontColor', BTN_FG, ...
        'FontWeight', 'bold', ...
        'Enable', 'off', ...
        'Tooltip', 'Index diffraction pattern and match to crystal phases');
    btnMatchDiffraction.Layout.Row = 5; btnMatchDiffraction.Layout.Column = 1;

    btnOverlayDiffRings = uibutton(diffInnerGL, 'Text', 'Overlay Rings', ...
        'ButtonPushedFcn', @onOverlayDiffRings, ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, ...
        'Enable', 'off', ...
        'Tooltip', 'Overlay d-spacing rings for selected phase');
    btnOverlayDiffRings.Layout.Row = 5; btnOverlayDiffRings.Layout.Column = 2;

    lblZoneAxisLabel = uilabel(diffInnerGL, 'Text', 'Zone Axis:', ...
        'FontSize', 10, 'HorizontalAlignment', 'left');
    lblZoneAxisLabel.Layout.Row = 6; lblZoneAxisLabel.Layout.Column = 1;

    lblZoneAxis = uilabel(diffInnerGL, 'Text', '', ...
        'FontSize', 10, 'HorizontalAlignment', 'left', 'FontWeight', 'bold');
    lblZoneAxis.Layout.Row = 6; lblZoneAxis.Layout.Column = 2;

    lbxDiffResults = uilistbox(diffInnerGL, ...
        'Items', {}, ...
        'FontSize', 9);
    lbxDiffResults.Layout.Row = 7; lbxDiffResults.Layout.Column = [1 2];

    % Row 8: Zone axis + Simulate
    edtZoneAxis = uieditfield(diffInnerGL, 'text', ...
        'Value', '0 0 1', 'Placeholder', 'Zone axis [u v w]');
    edtZoneAxis.Layout.Row = 8; edtZoneAxis.Layout.Column = 1;

    btnSimDiffraction = uibutton(diffInnerGL, 'Text', 'Simulate', ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, ...
        'Tooltip', 'Kinematic diffraction simulation', ...
        'Enable', 'off', ...
        'ButtonPushedFcn', @(~,~) onSimulateDiffraction());
    btnSimDiffraction.Layout.Row = 8; btnSimDiffraction.Layout.Column = 2;

    % Row 9: Virtual Dark-Field
    btnVDF = uibutton(diffInnerGL, 'Text', 'Virtual Dark-Field', ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, ...
        'Tooltip', 'Select FFT spot for virtual dark-field image', ...
        'Enable', 'off', ...
        'ButtonPushedFcn', @(~,~) onVirtualDarkField());
    btnVDF.Layout.Row = 9; btnVDF.Layout.Column = [1 2];

    % ── Section 10: Export & Style (accent header, open by default) ─────
    EXPORT_HDR_BG = [0.78 0.86 0.95];   % accent blue (light theme default)
    EXPORT_HDR_FG = [0.10 0.10 0.10];
    btnExportHeader = uibutton(toolsGL, 'Text', [ARROW_OPEN ' Export & Style'], ...
        'HorizontalAlignment', 'left', ...
        'BackgroundColor', EXPORT_HDR_BG, 'FontColor', EXPORT_HDR_FG, ...
        'FontWeight', 'bold', 'FontSize', 11, ...
        'ButtonPushedFcn', @(~,~) toggleSection(SECT_EXPORT));
    btnExportHeader.Layout.Row = 19;

    pnlExport = uipanel(toolsGL, 'BorderType', 'line');
    pnlExport.Layout.Row = 20;

    exportInnerGL = uigridlayout(pnlExport, [14 2], ...
        'RowHeight',   {22, 22, 22, 22, 14, 22, 22, 22, 22, 14, 22, 22, 22, 22}, ...
        'ColumnWidth', {'1x', '1x'}, ...
        'Padding',     [3 2 3 2], ...
        'RowSpacing',  2, ...
        'ColumnSpacing', 3);

    % ---- Tier 1: Core Export (rows 1-4) ----
    % Row 1: Save / Copy
    btnSaveImage = uibutton(exportInnerGL, 'Text', 'Save Image', ...
        'ButtonPushedFcn', @onSaveImage, ...
        'BackgroundColor', BTN_EXPORT, 'FontColor', BTN_FG, 'Enable', 'off', ...
        'Tooltip', 'Save current processed image to PNG or TIFF');
    btnSaveImage.Layout.Row = 1; btnSaveImage.Layout.Column = 1;

    btnCopyClipboard = uibutton(exportInnerGL, 'Text', 'Copy', ...
        'ButtonPushedFcn', @onCopyClipboard, ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, 'Enable', 'off', ...
        'Tooltip', 'Copy current view to clipboard');
    btnCopyClipboard.Layout.Row = 1; btnCopyClipboard.Layout.Column = 2;

    % Row 2: Burn Overlays / Batch Export
    btnExportOverlays = uibutton(exportInnerGL, 'Text', 'Burn Overlays', ...
        'ButtonPushedFcn', @onExportWithOverlays, ...
        'BackgroundColor', BTN_EXPORT, 'FontColor', BTN_FG, 'Enable', 'off', ...
        'Tooltip', 'Save with overlays burned in (scale bar, annotations, measurements)');
    btnExportOverlays.Layout.Row = 2; btnExportOverlays.Layout.Column = 1;

    btnBatchExport = uibutton(exportInnerGL, 'Text', 'Batch Export', ...
        'ButtonPushedFcn', @onBatchExport, ...
        'BackgroundColor', BTN_EXPORT, 'FontColor', BTN_FG, 'Enable', 'off', ...
        'Tooltip', 'Export all loaded images with current contrast to a folder');
    btnBatchExport.Layout.Row = 2; btnBatchExport.Layout.Column = 2;

    % Row 3: Session Save / Load
    btnSessionSave = uibutton(exportInnerGL, 'Text', 'Save .mat', ...
        'ButtonPushedFcn', @onSessionSave, ...
        'BackgroundColor', BTN_EXPORT, 'FontColor', BTN_FG, 'Enable', 'off', ...
        'Tooltip', 'Save images, contrast, overlays, annotations to .mat session');
    btnSessionSave.Layout.Row = 3; btnSessionSave.Layout.Column = 1;

    btnSessionLoad = uibutton(exportInnerGL, 'Text', 'Load .mat', ...
        'ButtonPushedFcn', @onSessionLoad, ...
        'BackgroundColor', BTN_EXPORT, 'FontColor', BTN_FG, ...
        'Tooltip', 'Restore a previously saved session');
    btnSessionLoad.Layout.Row = 3; btnSessionLoad.Layout.Column = 2;

    % Row 4: DPI
    lblDPI = uilabel(exportInnerGL, 'Text', 'DPI:', 'FontSize', 10);
    lblDPI.Layout.Row = 4; lblDPI.Layout.Column = 1;
    ddExportDPI = uidropdown(exportInnerGL, ...
        'Items', {'72', '150', '300', '600'}, ...
        'ItemsData', [72, 150, 300, 600], ...
        'Value', 300, ...
        'Tooltip', 'DPI for overlay and clipboard exports');
    ddExportDPI.Layout.Row = 4; ddExportDPI.Layout.Column = 2;

    % ---- Tier 2: Publication (rows 5-9) ----
    % Row 5: Sub-header
    lblPubHeader = uilabel(exportInnerGL, 'Text', 'Publication', ...
        'FontWeight', 'bold', 'FontSize', 10, ...
        'FontColor', [0.35 0.35 0.35]);
    lblPubHeader.Layout.Row = 5; lblPubHeader.Layout.Column = [1 2];

    % Row 6: Figure Builder / Journal Export
    btnFigureBuilder = uibutton(exportInnerGL, 'Text', 'Figure Builder...', ...
        'ButtonPushedFcn', @onFigureBuilder, ...
        'BackgroundColor', BTN_EXPORT, 'FontColor', BTN_FG, 'Enable', 'off', ...
        'Tooltip', 'Build multi-panel publication figure with labels, scale bars, and uniform sizing');
    btnFigureBuilder.Layout.Row = 6; btnFigureBuilder.Layout.Column = 1;

    btnJournalExport = uibutton(exportInnerGL, 'Text', 'Journal Export...', ...
        'ButtonPushedFcn', @onJournalExport, ...
        'BackgroundColor', BTN_EXPORT, 'FontColor', BTN_FG, 'Enable', 'off', ...
        'Tooltip', 'Export with journal-specific presets (Nature, Science, ACS, Elsevier)');
    btnJournalExport.Layout.Row = 6; btnJournalExport.Layout.Column = 2;

    % Row 7: Pub Presets / Calib. Colorbar
    btnPubPresets = uibutton(exportInnerGL, 'Text', 'Pub Presets', ...
        'ButtonPushedFcn', @onPubPresets, ...
        'BackgroundColor', BTN_EXPORT, 'FontColor', BTN_FG, 'Enable', 'off', ...
        'Tooltip', 'Apply journal-specific annotation formatting (APS/Nature/ACS)');
    btnPubPresets.Layout.Row = 7; btnPubPresets.Layout.Column = 1;

    btnCalibColorbar = uibutton(exportInnerGL, 'Text', 'Calib. Colorbar', ...
        'ButtonPushedFcn', @onCalibratedColorbar, ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, 'Enable', 'off', ...
        'Tooltip', 'Add a calibrated colorbar with real-unit labels burned into exports');
    btnCalibColorbar.Layout.Row = 7; btnCalibColorbar.Layout.Column = 2;

    % Row 8: Custom Colormap / EM Colormaps
    btnCustomCmap = uibutton(exportInnerGL, 'Text', 'Custom Colormap...', ...
        'ButtonPushedFcn', @onCustomColormap, ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, 'Enable', 'off', ...
        'Tooltip', 'Create a custom colormap from user-defined color stops');
    btnCustomCmap.Layout.Row = 8; btnCustomCmap.Layout.Column = 1;

    btnColormapPreset = uibutton(exportInnerGL, 'Text', 'EM Colormaps', ...
        'ButtonPushedFcn', @onColormapPreset, ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, 'Enable', 'off', ...
        'Tooltip', 'Auto-select colormap based on EM mode (SEM/TEM/STEM/EDS/phase)');
    btnColormapPreset.Layout.Row = 8; btnColormapPreset.Layout.Column = 2;

    % Row 9: Create GIF / Batch Convert
    btnCreateGIF = uibutton(exportInnerGL, 'Text', 'Create GIF...', ...
        'ButtonPushedFcn', @onCreateGIF, ...
        'BackgroundColor', BTN_EXPORT, 'FontColor', BTN_FG, 'Enable', 'off', ...
        'Tooltip', 'Combine selected images into an animated GIF with optional scale bar');
    btnCreateGIF.Layout.Row = 9; btnCreateGIF.Layout.Column = 1;

    btnBatchConvert = uibutton(exportInnerGL, 'Text', 'Batch Convert', ...
        'ButtonPushedFcn', @onBatchConvert, ...
        'BackgroundColor', BTN_EXPORT, 'FontColor', BTN_FG, 'Enable', 'off', ...
        'Tooltip', 'Convert loaded images between formats (PNG/TIFF/JPEG)');
    btnBatchConvert.Layout.Row = 9; btnBatchConvert.Layout.Column = 2;

    % ---- Tier 3: Utilities (rows 10-14) ----
    % Row 10: Sub-header
    lblUtilHeader = uilabel(exportInnerGL, 'Text', 'Utilities', ...
        'FontWeight', 'bold', 'FontSize', 10, ...
        'FontColor', [0.35 0.35 0.35]);
    lblUtilHeader.Layout.Row = 10; lblUtilHeader.Layout.Column = [1 2];

    % Row 11: Overlay / Flicker
    btnColorOverlay = uibutton(exportInnerGL, 'Text', 'Overlay...', ...
        'ButtonPushedFcn', @onColorOverlay, ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, 'Enable', 'off', ...
        'Tooltip', 'Blend two images with different colormaps in a new figure');
    btnColorOverlay.Layout.Row = 11; btnColorOverlay.Layout.Column = 1;

    btnFlickerCompare = uibutton(exportInnerGL, 'Text', 'Flicker...', ...
        'ButtonPushedFcn', @onFlickerCompare, ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, 'Enable', 'off', ...
        'Tooltip', 'Rapidly alternate between two images to spot subtle differences');
    btnFlickerCompare.Layout.Row = 11; btnFlickerCompare.Layout.Column = 2;

    % Row 12: Record Macro / Img Math
    btnMacroRecord = uibutton(exportInnerGL, 'Text', 'Record Macro', ...
        'ButtonPushedFcn', @onMacroToggle, ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, 'Enable', 'off', ...
        'Tooltip', 'Record measurement operations as a replayable macro');
    btnMacroRecord.Layout.Row = 12; btnMacroRecord.Layout.Column = 1;

    btnImgMath = uibutton(exportInnerGL, 'Text', 'Img Math...', ...
        'ButtonPushedFcn', @onImageMath, ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, 'Enable', 'off', ...
        'Tooltip', 'Image arithmetic: subtract, divide, or ratio two loaded images');
    btnImgMath.Layout.Row = 12; btnImgMath.Layout.Column = 2;

    % Row 13: Rename header + base name field
    lblRename = uilabel(exportInnerGL, 'Text', 'Rename', ...
        'FontWeight', 'bold', 'FontSize', 10, ...
        'FontColor', [0.15 0.15 0.15]);
    lblRename.Layout.Row = 13; lblRename.Layout.Column = 1;

    efRenameBase = uieditfield(exportInnerGL, 'text', ...
        'Placeholder', 'base_name', ...
        'Tooltip', 'Base name for rename — files become name_001, _002, etc.');
    efRenameBase.Layout.Row = 13; efRenameBase.Layout.Column = 2;

    % Row 14: Rename All / Selected
    btnBatchRename = uibutton(exportInnerGL, 'Text', 'Rename All', ...
        'ButtonPushedFcn', @onBatchRename, ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, 'Enable', 'off', ...
        'Tooltip', 'Rename all loaded files: base_001, _002, etc.');
    btnBatchRename.Layout.Row = 14; btnBatchRename.Layout.Column = 1;

    btnRenameSelected = uibutton(exportInnerGL, 'Text', 'Rename Sel.', ...
        'ButtonPushedFcn', @onRenameSelected, ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, 'Enable', 'off', ...
        'Tooltip', 'Rename only selected file(s) with sequential numbering');
    btnRenameSelected.Layout.Row = 14; btnRenameSelected.Layout.Column = 2;

    % ════════════════════════════════════════════════════════════════════
    %  ROW 3: STATUS BAR
    %  [dimensions] | [bit depth] | [pixel size] | [mouse position]
    % ════════════════════════════════════════════════════════════════════
    statusGL = uigridlayout(rootGL, [1 5], ...
        'ColumnWidth', {110, 60, 100, '1x', 'fit'}, ...
        'RowHeight',   {'1x'}, ...
        'Padding',     [6 0 6 0], ...
        'ColumnSpacing', 10);
    statusGL.Layout.Row = 3;
    statusGL.Layout.Column = 1;

    lblStatusDims = uilabel(statusGL, 'Text', '-- x -- px', ...
        'FontSize', 10, 'FontColor', [0.45 0.45 0.45]);
    lblStatusDims.Layout.Row = 1; lblStatusDims.Layout.Column = 1;

    lblStatusBits = uilabel(statusGL, 'Text', '--bit', ...
        'FontSize', 10, 'FontColor', [0.45 0.45 0.45]);
    lblStatusBits.Layout.Row = 1; lblStatusBits.Layout.Column = 2;

    lblStatusPixSize = uilabel(statusGL, 'Text', 'uncalibrated', ...
        'FontSize', 10, 'FontColor', [0.45 0.45 0.45]);
    lblStatusPixSize.Layout.Row = 1; lblStatusPixSize.Layout.Column = 3;

    lblStatusMouse = uilabel(statusGL, 'Text', '', ...
        'FontSize', 10, 'FontColor', [0.45 0.45 0.45]);
    lblStatusMouse.Layout.Row = 1; lblStatusMouse.Layout.Column = 4;

    % Discreet loading indicator — appears during file I/O, hidden otherwise
    lblLoadStatus = uilabel(statusGL, 'Text', '', ...
        'FontSize', 9, 'FontColor', [0.35 0.65 0.85], ...
        'HorizontalAlignment', 'right');
    lblLoadStatus.Layout.Row = 1; lblLoadStatus.Layout.Column = 5;

    % Populate recent files dropdown from persisted state
    updateRecentDropdown();

    % Wire right-click context menus on image axes, thumbnail list, scale bar
    buildContextMenus();

    % ════════════════════════════════════════════════════════════════════
    %  PROGRAMMATIC API (returned when nargout > 0)
    % ════════════════════════════════════════════════════════════════════
    if nargout > 0
        api.fig            = fig;
        api.loadImages     = @(paths) loadImagesAPI(paths);
        api.getImages      = @getImagesAPI;
        api.getActiveIdx   = @getActiveIdxAPI;
        api.setActiveIdx   = @(idx) setActiveIdxAPI(idx);

        % Phase 4 — contrast
        api.setContrast    = @(low, high) setContrastAPI(low, high);
        api.autoContrast   = @() onAutoContrast([], []);

        % Phase 5 — measurement
        api.getLineProfile = @(x1,y1,x2,y2) getLineProfileAPI(x1,y1,x2,y2);

        % Phase 6 — processing & export
        api.applyFilter    = @(type, params) applyFilterAPI(type, params);
        api.computeFFT     = @() computeFFTAPI();
        api.exportImage    = @(path) exportImageAPI(path);

        % Comparison mode
        api.enterCompare    = @() enterCompareMode();
        api.exitCompare     = @() exitCompareMode();
        api.isCompareMode   = @() appData.compareMode;

        % Annotations
        api.placeAnnotation = @(x, y, str, sz, col) placeAnnotationAPI(x, y, str, sz, col);
        api.clearAnnotations = @() onClearAnnotations([], []);

        % New features
        api.rotateFlip     = @(mode) onRotateFlip(mode);
        api.setPixelSize   = @(sz, unit) setPixelSizeAPI(sz, unit);

        % Phase 2 features
        api.setGamma       = @(g) setGammaAPI(g);
        api.sessionSave    = @(fp) sessionSaveAPI(fp);
        api.sessionLoad    = @(fp) sessionLoadAPI(fp);

        % New features
        api.view3D          = @() on3DSurface([], []);
        api.templateMatch   = @(x1,y1,w,h) templateMatchAPI(x1,y1,w,h);
        api.noiseEstimate   = @() noiseEstimateAPI();
        api.getMeasStats    = @() getMeasStatsAPI();

        % Interactive measurement/ROI tools — headless wrappers around the
        % nested execute* functions so tests can drive them with explicit
        % coordinates (bypassing the two-click capture flow).
        api.measureDistance = @(x1,y1,x2,y2) executeMeasureDistance(x1,y1,x2,y2);
        api.measureDSpacing = @(x1,y1,x2,y2) executeDSpacing(x1,y1,x2,y2);
        api.measureAngle    = @(vx,vy,r1x,r1y,r2x,r2y) ...
                               executeAngleFromPoints([vx vy; r1x r1y; r2x r2y]);
        api.measurePolyline = @(pts) executePolylineFromPoints(pts);
        api.roiEllipse      = @(cx,cy,ex,ey) executeEllipseROI(cx,cy,ex,ey);
        api.roiPolygon      = @(pts) executePolygonROI(pts);
        api.annotRect       = @(x1,y1,x2,y2) executeAnnotRect(x1,y1,x2,y2);
        api.getOverlays        = @getOverlaysAPI;
        api.getMeasurementLog  = @getMeasurementLogAPI;
        api.exportMeasurements = @(path) writeMeasurementsCSV(path);

        % Contrast stack — headless wrappers for reset, colormap, transform,
        % invert, and colorbar toggle. These drive the same widget callbacks
        % used by the mouse, so state stays consistent with the GUI.
        api.resetContrast        = @() onResetContrast([], []);
        api.setColormap          = @(name) setColormapAPI(name);
        api.cycleColormap        = @() cycleColormapAPI();
        api.getColormap          = @() ddColormap.Value;
        api.setContrastTransform = @(mode) setContrastTransformAPI(mode);
        api.getContrastTransform = @getContrastTransformAPI;
        api.setInvert            = @(tf) setInvertAPI(tf);
        api.isInverted           = @isInvertedAPI;
        api.setColorbar          = @(tf) setColorbarAPI(tf);
        api.isColorbarVisible    = @() logical(cbColorbar.Value);

        % Test hook: inject synthetic EELS spectrum so deconvolve/KK api
        % wrappers can be exercised headlessly without a DM3/DM4 file.
        % Priority-3 click-capture bypass wrappers: crop, zoom box,
        % reset zoom, FFT mask. Each one drives the same logic the
        % mouse handlers invoke, but takes explicit coordinates so
        % tests can exercise it headlessly without a click flow.
        api.cropRect     = @(xMin, yMin, xMax, yMax) cropRectAPI(xMin, yMin, xMax, yMax);
        api.zoomRect     = @(xMin, yMin, xMax, yMax) zoomRectAPI(xMin, yMin, xMax, yMax);
        api.resetZoom    = @() onResetZoom([], []);
        api.getAxLimits  = @() struct('XLim', ax.XLim, 'YLim', ax.YLim);
        api.fftMask      = @(masks) fftMaskAPI(masks);

        api.injectEELSData       = @(E, I) injectEELSDataAPI(E, I);
        api.getEELSData          = @getEELSDataAPI;
        api.getEELSSSD           = @getEELSSSDAPI;
        api.getEELSKKResult      = @getEELSKKResultAPI;

        % EDS composite mode
        api.enterEDS        = @() onEnterEDS([], []);
        api.exitEDS         = @() onExitEDS();
        api.isEDSMode       = @getEDSMode;
        api.getEDSChannels  = @getEDSChannelsAPI;
        api.setEDSChannel   = @(idx, field, val) setEDSChannelAPI(idx, field, val);
        api.getEDSComposite = @getEDSCompositeAPI;

        % EELS API
        api.enterEELS        = @() onEnterEELS([], []);
        api.exitEELS         = @() onExitEELS();
        api.isEELSMode       = @() appData.eelsMode;
        api.eelsBackground   = @(fitWin) eelsBackgroundAPI(fitWin);
        api.eelsExtractMap   = @(sigWin, bgWin) eelsExtractMapAPI(sigWin, bgWin);
        api.eelsDeconvolve    = @() onEELSDeconvolve([], []);
        api.eelsELNES         = @(onset) eelsELNESAPI(onset);
        api.eelsKramersKronig = @() onEELSKramersKronig([], []);
        api.eelsNavigate      = @(row, col) eelsNavigateAPI(row, col);
        api.eelsSVD           = @(nComp) eelsSVDAPI(nComp);

        % Diffraction API
        api.findDiffSpots       = @() onAutoDetectSpots([], []);
        api.matchDiffraction    = @() onMatchDiffraction([], []);
        api.getDiffResults      = @() appData.diffResults;
        api.simulateDiffraction = @(phase, za) simDiffAPI(phase, za);
        api.virtualDarkField    = @(center, radius) vdfAPI(center, radius);

        % EDS Quantification API
        api.edsAssignElements    = @(elems) edsAssignAPI(elems);
        api.edsQuantify          = @() onQuantifyCL([], []);
        api.getEDSQuantification = @() struct('atomicPct', {appData.edsAtomicPct}, ...
            'weightPct', {appData.edsWeightPct}, 'elements', {appData.edsElements});
        api.edsQuantifyZAF       = @(t, angle) quantifyZAFAPI(t, angle);

        % ── Testability API (headless test hooks) ──────────────────────
        api.getPixels          = @getPixelsAPI;
        api.getImageDimensions = @getImageDimensionsAPI;

        api.refreshState   = @refreshState;
        api.close          = @() close(fig);
        varargout{1}       = api;
    end

    % Apply initial theme
    applyTheme();

    % Phase 4: build right-click context menu and init macro state
    buildContextMenu();
    appData.isRecording    = false;
    appData.macroRecording = {};
    appData.captureClicks  = [];

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onOpenFiles — Browse for image files via uigetfile
    % ════════════════════════════════════════════════════════════════════
    function onOpenFiles(~, ~)
        filterSpec = { ...
            '*.tif;*.tiff;*.jpg;*.jpeg;*.png;*.bmp;*.raw;*.dm3;*.dm4;*.bcf;*.ser;*.mrc;*.mrcs;*.spm;*.000;*.001;*.002;*.003', 'All Supported Images'; ...
            '*.tif;*.tiff',                   'TIFF Files (*.tif, *.tiff)'; ...
            '*.jpg;*.jpeg;*.png;*.bmp',       'Common Images (*.jpg, *.png, *.bmp)'; ...
            '*.dm3;*.dm4',                    'Gatan Files (*.dm3, *.dm4)'; ...
            '*.bcf',                          'Bruker EDS Files (*.bcf)'; ...
            '*.ser',                          'FEI SER Files (*.ser)'; ...
            '*.mrc;*.mrcs',                   'MRC Files (*.mrc, *.mrcs)'; ...
            '*.spm;*.000;*.001;*.002;*.003',  'AFM Files (*.spm, *.000)'; ...
            '*.raw',                          'RAW Binary Files (*.raw)'; ...
            '*.*',                            'All Files (*.*)'};

        startDir = appData.lastDir;
        if isempty(startDir) || ~isfolder(startDir)
            startDir = pwd;
        end

        try
            [files, folder] = uigetfile(filterSpec, 'Select Image File(s)', ...
                startDir, 'MultiSelect', 'on');
        catch ME
            % uigetfile can fail on unreachable network paths or user interrupt
            fig.Pointer = 'arrow';
            setStatus('File browser cancelled or failed.');
            return;
        end

        if isequal(files, 0)
            return;   % user cancelled
        end

        appData.lastDir = folder;

        % Normalize to cell array
        if ischar(files)
            files = {files};
        end

        % Build full paths
        fpaths = cellfun(@(f) fullfile(folder, f), files, 'UniformOutput', false);

        try
            loadImagesFromPaths(fpaths);
        catch ME
            hideLoading();
            fprintf(2, '\n[FermiViewer] Error loading files: %s\n', ME.message);
            for si = 1:numel(ME.stack)
                fprintf(2, '  at %s (line %d)\n', ME.stack(si).name, ME.stack(si).line);
            end
            uialert(fig, sprintf('Error loading files:\n%s', ME.message), ...
                'Load Error', 'Icon', 'error');
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onRemoveImage — Remove selected image(s) from the list
    % ════════════════════════════════════════════════════════════════════
    function onRemoveImage(~, ~)
        if isempty(appData.images)
            return;
        end

        % Get selected indices from listbox
        selVals = lbImages.Value;
        if iscell(selVals)
            selIdx = [selVals{:}];
        else
            selIdx = selVals;
        end

        % Filter out invalid indices (e.g., the placeholder 0)
        selIdx = selIdx(selIdx > 0 & selIdx <= numel(appData.images));
        if isempty(selIdx)
            return;
        end

        % Confirm multi-image removal — matches BosonPlotter's dataset-
        % removal prompt so accidental Ctrl+A → Remove doesn't silently
        % destroy work.
        if numel(selIdx) > 1
            answer = uiconfirm(fig, ...
                sprintf('Remove %d selected images?', numel(selIdx)), ...
                'Confirm Remove', 'Options', {'Remove', 'Cancel'}, ...
                'DefaultOption', 'Remove', 'CancelOption', 'Cancel');
            if strcmp(answer, 'Cancel'), return; end
        end

        % Remove selected images (keep contrast-state cache in lockstep)
        appData.images(selIdx) = [];
        if numel(appData.imageContrastState) >= max(selIdx)
            appData.imageContrastState(selIdx) = [];
        end
        if appData.lastDisplayedIdx > 0 && any(selIdx == appData.lastDisplayedIdx)
            appData.lastDisplayedIdx = 0;   % referenced image gone
        end

        % Update active index
        if isempty(appData.images)
            appData.activeIdx = 0;
        elseif appData.activeIdx > numel(appData.images)
            appData.activeIdx = numel(appData.images);
        elseif any(selIdx == appData.activeIdx)
            appData.activeIdx = min(appData.activeIdx, numel(appData.images));
            if appData.activeIdx == 0 && ~isempty(appData.images)
                appData.activeIdx = 1;
            end
        end

        % Exit compare mode if fewer than 2 images remain
        if numel(appData.images) < 2 && appData.compareMode
            btnCompare.Value = false;
            exitCompareMode();
        end
        btnCompare.Enable = onOff(numel(appData.images) >= 2);
        btnEDSToolbar.Enable = onOff(numel(appData.images) >= 1);

        rebuildImageList();

        if appData.activeIdx > 0
            displayImage();
        else
            clearDisplay();
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onSelectImage — Handle listbox selection change
    % ════════════════════════════════════════════════════════════════════
    function onSelectImage(~, ~)
        selVals = lbImages.Value;
        if iscell(selVals)
            idx = selVals{1};   % display the first selected item
        else
            idx = selVals;
        end

        if idx < 1 || idx > numel(appData.images)
            return;
        end

        appData.activeIdx = idx;

        % In compare mode, update the active panel instead
        if appData.compareMode
            if appData.compareActivePanel == 'L'
                appData.compareIdxL = idx;
                displayCompareImage('L');
            else
                appData.compareIdxR = idx;
                displayCompareImage('R');
            end
            return;
        end

        displayImage();
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onZoomFit — Reset axes limits to show the full image
    % ════════════════════════════════════════════════════════════════════
    function onZoomFit(~, ~)
        if appData.activeIdx < 1 || isempty(appData.rawPixels)
            return;
        end
        [H, W] = size(appData.rawPixels);
        ax.XLim = [0.5, W + 0.5];
        ax.YLim = [0.5, H + 0.5];
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onZoomActual — Zoom to 1:1 pixel ratio, centred on view
    % ════════════════════════════════════════════════════════════════════
    function onZoomActual(~, ~)
        if appData.activeIdx < 1 || isempty(appData.rawPixels)
            return;
        end

        [H, W] = size(appData.rawPixels);

        % Get the axes size in pixels to determine how many image pixels fit
        axPos = getpixelposition(ax, true);
        axW_px = axPos(3);
        axH_px = axPos(4);

        % Current view centre
        cx = mean(ax.XLim);
        cy = mean(ax.YLim);

        % At 1:1 ratio, the view should span axW_px image pixels wide
        halfW = axW_px / 2;
        halfH = axH_px / 2;

        newXLim = [cx - halfW, cx + halfW];
        newYLim = [cy - halfH, cy + halfH];

        % Clamp to image bounds
        if newXLim(1) < 0.5
            newXLim = [0.5, 0.5 + axW_px];
        end
        if newXLim(2) > W + 0.5
            newXLim = [W + 0.5 - axW_px, W + 0.5];
        end
        if newYLim(1) < 0.5
            newYLim = [0.5, 0.5 + axH_px];
        end
        if newYLim(2) > H + 0.5
            newYLim = [H + 0.5 - axH_px, H + 0.5];
        end

        ax.XLim = newXLim;
        ax.YLim = newYLim;
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onMouseMotion — Track mouse over axes, show pixel info
    % ════════════════════════════════════════════════════════════════════
    function onMouseMotion(~, ~)
        % Panel resize border detection: skip during capture mode
        if isempty(appData.captureMode) || strcmp(appData.captureMode, '')
            dir = detectResizeBorder();
            appData.panelResizeDir = dir;
            if     ~isempty(dir) && startsWith(dir, 'v_'), fig.Pointer = 'left';
            elseif ~isempty(dir) && startsWith(dir, 'h_'), fig.Pointer = 'top';
            else
                fig.Pointer = 'arrow';
            end
        end

        % In compare mode, ax may not exist
        if isempty(ax) || ~isvalid(ax)
            return;
        end
        % If no image is loaded, nothing to show
        if appData.activeIdx < 1 || isempty(appData.rawPixels)
            lblStatusMouse.Text = '';
            return;
        end

        [H, W] = size(appData.rawPixels);

        % Get mouse position in data coordinates
        cp = ax.CurrentPoint;
        xData = cp(1, 1);
        yData = cp(1, 2);

        % Check if mouse is within axes limits
        if xData < ax.XLim(1) || xData > ax.XLim(2) || ...
           yData < ax.YLim(1) || yData > ax.YLim(2)
            lblStatusMouse.Text = '';
            return;
        end

        % Convert to nearest integer pixel coordinate
        col = round(xData);
        row = round(yData);

        % Check if within image bounds
        if col < 1 || col > W || row < 1 || row > H
            lblStatusMouse.Text = '';
            return;
        end

        % Read raw pixel intensity (before contrast adjustment)
        intensity = appData.rawPixels(row, col);

        % Format based on data type (integer vs float)
        if intensity == floor(intensity) && abs(intensity) < 1e7
            lblStatusMouse.Text = sprintf('(%d, %d) = %d', col, row, round(intensity));
        else
            lblStatusMouse.Text = sprintf('(%d, %d) = %.4g', col, row, intensity);
        end

        % Update pixel inspector if active
        if cbPixelInspector.Value && ~isempty(hPixelInspector) && isvalid(hPixelInspector)
            updatePixelInspector(col, row);
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onFigureClose — Clean up and close the figure
    % ════════════════════════════════════════════════════════════════════
    function onFigureClose(~, ~)
        % Flicker Compare mode spins up a timer; if the user closes the
        % window without clicking Stop, the timer keeps firing against
        % a deleted figure (swallowed by the callback's catch). Stop and
        % delete it here so nothing leaks across open/close cycles.
        if isfield(appData, 'flickerTimer') && ~isempty(appData.flickerTimer) ...
                && isvalid(appData.flickerTimer)
            stop(appData.flickerTimer);
            delete(appData.flickerTimer);
        end
        delete(fig);
    end

    % ════════════════════════════════════════════════════════════════════
    %  CORE RENDER: displayImage — Render the active image to axes
    % ════════════════════════════════════════════════════════════════════
    function displayImage()
        if appData.compareMode
            return;   % in compare mode, use displayCompareImage instead
        end
        if appData.edsMode
            compositeEDS();
            return;   % in EDS mode, show composite instead of single image
        end
        if appData.activeIdx < 1 || appData.activeIdx > numel(appData.images)
            clearDisplay();
            return;
        end

        % Persist the outgoing image's contrast/gamma state so it can be
        % restored when the user navigates back to it in the same session.
        % Inlined (no helper function) to stay under MATLAB's nested-fn cap.
        outIdx = appData.lastDisplayedIdx;
        if outIdx >= 1 && outIdx <= numel(appData.images) && ...
                ~appData.compareMode && ~appData.edsMode
            while numel(appData.imageContrastState) < outIdx
                appData.imageContrastState{end+1} = [];
            end
            appData.imageContrastState{outIdx} = struct( ...
                'lo',        sldLow.Value, ...
                'hi',        sldHigh.Value, ...
                'gamma',     appData.gamma, ...
                'transform', appData.contrastTransform, ...
                'invert',    appData.contrastInvert, ...
                'colormap',  ddColormap.Value);
        end

        % Clear any measurement selection when switching images
        deselectMeasurement();

        dataStruct = appData.images{appData.activeIdx};
        ps = dataStruct.metadata.parserSpecific;

        % Skip non-image data (e.g. 1D spectra from DM3/DM4)
        if ~isfield(ps, 'imageData') || ~isfield(ps, 'isImage') || ~ps.isImage
            clearDisplay();
            setStatus('Selected file is a spectrum, not an image.');
            return;
        end

        imgInfo    = ps.imageData;
        pixels     = imgInfo.pixels;

        % Convert to grayscale double (raw, unprocessed)
        if imgInfo.numChannels == 3
            % RGB: convert to luminance for grayscale display
            pixDouble = double(pixels);
            rawGray = 0.299 * pixDouble(:,:,1) + ...
                      0.587 * pixDouble(:,:,2) + ...
                      0.114 * pixDouble(:,:,3);
        else
            rawGray = double(pixels);
        end

        % Store the image pipeline state
        appData.rawPixels      = rawGray;
        appData.filteredPixels = rawGray;

        % Clear undo stack on image switch
        appData.undoStack = {};

        % Detect multi-frame stacks (e.g. multi-page TIFFs)
        if isfield(imgInfo, 'numFrames') && imgInfo.numFrames > 1 && ...
                isfield(imgInfo, 'frames') && ~isempty(imgInfo.frames)
            nF = numel(imgInfo.frames);
            appData.stackFrames = cell(1, nF);
            for fk = 1:nF
                frm = imgInfo.frames{fk};
                if size(frm, 3) == 3
                    frm = double(frm);
                    frm = 0.299*frm(:,:,1) + 0.587*frm(:,:,2) + 0.114*frm(:,:,3);
                else
                    frm = double(frm);
                end
                appData.stackFrames{fk} = frm;
            end
            showStackControls(nF);
        else
            appData.stackFrames = {};
            appData.stackIdx    = 0;
            showStackControls(0);
        end

        % Set slider ranges based on actual data range
        dMin = min(rawGray(:));
        dMax = max(rawGray(:));
        if dMax == dMin
            dMax = dMin + 1;   % avoid degenerate range
        end

        sldLow.Limits  = [dMin, dMax];
        sldHigh.Limits = [dMin, dMax];

        % Priority order for initial contrast window:
        %   1. In-session saved state (user was already here — restore it)
        %   2. DM-saved display window from the parser (DigitalMicrograph
        %      stored view — best match for microscopist intent)
        %   3. Full pixel range (safe fallback; no aggressive auto-stretch)
        pLow  = NaN;
        pHigh = NaN;
        savedState = [];
        if appData.activeIdx <= numel(appData.imageContrastState)
            tmpState = appData.imageContrastState{appData.activeIdx};
            if isstruct(tmpState), savedState = tmpState; end
        end

        if ~isempty(savedState) && ...
                isfinite(savedState.lo) && isfinite(savedState.hi) && ...
                savedState.hi > savedState.lo
            pLow  = max(dMin, min(dMax, savedState.lo));
            pHigh = max(dMin, min(dMax, savedState.hi));
        elseif isfield(imgInfo, 'displayLow') && isfield(imgInfo, 'displayHigh') ...
                && isfinite(imgInfo.displayLow) && isfinite(imgInfo.displayHigh) ...
                && imgInfo.displayHigh > imgInfo.displayLow
            bScale  = 1;
            bOrigin = 0;
            if isfield(imgInfo, 'intensityScale') && isfinite(imgInfo.intensityScale) ...
                    && imgInfo.intensityScale ~= 0
                bScale = imgInfo.intensityScale;
            end
            if isfield(imgInfo, 'intensityOrigin') && isfinite(imgInfo.intensityOrigin)
                bOrigin = imgInfo.intensityOrigin;
            end
            pLow  = (imgInfo.displayLow  - bOrigin) / bScale;
            pHigh = (imgInfo.displayHigh - bOrigin) / bScale;
            pLow  = max(dMin, min(dMax, pLow));
            pHigh = max(dMin, min(dMax, pHigh));
        end

        if ~(isfinite(pLow) && isfinite(pHigh) && pHigh > pLow)
            pLow  = dMin;
            pHigh = dMax;
        end
        sldLow.Value  = pLow;
        sldHigh.Value = pHigh;
        efLow.Value   = pLow;
        efHigh.Value  = pHigh;

        % Restore gamma / transform / invert / colormap from saved state,
        % or reset them to defaults on first-ever view of this image so
        % the UI doesn't leak the previous image's gamma/transform.
        if ~isempty(savedState)
            if isfield(savedState, 'gamma') && isfinite(savedState.gamma)
                appData.gamma = savedState.gamma;
                sldGamma.Value = max(sldGamma.Limits(1), ...
                                     min(sldGamma.Limits(2), savedState.gamma));
                efGamma.Value = appData.gamma;
            end
            if isfield(savedState, 'transform') && ...
                    any(strcmp(savedState.transform, ddContrastTransform.Items))
                appData.contrastTransform = savedState.transform;
                ddContrastTransform.Value = savedState.transform;
            end
            if isfield(savedState, 'invert')
                appData.contrastInvert = logical(savedState.invert);
                cbInvert.Value = appData.contrastInvert;
            end
            if isfield(savedState, 'colormap') && ...
                    any(strcmp(savedState.colormap, ddColormap.Items))
                ddColormap.Value = savedState.colormap;
            end
        else
            % Fresh view — reset gamma/transform/invert to defaults so the
            % new image doesn't inherit the previous image's adjustments.
            appData.gamma = 1.0;
            sldGamma.Value = 1.0;
            efGamma.Value = 1.0;
            appData.contrastTransform = 'linear';
            ddContrastTransform.Value = 'linear';
            appData.contrastInvert = false;
            cbInvert.Value = false;
        end
        lblGamma.Text = 'Gamma';

        [H, W] = size(rawGray);

        % Cancel any in-progress capture before clearing
        if ~isempty(appData.captureMode)
            cancelCapture();
        end

        % Clear all overlays (switches image context — old overlays no longer valid)
        clearAllOverlays();

        % Clear the axes and create fresh imagesc (resets zoom on image switch)
        if isempty(ax) || ~isvalid(ax), return; end
        delete(ax.Children);
        cla(ax);

        % Build the display buffer (HQ mode area-averages to axes size so
        % atomic features stay crisp without aliasing; fast mode skips it).
        % Must happen AFTER filteredPixels is set (line above) because
        % prepareDisplayBuffer reads from appData.filteredPixels.
        prepareDisplayBuffer();

        % Compute initial contrast-adjusted image via pipeline
        dispImg = applyContrastPipeline(appData.displayPixels, pLow, pHigh);
        appData.displayImg = dispImg;

        % Use the buffer's actual image-coordinate extent so MATLAB does NOT
        % bilinearly stretch a downsampled buffer across the full native
        % coordinate range. A downsampled buffer mapped to XData=[1 W] would
        % smear pixels across native coords — destroying atomic detail.
        % displayRegion is set by prepareDisplayBuffer() above.
        dr = appData.displayRegion;
        if isempty(dr), dr = [1, 1, W, H]; end
        hImg = imagesc(ax, 'XData', [dr(1) dr(3)], 'YData', [dr(2) dr(4)], 'CData', dispImg);
        appData.imgHandle = hImg;
        attachImageContextMenu();

        % Force nearest-neighbor sampling. In HQ mode the CData is already
        % at display resolution so 'nearest' gives pixel-perfect rendering.
        % Property added to uifigure Image in R2024a; try/catch for R2023b.
        try
            hImg.Interpolation = 'nearest';
        catch
        end

        % Apply selected colormap
        cmapName = ddColormap.Value;
        colormap(ax, feval(cmapName, 256));
        ax.CLim = [0 1];

        ax.YDir = 'reverse';
        axis(ax, 'equal');
        ax.XLim = [0.5, W + 0.5];
        ax.YLim = [0.5, H + 0.5];
        ax.XTick = [];
        ax.YTick = [];
        title(ax, '');
        xlabel(ax, '');
        ylabel(ax, '');
        ax.Toolbar.Visible = 'off';

        % Update filename label in toolbar
        [~, fname, fext] = fileparts(dataStruct.metadata.source);
        lblFilename.Text = [fname, fext];

        % Update metadata panel, status bar, and histogram
        updateMetadataPanel();
        updateStatusBar();
        updateHistogram();

        % Enable measurement controls; scale bar only when calibrated
        imgInfo2 = dataStruct.metadata.parserSpecific.imageData;
        isCalib  = imgInfo2.calibrated && ~isnan(imgInfo2.pixelSize);
        cbScaleBar.Enable       = onOff(isCalib);
        cbScaleBar.Value        = isCalib;   % on by default when calibrated
        btnScaleBarColor.Enable = onOff(isCalib);
        spnScaleBarFont.Enable  = onOff(isCalib);
        efScaleBarLen.Enable    = onOff(isCalib);
        ddScaleBarUnit.Enable   = onOff(isCalib);
        if isCalib
            rebuildScaleBar();
        end
        btnLineProfile.Enable   = 'on';
        btnDistance.Enable      = 'on';
        btnAngle.Enable        = 'on';
        btnPolyline.Enable     = 'on';
        btnClearOverlays.Enable = 'on';
        % Auto-populate tilt UI from image metadata (inlined to stay
        % under MATLAB's nested-function parser cap).
        spnTiltAngle.Enable    = 'on';
        cbTiltCorrect.Enable   = 'on';
        ddTiltGeometry.Enable  = 'on';
        try
            tiltMetaDeg = imaging.getStageTilt(imgInfo2);
        catch
            tiltMetaDeg = NaN;
        end
        if ~isnan(tiltMetaDeg) && abs(tiltMetaDeg) > 1e-3
            tiltMetaDeg = max(-89.9, min(89.9, tiltMetaDeg));
            spnTiltAngle.Value = tiltMetaDeg;
            cbTiltCorrect.Value = true;
        elseif ~cbTiltCorrect.Value
            spnTiltAngle.Value = 0;
        end

        % Enable processing controls
        % Icon transform toolbar above the image (mirrors the Transform
        % tab buttons' enable state). Guarded against stale/invalid
        % handles — the toolbar is rebuilt on compare-mode exit.
        if isfield(appData, 'transformToolbarBtns')
            for toolbarK = 1:numel(appData.transformToolbarBtns)
                toolbarBtn = appData.transformToolbarBtns(toolbarK);
                if ~isempty(toolbarBtn) && isgraphics(toolbarBtn) && isvalid(toolbarBtn)
                    toolbarBtn.Enable = 'on';
                end
            end
        end
        btnRotCW.Enable       = 'on';
        btnRotCCW.Enable      = 'on';
        btnFlipH.Enable       = 'on';
        btnFlipV.Enable       = 'on';
        btnGaussian.Enable    = 'on';
        btnMedian.Enable      = 'on';
        btnShowFFT.Enable     = 'on';
        btnCLAHE.Enable       = 'on';
        btnUndoFilters.Enable = 'on';
        btnROIStats.Enable    = 'on';
        btnZoomBox.Enable     = 'on';
        btnResetZoom.Enable   = 'on';
        btnCropImage.Enable   = 'on';
        btnSaveCrop.Enable    = 'on';
        btnSaveImage.Enable   = 'on';
        btnSetPixelSize.Enable  = 'on';
        btnFFTMask.Enable       = 'on';
        btnParticles.Enable     = 'on';
        btnAlignStack.Enable    = onOff(numel(appData.images) >= 2);
        btnColorOverlay.Enable  = onOff(numel(appData.images) >= 2);
        btnExportOverlays.Enable = 'on';
        btnBatchExport.Enable   = onOff(numel(appData.images) >= 1);
        btnCreateGIF.Enable     = onOff(numel(appData.images) >= 2);
        btnCopyClipboard.Enable = 'on';
        cbColorbar.Enable       = 'on';
        cbMinimap.Enable        = 'on';
        cbPixelInspector.Enable = 'on';
        btnLiveThresh.Enable    = 'on';
        btnImgMath.Enable       = onOff(numel(appData.images) >= 2);
        btnWatershed.Enable     = 'on';
        btnBatchCrop.Enable     = onOff(numel(appData.images) >= 2);
        btnMontage.Enable       = onOff(numel(appData.images) >= 2);
        btnSessionSave.Enable   = 'on';
        btnEnterEDS.Enable      = 'on';
        btnGrid.Enable          = onOff(numel(appData.images) >= 2);
        btnExportMeasure.Enable = 'on';
        btnDiffRings.Enable     = 'on';
        btnROIManager.Enable    = 'on';
        btnCalibrateBar.Enable  = 'on';
        btnBatchRename.Enable   = onOff(numel(appData.images) >= 1);
        btnRenameSelected.Enable = 'on';

        % Enable Phase 3 measurement controls
        btnDSpacing.Enable    = onOff(isCalib);
        spnProfileWidth.Enable = 'on';
        btnEllipseROI.Enable  = 'on';
        btnPolygonROI.Enable  = 'on';
        btnInvertImg.Enable   = 'on';

        % Enable Phase 3 processing controls
        btnSharpen.Enable      = 'on';
        btnBinImage.Enable     = 'on';
        btnMorphOp.Enable      = 'on';
        btnButterworth.Enable  = 'on';
        btnRadialProfile.Enable = 'on';
        btnAzIntegrate.Enable  = 'on';
        btnSurfacePlot.Enable  = 'on';
        btnBatchConvert.Enable = onOff(numel(appData.images) >= 1);
        btnCustomCmap.Enable   = 'on';

        % Enable Phase 4 processing controls
        btnPlaneLevel.Enable      = 'on';
        btnRoughness.Enable       = 'on';
        btnInterfaceFit.Enable    = 'on';
        btnMultiOtsu.Enable       = 'on';
        btnLatticeMeasure.Enable  = 'on';
        btnGPA.Enable             = 'on';
        btnCTF.Enable             = 'on';
        btnDefectCount.Enable     = 'on';
        btnBackProject.Enable     = 'on';
        btnFigureBuilder.Enable   = onOff(numel(appData.images) >= 1);
        btnJournalExport.Enable   = 'on';
        btnCalibColorbar.Enable   = 'on';
        btnMacroRecord.Enable     = 'on';
        btnFlickerCompare.Enable  = onOff(numel(appData.images) >= 2);
        btn3DSurface.Enable       = 'on';
        btnLiveFFT.Enable         = 'on';
        btnTemplateMatch.Enable   = 'on';
        btnStitchImages.Enable    = onOff(numel(appData.images) >= 2);
        btnNoiseEstimate.Enable   = 'on';
        btnPubPresets.Enable      = 'on';
        btnColormapPreset.Enable  = 'on';
        btnMeasStats.Enable       = 'on';
        btnBatchMeas.Enable       = onOff(numel(appData.images) >= 2);
        btnExportToDP.Enable      = 'on';

        % Enable annotation controls
        btnPlaceAnnot.Enable  = 'on';
        btnClearAnnot.Enable  = 'on';
        ddAnnotColor.Enable   = 'on';
        btnPlaceArrow.Enable  = 'on';
        btnPlaceLine.Enable   = 'on';
        btnPlaceRect.Enable   = 'on';
        btnPlaceCircle.Enable = 'on';

        % Remember which image we just displayed so the next displayImage()
        % call can save its state before switching away.
        appData.lastDisplayedIdx = appData.activeIdx;
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: clearDisplay — Clear the axes and reset status when no image
    % ════════════════════════════════════════════════════════════════════
    function clearDisplay()
        appData.rawPixels      = [];
        appData.filteredPixels = [];
        appData.preCropPixels  = [];
        appData.displayImg     = [];
        appData.imgHandle      = [];
        appData.edsComposite   = [];
        if ~isempty(ax) && isvalid(ax)
            delete(ax.Children);
            cla(ax);
        end
        if ~isempty(ax) && isvalid(ax)
            ax.XTick = [];
            ax.YTick = [];
            title(ax, 'Open an image file to begin', 'Interpreter', 'none');
            colormap(ax, gray(256));
            ax.Toolbar.Visible = 'off';
        end

        lblFilename.Text      = '(no image loaded)';
        lblStatusDims.Text    = '-- x -- px';
        lblStatusBits.Text    = '--bit';
        lblStatusPixSize.Text = 'uncalibrated';
        lblStatusMouse.Text   = '';
        taMetadata.Value      = {'(no image loaded)'};

        % Disable measurement controls
        btnLineProfile.Enable   = 'off';
        btnDistance.Enable      = 'off';
        btnExportProfile.Enable = 'off';
        btnAngle.Enable         = 'off';
        btnPolyline.Enable      = 'off';
        btnClearOverlays.Enable = 'off';
        cbScaleBar.Enable       = 'off';
        btnScaleBarColor.Enable = 'off';
        spnScaleBarFont.Enable  = 'off';
        efScaleBarLen.Enable    = 'off';
        ddScaleBarUnit.Enable   = 'off';

        % Disable processing controls
        % Icon transform toolbar above the image — mirrors the Transform
        % tab buttons so they grey out together when the display is cleared.
        if isfield(appData, 'transformToolbarBtns')
            for toolbarK = 1:numel(appData.transformToolbarBtns)
                toolbarBtn = appData.transformToolbarBtns(toolbarK);
                if ~isempty(toolbarBtn) && isgraphics(toolbarBtn) && isvalid(toolbarBtn)
                    toolbarBtn.Enable = 'off';
                end
            end
        end
        btnRotCW.Enable       = 'off';
        btnRotCCW.Enable      = 'off';
        btnFlipH.Enable       = 'off';
        btnFlipV.Enable       = 'off';
        btnGaussian.Enable    = 'off';
        btnMedian.Enable      = 'off';
        btnShowFFT.Enable     = 'off';
        btnCLAHE.Enable       = 'off';
        btnUndoFilters.Enable = 'off';
        btnROIStats.Enable    = 'off';
        btnZoomBox.Enable     = 'off';
        btnResetZoom.Enable   = 'off';
        btnCropImage.Enable   = 'off';
        btnSaveCrop.Enable    = 'off';
        btnSaveImage.Enable   = 'off';
        btnSetPixelSize.Enable   = 'off';
        btnFFTMask.Enable        = 'off';
        btnParticles.Enable      = 'off';
        btnAlignStack.Enable     = 'off';
        btnColorOverlay.Enable   = 'off';
        btnExportOverlays.Enable = 'off';
        btnBatchExport.Enable    = 'off';
        btnCreateGIF.Enable      = 'off';
        btnCopyClipboard.Enable  = 'off';
        cbColorbar.Enable        = 'off';
        cbColorbar.Value         = false;
        cbMinimap.Enable         = 'off';
        cbMinimap.Value          = false;
        cbPixelInspector.Enable  = 'off';
        cbPixelInspector.Value   = false;
        btnLiveThresh.Enable     = 'off';
        btnImgMath.Enable        = 'off';
        btnWatershed.Enable      = 'off';
        btnBatchCrop.Enable      = 'off';
        btnMontage.Enable        = 'off';
        btnSessionSave.Enable    = 'off';
        btnEnterEDS.Enable       = 'off';
        btnEDSToolbar.Enable     = 'off';
        btnAddChannel.Enable     = 'off';
        btnRemoveChannel.Enable  = 'off';
        btnExportComposite.Enable = 'off';
        btnGrid.Enable           = 'off';
        btnExportMeasure.Enable  = 'off';
        btnDiffRings.Enable      = 'off';
        btnROIManager.Enable     = 'off';
        btnCalibrateBar.Enable   = 'off';
        btnBatchRename.Enable    = 'off';
        btnRenameSelected.Enable = 'off';
        if ~isempty(hColorbar) && isvalid(hColorbar)
            delete(hColorbar);
            hColorbar = [];
        end
        if ~isempty(hMinimap) && isvalid(hMinimap)
            delete(hMinimap);
            hMinimap = [];
        end
        if ~isempty(hPixelInspector) && isvalid(hPixelInspector)
            delete(hPixelInspector);
            hPixelInspector = [];
        end

        % Disable Phase 4 buttons
        btnPlaneLevel.Enable      = 'off';
        btnRoughness.Enable       = 'off';
        btnInterfaceFit.Enable    = 'off';
        btnMultiOtsu.Enable       = 'off';
        btnLatticeMeasure.Enable  = 'off';
        btnGPA.Enable             = 'off';
        btnCTF.Enable             = 'off';
        btnDefectCount.Enable     = 'off';
        btnBackProject.Enable     = 'off';
        btnFigureBuilder.Enable   = 'off';
        btnJournalExport.Enable   = 'off';
        btnCalibColorbar.Enable   = 'off';
        btnMacroRecord.Enable     = 'off';
        btnFlickerCompare.Enable  = 'off';

        % Disable annotation controls
        btnPlaceAnnot.Enable  = 'off';
        btnClearAnnot.Enable  = 'off';
        ddAnnotColor.Enable   = 'off';

        % Hide stack navigator and reset stack state
        appData.stackFrames = {};
        appData.stackIdx    = 0;
        appData.undoStack   = {};
        showStackControls(0);

        % Clear histogram
        cla(histAx);
        histAx.XLim = [0 1];
        histAx.YLim = [0 1];
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: refreshTiltFromMetadata — Auto-populate tilt UI from image
    %  ───────────────────────────────────────────────────────────────────
    %  Reads the stage tilt via imaging.getStageTilt and updates the
    %  checkbox + spinner. Auto-enables the checkbox only when a non-zero
    %  tilt was actually found in the metadata. Leaves the controls usable
    %  (enable='on') so users can manually enter a tilt for uncalibrated
    %  images.
    % ════════════════════════════════════════════════════════════════════
    % ════════════════════════════════════════════════════════════════════
    %  HELPER: getTiltState — Returns effective tilt angle, axis, geometry
    %  ───────────────────────────────────────────────────────────────────
    %  Returns:
    %    tiltDeg  — 0 when correction is off; spinner value otherwise
    %    tiltAxis — 'Y' (default; perpendicular to the tilt rotation axis)
    %    isActive — logical shortcut (tiltDeg ~= 0)
    %    geometry — 'CrossSection' (default, 1/sin correction) or
    %               'Surface' (1/cos correction). Read from the tilt
    %               geometry dropdown; see imaging.measureDistance for
    %               the physics.
    % ════════════════════════════════════════════════════════════════════
    function [tiltDeg, tiltAxis, isActive, geometry] = getTiltState()
        tiltAxis = 'Y';
        if isvalid(cbTiltCorrect) && cbTiltCorrect.Value
            tiltDeg = spnTiltAngle.Value;
        else
            tiltDeg = 0;
        end
        isActive = tiltDeg ~= 0;
        if isvalid(ddTiltGeometry)
            geometry = ddTiltGeometry.Value;   % 'CrossSection' | 'Surface'
        else
            geometry = 'CrossSection';          % safe default
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: updateStatusBar — Refresh status bar labels from active image
    % ════════════════════════════════════════════════════════════════════
    function updateStatusBar()
        if appData.activeIdx < 1 || appData.activeIdx > numel(appData.images)
            lblStatusDims.Text    = '-- x -- px';
            lblStatusBits.Text    = '--bit';
            lblStatusPixSize.Text = 'uncalibrated';
            lblStatusMouse.Text   = '';
            return;
        end

        imgInfo = appData.images{appData.activeIdx}.metadata.parserSpecific.imageData;

        % Dimensions
        lblStatusDims.Text = sprintf('%d x %d px', imgInfo.width, imgInfo.height);

        % Bit depth
        lblStatusBits.Text = sprintf('%d-bit', imgInfo.bitDepth);

        % Pixel size
        if imgInfo.calibrated && ~isnan(imgInfo.pixelSize)
            lblStatusPixSize.Text = sprintf('%.4g %s/px', imgInfo.pixelSize, imgInfo.pixelUnit);
        else
            lblStatusPixSize.Text = 'uncalibrated';
        end

        % Mouse position is updated dynamically in onMouseMotion
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: updateMetadataPanel — Populate metadata text area
    % ════════════════════════════════════════════════════════════════════
    function updateMetadataPanel()
        if appData.activeIdx < 1 || appData.activeIdx > numel(appData.images)
            taMetadata.Value = {'(no image loaded)'};
            return;
        end

        dataStruct = appData.images{appData.activeIdx};
        imgInfo    = dataStruct.metadata.parserSpecific.imageData;
        lines      = {};

        % Source file
        [~, fname, fext] = fileparts(dataStruct.metadata.source);
        lines{end+1} = sprintf('File:   %s%s', fname, fext);
        lines{end+1} = sprintf('Parser: %s', dataStruct.metadata.parserName);
        lines{end+1} = '';

        % Dimensions
        lines{end+1} = sprintf('Width:  %d px', imgInfo.width);
        lines{end+1} = sprintf('Height: %d px', imgInfo.height);
        lines{end+1} = sprintf('Depth:  %d-bit', imgInfo.bitDepth);
        lines{end+1} = sprintf('Chans:  %d', imgInfo.numChannels);
        lines{end+1} = sprintf('Frames: %d', imgInfo.numFrames);
        lines{end+1} = '';

        % Calibration
        if imgInfo.calibrated && ~isnan(imgInfo.pixelSize)
            lines{end+1} = sprintf('Pixel:  %.4g %s', imgInfo.pixelSize, imgInfo.pixelUnit);
        else
            lines{end+1} = 'Pixel:  uncalibrated';
        end
        lines{end+1} = '';

        % Acquisition parameters (instrument metadata)
        if isstruct(imgInfo.acquiParams) && ~isempty(fieldnames(imgInfo.acquiParams))
            lines{end+1} = '── Acquisition ──';

            % FEI metadata (nested structs for sections)
            if isfield(imgInfo.acquiParams, 'feiMetadata')
                fei = imgInfo.acquiParams.feiMetadata;
                sections = fieldnames(fei);
                for si = 1:numel(sections)
                    sec = sections{si};
                    secData = fei.(sec);
                    if ~isstruct(secData)
                        continue;
                    end
                    lines{end+1} = sprintf('[%s]', sec); %#ok<AGROW>
                    keys = fieldnames(secData);
                    for ki = 1:numel(keys)
                        k = keys{ki};
                        v = secData.(k);
                        if ischar(v) || isstring(v)
                            lines{end+1} = sprintf('  %s: %s', k, v); %#ok<AGROW>
                        elseif isnumeric(v)
                            lines{end+1} = sprintf('  %s: %g', k, v); %#ok<AGROW>
                        end
                    end
                end
            else
                % Flat acquisition params (non-FEI)
                keys = fieldnames(imgInfo.acquiParams);
                for ki = 1:numel(keys)
                    k = keys{ki};
                    v = imgInfo.acquiParams.(k);
                    if ischar(v) || isstring(v)
                        lines{end+1} = sprintf('  %s: %s', k, v); %#ok<AGROW>
                    elseif isnumeric(v) && isscalar(v)
                        lines{end+1} = sprintf('  %s: %g', k, v); %#ok<AGROW>
                    end
                end
            end
        end

        taMetadata.Value = lines;
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: rebuildImageList — Sync the listbox with appData.images
    % ════════════════════════════════════════════════════════════════════
    function rebuildImageList()
        if isempty(appData.images)
            lbImages.Items     = {'(no images loaded)'};
            lbImages.ItemsData = {0};
            return;
        end

        items = cell(1, numel(appData.images));
        idata = cell(1, numel(appData.images));
        for k = 1:numel(appData.images)
            [~, fname, fext] = fileparts(appData.images{k}.metadata.source);
            items{k} = [fname, fext];
            idata{k} = k;
        end

        lbImages.Items     = items;
        lbImages.ItemsData = idata;

        % Restore selection to active index
        if appData.activeIdx >= 1 && appData.activeIdx <= numel(appData.images)
            lbImages.Value = {appData.activeIdx};
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: loadImagesFromPaths — Load files and add to appData.images
    % ════════════════════════════════════════════════════════════════════
    function loadImagesFromPaths(fpaths)
        if ischar(fpaths)
            fpaths = {fpaths};
        end

        nFiles = numel(fpaths);
        if nFiles > 0
            showLoading(sprintf('Loading %d file(s)...', nFiles));
        end
        loadedAny = false;

        for k = 1:nFiles
            fp = fpaths{k};
            [~, fn, fext] = fileparts(fp);
            updateLoading(k, nFiles, [fn fext]);

            [~, ~, ext] = fileparts(fp);
            ext = lower(ext);

            try
                switch ext
                    case {'.tif', '.tiff'}
                        data = parser.importTIFF(fp);
                        appendImage(data);
                        addToRecentFiles(fp);
                        loadedAny = true;

                    case {'.jpg', '.jpeg', '.png', '.bmp', '.gif'}
                        data = parser.importImage(fp);
                        appendImage(data);
                        addToRecentFiles(fp);
                        loadedAny = true;

                    case '.bcf'
                        data = parser.importBCF(fp);
                        appendImage(data);
                        addToRecentFiles(fp);
                        loadedAny = true;

                    case {'.spm', '.000', '.001', '.002', '.003'}
                        data = parser.importAFM(fp);
                        appendImage(data);
                        addToRecentFiles(fp);
                        loadedAny = true;

                    case '.raw'
                        % RAW files need dimensions from user
                        data = promptAndLoadRaw(fp);
                        if ~isempty(data)
                            appendImage(data);
                            addToRecentFiles(fp);
                            loadedAny = true;
                        end

                    case '.dm3'
                        data = parser.importDM3(fp);
                        appendImage(data);
                        addToRecentFiles(fp);
                        loadedAny = true;

                    case '.dm4'
                        data = parser.importDM4(fp);
                        appendImage(data);
                        addToRecentFiles(fp);
                        loadedAny = true;

                    case '.ser'
                        data = parser.importSER(fp);
                        appendImage(data);
                        addToRecentFiles(fp);
                        loadedAny = true;

                    case {'.mrc', '.mrcs'}
                        data = parser.importMRC(fp);
                        appendImage(data);
                        addToRecentFiles(fp);
                        loadedAny = true;

                    otherwise
                        uialert(fig, ...
                            sprintf('Unsupported file format: "%s"\n\nSupported: .tif, .tiff, .jpg, .png, .bcf, .raw, .dm3, .dm4, .ser, .mrc, .spm, .000', ext), ...
                            'Unsupported Format', 'Icon', 'warning');
                end
            catch ME
                fprintf(2, '\n[FermiViewer] Load error (%s): %s\n', fp, ME.message);
                for si = 1:numel(ME.stack)
                    fprintf(2, '  at %s (line %d)\n', ME.stack(si).name, ME.stack(si).line);
                end
                uialert(fig, ...
                    sprintf('Failed to load "%s":\n\n%s', fp, ME.message), ...
                    'Load Error', 'Icon', 'error');
            end
        end

        hideLoading();
        if loadedAny
            rebuildImageList();
            displayImage();
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: promptAndLoadRaw — Show input dialog for RAW file params
    % ════════════════════════════════════════════════════════════════════
    function data = promptAndLoadRaw(fp)
        data = [];

        [~, fname, fext] = fileparts(fp);
        prompt  = {'Width (pixels):', 'Height (pixels):', 'Bit Depth (8, 16, or 32):'};
        dlgTitle = sprintf('RAW Image Parameters — %s%s', fname, fext);
        defaults = {'512', '512', '16'};

        answer = inputdlg(prompt, dlgTitle, [1 40], defaults);
        if isempty(answer)
            return;   % user cancelled
        end

        W = str2double(answer{1});
        H = str2double(answer{2});
        B = str2double(answer{3});

        if isnan(W) || isnan(H) || isnan(B) || W < 1 || H < 1
            uialert(fig, 'Invalid dimensions. Width and Height must be positive integers.', ...
                'Invalid Input', 'Icon', 'error');
            return;
        end

        if ~ismember(B, [8 16 32])
            uialert(fig, 'BitDepth must be 8, 16, or 32.', ...
                'Invalid Input', 'Icon', 'error');
            return;
        end

        data = parser.importRawImage(fp, Width=W, Height=H, BitDepth=B);
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: appendImage — Add a parsed data struct to appData.images
    % ════════════════════════════════════════════════════════════════════
    function appendImage(data)
        appData.images{end+1} = data;
        appData.imageContrastState{end+1} = [];   % no saved state yet
        appData.activeIdx = numel(appData.images);
        btnCompare.Enable = onOff(numel(appData.images) >= 2);
        btnEDSToolbar.Enable = onOff(numel(appData.images) >= 1);
    end

    % ════════════════════════════════════════════════════════════════════
    %  API: getImagesAPI / getActiveIdxAPI — nested-function accessors
    %  (Anonymous functions capture a snapshot; nested functions share
    %   the workspace by reference, so these always return current state.)
    % ════════════════════════════════════════════════════════════════════
    function imgs = getImagesAPI()
        imgs = appData.images;
    end

    function idx = getActiveIdxAPI()
        idx = appData.activeIdx;
    end

    function s = getPixelsAPI()
    %GETPIXELSAPI  Return current pixel arrays. Falls back to image struct.
        s.raw      = appData.rawPixels;
        s.filtered = appData.filteredPixels;
        s.display  = appData.displayImg;
        % If filteredPixels is empty but we have images, force displayImage
        if isempty(s.filtered) && appData.activeIdx > 0 && ...
                appData.activeIdx <= numel(appData.images)
            displayImage();
            s.raw      = appData.rawPixels;
            s.filtered = appData.filteredPixels;
            s.display  = appData.displayImg;
        end
    end

    function dims = getImageDimensionsAPI()
    %GETIMAGEDIMENSIONSAPI  Return [height, width] of active image.
        if ~isempty(appData.filteredPixels)
            dims = [size(appData.filteredPixels, 1), size(appData.filteredPixels, 2)];
        elseif appData.activeIdx > 0 && appData.activeIdx <= numel(appData.images)
            % Force displayImage to populate pixels
            displayImage();
            dims = [size(appData.filteredPixels, 1), size(appData.filteredPixels, 2)];
        else
            dims = [0, 0];
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  API: loadImagesAPI — Programmatic image loading (for testing)
    % ════════════════════════════════════════════════════════════════════
    function loadImagesAPI(paths)
    %LOADIMAGESAPI  Load images programmatically from a cell array of paths.
    %   For TIFF files, provide a string path.
    %   For RAW files, provide a struct with fields: path, Width, Height, BitDepth.
        if ischar(paths) || isstring(paths)
            paths = {paths};
        end

        loadedAny = false;
        for k = 1:numel(paths)
            entry = paths{k};

            try
                if isstruct(entry)
                    % RAW file with explicit dimensions
                    rawPath = entry.path;
                    data = parser.importRawImage(rawPath, ...
                        Width=entry.Width, Height=entry.Height, ...
                        BitDepth=entry.BitDepth);
                    appendImage(data);
                    loadedAny = true;
                elseif ischar(entry) || isstring(entry)
                    fp = char(entry);
                    [~, ~, ext] = fileparts(fp);
                    ext = lower(ext);

                    switch ext
                        case {'.tif', '.tiff'}
                            data = parser.importTIFF(fp);
                            appendImage(data);
                            loadedAny = true;
                        case {'.jpg', '.jpeg', '.png', '.bmp', '.gif'}
                            data = parser.importImage(fp);
                            appendImage(data);
                            loadedAny = true;
                        case '.bcf'
                            data = parser.importBCF(fp);
                            appendImage(data);
                            loadedAny = true;
                        case '.dm3'
                            data = parser.importDM3(fp);
                            appendImage(data);
                            loadedAny = true;
                        case '.dm4'
                            data = parser.importDM4(fp);
                            appendImage(data);
                            loadedAny = true;
                        case '.ser'
                            data = parser.importSER(fp);
                            appendImage(data);
                            loadedAny = true;
                        case {'.mrc', '.mrcs'}
                            data = parser.importMRC(fp);
                            appendImage(data);
                            loadedAny = true;
                        case {'.spm', '.000', '.001', '.002', '.003'}
                            data = parser.importAFM(fp);
                            appendImage(data);
                            loadedAny = true;
                        case '.raw'
                            error('FermiViewer:rawNeedsStruct', ...
                                ['RAW files in API mode require a struct with ' ...
                                 'fields: path, Width, Height, BitDepth.']);
                        otherwise
                            warning('FermiViewer:unsupported', ...
                                'Unsupported format: %s', ext);
                    end
                end
            catch ME
                warning('FermiViewer:loadFailed', ...
                    'Failed to load entry %d: %s', k, ME.message);
            end
        end

        if loadedAny
            rebuildImageList();
            displayImage();
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  API: setActiveIdxAPI — Switch to a specific image by index
    % ════════════════════════════════════════════════════════════════════
    function setActiveIdxAPI(idx)
        if idx < 1 || idx > numel(appData.images)
            warning('FermiViewer:invalidIdx', ...
                'Index %d is out of range [1, %d].', idx, numel(appData.images));
            return;
        end
        appData.activeIdx = idx;

        % Update listbox selection
        if ~isempty(lbImages.ItemsData) && ...
                ~isequal(lbImages.ItemsData, {0})
            lbImages.Value = {idx};
        end

        displayImage();
    end

    % ════════════════════════════════════════════════════════════════════
    %  STUB: stubNotImplemented — Placeholder for future phase features
    % ════════════════════════════════════════════════════════════════════
    function varargout = stubNotImplemented(funcName)
        warning('FermiViewer:notImplemented', ...
            '%s is not yet implemented (scheduled for a later phase).', funcName);
        if nargout > 0
            varargout{1} = [];
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onContrastChanged — Slider moved; update CData in-place
    % ════════════════════════════════════════════════════════════════════
    function onContrastChanged(src, ~)
        if isempty(appData.filteredPixels) || isempty(appData.imgHandle) || ...
                ~isvalid(appData.imgHandle)
            return;
        end

        lo = sldLow.Value;
        hi = sldHigh.Value;

        % Enforce lo < hi — determine which slider moved by checking the source
        if lo >= hi
            span = sldLow.Limits(2) - sldLow.Limits(1);
            eps  = span * 0.001;
            if ~isempty(src) && isequal(src, sldLow)
                % Low slider moved up past High — clamp just below High
                lo = max(sldLow.Limits(1), hi - eps);
                sldLow.Value = lo;
            else
                % High slider moved below Low — clamp just above Low
                hi = min(sldHigh.Limits(2), lo + eps);
                sldHigh.Value = hi;
            end
        end

        % Sync typed edit fields with slider values
        efLow.Value  = lo;
        efHigh.Value = hi;

        % Pipeline runs on the display buffer (full-res in fast mode;
        % downsampled in HQ mode). Huge win on 2k/4k images.
        if isempty(appData.displayPixels)
            prepareDisplayBuffer();
        end
        dispImg = applyContrastPipeline(appData.displayPixels, lo, hi);
        appData.displayImg = dispImg;

        % Update CData without recreating imagesc (preserves zoom/pan state)
        appData.imgHandle.CData = dispImg;

        % Update histogram contrast lines (single codepath avoids duplicates)
        refreshHistogramMarkers();
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onContrastEditChanged — unified typed-entry path for the
    %  Low, High, and Gamma numeric edit fields. Clamps to the respective
    %  slider limits, pushes to the slider, then runs the matching
    %  refresh (contrast pipeline or gamma pipeline). Kept as one nested
    %  function because the parser workspace is near its cap.
    % ════════════════════════════════════════════════════════════════════
    function onContrastEditChanged(src, ~)
        if isequal(src, efLow)
            v = max(sldLow.Limits(1), min(sldLow.Limits(2), efLow.Value));
            sldLow.Value = v;
            onContrastChanged(sldLow, []);
        elseif isequal(src, efHigh)
            v = max(sldHigh.Limits(1), min(sldHigh.Limits(2), efHigh.Value));
            sldHigh.Value = v;
            onContrastChanged(sldHigh, []);
        elseif isequal(src, efGamma)
            v = max(sldGamma.Limits(1), min(sldGamma.Limits(2), efGamma.Value));
            sldGamma.Value = v;
            appData.gamma = v;
            lblGamma.Text = 'Gamma';
            onContrastChanged([], []);
        elseif isequal(src, ddRenderMode)
            appData.renderMode = ddRenderMode.Value;
            appData.displayPixels = [];
            prepareDisplayBuffer();
            onContrastChanged([], []);
            if strcmp(appData.renderMode, 'hq')
                setStatus('Render mode: HQ (DM-style area-averaged downsample).');
            else
                setStatus('Render mode: Fast (full-res nearest-neighbor).');
            end
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onAutoContrast — Stretch to 2nd/98th percentile
    % ════════════════════════════════════════════════════════════════════
    function onAutoContrast(~, ~)
        if isempty(appData.filteredPixels)
            return;
        end

        pLow  = percentileNoToolbox(appData.filteredPixels(:), 2);
        pHigh = percentileNoToolbox(appData.filteredPixels(:), 98);

        % Guard against degenerate case
        if pLow >= pHigh
            pLow  = sldLow.Limits(1);
            pHigh = sldHigh.Limits(2);
        end

        sldLow.Value  = pLow;
        sldHigh.Value = pHigh;

        onContrastChanged([], []);
        setStatus(sprintf('Auto contrast: [%.4g, %.4g]', pLow, pHigh));
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onResetContrast — Full range (min to max of raw pixels)
    % ════════════════════════════════════════════════════════════════════
    function onResetContrast(~, ~)
        if isempty(appData.filteredPixels)
            return;
        end

        dMin = sldLow.Limits(1);
        dMax = sldHigh.Limits(2);

        sldLow.Value  = dMin;
        sldHigh.Value = dMax;

        % Also reset gamma to 1.0 — the gamma slider is visually coarse
        % and hard to return to exactly 1.0 by dragging.
        appData.gamma = 1.0;
        sldGamma.Value = 1.0;
        efGamma.Value = 1.0;
        lblGamma.Text = 'Gamma';

        % Contrast-only path — the filtered pixel buffer hasn't changed
        % so the downsampled display cache stays valid. onContrastChanged
        % reruns the cheap part of the pipeline (lo/hi remap + markers).
        onContrastChanged([], []);
        setStatus('Contrast reset to full range; gamma reset to 1.00.');
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onColormapChanged — Apply selected colormap to axes
    % ════════════════════════════════════════════════════════════════════
    function onColormapChanged(~, ~)
        if appData.activeIdx < 1
            return;
        end
        cmapName = ddColormap.Value;
        colormap(ax, feval(cmapName, 256));
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onGaussianFilter — Prompt for sigma and apply Gaussian blur
    % ════════════════════════════════════════════════════════════════════
    function onGaussianFilter(~, ~)
        if isempty(appData.filteredPixels)
            return;
        end

        answer = inputdlg({'Sigma (pixels):  [positive number, e.g. 1.5]'}, ...
            'Gaussian Filter', [1 44], {'1.5'});
        if isempty(answer)
            return;   % user cancelled
        end

        sigma = str2double(answer{1});
        if isnan(sigma) || sigma <= 0
            uialert(fig, 'Sigma must be a positive number.', ...
                'Invalid Input', 'Icon', 'error');
            return;
        end

        fig.Pointer = 'watch';
        drawnow;

        try
            undoPush();
            appData.filteredPixels = imaging.applyGaussian( ...
                appData.filteredPixels, Sigma=sigma);
            refreshDisplay();
            setStatus(sprintf('Gaussian filter applied (sigma = %.2g px)', sigma));
        catch ME
            uialert(fig, sprintf('Gaussian filter failed:\n%s', ME.message), ...
                'Filter Error', 'Icon', 'error');
        end

        fig.Pointer = 'arrow';
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onMedianFilter — Prompt for window size and apply median
    % ════════════════════════════════════════════════════════════════════
    function onMedianFilter(~, ~)
        if isempty(appData.filteredPixels)
            return;
        end

        answer = inputdlg({'Window size (3, 5, or 7):'}, ...
            'Median Filter', [1 36], {'3'});
        if isempty(answer)
            return;   % user cancelled
        end

        wSize = round(str2double(answer{1}));
        if isnan(wSize) || ~ismember(wSize, [3 5 7])
            uialert(fig, 'Window size must be 3, 5, or 7.', ...
                'Invalid Input', 'Icon', 'error');
            return;
        end

        fig.Pointer = 'watch';
        drawnow;

        try
            undoPush();
            appData.filteredPixels = imaging.applyMedian( ...
                appData.filteredPixels, WindowSize=wSize);
            refreshDisplay();
            setStatus(sprintf('Median filter applied (%dx%d window)', wSize, wSize));
        catch ME
            uialert(fig, sprintf('Median filter failed:\n%s', ME.message), ...
                'Filter Error', 'Icon', 'error');
        end

        fig.Pointer = 'arrow';
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onShowFFT — Compute and display FFT magnitude in new figure
    % ════════════════════════════════════════════════════════════════════
    function onShowFFT(~, ~)
        if isempty(appData.filteredPixels)
            return;
        end

        fig.Pointer = 'watch';
        drawnow;

        magImg = imaging.computeFFT(appData.filteredPixels);

        fig.Pointer = 'arrow';

        % Get filename for title
        if appData.activeIdx >= 1
            [~, fname, fext] = fileparts( ...
                appData.images{appData.activeIdx}.metadata.source);
            titleStr = sprintf('FFT — %s%s', fname, fext);
        else
            titleStr = 'FFT';
        end

        fftFig = figure('Name', titleStr, 'NumberTitle', 'off', ...
            'Units', 'pixels', 'Position', [220 180 600 520]);
        fftAx = axes(fftFig);
        imagesc(fftAx, magImg);
        colormap(fftFig, parula(256));
        colorbar(fftAx);
        axis(fftAx, 'image');
        fftAx.XTick = [];
        fftAx.YTick = [];
        title(fftAx, titleStr, 'Interpreter', 'none');

        setStatus('FFT displayed in new figure.');
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onUndoFilters — Revert filteredPixels back to rawPixels
    % ════════════════════════════════════════════════════════════════════
    function onUndoFilters(~, ~)
        if isempty(appData.rawPixels)
            return;
        end

        % Try multi-level undo stack first
        if ~isempty(appData.undoStack)
            undoPop();
            return;
        end

        % Fallback: if no undo stack, revert to raw
        appData.filteredPixels = appData.rawPixels;
        refreshDisplay();
        setStatus('Filters undone — reverted to original image.');
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onSaveImage — Save current displayImg to PNG or TIFF
    % ════════════════════════════════════════════════════════════════════
    function onSaveImage(~, ~)
        if isempty(appData.displayImg)
            uialert(fig, 'No image to save.', 'No Image', 'Icon', 'warning');
            return;
        end

        % Suggest default filename from active image
        if appData.activeIdx >= 1
            [~, bname] = fileparts( ...
                appData.images{appData.activeIdx}.metadata.source);
            defName = [bname '_processed.tif'];
        else
            defName = 'em_image.tif';
        end

        startPath = appData.lastDir;
        if isempty(startPath) || ~isfolder(startPath)
            startPath = pwd;
        end

        [saveName, saveDir] = uiputfile( ...
            {'*.tif;*.tiff', 'TIFF (*.tif, *.tiff)'; ...
             '*.png',        'PNG (*.png)'}, ...
            'Save Processed Image As', ...
            fullfile(startPath, defName));

        if isequal(saveName, 0)
            return;   % user cancelled
        end

        outPath = fullfile(saveDir, saveName);
        [~, ~, ext] = fileparts(outPath);

        fig.Pointer = 'watch';
        drawnow;

        try
            dispImg = appData.displayImg;   % [0,1] double
            if strcmpi(ext, '.png')
                % Scale to uint8 for PNG
                imwrite(uint8(dispImg * 255), outPath);
            else
                % Scale to uint16 for TIFF (better precision)
                imwrite(uint16(dispImg * 65535), outPath);
            end
            setStatus(sprintf('Saved: %s', saveName));
        catch ME
            uialert(fig, sprintf('Save failed:\n%s', ME.message), ...
                'Save Error', 'Icon', 'error');
        end

        fig.Pointer = 'arrow';
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onZoomBox — Draw rectangle to zoom into a region
    % ════════════════════════════════════════════════════════════════════
    function onZoomBox(~, ~)
        if appData.activeIdx < 1 || isempty(appData.displayImg)
            return;
        end
        startRectCapture('zoom');
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onResetZoom — Reset axes limits to full image
    % ════════════════════════════════════════════════════════════════════
    function onResetZoom(~, ~)
        if isempty(appData.displayImg)
            return;
        end
        [H, W] = size(appData.filteredPixels);
        ax.XLim = [0.5 W+0.5];
        ax.YLim = [0.5 H+0.5];
        setStatus('Zoom reset.');
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onCropImage — Draw rectangle to crop image
    % ════════════════════════════════════════════════════════════════════
    function onCropImage(~, ~)
        if appData.activeIdx < 1 || isempty(appData.displayImg)
            return;
        end
        startRectCapture('crop');
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onSaveCrop — Draw rectangle and save cropped region
    % ════════════════════════════════════════════════════════════════════
    function onSaveCrop(~, ~)
        if appData.activeIdx < 1 || isempty(appData.displayImg)
            return;
        end
        startRectCapture('savecrop');
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: startRectCapture — Two-click rectangle selection
    % ════════════════════════════════════════════════════════════════════
    function startRectCapture(mode)
        if ~isempty(appData.captureMode)
            cancelCapture();
        end

        appData.captureMode   = mode;
        appData.captureClicks = [];

        fig.Pointer = 'crosshair';
        fig.WindowButtonDownFcn = @onRectClick;

        switch mode
            case 'zoom'
                setStatus('Click first corner for zoom region... (Esc to cancel)');
            case 'crop'
                setStatus('Click first corner of crop region... (Esc to cancel)');
            case 'savecrop'
                setStatus('Click first corner of region to save... (Esc to cancel)');
            case 'roistats'
                setStatus('Click first corner for ROI... (Esc to cancel)');
            case 'batchcrop'
                setStatus('Click first corner of batch crop region... (Esc to cancel)');
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onRectClick — Handle clicks during rectangle selection
    % ════════════════════════════════════════════════════════════════════
    function onRectClick(~, ~)
        if ~ismember(appData.captureMode, {'zoom', 'crop', 'savecrop', 'roistats', 'batchcrop'})
            return;
        end

        cp = ax.CurrentPoint;
        x  = cp(1, 1);
        y  = cp(1, 2);

        % Clamp to image bounds
        [H, W] = size(appData.filteredPixels);
        x = max(0.5, min(W + 0.5, x));
        y = max(0.5, min(H + 0.5, y));

        appData.captureClicks(end+1, :) = [x, y];

        if size(appData.captureClicks, 1) == 1
            % First click — draw live preview rectangle
            hRect = rectangle(ax, 'Position', [x y 1 1], ...
                'EdgeColor', OVERLAY_COLOR, ...
                'LineWidth', 1.5, ...
                'LineStyle', '--', ...
                'HandleVisibility', 'off');
            appData.overlays.clickMarkers{end+1} = hRect;

            % Attach motion callback for live rubber-band
            fig.WindowButtonMotionFcn = @(~,~) updateRectPreview(hRect, ...
                appData.captureClicks(1,1), appData.captureClicks(1,2));

            switch appData.captureMode
                case 'zoom'
                    setStatus('Click second corner to zoom... (Esc to cancel)');
                case 'crop'
                    setStatus('Click second corner to crop... (Esc to cancel)');
                case 'savecrop'
                    setStatus('Click second corner to save... (Esc to cancel)');
                case 'roistats'
                    setStatus('Click second corner for ROI... (Esc to cancel)');
            end

        elseif size(appData.captureClicks, 1) >= 2
            % Both corners collected
            x1 = appData.captureClicks(1, 1);
            y1 = appData.captureClicks(1, 2);
            x2 = appData.captureClicks(2, 1);
            y2 = appData.captureClicks(2, 2);

            mode = appData.captureMode;

            % Clean up preview rectangle and restore callbacks
            fig.WindowButtonMotionFcn = @onMouseMotion;
            for ci = 1:numel(appData.overlays.clickMarkers)
                h = appData.overlays.clickMarkers{ci};
                if isvalid(h), delete(h); end
            end
            appData.overlays.clickMarkers = {};
            finishCapture();

            % Normalize to [xMin xMax yMin yMax]
            xMin = max(1, floor(min(x1, x2)));
            xMax = min(size(appData.displayImg, 2), ceil(max(x1, x2)));
            yMin = max(1, floor(min(y1, y2)));
            yMax = min(size(appData.displayImg, 1), ceil(max(y1, y2)));

            if xMax - xMin < 2 || yMax - yMin < 2
                setStatus('Selection too small — cancelled.');
                return;
            end

            switch mode
                case 'zoom'
                    ax.XLim = [xMin - 0.5, xMax + 0.5];
                    ax.YLim = [yMin - 0.5, yMax + 0.5];
                    setStatus(sprintf('Zoomed to [%d:%d, %d:%d]', ...
                        xMin, xMax, yMin, yMax));

                case 'crop'
                    undoPush();
                    appData.rawPixels      = appData.rawPixels(yMin:yMax, xMin:xMax);
                    appData.filteredPixels = appData.filteredPixels(yMin:yMax, xMin:xMax);
                    refreshDisplay();
                    setStatus(sprintf('Cropped to %dx%d px', ...
                        xMax - xMin + 1, yMax - yMin + 1));

                case 'savecrop'
                    saveCroppedRegion(xMin, xMax, yMin, yMax);

                case 'roistats'
                    showROIStatistics(xMin, xMax, yMin, yMax);

                case 'batchcrop'
                    applyBatchCrop(xMin, xMax, yMin, yMax);
            end
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: updateRectPreview — Update rubber-band rectangle on motion
    % ════════════════════════════════════════════════════════════════════
    function updateRectPreview(hRect, x0, y0)
        if ~isvalid(hRect), return; end
        cp = ax.CurrentPoint;
        cx = cp(1,1);
        cy = cp(1,2);
        rx = min(x0, cx);
        ry = min(y0, cy);
        rw = abs(cx - x0);
        rh = abs(cy - y0);
        if rw < 0.5, rw = 0.5; end
        if rh < 0.5, rh = 0.5; end
        hRect.Position = [rx ry rw rh];
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: saveCroppedRegion — Save a rectangular crop, blocking
    %  overwrite of the original source file
    % ════════════════════════════════════════════════════════════════════
    function saveCroppedRegion(xMin, xMax, yMin, yMax)
        % Build default filename with _crop suffix
        if appData.activeIdx >= 1
            srcPath = appData.images{appData.activeIdx}.metadata.source;
            [srcDir, bname] = fileparts(srcPath);
            defName = [bname '_crop.tif'];
        else
            srcPath = '';
            srcDir  = '';
            defName = 'crop.tif';
        end

        startPath = appData.lastDir;
        if isempty(startPath) || ~isfolder(startPath)
            if ~isempty(srcDir) && isfolder(srcDir)
                startPath = srcDir;
            else
                startPath = pwd;
            end
        end

        [saveName, saveDir] = uiputfile( ...
            {'*.tif;*.tiff', 'TIFF (*.tif, *.tiff)'; ...
             '*.png',        'PNG (*.png)'}, ...
            'Save Cropped Region As', ...
            fullfile(startPath, defName));

        if isequal(saveName, 0)
            setStatus('Save cancelled.');
            return;
        end

        outPath = fullfile(saveDir, saveName);

        % Block overwrite of original source file (pure-MATLAB, no Java)
        if ~isempty(srcPath)
            srcResolved = fullfile(srcPath);
            outResolved = fullfile(outPath);
            if strcmpi(srcResolved, outResolved)
                uialert(fig, ...
                    'Cannot overwrite the original source file. Choose a different name.', ...
                    'Overwrite Blocked', 'Icon', 'warning');
                return;
            end
        end

        [~, ~, ext] = fileparts(outPath);

        fig.Pointer = 'watch';
        drawnow;

        try
            % Crop from filteredPixels (includes any applied filters)
            cropPx = appData.filteredPixels(yMin:yMax, xMin:xMax);

            % Scale to display range using current contrast
            lo = sldLow.Value;
            hi = sldHigh.Value;
            if hi <= lo, hi = lo + 1; end
            cropDisp = (cropPx - lo) / (hi - lo);
            cropDisp = max(0, min(1, cropDisp));

            if strcmpi(ext, '.png')
                imwrite(uint8(cropDisp * 255), outPath);
            else
                imwrite(uint16(cropDisp * 65535), outPath);
            end
            setStatus(sprintf('Crop saved: %s (%dx%d)', saveName, ...
                xMax - xMin + 1, yMax - yMin + 1));
        catch ME
            uialert(fig, sprintf('Save crop failed:\n%s', ME.message), ...
                'Save Error', 'Icon', 'error');
        end

        fig.Pointer = 'arrow';
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: showROIStatistics — Compute and display ROI statistics
    % ════════════════════════════════════════════════════════════════════
    function showROIStatistics(xMin, xMax, yMin, yMax)
        roiPx = appData.filteredPixels(yMin:yMax, xMin:xMax);
        vals = double(roiPx(:));

        roiMean = mean(vals);
        roiStd  = std(vals);
        roiMin  = min(vals);
        roiMax  = max(vals);
        roiArea = numel(vals);

        % Calibrated area if available
        areaStr = sprintf('%d px²', roiArea);
        if appData.activeIdx >= 1
            imgInfo = appData.images{appData.activeIdx}.metadata.parserSpecific.imageData;
            if imgInfo.calibrated && ~isnan(imgInfo.pixelSize)
                calibArea = roiArea * imgInfo.pixelSize^2;
                areaStr = sprintf('%.4g %s²', calibArea, imgInfo.pixelUnit);
            end
        end

        % Build stats text
        statsLines = { ...
            sprintf('ROI: [%d:%d, %d:%d]', xMin, xMax, yMin, yMax), ...
            sprintf('Size: %d x %d px', xMax - xMin + 1, yMax - yMin + 1), ...
            sprintf('Area: %s', areaStr), ...
            '', ...
            sprintf('Mean:  %.4g', roiMean), ...
            sprintf('Std:   %.4g', roiStd), ...
            sprintf('Min:   %.4g', roiMin), ...
            sprintf('Max:   %.4g', roiMax), ...
            sprintf('Range: %.4g', roiMax - roiMin)};

        % Show in a figure with histogram
        roiFig = figure('Name', 'ROI Statistics', 'NumberTitle', 'off', ...
            'Units', 'pixels', 'Position', [300 250 420 380]);
        roiLayout = uigridlayout(roiFig, [2 1], ...
            'RowHeight', {'1x', '1x'}, 'Padding', [10 10 10 10]);

        % Top: histogram
        roiAx = uiaxes(roiLayout);
        roiAx.Layout.Row = 1;
        histogram(roiAx, vals, 128, ...
            'FaceColor', [0.4 0.6 0.8], 'EdgeColor', 'none');
        title(roiAx, 'ROI Histogram', 'Interpreter', 'none');
        xlabel(roiAx, 'Intensity');
        ylabel(roiAx, 'Count');
        roiAx.Box = 'on';

        % Bottom: stats text
        taStats = uitextarea(roiLayout, ...
            'Value', statsLines, ...
            'Editable', 'off', ...
            'FontName', 'Courier New', ...
            'FontSize', 11);
        taStats.Layout.Row = 2;

        % Draw the ROI rectangle on the main image (persistent overlay)
        hRect = rectangle(ax, 'Position', [xMin yMin xMax-xMin yMax-yMin], ...
            'EdgeColor', [1 1 0], ...
            'LineWidth', 1.5, ...
            'LineStyle', '-', ...
            'HandleVisibility', 'off');
        appData.overlays.lines{end+1} = hRect;

        % Log to measurement table
        appData.measurementLog{end+1} = struct( ...
            'type', 'ROI', ...
            'value', roiMean, ...
            'unit', 'intensity', ...
            'details', sprintf('[%d:%d, %d:%d] mean=%.4g std=%.4g min=%.4g max=%.4g area=%s', ...
                xMin, xMax, yMin, yMax, roiMean, roiStd, roiMin, roiMax, areaStr), ...
            'timestamp', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')));

        % Add to ROI list for ROI Manager
        roiEntry = struct('name', sprintf('ROI_%d', numel(appData.roiList)+1), ...
            'xMin', xMin, 'xMax', xMax, 'yMin', yMin, 'yMax', yMax, ...
            'stats', struct('mean', roiMean, 'std', roiStd, 'min', roiMin, ...
                            'max', roiMax, 'area', roiArea), ...
            'areaStr', areaStr, 'hRect', hRect);
        appData.roiList{end+1} = roiEntry;

        setStatus(sprintf('ROI: mean=%.1f, std=%.1f, min=%.0f, max=%.0f', ...
            roiMean, roiStd, roiMin, roiMax));
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: refreshDisplay — Re-apply contrast to filteredPixels; update
    %  histogram and CData without resetting zoom
    % ════════════════════════════════════════════════════════════════════
    function refreshDisplay()
        if isempty(appData.filteredPixels) || isempty(appData.imgHandle) || ...
                ~isvalid(appData.imgHandle)
            return;
        end

        lo = sldLow.Value;
        hi = sldHigh.Value;

        % Called after filter / crop / rotate / undo changes to the
        % filteredPixels buffer. Always rebuild displayPixels here because
        % we can't cheaply detect value changes at same size (CLAHE, blur,
        % morph, etc.). Contrast/gamma-only paths use refreshContrastOnly
        % (cheaper — skips the rebuild).
        appData.displayPixels = [];
        prepareDisplayBuffer();
        dispImg = applyContrastPipeline(appData.displayPixels, lo, hi);

        appData.displayImg = dispImg;
        appData.imgHandle.CData = dispImg;

        % Only refresh the marker lines on contrast changes — rebuilding the
        % full histogram bars is O(N) on raw pixels and was firing on every
        % slider tick. updateHistogram() still runs on image-load paths.
        refreshHistogramMarkers();

        % Update minimap if active
        if cbMinimap.Value && ~isempty(hMinimap) && isvalid(hMinimap)
            updateMinimapRect();
        end

        % Update live FFT if active
        if ~isempty(appData.liveFFTFig) && isvalid(appData.liveFFTFig)
            updateLiveFFT();
        end

        % Restore scale bar if checkbox is still ticked.  The bar
        % position is stored in image-pixel coordinates so it must be
        % rebuilt any time filteredPixels changes (filter, crop, undo).
        if ~isempty(cbScaleBar) && isvalid(cbScaleBar) && ...
                strcmp(cbScaleBar.Enable, 'on') && cbScaleBar.Value
            rebuildScaleBar();
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: prepareDisplayBuffer — Build appData.displayPixels from
    %  appData.filteredPixels according to the current renderMode and
    %  axes zoom/size. In 'hq' mode, area-averages to axes pixel size so
    %  the image renders crisply (DM-style) and the contrast pipeline
    %  runs on a small buffer. In 'fast' mode, uses filteredPixels as-is.
    %
    %  When `pushToImage` is true, also runs the contrast pipeline and
    %  updates imgHandle.CData — used by the zoom listener to rebuild
    %  on viewport change without needing a second nested function.
    % ════════════════════════════════════════════════════════════════════
    function prepareDisplayBuffer(pushToImage)
        if nargin < 1, pushToImage = false; end
        if isempty(appData.filteredPixels)
            appData.displayPixels = [];
            return;
        end
        % Listener path: skip if no image drawn yet or Fast mode already
        % renders at native resolution (no rebuild needed on zoom).
        if pushToImage && (isempty(appData.imgHandle) || ...
                ~isvalid(appData.imgHandle) || ...
                ~strcmp(appData.renderMode, 'hq'))
            return;
        end

        [H, W] = size(appData.filteredPixels);
        x0 = 1; x1 = W; y0 = 1; y1 = H;    % default region = full image

        if strcmp(appData.renderMode, 'fast')
            % Fast mode — no preprocessing, CData spans full native pixels.
            appData.displayPixels = double(appData.filteredPixels);
        else
            % HQ mode — area-average the VISIBLE region to roughly 1.5×
            % axes pixel size (a little oversampling so minor zoom-in
            % doesn't immediately reveal downsample blocks).
            xLim = ax.XLim; yLim = ax.YLim;
            x0 = max(1, floor(xLim(1))); x1 = min(W, ceil(xLim(2)));
            y0 = max(1, floor(yLim(1))); y1 = min(H, ceil(yLim(2)));
            if x1 <= x0 || y1 <= y0
                x0 = 1; x1 = W; y0 = 1; y1 = H;
            end

            region = appData.filteredPixels(y0:y1, x0:x1);
            regH = y1 - y0 + 1;
            regW = x1 - x0 + 1;

            axPos = ax.InnerPosition;
            axW   = round(axPos(3));
            axH   = round(axPos(4));

            % Guard: InnerPosition returns [0 0 0 0] (or near-zero) before
            % the uifigure Chromium renderer completes its first layout pass.
            % Downsampling to a tiny buffer at this point would produce
            % catastrophic blur — the miniature buffer gets bilinearly
            % stretched across the full viewport by MATLAB's imagesc. Skip
            % downsampling entirely and let the zoom-listener rebuild the
            % buffer correctly after the first render pass.
            if axW < 100 || axH < 100
                appData.displayPixels = double(region);
            else
                targetW = round(axW * 1.5);
                targetH = round(axH * 1.5);

                if regH > targetH || regW > targetW
                    appData.displayPixels = imaging.areaDownsample(region, ...
                        min(regH, targetH), min(regW, targetW));
                else
                    appData.displayPixels = double(region);
                end
            end
        end

        % Always record the image-coordinate bounds of the display buffer.
        % The initial imagesc() call (and any direct CData update) must use
        % these as XData/YData so MATLAB maps the downsampled pixels to the
        % correct coordinate extent — not the full native extent, which would
        % bilinearly upscale the buffer and blur atomic-resolution detail.
        appData.displayRegion = [x0, y0, x1, y1];

        if pushToImage && ~isempty(appData.imgHandle) && isvalid(appData.imgHandle)
            lo = sldLow.Value; hi = sldHigh.Value;
            dispImg = applyContrastPipeline(appData.displayPixels, lo, hi);
            appData.displayImg = dispImg;
            % The CData represents the [y0..y1, x0..x1] sub-region at
            % downsample resolution; XData/YData must describe that
            % region in axes (= native image pixel) coordinates so
            % overlays, measurements, and zoom math stay aligned.
            appData.imgHandle.XData = [x0, x1];
            appData.imgHandle.YData = [y0, y1];
            appData.imgHandle.CData = dispImg;
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: updateHistogram — Draw histogram of raw pixels in histAx
    % ════════════════════════════════════════════════════════════════════
    function updateHistogram()
        if isempty(appData.rawPixels)
            cla(histAx);
            return;
        end

        % Compute histogram of raw (unfiltered) pixels for stable reference
        [counts, edges] = histcounts(double(appData.rawPixels(:)), 256);
        binCenters = (edges(1:end-1) + edges(2:end)) / 2;

        cla(histAx);
        bar(histAx, binCenters, counts, 1, ...
            'FaceColor', [0.5 0.5 0.5], ...
            'EdgeColor', 'none', ...
            'FaceAlpha', 0.8);

        % Pin limits to the data range. The init block sets XLim/YLim=[0 1]
        % which flips *LimMode to 'manual', so bar() no longer auto-scales
        % and the histogram renders off-screen (empty box).
        if edges(end) > edges(1)
            histAx.XLim = [edges(1), edges(end)];
        end
        yMax = max(counts);
        if yMax > 0
            histAx.YLim = [0, yMax * 1.05];
        end

        histAx.XTick = [];
        histAx.YTick = [];
        histAx.FontSize = 8;
        histAx.Box = 'on';
        histAx.Toolbar.Visible = 'off';

        % Draw Low/High contrast marker lines
        if ~isempty(appData.filteredPixels)
            refreshHistogramMarkers();
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: updateHistogramLines — Draw/update contrast marker lines
    % ════════════════════════════════════════════════════════════════════
    function updateHistogramLines(lo, hi)
        % Remove old contrast lines (tagged with UserData='contrastLine')
        kids = histAx.Children;
        for ki = numel(kids):-1:1
            h = kids(ki);
            if isvalid(h) && isprop(h, 'UserData') && ...
                    isequal(h.UserData, 'contrastLine')
                delete(h);
            end
        end

        yLim = histAx.YLim;
        if yLim(2) == 0
            yLim(2) = 1;
        end

        % Low line
        hLo = line(histAx, [lo lo], yLim, ...
            'Color',            [1 0.2 0.2], ...
            'LineStyle',        '--', ...
            'LineWidth',        1.5, ...
            'HandleVisibility', 'off');
        hLo.UserData = 'contrastLine';

        % High line
        hHi = line(histAx, [hi hi], yLim, ...
            'Color',            [1 0.2 0.2], ...
            'LineStyle',        '--', ...
            'LineWidth',        1.5, ...
            'HandleVisibility', 'off');
        hHi.UserData = 'contrastLine';
    end

    % ════════════════════════════════════════════════════════════════════
    %  API: setContrastAPI — Programmatic contrast adjustment
    % ════════════════════════════════════════════════════════════════════
    function setContrastAPI(lo, hi)
    %SETCONTRASTAPI  Set Low/High contrast sliders and refresh display.
        if isempty(appData.filteredPixels)
            warning('FermiViewer:noImage', 'No image loaded.');
            return;
        end

        % Validate the user's requested ordering first. Only reject
        % genuinely malformed input (non-finite or lo >= hi) — do NOT
        % reject a well-ordered window just because it straddles the
        % slider limits, since those limits track the actual data range
        % and may exclude legitimate requested bounds.
        if ~isfinite(lo) || ~isfinite(hi) || lo >= hi
            warning('FermiViewer:invalidContrast', ...
                'Low must be finite and less than High. Values unchanged.');
            return;
        end

        dMin = sldLow.Limits(1);
        dMax = sldHigh.Limits(2);

        loC = max(dMin, min(dMax, lo));
        hiC = max(dMin, min(dMax, hi));

        % If clamping collapsed the pair, the requested window lies
        % entirely outside the data range. Snap to the nearest edge with
        % a minimal span so the call still has a sensible effect.
        if loC >= hiC
            span = max(eps(dMax), (dMax - dMin) * 1e-6);
            if hi <= dMin           % window entirely below data range
                loC = dMin;
                hiC = min(dMax, dMin + span);
            elseif lo >= dMax       % window entirely above data range
                hiC = dMax;
                loC = max(dMin, dMax - span);
            else                     % degenerate data range — open fully
                loC = dMin;
                hiC = dMax;
            end
        end

        sldLow.Value  = loC;
        sldHigh.Value = hiC;
        onContrastChanged([], []);
    end

    % ════════════════════════════════════════════════════════════════════
    %  API: setPixelSizeAPI — Programmatic pixel calibration override
    % ════════════════════════════════════════════════════════════════════
    function setPixelSizeAPI(sz, unit)
    %SETPIXELSIZEAPI  Override pixel calibration from API.
    %   api.setPixelSize(2.4, 'nm')
        if appData.activeIdx < 1
            warning('FermiViewer:noImage', 'No image loaded.');
            return;
        end
        appData.images{appData.activeIdx}.metadata.parserSpecific.imageData.pixelSize  = sz;
        appData.images{appData.activeIdx}.metadata.parserSpecific.imageData.pixelUnit  = unit;
        appData.images{appData.activeIdx}.metadata.parserSpecific.imageData.calibrated = true;
        updateStatusBar();
        updateMetadataPanel();
    end

    % ════════════════════════════════════════════════════════════════════
    %  API: applyFilterAPI — Programmatic filter application
    % ════════════════════════════════════════════════════════════════════
    function applyFilterAPI(type, params)
    %APPLYFILTERAPI  Apply a named filter programmatically.
    %   api.applyFilter('gaussian', struct('Sigma', 1.5))
    %   api.applyFilter('median',   struct('WindowSize', 3))
        if isempty(appData.filteredPixels)
            warning('FermiViewer:noImage', 'No image loaded.');
            return;
        end

        switch lower(type)
            case 'gaussian'
                sigma = 1.0;
                if isstruct(params) && isfield(params, 'Sigma')
                    sigma = params.Sigma;
                end
                appData.filteredPixels = imaging.applyGaussian( ...
                    appData.filteredPixels, Sigma=sigma);

            case 'median'
                wSize = 3;
                if isstruct(params) && isfield(params, 'WindowSize')
                    wSize = params.WindowSize;
                end
                appData.filteredPixels = imaging.applyMedian( ...
                    appData.filteredPixels, WindowSize=wSize);

            otherwise
                warning('FermiViewer:unknownFilter', ...
                    'Unknown filter type "%s". Use ''gaussian'' or ''median''.', type);
                return;
        end

        refreshDisplay();
    end

    % ════════════════════════════════════════════════════════════════════
    %  API: computeFFTAPI — Programmatic FFT computation (no figure)
    % ════════════════════════════════════════════════════════════════════
    function result = computeFFTAPI()
    %COMPUTEFFTAPI  Compute FFT of filtered pixels without opening a figure.
    %   result = api.computeFFT()
    %   Returns struct with .magnitude ([HxW] double) and .phase ([HxW] double).
        result = struct('magnitude', [], 'phase', []);

        if isempty(appData.filteredPixels)
            warning('FermiViewer:noImage', 'No image loaded.');
            return;
        end

        [mag, ph] = imaging.computeFFT(appData.filteredPixels);
        result.magnitude = mag;
        result.phase     = ph;
    end

    % ════════════════════════════════════════════════════════════════════
    %  API: exportImageAPI — Programmatic image save
    % ════════════════════════════════════════════════════════════════════
    function exportImageAPI(outPath)
    %EXPORTIMAGEAPI  Save the current displayImg to a file path.
    %   api.exportImage('output.tif')  or  api.exportImage('output.png')
        if isempty(appData.displayImg)
            warning('FermiViewer:noImage', 'No image loaded.');
            return;
        end

        [~, ~, ext] = fileparts(outPath);

        dispImg = appData.displayImg;   % [0,1] double
        if strcmpi(ext, '.png')
            imwrite(uint8(dispImg * 255), outPath);
        else
            imwrite(uint16(dispImg * 65535), outPath);
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onScaleBarToggle — Add or remove scale bar overlay
    % ════════════════════════════════════════════════════════════════════
    function onScaleBarToggle(~, ~)
        if appData.activeIdx < 1
            return;
        end

        if cbScaleBar.Value
            rebuildScaleBar();
        else
            deleteScaleBar();
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onScaleBarColorToggle — Switch between white and black
    % ════════════════════════════════════════════════════════════════════
    function onScaleBarColorToggle(~, ~)
        if strcmp(appData.scaleBarColor, 'white')
            appData.scaleBarColor = 'black';
            btnScaleBarColor.Text            = 'Black';
            btnScaleBarColor.FontColor       = [0 0 0];
            btnScaleBarColor.BackgroundColor = [0.85 0.85 0.85];
        else
            appData.scaleBarColor = 'white';
            btnScaleBarColor.Text            = 'White';
            btnScaleBarColor.FontColor       = [1 1 1];
            btnScaleBarColor.BackgroundColor = [0.25 0.25 0.25];
        end
        if cbScaleBar.Value
            rebuildScaleBar();
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onScaleBarFontChange — Update font size
    % ════════════════════════════════════════════════════════════════════
    function onScaleBarFontChange(~, ~)
        % Shared callback for font-size, length-override, and unit-dropdown
        if cbScaleBar.Value
            rebuildScaleBar();
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: rebuildScaleBar — Delete and recreate with current settings
    % ════════════════════════════════════════════════════════════════════
    function rebuildScaleBar()
        deleteScaleBar();

        % Read from SSoT (appData.scaleBarColor), not the button styling
        if strcmp(appData.scaleBarColor, 'white')
            barColor = [1 1 1];
        else
            barColor = [0 0 0];
        end
        fontSize = spnScaleBarFont.Value;

        % Length override: editfield value > 0 with a non-auto unit
        lenVal  = efScaleBarLen.Value;
        unitVal = ddScaleBarUnit.Value;
        useLen  = lenVal > 0 && isfinite(lenVal) && ~strcmp(unitVal, 'auto');
        if useLen
            lenArgs = {'BarLength', lenVal, 'BarUnit', string(unitVal)};
        else
            lenArgs = {};
        end

        if appData.compareMode
            % Add scale bars to both compare axes
            for panelChar = ['L', 'R']
                if panelChar == 'L'
                    tgtAx = axL;  idx = appData.compareIdxL;
                else
                    tgtAx = axR;  idx = appData.compareIdxR;
                end
                if isempty(tgtAx) || ~isvalid(tgtAx), continue; end
                if idx < 1 || idx > numel(appData.images), continue; end
                imgI = appData.images{idx}.metadata.parserSpecific.imageData;
                if ~imgI.calibrated, continue; end
                hB = imaging.addScaleBar(tgtAx, imgI.pixelSize, imgI.pixelUnit, ...
                    'Color', barColor, 'FontSize', fontSize, lenArgs{:});
                makeScaleBarDraggable(hB);
                if panelChar == 'L'
                    appData.overlays.scalebarL = hB;
                else
                    appData.overlays.scalebarR = hB;
                end
            end
        else
            if appData.activeIdx < 1, return; end
            imgInfo = appData.images{appData.activeIdx}.metadata.parserSpecific.imageData;
            hBar = imaging.addScaleBar(ax, imgInfo.pixelSize, imgInfo.pixelUnit, ...
                'Color', barColor, 'FontSize', fontSize, lenArgs{:});
            appData.overlays.scalebar = hBar;
            makeScaleBarDraggable(hBar);
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onLineProfile — Start two-click line profile capture
    % ════════════════════════════════════════════════════════════════════
    function onLineProfile(~, ~)
        if appData.activeIdx < 1 || isempty(appData.displayImg)
            return;
        end
        startTwoClickCapture('profile');
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onDistance — Start two-click distance capture
    % ════════════════════════════════════════════════════════════════════
    function onDistance(~, ~)
        if appData.activeIdx < 1 || isempty(appData.displayImg)
            return;
        end
        startTwoClickCapture('distance');
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onExportProfile — Save last line profile to CSV
    % ════════════════════════════════════════════════════════════════════
    function onExportProfile(~, ~)
        if isempty(appData.lastProfile.dist)
            uialert(fig, 'No line profile available. Use "Line Profile" first.', ...
                'No Profile', 'Icon', 'warning');
            return;
        end

        % Suggest filename from the active image
        if appData.activeIdx >= 1
            [~, bname] = fileparts(appData.images{appData.activeIdx}.metadata.source);
            defName = [bname '_profile.csv'];
        else
            defName = 'line_profile.csv';
        end

        startPath = appData.lastDir;
        if isempty(startPath) || ~isfolder(startPath)
            startPath = pwd;
        end

        [saveName, saveDir] = uiputfile('*.csv', 'Save Line Profile As', ...
            fullfile(startPath, defName));

        if isequal(saveName, 0)
            return;   % user cancelled
        end

        outPath = fullfile(saveDir, saveName);

        % Build matrix: [distance, intensity]
        distCol  = appData.lastProfile.dist(:);
        intCol   = appData.lastProfile.intensity(:);
        M = [distCol, intCol];

        % Write with a header comment row
        unitStr = appData.lastProfile.unit;
        header  = sprintf('Distance (%s),Intensity', unitStr);

        try
            fid = fopen(outPath, 'w');
            if fid == -1
                error('FermiViewer:exportFailed', 'Cannot open file for writing: %s', outPath);
            end
            fprintf(fid, '%s\n', header);
            fclose(fid);
            writematrix(M, outPath, 'WriteMode', 'append');
            setStatus(sprintf('Profile saved: %s', saveName));
        catch ME
            uialert(fig, sprintf('Export failed:\n%s', ME.message), ...
                'Export Error', 'Icon', 'error');
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onClearOverlays — Remove all measurement overlays
    % ════════════════════════════════════════════════════════════════════
    function onClearOverlays(~, ~)
        % Cancel capture in progress
        if ~isempty(appData.captureMode)
            cancelCapture();
        end
        clearAllOverlays();
        cbScaleBar.Value = false;
        setStatus('All overlays cleared.');
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onCaptureClick — Handle clicks during two-click capture
    % ════════════════════════════════════════════════════════════════════
    function onCaptureClick(~, ~)
        if isempty(appData.captureMode)
            return;
        end

        % Get click position in data (image pixel) coordinates
        cp = ax.CurrentPoint;
        x  = cp(1, 1);
        y  = cp(1, 2);

        % Validate within image bounds
        if isempty(appData.displayImg)
            return;
        end
        [H, W] = size(appData.filteredPixels);
        x = max(0.5, min(W + 0.5, x));
        y = max(0.5, min(H + 0.5, y));

        % Draw click marker
        hMark = line(ax, x, y, ...
            'Marker',           'o', ...
            'MarkerSize',       6, ...
            'Color',            OVERLAY_COLOR, ...
            'MarkerFaceColor',  OVERLAY_COLOR, ...
            'LineStyle',        'none', ...
            'HandleVisibility', 'off');
        appData.overlays.clickMarkers{end+1} = hMark;

        % Handle single-click modes that accumulate without a fixed endpoint
        if strcmp(appData.captureMode, 'diffspot')
            newSpot = [y, x];  % [row, col]
            appData.diffSpots = [appData.diffSpots; newSpot];
            drawDiffSpots();
            lblSpotCount.Text = sprintf('%d spots', size(appData.diffSpots, 1));
            return;
        end

        if strcmp(appData.captureMode, 'specnav')
            % Navigate spectrum image pixel — single click, stays active
            col = round(x); row = round(y);
            [Ny, Nx, ~] = size(appData.eelsCube);
            if row >= 1 && row <= Ny && col >= 1 && col <= Nx
                spec = squeeze(double(appData.eelsCube(row, col, :)));
                delete(findobj(ax, 'Tag', 'specnav_marker'));
                hold(ax, 'on');
                plot(ax, col, row, 'r+', 'MarkerSize', 15, 'LineWidth', 2, ...
                    'Tag', 'specnav_marker', 'HandleVisibility', 'off');
                hold(ax, 'off');
                if ~isempty(appData.eelsFig) && isvalid(appData.eelsFig)
                    ax2 = findobj(appData.eelsFig, 'Type', 'axes');
                    if ~isempty(ax2)
                        cla(ax2(1));
                        plot(ax2(1), appData.eelsEnergyAxis, spec, 'k-', 'LineWidth', 1);
                        xlabel(ax2(1), 'Energy Loss (eV)'); ylabel(ax2(1), 'Counts');
                        title(ax2(1), sprintf('Pixel [%d, %d]', row, col));
                        grid(ax2(1), 'on');
                    end
                end
                setStatus(sprintf('Pixel [%d,%d]: max=%.0f', row, col, max(spec)));
            end
            return;
        end

        if strcmp(appData.captureMode, 'vdf_select')
            % Virtual dark-field — single click selects the FFT spot
            col = round(x); row = round(y);
            idx = appData.activeIdx;
            if idx > 0 && idx <= numel(appData.images)
                pixels = double(appData.images{idx}.metadata.parserSpecific.imageData.pixels);
                try
                    vdf = imaging.virtualDarkField(pixels, 'MaskCenter', [row col], 'MaskRadius', 10);
                    imagesc(ax, vdf); colormap(ax, 'gray'); axis(ax, 'image');
                    title(ax, sprintf('VDF at [%d,%d]', row, col));
                catch ME
                    setStatus(sprintf('VDF failed: %s', ME.message));
                end
            end
            appData.captureMode = '';
            fig.WindowButtonDownFcn = @onIdleMouseDown;
            fig.Pointer = 'arrow';
            return;
        end

        % Accumulate clicks
        appData.captureClicks(end+1, :) = [x, y];

        if size(appData.captureClicks, 1) == 1
            % First click recorded — wait for second
            if strcmp(appData.captureMode, 'scalebar')
                setStatus('Click other end of scale bar... (Escape to cancel)');
            else
                setStatus('Click second point on the image... (Escape to cancel)');
            end

        elseif size(appData.captureClicks, 1) >= 2
            % Both clicks collected — execute the measurement
            x1 = appData.captureClicks(1, 1);
            y1 = appData.captureClicks(1, 2);
            x2 = appData.captureClicks(2, 1);
            y2 = appData.captureClicks(2, 2);

            mode = appData.captureMode;

            % Restore normal interaction
            finishCapture();

            switch mode
                case 'profile'
                    executeMeasureProfile(x1, y1, x2, y2);
                case 'distance'
                    executeMeasureDistance(x1, y1, x2, y2);
                case 'scalebar'
                    executeScaleBarCalibration(x1, y1, x2, y2);
                case 'dspacing'
                    executeDSpacing(x1, y1, x2, y2);
                case 'roiellipse'
                    executeEllipseROI(x1, y1, x2, y2);
                case 'arrow'
                    executeArrow(x1, y1, x2, y2);
                case 'annotline'
                    executeAnnotLine(x1, y1, x2, y2);
                case 'annotrect'
                    executeAnnotRect(x1, y1, x2, y2);
                case 'annotcircle'
                    executeAnnotCircle(x1, y1, x2, y2);
                case 'lattice'
                    appData.captureClicks = [appData.captureClicks; x1, y1; x2, y2];
                    executeLattice();
                case 'gpa'
                    appData.captureClicks = [appData.captureClicks; x1, y1; x2, y2];
                    executeGPA();
                case 'edsprofile'
                    p1 = [x1, y1];
                    p2 = [x2, y2];
                    profile = imaging.edsCompositionProfile(appData.edsAtomicPct, ...
                        appData.edsElements, p1(1), p1(2), p2(1), p2(2));
                    profFig = figure('Name', 'Composition Profile');
                    ax2 = axes(profFig);
                    plot(ax2, profile.distance, profile.atomicPct, 'LineWidth', 1.5);
                    xlabel(ax2, sprintf('Distance (%s)', profile.unit));
                    ylabel(ax2, 'Atomic %%');
                    legend(ax2, appData.edsElements);
                    title(ax2, 'EDS Composition Profile');
                    grid(ax2, 'on');
                    setStatus('Profile extracted');
                case 'edsroi'
                    c1 = max(1, min(round(x1), round(x2)));
                    c2 = min(size(appData.edsAtomicPct{1},2), max(round(x1), round(x2)));
                    r1 = max(1, min(round(y1), round(y2)));
                    r2 = min(size(appData.edsAtomicPct{1},1), max(round(y1), round(y2)));
                    msg = 'ROI Composition: ';
                    for kq = 1:numel(appData.edsElements)
                        roi = appData.edsAtomicPct{kq}(r1:r2, c1:c2);
                        msg = [msg sprintf('%s=%.1f%% ', appData.edsElements{kq}, mean(roi(:), 'omitnan'))]; %#ok<AGROW>
                    end
                    setStatus(msg);
            end
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onKeyPress — Escape, arrow navigation, Tab (compare)
    % ════════════════════════════════════════════════════════════════════
    function onKeyPress(~, evt)
        % Escape cancels any in-progress capture
        if strcmp(evt.Key, 'escape') && ~isempty(appData.captureMode)
            cancelCapture();
            setStatus('Capture cancelled.');
            return;
        end

        % Don't navigate during capture
        if ~isempty(appData.captureMode)
            return;
        end

        nImages = numel(appData.images);

        % ── Compare mode: Tab switches panel, arrows scroll active panel ──
        if appData.compareMode
            if strcmp(evt.Key, 'tab')
                if appData.compareActivePanel == 'L'
                    appData.compareActivePanel = 'R';
                else
                    appData.compareActivePanel = 'L';
                end
                updateCompareHighlight();
                return;
            end

            % +/= or - → linked zoom in compare mode
            if strcmp(evt.Key, 'equal') || strcmp(evt.Key, 'add')
                % Zoom in on active panel, sync to other
                if appData.compareActivePanel == 'L' && ~isempty(axL) && isvalid(axL)
                    cx = mean(axL.XLim); cy = mean(axL.YLim);
                    hw = diff(axL.XLim)/4; hh = diff(axL.YLim)/4;
                    axL.XLim = [cx-hw, cx+hw]; axL.YLim = [cy-hh, cy+hh];
                    syncCompareZoom(axL, axR);
                elseif ~isempty(axR) && isvalid(axR)
                    cx = mean(axR.XLim); cy = mean(axR.YLim);
                    hw = diff(axR.XLim)/4; hh = diff(axR.YLim)/4;
                    axR.XLim = [cx-hw, cx+hw]; axR.YLim = [cy-hh, cy+hh];
                    syncCompareZoom(axR, axL);
                end
                return;
            end
            if strcmp(evt.Key, 'hyphen') || strcmp(evt.Key, 'subtract')
                if appData.compareActivePanel == 'L' && ~isempty(axL) && isvalid(axL)
                    cx = mean(axL.XLim); cy = mean(axL.YLim);
                    hw = diff(axL.XLim); hh = diff(axL.YLim);
                    axL.XLim = [cx-hw, cx+hw]; axL.YLim = [cy-hh, cy+hh];
                    syncCompareZoom(axL, axR);
                elseif ~isempty(axR) && isvalid(axR)
                    cx = mean(axR.XLim); cy = mean(axR.YLim);
                    hw = diff(axR.XLim); hh = diff(axR.YLim);
                    axR.XLim = [cx-hw, cx+hw]; axR.YLim = [cy-hh, cy+hh];
                    syncCompareZoom(axR, axL);
                end
                return;
            end
            % F → fit both panels
            if strcmp(evt.Key, 'f')
                if ~isempty(axL) && isvalid(axL)
                    cdata = axL.Children;
                    if ~isempty(cdata)
                        axL.XLim = [0.5, size(cdata(1).CData, 2) + 0.5];
                        axL.YLim = [0.5, size(cdata(1).CData, 1) + 0.5];
                    end
                end
                if ~isempty(axR) && isvalid(axR)
                    cdata = axR.Children;
                    if ~isempty(cdata)
                        axR.XLim = [0.5, size(cdata(1).CData, 2) + 0.5];
                        axR.YLim = [0.5, size(cdata(1).CData, 1) + 0.5];
                    end
                end
                return;
            end

            if nImages < 2, return; end

            delta = 0;
            if strcmp(evt.Key, 'rightarrow'), delta =  1; end
            if strcmp(evt.Key, 'leftarrow'),  delta = -1; end
            if delta == 0, return; end

            if appData.compareActivePanel == 'L'
                newIdx = appData.compareIdxL + delta;
                if newIdx < 1, newIdx = nImages; end
                if newIdx > nImages, newIdx = 1; end
                appData.compareIdxL = newIdx;
                displayCompareImage('L');
            else
                newIdx = appData.compareIdxR + delta;
                if newIdx < 1, newIdx = nImages; end
                if newIdx > nImages, newIdx = 1; end
                appData.compareIdxR = newIdx;
                displayCompareImage('R');
            end
            return;
        end

        % ── Keyboard shortcuts (with modifiers) ────────────────────────
        hasMod = ~isempty(evt.Modifier);
        hasCtrl = hasMod && any(strcmp(evt.Modifier, 'control'));
        hasShift = hasMod && any(strcmp(evt.Modifier, 'shift'));

        % Ctrl+Shift+S → Session save (must precede Ctrl+S)
        if hasCtrl && hasShift && strcmp(evt.Key, 's')
            onSessionSave([], []);
            return;
        end
        % Ctrl+Shift+L → Session load
        if hasCtrl && hasShift && strcmp(evt.Key, 'l')
            onSessionLoad([], []);
            return;
        end
        % Ctrl+O  → Open files
        if hasCtrl && strcmp(evt.Key, 'o')
            onOpenFiles([], []);
            return;
        end
        % Ctrl+S  → Save image
        if hasCtrl && strcmp(evt.Key, 's')
            onSaveImage([], []);
            return;
        end
        % Ctrl+Z  → Undo filters
        if hasCtrl && strcmp(evt.Key, 'z')
            onUndoFilters([], []);
            return;
        end

        % F5 → Refresh state
        if strcmp(evt.Key, 'f5')
            refreshState();
            return;
        end

        % Delete / Backspace → Remove selected measurement
        if strcmp(evt.Key, 'delete') || strcmp(evt.Key, 'backspace')
            if appData.selectedMeasIdx > 0
                deleteSelectedMeasurement();
                return;
            end
        end

        % No-modifier shortcuts
        if ~hasMod
            % A  → Auto contrast
            if strcmp(evt.Key, 'a')
                onAutoContrast([], []);
                return;
            end
            % F  → Fit to window
            if strcmp(evt.Key, 'f')
                onZoomFit([], []);
                return;
            end
            % +/= → Zoom in (2x)
            if strcmp(evt.Key, 'equal') || strcmp(evt.Key, 'add')
                if appData.activeIdx >= 1 && ~isempty(appData.rawPixels)
                    cx = mean(ax.XLim);
                    cy = mean(ax.YLim);
                    hw = diff(ax.XLim) / 4;
                    hh = diff(ax.YLim) / 4;
                    ax.XLim = [cx - hw, cx + hw];
                    ax.YLim = [cy - hh, cy + hh];
                end
                return;
            end
            % -  → Zoom out (2x)
            if strcmp(evt.Key, 'hyphen') || strcmp(evt.Key, 'subtract')
                if appData.activeIdx >= 1 && ~isempty(appData.rawPixels)
                    cx = mean(ax.XLim);
                    cy = mean(ax.YLim);
                    hw = diff(ax.XLim);
                    hh = diff(ax.YLim);
                    ax.XLim = [cx - hw, cx + hw];
                    ax.YLim = [cy - hh, cy + hh];
                end
                return;
            end
        end

        % ── Normal mode: left/right arrows cycle through images ──────────
        if nImages < 2, return; end

        if strcmp(evt.Key, 'rightarrow')
            newIdx = appData.activeIdx + 1;
            if newIdx > nImages, newIdx = 1; end
            setActiveIdxAPI(newIdx);
        elseif strcmp(evt.Key, 'leftarrow')
            newIdx = appData.activeIdx - 1;
            if newIdx < 1, newIdx = nImages; end
            setActiveIdxAPI(newIdx);
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  COMPARE MODE: enter / exit / display / highlight
    % ════════════════════════════════════════════════════════════════════
    function onCompareToggle(src, ~)
        if src.Value
            enterCompareMode();
        else
            exitCompareMode();
        end
    end

    function enterCompareMode()
        if numel(appData.images) < 2
            return;
        end

        % Mutually exclusive with EDS mode
        if appData.edsMode
            onExitEDS();
        end

        appData.compareMode = true;

        % Pick indices for left and right panels
        appData.compareIdxL = appData.activeIdx;
        nextIdx = appData.activeIdx + 1;
        if nextIdx > numel(appData.images), nextIdx = 1; end
        appData.compareIdxR = nextIdx;
        appData.compareActivePanel = 'L';

        % Cancel any in-progress capture
        if ~isempty(appData.captureMode)
            cancelCapture();
        end

        % Clear overlays before destroying the axes
        clearAllOverlays();

        % Destroy single-view axes
        delete(axGL);
        axGL = [];
        ax   = [];

        % Create side-by-side layout inside axPanel
        compareGL = uigridlayout(axPanel, [1 2], ...
            'ColumnWidth', {'1x', '1x'}, ...
            'Padding', [2 2 2 2], ...
            'ColumnSpacing', 4);

        axL = uiaxes(compareGL);
        axL.Layout.Row = 1; axL.Layout.Column = 1;
        axL.Box = 'on';
        axL.XTick = []; axL.YTick = [];
        axL.Toolbar.Visible = 'off';
        try, disableDefaultInteractivity(axL); catch, end
        axL.Interactions = [];
        colormap(axL, gray(256));

        axR = uiaxes(compareGL);
        axR.Layout.Row = 1; axR.Layout.Column = 2;
        axR.Box = 'on';
        axR.XTick = []; axR.YTick = [];
        axR.Toolbar.Visible = 'off';
        try, disableDefaultInteractivity(axR); catch, end
        axR.Interactions = [];
        colormap(axR, gray(256));

        % Render both panels
        displayCompareImage('L');
        displayCompareImage('R');
        updateCompareHighlight();

        % Disable measurement/processing buttons (they operate on single ax)
        setToolsEnabled('off');
        setStatus('Compare mode — click or Tab to switch panel, arrows to scroll');
    end

    function exitCompareMode()
        appData.compareMode = false;

        % Clean up compare scale bars (handles destroyed with axes)
        appData.overlays.scalebarL = [];
        appData.overlays.scalebarR = [];

        % Destroy compare layout
        if ~isempty(compareGL) && isvalid(compareGL)
            delete(compareGL);
        end
        compareGL = [];
        axL = [];
        axR = [];

        % Recreate single-view axes with toolbar + stack navigator rows
        axGL = uigridlayout(axPanel, [3 1], ...
            'RowHeight', {28, '1x', 0}, 'Padding', [2 2 2 2], ...
            'RowSpacing', 2);

        % Re-build the icon transform toolbar (row 1). Mirrors the block
        % in the main builder above — kept inline in both places to stay
        % under MATLAB's nested-function cap.
        rcToolbarGL = uigridlayout(axGL, [1 9], ...
            'ColumnWidth', {32, 32, 32, 32, 32, 32, 32, 32, '1x'}, ...
            'RowHeight',   {24}, ...
            'Padding',     [2 2 2 2], ...
            'ColumnSpacing', 3);
        rcToolbarGL.Layout.Row = 1;
        rcIconDir = fullfile(fileparts(mfilename('fullpath')), ...
                             'icons', 'fermiviewer');
        rcResetFcn = @(~,~) setActiveIdxAPI(getActiveIdxAPI());
        rcSpecs = {
            'rot_cw.png',    'CW',    'Rotate 90° clockwise',                                   @(~,~) onRotateFlip('rot90cw');
            'rot_ccw.png',   'CCW',   'Rotate 90° counter-clockwise',                           @(~,~) onRotateFlip('rot90ccw');
            'flip_h.png',    'FH',    'Flip horizontally (left-right mirror)',                  @(~,~) onRotateFlip('fliph');
            'flip_v.png',    'FV',    'Flip vertically (top-bottom mirror)',                    @(~,~) onRotateFlip('flipv');
            'zoom.png',      'Z',     'Zoom to box (Esc to cancel)',                            @onZoomBox;
            'fit.png',       'Fit',   'Fit image to window (reset zoom)',                       @onResetZoom;
            'reset_all.png', 'Reset', 'Reset all transforms (reload original image)',           rcResetFcn;
            'crop.png',      'Crop',  'Crop to rectangle (destructive — Undo Filters reverts)', @onCropImage;
        };
        rcBtns = gobjects(1, size(rcSpecs, 1));
        for rcK = 1:size(rcSpecs, 1)
            rcP = fullfile(rcIconDir, rcSpecs{rcK, 1});
            if isfile(rcP)
                rcBtns(rcK) = uibutton(rcToolbarGL, ...
                    'Icon', rcP, 'Text', '', 'IconAlignment', 'center', ...
                    'BackgroundColor', [0.96 0.96 0.97], ...
                    'Tooltip', rcSpecs{rcK, 3}, ...
                    'ButtonPushedFcn', rcSpecs{rcK, 4}, ...
                    'Enable', 'on');
            else
                rcBtns(rcK) = uibutton(rcToolbarGL, ...
                    'Text', rcSpecs{rcK, 2}, 'FontSize', 9, ...
                    'BackgroundColor', [0.96 0.96 0.97], ...
                    'Tooltip', rcSpecs{rcK, 3}, ...
                    'ButtonPushedFcn', rcSpecs{rcK, 4}, ...
                    'Enable', 'on');
            end
            rcBtns(rcK).Layout.Row = 1;
            rcBtns(rcK).Layout.Column = rcK;
        end
        appData.transformToolbarBtns = rcBtns;

        ax = uiaxes(axGL);
        ax.Layout.Row = 2;
        ax.Box = 'on';
        ax.XTick = [];
        ax.YTick = [];
        title(ax, 'Open an image file to begin', 'Interpreter', 'none');
        xlabel(ax, '');
        ylabel(ax, '');
        colormap(ax, gray(256));
        ax.Toolbar.Visible = 'off';

        % Recreate stack navigator row (hidden until multi-frame detected)
        stackGL = uigridlayout(axGL, [1 5], ...
            'ColumnWidth', {40, 40, '1x', 40, 80}, 'Padding', [0 0 0 0]);
        stackGL.Layout.Row = 3;
        btnStackPrev = uibutton(stackGL, 'Text', '<', ...
            'ButtonPushedFcn', @(~,~) onStackNav(-1), ...
            'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, ...
            'Tooltip', 'Previous frame');
        btnStackPrev.Layout.Column = 1;
        btnStackNext = uibutton(stackGL, 'Text', '>', ...
            'ButtonPushedFcn', @(~,~) onStackNav(1), ...
            'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, ...
            'Tooltip', 'Next frame');
        btnStackNext.Layout.Column = 2;
        sldStackFrame = uislider(stackGL, ...
            'Value', 1, 'Limits', [1 2], ...
            'ValueChangedFcn', @onStackSlider, ...
            'Tooltip', 'Scroll through frames');
        sldStackFrame.Layout.Column = 3;
        sldStackFrame.MajorTicks = [];
        sldStackFrame.MinorTicks = [];
        btnStackMIP = uibutton(stackGL, 'Text', 'MIP', ...
            'ButtonPushedFcn', @onStackMIP, ...
            'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, ...
            'Tooltip', 'Maximum Intensity Projection across all frames');
        btnStackMIP.Layout.Column = 4;
        lblStackFrame = uilabel(stackGL, 'Text', '1 / 1', ...
            'FontSize', 10, 'HorizontalAlignment', 'center', ...
            'FontColor', [0.7 0.7 0.7]);
        lblStackFrame.Layout.Column = 5;

        fig.WindowButtonMotionFcn = @onMouseMotion;

        % Restore single image view
        displayImage();

        setStatus('Compare mode off.');
    end

    function displayCompareImage(panel)
    %DISPLAYCOMPAREIMAGE  Render an image into the left or right compare axes.
        if panel == 'L'
            targetAx = axL;
            idx = appData.compareIdxL;
        else
            targetAx = axR;
            idx = appData.compareIdxR;
        end

        if isempty(targetAx) || ~isvalid(targetAx)
            return;
        end

        if idx < 1 || idx > numel(appData.images)
            return;
        end

        dataStruct = appData.images{idx};
        imgInfo = dataStruct.metadata.parserSpecific.imageData;
        pixels  = imgInfo.pixels;

        % Convert to grayscale double
        if imgInfo.numChannels == 3
            pixDouble = double(pixels);
            rawGray = 0.299*pixDouble(:,:,1) + 0.587*pixDouble(:,:,2) + 0.114*pixDouble(:,:,3);
        else
            rawGray = double(pixels);
        end

        % Auto-contrast (2nd/98th percentile)
        pLow  = percentileNoToolbox(rawGray(:), 2);
        pHigh = percentileNoToolbox(rawGray(:), 98);
        if pLow >= pHigh
            pLow  = min(rawGray(:));
            pHigh = max(rawGray(:));
        end
        if pHigh <= pLow, pHigh = pLow + 1; end

        dispImg = (rawGray - pLow) / (pHigh - pLow);
        dispImg = max(0, min(1, dispImg));

        [H, W] = size(rawGray);
        delete(targetAx.Children);
        cla(targetAx);
        imagesc(targetAx, 'XData', [1 W], 'YData', [1 H], 'CData', dispImg);
        targetAx.CLim = [0 1];
        targetAx.YDir = 'reverse';
        axis(targetAx, 'equal');
        targetAx.XLim = [0.5, W + 0.5];
        targetAx.YLim = [0.5, H + 0.5];
        targetAx.XTick = [];
        targetAx.YTick = [];

        [~, fname, fext] = fileparts(dataStruct.metadata.source);
        title(targetAx, sprintf('[%d] %s%s', idx, fname, fext), ...
            'Interpreter', 'none', 'FontSize', 10);

        % Click on either panel to make it the active one
        clickCb = @(~,~) onCompareAxesClick(panel);
        targetAx.ButtonDownFcn = clickCb;
        % Also set on the image object so clicks on pixels register
        imgObj = findobj(targetAx, 'Type', 'image');
        if ~isempty(imgObj)
            imgObj(1).ButtonDownFcn = clickCb;
        end

        % Rebuild scale bar on this panel if checkbox is on
        if cbScaleBar.Value
            rebuildCompareScaleBar(panel, idx);
        end
    end

    function rebuildCompareScaleBar(panel, idx)
    %REBUILDCOMPARESCALEBAR  Add scale bar to one compare panel.
        if panel == 'L'
            tgtAx = axL;  sbField = 'scalebarL';
        else
            tgtAx = axR;  sbField = 'scalebarR';
        end
        % Delete existing for this panel
        deleteScaleBarHandle(appData.overlays.(sbField));
        appData.overlays.(sbField) = [];
        if isempty(tgtAx) || ~isvalid(tgtAx), return; end
        if idx < 1 || idx > numel(appData.images), return; end
        imgI = appData.images{idx}.metadata.parserSpecific.imageData;
        if ~imgI.calibrated, return; end
        if isequal(btnScaleBarColor.FontColor, [1 1 1])
            barColor = [1 1 1];
        else
            barColor = [0 0 0];
        end
        hB = imaging.addScaleBar(tgtAx, imgI.pixelSize, imgI.pixelUnit, ...
            'Color', barColor, 'FontSize', spnScaleBarFont.Value);
        makeScaleBarDraggable(hB);
        appData.overlays.(sbField) = hB;
    end

    function onCompareAxesClick(panel)
    %ONCOMPAREAXESCLICK  Switch active panel when user clicks on an image.
        if ~appData.compareMode, return; end
        if appData.compareActivePanel ~= panel
            appData.compareActivePanel = panel;
            updateCompareHighlight();
        end
    end

    function syncCompareZoom(sourceAx, targetAx2)
    %SYNCCOMPAREZOOM  Copy axis limits from source to target in compare mode.
        if ~compareLinkedZoom, return; end
        if isempty(sourceAx) || ~isvalid(sourceAx), return; end
        if isempty(targetAx2) || ~isvalid(targetAx2), return; end
        targetAx2.XLim = sourceAx.XLim;
        targetAx2.YLim = sourceAx.YLim;
    end

    function updateCompareHighlight()
    %UPDATECOMPAREHIGHLIGHT  Show cyan border on the active compare panel.
        if isempty(axL) || ~isvalid(axL), return; end
        if isempty(axR) || ~isvalid(axR), return; end

        inactiveBorder = [0.4 0.4 0.4];
        if appData.compareActivePanel == 'L'
            axL.XColor = OVERLAY_COLOR; axL.YColor = OVERLAY_COLOR;
            axL.LineWidth = 2;
            axR.XColor = inactiveBorder; axR.YColor = inactiveBorder;
            axR.LineWidth = 0.5;
            setStatus(sprintf('Compare: LEFT [%d] active — click or Tab to switch, arrows to scroll', ...
                appData.compareIdxL));
        else
            axR.XColor = OVERLAY_COLOR; axR.YColor = OVERLAY_COLOR;
            axR.LineWidth = 2;
            axL.XColor = inactiveBorder; axL.YColor = inactiveBorder;
            axL.LineWidth = 0.5;
            setStatus(sprintf('Compare: RIGHT [%d] active — click or Tab to switch, arrows to scroll', ...
                appData.compareIdxR));
        end
    end

    function setToolsEnabled(state)
    %SETTOOLSENABLED  Enable or disable measurement/processing/annotation buttons.
        % Icon transform toolbar above the image — mirrors the Transform
        % tab buttons' enable state. Guarded against partial-build and
        % post-compare-mode reconstruction where the array may be stale.
        if isfield(appData, 'transformToolbarBtns')
            for bk = 1:numel(appData.transformToolbarBtns)
                b = appData.transformToolbarBtns(bk);
                if ~isempty(b) && isgraphics(b) && isvalid(b)
                    b.Enable = state;
                end
            end
        end

        btnLineProfile.Enable   = state;
        btnDistance.Enable      = state;
        btnAngle.Enable        = state;
        btnPolyline.Enable     = state;
        btnExportProfile.Enable = state;
        btnClearOverlays.Enable = state;
        btnRotCW.Enable        = state;
        btnRotCCW.Enable       = state;
        btnFlipH.Enable        = state;
        btnFlipV.Enable        = state;
        btnGaussian.Enable     = state;
        btnMedian.Enable       = state;
        btnShowFFT.Enable      = state;
        btnCLAHE.Enable        = state;
        btnUndoFilters.Enable  = state;
        btnROIStats.Enable     = state;
        btnZoomBox.Enable      = state;
        btnResetZoom.Enable    = state;
        btnCropImage.Enable    = state;
        btnSaveCrop.Enable     = state;
        btnSaveImage.Enable    = state;
        btnSetPixelSize.Enable   = state;
        btnFFTMask.Enable        = state;
        btnParticles.Enable      = state;
        btnAlignStack.Enable     = state;
        btnColorOverlay.Enable   = state;
        btnExportOverlays.Enable = state;
        btnBatchExport.Enable    = state;
        btnCreateGIF.Enable      = state;
        btnCopyClipboard.Enable  = state;
        cbMinimap.Enable         = state;
        cbPixelInspector.Enable  = state;
        btnLiveThresh.Enable     = state;
        btnImgMath.Enable        = state;
        btnWatershed.Enable      = state;
        btnBatchCrop.Enable      = state;
        btnMontage.Enable        = state;
        btnSessionSave.Enable    = state;
        btnGrid.Enable           = state;
        btnExportMeasure.Enable  = state;
        btnDiffRings.Enable      = state;
        btnROIManager.Enable     = state;
        btnCalibrateBar.Enable   = state;
        btnBatchRename.Enable    = state;
        btnRenameSelected.Enable = state;
        btnPlaceAnnot.Enable   = state;
        btnClearAnnot.Enable   = state;
        ddAnnotColor.Enable    = state;
        cbColorbar.Enable      = state;
        % Phase 3 buttons
        btnDSpacing.Enable      = state;
        spnProfileWidth.Enable  = state;
        btnEllipseROI.Enable    = state;
        btnPolygonROI.Enable    = state;
        btnInvertImg.Enable     = state;
        btnSharpen.Enable       = state;
        btnBinImage.Enable      = state;
        btnMorphOp.Enable       = state;
        btnButterworth.Enable   = state;
        btnRadialProfile.Enable = state;
        btnAzIntegrate.Enable   = state;
        btnSurfacePlot.Enable   = state;
        btnBatchConvert.Enable  = state;
        btnCustomCmap.Enable    = state;
        btnPlaceArrow.Enable    = state;
        btnPlaceLine.Enable     = state;
        btnPlaceRect.Enable     = state;
        btnPlaceCircle.Enable   = state;
        % Phase 4 buttons
        btnPlaneLevel.Enable      = state;
        btnRoughness.Enable       = state;
        btnInterfaceFit.Enable    = state;
        btnMultiOtsu.Enable       = state;
        btnLatticeMeasure.Enable  = state;
        btnGPA.Enable             = state;
        btnCTF.Enable             = state;
        btnDefectCount.Enable     = state;
        btnBackProject.Enable     = state;
        btnFigureBuilder.Enable   = state;
        btnJournalExport.Enable   = state;
        btnCalibColorbar.Enable   = state;
        btnMacroRecord.Enable     = state;
        btnFlickerCompare.Enable  = state;
        % New feature buttons
        btn3DSurface.Enable       = state;
        btnLiveFFT.Enable         = state;
        btnTemplateMatch.Enable   = state;
        btnStitchImages.Enable    = state;
        btnNoiseEstimate.Enable   = state;
        btnPubPresets.Enable      = state;
        btnColormapPreset.Enable  = state;
        btnMeasStats.Enable       = state;
        btnBatchMeas.Enable       = state;
        btnExportToDP.Enable      = state;
        spnMeasLabelFont.Enable   = state;
        % EDS channel controls (only in EDS mode)
        if ~appData.edsMode
            btnAddChannel.Enable       = state;
            btnRemoveChannel.Enable    = state;
            ddChannelColor.Enable      = state;
            cbChannelVisible.Enable    = state;
            sldChannelIntensity.Enable = state;
            efChannelLabel.Enable      = state;
            btnExportComposite.Enable  = state;
        end
        % EDS quantification controls
        btnAssignElements.Enable       = state;
        btnQuantifyCL.Enable           = state;
        btnCompositionProfile.Enable   = state;
        btnROIComposition.Enable       = state;
        % EELS controls
        btnEnterEELS.Enable            = state;
        btnEELSFitBG.Enable            = state;
        ddEELSMethod.Enable            = state;
        chkShowEdges.Enable            = state;
        ddEdgeFilter.Enable            = state;
        btnEELSExtractMap.Enable       = state;
        btnEELSThickness.Enable        = state;
        btnEELSAlignZLP.Enable         = state;
        btnEELSDeconvolve.Enable       = state;
        btnEELSELNES.Enable            = state;
        btnEELSKK.Enable               = state;
        btnEELSNavigate.Enable         = state;
        btnEELSSVD.Enable              = state;
        % Diffraction controls
        btnAutoDetectSpots.Enable      = state;
        btnClickDiffSpot.Enable        = state;
        btnClearDiffSpots.Enable       = state;
        ddAccVoltage.Enable            = state;
        btnMatchDiffraction.Enable     = state;
        btnOverlayDiffRings.Enable     = state;
        btnSimDiffraction.Enable       = state;
        btnVDF.Enable                  = state;
        % ZAF quantification
        btnQuantifyZAF.Enable          = state;
    end

    % ════════════════════════════════════════════════════════════════════
    %  COLLAPSIBLE SECTION TOGGLE
    % ════════════════════════════════════════════════════════════════════
    function toggleSection(sect)
    %TOGGLESECTION  Collapse or expand a tools panel section.
        % Map section name → header button handle
        switch sect.name
            case 'Contrast',    hdr = btnContrastHeader;
            case 'Histogram',   hdr = btnHistogramHeader;
            case 'Measurement', hdr = btnMeasureHeader;
            case 'Processing',  hdr = btnProcessHeader;
            case 'Export & Style', hdr = btnExportHeader;
            case 'Annotations',  hdr = btnAnnotHeader;
            case 'EDS Channels', hdr = btnEDSHeader;
            case 'EELS Spectrum', hdr = btnEELSHeader;
            case 'Diffraction',  hdr = btnDiffHeader;
            case 'Metadata',     hdr = btnMetaHeader;
            otherwise, return;
        end

        currentH = toolsGL.RowHeight{sect.panelRow};
        if currentH == 0
            % Expand — cap to 60% of figure height so one section can't
            % consume the entire panel on small screens (e.g. 1280x800).
            figH    = fig.Position(4);
            capH    = floor(figH * 0.6);
            openH   = min(sect.openHeight, capH);
            toolsGL.RowHeight{sect.panelRow} = openH;
            hdr.Text = [ARROW_OPEN ' ' sect.name];
        else
            % Collapse
            toolsGL.RowHeight{sect.panelRow} = 0;
            hdr.Text = [ARROW_SHUT ' ' sect.name];
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  PANEL DRAG-RESIZE
    % ════════════════════════════════════════════════════════════════════

    function onIdleMouseDown(~, ~)
    %ONIDLEMOUSEDOWN  Figure-level mouse-down in idle mode — starts resize if near border.
        if strcmp(fig.SelectionType, 'alt'), return; end   % right-click: skip
        if ~isempty(appData.panelResizeDir)
            startPanelResize();
            return;
        end
        % Click on empty canvas deselects any highlighted measurement.
        % A measurement's own ButtonDownFcn fires AFTER this figure-level
        % callback, so clicks directly on a measurement re-select it via
        % selectMeasurement — no flicker, no missed highlights.
        if appData.selectedMeasIdx > 0
            deselectMeasurement();
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  BOX-ZOOM: click-drag rubber-band on image axes, double-click reset
    % ════════════════════════════════════════════════════════════════════
    function onAxesMouseDown(src, ~)
    %ONAXESMOUSEDOWN  Image-axes ButtonDownFcn: box-zoom or double-click reset.
        if ~isempty(appData.captureMode), return; end
        if appData.compareMode, return; end
        if isempty(appData.imgHandle) || ~isvalid(appData.imgHandle), return; end

        selType = fig.SelectionType;
        if strcmp(selType, 'alt'), return; end

        % Manual double-click detection — uifigure on macOS does not always
        % upgrade SelectionType to 'open' for rapid successive clicks.
        nowTick = tic;
        isDouble = strcmp(selType, 'open');
        if ~isDouble && appData.lastClickTick > 0
            if toc(appData.lastClickTick) < 0.35
                isDouble = true;
            end
        end
        appData.lastClickTick = nowTick;

        if isDouble
            cdata = appData.imgHandle.CData;
            H = size(cdata, 1); W = size(cdata, 2);
            if H > 0 && W > 0
                ax.XLim = [0.5, W + 0.5];
                ax.YLim = [0.5, H + 0.5];
            end
            return;
        end

        % Normal / extended click → begin rubber-band zoom (rect created on
        % first motion so single clicks leave no artifact)
        cp = src.CurrentPoint;
        appData.zoomStartXY = cp(1, 1:2);
        appData.zoomRect = [];
        appData.prevMotionFcn = fig.WindowButtonMotionFcn;
        appData.prevUpFcn     = fig.WindowButtonUpFcn;
        fig.WindowButtonMotionFcn = @onBoxZoomDrag;
        fig.WindowButtonUpFcn     = @onBoxZoomRelease;
    end

    function onBoxZoomDrag(~, ~)
    %ONBOXZOOMDRAG  Update rubber-band rectangle to follow cursor.
        p0 = appData.zoomStartXY;
        if isempty(p0), return; end
        cp = ax.CurrentPoint;
        x0 = min(p0(1), cp(1,1));  x1 = max(p0(1), cp(1,1));
        y0 = min(p0(2), cp(1,2));  y1 = max(p0(2), cp(1,2));
        w = max(1e-6, x1 - x0);    h = max(1e-6, y1 - y0);
        if isempty(appData.zoomRect) || ~isvalid(appData.zoomRect)
            % Defer creating the rubber-band until motion exceeds a small
            % threshold — avoids a stray 0-size rect on a simple click and
            % keeps the axes clean for the double-click reset gesture.
            if w < 2 && h < 2, return; end
            appData.zoomRect = rectangle(ax, ...
                'Position',        [x0, y0, w, h], ...
                'EdgeColor',       [1 1 0], ...
                'LineStyle',       '--', ...
                'LineWidth',       1, ...
                'FaceColor',       'none', ...
                'PickableParts',   'none', ...
                'HandleVisibility','off');
            return;
        end
        appData.zoomRect.Position = [x0, y0, w, h];
    end

    function onBoxZoomRelease(~, ~)
    %ONBOXZOOMRELEASE  Apply zoom if the drag is non-trivial; restore handlers.
        pos = [];
        if ~isempty(appData.zoomRect) && isvalid(appData.zoomRect)
            pos = appData.zoomRect.Position;
            delete(appData.zoomRect);
        end
        appData.zoomRect = [];
        appData.zoomStartXY = [];
        fig.WindowButtonMotionFcn = appData.prevMotionFcn;
        fig.WindowButtonUpFcn     = appData.prevUpFcn;
        appData.prevMotionFcn = '';
        appData.prevUpFcn     = '';
        % Apply only if drag covers > 3 data units in both dims (ignores stray clicks)
        if ~isempty(pos) && pos(3) >= 3 && pos(4) >= 3
            ax.XLim = [pos(1), pos(1) + pos(3)];
            ax.YLim = [pos(2), pos(2) + pos(4)];
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  CONTEXT MENUS: right-click on image, thumbnail list, scale bar
    % ════════════════════════════════════════════════════════════════════
    function buildContextMenus()
    %BUILDCONTEXTMENUS  Attach right-click menus to image axes, listbox, scale bar.
    %  All items reuse existing callbacks — no new business logic.
    %  macOS uifigure does not reliably deliver right-clicks to a parent
    %  uiaxes wrapper; attach the image menu to BOTH the axes and the image
    %  HG object, and reapply to the image object on every displayImage.

        % --- Image axes + image menu -----------------------------------------
        cmImage = uicontextmenu(fig);
        uimenu(cmImage, 'Text', 'Zoom', ...
            'MenuSelectedFcn', @(~,~) onZoomBox([], []));
        uimenu(cmImage, 'Text', 'Reset Zoom', ...
            'MenuSelectedFcn', @(~,~) onResetZoom([], []));
        uimenu(cmImage, 'Text', 'Fit to Window', ...
            'MenuSelectedFcn', @(~,~) onZoomFit([], []));
        uimenu(cmImage, 'Text', 'Zoom 1:1 (Actual Size)', ...
            'MenuSelectedFcn', @(~,~) onZoomActual([], []));
        uimenu(cmImage, 'Text', 'Copy to Clipboard', ...
            'Separator', 'on', ...
            'MenuSelectedFcn', @(~,~) onCopyClipboard([], []));
        uimenu(cmImage, 'Text', 'Save Image As…', ...
            'MenuSelectedFcn', @(~,~) onSaveImage([], []));
        uimenu(cmImage, 'Text', 'Toggle Scale Bar', ...
            'Separator', 'on', ...
            'MenuSelectedFcn', @(~,~) contextToggleScaleBar());
        uimenu(cmImage, 'Text', 'Clear Overlays', ...
            'MenuSelectedFcn', @(~,~) onClearOverlays([], []));
        appData.cmImage = cmImage;
        if ~isempty(ax) && isvalid(ax)
            ax.ContextMenu = cmImage;
        end
        attachImageContextMenu();   % also attach to the current image HG object

        % --- Thumbnail list menu ---------------------------------------------
        cmList = uicontextmenu(fig);
        uimenu(cmList, 'Text', 'Open…', ...
            'MenuSelectedFcn', @(~,~) onOpenFiles([], []));
        uimenu(cmList, 'Text', 'Rename Selected…', ...
            'MenuSelectedFcn', @(~,~) onRenameSelected([], []));
        uimenu(cmList, 'Text', 'Remove Selected', ...
            'Separator', 'on', ...
            'MenuSelectedFcn', @(~,~) onRemoveImage([], []));
        appData.cmList = cmList;
        if ~isempty(lbImages) && isvalid(lbImages)
            lbImages.ContextMenu = cmList;
        end
    end

    function attachImageContextMenu()
    %ATTACHIMAGECONTEXTMENU  Bind the image context menu to the current
    %  image HG object. Called from displayImage / undoPop / FFT-mask apply
    %  etc. because imagesc creates a fresh object each time and Mac
    %  uifigure delivers right-clicks to the image, not the axes wrapper.
        if isempty(appData.cmImage) || ~isvalid(appData.cmImage), return; end
        if ~isempty(appData.imgHandle) && isvalid(appData.imgHandle)
            appData.imgHandle.ContextMenu = appData.cmImage;
        end
    end

    function contextToggleScaleBar()
    %CONTEXTTOGGLESCALEBAR  Flip the scale-bar checkbox from the context menu.
        if isempty(cbScaleBar) || ~isvalid(cbScaleBar), return; end
        if strcmp(cbScaleBar.Enable, 'off')
            setStatus('Scale bar requires a calibrated image.');
            return;
        end
        cbScaleBar.Value = ~cbScaleBar.Value;
        onScaleBarToggle([], []);
    end

    function dir = detectResizeBorder()
    %DETECTRESIZEBORDER  Check if cursor is near a draggable panel border.
    %  Returns:  'v_col12'   — left panel / image border
    %            'v_col23'   — image / tools panel border
    %            ''          — not near any border
        dir = '';
        try
            mp = fig.CurrentPoint;   % [x y] from bottom-left

            % v_col12: right edge of left listPanel
            lPos = getpixelposition(listPanel, true);
            borderX = lPos(1) + lPos(3);
            if abs(mp(1) - borderX) <= SNAP_PX && ...
               mp(2) >= lPos(2) && mp(2) <= lPos(2) + lPos(4)
                dir = 'v_col12'; return;
            end

            % v_col23: left edge of tools panel
            tPos = getpixelposition(toolsPanel, true);
            borderX = tPos(1);
            if abs(mp(1) - borderX) <= SNAP_PX && ...
               mp(2) >= tPos(2) && mp(2) <= tPos(2) + tPos(4)
                dir = 'v_col23'; return;
            end

        catch
            % getpixelposition may throw on first render — silently skip
        end
    end

    function startPanelResize()
    %STARTPANELRESIZE  Begin dragging a panel border.
        mp = fig.CurrentPoint;
        appData.panelResizeStart = mp;

        if strcmp(appData.panelResizeDir, 'v_col12')
            try
                lPos = getpixelposition(listPanel, true);
                appData.panelResizeOrig = lPos(3);
            catch
                appData.panelResizeOrig = appData.leftPanelWidth;
            end
        elseif strcmp(appData.panelResizeDir, 'v_col23')
            try
                tPos = getpixelposition(toolsPanel, true);
                appData.panelResizeOrig = tPos(3);
            catch
                appData.panelResizeOrig = appData.toolsPanelWidth;
            end
        end

        fig.WindowButtonMotionFcn = @onPanelResizeMove;
        fig.WindowButtonUpFcn     = @onPanelResizeUp;
    end

    function onPanelResizeMove(~, ~)
    %ONPANELRESIZEMOVE  Live-update layout while dragging a panel border.
        if isempty(appData.panelResizeStart), return; end
        mp = fig.CurrentPoint;

        if strcmp(appData.panelResizeDir, 'v_col12')
            % Drag right → left panel wider
            delta = mp(1) - appData.panelResizeStart(1);
            newW  = round(appData.panelResizeOrig + delta);
            newW  = max(MIN_LEFT_W, min(newW, 400));
            appData.leftPanelWidth = newW;
            cw = mainGL.ColumnWidth;
            cw{1} = newW;
            mainGL.ColumnWidth = cw;

        elseif strcmp(appData.panelResizeDir, 'v_col23')
            % Drag left → tools panel wider (note: delta is negative when dragging left)
            delta = mp(1) - appData.panelResizeStart(1);
            newW  = round(appData.panelResizeOrig - delta);
            newW  = max(MIN_TOOLS_W, min(newW, 500));
            appData.toolsPanelWidth = newW;
            cw = mainGL.ColumnWidth;
            cw{3} = newW;
            mainGL.ColumnWidth = cw;

        end
    end

    function onPanelResizeUp(~, ~)
    %ONPANELRESIZEUP  Finish a panel border drag and restore normal handlers.
        fig.WindowButtonMotionFcn = @onMouseMotion;
        fig.WindowButtonUpFcn     = '';
        appData.panelResizeStart  = [];
        appData.panelResizeOrig   = [];
        appData.panelResizeDir    = '';
    end

    % ════════════════════════════════════════════════════════════════════
    %  THEME: dark / light mode toggle
    % ════════════════════════════════════════════════════════════════════
    function onThemeToggle(~, ~)
        appData.darkMode = ~appData.darkMode;
        applyTheme();
    end

    function applyTheme()
    %APPLYTHEME  Apply dark or light colour scheme to all GUI elements.
        if appData.darkMode
            % ── Dark theme ──
            figBG     = [0.15 0.15 0.15];
            panelBG   = [0.18 0.18 0.18];
            panelFG   = [0.9 0.9 0.9];
            hdrBG     = [0.22 0.22 0.22];
            hdrFG     = [0.85 0.85 0.85];
            statusFG  = [0.45 0.45 0.45];
            filenameFG = [0.85 0.85 0.85];
            sepFG     = [0.5 0.5 0.5];
            axBG      = [0 0 0];
            editBG    = [0.22 0.22 0.22];
            editFG    = [0.9 0.9 0.9];
            btnThemeToggle.Text = char(9790);   % moon
            btnThemeToggle.Tooltip = 'Switch to light mode';
        else
            % ── Light theme ──
            figBG     = [0.94 0.94 0.94];
            panelBG   = [0.96 0.96 0.96];
            panelFG   = [0.1 0.1 0.1];
            hdrBG     = [0.88 0.88 0.88];
            hdrFG     = [0.15 0.15 0.15];
            statusFG  = [0.4 0.4 0.4];
            filenameFG = [0.2 0.2 0.2];
            sepFG     = [0.65 0.65 0.65];
            axBG      = [1 1 1];
            editBG    = [1 1 1];
            editFG    = [0.1 0.1 0.1];
            btnThemeToggle.Text = char(9728);   % sun
            btnThemeToggle.Tooltip = 'Switch to dark mode';
        end

        % Figure
        fig.Color = figBG;

        % Panels
        listPanel.BackgroundColor  = panelBG;
        listPanel.ForegroundColor  = panelFG;
        toolsPanel.BackgroundColor = panelBG;
        toolsPanel.ForegroundColor = panelFG;
        % Section panels
        pnlContrast.BackgroundColor  = panelBG;
        pnlHistogram.BackgroundColor = panelBG;
        pnlMeasure.BackgroundColor   = panelBG;
        pnlProcess.BackgroundColor   = panelBG;
        pnlExport.BackgroundColor    = panelBG;
        pnlAnnot.BackgroundColor     = panelBG;
        pnlEDS.BackgroundColor       = panelBG;

        % Section header buttons
        btnContrastHeader.BackgroundColor  = hdrBG;
        btnContrastHeader.FontColor        = hdrFG;
        btnHistogramHeader.BackgroundColor = hdrBG;
        btnHistogramHeader.FontColor       = hdrFG;
        btnMeasureHeader.BackgroundColor   = hdrBG;
        btnMeasureHeader.FontColor         = hdrFG;
        btnProcessHeader.BackgroundColor   = hdrBG;
        btnProcessHeader.FontColor         = hdrFG;
        if appData.darkMode
            btnExportHeader.BackgroundColor = [0.18 0.32 0.52];
            btnExportHeader.FontColor       = [1 1 1];
        else
            btnExportHeader.BackgroundColor = [0.78 0.86 0.95];
            btnExportHeader.FontColor       = [0.10 0.10 0.10];
        end
        btnAnnotHeader.BackgroundColor     = hdrBG;
        btnAnnotHeader.FontColor           = hdrFG;
        btnEDSHeader.BackgroundColor       = hdrBG;
        btnEDSHeader.FontColor             = hdrFG;
        btnEELSHeader.BackgroundColor      = hdrBG;
        btnEELSHeader.FontColor            = hdrFG;
        btnDiffHeader.BackgroundColor      = hdrBG;
        btnDiffHeader.FontColor            = hdrFG;
        btnMetaHeader.BackgroundColor      = hdrBG;
        btnMetaHeader.FontColor            = hdrFG;

        % Status bar labels
        lblStatusDims.FontColor    = statusFG;
        lblStatusBits.FontColor    = statusFG;
        lblStatusPixSize.FontColor = statusFG;
        lblStatusMouse.FontColor   = statusFG;

        % Filename label
        lblFilename.FontColor = filenameFG;

        % Separator labels
        lblSep.FontColor  = sepFG;
        lblSep2.FontColor = sepFG;
        lblSep3.FontColor = sepFG;
        lblSep4.FontColor = sepFG;

        % Image axes
        if ~isempty(ax) && isvalid(ax)
            ax.Color = axBG;
        end

        % Histogram axes
        histAx.Color = axBG;
        histAx.XColor = sepFG;
        histAx.YColor = sepFG;

        % Metadata textarea
        taMetadata.BackgroundColor = editBG;
        taMetadata.FontColor       = editFG;

        % Edit fields and listbox
        efRenameBase.BackgroundColor = editBG;
        efRenameBase.FontColor       = editFG;
        efAnnotText.BackgroundColor  = editBG;
        efAnnotText.FontColor        = editFG;
        lbImages.BackgroundColor     = editBG;
        lbImages.FontColor           = editFG;

        % Grid layout backgrounds
        rootGL.BackgroundColor    = figBG;
        mainGL.BackgroundColor    = figBG;
        toolbarGL.BackgroundColor = figBG;
        statusGL.BackgroundColor  = figBG;
        listGL.BackgroundColor    = panelBG;

        % Inner section grid backgrounds
        try
            contrastInnerGL.BackgroundColor = panelBG;
            measureInnerGL.BackgroundColor  = panelBG;
            processInnerGL.BackgroundColor  = panelBG;
            exportInnerGL.BackgroundColor   = panelBG;
            for pg = 1:numel(processTabGrids)
                processTabGrids{pg}.BackgroundColor = panelBG;
            end
            annotInnerGL.BackgroundColor    = panelBG;
            edsInnerGL.BackgroundColor      = panelBG;
            toolsGL.BackgroundColor         = panelBG;
        catch
        end

        % Export sub-headers and labels
        lblRename.FontColor     = hdrFG;
        lblDPI.FontColor        = hdrFG;
        lblPubHeader.FontColor  = statusFG;
        lblUtilHeader.FontColor = statusFG;
    end

    % ════════════════════════════════════════════════════════════════════
    %  ANNOTATIONS: colour selection, place, clear, API
    % ════════════════════════════════════════════════════════════════════
    function onAnnotColorChange(src, ~)
        % uidropdown ValueChangedFcn — src.Value is one of the ItemsData
        % entries {'White','Cyan','Yellow','Red','Black'}.
        names  = {'White', 'Cyan', 'Yellow', 'Red', 'Black'};
        colors = {[1 1 1], OVERLAY_COLOR, [1 1 0], [1 0 0], [0 0 0]};
        bgs    = {[0.25 0.25 0.25], [0.15 0.15 0.15], [0.15 0.15 0.15], ...
                  [0.15 0.15 0.15], [0.85 0.85 0.85]};

        idx = find(strcmp(names, src.Value), 1);
        if isempty(idx)
            idx = 1;   % defensive fallback to White
        end

        appData.annotationColor    = colors{idx};
        ddAnnotColor.FontColor     = colors{idx};
        ddAnnotColor.BackgroundColor = bgs{idx};
    end

    function onPlaceAnnotation(~, ~)
        if appData.activeIdx < 1 || isempty(appData.displayImg)
            return;
        end
        if appData.compareMode
            return;
        end
        if ~isempty(appData.captureMode)
            cancelCapture();
        end

        appData.captureMode = 'annotation';
        appData.captureClicks = [];
        fig.Pointer = 'crosshair';
        fig.WindowButtonDownFcn = @onAnnotationClick;
        setStatus('Click on image to place text annotation... (Esc to cancel)');
    end

    function onAnnotationClick(~, ~)
        if ~strcmp(appData.captureMode, 'annotation')
            return;
        end

        cp = ax.CurrentPoint;
        x  = cp(1, 1);
        y  = cp(1, 2);

        % Validate within image bounds
        if isempty(appData.displayImg), return; end
        [H, W] = size(appData.filteredPixels);
        if x < 0.5 || x > W + 0.5 || y < 0.5 || y > H + 0.5
            return;
        end

        annotStr   = efAnnotText.Value;
        annotSize  = spnAnnotFont.Value;
        annotColor = appData.annotationColor;

        if isempty(strtrim(annotStr))
            setStatus('Annotation text is empty — enter text first.');
            return;
        end

        placeAnnotationAt(x, y, annotStr, annotSize, annotColor);
        finishCapture();
        setStatus(sprintf('Annotation placed at (%.0f, %.0f).', x, y));
    end

    function placeAnnotationAt(x, y, str, fontSize, color)
    %PLACEANNOTATIONAT  Create a text object on ax and store it.
        hTxt = text(ax, x, y, str, ...
            'Color',               color, ...
            'FontSize',            fontSize, ...
            'FontWeight',          'bold', ...
            'HorizontalAlignment', 'center', ...
            'VerticalAlignment',   'bottom', ...
            'HandleVisibility',    'off', ...
            'Tag',                 'EMAnnotation');

        annot = struct('hText', hTxt, 'x', x, 'y', y, ...
                       'str', str, 'fontSize', fontSize, 'color', color);
        appData.overlays.textAnnotations{end+1} = annot;
    end

    function placeAnnotationAPI(x, y, str, fontSize, color)
    %PLACEANNOTATIONAPI  Non-interactive annotation placement for testing.
        if appData.activeIdx < 1 || isempty(appData.displayImg)
            return;
        end
        placeAnnotationAt(x, y, str, fontSize, color);
    end

    function onClearAnnotations(~, ~)
        for ci = 1:numel(appData.overlays.textAnnotations)
            a = appData.overlays.textAnnotations{ci};
            if isfield(a, 'hText') && isvalid(a.hText)
                delete(a.hText);
            end
        end
        appData.overlays.textAnnotations = {};
        setStatus('Text annotations cleared.');
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: startTwoClickCapture — Enter two-click capture mode
    % ════════════════════════════════════════════════════════════════════
    function startTwoClickCapture(mode)
        % Cancel any existing capture first
        if ~isempty(appData.captureMode)
            cancelCapture();
        end

        appData.captureMode   = mode;
        appData.captureClicks = [];

        fig.Pointer = 'crosshair';

        % Intercept button-down on the axes
        fig.WindowButtonDownFcn = @onCaptureClick;

        switch mode
            case 'profile'
                setStatus('Click first point for line profile... (Escape to cancel)');
            case 'distance'
                setStatus('Click first point for distance... (Escape to cancel)');
            case 'scalebar'
                setStatus('Click one end of the scale bar... (Escape to cancel)');
            case 'dspacing'
                setStatus('Click first FFT spot for d-spacing measurement... (Escape to cancel)');
            case 'roiellipse'
                setStatus('Click center of ellipse... (Escape to cancel)');
            case 'arrow'
                setStatus('Click arrow start point... (Escape to cancel)');
            case 'annotline'
                setStatus('Click line start point... (Escape to cancel)');
            case 'annotrect'
                setStatus('Click first corner of rectangle... (Escape to cancel)');
            case 'annotcircle'
                setStatus('Click center of circle... (Escape to cancel)');
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: finishCapture — Restore cursor and ButtonDownFcn after capture
    % ════════════════════════════════════════════════════════════════════
    function finishCapture()
        appData.captureMode   = '';
        appData.captureClicks = [];
        fig.Pointer = 'arrow';
        fig.WindowButtonDownFcn = @onIdleMouseDown;
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: cancelCapture — Abort capture and remove partial markers
    % ════════════════════════════════════════════════════════════════════
    function cancelCapture()
        % Delete any partial click markers placed during this capture
        for ci = 1:numel(appData.overlays.clickMarkers)
            h = appData.overlays.clickMarkers{ci};
            if isvalid(h)
                delete(h);
            end
        end
        appData.overlays.clickMarkers = {};

        % Restore motion callback in case rect-capture had replaced it
        fig.WindowButtonMotionFcn = @onMouseMotion;

        finishCapture();
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: executeMeasureProfile — Draw line and plot profile figure
    % ════════════════════════════════════════════════════════════════════
    function executeMeasureProfile(x1, y1, x2, y2)
        % Draw the measurement line
        hLine = line(ax, [x1 x2], [y1 y2], ...
            'Color',            OVERLAY_COLOR, ...
            'LineWidth',        1.5, ...
            'HandleVisibility', 'off');
        appData.overlays.lines{end+1} = hLine;

        % Delete temporary click markers — we'll create draggable ones
        for ci = 1:numel(appData.overlays.clickMarkers)
            h = appData.overlays.clickMarkers{ci};
            if isvalid(h), delete(h); end
        end
        appData.overlays.clickMarkers = {};

        % Create draggable endpoint markers
        hP1 = createEndpointMarker(x1, y1);
        hP2 = createEndpointMarker(x2, y2);

        % Build measurement record
        meas.type  = 'profile';
        meas.hLine = hLine;
        meas.hP1   = hP1;
        meas.hP2   = hP2;
        meas.hText = [];   % profiles don't have a midpoint label
        midx = numel(appData.overlays.measurements) + 1;
        appData.overlays.measurements{midx} = meas;

        % Attach drag + selection callbacks
        hP1.ButtonDownFcn   = @(~,~) startEndpointDrag(midx, 1);
        hP2.ButtonDownFcn   = @(~,~) startEndpointDrag(midx, 2);
        hLine.ButtonDownFcn = @(~,~) selectMeasurement(midx);
        hLine.HitTest = 'on'; hLine.PickableParts = 'all';

        % Run the profile computation
        runProfile(x1, y1, x2, y2);
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: executeMeasureDistance — Draw line and annotate distance
    % ════════════════════════════════════════════════════════════════════
    function executeMeasureDistance(x1, y1, x2, y2)
        % Draw the measurement line
        hLine = line(ax, [x1 x2], [y1 y2], ...
            'Color',            OVERLAY_COLOR, ...
            'LineWidth',        1.5, ...
            'HandleVisibility', 'off');
        appData.overlays.lines{end+1} = hLine;

        % Delete temporary click markers — we'll create draggable ones
        for ci = 1:numel(appData.overlays.clickMarkers)
            h = appData.overlays.clickMarkers{ci};
            if isvalid(h), delete(h); end
        end
        appData.overlays.clickMarkers = {};

        % Create draggable endpoint markers
        hP1 = createEndpointMarker(x1, y1);
        hP2 = createEndpointMarker(x2, y2);

        % Create midpoint distance label
        hTxt = createDistanceLabel(x1, y1, x2, y2);

        % Build measurement record
        meas.type  = 'distance';
        meas.hLine = hLine;
        meas.hP1   = hP1;
        meas.hP2   = hP2;
        meas.hText = hTxt;
        % Store distance value in calibrated units (or px if uncalibrated),
        % so getMeasStatsAPI can aggregate across measurements.
        try
            imgInfo = appData.images{appData.activeIdx}.metadata.parserSpecific.imageData;
            [tiltDeg, tiltAxis, ~, tiltGeom] = getTiltState();
            if imgInfo.calibrated && ~isnan(imgInfo.pixelSize)
                [dv, du] = imaging.measureDistance(x1, y1, x2, y2, ...
                    PixelSize=imgInfo.pixelSize, PixelUnit=imgInfo.pixelUnit, ...
                    TiltAngle=tiltDeg, TiltAxis=tiltAxis, Geometry=tiltGeom);
            else
                [dv, du] = imaging.measureDistance(x1, y1, x2, y2, ...
                    TiltAngle=tiltDeg, TiltAxis=tiltAxis, Geometry=tiltGeom);
            end
            meas.distance = dv;
            meas.unit     = du;
        catch
            meas.distance = sqrt((x2-x1)^2 + (y2-y1)^2);
            meas.unit     = 'px';
        end
        midx = numel(appData.overlays.measurements) + 1;
        appData.overlays.measurements{midx} = meas;

        % Attach drag + selection callbacks
        hP1.ButtonDownFcn   = @(~,~) startEndpointDrag(midx, 1);
        hP2.ButtonDownFcn   = @(~,~) startEndpointDrag(midx, 2);
        hLine.ButtonDownFcn = @(~,~) selectMeasurement(midx);
        hLine.HitTest = 'on'; hLine.PickableParts = 'all';

        appData.overlays.distLabels{end+1} = hTxt;
        setStatus(sprintf('Distance: %s', hTxt.String));
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: createEndpointMarker — Draggable circle marker for line ends
    % ════════════════════════════════════════════════════════════════════
    function hMark = createEndpointMarker(x, y)
        % Endpoint marker: a short horizontal tick with a hollow circle
        % centered on (x, y). The tick's endpoints mark the exact pixel
        % being measured — the prior solid-circle design hid the point
        % beneath the marker fill. Kept as a single line object so the
        % existing ButtonDownFcn / drag wiring stays unchanged.
        tickHalf = 4;  % pixels to each side of the endpoint
        hMark = line(ax, [x - tickHalf, x, x + tickHalf], [y, y, y], ...
            'Marker',           'o', ...
            'MarkerIndices',    2, ...
            'MarkerSize',       6, ...
            'MarkerEdgeColor',  OVERLAY_COLOR, ...
            'MarkerFaceColor',  'none', ...
            'LineStyle',        '-', ...
            'LineWidth',        1.0, ...
            'Color',            OVERLAY_COLOR, ...
            'HandleVisibility', 'off');
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: createDistanceLabel — Offset annotation with distance text
    %
    %  Label placement convention (shared with the endpoint drag-motion
    %  handler below — the offset math is inlined in both places to stay
    %  under FermiViewer's nested-function count budget, so KEEP THE TWO
    %  BLOCKS IN SYNC if you change one): the label sits ~14 data-pixel
    %  units off the line midpoint along the perpendicular direction
    %  that points "up on screen" (negative y in image axes with
    %  YDir='reverse'). When that would push the label outside the
    %  displayed image, the perpendicular is flipped so the label stays
    %  visible.
    % ════════════════════════════════════════════════════════════════════
    function hTxt = createDistanceLabel(x1, y1, x2, y2)
        % Retrieve calibration
        imgInfo = appData.images{appData.activeIdx}.metadata.parserSpecific.imageData;
        ps = NaN;
        pu = 'px';
        if imgInfo.calibrated && ~isnan(imgInfo.pixelSize)
            ps = imgInfo.pixelSize;
            pu = imgInfo.pixelUnit;
        end

        [tiltDeg, tiltAxis, tiltActive, tiltGeom] = getTiltState();

        if ~isnan(ps)
            [dVal, dUnit] = imaging.measureDistance(x1, y1, x2, y2, ...
                PixelSize=ps, PixelUnit=pu, ...
                TiltAngle=tiltDeg, TiltAxis=tiltAxis, Geometry=tiltGeom);
            distStr = sprintf('%.4g %s', dVal, dUnit);
        else
            [dVal, dUnit] = imaging.measureDistance(x1, y1, x2, y2, ...
                TiltAngle=tiltDeg, TiltAxis=tiltAxis, Geometry=tiltGeom);
            distStr = sprintf('%.1f %s', dVal, dUnit);
        end
        % Asterisk suffix marks tilt-corrected distances. The Tooltip on
        % hTxt (set below) explains which trig factor was applied (cos for
        % Surface geometry, sin for Cross-section). This symbol is preserved
        % in exported figures and CSV logs where the tooltip is lost —
        % figure captions should reiterate the correction formula.
        if tiltActive
            distStr = [distStr, '*'];
        end

        % Offset the label perpendicular to the measurement line so it
        % doesn't sit on top of the pixel data. Direction picked to keep
        % the label inside the image bounds (flips the perpendicular sign
        % when the default "upward-in-screen" side would clip off-axis).
        % 14-data-pixel offset ≈ 1.1x the 13pt bold cap-height; inlined
        % here (not factored into a helper) to avoid exceeding the
        % nested-function count budget — see the header block comment.
        mx_ = (x1 + x2) / 2;
        my_ = (y1 + y2) / 2;
        dx_ = x2 - x1;  dy_ = y2 - y1;
        len_ = hypot(dx_, dy_);
        if len_ < eps
            nx_ = 0;  ny_ = -1;
        else
            nx_ = -dy_ / len_;  ny_ = dx_ / len_;
            if ny_ > 0, nx_ = -nx_; ny_ = -ny_; end   % prefer up-on-screen
        end
        lx_ = mx_ + 14 * nx_;
        ly_ = my_ + 14 * ny_;
        if ~isempty(appData.filteredPixels)
            [H_, W_] = size(appData.filteredPixels);
            if lx_ < 1 || lx_ > W_ || ly_ < 1 || ly_ > H_
                lx_ = mx_ - 14 * nx_;
                ly_ = my_ - 14 * ny_;
            end
        end
        lblPos = [lx_, ly_, 0];

        % Defaults chosen for readability on typical EM images:
        %   FontSize=13 bold — visible at normal zoom on 4K displays
        %     without being intrusive (was 10, user feedback: too small).
        %   BackgroundColor='none' + EdgeColor='none' + Margin=1 — the
        %     filled black box on the old default occluded pixel data and
        %     looked heavy. Bold white text stays legible on most EM
        %     images; for bright specimens users can adjust Color on the
        %     returned handle or via a future styling hook.
        %   Offset perpendicular to the line — computed above, so the
        %     label never covers the measured feature.
        hTxt = text(ax, lblPos(1), lblPos(2), distStr, ...
            'Color',               [1 1 1], ...
            'FontSize',            spnMeasLabelFont.Value, ...
            'FontWeight',          'bold', ...
            'HorizontalAlignment', 'center', ...
            'VerticalAlignment',   'middle', ...
            'BackgroundColor',     'none', ...
            'EdgeColor',           'none', ...
            'Margin',              1, ...
            'HandleVisibility',    'off');

        % Drag to reposition the label without affecting the measurement.
        hTxt.ButtonDownFcn = @(~,~) startLabelDrag(hTxt);

        % Context menu: always includes "Font size..." for all labels.
        % For tilt-corrected labels also shows the correction explanation
        % as a disabled informational item (text() has no native Tooltip).
        cm = uicontextmenu(fig);
        if tiltActive
            if strcmpi(tiltGeom, 'Surface')
                factorName = 'cos';
            else
                factorName = 'sin';
            end
            tipStr = sprintf( ...
                'Tilt-corrected: 1/%s(%.1f°) applied on %s-axis (%s geometry)', ...
                factorName, tiltDeg, upper(char(tiltAxis)), tiltGeom);
            hTxt.UserData = struct('tooltip', tipStr);
            uimenu(cm, 'Text', tipStr, 'Enable', 'off');
        end
        uimenu(cm, 'Text', 'Font size...', ...
            'MenuSelectedFcn', @(~,~) setLabelFontSize(hTxt));
        hTxt.ContextMenu = cm;

        % Log measurement (details includes tilt when active)
        detailStr = sprintf('(%.0f,%.0f)-(%.0f,%.0f)', x1, y1, x2, y2);
        if tiltActive
            detailStr = sprintf('%s tilt=%.2f° axis=%s geom=%s', ...
                detailStr, tiltDeg, tiltAxis, tiltGeom);
        end
        appData.measurementLog{end+1} = struct( ...
            'type', 'distance', 'value', dVal, 'unit', dUnit, ...
            'details', detailStr, ...
            'timestamp', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')));
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: runProfile — Extract and display line profile
    % ════════════════════════════════════════════════════════════════════
    function runProfile(x1, y1, x2, y2)
        % Preflight: imaging.lineProfile needs a non-empty numeric matrix.
        % Some parsers return pixelUnit as a MATLAB string; coerce to char
        % so the call site never depends on the lineProfile arguments
        % block coercing for us (was the source of the "Undefined function
        % ... for input arguments of type 'string'" dispatch failure).
        if isempty(appData.filteredPixels) || ~isnumeric(appData.filteredPixels)
            uialert(fig, 'Load an image before running a line profile.', ...
                'No image', 'Icon', 'warning');
            return;
        end
        imgInfo = appData.images{appData.activeIdx}.metadata.parserSpecific.imageData;
        ps = NaN;
        pu = 'px';
        if imgInfo.calibrated && ~isnan(imgInfo.pixelSize)
            ps = imgInfo.pixelSize;
            pu = char(imgInfo.pixelUnit);
            if isempty(pu), pu = 'px'; end
        end

        [tiltDeg, tiltAxis, tiltActive, tiltGeom] = getTiltState();

        try
            profileWidth = spnProfileWidth.Value;
            if profileWidth > 1
                % Width-averaged profile (sampling is in pixel space; apply
                % tilt correction to the distance axis after scaling).
                profResult = runWidthAveragedProfile(x1, y1, x2, y2, profileWidth);
                dist = profResult.dist;
                intensity = profResult.intensity;
                if tiltActive && ~isempty(dist)
                    % Rescale distance axis proportionally so total matches
                    % the tilt-corrected pixel distance. Geometry chooses
                    % the trig factor (1/sin for cross-section, 1/cos for
                    % plan-view surface).
                    dxp = x2 - x1; dyp = y2 - y1;
                    if strcmpi(tiltGeom, 'Surface')
                        scl = 1 / cosd(tiltDeg);
                    else
                        scl = 1 / sind(tiltDeg);
                    end
                    if strcmpi(tiltAxis, 'Y'), dyp = dyp * scl; else, dxp = dxp * scl; end
                    correctedPx = sqrt(dxp^2 + dyp^2);
                    origPx = sqrt((x2-x1)^2 + (y2-y1)^2);
                    if origPx > 0
                        dist = dist * (correctedPx / origPx);
                    end
                end
                if ~isnan(ps)
                    dist = dist * ps;
                end
            else
                if ~isnan(ps)
                    [dist, intensity] = imaging.lineProfile(appData.filteredPixels, ...
                        x1, y1, x2, y2, PixelSize=ps, PixelUnit=pu, ...
                        TiltAngle=tiltDeg, TiltAxis=tiltAxis, Geometry=tiltGeom);
                else
                    [dist, intensity] = imaging.lineProfile(appData.filteredPixels, ...
                        x1, y1, x2, y2, TiltAngle=tiltDeg, TiltAxis=tiltAxis, ...
                        Geometry=tiltGeom);
                end
            end
        catch ME
            uialert(fig, sprintf('Line profile failed:\n%s', ME.message), ...
                'Error', 'Icon', 'error');
            return;
        end

        % Store for CSV export
        appData.lastProfile = struct('dist', dist, 'intensity', intensity, 'unit', pu);
        btnExportProfile.Enable = 'on';

        % Status bar
        [dVal, dUnit] = imaging.measureDistance(x1, y1, x2, y2, ...
            PixelSize=ps, PixelUnit=pu, ...
            TiltAngle=tiltDeg, TiltAxis=tiltAxis, Geometry=tiltGeom);
        tiltTag = '';
        if tiltActive, tiltTag = sprintf(' (tilt %.1f°)', tiltDeg); end
        if ~isnan(ps)
            setStatus(sprintf('Line profile: %.4g %s%s', dVal, dUnit, tiltTag));
        else
            setStatus(sprintf('Line profile: %.1f px%s', dVal, tiltTag));
        end

        % Open or update profile figure
        pfig = findobj(0, 'Type', 'figure', 'Name', 'Line Profile');
        if isempty(pfig)
            pfig = figure('Name', 'Line Profile', 'NumberTitle', 'off', ...
                'Units', 'pixels', 'Position', [200 200 560 300]);
        else
            figure(pfig(1));
            pfig = pfig(1);
        end
        pax = findobj(pfig, 'Type', 'axes');
        if isempty(pax)
            pax = axes(pfig);
        else
            cla(pax(1));
            pax = pax(1);
        end
        plot(pax, dist, intensity, 'Color', [0 0.4 0.8], 'LineWidth', 1.2);
        grid(pax, 'on');
        if ~isnan(ps)
            xlabel(pax, sprintf('Distance (%s)', pu));
        else
            xlabel(pax, 'Distance (px)');
        end
        ylabel(pax, 'Intensity');
        title(pax, 'Line Profile', 'Interpreter', 'none');
        box(pax, 'on');
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: startEndpointDrag — Drag a line endpoint to update measurement
    % ════════════════════════════════════════════════════════════════════
    function startEndpointDrag(measIdx, whichEnd)
        % whichEnd: 1 = start (P1), 2 = end (P2)
        if measIdx > numel(appData.overlays.measurements)
            return;
        end
        meas = appData.overlays.measurements{measIdx};
        if ~isvalid(meas.hLine)
            return;
        end

        % Select this measurement (highlight + enable Delete key)
        selectMeasurement(measIdx);

        % Store original callbacks
        origMotionFcn  = fig.WindowButtonMotionFcn;
        origReleaseFcn = fig.WindowButtonUpFcn;

        fig.Pointer = 'crosshair';
        fig.WindowButtonMotionFcn = @dragMotion;
        fig.WindowButtonUpFcn    = @dragRelease;

        function dragMotion(~, ~)
            cp = ax.CurrentPoint;
            nx = cp(1,1);
            ny = cp(1,2);

            % Clamp to image bounds
            if ~isempty(appData.displayImg)
                [H, W] = size(appData.filteredPixels);
                nx = max(0.5, min(W + 0.5, nx));
                ny = max(0.5, min(H + 0.5, ny));
            end

            % Update endpoint marker position. The marker is a 3-point
            % line (horizontal tick with a circle at index 2); preserve
            % its existing tick half-length while re-centering on (nx, ny).
            if whichEnd == 1
                rTick = (meas.hP1.XData(end) - meas.hP1.XData(1)) / 2;
                meas.hP1.XData = [nx - rTick, nx, nx + rTick];
                meas.hP1.YData = [ny, ny, ny];
                meas.hLine.XData(1) = nx;
                meas.hLine.YData(1) = ny;
            else
                rTick = (meas.hP2.XData(end) - meas.hP2.XData(1)) / 2;
                meas.hP2.XData = [nx - rTick, nx, nx + rTick];
                meas.hP2.YData = [ny, ny, ny];
                meas.hLine.XData(2) = nx;
                meas.hLine.YData(2) = ny;
            end

            % Update distance label position (perpendicular offset) during
            % drag. Math is kept in sync with the inlined block in
            % createDistanceLabel above — see the header comment there
            % for why this isn't a shared helper (nested-fn budget).
            if ~isempty(meas.hText) && isvalid(meas.hText)
                x1d_ = meas.hLine.XData(1); y1d_ = meas.hLine.YData(1);
                x2d_ = meas.hLine.XData(2); y2d_ = meas.hLine.YData(2);
                mx_ = (x1d_ + x2d_) / 2;
                my_ = (y1d_ + y2d_) / 2;
                dx_ = x2d_ - x1d_;  dy_ = y2d_ - y1d_;
                len_ = hypot(dx_, dy_);
                if len_ < eps
                    nx_ = 0;  ny_ = -1;
                else
                    nx_ = -dy_ / len_;  ny_ = dx_ / len_;
                    if ny_ > 0, nx_ = -nx_; ny_ = -ny_; end
                end
                lx_ = mx_ + 14 * nx_;
                ly_ = my_ + 14 * ny_;
                if ~isempty(appData.filteredPixels)
                    [H_, W_] = size(appData.filteredPixels);
                    if lx_ < 1 || lx_ > W_ || ly_ < 1 || ly_ > H_
                        lx_ = mx_ - 14 * nx_;
                        ly_ = my_ - 14 * ny_;
                    end
                end
                meas.hText.Position = [lx_, ly_, 0];
            end
        end

        function dragRelease(~, ~)
            fig.WindowButtonMotionFcn = origMotionFcn;
            fig.WindowButtonUpFcn    = origReleaseFcn;
            fig.Pointer = 'arrow';

            % Read final positions
            x1 = meas.hLine.XData(1);
            y1 = meas.hLine.YData(1);
            x2 = meas.hLine.XData(2);
            y2 = meas.hLine.YData(2);

            % Update the stored record
            appData.overlays.measurements{measIdx} = meas;

            % Re-run the measurement
            switch meas.type
                case 'profile'
                    runProfile(x1, y1, x2, y2);
                case 'distance'
                    % Update the distance label text
                    if ~isempty(meas.hText) && isvalid(meas.hText)
                        delete(meas.hText);
                    end
                    newTxt = createDistanceLabel(x1, y1, x2, y2);
                    meas.hText = newTxt;
                    appData.overlays.measurements{measIdx} = meas;
                    setStatus(sprintf('Distance: %s', newTxt.String));
                    % Update distLabels reference
                    appData.overlays.distLabels{end+1} = newTxt;
            end

            % Clear the yellow selection highlight that startEndpointDrag
            % applied — the endpoint marker reverts to the normal hollow
            % overlay color so the user sees exactly what is persisted.
            deselectMeasurement();
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: clearAllOverlays — Delete all measurement graphics objects
    % ════════════════════════════════════════════════════════════════════
    function clearAllOverlays()
        % Scale bar
        deleteScaleBar();

        % Measurement records (draggable endpoints)
        for ci = 1:numel(appData.overlays.measurements)
            m = appData.overlays.measurements{ci};
            if isfield(m, 'hP1') && isvalid(m.hP1), delete(m.hP1); end
            if isfield(m, 'hP2') && isvalid(m.hP2), delete(m.hP2); end
            if isfield(m, 'hText') && ~isempty(m.hText) && isvalid(m.hText)
                delete(m.hText);
            end
        end
        appData.overlays.measurements = {};

        % Measurement lines
        for ci = 1:numel(appData.overlays.lines)
            h = appData.overlays.lines{ci};
            if isvalid(h)
                delete(h);
            end
        end
        appData.overlays.lines = {};

        for ci = 1:numel(appData.overlays.clickMarkers)
            h = appData.overlays.clickMarkers{ci};
            if isvalid(h)
                delete(h);
            end
        end
        appData.overlays.clickMarkers = {};

        % Distance text annotations
        for ci = 1:numel(appData.overlays.distLabels)
            h = appData.overlays.distLabels{ci};
            if isvalid(h)
                delete(h);
            end
        end
        appData.overlays.distLabels = {};

        % Text annotations
        for ci = 1:numel(appData.overlays.textAnnotations)
            a = appData.overlays.textAnnotations{ci};
            if isfield(a, 'hText') && isvalid(a.hText)
                delete(a.hText);
            end
        end
        appData.overlays.textAnnotations = {};
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: deleteScaleBar — Remove scale bar graphics handles if present
    % ════════════════════════════════════════════════════════════════════
    function deleteScaleBar()
        % Delete single-view scale bar
        deleteScaleBarHandle(appData.overlays.scalebar);
        appData.overlays.scalebar = [];
        % Delete compare-mode scale bars
        deleteScaleBarHandle(appData.overlays.scalebarL);
        appData.overlays.scalebarL = [];
        deleteScaleBarHandle(appData.overlays.scalebarR);
        appData.overlays.scalebarR = [];
    end

    function deleteScaleBarHandle(sb)
        if ~isempty(sb) && isstruct(sb)
            if isfield(sb, 'bar') && isvalid(sb.bar), delete(sb.bar); end
            if isfield(sb, 'label') && isvalid(sb.label), delete(sb.label); end
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: makeScaleBarDraggable — attach ButtonDownFcn for dragging
    % ════════════════════════════════════════════════════════════════════
    function makeScaleBarDraggable(hBar)
        % Both the rectangle and label trigger the same drag behaviour.
        % On mouse-down, record the initial position offset, then track
        % mouse motion and release via temporary figure callbacks.

        if ~isstruct(hBar), return; end

        % Determine which axes this scale bar lives on
        if isfield(hBar, 'bar') && isvalid(hBar.bar)
            dragAx = ancestor(hBar.bar, 'axes');
            hBar.bar.ButtonDownFcn = @(~,~) startScaleBarDrag(hBar, dragAx);
        end
        if isfield(hBar, 'label') && isvalid(hBar.label)
            dragAx = ancestor(hBar.label, 'axes');
            hBar.label.ButtonDownFcn = @(~,~) startScaleBarDrag(hBar, dragAx);
        end
    end

    function startScaleBarDrag(sb, dragAx)
        if isempty(sb) || ~isstruct(sb), return; end
        if isempty(dragAx) || ~isvalid(dragAx), return; end

        % Current bar position: [x y w h]
        barPos  = sb.bar.Position;
        labelPt = [sb.label.Position(1), sb.label.Position(2)];

        % Get click location in data coords
        cp = dragAx.CurrentPoint;
        startX = cp(1,1);
        startY = cp(1,2);

        % Store original callbacks to restore on release
        origMotionFcn  = fig.WindowButtonMotionFcn;
        origReleaseFcn = fig.WindowButtonUpFcn;

        fig.WindowButtonMotionFcn = @dragMotion;
        fig.WindowButtonUpFcn    = @dragRelease;

        function dragMotion(~, ~)
            cp2 = dragAx.CurrentPoint;
            dx = cp2(1,1) - startX;
            dy = cp2(1,2) - startY;

            % Move rectangle
            sb.bar.Position(1) = barPos(1) + dx;
            sb.bar.Position(2) = barPos(2) + dy;

            % Move label
            sb.label.Position = [labelPt(1) + dx, labelPt(2) + dy, 0];
        end

        function dragRelease(~, ~)
            fig.WindowButtonMotionFcn = origMotionFcn;
            fig.WindowButtonUpFcn    = origReleaseFcn;
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: startLabelDrag — Drag a distance label to reposition it
    % ════════════════════════════════════════════════════════════════════
    function startLabelDrag(hT)
        origMotionFcn  = fig.WindowButtonMotionFcn;
        origReleaseFcn = fig.WindowButtonUpFcn;
        cp0    = ax.CurrentPoint;
        origPos = hT.Position;
        fig.Pointer = 'fleur';
        fig.WindowButtonMotionFcn = @lblDragMotion;
        fig.WindowButtonUpFcn    = @lblDragRelease;

        function lblDragMotion(~, ~)
            cp = ax.CurrentPoint;
            hT.Position = [origPos(1) + (cp(1,1) - cp0(1,1)), ...
                           origPos(2) + (cp(1,2) - cp0(1,2)), 0];
        end

        function lblDragRelease(~, ~)
            fig.WindowButtonMotionFcn = origMotionFcn;
            fig.WindowButtonUpFcn    = origReleaseFcn;
            fig.Pointer = 'arrow';
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: setLabelFontSize — Apply font size to a label and all peers
    % ════════════════════════════════════════════════════════════════════
    function setLabelFontSize(hT)
        resp = inputdlg('Font size (pt):', 'Label font size', 1, ...
            {num2str(hT.FontSize)});
        if isempty(resp), return; end
        fs = str2double(resp{1});
        if isnan(fs) || fs < 6 || fs > 72, return; end
        for k = 1:numel(appData.overlays.distLabels)
            lh = appData.overlays.distLabels{k};
            if ~isempty(lh) && isvalid(lh)
                lh.FontSize = fs;
            end
        end
        spnMeasLabelFont.Value = fs;
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onMeasLabelFontChange — Panel spinner updates all labels
    % ════════════════════════════════════════════════════════════════════
    function onMeasLabelFontChange(fs)
        for k = 1:numel(appData.overlays.distLabels)
            lh = appData.overlays.distLabels{k};
            if ~isempty(lh) && isvalid(lh)
                lh.FontSize = fs;
            end
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onRotateFlip — Rotate or flip the image
    % ════════════════════════════════════════════════════════════════════
    function onRotateFlip(mode)
        if isempty(appData.rawPixels)
            return;
        end

        undoPush();

        switch mode
            case 'rot90cw'
                appData.rawPixels      = rot90(appData.rawPixels, -1);
                appData.filteredPixels = rot90(appData.filteredPixels, -1);
                msg = 'Rotated 90° CW';
            case 'rot90ccw'
                appData.rawPixels      = rot90(appData.rawPixels, 1);
                appData.filteredPixels = rot90(appData.filteredPixels, 1);
                msg = 'Rotated 90° CCW';
            case 'fliph'
                appData.rawPixels      = fliplr(appData.rawPixels);
                appData.filteredPixels = fliplr(appData.filteredPixels);
                msg = 'Flipped horizontally';
            case 'flipv'
                appData.rawPixels      = flipud(appData.rawPixels);
                appData.filteredPixels = flipud(appData.filteredPixels);
                msg = 'Flipped vertically';
            otherwise
                return;
        end

        % Rebuild display (need new imagesc for changed dimensions on rotation)
        [H, W] = size(appData.filteredPixels);
        lo = sldLow.Value;
        hi = sldHigh.Value;
        appData.displayPixels = [];    % invalidate downsample cache
        prepareDisplayBuffer();
        dispImg = applyContrastPipeline(appData.displayPixels, lo, hi);
        appData.displayImg = dispImg;

        delete(ax.Children);
        cla(ax);
        dr = appData.displayRegion;
        if isempty(dr), dr = [1, 1, W, H]; end
        hImg = imagesc(ax, 'XData', [dr(1) dr(3)], 'YData', [dr(2) dr(4)], 'CData', dispImg);
        try, hImg.Interpolation = 'nearest'; catch, end
        appData.imgHandle = hImg;
        attachImageContextMenu();
        cmapName = ddColormap.Value;
        colormap(ax, feval(cmapName, 256));
        ax.CLim = [0 1];
        ax.YDir = 'reverse';
        axis(ax, 'equal');
        ax.XLim = [0.5, W + 0.5];
        ax.YLim = [0.5, H + 0.5];
        ax.XTick = [];
        ax.YTick = [];
        ax.Toolbar.Visible = 'off';

        % Rebuild colorbar if visible
        if cbColorbar.Value
            if ~isempty(hColorbar) && isvalid(hColorbar)
                delete(hColorbar);
            end
            hColorbar = colorbar(ax);
        end

        clearAllOverlays();
        if ~isempty(cbScaleBar) && isvalid(cbScaleBar) && ...
                strcmp(cbScaleBar.Enable, 'on') && cbScaleBar.Value
            rebuildScaleBar();
        end
        setStatus(msg);
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onCLAHE — Contrast-Limited Adaptive Histogram Equalization
    % ════════════════════════════════════════════════════════════════════
    function onCLAHE(~, ~)
        if isempty(appData.filteredPixels)
            return;
        end

        answer = inputdlg( ...
            {'Tile size (pixels per tile, e.g. 64):', ...
             'Clip limit (contrast factor, e.g. 3.0):'}, ...
            'CLAHE Parameters', [1 44], {'64', '3.0'});
        if isempty(answer)
            return;
        end

        tileSize  = round(str2double(answer{1}));
        clipLimit = str2double(answer{2});
        if isnan(tileSize) || tileSize < 8
            uialert(fig, 'Tile size must be >= 8.', 'Invalid Input', 'Icon', 'error');
            return;
        end
        if isnan(clipLimit) || clipLimit <= 0
            uialert(fig, 'Clip limit must be positive.', 'Invalid Input', 'Icon', 'error');
            return;
        end

        fig.Pointer = 'watch';
        drawnow;

        try
            undoPush();
            appData.filteredPixels = applyCLAHE(appData.filteredPixels, tileSize, clipLimit);
            refreshDisplay();
            setStatus(sprintf('CLAHE applied (tile=%d, clip=%.1f)', tileSize, clipLimit));
        catch ME
            uialert(fig, sprintf('CLAHE failed:\n%s', ME.message), ...
                'Filter Error', 'Icon', 'error');
        end

        fig.Pointer = 'arrow';
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: applyCLAHE — No-toolbox CLAHE implementation
    %  Tiles the image, computes clipped local histograms, bilinear-
    %  interpolates the mappings across tile boundaries.
    % ════════════════════════════════════════════════════════════════════
    function out = applyCLAHE(img, tileSize, clipLimit)
        [H, W] = size(img);

        % Normalize to [0, 1]
        dMin = min(img(:));
        dMax = max(img(:));
        if dMax == dMin, dMax = dMin + 1; end
        imgNorm = (img - dMin) / (dMax - dMin);

        nBins = 256;
        nTilesR = max(1, round(H / tileSize));
        nTilesC = max(1, round(W / tileSize));
        tileH = H / nTilesR;
        tileW = W / nTilesC;

        % Compute clipped CDF for each tile
        mappings = cell(nTilesR, nTilesC);
        for tr = 1:nTilesR
            r1 = round((tr-1) * tileH) + 1;
            r2 = min(H, round(tr * tileH));
            for tc = 1:nTilesC
                c1 = round((tc-1) * tileW) + 1;
                c2 = min(W, round(tc * tileW));
                tile = imgNorm(r1:r2, c1:c2);

                % Histogram
                counts = histcounts(tile(:), linspace(0, 1, nBins+1));

                % Clip and redistribute
                nPix = numel(tile);
                clipCount = clipLimit * (nPix / nBins);
                excess = sum(max(0, counts - clipCount));
                counts = min(counts, clipCount);
                counts = counts + excess / nBins;

                % CDF as mapping table
                cdf = cumsum(counts);
                if cdf(end) == 0
                    cdf = linspace(0, 1, nBins);  % uniform tile fallback
                else
                    cdf = cdf / cdf(end);
                end
                mappings{tr, tc} = cdf;
            end
        end

        % Apply mappings with bilinear interpolation
        out = zeros(H, W);
        for r = 1:H
            % Which tiles does this row relate to?
            ty = (r - 0.5) / tileH - 0.5;   % tile-space coord (0-based)
            tr1 = max(1, floor(ty) + 1);
            tr2 = min(nTilesR, tr1 + 1);
            fy = ty - (tr1 - 1);  % fractional position [0, 1]
            fy = max(0, min(1, fy));

            for c = 1:W
                tx = (c - 0.5) / tileW - 0.5;
                tc1 = max(1, floor(tx) + 1);
                tc2 = min(nTilesC, tc1 + 1);
                fx = tx - (tc1 - 1);
                fx = max(0, min(1, fx));

                % Bin index for this pixel
                val = imgNorm(r, c);
                bin = max(1, min(nBins, round(val * (nBins-1)) + 1));

                % Bilinear interpolation of 4 tile CDFs
                v11 = mappings{tr1, tc1}(bin);
                v12 = mappings{tr1, tc2}(bin);
                v21 = mappings{tr2, tc1}(bin);
                v22 = mappings{tr2, tc2}(bin);

                mapped = (1-fy) * ((1-fx)*v11 + fx*v12) + ...
                          fy    * ((1-fx)*v21 + fx*v22);
                out(r, c) = mapped;
            end
        end

        % Rescale back to original range
        out = out * (dMax - dMin) + dMin;
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onROIStats — Draw rectangle ROI and show statistics
    % ════════════════════════════════════════════════════════════════════
    function onROIStats(~, ~)
        if appData.activeIdx < 1 || isempty(appData.displayImg)
            return;
        end
        if appData.compareMode
            return;
        end
        startRectCapture('roistats');
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onAngleMeasure — Three-click angle measurement
    % ════════════════════════════════════════════════════════════════════
    function onAngleMeasure(~, ~)
        if appData.activeIdx < 1 || isempty(appData.displayImg)
            return;
        end
        if appData.compareMode
            return;
        end
        if ~isempty(appData.captureMode)
            cancelCapture();
        end

        appData.captureMode = 'angle';
        appData.captureClicks = [];
        fig.Pointer = 'crosshair';
        fig.WindowButtonDownFcn = @onAngleClick;
        setStatus('Click vertex point (1 of 3)... (Esc to cancel)');
    end

    function onAngleClick(~, ~)
        if ~strcmp(appData.captureMode, 'angle')
            return;
        end

        cp = ax.CurrentPoint;
        x = cp(1,1);
        y = cp(1,2);

        % Validate within image bounds
        if isempty(appData.displayImg), return; end
        [H, W] = size(appData.filteredPixels);
        if x < 0.5 || x > W + 0.5 || y < 0.5 || y > H + 0.5
            return;
        end

        appData.captureClicks(end+1, :) = [x, y];
        nClicks = size(appData.captureClicks, 1);

        % Draw marker
        hM = line(ax, x, y, ...
            'Marker', 'o', 'MarkerSize', 8, ...
            'MarkerFaceColor', OVERLAY_COLOR, ...
            'MarkerEdgeColor', 'none', ...
            'LineStyle', 'none', ...
            'HandleVisibility', 'off');
        appData.overlays.clickMarkers{end+1} = hM;

        if nClicks == 1
            setStatus('Click first ray endpoint (2 of 3)... (Esc to cancel)');
        elseif nClicks == 2
            % Draw line from vertex to first ray
            pts = appData.captureClicks;
            hL = line(ax, [pts(1,1) pts(2,1)], [pts(1,2) pts(2,2)], ...
                'Color', OVERLAY_COLOR, 'LineWidth', 1.5, ...
                'HandleVisibility', 'off');
            appData.overlays.lines{end+1} = hL;
            setStatus('Click second ray endpoint (3 of 3)... (Esc to cancel)');
        elseif nClicks >= 3
            % Draw second ray and compute angle
            pts = appData.captureClicks;
            hL2 = line(ax, [pts(1,1) pts(3,1)], [pts(1,2) pts(3,2)], ...
                'Color', OVERLAY_COLOR, 'LineWidth', 1.5, ...
                'HandleVisibility', 'off');
            appData.overlays.lines{end+1} = hL2;

            % Compute angle at vertex (pts(1,:)). When tilt correction is
            % active, unfold the foreshortened axis for the angle math so
            % that a right-angle feature in the true sample frame reads 90°
            % instead of a projected value. The arc visualization still
            % uses the raw (image-space) vectors because that's what the
            % user sees on the image.
            v1 = pts(2,:) - pts(1,:);
            v2 = pts(3,:) - pts(1,:);
            [tiltDeg, tiltAxis, tiltActive, tiltGeom] = getTiltState();
            vc1 = v1; vc2 = v2;
            if tiltActive
                % Cross-section (default) uses 1/sin; plan-view surface
                % uses 1/cos. See imaging.measureDistance doc for the
                % physics derivation.
                if strcmpi(tiltGeom, 'Surface')
                    scl = 1 / cosd(tiltDeg);
                else
                    scl = 1 / sind(tiltDeg);
                end
                if strcmpi(tiltAxis, 'Y')
                    vc1(2) = v1(2) * scl; vc2(2) = v2(2) * scl;
                else
                    vc1(1) = v1(1) * scl; vc2(1) = v2(1) * scl;
                end
            end
            cosA = dot(vc1, vc2) / (norm(vc1) * norm(vc2) + eps);
            cosA = max(-1, min(1, cosA));   % clamp for acosd
            angleDeg = acosd(cosA);

            % Draw arc to visualize the angle (use raw image-space vectors)
            arcRadius = min(norm(v1), norm(v2)) * 0.3;
            a1 = atan2d(v1(2), v1(1));
            a2 = atan2d(v2(2), v2(1));
            % Ensure arc goes the short way
            if abs(a2 - a1) > 180
                if a2 > a1
                    a1 = a1 + 360;
                else
                    a2 = a2 + 360;
                end
            end
            arcAngles = linspace(a1, a2, 40);
            arcX = pts(1,1) + arcRadius * cosd(arcAngles);
            arcY = pts(1,2) + arcRadius * sind(arcAngles);
            hArc = line(ax, arcX, arcY, ...
                'Color', OVERLAY_COLOR, 'LineWidth', 1, ...
                'LineStyle', '--', ...
                'HandleVisibility', 'off');
            appData.overlays.lines{end+1} = hArc;

            % Label at midpoint of arc
            midAngle = (a1 + a2) / 2;
            labelX = pts(1,1) + arcRadius * 1.4 * cosd(midAngle);
            labelY = pts(1,2) + arcRadius * 1.4 * sind(midAngle);
            angleStr = sprintf('%.1f°', angleDeg);
            if tiltActive, angleStr = [angleStr, '*']; end
            hLabel = text(ax, labelX, labelY, angleStr, ...
                'Color', OVERLAY_COLOR, 'FontSize', 12, ...
                'FontWeight', 'bold', ...
                'HorizontalAlignment', 'center', ...
                'HandleVisibility', 'off');
            appData.overlays.distLabels{end+1} = hLabel;

            % Clean up temporary click markers (keep lines and labels)
            for ci = 1:numel(appData.overlays.clickMarkers)
                h = appData.overlays.clickMarkers{ci};
                if isvalid(h), delete(h); end
            end
            appData.overlays.clickMarkers = {};

            finishCapture();
            tiltTag = '';
            if tiltActive, tiltTag = sprintf(' [tilt %.1f°]', tiltDeg); end
            setStatus(sprintf('Angle: %.1f°%s', angleDeg, tiltTag));

            % Log measurement
            detailStr = sprintf('vertex=(%.0f,%.0f)', pts(1,1), pts(1,2));
            if tiltActive
                detailStr = sprintf('%s tilt=%.2f° axis=%s', detailStr, tiltDeg, tiltAxis);
            end
            appData.measurementLog{end+1} = struct( ...
                'type', 'angle', 'value', angleDeg, 'unit', 'deg', ...
                'details', detailStr, ...
                'timestamp', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')));
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onPolylineMeasure — Multi-point distance measurement
    % ════════════════════════════════════════════════════════════════════
    function onPolylineMeasure(~, ~)
        if appData.activeIdx < 1 || isempty(appData.displayImg)
            return;
        end
        if appData.compareMode
            return;
        end
        if ~isempty(appData.captureMode)
            cancelCapture();
        end

        appData.captureMode = 'polyline';
        appData.captureClicks = [];
        fig.Pointer = 'crosshair';
        fig.WindowButtonDownFcn = @onPolylineClick;
        setStatus('Click points to measure path length; double-click to finish (Esc to cancel)');
    end

    function onPolylineClick(~, ~)
        if ~strcmp(appData.captureMode, 'polyline')
            return;
        end

        cp = ax.CurrentPoint;
        x = cp(1,1);
        y = cp(1,2);

        if isempty(appData.displayImg), return; end
        [H, W] = size(appData.filteredPixels);
        if x < 0.5 || x > W + 0.5 || y < 0.5 || y > H + 0.5
            return;
        end

        % Check for double-click BEFORE adding the point (avoids duplicate)
        isDoubleClick = false;
        if isprop(fig, 'SelectionType')
            isDoubleClick = strcmp(fig.SelectionType, 'open');
        end

        if isDoubleClick && size(appData.captureClicks, 1) >= 2
            % Double-click finishes — do NOT add the duplicate point
            pts = appData.captureClicks;

            % Sum segment lengths with optional per-segment tilt correction.
            % Correcting each segment (not the overall bounding box) is the
            % correct approach: the tilt stretches one axis uniformly, so
            % total true-path = sum of true-segment-lengths.
            [tiltDeg, tiltAxis, tiltActive, tiltGeom] = getTiltState();
            totalDist = 0;
            for si = 2:size(pts, 1)
                if tiltActive
                    segLen = imaging.measureDistance( ...
                        pts(si-1,1), pts(si-1,2), pts(si,1), pts(si,2), ...
                        TiltAngle=tiltDeg, TiltAxis=tiltAxis, Geometry=tiltGeom);
                else
                    segLen = sqrt((pts(si,1) - pts(si-1,1))^2 + ...
                                  (pts(si,2) - pts(si-1,2))^2);
                end
                totalDist = totalDist + segLen;
            end

            % Convert to calibrated units if available
            unitStr = 'px';
            if appData.activeIdx >= 1
                imgInfo = appData.images{appData.activeIdx}.metadata.parserSpecific.imageData;
                if imgInfo.calibrated && ~isnan(imgInfo.pixelSize)
                    totalDist = totalDist * imgInfo.pixelSize;
                    unitStr = imgInfo.pixelUnit;
                end
            end

            nSegs = size(pts, 1) - 1;

            % Label at midpoint of polyline
            midIdx = max(1, round(size(pts, 1) / 2));
            labelStr = sprintf('%.2f %s', totalDist, unitStr);
            if tiltActive, labelStr = [labelStr, '*']; end
            hLabel = text(ax, pts(midIdx, 1), pts(midIdx, 2), labelStr, ...
                'Color', OVERLAY_COLOR, 'FontSize', 11, ...
                'FontWeight', 'bold', ...
                'HorizontalAlignment', 'center', ...
                'VerticalAlignment', 'bottom', ...
                'HandleVisibility', 'off');
            appData.overlays.distLabels{end+1} = hLabel;

            finishCapture();
            tiltTag = '';
            if tiltActive, tiltTag = sprintf(' [tilt %.1f°]', tiltDeg); end
            setStatus(sprintf('Polyline: %.2f %s (%d segments)%s', ...
                totalDist, unitStr, nSegs, tiltTag));

            % Log measurement
            detailStr = sprintf('%d segments', nSegs);
            if tiltActive
                detailStr = sprintf('%s tilt=%.2f° axis=%s', detailStr, tiltDeg, tiltAxis);
            end
            appData.measurementLog{end+1} = struct( ...
                'type', 'polyline', 'value', totalDist, 'unit', unitStr, ...
                'details', detailStr, ...
                'timestamp', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')));
            return;
        end

        % Single click — add point
        appData.captureClicks(end+1, :) = [x, y];
        nPts = size(appData.captureClicks, 1);

        % Draw marker
        hM = line(ax, x, y, ...
            'Marker', 'o', 'MarkerSize', 6, ...
            'MarkerFaceColor', OVERLAY_COLOR, ...
            'MarkerEdgeColor', 'none', ...
            'LineStyle', 'none', ...
            'HandleVisibility', 'off');
        appData.overlays.clickMarkers{end+1} = hM;

        % Draw line segment from previous point
        if nPts >= 2
            px = appData.captureClicks(nPts-1, 1);
            py = appData.captureClicks(nPts-1, 2);
            hL = line(ax, [px x], [py y], ...
                'Color', OVERLAY_COLOR, 'LineWidth', 1.5, ...
                'HandleVisibility', 'off');
            appData.overlays.lines{end+1} = hL;
        end

        setStatus(sprintf('Point %d placed — click next or double-click to finish', nPts));
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: executeAngleFromPoints — Headless angle measurement
    % ════════════════════════════════════════════════════════════════════
    function angleDeg = executeAngleFromPoints(pts)
    %EXECUTEANGLEFROMPOINTS  Measure/draw/log angle from 3 points.
    %   pts is a 3x2 matrix: [vertex; ray1; ray2]. Draws both rays, an
    %   arc annotation, and a degree label. Appends to appData.measurementLog.
    %   Returns the angle in degrees.
    %
    %   Used by api.measureAngle to bypass the interactive click-capture
    %   flow in onAngleMeasure/onAngleClick.
        if appData.activeIdx < 1 || isempty(appData.displayImg)
            angleDeg = NaN; return;
        end
        if ~isequal(size(pts), [3 2])
            error('FermiViewer:badInput', 'executeAngleFromPoints: pts must be 3x2');
        end

        v1 = pts(2,:) - pts(1,:);
        v2 = pts(3,:) - pts(1,:);
        nrm = norm(v1) * norm(v2);
        if nrm < eps
            angleDeg = NaN; return;
        end
        cosA = dot(v1, v2) / nrm;
        cosA = max(-1, min(1, cosA));
        angleDeg = acosd(cosA);

        % Draw the two rays
        hL1 = line(ax, [pts(1,1) pts(2,1)], [pts(1,2) pts(2,2)], ...
            'Color', OVERLAY_COLOR, 'LineWidth', 1.5, 'HandleVisibility', 'off');
        appData.overlays.lines{end+1} = hL1;
        hL2 = line(ax, [pts(1,1) pts(3,1)], [pts(1,2) pts(3,2)], ...
            'Color', OVERLAY_COLOR, 'LineWidth', 1.5, 'HandleVisibility', 'off');
        appData.overlays.lines{end+1} = hL2;

        % Arc annotation
        arcRadius = min(norm(v1), norm(v2)) * 0.3;
        a1 = atan2d(v1(2), v1(1));
        a2 = atan2d(v2(2), v2(1));
        if abs(a2 - a1) > 180
            if a2 > a1, a1 = a1 + 360; else, a2 = a2 + 360; end
        end
        arcAngles = linspace(a1, a2, 40);
        arcX = pts(1,1) + arcRadius * cosd(arcAngles);
        arcY = pts(1,2) + arcRadius * sind(arcAngles);
        hArc = line(ax, arcX, arcY, ...
            'Color', OVERLAY_COLOR, 'LineWidth', 1, 'LineStyle', '--', ...
            'HandleVisibility', 'off');
        appData.overlays.lines{end+1} = hArc;

        % Label at midpoint of arc
        midAngle = (a1 + a2) / 2;
        labelX = pts(1,1) + arcRadius * 1.4 * cosd(midAngle);
        labelY = pts(1,2) + arcRadius * 1.4 * sind(midAngle);
        hLabel = text(ax, labelX, labelY, sprintf('%.1f°', angleDeg), ...
            'Color', OVERLAY_COLOR, 'FontSize', 12, 'FontWeight', 'bold', ...
            'HorizontalAlignment', 'center', 'HandleVisibility', 'off');
        appData.overlays.distLabels{end+1} = hLabel;

        appData.measurementLog{end+1} = struct( ...
            'type', 'angle', 'value', angleDeg, 'unit', 'deg', ...
            'details', sprintf('vertex=(%.0f,%.0f)', pts(1,1), pts(1,2)), ...
            'timestamp', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')));
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: executePolylineFromPoints — Headless polyline length
    % ════════════════════════════════════════════════════════════════════
    function totalDist = executePolylineFromPoints(pts)
    %EXECUTEPOLYLINEFROMPOINTS  Measure/draw/log polyline path length.
    %   pts is an Nx2 matrix of (x,y) vertices (N >= 2). Draws each
    %   vertex marker, connecting line segments, and a total-length label,
    %   then appends to appData.measurementLog. Returns length in
    %   calibrated units when the image has pixel calibration, otherwise
    %   in pixels.
        if appData.activeIdx < 1 || isempty(appData.displayImg)
            totalDist = NaN; return;
        end
        if size(pts, 2) ~= 2 || size(pts, 1) < 2
            error('FermiViewer:badInput', ...
                'executePolylineFromPoints: pts must be Nx2 with N>=2');
        end

        % Draw vertex markers and segments
        for pi = 1:size(pts, 1)
            hM = line(ax, pts(pi,1), pts(pi,2), ...
                'Marker', 'o', 'MarkerSize', 6, ...
                'MarkerFaceColor', OVERLAY_COLOR, ...
                'MarkerEdgeColor', 'none', ...
                'LineStyle', 'none', 'HandleVisibility', 'off');
            appData.overlays.clickMarkers{end+1} = hM;
            if pi >= 2
                hL = line(ax, [pts(pi-1,1) pts(pi,1)], ...
                              [pts(pi-1,2) pts(pi,2)], ...
                    'Color', OVERLAY_COLOR, 'LineWidth', 1.5, ...
                    'HandleVisibility', 'off');
                appData.overlays.lines{end+1} = hL;
            end
        end

        % Total length
        totalDist = 0;
        for si = 2:size(pts, 1)
            totalDist = totalDist + sqrt( ...
                (pts(si,1) - pts(si-1,1))^2 + ...
                (pts(si,2) - pts(si-1,2))^2);
        end

        % Calibration
        unitStr = 'px';
        imgInfo = appData.images{appData.activeIdx}.metadata.parserSpecific.imageData;
        if imgInfo.calibrated && ~isnan(imgInfo.pixelSize)
            totalDist = totalDist * imgInfo.pixelSize;
            unitStr = imgInfo.pixelUnit;
        end

        % Label at midpoint
        midIdx = max(1, round(size(pts, 1) / 2));
        hLabel = text(ax, pts(midIdx, 1), pts(midIdx, 2), ...
            sprintf('%.2f %s', totalDist, unitStr), ...
            'Color', OVERLAY_COLOR, 'FontSize', 11, 'FontWeight', 'bold', ...
            'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
            'HandleVisibility', 'off');
        appData.overlays.distLabels{end+1} = hLabel;

        nSegs = size(pts, 1) - 1;
        appData.measurementLog{end+1} = struct( ...
            'type', 'polyline', 'value', totalDist, 'unit', unitStr, ...
            'details', sprintf('%d segments', nSegs), ...
            'timestamp', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')));
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onColorbarToggle — Show/hide colorbar
    % ════════════════════════════════════════════════════════════════════
    function onColorbarToggle(~, ~)
        if appData.activeIdx < 1 || isempty(ax) || ~isvalid(ax)
            return;
        end

        if cbColorbar.Value
            hColorbar = colorbar(ax);
        else
            if ~isempty(hColorbar) && isvalid(hColorbar)
                delete(hColorbar);
                hColorbar = [];
            end
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onSetPixelSize — Override pixel calibration
    % ════════════════════════════════════════════════════════════════════
    function onSetPixelSize(~, ~)
        if appData.activeIdx < 1
            return;
        end

        imgInfo = appData.images{appData.activeIdx}.metadata.parserSpecific.imageData;
        if imgInfo.calibrated && ~isnan(imgInfo.pixelSize)
            defSize = num2str(imgInfo.pixelSize);
            defUnit = imgInfo.pixelUnit;
        else
            defSize = '1.0';
            defUnit = 'nm';
        end

        answer = inputdlg( ...
            {'Pixel size:', 'Unit (nm, µm, Å, mm, etc.):'}, ...
            'Set Pixel Calibration', [1 36], {defSize, defUnit});
        if isempty(answer)
            return;
        end

        newSize = str2double(answer{1});
        newUnit = strtrim(answer{2});
        if isnan(newSize) || newSize <= 0
            uialert(fig, 'Pixel size must be a positive number.', ...
                'Invalid Input', 'Icon', 'error');
            return;
        end
        if isempty(newUnit)
            newUnit = 'px';
        end

        applyCalibration(newSize, newUnit);
        setStatus(sprintf('Pixel size set to %.4g %s/px', newSize, newUnit));
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onCalibrateBar — Calibrate pixel size from scale bar
    % ════════════════════════════════════════════════════════════════════
    function onCalibrateBar(~, ~)
        if appData.activeIdx < 1 || isempty(appData.displayImg)
            return;
        end

        % Offer choice: manual draw or auto-detect
        sel = uiconfirm(fig, ...
            ['Choose calibration method:' newline newline ...
             'DRAW — Click both ends of the scale bar, then enter the distance.' newline ...
             'AUTO-DETECT — Scan the image for a scale bar and suggest calibration.'], ...
            'Calibrate from Scale Bar', ...
            'Options', {'Draw on Bar', 'Auto-Detect', 'Cancel'}, ...
            'DefaultOption', 1, 'CancelOption', 3, ...
            'Icon', 'question');

        switch sel
            case 'Draw on Bar'
                startTwoClickCapture('scalebar');
            case 'Auto-Detect'
                autoDetectScaleBar();
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: executeScaleBarCalibration — After two clicks on scale bar
    % ════════════════════════════════════════════════════════════════════
    function executeScaleBarCalibration(x1, y1, x2, y2)
        % Draw overlay line where user clicked
        hLine = line(ax, [x1 x2], [y1 y2], ...
            'Color', [0 1 1], 'LineWidth', 2, 'LineStyle', '--', ...
            'HandleVisibility', 'off');

        % Compute pixel distance
        pxDist = sqrt((x2 - x1)^2 + (y2 - y1)^2);

        % Clean up click markers
        for ci = 1:numel(appData.overlays.clickMarkers)
            h = appData.overlays.clickMarkers{ci};
            if isvalid(h), delete(h); end
        end
        appData.overlays.clickMarkers = {};

        % Prompt for real distance with unit dropdown
        [realDist, realUnit, cancelled] = promptScaleBarDistance(pxDist);

        % Remove overlay line
        if isvalid(hLine), delete(hLine); end

        if cancelled, return; end

        % Compute pixel size = realDist / pxDist
        newPixelSize = realDist / pxDist;

        applyCalibration(newPixelSize, realUnit);
        setStatus(sprintf('Calibrated: %.4g %s/px (from %.1f px = %g %s)', ...
            newPixelSize, realUnit, pxDist, realDist, realUnit));
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: autoDetectScaleBar — Find scale bar in image automatically
    % ════════════════════════════════════════════════════════════════════
    function autoDetectScaleBar()
        fig.Pointer = 'watch'; drawnow;

        try
            px = double(appData.filteredPixels);
            [H, W] = size(px);

            % SEM/TEM scale bars are typically in the bottom 15% of the image,
            % often as a bright or dark horizontal bar on a data bar / info strip
            stripH = max(10, round(H * 0.15));
            strip = px(H - stripH + 1 : H, :);

            % Binarize the strip: look for the darkest or brightest regions
            % Many SEM images have a dark info bar at bottom with white scale bar
            stripMin = min(strip(:));
            stripMax = max(strip(:));
            stripRange = stripMax - stripMin;

            if stripRange < 1
                fig.Pointer = 'arrow';
                uialert(fig, 'Could not detect a scale bar (bottom strip is uniform).', ...
                    'Auto-Detect Failed', 'Icon', 'warning');
                return;
            end

            % Try both bright-on-dark and dark-on-bright
            stripNorm = (strip - stripMin) / stripRange;

            % Detect horizontal runs in each row
            bestBarLen = 0;
            bestBarRow = 0;
            bestBarX1  = 0;
            bestBarX2  = 0;

            for tryWhite = [true, false]
                if tryWhite
                    bw = stripNorm > 0.85;   % bright bar
                else
                    bw = stripNorm < 0.15;   % dark bar
                end

                % Find the longest horizontal run in each row
                for ri = 1:size(bw, 1)
                    row = bw(ri, :);
                    % Find runs of 1s
                    d = diff([0, row, 0]);
                    starts = find(d == 1);
                    ends   = find(d == -1) - 1;

                    for si = 1:numel(starts)
                        runLen = ends(si) - starts(si) + 1;
                        % Scale bars are typically 5-50% of image width,
                        % and at least 20 px, and narrow (1-10 px tall)
                        if runLen > bestBarLen && runLen >= 20 && ...
                                runLen >= W * 0.03 && runLen <= W * 0.60
                            % Verify it's a thin bar: check rows above/below
                            barHeight = 1;
                            for rr = ri+1:size(bw, 1)
                                sampCols = max(1, starts(si)+2) : min(W, ends(si)-2);
                                if numel(sampCols) < 3, break; end
                                if mean(bw(rr, sampCols)) > 0.7
                                    barHeight = barHeight + 1;
                                else
                                    break;
                                end
                            end
                            % Scale bars are thin: 1-15 px tall
                            if barHeight >= 1 && barHeight <= 15
                                bestBarLen  = runLen;
                                bestBarRow  = ri;
                                bestBarX1   = starts(si);
                                bestBarX2   = ends(si);
                            end
                        end
                    end
                end
            end

            if bestBarLen == 0
                fig.Pointer = 'arrow';
                uialert(fig, ...
                    ['Could not detect a scale bar in the bottom 15% of the image.' newline ...
                     'Use "Draw on Bar" instead.'], ...
                    'Auto-Detect Failed', 'Icon', 'warning');
                return;
            end

            % Convert strip-local coords to image coords
            barY = H - stripH + bestBarRow;
            barX1 = bestBarX1;
            barX2 = bestBarX2;

            % We can't truly know the bar value without OCR — just present the
            % pixel length and let the user type the real distance

            fig.Pointer = 'arrow';

            % Draw overlay showing detected bar
            barColor = [0 1 1];
            hBarLine = line(ax, [barX1 barX2], [barY barY], ...
                'Color', barColor, 'LineWidth', 3, 'LineStyle', '-', ...
                'HandleVisibility', 'off');
            hBarEnd1 = line(ax, [barX1 barX1], [barY-8 barY+8], ...
                'Color', barColor, 'LineWidth', 2, ...
                'HandleVisibility', 'off');
            hBarEnd2 = line(ax, [barX2 barX2], [barY-8 barY+8], ...
                'Color', barColor, 'LineWidth', 2, ...
                'HandleVisibility', 'off');
            hBarLabel = text(ax, (barX1 + barX2)/2, barY - 12, ...
                sprintf('%.0f px detected', bestBarLen), ...
                'Color', barColor, 'FontSize', 11, 'FontWeight', 'bold', ...
                'HorizontalAlignment', 'center', ...
                'BackgroundColor', [0.1 0.1 0.1], ...
                'HandleVisibility', 'off');

            drawnow;

            % Ask user to confirm and enter real distance with unit dropdown
            [realDist, realUnit, cancelled] = promptScaleBarDistance(bestBarLen);

            % Clean up overlay
            if isvalid(hBarLine),  delete(hBarLine);  end
            if isvalid(hBarEnd1),  delete(hBarEnd1);  end
            if isvalid(hBarEnd2),  delete(hBarEnd2);  end
            if isvalid(hBarLabel), delete(hBarLabel); end

            if cancelled, return; end

            newPixelSize = realDist / bestBarLen;
            applyCalibration(newPixelSize, realUnit);
            setStatus(sprintf('Calibrated: %.4g %s/px (auto-detected %0.f px = %g %s)', ...
                newPixelSize, realUnit, bestBarLen, realDist, realUnit));

        catch ME
            fig.Pointer = 'arrow';
            uialert(fig, sprintf('Auto-detect failed:\n%s', ME.message), ...
                'Error', 'Icon', 'error');
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: applyCalibration — Set pixel size and refresh UI
    % ════════════════════════════════════════════════════════════════════
    function applyCalibration(newPixelSize, newUnit)
        appData.images{appData.activeIdx}.metadata.parserSpecific.imageData.pixelSize  = newPixelSize;
        appData.images{appData.activeIdx}.metadata.parserSpecific.imageData.pixelUnit  = newUnit;
        appData.images{appData.activeIdx}.metadata.parserSpecific.imageData.calibrated = true;

        updateStatusBar();
        updateMetadataPanel();

        cbScaleBar.Enable       = 'on';
        btnScaleBarColor.Enable = 'on';
        spnScaleBarFont.Enable  = 'on';
        efScaleBarLen.Enable    = 'on';
        ddScaleBarUnit.Enable   = 'on';
        cbScaleBar.Value        = true;
        rebuildScaleBar();
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: promptScaleBarDistance — Modal dialog with distance + unit dropdown
    % ════════════════════════════════════════════════════════════════════
    function [dist, unit, cancelled] = promptScaleBarDistance(pxLen)
    %PROMPTSCALEBARDISTANCE  Show a dialog with distance field + unit dropdown.
    %   Returns dist (double), unit (char), cancelled (logical).
        UNITS = {char(197), 'nm', [char(181) 'm'], 'mm', 'cm', 'm'};  % Å, nm, µm, mm, cm, m

        cancelled = true;
        dist = 0;
        unit = 'nm';

        dlgFig = uifigure('Name', 'Scale Bar Distance', ...
            'Position', [400 350 320 170], ...
            'WindowStyle', 'modal', ...
            'Resize', 'off', ...
            'Color', [0.94 0.94 0.94]);

        dlgGL = uigridlayout(dlgFig, [5 2], ...
            'RowHeight', {20, 28, 28, 10, 32}, ...
            'ColumnWidth', {'1x', '1x'}, ...
            'Padding', [15 15 15 15], ...
            'RowSpacing', 6);

        % Info label
        lblInfo = uilabel(dlgGL, ...
            'Text', sprintf('Drawn line: %.1f px', pxLen), ...
            'FontWeight', 'bold', 'FontSize', 12);
        lblInfo.Layout.Row = 1; lblInfo.Layout.Column = [1 2];

        % Distance label + field
        lblDist = uilabel(dlgGL, 'Text', 'Distance:');
        lblDist.Layout.Row = 2;
        edDist = uieditfield(dlgGL, 'numeric', ...
            'Value', 1, 'Limits', [0 Inf], ...
            'LowerLimitInclusive', 'off');
        edDist.Layout.Row = 2; edDist.Layout.Column = 2;

        % Unit label + dropdown
        lblUnit = uilabel(dlgGL, 'Text', 'Unit:');
        lblUnit.Layout.Row = 3;
        ddUnit = uidropdown(dlgGL, 'Items', UNITS, 'Value', 'nm');
        ddUnit.Layout.Row = 3; ddUnit.Layout.Column = 2;

        % Buttons
        btnOK = uibutton(dlgGL, 'Text', 'OK', ...
            'ButtonPushedFcn', @(~,~) okCB());
        btnOK.Layout.Row = 5; btnOK.Layout.Column = 1;

        btnCancel = uibutton(dlgGL, 'Text', 'Cancel', ...
            'ButtonPushedFcn', @(~,~) delete(dlgFig));
        btnCancel.Layout.Row = 5; btnCancel.Layout.Column = 2;

        uiwait(dlgFig);

        function okCB()
            dist = edDist.Value;
            unit = ddUnit.Value;
            cancelled = false;
            delete(dlgFig);
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: selectMeasurement — Highlight a measurement overlay
    % ════════════════════════════════════════════════════════════════════
    function selectMeasurement(idx)
        % Deselect previous
        deselectMeasurement();

        if idx < 1 || idx > numel(appData.overlays.measurements)
            return;
        end

        meas = appData.overlays.measurements{idx};
        if ~isvalid(meas.hLine), return; end

        appData.selectedMeasIdx = idx;

        % Highlight: thicken the connecting line and recolor the endpoint
        % tick (edge only) to yellow. Preserve MarkerFaceColor='none' so
        % the hollow endpoint circle from createEndpointMarker stays open
        % — filling it here hid the exact measurement point.
        meas.hLine.LineWidth = 3;
        meas.hLine.Color = [1 1 0];
        if isvalid(meas.hP1)
            meas.hP1.Color           = [1 1 0];
            meas.hP1.MarkerEdgeColor = [1 1 0];
        end
        if isvalid(meas.hP2)
            meas.hP2.Color           = [1 1 0];
            meas.hP2.MarkerEdgeColor = [1 1 0];
        end

        setStatus(sprintf('Selected %s measurement %d (press Delete to remove)', ...
            meas.type, idx));
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: deselectMeasurement — Restore normal styling
    % ════════════════════════════════════════════════════════════════════
    function deselectMeasurement()
        idx = appData.selectedMeasIdx;
        if idx < 1 || idx > numel(appData.overlays.measurements)
            appData.selectedMeasIdx = 0;
            return;
        end

        meas = appData.overlays.measurements{idx};
        if isvalid(meas.hLine)
            meas.hLine.LineWidth = 1.5;
            meas.hLine.Color = OVERLAY_COLOR;
        end
        % Restore the endpoint markers to the original hollow-circle style
        % from createEndpointMarker — edge in OVERLAY_COLOR, face='none'.
        if isvalid(meas.hP1)
            meas.hP1.Color           = OVERLAY_COLOR;
            meas.hP1.MarkerEdgeColor = OVERLAY_COLOR;
            meas.hP1.MarkerFaceColor = 'none';
        end
        if isvalid(meas.hP2)
            meas.hP2.Color           = OVERLAY_COLOR;
            meas.hP2.MarkerEdgeColor = OVERLAY_COLOR;
            meas.hP2.MarkerFaceColor = 'none';
        end

        appData.selectedMeasIdx = 0;
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: deleteSelectedMeasurement — Remove selected overlay
    % ════════════════════════════════════════════════════════════════════
    function deleteSelectedMeasurement()
        idx = appData.selectedMeasIdx;
        if idx < 1 || idx > numel(appData.overlays.measurements)
            return;
        end

        meas = appData.overlays.measurements{idx};

        % Delete graphics objects
        if isvalid(meas.hLine), delete(meas.hLine); end
        if isvalid(meas.hP1),   delete(meas.hP1);   end
        if isvalid(meas.hP2),   delete(meas.hP2);   end
        if ~isempty(meas.hText) && isvalid(meas.hText)
            delete(meas.hText);
        end

        % Remove from list
        appData.overlays.measurements(idx) = [];

        % Re-bind drag + selection callbacks with updated indices
        for mi = 1:numel(appData.overlays.measurements)
            m = appData.overlays.measurements{mi};
            if isvalid(m.hP1)
                m.hP1.ButtonDownFcn = @(~,~) startEndpointDrag(mi, 1);
            end
            if isvalid(m.hP2)
                m.hP2.ButtonDownFcn = @(~,~) startEndpointDrag(mi, 2);
            end
            if isvalid(m.hLine)
                m.hLine.ButtonDownFcn = @(~,~) selectMeasurement(mi);
            end
        end

        appData.selectedMeasIdx = 0;
        setStatus(sprintf('Deleted %s measurement', meas.type));
    end

    % ════════════════════════════════════════════════════════════════════
    %  UNDO STACK: push / pop
    % ════════════════════════════════════════════════════════════════════
    function undoPush()
    %UNDOPUSH  Push current pixel state onto the undo stack.
        snapshot = {appData.rawPixels, appData.filteredPixels};
        appData.undoStack{end+1} = snapshot;
        if numel(appData.undoStack) > appData.undoStackMax
            appData.undoStack(1) = [];   % discard oldest
        end
    end

    function undoPop()
    %UNDOPOP  Pop the most recent snapshot and restore it.
        if isempty(appData.undoStack)
            setStatus('Nothing to undo.');
            return;
        end
        snapshot = appData.undoStack{end};
        appData.undoStack(end) = [];
        appData.rawPixels      = snapshot{1};
        appData.filteredPixels = snapshot{2};

        % If dimensions changed (e.g. undoing a rotation), do full rebuild
        [H2, W2] = size(appData.filteredPixels);
        appData.displayPixels = [];    % always invalidate downsample on undo
        if ~isempty(appData.imgHandle) && isvalid(appData.imgHandle) && ...
                ~isequal(size(appData.imgHandle.CData), [H2 W2])
            lo = sldLow.Value;
            hi = sldHigh.Value;
            prepareDisplayBuffer();
            dispImg = applyContrastPipeline(appData.displayPixels, lo, hi);
            appData.displayImg = dispImg;
            delete(ax.Children);
            cla(ax);
            hImg = imagesc(ax, 'XData', [1 W2], 'YData', [1 H2], 'CData', dispImg);
            appData.imgHandle = hImg;
            attachImageContextMenu();
            colormap(ax, feval(ddColormap.Value, 256));
            ax.CLim = [0 1]; ax.YDir = 'reverse';
            axis(ax, 'equal');
            ax.XLim = [0.5, W2+0.5]; ax.YLim = [0.5, H2+0.5];
            ax.XTick = []; ax.YTick = []; ax.Toolbar.Visible = 'off';
            if cbColorbar.Value
                if ~isempty(hColorbar) && isvalid(hColorbar)
                    delete(hColorbar);
                end
                hColorbar = colorbar(ax);
            end
            if ~isempty(cbScaleBar) && isvalid(cbScaleBar) && ...
                    strcmp(cbScaleBar.Enable, 'on') && cbScaleBar.Value
                rebuildScaleBar();
            end
        else
            refreshDisplay();
        end
        setStatus(sprintf('Undo — %d states remaining', numel(appData.undoStack)));
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onFFTMask — Interactive FFT masking with inverse FFT
    % ════════════════════════════════════════════════════════════════════
    function onFFTMask(~, ~)
        if isempty(appData.filteredPixels)
            return;
        end

        fig.Pointer = 'watch'; drawnow;
        pixels = appData.filteredPixels;
        F = fft2(double(pixels));
        Fshift = fftshift(F);
        magImg = log10(abs(Fshift) + 1);
        fig.Pointer = 'arrow';

        % Show FFT in a new figure with masking controls
        fftFig = figure('Name', 'FFT Mask Editor', 'NumberTitle', 'off', ...
            'Units', 'pixels', 'Position', [200 150 700 560]);
        fftLayout = uigridlayout(fftFig, [2 1], ...
            'RowHeight', {'1x', 30}, 'Padding', [6 6 6 6]);

        fftAx = axes('Parent', uipanel(fftLayout));
        fftAx.Parent.Layout.Row = 1;
        imagesc(fftAx, magImg);
        colormap(fftAx, parula(256));
        axis(fftAx, 'image');
        fftAx.XTick = []; fftAx.YTick = [];
        title(fftAx, 'Click to place circular masks, then Apply', 'Interpreter', 'none');

        btnRow = uigridlayout(fftLayout, [1 5], ...
            'ColumnWidth', {60, 80, 80, 80, 80}, 'Padding', [0 0 0 0]);
        btnRow.Layout.Row = 2;

        % Mask radius spinner
        lblRadius = uilabel(btnRow, 'Text', 'Radius:', 'HorizontalAlignment', 'right');
        lblRadius.Layout.Column = 1;
        spnRadius = uispinner(btnRow, 'Value', 15, 'Limits', [3 200], 'Step', 2);
        spnRadius.Layout.Column = 2;

        btnAddMask = uibutton(btnRow, 'Text', 'Add Mask', ...
            'ButtonPushedFcn', @(~,~) fftAddMask());
        btnAddMask.Layout.Column = 3;

        btnApply = uibutton(btnRow, 'Text', 'Apply', ...
            'BackgroundColor', BTN_PRIMARY, 'FontColor', BTN_FG, ...
            'ButtonPushedFcn', @(~,~) fftApplyMask());
        btnApply.Layout.Column = 4;

        btnCancel = uibutton(btnRow, 'Text', 'Cancel', ...
            'ButtonPushedFcn', @(~,~) close(fftFig));
        btnCancel.Layout.Column = 5;

        maskCircles = {};   % store mask center + radius

        function fftAddMask()
            % Use ButtonDownFcn instead of ginput (ginput unreliable from uifigure)
            title(fftAx, 'Click on the FFT image to place mask center...', ...
                'Interpreter', 'none');
            fftAx.ButtonDownFcn = @captureMaskClick;
        end

        function captureMaskClick(~, evt)
            fftAx.ButtonDownFcn = [];   % one-shot
            cx = evt.IntersectionPoint(1);
            cy = evt.IntersectionPoint(2);
            r = spnRadius.Value;
            th = linspace(0, 2*pi, 60);
            xc = cx + r * cos(th);
            yc = cy + r * sin(th);
            hold(fftAx, 'on');
            plot(fftAx, xc, yc, 'r-', 'LineWidth', 1.5, 'HitTest', 'off');
            hold(fftAx, 'off');
            maskCircles{end+1} = [cx, cy, r];
            title(fftAx, sprintf('%d mask(s) placed — Add more or Apply', ...
                numel(maskCircles)), 'Interpreter', 'none');
        end

        function fftApplyMask()
            if isempty(maskCircles)
                return;
            end

            undoPush();

            [H2, W2] = size(Fshift);
            mask = ones(H2, W2);
            [XX, YY] = meshgrid(1:W2, 1:H2);
            for mi = 1:numel(maskCircles)
                mc = maskCircles{mi};
                dist2 = (XX - mc(1)).^2 + (YY - mc(2)).^2;
                mask(dist2 <= mc(3)^2) = 0;
                % Mirror mask (FFT symmetry)
                mcx = W2 + 1 - mc(1);
                mcy = H2 + 1 - mc(2);
                dist2m = (XX - mcx).^2 + (YY - mcy).^2;
                mask(dist2m <= mc(3)^2) = 0;
            end

            Fmasked = Fshift .* mask;
            recovered = real(ifft2(ifftshift(Fmasked)));

            appData.filteredPixels = recovered;
            refreshDisplay();
            close(fftFig);
            setStatus(sprintf('FFT mask applied (%d regions masked)', numel(maskCircles)));
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onParticleCount — Threshold and count connected components
    % ════════════════════════════════════════════════════════════════════
    function onParticleCount(~, ~)
        if isempty(appData.filteredPixels)
            return;
        end

        % Prompt for threshold
        dMin = min(appData.filteredPixels(:));
        dMax = max(appData.filteredPixels(:));
        defThresh = num2str(round((dMin + dMax) / 2));
        answer = inputdlg( ...
            {sprintf('Threshold (%.0f – %.0f):', dMin, dMax), ...
             'Min particle area (pixels):'}, ...
            'Particle Detection', [1 44], {defThresh, '10'});
        if isempty(answer), return; end

        thresh = str2double(answer{1});
        minArea = str2double(answer{2});
        if isnan(thresh) || isnan(minArea) || minArea < 1
            uialert(fig, 'Invalid parameters.', 'Error', 'Icon', 'error');
            return;
        end

        fig.Pointer = 'watch'; drawnow;

        % Binary threshold
        bw = appData.filteredPixels > thresh;

        % Connected-component labeling (no toolbox — flood fill)
        labelMap = bwlabelNoToolbox(bw);
        nLabels = max(labelMap(:));

        % Compute areas and filter
        areas = [];
        for li = 1:nLabels
            a = sum(labelMap(:) == li);
            if a >= minArea
                areas(end+1) = a; %#ok<AGROW>
            end
        end

        fig.Pointer = 'arrow';

        % Calibrate areas if possible
        unitStr = 'px²';
        areaScale = 1;
        if appData.activeIdx >= 1
            imgInfo = appData.images{appData.activeIdx}.metadata.parserSpecific.imageData;
            if imgInfo.calibrated && ~isnan(imgInfo.pixelSize)
                areaScale = imgInfo.pixelSize^2;
                unitStr = sprintf('%s²', imgInfo.pixelUnit);
            end
        end

        % Show results in a figure
        pFig = figure('Name', 'Particle Analysis', 'NumberTitle', 'off', ...
            'Units', 'pixels', 'Position', [280 200 550 450]);
        pLayout = uigridlayout(pFig, [2 1], ...
            'RowHeight', {'1x', '1x'}, 'Padding', [10 10 10 10]);

        % Top: labeled image
        pAx1 = uiaxes(pLayout);
        pAx1.Layout.Row = 1;
        imagesc(pAx1, labelMap);
        colormap(pAx1, [0 0 0; lines(max(1, nLabels))]);
        axis(pAx1, 'image');
        pAx1.XTick = []; pAx1.YTick = [];
        title(pAx1, sprintf('%d particles (>%d px)', numel(areas), minArea), ...
            'Interpreter', 'none');

        % Bottom: size distribution
        pAx2 = uiaxes(pLayout);
        pAx2.Layout.Row = 2;
        if ~isempty(areas)
            histogram(pAx2, areas * areaScale, min(30, numel(areas)), ...
                'FaceColor', [0.4 0.7 0.4], 'EdgeColor', 'none');
        end
        xlabel(pAx2, sprintf('Area (%s)', unitStr));
        ylabel(pAx2, 'Count');
        title(pAx2, 'Size Distribution', 'Interpreter', 'none');

        setStatus(sprintf('Found %d particles (threshold=%.0f, minArea=%d)', ...
            numel(areas), thresh, minArea));
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: bwlabelNoToolbox — Connected-component labeling (4-connected)
    % ════════════════════════════════════════════════════════════════════
    function L = bwlabelNoToolbox(bw)
    %BWLABELNOTTOOLBOX  Label connected components using two-pass algorithm.
        [H2, W2] = size(bw);
        L = zeros(H2, W2);
        nextLabel = 1;
        equiv = (1:H2*W2);   % union-find parent array

        % Pass 1: assign provisional labels
        for r = 1:H2
            for c = 1:W2
                if ~bw(r, c), continue; end

                neighbors = [];
                if r > 1 && bw(r-1, c)
                    neighbors(end+1) = L(r-1, c); %#ok<AGROW>
                end
                if c > 1 && bw(r, c-1)
                    neighbors(end+1) = L(r, c-1); %#ok<AGROW>
                end

                if isempty(neighbors)
                    L(r, c) = nextLabel;
                    nextLabel = nextLabel + 1;
                else
                    minL = min(neighbors);
                    L(r, c) = minL;
                    for ni = 1:numel(neighbors)
                        equiv = ufUnion(equiv, minL, neighbors(ni));
                    end
                end
            end
        end

        % Resolve equivalences
        for k = 1:nextLabel-1
            equiv = ufFind(equiv, k);
        end

        % Pass 2: relabel
        remap = zeros(1, nextLabel-1);
        newLabel = 0;
        for k = 1:nextLabel-1
            root = ufFindSingle(equiv, k);
            if remap(root) == 0
                newLabel = newLabel + 1;
                remap(root) = newLabel;
            end
            remap(k) = remap(root);
        end

        for r = 1:H2
            for c = 1:W2
                if L(r, c) > 0
                    L(r, c) = remap(L(r, c));
                end
            end
        end
    end

    function p = ufFind(parent, k)
    %UFFIND  Union-find: path-compress all entries up to k.
        p = parent;
        for i = 1:k
            root = i;
            while p(root) ~= root
                root = p(root);
            end
            % Path compression
            j = i;
            while p(j) ~= root
                next = p(j);
                p(j) = root;
                j = next;
            end
        end
    end

    function root = ufFindSingle(parent, x)
    %UFFINDSINGLE  Find root of x with path compression.
        root = x;
        while parent(root) ~= root
            root = parent(root);
        end
    end

    function p = ufUnion(parent, a, b)
    %UFUNION  Union two labels.
        p = parent;
        rootA = a;
        while p(rootA) ~= rootA, rootA = p(rootA); end
        rootB = b;
        while p(rootB) ~= rootB, rootB = p(rootB); end
        if rootA ~= rootB
            p(rootB) = rootA;
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onAlignStack — Cross-correlation drift correction
    % ════════════════════════════════════════════════════════════════════
    function onAlignStack(~, ~)
        if numel(appData.images) < 2
            uialert(fig, 'Need at least 2 images to align.', ...
                'Align Stack', 'Icon', 'warning');
            return;
        end

        answer = questdlg( ...
            sprintf('Align %d loaded images using cross-correlation?\nThe first image is the reference.', ...
            numel(appData.images)), ...
            'Drift Correction', 'Align', 'Cancel', 'Align');
        if ~strcmp(answer, 'Align')
            return;
        end

        fig.Pointer = 'watch'; drawnow;

        try
            % Get reference image (first loaded)
            refInfo = appData.images{1}.metadata.parserSpecific.imageData;
            refPx = double(refInfo.pixels);
            if refInfo.numChannels == 3
                refPx = 0.299*refPx(:,:,1) + 0.587*refPx(:,:,2) + 0.114*refPx(:,:,3);
            end

            shifts = zeros(numel(appData.images), 2);
            for ki = 2:numel(appData.images)
                imgInfo = appData.images{ki}.metadata.parserSpecific.imageData;
                movPx = double(imgInfo.pixels);
                if imgInfo.numChannels == 3
                    movPx = 0.299*movPx(:,:,1) + 0.587*movPx(:,:,2) + 0.114*movPx(:,:,3);
                end

                % Cross-correlation via FFT
                [H2, W2] = size(refPx);
                [Hm, Wm] = size(movPx);
                padH = max(H2, Hm);
                padW = max(W2, Wm);

                refPad = zeros(padH, padW);
                refPad(1:H2, 1:W2) = refPx;
                movPad = zeros(padH, padW);
                movPad(1:Hm, 1:Wm) = movPx;

                cc = real(ifft2(fft2(refPad) .* conj(fft2(movPad))));
                [~, maxIdx] = max(cc(:));
                [peakR, peakC] = ind2sub(size(cc), maxIdx);

                % Convert to shift (handle wrap-around)
                dy = peakR - 1;
                dx = peakC - 1;
                if dy > padH/2, dy = dy - padH; end
                if dx > padW/2, dx = dx - padW; end
                shifts(ki, :) = [dy, dx];

                % Apply shift via circshift
                shiftedPx = circshift(movPx, [dy, dx]);
                appData.images{ki}.metadata.parserSpecific.imageData.pixels = ...
                    cast(shiftedPx, class(imgInfo.pixels));
            end

            fig.Pointer = 'arrow';

            % Show results
            shiftStr = '';
            for ki = 2:numel(appData.images)
                [~, fn, fe] = fileparts(appData.images{ki}.metadata.source);
                shiftStr = [shiftStr sprintf('  %s%s: dy=%+d, dx=%+d\n', fn, fe, ...
                    shifts(ki,1), shifts(ki,2))]; %#ok<AGROW>
            end
            uialert(fig, sprintf('Alignment complete:\n\n%s', shiftStr), ...
                'Drift Correction', 'Icon', 'info');

            % Refresh display
            displayImage();
            setStatus(sprintf('Aligned %d images to reference', numel(appData.images) - 1));
        catch ME
            fig.Pointer = 'arrow';
            uialert(fig, sprintf('Alignment failed:\n%s', ME.message), ...
                'Error', 'Icon', 'error');
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onColorOverlay — Blend two images with different colormaps
    % ════════════════════════════════════════════════════════════════════
    function onColorOverlay(~, ~)
        if numel(appData.images) < 2
            uialert(fig, 'Need at least 2 images for color overlay.', ...
                'Color Overlay', 'Icon', 'warning');
            return;
        end

        % Build list of loaded image names
        names = cell(1, numel(appData.images));
        for ki = 1:numel(appData.images)
            [~, fn, fe] = fileparts(appData.images{ki}.metadata.source);
            names{ki} = sprintf('[%d] %s%s', ki, fn, fe);
        end

        % Prompt for which two images and colormaps
        answer = inputdlg( ...
            {'Image A index (1-based):', ...
             'Image A colormap (red, green, blue, cyan, magenta, yellow):', ...
             'Image B index (1-based):', ...
             'Image B colormap:', ...
             'Blend alpha (0-1, for image B):'}, ...
            'Color Overlay', [1 50], ...
            {'1', 'green', '2', 'magenta', '0.5'});
        if isempty(answer), return; end

        idxA = str2double(answer{1});
        cmapA = lower(strtrim(answer{2}));
        idxB = str2double(answer{3});
        cmapB = lower(strtrim(answer{4}));
        alpha = str2double(answer{5});

        if isnan(idxA) || isnan(idxB) || idxA < 1 || idxB < 1 || ...
                idxA > numel(appData.images) || idxB > numel(appData.images)
            uialert(fig, 'Invalid image indices.', 'Error', 'Icon', 'error');
            return;
        end
        alpha = max(0, min(1, alpha));

        % Extract grayscale
        imgA = getGrayscale(appData.images{round(idxA)});
        imgB = getGrayscale(appData.images{round(idxB)});

        % Normalize to [0,1]
        imgA = (imgA - min(imgA(:))) / max(1, max(imgA(:)) - min(imgA(:)));
        imgB = (imgB - min(imgB(:))) / max(1, max(imgB(:)) - min(imgB(:)));

        % Resize to match (use smaller dimensions)
        [Ha, Wa] = size(imgA);
        [Hb, Wb] = size(imgB);
        H2 = min(Ha, Hb);
        W2 = min(Wa, Wb);
        imgA = imgA(1:H2, 1:W2);
        imgB = imgB(1:H2, 1:W2);

        % Apply pseudo-colormaps
        rgbA = applyColorChannel(imgA, cmapA);
        rgbB = applyColorChannel(imgB, cmapB);

        % Blend
        blended = rgbA * (1 - alpha) + rgbB * alpha;
        blended = max(0, min(1, blended));

        % Show in new figure
        ovFig = figure('Name', 'Color Overlay', 'NumberTitle', 'off', ...
            'Units', 'pixels', 'Position', [250 180 650 550]);
        ovAx = axes(ovFig);
        image(ovAx, blended);
        axis(ovAx, 'image');
        ovAx.XTick = []; ovAx.YTick = [];
        title(ovAx, sprintf('%s (%s) + %s (%s), alpha=%.1f', ...
            names{round(idxA)}, cmapA, names{round(idxB)}, cmapB, alpha), ...
            'Interpreter', 'none');

        setStatus('Color overlay displayed.');
    end

    function gray = getGrayscale(dataStruct)
    %GETGRAYSCALE  Extract grayscale double from a data struct.
        imgInfo = dataStruct.metadata.parserSpecific.imageData;
        px = double(imgInfo.pixels);
        if imgInfo.numChannels == 3
            gray = 0.299*px(:,:,1) + 0.587*px(:,:,2) + 0.114*px(:,:,3);
        else
            gray = px;
        end
    end

    function rgb = applyColorChannel(gray, colorName)
    %APPLYCOLORCHANNEL  Map grayscale [0,1] to an RGB image using a named color.
        [H2, W2] = size(gray);
        rgb = zeros(H2, W2, 3);
        switch colorName
            case 'red',     rgb(:,:,1) = gray;
            case 'green',   rgb(:,:,2) = gray;
            case 'blue',    rgb(:,:,3) = gray;
            case 'cyan',    rgb(:,:,2) = gray; rgb(:,:,3) = gray;
            case 'magenta', rgb(:,:,1) = gray; rgb(:,:,3) = gray;
            case 'yellow',  rgb(:,:,1) = gray; rgb(:,:,2) = gray;
            otherwise,      rgb(:,:,1) = gray; rgb(:,:,2) = gray; rgb(:,:,3) = gray;
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  EDS MULTI-CHANNEL COMPOSITE MODE
    % ════════════════════════════════════════════════════════════════════

    function onEDSToolbarToggle(src, ~)
    %ONEDSTOOLBARTOGGLE  Toolbar state button toggle for EDS mode.
        if src.Value
            onEnterEDS([], []);
        else
            onExitEDS();
        end
    end

    function onEnterEDS(~, ~)
    %ONENTEREDS  Enter multi-channel EDS false-color composite mode.
        if isempty(appData.images)
            return;
        end

        % Mutually exclusive with compare mode
        if appData.compareMode
            btnCompare.Value = false;
            exitCompareMode();
        end

        appData.edsMode = true;
        btnEDSToolbar.Value = true;
        btnEnterEDS.Text = 'Exit EDS Mode';
        btnEnterEDS.BackgroundColor = BTN_DANGER;
        btnEnterEDS.ButtonPushedFcn = @(~,~) onExitEDS();

        % Auto-populate channels from all loaded images if empty
        if isempty(appData.edsChannels)
            defaultColors = EDS_COLORS;
            nImg = numel(appData.images);
            for ci = 1:nImg
                [~, fn, fe] = fileparts(appData.images{ci}.metadata.source);
                ch.imageIdx  = ci;
                ch.label     = [fn fe];
                ch.color     = defaultColors{mod(ci-1, numel(defaultColors)) + 1};
                ch.visible   = true;
                ch.intensity = 1.0;
                appData.edsChannels{ci} = ch;
            end
        end

        % Enable channel controls
        btnAddChannel.Enable       = 'on';
        btnRemoveChannel.Enable    = 'on';
        ddChannelColor.Enable      = 'on';
        cbChannelVisible.Enable    = 'on';
        sldChannelIntensity.Enable = 'on';
        efChannelLabel.Enable      = 'on';
        btnExportComposite.Enable  = 'on';

        % Disable tools that don't apply in EDS mode
        setToolsEnabled('off');
        btnEnterEDS.Enable = 'on';
        btnEDSToolbar.Enable = 'on';

        refreshEDSList();
        compositeEDS();
        setStatus('EDS composite mode — adjust channels in Tools > EDS Channels');
    end

    function onExitEDS()
    %ONEXITEDS  Exit EDS composite mode, restore normal view.
        appData.edsMode = false;
        appData.edsComposite = [];
        btnEDSToolbar.Value = false;
        btnEnterEDS.Text = 'Enter EDS Mode';
        btnEnterEDS.BackgroundColor = BTN_PRIMARY;
        btnEnterEDS.ButtonPushedFcn = @onEnterEDS;

        % Disable channel controls
        btnAddChannel.Enable       = 'off';
        btnRemoveChannel.Enable    = 'off';
        ddChannelColor.Enable      = 'off';
        cbChannelVisible.Enable    = 'off';
        sldChannelIntensity.Enable = 'off';
        efChannelLabel.Enable      = 'off';
        btnExportComposite.Enable  = 'off';

        % Re-enable tools
        setToolsEnabled('on');

        % Restore normal display
        if appData.activeIdx >= 1 && appData.activeIdx <= numel(appData.images)
            displayImage();
        else
            clearDisplay();
        end
        setStatus('Exited EDS mode');
    end

    function compositeEDS()
    %COMPOSITEEDS  Blend all visible EDS channels into an RGB composite.
        if ~appData.edsMode || isempty(appData.edsChannels)
            return;
        end

        % Determine output dimensions from visible channels
        H = Inf; W = Inf;
        hasVisible = false;
        for ci = 1:numel(appData.edsChannels)
            ch = appData.edsChannels{ci};
            if ~ch.visible, continue; end
            if ch.imageIdx < 1 || ch.imageIdx > numel(appData.images), continue; end
            gray = getGrayscale(appData.images{ch.imageIdx});
            [h2, w2] = size(gray);
            H = min(H, h2);
            W = min(W, w2);
            hasVisible = true;
        end

        if ~hasVisible
            % Show black image
            if ~isempty(ax) && isvalid(ax)
                delete(ax.Children); cla(ax);
                appData.edsComposite = zeros(256, 256, 3);
                appData.displayImg = appData.edsComposite;
                hImg = image(ax, appData.edsComposite);
                appData.imgHandle = hImg;
                attachImageContextMenu();
                axis(ax, 'image');
                ax.XTick = []; ax.YTick = [];
            end
            return;
        end

        % Additive blend
        composite = zeros(H, W, 3);
        for ci = 1:numel(appData.edsChannels)
            ch = appData.edsChannels{ci};
            if ~ch.visible, continue; end
            if ch.imageIdx < 1 || ch.imageIdx > numel(appData.images), continue; end

            gray = getGrayscale(appData.images{ch.imageIdx});
            gray = gray(1:H, 1:W);

            % Normalize to [0,1]
            gmin = min(gray(:));
            gmax = max(gray(:));
            if gmax > gmin
                gray = (gray - gmin) / (gmax - gmin);
            else
                gray = zeros(H, W);
            end

            % Scale by channel intensity and apply color
            rgb = applyColorChannel(gray * ch.intensity, ch.color);
            composite = composite + rgb;
        end
        composite = min(1, composite);

        appData.edsComposite = composite;
        appData.displayImg = composite;

        % Render on main axes
        if ~isempty(ax) && isvalid(ax)
            delete(ax.Children); cla(ax);
            hImg = image(ax, composite);
            appData.imgHandle = hImg;
            attachImageContextMenu();
            axis(ax, 'image');
            ax.XTick = []; ax.YTick = [];
            cmapName = ddColormap.Value;
            colormap(ax, feval(cmapName, 256));
        end
    end

    function refreshEDSList()
    %REFRESHEDSLIST  Rebuild the EDS channel listbox from appData.edsChannels.
        if isempty(appData.edsChannels)
            lbEDSChannels.Items = {'(no channels)'};
            lbEDSChannels.ItemsData = 0;
            return;
        end
        items = cell(1, numel(appData.edsChannels));
        idata = zeros(1, numel(appData.edsChannels));
        for ci = 1:numel(appData.edsChannels)
            ch = appData.edsChannels{ci};
            visStr = '';
            if ~ch.visible, visStr = ' [hidden]'; end
            items{ci} = sprintf('[%s] %s (img %d)%s', ...
                ch.color, ch.label, ch.imageIdx, visStr);
            idata(ci) = ci;
        end
        lbEDSChannels.Items = items;
        lbEDSChannels.ItemsData = idata;
        if ~isempty(idata)
            lbEDSChannels.Value = idata(1);
            populateEDSControls(1);
        end
    end

    function populateEDSControls(idx)
    %POPULATEEDSCONTROLS  Fill channel property widgets from selected channel.
        if idx < 1 || idx > numel(appData.edsChannels)
            return;
        end
        ch = appData.edsChannels{idx};
        ddChannelColor.Value      = ch.color;
        cbChannelVisible.Value    = ch.visible;
        sldChannelIntensity.Value = ch.intensity;
        lblEDSIntensity.Text      = sprintf('Int: %.2f', ch.intensity);
        efChannelLabel.Value      = ch.label;
    end

    function onEDSChannelSelected(~, ~)
    %ONEDSCHANNELSELECTED  Listbox selection changed — populate controls.
        idx = lbEDSChannels.Value;
        if isempty(idx) || (isnumeric(idx) && idx == 0)
            return;
        end
        populateEDSControls(idx);
    end

    function onAddEDSChannel(~, ~)
    %ONADDEDSCHANNEL  Add the active image as a new EDS channel.
        if appData.activeIdx < 1 || appData.activeIdx > numel(appData.images)
            return;
        end
        % Check if already added
        for ci = 1:numel(appData.edsChannels)
            if appData.edsChannels{ci}.imageIdx == appData.activeIdx
                setStatus(sprintf('Image %d is already an EDS channel', appData.activeIdx));
                return;
            end
        end
        [~, fn, fe] = fileparts(appData.images{appData.activeIdx}.metadata.source);
        ch.imageIdx  = appData.activeIdx;
        ch.label     = [fn fe];
        nCh = numel(appData.edsChannels);
        ch.color     = EDS_COLORS{mod(nCh, numel(EDS_COLORS)) + 1};
        ch.visible   = true;
        ch.intensity = 1.0;
        appData.edsChannels{end+1} = ch;
        refreshEDSList();
        if appData.edsMode
            compositeEDS();
        end
    end

    function onRemoveEDSChannel(~, ~)
    %ONREMOVEEDSCHANNEL  Remove selected channel from EDS list.
        idx = lbEDSChannels.Value;
        if isempty(idx) || (isnumeric(idx) && idx == 0)
            return;
        end
        if idx >= 1 && idx <= numel(appData.edsChannels)
            appData.edsChannels(idx) = [];
        end
        refreshEDSList();
        if appData.edsMode
            compositeEDS();
        end
    end

    function onChannelColorChanged(~, ~)
    %ONCHANNELCOLORCHANGED  Update color assignment for selected channel.
        idx = lbEDSChannels.Value;
        if isempty(idx) || idx < 1 || idx > numel(appData.edsChannels)
            return;
        end
        appData.edsChannels{idx}.color = ddChannelColor.Value;
        refreshEDSList();
        lbEDSChannels.Value = idx;
        if appData.edsMode, compositeEDS(); end
    end

    function onChannelVisibilityChanged(~, ~)
    %ONCHANNELVISIBILITYCHANGED  Toggle visibility for selected channel.
        idx = lbEDSChannels.Value;
        if isempty(idx) || idx < 1 || idx > numel(appData.edsChannels)
            return;
        end
        appData.edsChannels{idx}.visible = cbChannelVisible.Value;
        refreshEDSList();
        lbEDSChannels.Value = idx;
        if appData.edsMode, compositeEDS(); end
    end

    function onChannelIntensityChanged(~, ~)
    %ONCHANNELINTENSITYCHANGED  Update intensity scaling for selected channel.
        idx = lbEDSChannels.Value;
        if isempty(idx) || idx < 1 || idx > numel(appData.edsChannels)
            return;
        end
        appData.edsChannels{idx}.intensity = sldChannelIntensity.Value;
        lblEDSIntensity.Text = sprintf('Int: %.2f', sldChannelIntensity.Value);
        refreshEDSList();
        lbEDSChannels.Value = idx;
        if appData.edsMode, compositeEDS(); end
    end

    function onChannelLabelChanged(~, ~)
    %ONCHANNELLABELCHANGED  Update label for selected channel.
        idx = lbEDSChannels.Value;
        if isempty(idx) || idx < 1 || idx > numel(appData.edsChannels)
            return;
        end
        appData.edsChannels{idx}.label = efChannelLabel.Value;
        refreshEDSList();
        lbEDSChannels.Value = idx;
    end

    function onExportEDSComposite(~, ~)
    %ONEXPORTEDSCOMPOSITE  Save the EDS composite RGB image to file.
        if isempty(appData.edsComposite)
            uialert(fig, 'No EDS composite to export.', 'Export', 'Icon', 'warning');
            return;
        end
        startPath = appData.lastDir;
        if isempty(startPath) || ~isfolder(startPath), startPath = pwd; end

        [saveName, saveDir] = uiputfile( ...
            {'*.png', 'PNG (*.png)'; '*.tif;*.tiff', 'TIFF (*.tif)'}, ...
            'Export EDS Composite', fullfile(startPath, 'eds_composite.png'));
        if isequal(saveName, 0), return; end

        outPath = fullfile(saveDir, saveName);
        try
            imwrite(uint8(appData.edsComposite * 255), outPath);
            setStatus(sprintf('EDS composite saved: %s', outPath));
        catch ME
            uialert(fig, sprintf('Export failed:\n%s', ME.message), ...
                'Error', 'Icon', 'error');
        end
    end

    function setEDSChannelAPI(idx, field, val)
    %SETEDSCHANNELAPI  Programmatic setter for EDS channel properties.
        if idx < 1 || idx > numel(appData.edsChannels)
            error('FermiViewer:invalidIdx', 'Channel index %d out of range', idx);
        end
        switch field
            case 'color'
                appData.edsChannels{idx}.color = val;
            case 'visible'
                appData.edsChannels{idx}.visible = val;
            case 'intensity'
                appData.edsChannels{idx}.intensity = max(0, min(1, val));
            case 'label'
                appData.edsChannels{idx}.label = val;
            otherwise
                error('FermiViewer:invalidField', 'Unknown field: %s', field);
        end
        refreshEDSList();
        if appData.edsMode, compositeEDS(); end
    end

    function tf = getEDSMode()
        % Nested accessor — sees live appData (anonymous closures would
        % capture the struct by value at api-build time).
        tf = appData.edsMode;
    end

    function chs = getEDSChannelsAPI()
        chs = appData.edsChannels;
    end

    function comp = getEDSCompositeAPI()
        comp = appData.edsComposite;
    end

    % ════════════════════════════════════════════════════════════════════
    %  NEW FEATURES: 3D Surface, Live FFT, Template Match, Stitch,
    %  Noise Estimate, Pub Presets, Colormap Presets, Measurement Stats,
    %  Batch Measurement, Export to BosonPlotter
    % ════════════════════════════════════════════════════════════════════

    function on3DSurface(~, ~)
    %ON3DSURFACE  Render the current image as a 3D height map.
        if isempty(appData.filteredPixels), return; end
        surfFig = figure('Name', 'EM 3D Surface View', 'NumberTitle', 'off', ...
            'Units', 'pixels', 'Position', [200 150 700 550], 'Tag', 'fermiViewer3D');
        surfAx = axes(surfFig);
        img = appData.filteredPixels;
        % Downsample large images for performance
        [H, W] = size(img);
        maxDim = 512;
        if H > maxDim || W > maxDim
            factor = max(H, W) / maxDim;
            newH = round(H / factor); newW = round(W / factor);
            [Xq, Yq] = meshgrid(linspace(1, W, newW), linspace(1, H, newH));
            img = interp2(double(img), Xq, Yq, 'linear');
        end
        surf(surfAx, img, 'EdgeColor', 'none');
        colormap(surfAx, gray(256));
        colorbar(surfAx);
        axis(surfAx, 'tight');
        surfAx.View = [-37.5 30];
        xlabel(surfAx, 'X (px)'); ylabel(surfAx, 'Y (px)'); zlabel(surfAx, 'Intensity');
        title(surfAx, '3D Surface View', 'Interpreter', 'none');
        rotate3d(surfFig, 'on');
        setStatus('3D surface view opened — drag to rotate');
    end

    appData.liveFFTFig = [];  % persistent live FFT figure handle

    function onLiveFFTToggle(src, ~)
    %ONLIVEFFTTOGGLE  Show/hide persistent FFT panel that updates with filters.
        if src.Value
            % Create live FFT figure
            appData.liveFFTFig = figure('Name', 'Live FFT', 'NumberTitle', 'off', ...
                'Units', 'pixels', 'Position', [250 200 400 400], ...
                'Tag', 'fermiViewerLiveFFT', ...
                'DeleteFcn', @(~,~) set(src, 'Value', false));
            updateLiveFFT();
        else
            if ~isempty(appData.liveFFTFig) && isvalid(appData.liveFFTFig)
                delete(appData.liveFFTFig);
            end
            appData.liveFFTFig = [];
        end
    end

    function updateLiveFFT()
    %UPDATELIVEFFT  Refresh the live FFT display from current filteredPixels.
        if isempty(appData.liveFFTFig) || ~isvalid(appData.liveFFTFig), return; end
        if isempty(appData.filteredPixels), return; end
        fftAx = findobj(appData.liveFFTFig, 'Type', 'axes');
        if isempty(fftAx)
            fftAx = axes(appData.liveFFTFig);
        end
        F = fft2(double(appData.filteredPixels));
        Fshift = fftshift(F);
        mag = log10(1 + abs(Fshift));
        imagesc(fftAx, mag);
        axis(fftAx, 'image');
        colormap(fftAx, gray(256));
        fftAx.XTick = []; fftAx.YTick = [];
        title(fftAx, 'Live FFT (log magnitude)');
    end

    function onTemplateMatch(~, ~)
    %ONTEMPLATEMATCH  Select a template ROI and find matches in the image.
        if isempty(appData.filteredPixels), return; end
        % Prompt for template region via crop-style selection
        answer = inputdlg({'X start:', 'Y start:', 'Width:', 'Height:'}, ...
            'Select Template Region', 1, {'10', '10', '50', '50'});
        if isempty(answer), return; end
        x1 = str2double(answer{1}); y1 = str2double(answer{2});
        tw = str2double(answer{3}); th = str2double(answer{4});
        [H, W] = size(appData.filteredPixels);
        x2 = min(x1 + tw - 1, W); y2 = min(y1 + th - 1, H);
        template = appData.filteredPixels(max(1,y1):y2, max(1,x1):x2);
        if numel(template) < 4
            uialert(fig, 'Template too small.', 'Template Match', 'Icon', 'warning');
            return;
        end
        fig.Pointer = 'watch'; drawnow;
        try
            r = imaging.templateMatch(appData.filteredPixels, template, Threshold=0.6);
            fig.Pointer = 'arrow';
            % Mark matches on image
            if r.nMatches > 0
                hold(ax, 'on');
                for mi = 1:r.nMatches
                    plot(ax, r.locations(mi,2), r.locations(mi,1), 'r+', ...
                        'MarkerSize', 12, 'LineWidth', 2, 'HandleVisibility', 'off');
                end
                hold(ax, 'off');
            end
            setStatus(sprintf('Template match: %d matches found (threshold=%.2f)', ...
                r.nMatches, r.threshold));
        catch ME
            fig.Pointer = 'arrow';
            uialert(fig, sprintf('Template match failed:\n%s', ME.message), ...
                'Error', 'Icon', 'error');
        end
    end

    function onStitchImages(~, ~)
    %ONSTITCHIMAGES  Stitch all loaded images into a panoramic mosaic.
        if numel(appData.images) < 2
            uialert(fig, 'Need at least 2 images to stitch.', 'Stitch', 'Icon', 'warning');
            return;
        end
        layouts = {'horizontal', 'vertical', 'auto'};
        [sel, ok] = listdlg('ListString', layouts, 'SelectionMode', 'single', ...
            'PromptString', 'Layout direction:', 'ListSize', [150 60]);
        if ~ok, return; end
        fig.Pointer = 'watch'; drawnow;
        try
            imgs = cell(1, numel(appData.images));
            for si = 1:numel(appData.images)
                imgs{si} = getGrayscale(appData.images{si});
            end
            r = imaging.stitchImages(imgs, Layout=layouts{sel});
            % Show in new figure
            sFig = figure('Name', 'Stitched Mosaic', 'NumberTitle', 'off', ...
                'Tag', 'fermiViewerStitch');
            sAx = axes(sFig);
            imagesc(sAx, r.mosaic);
            axis(sAx, 'image'); colormap(sAx, gray(256));
            sAx.XTick = []; sAx.YTick = [];
            title(sAx, sprintf('Mosaic: %d images (%s)', r.nImages, r.layout));
            fig.Pointer = 'arrow';
            setStatus(sprintf('Stitched %d images (%s layout)', r.nImages, r.layout));
        catch ME
            fig.Pointer = 'arrow';
            uialert(fig, sprintf('Stitch failed:\n%s', ME.message), 'Error', 'Icon', 'error');
        end
    end

    function onNoiseEstimate(~, ~)
    %ONNOISEESTIMATE  Characterize noise and suggest filter parameters.
        if isempty(appData.filteredPixels), return; end
        try
            r = imaging.noiseEstimate(appData.filteredPixels, Method='both');
            msg = { ...
                sprintf('Noise σ = %.3f', r.sigma), ...
                sprintf('SNR = %.1f dB (%.1f linear)', r.snr, r.snrLinear), ...
                sprintf('Noise type: %s', r.noiseType), ...
                '', ...
                'Suggested filter:', ...
                sprintf('  Type: %s', r.suggestedFilter.type), ...
                sprintf('  σ = %.1f (Gaussian) or window = %d (median)', ...
                    r.suggestedFilter.sigma, r.suggestedFilter.window)};
            uialert(fig, strjoin(msg, '\n'), 'Noise Estimate', 'Icon', 'info');
            setStatus(sprintf('Noise: σ=%.3f, SNR=%.1fdB, type=%s', r.sigma, r.snr, r.noiseType));
        catch ME
            uialert(fig, sprintf('Noise estimate failed:\n%s', ME.message), ...
                'Error', 'Icon', 'error');
        end
    end

    function onPubPresets(~, ~)
    %ONPUBPRESETS  Apply journal-specific annotation formatting.
        journals = {'APS (Phys Rev)', 'Nature', 'ACS (JACS/Nano)', 'Elsevier'};
        [sel, ok] = listdlg('ListString', journals, 'SelectionMode', 'single', ...
            'PromptString', 'Select journal preset:', 'ListSize', [200 80]);
        if ~ok, return; end
        switch sel
            case 1  % APS
                sbFont = 10; sbColor = [1 1 1]; annFont = 8;
            case 2  % Nature
                sbFont = 12; sbColor = [1 1 1]; annFont = 10;
            case 3  % ACS
                sbFont = 10; sbColor = [0 0 0]; annFont = 9;
            case 4  % Elsevier
                sbFont = 11; sbColor = [1 1 1]; annFont = 9;
        end
        % Apply to scale bar if present
        if ~isempty(appData.overlays.scalebar)
            sb = appData.overlays.scalebar;
            if isfield(sb, 'label') && isvalid(sb.label)
                sb.label.FontSize = sbFont;
                sb.label.Color = sbColor;
            end
        end
        % Apply to annotations
        for ai = 1:numel(appData.overlays.textAnnotations)
            ann = appData.overlays.textAnnotations{ai};
            if isfield(ann, 'handle') && isvalid(ann.handle)
                ann.handle.FontSize = annFont;
            end
        end
        setStatus(sprintf('Applied %s publication preset', journals{sel}));
    end

    function onColormapPreset(~, ~)
    %ONCOLORMAPPRESET  Auto-select colormap based on EM mode.
        modes = {'SEM (gray)', 'TEM BF (gray)', 'STEM-HAADF (hot)', ...
                 'STEM-ABF (bone)', 'EDS (parula)', 'Phase (hsv)', ...
                 'Topography (turbo)', 'Diff. pattern (copper)'};
        cmaps = {'gray', 'gray', 'hot', 'bone', 'parula', 'hsv', 'turbo', 'copper'};
        [sel, ok] = listdlg('ListString', modes, 'SelectionMode', 'single', ...
            'PromptString', 'Select EM imaging mode:', 'ListSize', [220 120]);
        if ~ok, return; end
        ddColormap.Value = cmaps{sel};
        if ~isempty(ax) && isvalid(ax)
            colormap(ax, feval(cmaps{sel}, 256));
        end
        setStatus(sprintf('Colormap: %s (%s)', cmaps{sel}, modes{sel}));
    end

    function onMeasurementStats(~, ~)
    %ONMEASUREMENTSTATS  Show aggregate statistics for all measurements.
        meas = appData.overlays.measurements;
        if isempty(meas)
            uialert(fig, 'No measurements to analyze.', 'Stats', 'Icon', 'info');
            return;
        end
        % Collect distances
        dists = [];
        for mi = 1:numel(meas)
            m = meas{mi};
            if isfield(m, 'distance') && ~isnan(m.distance)
                dists(end+1) = m.distance; %#ok<AGROW>
            end
        end
        if isempty(dists)
            uialert(fig, 'No distance measurements found.', 'Stats', 'Icon', 'info');
            return;
        end
        % Show stats + histogram
        statsFig = figure('Name', 'Measurement Statistics', 'NumberTitle', 'off', ...
            'Units', 'pixels', 'Position', [300 200 500 400], 'Tag', 'fermiViewerMeasStats');
        subplot(2, 1, 1);
        histogram(dists, max(3, round(sqrt(numel(dists)))));
        xlabel('Distance'); ylabel('Count');
        title(sprintf('N=%d, Mean=%.2f, Std=%.2f, Min=%.2f, Max=%.2f', ...
            numel(dists), mean(dists), std(dists), min(dists), max(dists)));
        subplot(2, 1, 2);
        plot(1:numel(dists), sort(dists), 'bo-', 'LineWidth', 1.5);
        xlabel('Rank'); ylabel('Distance'); title('Sorted Measurements');
        setStatus(sprintf('Stats: N=%d, mean=%.2f ± %.2f', numel(dists), mean(dists), std(dists)));
    end

    function onBatchMeasurement(~, ~)
    %ONBATCHMEASUREMENT  Apply line profile measurement across all images.
        if numel(appData.images) < 2
            uialert(fig, 'Need 2+ images for batch measurement.', 'Batch', 'Icon', 'warning');
            return;
        end
        answer = inputdlg({'X1:', 'Y1:', 'X2:', 'Y2:'}, ...
            'Line Profile Coordinates (same for all images)', 1, {'10', '10', '100', '100'});
        if isempty(answer), return; end
        x1 = str2double(answer{1}); y1 = str2double(answer{2});
        x2 = str2double(answer{3}); y2 = str2double(answer{4});
        fig.Pointer = 'watch'; drawnow;
        try
            batchFig = figure('Name', 'Batch Line Profiles', 'NumberTitle', 'off', ...
                'Tag', 'fermiViewerBatchMeas');
            batchAx = axes(batchFig);
            hold(batchAx, 'on');
            legends = {};
            for bi = 1:numel(appData.images)
                gray = getGrayscale(appData.images{bi});
                [dist, intensity] = imaging.lineProfile(gray, x1, y1, x2, y2);
                plot(batchAx, dist, intensity, 'LineWidth', 1.2);
                [~, fn, fe] = fileparts(appData.images{bi}.metadata.source);
                legends{bi} = [fn fe]; %#ok<AGROW>
            end
            hold(batchAx, 'off');
            legend(batchAx, legends, 'Interpreter', 'none', 'Location', 'best');
            xlabel(batchAx, 'Distance (px)'); ylabel(batchAx, 'Intensity');
            title(batchAx, sprintf('Batch profiles: (%d,%d) to (%d,%d)', x1, y1, x2, y2));
            fig.Pointer = 'arrow';
            setStatus(sprintf('Batch profiles: %d images', numel(appData.images)));
        catch ME
            fig.Pointer = 'arrow';
            uialert(fig, sprintf('Batch failed:\n%s', ME.message), 'Error', 'Icon', 'error');
        end
    end

    function onExportProfileToDP(~, ~)
    %ONEXPORTPROFILETODP  Send last line profile to BosonPlotter as data struct.
        if isempty(appData.lastProfile.dist)
            uialert(fig, 'No line profile available. Draw one first.', ...
                'Export', 'Icon', 'warning');
            return;
        end
        % Build standard unified data struct
        data = parser.createDataStruct( ...
            appData.lastProfile.dist, ...
            appData.lastProfile.intensity, ...
            {'Intensity'}, ...
            {appData.lastProfile.unit}, ...
            struct('source', 'FermiViewer line profile', 'parserName', 'FermiViewer'));
        % Save to workspace and launch BosonPlotter
        assignin('base', 'emProfileData', data);
        setStatus('Line profile exported to workspace as ''emProfileData''. Launch BosonPlotter to load.');
        try
            BosonPlotter;
        catch
            % BosonPlotter may not be on path
        end
    end

    function result = templateMatchAPI(x1, y1, w, h)
    %TEMPLATEMATCHAPI  API wrapper for template matching.
        [H2, W2] = size(appData.filteredPixels);
        x2 = min(x1 + w - 1, W2); y2 = min(y1 + h - 1, H2);
        template = appData.filteredPixels(max(1,y1):y2, max(1,x1):x2);
        result = imaging.templateMatch(appData.filteredPixels, template, Threshold=0.6);
    end

    function result = noiseEstimateAPI()
    %NOISEESTIMATEAPI  API wrapper for noise estimation.
        result = imaging.noiseEstimate(appData.filteredPixels, Method='both');
    end

    function ov = getOverlaysAPI()
    %GETOVERLAYSAPI  Return a live snapshot of appData.overlays (for tests).
        ov = appData.overlays;
    end

    function mlog = getMeasurementLogAPI()
    %GETMEASUREMENTLOGAPI  Return a live snapshot of appData.measurementLog.
        mlog = appData.measurementLog;
    end

    function mode = getContrastTransformAPI()
        mode = appData.contrastTransform;
    end

    function tf = isInvertedAPI()
        tf = appData.contrastInvert;
    end

    function setColormapAPI(name)
    %SETCOLORMAPAPI  Programmatically set colormap (matches dropdown items).
        if ~any(strcmp(name, ddColormap.Items))
            error('FermiViewer:setColormap:unknown', ...
                'Unknown colormap "%s". Valid: %s', name, strjoin(ddColormap.Items, ', '));
        end
        ddColormap.Value = name;
        onColormapChanged([], []);
    end

    function cycleColormapAPI()
    %CYCLECOLORMAPAPI  Advance to the next colormap in the dropdown list.
        items = ddColormap.Items;
        cur = ddColormap.Value;
        idx = find(strcmp(items, cur), 1);
        if isempty(idx), idx = 0; end
        next = items{mod(idx, numel(items)) + 1};
        ddColormap.Value = next;
        onColormapChanged([], []);
    end

    function setContrastTransformAPI(mode)
    %SETCONTRASTTRANSFORMAPI  Set 'linear' | 'log' | 'sqrt' | 'power'.
        if ~any(strcmp(mode, ddContrastTransform.Items))
            error('FermiViewer:setContrastTransform:unknown', ...
                'Unknown transform "%s". Valid: %s', mode, ...
                strjoin(ddContrastTransform.Items, ', '));
        end
        ddContrastTransform.Value = mode;
        onContrastTransformChanged([], []);
    end

    function setInvertAPI(tf)
    %SETINVERTAPI  Enable or disable display inversion.
        cbInvert.Value = logical(tf);
        onInvertToggle([], []);
    end

    function setColorbarAPI(tf)
    %SETCOLORBARAPI  Show or hide the colorbar.
        cbColorbar.Value = logical(tf);
        onColorbarToggle([], []);
    end

    function cropRectAPI(xMin, yMin, xMax, yMax)
    %CROPRECTAPI  Crop the active image to an explicit rectangle.
    %   Bypasses the click-capture flow so tests can drive cropping
    %   directly. Accepts coordinates in image pixel space; they are
    %   clamped to the current image bounds and rounded.
        if isempty(appData.filteredPixels), return; end
        [H, W] = size(appData.filteredPixels);
        x1 = max(1, round(min(xMin, xMax)));
        x2 = min(W, round(max(xMin, xMax)));
        y1 = max(1, round(min(yMin, yMax)));
        y2 = min(H, round(max(yMin, yMax)));
        if x2 - x1 < 1 || y2 - y1 < 1
            setStatus('cropRect: selection too small.');
            return;
        end
        undoPush();
        appData.rawPixels      = appData.rawPixels(y1:y2, x1:x2);
        appData.filteredPixels = appData.filteredPixels(y1:y2, x1:x2);
        rebuildAxesForNewSize();
        setStatus(sprintf('Cropped to %dx%d px', x2 - x1 + 1, y2 - y1 + 1));
    end

    function zoomRectAPI(xMin, yMin, xMax, yMax)
    %ZOOMRECTAPI  Set axes XLim/YLim to an explicit rectangle.
        if isempty(appData.displayImg) || isempty(ax) || ~isvalid(ax)
            return;
        end
        [H, W] = size(appData.filteredPixels);
        x1 = max(0.5,     min(xMin, xMax));
        x2 = min(W + 0.5, max(xMin, xMax));
        y1 = max(0.5,     min(yMin, yMax));
        y2 = min(H + 0.5, max(yMin, yMax));
        if x2 - x1 < 1 || y2 - y1 < 1
            setStatus('zoomRect: selection too small.');
            return;
        end
        ax.XLim = [x1, x2];
        ax.YLim = [y1, y2];
        setStatus(sprintf('Zoomed to [%.1f:%.1f, %.1f:%.1f]', x1, x2, y1, y2));
    end

    function fftMaskAPI(masks)
    %FFTMASKAPI  Apply one or more circular FFT masks headlessly.
    %   masks is an N-by-3 double array where each row is
    %   [cx, cy, radius] in fftshift (centered) coordinates. The mask
    %   is mirrored across the FFT center to preserve Hermitian
    %   symmetry, so real-space output stays real.
        if isempty(appData.filteredPixels), return; end
        if isempty(masks) || size(masks, 2) ~= 3
            setStatus('fftMask: masks must be N-by-3 [cx cy r].');
            return;
        end

        undoPush();
        pixels = double(appData.filteredPixels);
        F      = fft2(pixels);
        Fshift = fftshift(F);
        [H2, W2] = size(Fshift);
        mask = ones(H2, W2);
        [XX, YY] = meshgrid(1:W2, 1:H2);
        for mi = 1:size(masks, 1)
            cx = masks(mi, 1);
            cy = masks(mi, 2);
            r  = masks(mi, 3);
            if r <= 0, continue; end
            d2 = (XX - cx).^2 + (YY - cy).^2;
            mask(d2 <= r^2) = 0;
            % Mirror for Hermitian symmetry
            mcx = W2 + 1 - cx;
            mcy = H2 + 1 - cy;
            d2m = (XX - mcx).^2 + (YY - mcy).^2;
            mask(d2m <= r^2) = 0;
        end
        Fmasked = Fshift .* mask;
        recovered = real(ifft2(ifftshift(Fmasked)));
        appData.filteredPixels = recovered;
        refreshDisplay();
        setStatus(sprintf('FFT mask applied (%d region(s))', size(masks, 1)));
    end

    function injectEELSDataAPI(E, I)
    %INJECTEELSDATAAPI  Populate appData.eelsData with a synthetic spectrum
    %  so the deconvolve / Kramers-Kronig api wrappers can run headlessly
    %  without needing a real DM3/DM4 EELS file.
        spec.energyAxis  = E(:);
        spec.counts      = I(:);
        spec.energyScale = (E(end) - E(1)) / max(numel(E) - 1, 1);
        spec.energyOrigin = E(1);
        spec.energyUnit  = 'eV';
        spec.nChannels   = numel(E);
        appData.eelsData = spec;
        appData.eelsMode = true;
        appData.eelsEnergyAxis = E(:);
    end

    function d = getEELSDataAPI()
        d = appData.eelsData;
    end

    function s = getEELSSSDAPI()
        s = appData.eelsSSD;
    end

    function r = getEELSKKResultAPI()
        r = appData.eelsKKResult;
    end

    function result = getMeasStatsAPI()
    %GETMEASSTATSAPI  Return aggregate measurement statistics.
        meas = appData.overlays.measurements;
        dists = [];
        for mi = 1:numel(meas)
            m = meas{mi};
            if isfield(m, 'distance') && ~isnan(m.distance)
                dists(end+1) = m.distance; %#ok<AGROW>
            end
        end
        result.distances = dists;
        result.count = numel(dists);
        if ~isempty(dists)
            result.mean = mean(dists);
            result.std = std(dists);
            result.min = min(dists);
            result.max = max(dists);
        else
            result.mean = NaN; result.std = NaN;
            result.min = NaN; result.max = NaN;
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onExportWithOverlays — Burn overlays into exported image
    % ════════════════════════════════════════════════════════════════════
    function onExportWithOverlays(~, ~)
        if isempty(appData.displayImg) || isempty(ax) || ~isvalid(ax)
            return;
        end

        if appData.activeIdx >= 1
            [~, bname] = fileparts(appData.images{appData.activeIdx}.metadata.source);
            defName = [bname '_overlay.png'];
        else
            defName = 'overlay.png';
        end

        startPath = appData.lastDir;
        if isempty(startPath) || ~isfolder(startPath)
            startPath = pwd;
        end

        [saveName, saveDir] = uiputfile( ...
            {'*.png', 'PNG (*.png)'; '*.tif;*.tiff', 'TIFF (*.tif)'}, ...
            'Export with Overlays', fullfile(startPath, defName));
        if isequal(saveName, 0), return; end

        outPath = fullfile(saveDir, saveName);

        fig.Pointer = 'watch'; drawnow;

        try
            % Use print to capture the axes content including overlays
            tmpFig = figure('Visible', 'off', 'Color', 'k');
            copyobj(ax, tmpFig);
            tmpAx = findobj(tmpFig, 'Type', 'axes');
            tmpAx.Units = 'normalized';
            tmpAx.Position = [0 0 1 1];

            % Match colormap
            cmapName = ddColormap.Value;
            colormap(tmpFig, feval(cmapName, 256));

            % Capture at configured DPI resolution
            dpi = getExportDPI();
            set(tmpFig, 'PaperUnits', 'inches', ...
                'PaperPosition', [0 0 size(appData.displayImg,2)/dpi size(appData.displayImg,1)/dpi]);
            frame = getframe(tmpAx);
            close(tmpFig);

            [~, ~, ext] = fileparts(outPath);
            if strcmpi(ext, '.tif') || strcmpi(ext, '.tiff')
                imwrite(frame.cdata, outPath, 'Compression', 'none');
            else
                imwrite(frame.cdata, outPath);
            end

            setStatus(sprintf('Exported with overlays: %s', saveName));
        catch ME
            fig.Pointer = 'arrow';
            uialert(fig, sprintf('Export failed:\n%s', ME.message), ...
                'Error', 'Icon', 'error');
            return;
        end

        fig.Pointer = 'arrow';
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onBatchExport — Export all loaded images to a folder
    % ════════════════════════════════════════════════════════════════════
    function onBatchExport(~, ~)
        if isempty(appData.images)
            return;
        end

        outDir = uigetdir(appData.lastDir, 'Select Output Folder for Batch Export');
        if isequal(outDir, 0), return; end

        fig.Pointer = 'watch'; drawnow;

        nExported = 0;
        for ki = 1:numel(appData.images)
            try
                imgInfo = appData.images{ki}.metadata.parserSpecific.imageData;
                px = double(imgInfo.pixels);
                if imgInfo.numChannels == 3
                    px = 0.299*px(:,:,1) + 0.587*px(:,:,2) + 0.114*px(:,:,3);
                end

                % Per-image auto-contrast (2nd/98th percentile)
                lo = percentileNoToolbox(px(:), 2);
                hi = percentileNoToolbox(px(:), 98);
                if lo >= hi
                    lo = min(px(:)); hi = max(px(:));
                end
                if hi <= lo, hi = lo + 1; end
                dispPx = (px - lo) / (hi - lo);
                dispPx = max(0, min(1, dispPx));

                [~, bname] = fileparts(appData.images{ki}.metadata.source);
                outPath = fullfile(outDir, [bname '_export.png']);
                imwrite(uint8(dispPx * 255), outPath);
                nExported = nExported + 1;
            catch
                % Skip failed images
            end
        end

        fig.Pointer = 'arrow';
        setStatus(sprintf('Batch exported %d / %d images to %s', ...
            nExported, numel(appData.images), outDir));
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onCreateGIF — Combine images into an animated GIF
    % ════════════════════════════════════════════════════════════════════
    function onCreateGIF(~, ~)
        if numel(appData.images) < 2, return; end

        % ── Build options dialog ──────────────────────────────────────
        nImg = numel(appData.images);
        names = cell(1, nImg);
        for ni = 1:nImg
            [~, names{ni}] = fileparts(appData.images{ni}.metadata.source);
        end

        dlg = uifigure('Name', 'Create Animated GIF', ...
            'Position', [200 200 400 370], ...
            'Resize', 'off', ...
            'WindowStyle', 'modal');
        dlgGL = uigridlayout(dlg, [8 2], ...
            'RowHeight', {22, 120, 22, 22, 22, 22, 10, 28}, ...
            'ColumnWidth', {120, '1x'}, ...
            'Padding', [10 10 10 10], ...
            'RowSpacing', 6);

        % Row 1: Label
        lblGIFSelect = uilabel(dlgGL, 'Text', 'Select images:', 'FontWeight', 'bold', ...
            'FontSize', 11);
        lblGIFSelect.Layout.Row = 1;

        % Row 2: Image list (multi-select)
        lbGIFImages = uilistbox(dlgGL, ...
            'Items', names, ...
            'ItemsData', 1:nImg, ...
            'Multiselect', 'on', ...
            'Value', 1:nImg);
        lbGIFImages.Layout.Row = 2;
        lbGIFImages.Layout.Column = [1 2];

        % Row 3: Frame delay
        lblDelay = uilabel(dlgGL, 'Text', 'Frame delay (s):', ...
            'HorizontalAlignment', 'right');
        lblDelay.Layout.Row = 3; lblDelay.Layout.Column = 1;
        efDelay = uieditfield(dlgGL, 'numeric', ...
            'Value', 0.5, 'Limits', [0.02 10], ...
            'Tooltip', 'Seconds per frame (0.02 – 10)');
        efDelay.Layout.Row = 3; efDelay.Layout.Column = 2;

        % Row 4: Loop count
        lblLoop = uilabel(dlgGL, 'Text', 'Loop:', ...
            'HorizontalAlignment', 'right');
        lblLoop.Layout.Row = 4; lblLoop.Layout.Column = 1;
        ddLoop = uidropdown(dlgGL, ...
            'Items', {'Infinite', '1', '2', '3', '5', '10'}, ...
            'ItemsData', {Inf, 1, 2, 3, 5, 10}, ...
            'Value', Inf, ...
            'Tooltip', 'Number of times the GIF loops');
        ddLoop.Layout.Row = 4; ddLoop.Layout.Column = 2;

        % Row 5: Include scale bar
        cbScaleBarGIF = uicheckbox(dlgGL, ...
            'Text', 'Include scale bar', ...
            'Value', true, ...
            'Tooltip', 'Add a scale bar at same position on every frame');
        cbScaleBarGIF.Layout.Row = 5;
        cbScaleBarGIF.Layout.Column = [1 2];

        % Row 6: Scale bar color
        lblBarColor = uilabel(dlgGL, 'Text', 'Bar color:', ...
            'HorizontalAlignment', 'right');
        lblBarColor.Layout.Row = 6; lblBarColor.Layout.Column = 1;
        ddBarColor = uidropdown(dlgGL, ...
            'Items', {'White', 'Black'}, ...
            'Value', 'White', ...
            'Tooltip', 'Scale bar and label color');
        ddBarColor.Layout.Row = 6; ddBarColor.Layout.Column = 2;

        % Row 7: spacer

        % Row 8: Create / Cancel buttons
        btnGo = uibutton(dlgGL, 'Text', 'Create GIF', ...
            'BackgroundColor', [0.20 0.55 0.35], ...
            'FontColor', [1 1 1]);
        btnGo.Layout.Row = 8; btnGo.Layout.Column = 1;

        btnCancel = uibutton(dlgGL, 'Text', 'Cancel', ...
            'BackgroundColor', [0.4 0.4 0.4], ...
            'FontColor', [1 1 1], ...
            'ButtonPushedFcn', @(~,~) close(dlg));
        btnCancel.Layout.Row = 8; btnCancel.Layout.Column = 2;

        btnGo.ButtonPushedFcn = @(~,~) doCreateGIF(dlg, lbGIFImages, ...
            efDelay, ddLoop, cbScaleBarGIF, ddBarColor);
    end

    function doCreateGIF(dlg, lbImages, efDelay, ddLoop, cbBar, ddBarColor)
    %DOCREATEGIF  Build and save the animated GIF from selected images.
        selIdx = lbImages.Value;
        if isempty(selIdx) || ~iscell(selIdx) && isscalar(selIdx) && selIdx < 1
            uialert(dlg, 'Select at least 2 images.', 'GIF Error');
            return;
        end
        if ~iscell(selIdx), selIdx = {selIdx}; end
        idxList = [selIdx{:}];
        if numel(idxList) < 2
            uialert(dlg, 'Select at least 2 images.', 'GIF Error');
            return;
        end

        delay     = efDelay.Value;
        loopCount = ddLoop.Value;
        addBar    = cbBar.Value;
        barColor  = [1 1 1];
        if strcmp(ddBarColor.Value, 'Black'), barColor = [0 0 0]; end

        % Loop count for GIF: Inf→0 (infinite), N→N-1 (GIF spec: 0=infinite, N=play N+1 times)
        if isinf(loopCount)
            gifLoop = 0;
        else
            gifLoop = max(0, loopCount - 1);
        end

        close(dlg);

        % Ask for save path
        startPath = appData.lastDir;
        if isempty(startPath), startPath = pwd; end
        [saveName, saveDir] = uiputfile( ...
            {'*.gif', 'Animated GIF (*.gif)'}, ...
            'Save Animated GIF', fullfile(startPath, 'animation.gif'));
        if isequal(saveName, 0), return; end
        outPath = fullfile(saveDir, saveName);

        fig.Pointer = 'watch'; drawnow;
        setStatus('Creating GIF...');

        try
            % ── Determine target dimensions (largest image) ──────────
            maxH = 0; maxW = 0;
            for qi = 1:numel(idxList)
                imgInfo = appData.images{idxList(qi)}.metadata.parserSpecific.imageData;
                maxH = max(maxH, imgInfo.height);
                maxW = max(maxW, imgInfo.width);
            end

            % ── Determine shared scale bar parameters ────────────────
            % Use the first calibrated image to compute bar length;
            % if none are calibrated, skip scale bar.
            barLenPx = 0;  barLenPhys = 0;  barUnit = '';
            if addBar
                for qi = 1:numel(idxList)
                    imgInfo = appData.images{idxList(qi)}.metadata.parserSpecific.imageData;
                    if imgInfo.calibrated
                        pxSz = imgInfo.pixelSize;
                        barUnit = imgInfo.pixelUnit;
                        targetPhys = maxW * pxSz / 5;
                        niceLens = [1 2 5 10 20 50 100 200 500 1000];
                        [~, bestIdx] = min(abs(niceLens - targetPhys));
                        barLenPhys = niceLens(bestIdx);
                        barLenPx   = barLenPhys / pxSz;
                        break;
                    end
                end
                if barLenPx == 0
                    addBar = false;  % no calibrated image found
                end
            end

            % ── Build frames ─────────────────────────────────────────
            cmapName = ddColormap.Value;
            cmap256 = getCmapByName(cmapName);

            for qi = 1:numel(idxList)
                imgInfo = appData.images{idxList(qi)}.metadata.parserSpecific.imageData;
                px = double(imgInfo.pixels);
                if imgInfo.numChannels == 3
                    px = 0.299*px(:,:,1) + 0.587*px(:,:,2) + 0.114*px(:,:,3);
                end

                % Per-image auto-contrast
                lo = percentileNoToolbox(px(:), 2);
                hi = percentileNoToolbox(px(:), 98);
                if lo >= hi, lo = min(px(:)); hi = max(px(:)); end
                if hi <= lo, hi = lo + 1; end
                dispPx = (px - lo) / (hi - lo);
                dispPx = max(0, min(1, dispPx));

                % Pad to target dimensions (centre the image)
                [curH, curW] = size(dispPx);
                if curH ~= maxH || curW ~= maxW
                    padded = zeros(maxH, maxW);
                    offY = floor((maxH - curH) / 2) + 1;
                    offX = floor((maxW - curW) / 2) + 1;
                    padded(offY:offY+curH-1, offX:offX+curW-1) = dispPx;
                    dispPx = padded;
                end

                % Map [0,1] grayscale through colormap → RGB uint8
                idxImg = max(1, min(256, round(dispPx * 255) + 1));
                rgbFrame = uint8(reshape(cmap256(idxImg(:), :), [maxH, maxW, 3]) * 255);

                % Draw scale bar directly on the RGB frame
                if addBar
                    barH   = max(2, round(maxH * 0.02));
                    margin = round(barLenPx * 0.3);
                    bx1 = maxW - margin - round(barLenPx) + 1;
                    bx2 = maxW - margin;
                    by1 = maxH - margin - barH + 1;
                    by2 = maxH - margin;

                    % Clamp to image bounds
                    bx1 = max(1, bx1); bx2 = min(maxW, bx2);
                    by1 = max(1, by1); by2 = min(maxH, by2);

                    barRGB = uint8(barColor * 255);
                    rgbFrame(by1:by2, bx1:bx2, 1) = barRGB(1);
                    rgbFrame(by1:by2, bx1:bx2, 2) = barRGB(2);
                    rgbFrame(by1:by2, bx1:bx2, 3) = barRGB(3);

                    % Render label text via temporary figure
                    if barLenPhys == round(barLenPhys)
                        lblStr = sprintf('%d %s', round(barLenPhys), barUnit);
                    else
                        lblStr = sprintf('%.2g %s', barLenPhys, barUnit);
                    end
                    rgbFrame = burnTextOnFrame(rgbFrame, lblStr, ...
                        round((bx1 + bx2) / 2), by1, barColor);
                end

                % Quantise RGB to 256-colour indexed image
                [idxFrame, cmap] = rgb2ind(rgbFrame, 256, 'nodither');

                % Write frame to GIF
                if qi == 1
                    imwrite(idxFrame, cmap, outPath, 'gif', ...
                        'LoopCount', gifLoop, 'DelayTime', delay);
                else
                    imwrite(idxFrame, cmap, outPath, 'gif', ...
                        'WriteMode', 'append', 'DelayTime', delay);
                end

                setStatus(sprintf('Creating GIF... frame %d / %d', qi, numel(idxList)));
                drawnow;
            end

            fig.Pointer = 'arrow';
            setStatus(sprintf('GIF saved: %s (%d frames)', saveName, numel(idxList)));
        catch ME
            fig.Pointer = 'arrow';
            setStatus(sprintf('GIF export failed: %s', ME.message));
            uialert(fig, sprintf('GIF creation failed:\n%s', ME.message), ...
                'Error', 'Icon', 'error');
        end
    end

    function rgb = burnTextOnFrame(rgb, str, cx, topY, color)
    %BURNTEXTONFRAME  Render text onto an RGB image using a temporary figure.
    %   cx   — horizontal centre pixel
    %   topY — pixel row just above the bar (text placed above)
        [fH, fW, ~] = size(rgb);
        tmpFig = figure('Visible', 'off', 'Color', 'k', ...
            'Units', 'pixels', 'Position', [0 0 fW fH], ...
            'MenuBar', 'none', 'ToolBar', 'none');
        tmpAx = axes(tmpFig, 'Units', 'pixels', 'Position', [0 0 fW fH], ...
            'XLim', [0.5 fW+0.5], 'YLim', [0.5 fH+0.5], 'YDir', 'reverse', ...
            'Visible', 'off', 'Color', 'none');
        image(tmpAx, 'CData', rgb, 'XData', [1 fW], 'YData', [1 fH]);
        fontSize = max(8, round(fH * 0.025));
        text(tmpAx, cx, topY - round(fH*0.005), str, ...
            'Color', color, 'FontSize', fontSize, ...
            'HorizontalAlignment', 'center', ...
            'VerticalAlignment', 'bottom', ...
            'FontWeight', 'bold');
        drawnow;
        frame = getframe(tmpAx);
        close(tmpFig);
        rgb = frame.cdata;
        % Resize back if getframe returned different dimensions
        if size(rgb,1) ~= fH || size(rgb,2) ~= fW
            rgb = imresize(rgb, [fH fW]);
        end
    end

    function cmap = getCmapByName(name)
    %GETCMAPBYNAME  Return a 256×3 colormap matrix for a given name.
        switch lower(name)
            case 'viridis'
                cmap = generateViridis(256);
            case 'plasma'
                cmap = generatePlasma(256);
            case 'inferno'
                cmap = generateInferno(256);
            otherwise
                try
                    cmap = feval(name, 256);
                catch
                    cmap = parula(256);
                end
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onBatchRename — Rename all loaded files with base_NNN
    % ════════════════════════════════════════════════════════════════════
    function onBatchRename(~, ~)
        renameBatch(1:numel(appData.images));
    end

    function onRenameSelected(~, ~)
        selVals = lbImages.Value;
        if iscell(selVals)
            idxs = [selVals{:}];
        else
            idxs = selVals;
        end
        idxs(idxs < 1 | idxs > numel(appData.images)) = [];
        if isempty(idxs)
            setStatus('No valid files selected for rename.');
            return;
        end
        renameBatch(idxs);
    end

    function renameBatch(idxs)
    %RENAMEBATCH  Rename files on disk with baseName_001, _002, ... pattern.
        if isempty(appData.images)
            setStatus('No images loaded.'); return;
        end

        baseName = strtrim(efRenameBase.Value);
        if isempty(baseName)
            setStatus('Enter a base name before renaming.');
            return;
        end

        % Confirm with user
        msg = sprintf('Rename %d file(s) on disk to %s_001, _002, ...?\nThis cannot be undone.', ...
            numel(idxs), baseName);
        answer = uiconfirm(fig, msg, 'Confirm Batch Rename', ...
            'Options', {'Rename', 'Cancel'}, 'DefaultOption', 2, 'CancelOption', 2);
        if ~strcmp(answer, 'Rename'), return; end

        fig.Pointer = 'watch'; drawnow;
        nRenamed = 0;
        for ri = 1:numel(idxs)
            ki = idxs(ri);
            try
                srcPath = appData.images{ki}.metadata.source;
                [srcDir, ~, srcExt] = fileparts(srcPath);
                newName = sprintf('%s_%03d%s', baseName, ri, srcExt);
                newPath = fullfile(srcDir, newName);

                if ~strcmp(srcPath, newPath)
                    if isfile(newPath)
                        warning('FermiViewer:rename', ...
                            'Skipped %s: target %s already exists.', srcPath, newName);
                        continue;
                    end
                    movefile(srcPath, newPath);
                    appData.images{ki}.metadata.source = newPath;
                    nRenamed = nRenamed + 1;
                end
            catch ME
                warning('FermiViewer:rename', 'Failed to rename %s: %s', ...
                    srcPath, ME.message);
            end
        end

        % Update listbox display
        refreshImageList();
        fig.Pointer = 'arrow';
        setStatus(sprintf('Renamed %d / %d files with base "%s".', ...
            nRenamed, numel(idxs), baseName));
    end

    function refreshImageList()
    %REFRESHIMAGELIST  Rebuild listbox items from current appData.images.
        if isempty(appData.images)
            lbImages.Items = {'(no images loaded)'};
            lbImages.ItemsData = {0};
            return;
        end
        names = cell(1, numel(appData.images));
        data  = cell(1, numel(appData.images));
        for ri = 1:numel(appData.images)
            [~, nm, ex] = fileparts(appData.images{ri}.metadata.source);
            names{ri} = [nm ex];
            data{ri}  = ri;
        end
        lbImages.Items = names;
        lbImages.ItemsData = data;
        % Restore selection to current active
        if appData.activeIdx >= 1 && appData.activeIdx <= numel(appData.images)
            lbImages.Value = {appData.activeIdx};
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onEditMetadata — Open Metadata Editor for active image
    % ════════════════════════════════════════════════════════════════════
    function onEditMetadata()
        if appData.activeIdx < 1 || appData.activeIdx > numel(appData.images)
            return;
        end
        imgData = appData.images{appData.activeIdx};
        corrected = templates.MetadataEditor(imgData, ParentFig=fig);
        if ~isempty(corrected)
            appData.images{appData.activeIdx} = corrected;
            displayImage();
            setStatus('Metadata updated.');
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onCopyClipboard — Copy current view to system clipboard
    % ════════════════════════════════════════════════════════════════════
    function onCopyClipboard(~, ~)
        if isempty(appData.displayImg) || isempty(ax) || ~isvalid(ax)
            return;
        end

        try
            tmpFig = figure('Visible', 'off', 'Color', 'k');
            newAx = copyobj(ax, tmpFig);
            newAx.Units = 'normalized';
            newAx.Position = [0 0 1 1];
            colormap(tmpFig, feval(ddColormap.Value, 256));
            copygraphics(tmpFig, 'Resolution', 200);
            close(tmpFig);
            setStatus('Copied to clipboard.');
        catch ME
            setStatus(sprintf('Clipboard copy failed: %s', ME.message));
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onFileDrop — Handle drag-and-drop files onto the figure
    % ════════════════════════════════════════════════════════════════════
    function onFileDrop(~, evt)
        % evt.Items contains the dropped file paths
        if isempty(evt) || ~isprop(evt, 'Items')
            return;
        end

        items = evt.Items;
        fpaths = {};

        for ki = 1:numel(items)
            fp = items(ki);
            if ischar(fp) || isstring(fp)
                fp = char(fp);
            elseif isstruct(fp) && isfield(fp, 'Path')
                fp = char(fp.Path);
            else
                continue;
            end

            [~, ~, ext] = fileparts(fp);
            if ismember(lower(ext), {'.tif', '.tiff', '.raw', '.dm3', '.dm4'})
                fpaths{end+1} = fp; %#ok<AGROW>
            end
        end

        if ~isempty(fpaths)
            loadImagesFromPaths(fpaths);
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  STACK NAVIGATOR: frame slider, prev/next, MIP
    % ════════════════════════════════════════════════════════════════════
    function showStackControls(nFrames)
    %SHOWSTACKCONTROLS  Show/configure the frame slider for multi-frame images.
        if ~isvalid(axGL), return; end
        if nFrames <= 1
            axGL.RowHeight = {'1x', 0};
            appData.stackFrames = {};
            appData.stackIdx = 0;
            return;
        end
        axGL.RowHeight = {'1x', 28};
        sldStackFrame.Limits = [1 nFrames];
        sldStackFrame.Value  = 1;
        sldStackFrame.MajorTicks = [];
        sldStackFrame.MinorTicks = [];
        lblStackFrame.Text = sprintf('1 / %d', nFrames);
        appData.stackIdx = 1;
    end

    function onStackNav(delta)
    %ONSTACKNAV  Navigate stack frames by delta (+1 / -1).
        if isempty(appData.stackFrames)
            return;
        end
        nFrames = numel(appData.stackFrames);
        newIdx = appData.stackIdx + delta;
        if newIdx < 1, newIdx = nFrames; end
        if newIdx > nFrames, newIdx = 1; end
        appData.stackIdx = newIdx;
        sldStackFrame.Value = newIdx;
        lblStackFrame.Text = sprintf('%d / %d', newIdx, nFrames);
        displayStackFrame(newIdx);
    end

    function onStackSlider(~, ~)
    %ONSTACKSLIDER  Handle frame slider value change.
        if isempty(appData.stackFrames)
            return;
        end
        idx = round(sldStackFrame.Value);
        idx = max(1, min(numel(appData.stackFrames), idx));
        appData.stackIdx = idx;
        sldStackFrame.Value = idx;
        lblStackFrame.Text = sprintf('%d / %d', idx, numel(appData.stackFrames));
        displayStackFrame(idx);
    end

    function onStackMIP(~, ~)
    %ONSTACKMIP  Maximum Intensity Projection across all stack frames.
        if isempty(appData.stackFrames)
            return;
        end

        fig.Pointer = 'watch'; drawnow;

        % Stack all frames into 3D array and take max along dim 3
        nFrames = numel(appData.stackFrames);
        [H2, W2] = size(appData.stackFrames{1});
        stack3D = zeros(H2, W2, nFrames);
        for fm = 1:nFrames
            frame = appData.stackFrames{fm};
            % Handle size mismatch gracefully
            [fh, fw] = size(frame);
            mh = min(H2, fh); mw = min(W2, fw);
            stack3D(1:mh, 1:mw, fm) = frame(1:mh, 1:mw);
        end

        mipImg = max(stack3D, [], 3);

        appData.rawPixels      = mipImg;
        appData.filteredPixels = mipImg;

        % Update slider ranges
        dMin = min(mipImg(:));
        dMax = max(mipImg(:));
        if dMax == dMin, dMax = dMin + 1; end
        sldLow.Limits = [dMin, dMax];
        sldHigh.Limits = [dMin, dMax];

        onAutoContrast([], []);
        setStatus(sprintf('MIP of %d frames', nFrames));
        fig.Pointer = 'arrow';
    end

    function displayStackFrame(idx)
    %DISPLAYSTACKFRAME  Render a specific frame from the stack.
        if idx < 1 || idx > numel(appData.stackFrames)
            return;
        end

        frame = appData.stackFrames{idx};
        appData.rawPixels      = frame;
        appData.filteredPixels = frame;

        % Update slider ranges for this frame
        dMin = min(frame(:));
        dMax = max(frame(:));
        if dMax == dMin, dMax = dMin + 1; end
        sldLow.Limits = [dMin, dMax];
        sldHigh.Limits = [dMin, dMax];

        % Auto-contrast
        pLow  = percentileNoToolbox(frame(:), 2);
        pHigh = percentileNoToolbox(frame(:), 98);
        if pLow >= pHigh
            pLow = dMin; pHigh = dMax;
        end
        sldLow.Value = pLow;
        sldHigh.Value = pHigh;

        % Stack frame change — rebuild display buffer for the new frame
        appData.displayPixels = [];
        prepareDisplayBuffer();

        dispImg = applyContrastPipeline(appData.displayPixels, pLow, pHigh);
        appData.displayImg = dispImg;

        if ~isempty(appData.imgHandle) && isvalid(appData.imgHandle)
            appData.imgHandle.CData = dispImg;
        end

        updateHistogram();
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: saveRecentFiles — Persist recent file list to MAT
    % ════════════════════════════════════════════════════════════════════
    function saveRecentFiles()
        try
            recentFiles = appData.recentFiles;
            save(recentFilePath, 'recentFiles');
        catch
            % Ignore save errors
        end
    end

    function addToRecentFiles(fp)
    %ADDTORECENTFILES  Add a file path to the recent files list (deduplicated).
        fp = char(fp);
        % Remove if already present
        appData.recentFiles(strcmp(appData.recentFiles, fp)) = [];
        % Prepend
        appData.recentFiles = [{fp}, appData.recentFiles];
        % Cap at 10
        if numel(appData.recentFiles) > 10
            appData.recentFiles = appData.recentFiles(1:10);
        end
        saveRecentFiles();
        updateRecentDropdown();
    end

    function updateRecentDropdown()
    %UPDATERECENTDROPDOWN  Refresh the Recent dropdown in the toolbar.
        if isempty(appData.recentFiles)
            ddRecent.Items = {'(recent files)'};
            ddRecent.Value = '(recent files)';
        else
            shortNames = cell(size(appData.recentFiles));
            for ri = 1:numel(appData.recentFiles)
                [~, fn, fe] = fileparts(appData.recentFiles{ri});
                shortNames{ri} = [fn fe];
            end
            ddRecent.Items     = shortNames;
            ddRecent.ItemsData = appData.recentFiles;
            ddRecent.Value     = appData.recentFiles{1};
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  PHASE 2 CALLBACKS
    % ════════════════════════════════════════════════════════════════════

    % ── Feature 1+3: Live Threshold Preview with Otsu ─────────────────
    function onLiveThreshold(~, ~)
        if isempty(appData.filteredPixels), return; end

        px = appData.filteredPixels;
        dMin = min(px(:)); dMax = max(px(:));
        otsuThresh = otsuThreshold(px);

        tFig = uifigure('Name', 'Live Threshold Preview', ...
            'Position', [250 200 500 400]);
        tGL = uigridlayout(tFig, [3 1], ...
            'RowHeight', {'1x', 30, 30}, 'Padding', [6 6 6 6]);

        tAx = uiaxes(tGL);
        tAx.Layout.Row = 1;
        imagesc(tAx, px); colormap(tAx, gray(256));
        axis(tAx, 'image'); tAx.XTick = []; tAx.YTick = [];
        tAx.Toolbar.Visible = 'off';

        % Threshold slider row
        sldRow = uigridlayout(tGL, [1 3], ...
            'ColumnWidth', {60, '1x', 60}, 'Padding', [0 0 0 0]);
        sldRow.Layout.Row = 2;
        uilabel(sldRow, 'Text', 'Threshold:', 'HorizontalAlignment', 'right');
        sldThresh = uislider(sldRow, 'Limits', [dMin dMax], 'Value', otsuThresh);
        sldThresh.Layout.Column = 2;
        sldThresh.MajorTicks = []; sldThresh.MinorTicks = [];
        lblThVal = uilabel(sldRow, 'Text', sprintf('%.0f', otsuThresh));
        lblThVal.Layout.Column = 3;

        % Button row
        btnRowT = uigridlayout(tGL, [1 3], ...
            'ColumnWidth', {'1x', 80, 80}, 'Padding', [0 0 0 0]);
        btnRowT.Layout.Row = 3;
        uilabel(btnRowT, 'Text', sprintf('Otsu: %.0f', otsuThresh), ...
            'FontColor', [0.4 0.7 0.4]);
        uibutton(btnRowT, 'Text', 'Apply', ...
            'BackgroundColor', BTN_PRIMARY, 'FontColor', BTN_FG, ...
            'ButtonPushedFcn', @(~,~) applyThreshold());
        uibutton(btnRowT, 'Text', 'Cancel', ...
            'ButtonPushedFcn', @(~,~) close(tFig));

        hOverlay = [];
        sldThresh.ValueChangedFcn = @(~,~) updateThreshPreview();
        updateThreshPreview();

        function updateThreshPreview()
            tv = sldThresh.Value;
            lblThVal.Text = sprintf('%.0f', tv);
            bw = px > tv;
            % Show red overlay on thresholded regions
            if ~isempty(hOverlay) && isvalid(hOverlay)
                delete(hOverlay);
            end
            hold(tAx, 'on');
            alphaMap = double(bw) * 0.35;
            redImg = zeros([size(bw) 3]);
            redImg(:,:,1) = 1;
            hOverlay = image(tAx, 'CData', redImg, 'AlphaData', alphaMap);
            hOverlay.HitTest = 'off';
            hold(tAx, 'off');
        end

        function applyThreshold()
            undoPush();
            tv = sldThresh.Value;
            appData.filteredPixels = double(px > tv) .* px;
            refreshDisplay();
            close(tFig);
            setStatus(sprintf('Threshold applied at %.0f', tv));
        end
    end

    function thresh = otsuThreshold(img)
    %OTSUTHRESHOLD  Compute Otsu's optimal threshold (no toolbox).
        img = double(img(:));
        nBins = 256;
        [counts, edges] = histcounts(img, nBins);
        binCenters = (edges(1:end-1) + edges(2:end)) / 2;
        totalPx = numel(img);
        sumTotal = sum(binCenters .* counts);
        sumB = 0; wB = 0;
        maxVar = 0; thresh = binCenters(1);
        for bi = 1:nBins
            wB = wB + counts(bi);
            if wB == 0, continue; end
            wF = totalPx - wB;
            if wF == 0, break; end
            sumB = sumB + binCenters(bi) * counts(bi);
            mB = sumB / wB;
            mF = (sumTotal - sumB) / wF;
            varBetween = wB * wF * (mB - mF)^2;
            if varBetween > maxVar
                maxVar = varBetween;
                thresh = binCenters(bi);
            end
        end
    end

    % ── Feature 2: Image Arithmetic ───────────────────────────────────
    function onImageMath(~, ~)
        if numel(appData.images) < 2, return; end

        % Build image name list
        names = cell(1, numel(appData.images));
        for mi = 1:numel(appData.images)
            [~, fn, fe] = fileparts(appData.images{mi}.metadata.source);
            names{mi} = sprintf('%d: %s%s', mi, fn, fe);
        end

        answer = inputdlg( ...
            {'Image A (index):', 'Image B (index):', ...
             'Operation (subtract, divide, ratio, add):'}, ...
            'Image Arithmetic', [1 44], ...
            {num2str(1), num2str(2), 'subtract'});
        if isempty(answer), return; end

        idxA = str2double(answer{1});
        idxB = str2double(answer{2});
        op   = lower(strtrim(answer{3}));

        if isnan(idxA) || isnan(idxB) || idxA < 1 || idxB < 1 || ...
                idxA > numel(appData.images) || idxB > numel(appData.images)
            uialert(fig, 'Invalid image indices.', 'Error', 'Icon', 'error');
            return;
        end

        pxA = getGrayscaleFromIdx(idxA);
        pxB = getGrayscaleFromIdx(idxB);

        % Resize to match smaller
        [hA, wA] = size(pxA); [hB, wB] = size(pxB);
        mh = min(hA, hB); mw = min(wA, wB);
        pxA = pxA(1:mh, 1:mw); pxB = pxB(1:mh, 1:mw);

        switch op
            case 'subtract'
                result = pxA - pxB;
            case 'divide'
                result = pxA ./ max(pxB, 1);
            case 'ratio'
                result = pxA ./ max(pxA + pxB, 1);
            case 'add'
                result = pxA + pxB;
            otherwise
                uialert(fig, 'Unknown operation. Use: subtract, divide, ratio, add.', ...
                    'Error', 'Icon', 'error');
                return;
        end

        % Show result in new figure
        figure('Name', sprintf('Image Math: %s', op), 'NumberTitle', 'off');
        imagesc(result); colormap(gray(256)); axis image; colorbar;
        title(sprintf('%s — %s', names{idxA}, op), 'Interpreter', 'none');

        % Only replace active image if one is loaded
        if appData.activeIdx >= 1 && ~isempty(appData.imgHandle) && isvalid(appData.imgHandle)
            undoPush();
            appData.rawPixels = result;
            appData.filteredPixels = result;
            refreshDisplay();
        end
        setStatus(sprintf('Image math: %s (A=%d, B=%d)', op, idxA, idxB));
    end

    function px = getGrayscaleFromIdx(idx)
    %GETGRAYSCALEFROMIDX  Get grayscale double pixels for image at index.
        imgInfo = appData.images{idx}.metadata.parserSpecific.imageData;
        if imgInfo.numChannels == 3
            p = double(imgInfo.pixels);
            px = 0.299*p(:,:,1) + 0.587*p(:,:,2) + 0.114*p(:,:,3);
        else
            px = double(imgInfo.pixels);
        end
    end

    % ── Feature 4: ROI Manager ────────────────────────────────────────
    function onROIManager(~, ~)
        if isempty(appData.filteredPixels), return; end

        rmFig = uifigure('Name', 'ROI Manager', ...
            'Position', [280 200 500 350]);
        rmGL = uigridlayout(rmFig, [2 1], ...
            'RowHeight', {'1x', 30}, 'Padding', [6 6 6 6]);

        % Table of ROIs
        if isempty(appData.roiList)
            tData = {};
        else
            tData = cell(numel(appData.roiList), 6);
            for ri = 1:numel(appData.roiList)
                roi = appData.roiList{ri};
                tData{ri, 1} = roi.name;
                tData{ri, 2} = sprintf('[%d:%d, %d:%d]', roi.xMin, roi.xMax, roi.yMin, roi.yMax);
                tData{ri, 3} = sprintf('%.1f', roi.stats.mean);
                tData{ri, 4} = sprintf('%.1f', roi.stats.std);
                tData{ri, 5} = sprintf('%.1f', roi.stats.min);
                tData{ri, 6} = sprintf('%.1f', roi.stats.max);
            end
        end

        uit = uitable(rmGL, ...
            'ColumnName', {'Name', 'Region', 'Mean', 'Std', 'Min', 'Max'}, ...
            'ColumnWidth', {80, 120, 60, 60, 60, 60});
        uit.Layout.Row = 1;
        if ~isempty(tData)
            uit.Data = tData;
        end

        btnRowRM = uigridlayout(rmGL, [1 3], ...
            'ColumnWidth', {80, 80, '1x'}, 'Padding', [0 0 0 0]);
        btnRowRM.Layout.Row = 2;

        uibutton(btnRowRM, 'Text', 'Add ROI', ...
            'BackgroundColor', BTN_PRIMARY, 'FontColor', BTN_FG, ...
            'ButtonPushedFcn', @(~,~) addROI());
        uibutton(btnRowRM, 'Text', 'Export CSV', ...
            'BackgroundColor', BTN_EXPORT, 'FontColor', BTN_FG, ...
            'ButtonPushedFcn', @(~,~) exportROIs());

        function addROI()
            setStatus('Draw rectangle for ROI... (Esc to cancel)');
            % Use existing rect capture mechanism
            startRectCapture('roistats');
            % The ROI will be added via showROIStatistics
        end

        function exportROIs()
            if isempty(appData.roiList), return; end
            [fn, fp] = uiputfile('*.csv', 'Export ROIs');
            if isequal(fn, 0), return; end
            fid = fopen(fullfile(fp, fn), 'w');
            fprintf(fid, 'Name,xMin,xMax,yMin,yMax,Mean,Std,Min,Max,Area\n');
            for eri = 1:numel(appData.roiList)
                roi = appData.roiList{eri};
                fprintf(fid, '%s,%d,%d,%d,%d,%.4f,%.4f,%.4f,%.4f,%d\n', ...
                    roi.name, roi.xMin, roi.xMax, roi.yMin, roi.yMax, ...
                    roi.stats.mean, roi.stats.std, roi.stats.min, roi.stats.max, roi.stats.area);
            end
            fclose(fid);
            setStatus(sprintf('Exported %d ROIs to %s', numel(appData.roiList), fn));
        end
    end

    % ── Feature 5: Session Save/Load ──────────────────────────────────
    function onSessionSave(~, ~)
        defName = 'emviewer_session.mat';
        startPath = appData.lastDir;
        if isempty(startPath) || ~isfolder(startPath), startPath = pwd; end

        [fn, fp] = uiputfile({'*.mat', 'Session File (*.mat)'}, ...
            'Save Session', fullfile(startPath, defName));
        if isequal(fn, 0), return; end
        sessionSaveAPI(fullfile(fp, fn));
    end

    function sessionSaveAPI(outPath)
        fig.Pointer = 'watch'; drawnow;
        try
            session.images     = appData.images;
            session.activeIdx  = appData.activeIdx;
            session.gamma      = appData.gamma;
            session.roiList    = appData.roiList;
            session.measureLog = appData.measurementLog;
            session.contrastLow  = sldLow.Value;
            session.contrastHigh = sldHigh.Value;
            session.colormap     = ddColormap.Value;
            session.prefs        = appData.prefs;
            session.edsChannels  = appData.edsChannels;
            save(outPath, 'session', '-v7.3');
            appData.sessionFile = outPath;
            setStatus(sprintf('Session saved: %s', outPath));
        catch ME
            uialert(fig, sprintf('Save failed:\n%s', ME.message), ...
                'Session Error', 'Icon', 'error');
        end
        fig.Pointer = 'arrow';
    end

    function onSessionLoad(~, ~)
        startPath = appData.lastDir;
        if isempty(startPath) || ~isfolder(startPath), startPath = pwd; end
        [fn, fp] = uigetfile({'*.mat', 'Session File (*.mat)'}, ...
            'Load Session', startPath);
        if isequal(fn, 0), return; end
        sessionLoadAPI(fullfile(fp, fn));
    end

    function sessionLoadAPI(inPath)
        fig.Pointer = 'watch'; drawnow;
        try
            tmp = load(inPath, 'session');
            if ~isfield(tmp, 'session')
                uialert(fig, 'Not a valid session file.', 'Error', 'Icon', 'error');
                fig.Pointer = 'arrow'; return;
            end
            s = tmp.session;
            appData.images        = s.images;
            appData.activeIdx     = s.activeIdx;
            % Reset contrast-state cache to match restored image list
            appData.imageContrastState = cell(1, numel(appData.images));
            appData.lastDisplayedIdx   = 0;
            if isfield(s, 'gamma')
                appData.gamma = s.gamma;
                sldGamma.Value = s.gamma;
                efGamma.Value = s.gamma;
            end
            if isfield(s, 'roiList'), appData.roiList = s.roiList; end
            if isfield(s, 'measureLog'), appData.measurementLog = s.measureLog; end
            if isfield(s, 'edsChannels'), appData.edsChannels = s.edsChannels; end
            if isfield(s, 'colormap') && ismember(s.colormap, ddColormap.Items)
                ddColormap.Value = s.colormap;
            end
            if isfield(s, 'prefs')
                flds = fieldnames(s.prefs);
                for fi2 = 1:numel(flds)
                    appData.prefs.(flds{fi2}) = s.prefs.(flds{fi2});
                end
            end
            rebuildImageList();
            if appData.activeIdx >= 1 && appData.activeIdx <= numel(appData.images)
                displayImage();
                if isfield(s, 'contrastLow') && isfield(s, 'contrastHigh')
                    lo2 = max(sldLow.Limits(1), min(sldLow.Limits(2), s.contrastLow));
                    hi2 = max(sldHigh.Limits(1), min(sldHigh.Limits(2), s.contrastHigh));
                    if lo2 < hi2
                        sldLow.Value  = lo2;
                        sldHigh.Value = hi2;
                    end
                    refreshDisplay();
                end
            end
            appData.sessionFile = inPath;
            setStatus(sprintf('Session loaded: %d images from %s', numel(appData.images), inPath));
        catch ME
            uialert(fig, sprintf('Load failed:\n%s', ME.message), ...
                'Session Error', 'Icon', 'error');
        end
        fig.Pointer = 'arrow';
    end

    function setGammaAPI(g)
        appData.gamma = g;
        sldGamma.Value = g;
        efGamma.Value = g;
        lblGamma.Text = 'Gamma';
        refreshDisplay();
    end

    % ── Feature 6: Recent Files Menu callback ─────────────────────────
    function onRecentFileSelected(~, evt)
        fp = evt.Value;
        if ischar(fp) && strcmp(fp, '(recent files)'), return; end
        if ~isfile(fp)
            uialert(fig, sprintf('File not found:\n%s', fp), ...
                'File Missing', 'Icon', 'warning');
            return;
        end
        loadImagesFromPaths({fp});
    end

    % ── Feature 7: Export Resolution (helper for export dialogs) ──────
    function dpi = getExportDPI()
    %GETEXPORTDPI  Read DPI from the Export DPI dropdown in the left panel.
        dpi = ddExportDPI.Value;
    end

    % ── Feature 8: Thumbnail Grid View ────────────────────────────────
    function onThumbnailGrid(~, ~)
        nImgs = numel(appData.images);
        if nImgs < 1, return; end

        nCols = ceil(sqrt(nImgs));
        nRows = ceil(nImgs / nCols);

        figure('Name', 'Image Grid', 'NumberTitle', 'off', ...
            'Units', 'normalized', 'Position', [0.1 0.1 0.7 0.7]);

        for gi = 1:nImgs
            subplot(nRows, nCols, gi);
            imgInfo = appData.images{gi}.metadata.parserSpecific.imageData;
            px = double(imgInfo.pixels);
            if imgInfo.numChannels == 3
                px = 0.299*px(:,:,1) + 0.587*px(:,:,2) + 0.114*px(:,:,3);
            end
            thumb = imaging.generateThumbnail(px, MaxSize=128);
            % Auto-contrast
            lo = percentileNoToolbox(thumb(:), 2);
            hi = percentileNoToolbox(thumb(:), 98);
            if hi <= lo, hi = lo + 1; end
            thumbDisp = max(0, min(1, (thumb - lo) / (hi - lo)));
            imagesc(thumbDisp); colormap(gray(256)); axis image off;
            [~, fn, fe] = fileparts(appData.images{gi}.metadata.source);
            title([fn fe], 'Interpreter', 'none', 'FontSize', 8);

            % Click handler to jump to image
            ax_g = gca;
            ax_g.UserData = gi;
            ax_g.ButtonDownFcn = @(src, ~) gridClickJump(src);
        end

        function gridClickJump(src)
            idx = src.UserData;
            appData.activeIdx = idx;
            lbImages.Value = {idx};
            displayImage();
            setStatus(sprintf('Jumped to image %d', idx));
        end
    end

    % ── Feature 9: Histogram Markers (integrated into updateHistogram) ──
    % (Handled by modifying updateHistogram to draw vertical lines at
    %  sldLow/sldHigh positions — see refreshHistogramMarkers below)

    function refreshHistogramMarkers()
    %REFRESHHISTOGRAMMARKERS  Draw vertical lines on histogram at contrast bounds.
        if isempty(appData.filteredPixels), return; end
        if isempty(histAx) || ~isvalid(histAx), return; end

        % Remove old markers
        delete(findobj(histAx, 'Tag', 'histMarker'));

        lo = sldLow.Value;
        hi = sldHigh.Value;
        yLims = histAx.YLim;
        hold(histAx, 'on');
        plot(histAx, [lo lo], yLims, 'c-', 'LineWidth', 1.5, ...
            'Tag', 'histMarker', 'HitTest', 'off');
        plot(histAx, [hi hi], yLims, 'm-', 'LineWidth', 1.5, ...
            'Tag', 'histMarker', 'HitTest', 'off');
        hold(histAx, 'off');
    end

    % ── Feature 10: Batch Crop Template ───────────────────────────────
    function onBatchCrop(~, ~)
        if numel(appData.images) < 2 || isempty(appData.displayImg), return; end

        setStatus('Draw crop rectangle on current image... (Esc to cancel)');
        startRectCapture('batchcrop');
    end

    function applyBatchCrop(xMin, xMax, yMin, yMax)
    %APPLYBATCHCROP  Apply the same crop region to all loaded images.
        nCropped = 0;
        for ci = 1:numel(appData.images)
            try
                imgInfo = appData.images{ci}.metadata.parserSpecific.imageData;
                px = imgInfo.pixels;
                [pH, pW, ~] = size(px);
                x1 = max(1, min(pW, xMin));
                x2 = max(1, min(pW, xMax));
                y1 = max(1, min(pH, yMin));
                y2 = max(1, min(pH, yMax));
                if x2 > x1 && y2 > y1
                    appData.images{ci}.metadata.parserSpecific.imageData.pixels = px(y1:y2, x1:x2, :);
                    [newH, newW, ~] = size(appData.images{ci}.metadata.parserSpecific.imageData.pixels);
                    appData.images{ci}.metadata.parserSpecific.imageData.width = newW;
                    appData.images{ci}.metadata.parserSpecific.imageData.height = newH;
                    nCropped = nCropped + 1;
                end
            catch
            end
        end
        displayImage();
        setStatus(sprintf('Batch crop applied to %d / %d images [%d:%d, %d:%d]', ...
            nCropped, numel(appData.images), xMin, xMax, yMin, yMax));
    end

    % ── Feature 11: Watershed Segmentation ────────────────────────────
    function onWatershed(~, ~)
        if isempty(appData.filteredPixels), return; end

        px = appData.filteredPixels;
        dMin = min(px(:)); dMax = max(px(:));
        otsu = otsuThreshold(px);

        answer = inputdlg( ...
            {sprintf('Threshold (%.0f – %.0f):', dMin, dMax), ...
             'Min particle area (pixels):'}, ...
            'Watershed Segmentation', [1 44], {num2str(round(otsu)), '10'});
        if isempty(answer), return; end

        thresh = str2double(answer{1});
        minArea = str2double(answer{2});
        if isnan(thresh) || isnan(minArea), return; end

        fig.Pointer = 'watch'; drawnow;

        % Binary threshold
        bw = px > thresh;

        % Distance transform (no toolbox) — iterative erosion
        dist = zeros(size(bw));
        current = bw;
        level = 0;
        while any(current(:))
            level = level + 1;
            dist(current) = level;
            % Erode by 1 pixel (4-connected)
            eroded = current;
            eroded(1:end-1, :) = eroded(1:end-1, :) & current(2:end, :);
            eroded(2:end, :)   = eroded(2:end, :)   & current(1:end-1, :);
            eroded(:, 1:end-1) = eroded(:, 1:end-1) & current(:, 2:end);
            eroded(:, 2:end)   = eroded(:, 2:end)   & current(:, 1:end-1);
            current = eroded;
        end

        % Find local maxima in distance map (seeds):
        % a pixel is a seed if it is strictly greater than all 8 neighbours.
        seeds = true(size(dist));
        padD = padarray(dist, [1 1], 0);
        for dr = -1:1
            for dc = -1:1
                if dr == 0 && dc == 0, continue; end
                seeds = seeds & (dist > padD((2:end-1)+dr, (2:end-1)+dc));
            end
        end
        seeds = seeds & (dist > 1);   % must be interior points

        % Label seeds
        seedLabel = bwlabelNoToolbox(seeds);
        nSeeds = max(seedLabel(:));

        % Grow seeds outward using distance-ordered expansion
        labelMap = zeros(size(bw));
        labelMap(seeds) = seedLabel(seeds);

        % Flatten distance, sort descending for marker-controlled expansion
        [sortDist, sortIdx] = sort(dist(:), 'descend');
        for si = 1:numel(sortIdx)
            if sortDist(si) == 0, break; end
            [sr, sc] = ind2sub(size(bw), sortIdx(si));
            if labelMap(sr, sc) > 0, continue; end
            % Find labeled neighbors (max 4 — N/S/W/E)
            neighbors = zeros(1, 4);
            nNbr = 0;
            if sr > 1 && labelMap(sr-1, sc) > 0, nNbr = nNbr+1; neighbors(nNbr) = labelMap(sr-1, sc); end
            if sr < size(bw,1) && labelMap(sr+1, sc) > 0, nNbr = nNbr+1; neighbors(nNbr) = labelMap(sr+1, sc); end
            if sc > 1 && labelMap(sr, sc-1) > 0, nNbr = nNbr+1; neighbors(nNbr) = labelMap(sr, sc-1); end
            if sc < size(bw,2) && labelMap(sr, sc+1) > 0, nNbr = nNbr+1; neighbors(nNbr) = labelMap(sr, sc+1); end
            if nNbr > 0
                un = unique(neighbors(1:nNbr));
                if isscalar(un)
                    labelMap(sr, sc) = un;
                end
                % If multiple different labels meet, this is a watershed line — leave as 0
            end
        end

        % Filter by area
        areas = [];
        for li = 1:nSeeds
            a = sum(labelMap(:) == li);
            if a < minArea
                labelMap(labelMap == li) = 0;
            else
                areas(end+1) = a; %#ok<AGROW>
            end
        end

        fig.Pointer = 'arrow';

        % Display result
        wFig = figure('Name', 'Watershed Segmentation', 'NumberTitle', 'off', ...
            'Units', 'pixels', 'Position', [280 200 550 450]);
        wLayout = uigridlayout(wFig, [2 1], ...
            'RowHeight', {'1x', '1x'}, 'Padding', [10 10 10 10]);

        wAx1 = uiaxes(wLayout); wAx1.Layout.Row = 1;
        imagesc(wAx1, labelMap);
        colormap(wAx1, [0 0 0; lines(max(1, nSeeds))]);
        axis(wAx1, 'image'); wAx1.XTick = []; wAx1.YTick = [];
        title(wAx1, sprintf('Watershed: %d segments', numel(areas)), 'Interpreter', 'none');

        wAx2 = uiaxes(wLayout); wAx2.Layout.Row = 2;
        if ~isempty(areas)
            histogram(wAx2, areas, min(30, numel(areas)), ...
                'FaceColor', [0.4 0.7 0.4], 'EdgeColor', 'none');
        end
        xlabel(wAx2, 'Area (px)'); ylabel(wAx2, 'Count');
        title(wAx2, 'Size Distribution', 'Interpreter', 'none');

        setStatus(sprintf('Watershed: %d segments (threshold=%.0f)', numel(areas), thresh));
    end

    % ── Feature 12: Measurement Table Export ──────────────────────────
    function onExportMeasurements(~, ~)
        if isempty(appData.measurementLog)
            uialert(fig, 'No measurements recorded yet.', 'Empty', 'Icon', 'info');
            return;
        end

        [fn, fp] = uiputfile('*.csv', 'Export Measurements');
        if isequal(fn, 0), return; end

        try
            writeMeasurementsCSV(fullfile(fp, fn));
            setStatus(sprintf('Exported %d measurements to %s', ...
                numel(appData.measurementLog), fn));
        catch ME
            uialert(fig, sprintf('Cannot write to:\n%s\n\n%s', fn, ME.message), ...
                'Export Error', 'Icon', 'error');
        end
    end

    function writeMeasurementsCSV(fullpath)
    %WRITEMEASUREMENTSCSV  Write the measurement log to a CSV file.
    %   Shared by onExportMeasurements (GUI path) and the
    %   api.exportMeasurements (headless path). Throws on I/O error.
        if isempty(appData.measurementLog)
            error('FermiViewer:noMeasurements', 'No measurements to export.');
        end
        fid = fopen(fullpath, 'w');
        if fid == -1
            error('FermiViewer:cannotWrite', 'Cannot open file for writing: %s', fullpath);
        end
        cleaner = onCleanup(@() fclose(fid));
        fprintf(fid, 'Type,Value,Unit,Details\n');
        for mi = 1:numel(appData.measurementLog)
            m = appData.measurementLog{mi};
            details = strrep(m.details, '"', '""');
            fprintf(fid, '%s,%.6g,%s,"%s"\n', m.type, m.value, m.unit, details);
        end
    end

    % ── Feature 13: Gamma Curve ───────────────────────────────────────
    function onGammaChanged(~, ~)
        appData.gamma = sldGamma.Value;
        efGamma.Value = appData.gamma;
        lblGamma.Text = 'Gamma';
        % Contrast-only path (no filter change) — reuse cached display buf.
        onContrastChanged([], []);
    end

    % ── Feature 14: Image Montage / Stitching ─────────────────────────
    function onMontage(~, ~)
        if numel(appData.images) < 2, return; end

        nImgs = numel(appData.images);
        defCols = ceil(sqrt(nImgs));

        answer = inputdlg( ...
            {'Columns:', 'Overlap % (0-50):'}, ...
            'Montage / Stitch', [1 36], {num2str(defCols), '0'});
        if isempty(answer), return; end

        nCols = round(str2double(answer{1}));
        overlap = str2double(answer{2}) / 100;
        if isnan(nCols) || nCols < 1, nCols = defCols; end
        if isnan(overlap), overlap = 0; end
        overlap = max(0, min(0.5, overlap));

        fig.Pointer = 'watch'; drawnow;

        nRows2 = ceil(nImgs / nCols);

        % Get all tiles as grayscale
        tiles = cell(1, nImgs);
        maxH = 0; maxW = 0;
        for ti = 1:nImgs
            tiles{ti} = getGrayscaleFromIdx(ti);
            [h, w] = size(tiles{ti});
            maxH = max(maxH, h); maxW = max(maxW, w);
        end

        % Compute output size
        stepY = round(maxH * (1 - overlap));
        stepX = round(maxW * (1 - overlap));
        outH = (nRows2 - 1) * stepY + maxH;
        outW = (nCols - 1) * stepX + maxW;
        montage = zeros(outH, outW);
        weight  = zeros(outH, outW);

        for ti = 1:nImgs
            row = floor((ti - 1) / nCols);
            col = mod(ti - 1, nCols);
            y0 = row * stepY + 1;
            x0 = col * stepX + 1;
            [th, tw] = size(tiles{ti});
            yEnd = min(outH, y0 + th - 1);
            xEnd = min(outW, x0 + tw - 1);
            rh = yEnd - y0 + 1; rw = xEnd - x0 + 1;
            montage(y0:yEnd, x0:xEnd) = montage(y0:yEnd, x0:xEnd) + tiles{ti}(1:rh, 1:rw);
            weight(y0:yEnd, x0:xEnd)  = weight(y0:yEnd, x0:xEnd)  + 1;
        end

        weight(weight == 0) = 1;
        montage = montage ./ weight;

        fig.Pointer = 'arrow';

        % Display in new figure
        figure('Name', 'Montage', 'NumberTitle', 'off');
        imagesc(montage); colormap(gray(256)); axis image;
        title(sprintf('%d images, %dx%d grid, %.0f%% overlap', ...
            nImgs, nRows2, nCols, overlap*100), 'Interpreter', 'none');
        colorbar;

        setStatus(sprintf('Montage: %dx%d grid (%dx%d px)', nRows2, nCols, outW, outH));
    end

    % ── Feature 15: Diffraction Ring Overlay ──────────────────────────
    function onDiffRings(~, ~)
        if isempty(appData.displayImg), return; end

        answer = inputdlg( ...
            {'d-spacings (Angstrom, comma-separated):', ...
             'Camera length (mm):', ...
             'Wavelength (Angstrom, e.g. 0.0251 for 200kV e-):'}, ...
            'Diffraction Ring Overlay', [1 50], ...
            {'2.338, 2.024, 1.431, 1.221', '500', '0.0251'});
        if isempty(answer), return; end

        dSpacings = str2double(strsplit(answer{1}, ','));
        camLength = str2double(answer{2});
        wavelength = str2double(answer{3});

        if any(isnan(dSpacings)) || isnan(camLength) || isnan(wavelength)
            uialert(fig, 'Invalid parameters.', 'Error', 'Icon', 'error');
            return;
        end

        [H, W] = size(appData.filteredPixels);
        cx = W / 2; cy = H / 2;

        % Pixel size for conversion
        pixSize = 1;
        if appData.activeIdx >= 1
            imgInfo = appData.images{appData.activeIdx}.metadata.parserSpecific.imageData;
            if imgInfo.calibrated && ~isnan(imgInfo.pixelSize)
                pixSize = imgInfo.pixelSize;
            end
        end

        colors = lines(numel(dSpacings));
        hold(ax, 'on');
        for di = 1:numel(dSpacings)
            % Bragg angle: sin(theta) = lambda / (2*d)
            sinTheta = wavelength / (2 * dSpacings(di));
            if sinTheta > 1, continue; end
            % Radius on detector: R = L * tan(2*theta), in pixels
            radius = camLength * tan(2 * asin(sinTheta)) / pixSize;

            th = linspace(0, 2*pi, 120);
            xr = cx + radius * cos(th);
            yr = cy + radius * sin(th);
            plot(ax, xr, yr, '-', 'Color', colors(di,:), 'LineWidth', 1.2, ...
                'HandleVisibility', 'off', 'HitTest', 'off');
            text(ax, cx + radius * 0.72, cy - radius * 0.72, ...
                sprintf('%.3f A', dSpacings(di)), ...
                'Color', colors(di,:), 'FontSize', 8, ...
                'HandleVisibility', 'off', 'HitTest', 'off');
        end
        hold(ax, 'off');

        setStatus(sprintf('%d diffraction rings overlaid', numel(dSpacings)));
    end

    % ── Feature 16: Minimap / Overview ────────────────────────────────
    function onMinimapToggle(~, ~)
        if cbMinimap.Value && ~isempty(appData.displayImg)
            buildMinimap();
        else
            if ~isempty(hMinimap) && isvalid(hMinimap)
                delete(hMinimap);
                hMinimap = [];
            end
            if ~isempty(hMinimapRect) && isvalid(hMinimapRect)
                delete(hMinimapRect);
                hMinimapRect = [];
            end
        end
    end

    function buildMinimap()
    %BUILDMINIMAP  Create a small overview inset in the corner of the axes.
        if isempty(appData.displayImg) || isempty(ax) || ~isvalid(ax)
            return;
        end

        % Remove old minimap
        if ~isempty(hMinimap) && isvalid(hMinimap), delete(hMinimap); end
        if ~isempty(hMinimapRect) && isvalid(hMinimapRect), delete(hMinimapRect); end

        [H, W] = size(appData.filteredPixels);
        thumb = imaging.generateThumbnail(appData.displayImg, MaxSize=80);
        [th, tw] = size(thumb);

        % Create overlay axes positioned in upper-right corner
        % Use annotation or axes overlay
        hMinimap = axes('Parent', ax.Parent, ...
            'Units', 'pixels', 'Position', [5 5 tw+4 th+4], ...
            'Tag', 'minimap');
        imagesc(hMinimap, 'XData', [1 W], 'YData', [1 H], 'CData', thumb);
        colormap(hMinimap, gray(256)); hMinimap.CLim = [0 1];
        axis(hMinimap, 'image'); hMinimap.XTick = []; hMinimap.YTick = [];
        hMinimap.Box = 'on'; hMinimap.XColor = [0.5 0.8 1]; hMinimap.YColor = [0.5 0.8 1];
        hMinimap.YDir = 'reverse';

        updateMinimapRect();
    end

    function updateMinimapRect()
    %UPDATEMINIMAPVIEWPORT  Update the viewport rectangle on the minimap.
        if isempty(hMinimap) || ~isvalid(hMinimap), return; end
        if ~isempty(hMinimapRect) && isvalid(hMinimapRect), delete(hMinimapRect); end

        xl = ax.XLim; yl = ax.YLim;
        hold(hMinimap, 'on');
        hMinimapRect = rectangle(hMinimap, ...
            'Position', [xl(1) yl(1) diff(xl) diff(yl)], ...
            'EdgeColor', [0.5 0.8 1], 'LineWidth', 1.5, ...
            'HitTest', 'off');
        hold(hMinimap, 'off');
    end

    % ── Feature 17: Pixel Inspector ───────────────────────────────────
    function onPixelInspectorToggle(~, ~)
        if cbPixelInspector.Value && ~isempty(appData.displayImg)
            buildPixelInspector();
        else
            if ~isempty(hPixelInspector) && isvalid(hPixelInspector)
                delete(hPixelInspector);
                hPixelInspector = [];
            end
        end
    end

    function buildPixelInspector()
    %BUILDPIXELINSPECTOR  Create a small axes overlay for pixel neighborhood.
        if ~isempty(hPixelInspector) && isvalid(hPixelInspector)
            delete(hPixelInspector);
        end
        N = appData.prefs.pixelInspectorSize;
        sz = N * 18 + 4;
        hPixelInspector = axes('Parent', ax.Parent, ...
            'Units', 'pixels', 'Position', [5 90 sz sz], ...
            'Tag', 'pixelInspector');
        hPixelInspector.XTick = []; hPixelInspector.YTick = [];
        hPixelInspector.Box = 'on';
        hPixelInspector.XColor = [1 0.8 0.3]; hPixelInspector.YColor = [1 0.8 0.3];
        title(hPixelInspector, 'Pixel', 'FontSize', 7, 'Color', [1 0.8 0.3]);
    end

    function updatePixelInspector(px, py)
    %UPDATEPIXELINSPECTOR  Show NxN neighborhood of pixel values.
        if isempty(hPixelInspector) || ~isvalid(hPixelInspector), return; end
        if isempty(appData.filteredPixels), return; end

        N = appData.prefs.pixelInspectorSize;
        halfN = floor(N / 2);
        [H, W] = size(appData.filteredPixels);
        px = round(px); py = round(py);
        if px < 1 || py < 1 || px > W || py > H, return; end

        % Extract neighborhood with boundary clamping
        rows = max(1, py-halfN):min(H, py+halfN);
        cols = max(1, px-halfN):min(W, px+halfN);
        neighborhood = appData.filteredPixels(rows, cols);

        % Display as color-coded grid with text values
        cla(hPixelInspector);
        imagesc(hPixelInspector, neighborhood);
        colormap(hPixelInspector, gray(256));
        hPixelInspector.XTick = []; hPixelInspector.YTick = [];
        axis(hPixelInspector, 'image');

        % Overlay text values
        [nR, nC] = size(neighborhood);
        for ri = 1:nR
            for ci = 1:nC
                v = neighborhood(ri, ci);
                if v > mean(appData.filteredPixels(:))
                    tc = [0 0 0];
                else
                    tc = [1 1 1];
                end
                text(hPixelInspector, ci, ri, sprintf('%.0f', v), ...
                    'HorizontalAlignment', 'center', 'FontSize', 6, ...
                    'Color', tc, 'HitTest', 'off');
            end
        end
    end

    % ── Feature 18: Preferences Dialog ────────────────────────────────
    function onPreferences(~, ~)
        pFig2 = uifigure('Name', 'Preferences', 'Position', [350 250 360 280]);
        pGL = uigridlayout(pFig2, [7 2], ...
            'RowHeight', {25, 25, 25, 25, 25, 25, 30}, ...
            'ColumnWidth', {160, '1x'}, ...
            'Padding', [10 10 10 10], 'RowSpacing', 4);

        lbl1 = uilabel(pGL, 'Text', 'Default Colormap:');
        lbl1.Layout.Row = 1;
        ddPrefCmap = uidropdown(pGL, 'Items', {'gray','parula','hot','jet','bone'}, ...
            'Value', appData.prefs.defaultColormap);
        ddPrefCmap.Layout.Row = 1; ddPrefCmap.Layout.Column = 2;

        lbl2 = uilabel(pGL, 'Text', 'Auto-Contrast Low %:');
        lbl2.Layout.Row = 2;
        spnPrefLow = uispinner(pGL, 'Value', appData.prefs.autoContrastLow, ...
            'Limits', [0 49], 'Step', 1);
        spnPrefLow.Layout.Row = 2; spnPrefLow.Layout.Column = 2;

        lbl3 = uilabel(pGL, 'Text', 'Auto-Contrast High %:');
        lbl3.Layout.Row = 3;
        spnPrefHigh = uispinner(pGL, 'Value', appData.prefs.autoContrastHigh, ...
            'Limits', [51 100], 'Step', 1);
        spnPrefHigh.Layout.Row = 3; spnPrefHigh.Layout.Column = 2;

        lbl4 = uilabel(pGL, 'Text', 'Export DPI:');
        lbl4.Layout.Row = 4;
        spnPrefDPI = uispinner(pGL, 'Value', appData.prefs.exportDPI, ...
            'Limits', [72 600], 'Step', 50);
        spnPrefDPI.Layout.Row = 4; spnPrefDPI.Layout.Column = 2;

        lbl5 = uilabel(pGL, 'Text', 'Pixel Inspector Size:');
        lbl5.Layout.Row = 5;
        spnPrefInsp = uispinner(pGL, 'Value', appData.prefs.pixelInspectorSize, ...
            'Limits', [3 15], 'Step', 2);
        spnPrefInsp.Layout.Row = 5; spnPrefInsp.Layout.Column = 2;

        % Spacer row 6

        btnRowP = uigridlayout(pGL, [1 2], 'ColumnWidth', {'1x', '1x'}, 'Padding', [0 0 0 0]);
        btnRowP.Layout.Row = 7; btnRowP.Layout.Column = [1 2];

        uibutton(btnRowP, 'Text', 'Save', ...
            'BackgroundColor', BTN_PRIMARY, 'FontColor', BTN_FG, ...
            'ButtonPushedFcn', @(~,~) savePrefs());
        uibutton(btnRowP, 'Text', 'Cancel', ...
            'ButtonPushedFcn', @(~,~) close(pFig2));

        function savePrefs()
            appData.prefs.defaultColormap    = ddPrefCmap.Value;
            appData.prefs.autoContrastLow    = spnPrefLow.Value;
            appData.prefs.autoContrastHigh   = spnPrefHigh.Value;
            appData.prefs.exportDPI          = spnPrefDPI.Value;
            appData.prefs.pixelInspectorSize = spnPrefInsp.Value;
            try
                prefs = appData.prefs;
                save(prefsFilePath, 'prefs');
            catch
            end
            close(pFig2);
            setStatus('Preferences saved.');
        end
    end

    % ── Feature 19: Progress indicator (helper) ──────────────────────
    function showProgress(msg, frac)
    %SHOWPROGRESS  Update status bar with progress percentage.
        if frac >= 1
            setStatus(msg);
        else
            setStatus(sprintf('%s (%.0f%%)', msg, frac * 100));
        end
        drawnow;
    end

    % ── Feature 20: Dual-Cursor Line Profile (enhanced) ──────────────
    % (The dual-cursor is implemented by making existing line profile
    %  endpoints draggable after placement — integrated into the
    %  existing distance/profile callback flow via draggable markers)

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: setStatus — Write a message to the mouse status label
    % ════════════════════════════════════════════════════════════════════
    function setStatus(msg)
        lblStatusMouse.Text = msg;
    end

    function showLoading(msg)
    %SHOWLOADING  Display a discreet loading indicator in the status bar.
        if nargin < 1, msg = 'Loading...'; end
        lblLoadStatus.Text = msg;
        fig.Pointer = 'watch';
        drawnow;
    end

    function updateLoading(current, total, fname)
    %UPDATELOADING  Update loading progress (e.g. "Loading 2/5 file.tif").
        lblLoadStatus.Text = sprintf('Loading %d/%d  %s', current, total, fname);
        drawnow;
    end

    function hideLoading()
    %HIDELOADING  Clear the loading indicator.
        lblLoadStatus.Text = '';
        fig.Pointer = 'arrow';
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: onOff — Convert logical to 'on'/'off' string
    % ════════════════════════════════════════════════════════════════════
    function s = onOff(tf)
        if tf
            s = 'on';
        else
            s = 'off';
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  API: getLineProfileAPI — Programmatic line profile extraction
    % ════════════════════════════════════════════════════════════════════
    function result = getLineProfileAPI(x1, y1, x2, y2)
    %GETLINEPROFILEAPI  Extract a line profile from the active image.
    %   result = api.getLineProfile(x1, y1, x2, y2)
    %   Returns a struct with fields:
    %       .dist      — [Nx1] distance vector
    %       .intensity — [Nx1] interpolated intensity values (raw pixel counts)
    %       .unit      — unit string ('px' when uncalibrated)
        result = struct('dist', [], 'intensity', [], 'unit', 'px');

        if appData.activeIdx < 1 || isempty(appData.filteredPixels)
            warning('FermiViewer:noImage', 'No image loaded.');
            return;
        end

        imgInfo = appData.images{appData.activeIdx}.metadata.parserSpecific.imageData;
        ps = NaN;
        pu = 'px';
        if imgInfo.calibrated && ~isnan(imgInfo.pixelSize)
            ps = imgInfo.pixelSize;
            pu = imgInfo.pixelUnit;
        end

        if ~isnan(ps)
            [dist, intensity] = imaging.lineProfile(appData.filteredPixels, ...
                x1, y1, x2, y2, PixelSize=ps, PixelUnit=pu);
        else
            [dist, intensity] = imaging.lineProfile(appData.filteredPixels, ...
                x1, y1, x2, y2);
        end

        result.dist      = dist;
        result.intensity = intensity;
        result.unit      = pu;

        % Also cache it so Export CSV becomes available
        appData.lastProfile = result;
        btnExportProfile.Enable = 'on';
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: percentileNoToolbox — p-th percentile without Statistics Toolbox
    % ════════════════════════════════════════════════════════════════════
    function v = percentileNoToolbox(data, p)
    %PERCENTILENOTTOOLBOX  Compute the p-th percentile of a vector.
    %   Uses linear interpolation matching MATLAB's Statistics Toolbox
    %   prctile behaviour (method 5 / R-7).
        x = sort(double(data(:)));
        n = numel(x);
        if n == 0
            v = NaN;
            return;
        end
        if n == 1
            v = x(1);
            return;
        end
        % Map percentile p to a fractional index in [1, n]
        h = (p / 100) * (n - 1) + 1;   % 1-based fractional index
        lo = floor(h);
        hi = ceil(h);
        lo = max(1, min(n, lo));
        hi = max(1, min(n, hi));
        if lo == hi
            v = x(lo);
        else
            frac = h - lo;
            v = x(lo) * (1 - frac) + x(hi) * frac;
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  PHASE 3: Contrast Pipeline Helper
    % ════════════════════════════════════════════════════════════════════
    function dispImg = applyContrastPipeline(pixels, lo, hi)
    %APPLYCONTRASTPIPELINE  Apply contrast transform → window → gamma → invert.
    %  Centralizes the display pipeline so log/sqrt/power transforms,
    %  gamma correction, and image inversion are handled uniformly.
        img = double(pixels);

        % Step 1: Apply contrast transform
        switch appData.contrastTransform
            case 'log'
                % Clamp to >= -1 so log1p never produces NaN or complex values.
                % Negative slider values (post-filter images) would otherwise
                % yield log1p(lo) = NaN and divide-by-zero in the stretch step.
                img = log1p(max(img, -1));
                lo  = log1p(max(lo,  -1));
                hi  = log1p(max(hi,  -1));
            case 'sqrt'
                img = sqrt(max(img, 0));
                lo = sqrt(max(lo, 0));
                hi = sqrt(max(hi, 0));
            case 'power'
                % Clamp to >= 0: raising a negative to 0.3 yields complex
                % in MATLAB, which crashes imagesc CData assignment.
                img = max(img, 0) .^ 0.3;
                lo  = max(lo,  0) ^ 0.3;
                hi  = max(hi,  0) ^ 0.3;
            % 'linear' — no transform
        end

        % Step 2: Linear contrast stretch
        if hi <= lo
            hi = lo + 1;
        end
        dispImg = (img - lo) / (hi - lo);
        dispImg = max(0, min(1, dispImg));

        % Step 3: Gamma correction
        if appData.gamma ~= 1.0
            dispImg = dispImg .^ appData.gamma;
        end

        % Step 4: Invert
        if appData.contrastInvert
            dispImg = 1 - dispImg;
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  PHASE 3: Contrast Transform & Invert Callbacks
    % ════════════════════════════════════════════════════════════════════
    function onContrastTransformChanged(~, ~)
        appData.contrastTransform = ddContrastTransform.Value;
        % Transform is applied inside applyContrastPipeline; no filter change
        onContrastChanged([], []);
    end

    function onInvertToggle(~, ~)
        appData.contrastInvert = cbInvert.Value;
        % Invert is applied inside applyContrastPipeline; no filter change
        onContrastChanged([], []);
    end

    % ════════════════════════════════════════════════════════════════════
    %  PHASE 3: d-Spacing Measurement
    % ════════════════════════════════════════════════════════════════════
    function onDSpacing(~, ~)
        if appData.activeIdx < 1 || isempty(appData.displayImg), return; end
        if appData.compareMode, return; end
        startTwoClickCapture('dspacing');
    end

    function executeDSpacing(x1, y1, x2, y2)
    %EXECUTEDSPACING  Compute d-spacing from two FFT spots.
    %  d = N * pixelSize / r_px where r_px is distance from center.
        if appData.activeIdx < 1, return; end

        imgInfo = appData.images{appData.activeIdx}.metadata.parserSpecific.imageData;
        if ~imgInfo.calibrated || isnan(imgInfo.pixelSize)
            setStatus('d-spacing requires pixel size calibration.');
            return;
        end

        [H, W] = size(appData.filteredPixels);
        cx = W / 2;
        cy = H / 2;
        pixSize = imgInfo.pixelSize;

        % Compute distances from center for each spot
        r1 = sqrt((x1 - cx)^2 + (y1 - cy)^2);
        r2 = sqrt((x2 - cx)^2 + (y2 - cy)^2);

        % d-spacing: d = N * pixelSize / r_px
        % N is the image dimension (use geometric mean for non-square)
        N = sqrt(H * W);

        results = {};
        hold(ax, 'on');
        for si = 1:2
            if si == 1, rPx = r1; sx = x1; sy = y1;
            else,       rPx = r2; sx = x2; sy = y2;
            end
            if rPx < 1, continue; end
            dSpace = N * pixSize / rPx;
            results{end+1} = sprintf('%.3f %s', dSpace, imgInfo.pixelUnit); %#ok<AGROW>

            % Draw circle around spot
            th = linspace(0, 2*pi, 60);
            spotR = max(5, min(15, rPx * 0.05));
            plot(ax, sx + spotR*cos(th), sy + spotR*sin(th), '-', ...
                'Color', OVERLAY_COLOR, 'LineWidth', 1.5, ...
                'HandleVisibility', 'off', 'HitTest', 'off');
            text(ax, sx + spotR + 3, sy, sprintf('d=%.3f %s', dSpace, imgInfo.pixelUnit), ...
                'Color', OVERLAY_COLOR, 'FontSize', 9, ...
                'HandleVisibility', 'off', 'HitTest', 'off');
        end
        hold(ax, 'off');

        if ~isempty(results)
            setStatus(['d-spacing: ' strjoin(results, ', ')]);
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  PHASE 3: Ellipse ROI
    % ════════════════════════════════════════════════════════════════════
    function onEllipseROI(~, ~)
        if appData.activeIdx < 1 || isempty(appData.displayImg), return; end
        if appData.compareMode, return; end
        startTwoClickCapture('roiellipse');
    end

    function executeEllipseROI(cx, cy, ex, ey)
    %EXECUTEELLIPSEROI  Compute stats over a circular ROI.
    %  Center=(cx,cy), edge point=(ex,ey) defines the radius.
    %  A single edge click only provides one distance, so the ROI is always
    %  circular (radius = Euclidean distance from center to click).
        if isempty(appData.filteredPixels), return; end

        [H, W] = size(appData.filteredPixels);
        r = sqrt((ex - cx)^2 + (ey - cy)^2);
        if r < 1
            setStatus('Circle ROI too small.'); return;
        end

        % Create circular mask
        [XX, YY] = meshgrid(1:W, 1:H);
        mask = (XX - cx).^2 + (YY - cy).^2 <= r^2;
        vals = appData.filteredPixels(mask);

        if isempty(vals)
            setStatus('No pixels in circle ROI.'); return;
        end

        % Compute statistics
        roiMean = mean(vals);
        roiStd  = std(vals);
        roiMin  = min(vals);
        roiMax  = max(vals);
        roiArea = numel(vals);

        % Draw circle overlay
        hold(ax, 'on');
        th = linspace(0, 2*pi, 120);
        plot(ax, cx + r*cos(th), cy + r*sin(th), '-', ...
            'Color', OVERLAY_COLOR, 'LineWidth', 1.5, ...
            'HandleVisibility', 'off', 'HitTest', 'off');
        hold(ax, 'off');

        % Log measurement
        meas = struct('type', 'circleROI', 'cx', cx, 'cy', cy, ...
            'radius', r, 'mean', roiMean, 'std', roiStd, ...
            'min', roiMin, 'max', roiMax, 'area', roiArea);
        appData.measurementLog{end+1} = meas;

        setStatus(sprintf('Circle ROI (r=%.0fpx): mean=%.1f std=%.1f min=%.0f max=%.0f area=%d px', ...
            r, roiMean, roiStd, roiMin, roiMax, roiArea));
    end

    % ════════════════════════════════════════════════════════════════════
    %  PHASE 3: Polygon ROI (multi-click)
    % ════════════════════════════════════════════════════════════════════
    function onPolygonROI(~, ~)
        if appData.activeIdx < 1 || isempty(appData.displayImg), return; end
        if appData.compareMode, return; end
        if ~isempty(appData.captureMode), cancelCapture(); end

        appData.captureMode = 'roipoly';
        appData.captureClicks = [];
        fig.Pointer = 'crosshair';
        fig.WindowButtonDownFcn = @onPolygonClick;
        setStatus('Click polygon vertices; double-click to close (Esc to cancel)');
    end

    function onPolygonClick(~, ~)
        if ~strcmp(appData.captureMode, 'roipoly'), return; end

        cp = ax.CurrentPoint;
        x = cp(1, 1); y = cp(1, 2);
        [H, W] = size(appData.filteredPixels);
        if x < 0.5 || x > W+0.5 || y < 0.5 || y > H+0.5, return; end

        % Check for double-click BEFORE appending: WindowButtonDownFcn fires
        % twice for a double-click (first as 'normal', then as 'open').
        % Checking here avoids adding a duplicate vertex on the second fire.
        if strcmp(fig.SelectionType, 'open') && size(appData.captureClicks, 1) >= 3
            pts = appData.captureClicks;
            finishCapture();
            executePolygonROI(pts);
            return;
        end

        % Single click: append vertex and draw marker
        hMark = line(ax, x, y, 'Marker', 'o', 'MarkerSize', 5, ...
            'Color', OVERLAY_COLOR, 'MarkerFaceColor', OVERLAY_COLOR, ...
            'LineStyle', 'none', 'HandleVisibility', 'off');
        appData.overlays.clickMarkers{end+1} = hMark;
        appData.captureClicks(end+1, :) = [x, y];

        setStatus(sprintf('%d vertices placed; double-click to close', ...
            size(appData.captureClicks, 1)));
    end

    function executePolygonROI(pts)
    %EXECUTEPOLYGONROI  Compute stats over a polygon ROI defined by vertices.
        if isempty(appData.filteredPixels), return; end
        [H, W] = size(appData.filteredPixels);

        % Create polygon mask using inpolygon
        [XX, YY] = meshgrid(1:W, 1:H);
        mask = inpolygon(XX, YY, pts(:,1), pts(:,2));
        vals = appData.filteredPixels(mask);

        if isempty(vals)
            setStatus('No pixels in polygon ROI.'); return;
        end

        roiMean = mean(vals);
        roiStd  = std(vals);
        roiMin  = min(vals);
        roiMax  = max(vals);
        roiArea = numel(vals);

        % Draw polygon overlay
        hold(ax, 'on');
        plot(ax, [pts(:,1); pts(1,1)], [pts(:,2); pts(1,2)], '-', ...
            'Color', OVERLAY_COLOR, 'LineWidth', 1.5, ...
            'HandleVisibility', 'off', 'HitTest', 'off');
        hold(ax, 'off');

        meas = struct('type', 'polygonROI', 'vertices', pts, ...
            'mean', roiMean, 'std', roiStd, 'min', roiMin, 'max', roiMax, ...
            'area', roiArea);
        appData.measurementLog{end+1} = meas;

        setStatus(sprintf('Polygon ROI: mean=%.1f std=%.1f min=%.0f max=%.0f area=%d px', ...
            roiMean, roiStd, roiMin, roiMax, roiArea));
    end

    % ════════════════════════════════════════════════════════════════════
    %  PHASE 3: Image Inversion (Process)
    % ════════════════════════════════════════════════════════════════════
    function onInvertImage(~, ~)
        if isempty(appData.filteredPixels), return; end
        try
            undoPush();
            appData.filteredPixels = max(appData.filteredPixels(:)) - appData.filteredPixels;
            refreshDisplay();
            setStatus('Image inverted.');
        catch ME
            setStatus(['Invert failed: ' ME.message]);
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  PHASE 3: Unsharp Mask / Sharpen
    % ════════════════════════════════════════════════════════════════════
    function onSharpen(~, ~)
        if isempty(appData.filteredPixels), return; end
        answer = inputdlg({'Sigma:', 'Amount:'}, 'Unsharp Mask', [1 30], {'2', '1.0'});
        if isempty(answer), return; end
        sigma  = str2double(answer{1});
        amount = str2double(answer{2});
        if isnan(sigma) || isnan(amount), return; end
        try
            undoPush();
            appData.filteredPixels = imaging.unsharpMask(appData.filteredPixels, ...
                Sigma=sigma, Amount=amount);
            refreshDisplay();
            setStatus(sprintf('Sharpened (sigma=%.1f, amount=%.1f)', sigma, amount));
        catch ME
            setStatus(['Sharpen failed: ' ME.message]);
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  PHASE 3: Image Binning
    % ════════════════════════════════════════════════════════════════════
    function onBinImage(~, ~)
        if isempty(appData.filteredPixels), return; end
        answer = inputdlg({'Bin size (2, 4, or 8):', 'Mode (average or sum):'}, ...
            'Bin Image', [1 30], {'2', 'average'});
        if isempty(answer), return; end
        binSz = round(str2double(answer{1}));
        mode  = strtrim(answer{2});
        if isnan(binSz) || ~any(binSz == [2 4 8]), binSz = 2; end
        if ~any(strcmp(mode, {'average', 'sum'})), mode = 'average'; end
        try
            undoPush();
            appData.filteredPixels = imaging.binImage(appData.filteredPixels, ...
                BinSize=binSz, Mode=mode);
            appData.rawPixels = appData.filteredPixels;
            rebuildAxesForNewSize();
            setStatus(sprintf('Binned %dx%d (%s)', binSz, binSz, mode));
        catch ME
            setStatus(['Bin failed: ' ME.message]);
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  PHASE 3: Morphological Operations
    % ════════════════════════════════════════════════════════════════════
    function onMorphOp(~, ~)
        if isempty(appData.filteredPixels), return; end
        answer = inputdlg({'Operation (erode/dilate/open/close):', 'Radius (1-10):'}, ...
            'Morphological Operation', [1 40], {'open', '2'});
        if isempty(answer), return; end
        op = strtrim(answer{1});
        radius = round(str2double(answer{2}));
        if isnan(radius) || radius < 1, radius = 2; end
        try
            undoPush();
            appData.filteredPixels = imaging.morphOp(appData.filteredPixels, op, ...
                Radius=radius);
            refreshDisplay();
            setStatus(sprintf('Morphological %s (radius=%d)', op, radius));
        catch ME
            setStatus(['Morph op failed: ' ME.message]);
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  PHASE 3: Butterworth Bandpass Filter
    % ════════════════════════════════════════════════════════════════════
    function onButterworth(~, ~)
        if isempty(appData.filteredPixels), return; end
        answer = inputdlg({'Low cutoff (0-1, 0=no highpass):', ...
                           'High cutoff (0-1, 1=no lowpass):', ...
                           'Order (1-10):'}, ...
            'Butterworth Filter', [1 40], {'0', '0.5', '2'});
        if isempty(answer), return; end
        lowC  = str2double(answer{1});
        highC = str2double(answer{2});
        order = round(str2double(answer{3}));
        if isnan(lowC),  lowC  = 0; end
        if isnan(highC), highC = 0.5; end
        if isnan(order), order = 2; end
        try
            undoPush();
            appData.filteredPixels = imaging.butterworthFilter(appData.filteredPixels, ...
                LowCutoff=lowC, HighCutoff=highC, Order=order);
            refreshDisplay();
            setStatus(sprintf('Butterworth filter (low=%.2f, high=%.2f, order=%d)', ...
                lowC, highC, order));
        catch ME
            setStatus(['Butterworth failed: ' ME.message]);
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  PHASE 3: Radial Profile from FFT / Diffraction
    % ════════════════════════════════════════════════════════════════════
    function onRadialProfile(~, ~)
        if isempty(appData.filteredPixels), return; end
        try
            % Compute FFT magnitude for radial profile
            [mag, ~] = imaging.computeFFT(appData.filteredPixels);
            [radii, avgProf, maxProf] = imaging.radialProfile(mag);

            % Plot in new figure
            figure('Name', 'Radial Profile', 'NumberTitle', 'off');
            subplot(1, 2, 1);
            plot(radii, avgProf, 'b-', 'LineWidth', 1.2);
            xlabel('Spatial Frequency (px^{-1})'); ylabel('Mean Intensity');
            title('Radial Average'); grid on;

            subplot(1, 2, 2);
            plot(radii, maxProf, 'r-', 'LineWidth', 1.2);
            xlabel('Spatial Frequency (px^{-1})'); ylabel('Max Intensity');
            title('Radial Maximum'); grid on;

            setStatus('Radial profile computed from FFT.');
        catch ME
            setStatus(['Radial profile failed: ' ME.message]);
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  PHASE 3: Azimuthal Integration
    % ════════════════════════════════════════════════════════════════════
    function onAzIntegrate(~, ~)
        if isempty(appData.filteredPixels), return; end
        try
            [mag, ~] = imaging.computeFFT(appData.filteredPixels);
            [radii, intensity] = imaging.azimuthalIntegrate(mag);

            figure('Name', 'Azimuthal Integration', 'NumberTitle', 'off');
            plot(radii, intensity, 'k-', 'LineWidth', 1.2);
            xlabel('Spatial Frequency (px^{-1})'); ylabel('Integrated Intensity');
            title('Azimuthal Integration'); grid on;

            setStatus('Azimuthal integration complete.');
        catch ME
            setStatus(['Azimuthal integration failed: ' ME.message]);
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  PHASE 3: Surface / 3D Plot
    % ════════════════════════════════════════════════════════════════════
    function onSurfacePlot(~, ~)
        if isempty(appData.filteredPixels), return; end
        try
            img = appData.filteredPixels;
            % Downsample if large (>512 in any dimension)
            [H, W] = size(img);
            maxDim = 512;
            if H > maxDim || W > maxDim
                scaleFactor = maxDim / max(H, W);
                newH = round(H * scaleFactor);
                newW = round(W * scaleFactor);
                [Xq, Yq] = meshgrid(linspace(1, W, newW), linspace(1, H, newH));
                [Xo, Yo] = meshgrid(1:W, 1:H);
                img = interp2(Xo, Yo, img, Xq, Yq, 'linear');
            end

            figure('Name', 'Surface Plot', 'NumberTitle', 'off');
            surf(img, 'EdgeColor', 'none');
            colormap(parula); colorbar;
            xlabel('X (px)'); ylabel('Y (px)'); zlabel('Intensity');
            title('Image Intensity Surface');
            view(45, 30);

            setStatus('Surface plot opened.');
        catch ME
            setStatus(['Surface plot failed: ' ME.message]);
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  PHASE 3: Batch Format Conversion
    % ════════════════════════════════════════════════════════════════════
    function onBatchConvert(~, ~)
        if isempty(appData.images), return; end

        answer = inputdlg({'Output format (png/tiff/jpeg):', 'Output directory (blank = same as source):'}, ...
            'Batch Convert', [1 50], {'png', ''});
        if isempty(answer), return; end
        fmt = lower(strtrim(answer{1}));
        outDir = strtrim(answer{2});
        if ~any(strcmp(fmt, {'png', 'tiff', 'jpeg', 'jpg'}))
            setStatus('Unsupported format. Use png, tiff, or jpeg.');
            return;
        end
        if strcmp(fmt, 'jpg'), fmt = 'jpeg'; end

        fig.Pointer = 'watch'; drawnow;
        nConverted = 0;
        for ki = 1:numel(appData.images)
            try
                ds = appData.images{ki};
                imgInfo = ds.metadata.parserSpecific.imageData;
                pixels = double(imgInfo.pixels);
                if size(pixels, 3) == 3
                    pixels = 0.299*pixels(:,:,1) + 0.587*pixels(:,:,2) + 0.114*pixels(:,:,3);
                end

                % Auto-contrast for export
                pL = percentileNoToolbox(pixels(:), 2);
                pH = percentileNoToolbox(pixels(:), 98);
                if pH <= pL, pH = pL + 1; end
                outImg = (pixels - pL) / (pH - pL);
                outImg = max(0, min(1, outImg));

                [srcDir, srcName, ~] = fileparts(ds.metadata.source);
                if ~isempty(outDir), srcDir = outDir; end
                if ~isfolder(srcDir), mkdir(srcDir); end
                outPath = fullfile(srcDir, [srcName '.' fmt]);
                imwrite(uint8(outImg * 255), outPath, fmt);
                nConverted = nConverted + 1;
            catch ME
                setStatus(sprintf('Batch convert: image %d failed — %s', ki, ME.message));
            end
        end
        fig.Pointer = 'arrow';
        setStatus(sprintf('Converted %d / %d images to %s.', nConverted, numel(appData.images), fmt));
    end

    % ════════════════════════════════════════════════════════════════════
    %  PHASE 3: Custom Colormap
    % ════════════════════════════════════════════════════════════════════
    function onCustomColormap(~, ~)
        answer = inputdlg({'Color stops (e.g. "0 0 0; 1 0 0; 1 1 1" for black→red→white):'}, ...
            'Custom Colormap', [3 60], {'0 0 0; 1 0 0; 1 1 1'});
        if isempty(answer), return; end
        try
            % Parse color stops without eval (str2num is eval-based).
            % Expected input: "R G B; R G B; ..." where values are 0-1 doubles.
            rawRows = strsplit(strtrim(answer{1}), ';');
            stops = zeros(numel(rawRows), 3);
            parseOk = true;
            for rr = 1:numel(rawRows)
                rowVals = str2double(strsplit(strtrim(rawRows{rr})));
                if numel(rowVals) ~= 3 || any(isnan(rowVals))
                    parseOk = false; break;
                end
                stops(rr, :) = rowVals;
            end
            if ~parseOk || size(stops, 1) < 2
                setStatus('Enter at least 2 rows of R G B values (0-1).');
                return;
            end
            stops = max(0, min(1, stops));
            nStops = size(stops, 1);
            cmap = zeros(256, 3);
            for ch = 1:3
                cmap(:, ch) = interp1(linspace(0, 1, nStops), stops(:, ch), ...
                    linspace(0, 1, 256), 'linear');
            end
            if ~isempty(ax) && isvalid(ax)
                colormap(ax, cmap);
            end
            setStatus('Custom colormap applied.');
        catch ME
            setStatus(['Custom colormap failed: ' ME.message]);
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  PHASE 3: Arrow Annotation
    % ════════════════════════════════════════════════════════════════════
    function onPlaceArrow(~, ~)
        if appData.activeIdx < 1 || isempty(appData.displayImg), return; end
        if appData.compareMode, return; end
        startTwoClickCapture('arrow');
    end

    function executeArrow(x1, y1, x2, y2)
    %EXECUTEARROW  Draw an arrow from (x1,y1) to (x2,y2) with arrowhead.
        color = appData.annotationColor;

        % Draw line
        hold(ax, 'on');
        hLine = plot(ax, [x1 x2], [y1 y2], '-', ...
            'Color', color, 'LineWidth', 2, ...
            'HandleVisibility', 'off', 'HitTest', 'off');

        % Draw arrowhead using a small triangle patch
        dx = x2 - x1;
        dy = y2 - y1;
        len = sqrt(dx^2 + dy^2);
        if len < 1, hold(ax, 'off'); return; end
        ux = dx / len;
        uy = dy / len;

        headLen = min(15, len * 0.2);
        headW   = headLen * 0.5;

        % Arrowhead vertices: tip, left, right
        tipX = x2;
        tipY = y2;
        leftX = x2 - headLen * ux + headW * uy;
        leftY = y2 - headLen * uy - headW * ux;
        rightX = x2 - headLen * ux - headW * uy;
        rightY = y2 - headLen * uy + headW * ux;

        hHead = patch(ax, [tipX leftX rightX], [tipY leftY rightY], color, ...
            'EdgeColor', color, 'FaceColor', color, ...
            'HandleVisibility', 'off', 'HitTest', 'off');
        hold(ax, 'off');

        annot = struct('type', 'arrow', 'hLine', hLine, 'hHead', hHead, ...
            'x1', x1, 'y1', y1, 'x2', x2, 'y2', y2, 'color', color);
        appData.overlays.textAnnotations{end+1} = annot;

        setStatus(sprintf('Arrow placed (%.0f,%.0f) → (%.0f,%.0f)', x1, y1, x2, y2));
    end

    % ════════════════════════════════════════════════════════════════════
    %  PHASE 3: Line / Rectangle / Circle Shape Annotations
    % ════════════════════════════════════════════════════════════════════
    function onPlaceLine(~, ~)
        if appData.activeIdx < 1 || isempty(appData.displayImg), return; end
        if appData.compareMode, return; end
        startTwoClickCapture('annotline');
    end

    function onPlaceRect(~, ~)
        if appData.activeIdx < 1 || isempty(appData.displayImg), return; end
        if appData.compareMode, return; end
        startTwoClickCapture('annotrect');
    end

    function onPlaceCircle(~, ~)
        if appData.activeIdx < 1 || isempty(appData.displayImg), return; end
        if appData.compareMode, return; end
        startTwoClickCapture('annotcircle');
    end

    function executeAnnotLine(x1, y1, x2, y2)
        color = appData.annotationColor;
        hold(ax, 'on');
        hL = plot(ax, [x1 x2], [y1 y2], '-', 'Color', color, 'LineWidth', 2, ...
            'HandleVisibility', 'off', 'HitTest', 'off');
        hold(ax, 'off');
        annot = struct('type', 'line', 'hLine', hL, ...
            'x1', x1, 'y1', y1, 'x2', x2, 'y2', y2, 'color', color);
        appData.overlays.textAnnotations{end+1} = annot;
        setStatus(sprintf('Line annotation placed.'));
    end

    function executeAnnotRect(x1, y1, x2, y2)
        color = appData.annotationColor;
        xMin = min(x1, x2); yMin = min(y1, y2);
        w = abs(x2 - x1); h = abs(y2 - y1);
        hold(ax, 'on');
        hR = rectangle(ax, 'Position', [xMin yMin w h], ...
            'EdgeColor', color, 'LineWidth', 2, ...
            'FaceColor', 'none', 'HitTest', 'off');
        hold(ax, 'off');
        annot = struct('type', 'rectangle', 'hRect', hR, ...
            'x1', x1, 'y1', y1, 'x2', x2, 'y2', y2, 'color', color);
        appData.overlays.textAnnotations{end+1} = annot;
        setStatus('Rectangle annotation placed.');
    end

    function executeAnnotCircle(cx, cy, ex, ey)
        color = appData.annotationColor;
        r = sqrt((ex - cx)^2 + (ey - cy)^2);
        if r < 1, return; end
        hold(ax, 'on');
        th = linspace(0, 2*pi, 120);
        hC = plot(ax, cx + r*cos(th), cy + r*sin(th), '-', ...
            'Color', color, 'LineWidth', 2, ...
            'HandleVisibility', 'off', 'HitTest', 'off');
        hold(ax, 'off');
        annot = struct('type', 'circle', 'hCircle', hC, ...
            'cx', cx, 'cy', cy, 'radius', r, 'color', color);
        appData.overlays.textAnnotations{end+1} = annot;
        setStatus(sprintf('Circle annotation placed (r=%.0f px).', r));
    end

    % ════════════════════════════════════════════════════════════════════
    %  PHASE 3: Width-Averaged Line Profile
    % ════════════════════════════════════════════════════════════════════
    function profile = runWidthAveragedProfile(x1, y1, x2, y2, width)
    %RUNWIDTHAVERAGEDPROFILE  Compute a width-averaged intensity profile.
    %  Samples 'width' parallel lines perpendicular to the profile direction
    %  and averages them.
        if width <= 1
            % Standard single-pixel profile
            [profile.dist, profile.intensity] = imaging.lineProfile(...
                appData.filteredPixels, x1, y1, x2, y2);
            return;
        end

        % Perpendicular unit vector
        dx = x2 - x1;
        dy = y2 - y1;
        len = sqrt(dx^2 + dy^2);
        if len < 1
            profile.dist = 0;
            profile.intensity = 0;
            return;
        end
        px = -dy / len;  % perpendicular x
        py =  dx / len;  % perpendicular y

        halfW = (width - 1) / 2;
        offsets = linspace(-halfW, halfW, width);

        % Sample parallel profiles
        % Use NaN initialisation so that out-of-boundary pixels (returned as
        % NaN by imaging.lineProfile's interp2) do not bias the average toward
        % zero when lines extend outside the image.
        % Pre-compute profile length from the centre line
        [d, refI] = imaging.lineProfile(appData.filteredPixels, x1, y1, x2, y2);
        nProfPts = numel(refI);
        allI = NaN(numel(offsets), nProfPts);
        allI(1, :) = refI;  % centre line is offset index ceil(width/2)
        for oi = 1:numel(offsets)
            off = offsets(oi);
            if off == 0, allI(oi, :) = refI; continue; end
            ox1 = x1 + off * px;
            oy1 = y1 + off * py;
            ox2 = x2 + off * px;
            oy2 = y2 + off * py;
            [~, intensity] = imaging.lineProfile(appData.filteredPixels, ...
                ox1, oy1, ox2, oy2);
            nPts = min(nProfPts, numel(intensity));
            allI(oi, 1:nPts) = intensity(1:nPts);
        end

        profile.dist = d;
        profile.intensity = mean(allI, 1, 'omitnan');
    end

    % ════════════════════════════════════════════════════════════════════
    %  PHASE 3: Helper — rebuild axes after dimension-changing operations
    % ════════════════════════════════════════════════════════════════════
    function rebuildAxesForNewSize()
    %REBUILDAXESFORNEWSIZE  Rebuild image display after binning/crop changes dimensions.
        [H, W] = size(appData.filteredPixels);
        lo = sldLow.Value;
        hi = sldHigh.Value;

        % Clamp slider limits to new data range
        dMin = min(appData.filteredPixels(:));
        dMax = max(appData.filteredPixels(:));
        if dMax == dMin, dMax = dMin + 1; end
        sldLow.Limits = [dMin dMax];
        sldHigh.Limits = [dMin dMax];
        sldLow.Value = max(dMin, min(lo, dMax));
        sldHigh.Value = max(dMin, min(hi, dMax));

        appData.displayPixels = [];
        prepareDisplayBuffer();
        dispImg = applyContrastPipeline(appData.displayPixels, sldLow.Value, sldHigh.Value);
        appData.displayImg = dispImg;

        if ~isempty(ax) && isvalid(ax)
            delete(ax.Children);
            cla(ax);
            dr = appData.displayRegion;
            if isempty(dr), dr = [1, 1, W, H]; end
            hImg = imagesc(ax, 'XData', [dr(1) dr(3)], 'YData', [dr(2) dr(4)], 'CData', dispImg);
            try, hImg.Interpolation = 'nearest'; catch, end
            appData.imgHandle = hImg;
            attachImageContextMenu();
            colormap(ax, feval(ddColormap.Value, 256));
            ax.CLim = [0 1]; ax.YDir = 'reverse';
            axis(ax, 'equal');
            ax.XLim = [0.5, W+0.5]; ax.YLim = [0.5, H+0.5];
            ax.XTick = []; ax.YTick = []; ax.Toolbar.Visible = 'off';
        end

        updateStatusBar();
        updateHistogram();
        if ~isempty(cbScaleBar) && isvalid(cbScaleBar) && ...
                strcmp(cbScaleBar.Enable, 'on') && cbScaleBar.Value
            rebuildScaleBar();
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  PHASE 4: HELPERS
    % ════════════════════════════════════════════════════════════════════

    function px = guiPixelSize()
    %GUIPIXELSIZE  Return pixel size of the active image (0 if uncalibrated).
        px = 0;
        if isempty(appData.images) || appData.activeIdx < 1, return; end
        try
            imgInfo = appData.images{appData.activeIdx}.metadata.parserSpecific.imageData;
            if imgInfo.calibrated && ~isnan(imgInfo.pixelSize)
                px = imgInfo.pixelSize;
            end
        catch
        end
    end

    function pu = guiPixelUnit()
    %GUIPIXELUNIT  Return pixel unit string of the active image.
        pu = 'px';
        if isempty(appData.images) || appData.activeIdx < 1, return; end
        try
            imgInfo = appData.images{appData.activeIdx}.metadata.parserSpecific.imageData;
            if imgInfo.calibrated && ~isnan(imgInfo.pixelSize)
                pu = imgInfo.pixelUnit;
            end
        catch
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  PHASE 4: ANALYSIS & PUBLICATION FEATURES
    % ════════════════════════════════════════════════════════════════════

    % ── Feature 6: Plane Leveling ──────────────────────────────────────
    function onPlaneLevel(~, ~)
        if isempty(appData.rawPixels), return; end
        answer = inputdlg('Polynomial order (1=plane, 2=quadratic, 3=cubic):', ...
            'Plane Level', [1 40], {'1'});
        if isempty(answer), return; end
        order = str2double(answer{1});
        if isnan(order) || ~ismember(order, [1 2 3])
            uialert(fig, 'Order must be 1, 2, or 3.', 'Invalid'); return;
        end
        try
            undoPush();
            result = imaging.planeLevel(double(appData.filteredPixels), Order=order);
            appData.filteredPixels = result.leveled;
            displayImage();
            setStatus(sprintf('Plane leveled (order %d).', order));
        catch ME
            setStatus(['Plane level error: ' ME.message]);
        end
    end

    % ── Feature 4: Surface Roughness ───────────────────────────────────
    function onRoughness(~, ~)
        if isempty(appData.rawPixels), return; end
        try
            px = guiPixelSize();
            pu = guiPixelUnit();
            result = imaging.surfaceRoughness(double(appData.filteredPixels), ...
                PixelSize=px, PixelUnit=pu, Level='plane');
            msg = sprintf(['Surface Roughness\n\n' ...
                'Ra  = %.4g %s\nRq  = %.4g %s\nRz  = %.4g %s\n' ...
                'Rsk = %.4f\nRku = %.4f\nRp  = %.4g %s\nRv  = %.4g %s\n' ...
                'SAR = %.4f'], ...
                result.Ra, pu, result.Rq, pu, result.Rz, pu, ...
                result.Rsk, result.Rku, result.Rp, pu, result.Rv, pu, ...
                result.SAR);
            uialert(fig, msg, 'Roughness Statistics', 'Icon', 'info');
            setStatus(sprintf('Roughness: Ra=%.3g, Rq=%.3g %s', result.Ra, result.Rq, pu));
        catch ME
            setStatus(['Roughness error: ' ME.message]);
        end
    end

    % ── Feature 5: Interface Width Fit ─────────────────────────────────
    function onInterfaceFit(~, ~)
        if isempty(appData.rawPixels), return; end
        if ~isfield(appData, 'lastProfile') || isempty(appData.lastProfile)
            uialert(fig, 'Draw a line profile first, then click Interface Fit.', 'No profile');
            return;
        end
        try
            lp = appData.lastProfile;
            result = imaging.fitInterfaceWidth(lp.dist, lp.intensity);
            % Show fit on profile plot
            msg = sprintf(['Interface Width Fit\n\n' ...
                'Center: %.2f\nSigma: %.3f\n' ...
                '10-90%% width: %.3f\nR^2: %.4f\nModel: %s'], ...
                result.center, result.sigma, result.width1090, ...
                result.rSquared, result.model);
            uialert(fig, msg, 'Interface Fit', 'Icon', 'info');
            setStatus(sprintf('Interface width: %.3f (10-90%%)', result.width1090));
        catch ME
            setStatus(['Interface fit error: ' ME.message]);
        end
    end

    % ── Feature 13: Multi-class Threshold ──────────────────────────────
    function onMultiOtsu(~, ~)
        if isempty(appData.rawPixels), return; end
        answer = inputdlg('Number of classes (2-5):', 'Multi-Otsu', [1 30], {'3'});
        if isempty(answer), return; end
        nClass = str2double(answer{1});
        if isnan(nClass) || nClass < 2 || nClass > 5
            uialert(fig, 'Classes must be 2-5.', 'Invalid'); return;
        end
        try
            result = imaging.multiOtsu(appData.filteredPixels, NumClasses=nClass);
            % Display label map as colored overlay
            classColors = [0 0 0.7; 0 0.7 0; 0.7 0 0; 0.7 0.7 0; 0.7 0 0.7];
            [H, W] = size(result.labelMap);
            rgb = zeros(H, W, 3);
            for ci = 1:nClass
                mask = result.labelMap == ci;
                for ch = 1:3
                    rgb(:,:,ch) = rgb(:,:,ch) + classColors(ci,ch) * double(mask);
                end
            end
            % Show in new figure
            figSeg = figure('Name', 'Multi-class Segmentation', 'NumberTitle', 'off');
            subplot(1,2,1); imagesc(appData.filteredPixels); colormap(gca, gray(256));
            axis equal tight; title('Original');
            subplot(1,2,2); image(rgb); axis equal tight; title(sprintf('%d-class Otsu', nClass));
            % Report fractions
            fracStr = strjoin(arrayfun(@(i) sprintf('Class %d: %.1f%%', i, ...
                result.classFractions(i)*100), 1:nClass, 'UniformOutput', false), ', ');
            setStatus(fracStr);
        catch ME
            setStatus(['Multi-Otsu error: ' ME.message]);
        end
    end

    % ── Feature 1: Lattice Measure from FFT ────────────────────────────
    function onLatticeMeasure(~, ~)
        if isempty(appData.rawPixels), return; end
        px = guiPixelSize();
        pu = guiPixelUnit();
        if px <= 0
            uialert(fig, 'Set pixel calibration first (pixel size > 0).', 'No calibration');
            return;
        end
        appData.captureMode = 'lattice';
        appData.captureClicks = [];
        setStatus('Lattice: click two FFT spots (non-collinear). Esc to cancel.');
    end

    function executeLattice()
        pts = appData.captureClicks;
        if size(pts, 1) < 2, return; end
        try
            [H, W] = size(appData.filteredPixels);
            px = guiPixelSize();
            pu = guiPixelUnit();
            result = imaging.latticeMeasure( ...
                [pts(1,2), pts(1,1)], [pts(2,2), pts(2,1)], [H, W], ...
                PixelSize=px, PixelUnit=pu);
            msg = sprintf(['Lattice Parameters\n\n' ...
                'a = %.3f %s\nb = %.3f %s\n' char(947) ' = %.1f' char(176) '\n' ...
                'd1 = %.3f %s\nd2 = %.3f %s\nUnit cell area = %.2f %s' char(178)], ...
                result.a, pu, result.b, pu, result.gamma, ...
                result.dSpacing1, pu, result.dSpacing2, pu, result.unitCellArea, pu);
            uialert(fig, msg, 'Lattice Measurement', 'Icon', 'info');
            setStatus(sprintf('Lattice: a=%.3f, b=%.3f %s, %s=%.1f%s', ...
                result.a, result.b, pu, char(947), result.gamma, char(176)));
        catch ME
            setStatus(['Lattice error: ' ME.message]);
        end
    end

    % ── Feature 3: GPA Strain Mapping ──────────────────────────────────
    function onGPA(~, ~)
        if isempty(appData.rawPixels), return; end
        px = guiPixelSize();
        if px <= 0
            uialert(fig, 'Set pixel calibration first for meaningful strain values.', 'No calibration');
        end
        appData.captureMode = 'gpa';
        appData.captureClicks = [];
        setStatus('GPA: click two Bragg spots in the FFT. Esc to cancel.');
    end

    function executeGPA()
        pts = appData.captureClicks;
        if size(pts, 1) < 2, return; end
        try
            [H, W] = size(appData.filteredPixels);
            center = [H/2, W/2];
            g1 = [pts(1,1) - center(2), pts(1,2) - center(1)];
            g2 = [pts(2,1) - center(2), pts(2,2) - center(1)];
            px = max(guiPixelSize(), 1);
            result = imaging.geometricPhaseAnalysis( ...
                double(appData.filteredPixels), g1, g2, PixelSize=px);
            % Display strain maps in new figure
            figGPA = figure('Name', 'GPA Strain Maps', 'NumberTitle', 'off');
            ax1 = subplot(2,2,1); imagesc(result.exx); axis equal tight;
            colorbar(ax1); title('exx'); colormap(ax1, jet(256)); clim(ax1, [-0.05 0.05]);
            ax2 = subplot(2,2,2); imagesc(result.eyy); axis equal tight;
            colorbar(ax2); title('eyy'); colormap(ax2, jet(256)); clim(ax2, [-0.05 0.05]);
            ax3 = subplot(2,2,3); imagesc(result.exy); axis equal tight;
            colorbar(ax3); title('exy'); colormap(ax3, jet(256)); clim(ax3, [-0.05 0.05]);
            ax4 = subplot(2,2,4); imagesc(rad2deg(result.rotation)); axis equal tight;
            colorbar(ax4); title('Rotation (deg)'); colormap(ax4, jet(256));
            setStatus('GPA strain maps computed.');
        catch ME
            setStatus(['GPA error: ' ME.message]);
        end
    end

    % ── Feature 9: CTF Estimation ──────────────────────────────────────
    function onCTFEstimate(~, ~)
        if isempty(appData.rawPixels), return; end
        answer = inputdlg({'Voltage (kV):', 'Cs (mm):', 'Pixel size (Å):'}, ...
            'CTF Parameters', [1 40; 1 40; 1 40], {'200', '1.2', '1'});
        if isempty(answer), return; end
        kV = str2double(answer{1});
        Cs = str2double(answer{2});
        pxA = str2double(answer{3});
        if any(isnan([kV, Cs, pxA]))
            uialert(fig, 'Invalid numeric input.', 'Error'); return;
        end
        try
            result = imaging.estimateCTF(double(appData.filteredPixels), ...
                Voltage_kV=kV, Cs_mm=Cs, PixelSize=pxA);
            % Show results
            figCTF = figure('Name', 'CTF Estimation', 'NumberTitle', 'off');
            plot(result.radialProfile(:,1), log10(result.radialProfile(:,2) + 1), 'b');
            hold on;
            plot(result.radialProfile(:,1), result.ctfFit, 'r--', 'LineWidth', 1.5);
            xlabel('Spatial frequency (1/Å)'); ylabel('log10(Power + 1)');
            title(sprintf('CTF Fit: Defocus = %.0f nm (R^2 = %.3f)', ...
                result.defocus_nm, result.rSquared));
            legend('Power spectrum', 'CTF^2 fit');
            setStatus(sprintf('CTF: defocus = %.0f nm', result.defocus_nm));
        catch ME
            setStatus(['CTF error: ' ME.message]);
        end
    end

    % ── Feature 11: Defect Counter ─────────────────────────────────────
    function onDefectCount(~, ~)
        if isempty(appData.rawPixels), return; end
        answer = inputdlg({'Grid spacing (px):', 'Foil thickness (nm, 0=unknown):', ...
                           'Defect direction (deg, NaN=all):'}, ...
            'Defect Counter', [1 40; 1 40; 1 40], {'50', '0', 'NaN'});
        if isempty(answer), return; end
        gridSp = str2double(answer{1});
        thick  = str2double(answer{2});
        direct = str2double(answer{3});
        if isnan(gridSp), gridSp = 50; end
        try
            optArgs = struct('GridSpacing', gridSp, 'PixelSize', max(guiPixelSize(),1), ...
                             'PixelUnit', guiPixelUnit());
            if thick > 0, optArgs.FoilThickness = thick; end
            if ~isnan(direct), optArgs.Direction = direct; end
            result = imaging.countDefectLines(double(appData.filteredPixels), ...
                GridSpacing=gridSp, PixelSize=max(guiPixelSize(),1), ...
                PixelUnit=guiPixelUnit());
            msg = sprintf(['Defect Line Count\n\n' ...
                'Intersections: %d\nTest lines: %d\n' ...
                'Density: %.3g %s'], ...
                result.intersectionCount, result.numTestLines, ...
                result.density, result.densityUnit);
            uialert(fig, msg, 'Defect Count', 'Icon', 'info');
            setStatus(sprintf('Defect density: %.3g %s', result.density, result.densityUnit));
        catch ME
            setStatus(['Defect count error: ' ME.message]);
        end
    end

    % ── Feature 8: Back-Projection Preview ─────────────────────────────
    function onBackProject(~, ~)
        if isempty(appData.rawPixels), return; end
        if ~isfield(appData, 'images') || numel(appData.images) < 2
            uialert(fig, 'Load a tilt series (multi-frame) first.', 'Need stack'); return;
        end
        answer = inputdlg({'Tilt angles (comma-separated, deg):', 'Row index for sinogram:'}, ...
            'Back-Projection', [1 60; 1 40], ...
            {sprintf('%.0f,', linspace(-70, 70, numel(appData.images))), ...
             num2str(round(size(appData.images{1}, 1) / 2))});
        if isempty(answer), return; end
        try
            % Parse comma/space-separated angle list without eval. str2num
            % evaluates its input as MATLAB code and violates no-eval.md —
            % a user typing a function call or expression would execute.
            tokens = strtrim(strsplit(answer{1}, {',', ' '}));
            tokens = tokens(~cellfun('isempty', tokens));
            angles = str2double(tokens);
            if any(isnan(angles))
                error('Tilt-angle list contains one or more non-numeric entries.');
            end
            rowIdx = str2double(answer{2});
            if numel(angles) ~= numel(appData.images)
                error('Number of angles (%d) must match frames (%d).', ...
                    numel(angles), numel(appData.images));
            end
            % Build sinogram from the selected row
            nFrames = numel(appData.images);
            W = size(appData.images{1}, 2);
            sinogram = zeros(nFrames, W);
            for fi = 1:nFrames
                frame = double(appData.images{fi});
                sinogram(fi, :) = frame(min(rowIdx, size(frame,1)), :);
            end
            result = imaging.backProject(sinogram, Angles=angles(:));
            figBP = figure('Name', 'Back-Projection Preview', 'NumberTitle', 'off');
            subplot(1,2,1); imagesc(sinogram); axis tight;
            xlabel('Pixel'); ylabel('Angle index'); title('Sinogram');
            subplot(1,2,2); imagesc(result.reconstruction); axis equal tight;
            colormap gray; title('Reconstruction (preview)');
            setStatus('Back-projection preview computed.');
        catch ME
            setStatus(['Back-projection error: ' ME.message]);
        end
    end

    % ── Feature 2: Figure Panel Builder ────────────────────────────────
    function onFigureBuilder(~, ~)
        if isempty(appData.rawPixels), return; end
        nImg = numel(appData.images);
        if nImg < 1
            uialert(fig, 'Load at least one image.', 'No images'); return;
        end
        answer = inputdlg({'Rows:', 'Columns:', 'Gap (px):'}, ...
            'Figure Builder', [1 30; 1 30; 1 30], ...
            {num2str(ceil(sqrt(nImg))), num2str(ceil(nImg / ceil(sqrt(nImg)))), '2'});
        if isempty(answer), return; end
        try
            nRows = str2double(answer{1});
            nCols = str2double(answer{2});
            gap   = str2double(answer{3});
            imgs = appData.images(1:min(nImg, nRows*nCols));
            result = imaging.buildFigurePanel(imgs, Rows=nRows, Cols=nCols, Gap=gap);
            figPanel = figure('Name', 'Figure Panel', 'NumberTitle', 'off');
            image(result.composite); axis equal tight off;
            title(sprintf('%dx%d panel (%d images)', nRows, nCols, numel(imgs)));
            setStatus('Figure panel built.');
        catch ME
            setStatus(['Figure builder error: ' ME.message]);
        end
    end

    % ── Feature 15: Journal Export Presets ──────────────────────────────
    function onJournalExport(~, ~)
        if isempty(appData.rawPixels), return; end
        presets = { ...
            'Nature',      89,  300, 'tiff'; ...
            'Science',     85,  300, 'tiff'; ...
            'ACS',         84,  300, 'tiff'; ...
            'Elsevier',    90,  300, 'tiff'; ...
            'APS (PRL)',   86,  300, 'eps';  ...
            'Wiley',       85,  300, 'tiff'; ...
            'IUCr',        83,  600, 'tiff'; ...
            'Custom',      85,  300, 'tiff'};
        names = presets(:,1);
        [sel, ok] = listdlg('ListString', names, 'SelectionMode', 'single', ...
            'PromptString', 'Select journal preset:', 'ListSize', [250 200]);
        if ~ok, return; end
        widthMM = presets{sel, 2};
        dpi = presets{sel, 3};
        fmt = presets{sel, 4};
        if strcmp(names{sel}, 'Custom')
            ans2 = inputdlg({'Width (mm):', 'DPI:', 'Format (tiff/png/eps/pdf):'}, ...
                'Custom Export', [1 30; 1 30; 1 30], ...
                {num2str(widthMM), num2str(dpi), fmt});
            if isempty(ans2), return; end
            widthMM = str2double(ans2{1});
            dpi = str2double(ans2{2});
            fmt = strtrim(ans2{3});
        end
        widthPx = round(widthMM / 25.4 * dpi);
        try
            img = appData.filteredPixels;
            [H, W] = size(img, [1 2]);
            scale = widthPx / W;
            newH = round(H * scale);
            [Xq, Yq] = meshgrid(linspace(1, W, widthPx), linspace(1, H, newH));
            if ndims(img) == 3
                resized = zeros(newH, widthPx, 3, 'like', img);
                for ch = 1:3
                    resized(:,:,ch) = interp2(double(img(:,:,ch)), Xq, Yq, 'bilinear');
                end
            else
                resized = interp2(double(img), Xq, Yq, 'bilinear');
            end
            % Apply contrast
            dispImg = applyContrastPipeline(resized, sldLow.Value, sldHigh.Value);
            ext = ['.' fmt];
            [fname, fpath] = uiputfile({['*' ext], [upper(fmt) ' file']}, ...
                'Export for journal', ['figure' ext]);
            if isequal(fname, 0), return; end
            outPath = fullfile(fpath, fname);
            if ismember(fmt, {'tiff', 'tif'})
                imwrite(uint8(dispImg * 255), outPath, 'tiff', 'Compression', 'lzw', ...
                    'Resolution', dpi);
            elseif strcmp(fmt, 'png')
                imwrite(uint8(dispImg * 255), outPath, 'png');
            else
                % Vector formats: use saveFigure if available
                tmpFig = figure('Visible', 'off');
                imshow(dispImg, 'Parent', axes(tmpFig));
                print(tmpFig, outPath, ['-d' fmt], ['-r' num2str(dpi)]);
                close(tmpFig);
            end
            setStatus(sprintf('Exported %dx%d px @ %d dpi → %s', widthPx, newH, dpi, fname));
        catch ME
            setStatus(['Journal export error: ' ME.message]);
        end
    end

    % ── Feature 14: Calibrated Colorbar ────────────────────────────────
    function onCalibratedColorbar(~, ~)
        if isempty(appData.rawPixels), return; end
        answer = inputdlg({'Min value:', 'Max value:', 'Unit label:'}, ...
            'Calibrated Colorbar', [1 30; 1 30; 1 30], ...
            {num2str(min(appData.filteredPixels(:))), ...
             num2str(max(appData.filteredPixels(:))), 'counts'});
        if isempty(answer), return; end
        try
            minVal = str2double(answer{1});
            maxVal = str2double(answer{2});
            unitLabel = answer{3};
            cmap = feval(ddColormap.Value, 256);
            [H, W] = size(appData.filteredPixels);
            result = imaging.addColorbar([H, W], Colormap=cmap, ...
                Range=[minVal, maxVal], Unit=unitLabel);
            % Overlay on axes using MATLAB colorbar with custom tick labels
            if ~isempty(ax) && isvalid(ax)
                ax.CLim = [0 1];
                cb = colorbar(ax, 'Location', 'eastoutside');
                nTicks = numel(result.labelStrings);
                cb.Ticks = linspace(0, 1, nTicks);
                cb.TickLabels = result.labelStrings;
                cb.Label.String = unitLabel;
                appData.calibColorbar = cb;
            end
            setStatus(sprintf('Colorbar: %.3g to %.3g %s', minVal, maxVal, unitLabel));
        catch ME
            setStatus(['Colorbar error: ' ME.message]);
        end
    end

    % ── Feature 10: Macro Recorder ─────────────────────────────────────
    function onMacroToggle(~, ~)
        if ~isfield(appData, 'isRecording'), appData.isRecording = false; end
        if ~appData.isRecording
            % Start recording
            appData.isRecording = true;
            appData.macroRecording = {};
            btnMacroRecord.Text = 'Stop Recording';
            btnMacroRecord.BackgroundColor = [0.7 0.15 0.15];
            setStatus('Macro recording started. Perform measurements, then click Stop.');
        else
            % Stop recording
            appData.isRecording = false;
            btnMacroRecord.Text = 'Record Macro';
            btnMacroRecord.BackgroundColor = BTN_TOOL;
            nCmds = numel(appData.macroRecording);
            if nCmds == 0
                setStatus('Macro: no commands recorded.');
                return;
            end
            % Save macro
            [fname, fpath] = uiputfile({'*.mat', 'MATLAB macro (*.mat)'}, ...
                'Save Macro', 'macro.mat');
            if ~isequal(fname, 0)
                macroData = appData.macroRecording; %#ok<NASGU>
                save(fullfile(fpath, fname), 'macroData');
                setStatus(sprintf('Macro saved: %d commands → %s', nCmds, fname));
            else
                setStatus(sprintf('Macro: %d commands recorded (not saved).', nCmds));
            end
        end
    end

    % ── Feature 18: Flicker Compare ────────────────────────────────────
    function onFlickerCompare(~, ~)
        if ~isfield(appData, 'images') || numel(appData.images) < 2
            uialert(fig, 'Load at least 2 images.', 'Need 2+ images'); return;
        end
        if isfield(appData, 'flickerTimer') && ~isempty(appData.flickerTimer) ...
                && isvalid(appData.flickerTimer)
            stop(appData.flickerTimer);
            delete(appData.flickerTimer);
            appData.flickerTimer = [];
            btnFlickerCompare.Text = 'Flicker...';
            setStatus('Flicker mode stopped.');
            return;
        end
        answer = inputdlg({'Flicker rate (Hz):', 'Image A index:', 'Image B index:'}, ...
            'Flicker Compare', [1 30; 1 30; 1 30], ...
            {'2', '1', num2str(min(2, numel(appData.images)))});
        if isempty(answer), return; end
        rate = str2double(answer{1});
        idxA = str2double(answer{2});
        idxB = str2double(answer{3});
        if any(isnan([rate, idxA, idxB])), return; end
        rate = max(0.5, min(rate, 10));
        imgA = appData.images{idxA};
        imgB = appData.images{idxB};
        % Resize B to match A if needed
        [HA, WA] = size(imgA, [1 2]);
        [HB, WB] = size(imgB, [1 2]);
        if HA ~= HB || WA ~= WB
            [Xq, Yq] = meshgrid(linspace(1, WB, WA), linspace(1, HB, HA));
            imgB = interp2(double(imgB), Xq, Yq, 'nearest');
        end
        flickerState = struct('imgA', imgA, 'imgB', imgB, 'showA', true);
        appData.flickerState = flickerState;
        t = timer('ExecutionMode', 'fixedRate', 'Period', 1/rate, ...
            'TimerFcn', @(~,~) flickerTick());
        appData.flickerTimer = t;
        start(t);
        btnFlickerCompare.Text = 'Stop Flicker';
        setStatus(sprintf('Flicker: %.1f Hz between images %d and %d', rate, idxA, idxB));
    end

    function flickerTick()
        if ~isfield(appData, 'flickerState'), return; end
        try
            fs = appData.flickerState;
            if fs.showA
                appData.filteredPixels = fs.imgA;
            else
                appData.filteredPixels = fs.imgB;
            end
            appData.flickerState.showA = ~fs.showA;
            displayImage();
        catch
            % Timer may fire after GUI closes
        end
    end

    % ── Feature 7: Rich Text Labels (extends annotation) ──────────────
    % Rich text is handled by extending the existing annotation system:
    % the spnAnnotFont already exists, and MATLAB's text() with 'tex'
    % interpreter handles subscripts. This feature is active by default
    % when the annotation section uses TeX — no additional callback needed.

    % ── Feature 12: Synced Annotations in Compare Mode ─────────────────
    % Sync is handled inside the existing compare-mode measurement
    % callbacks. When appData.syncAnnotations is true, measurements are
    % mirrored to both axes. Toggle is in the compare mode panel.

    % ── Feature 16: Image Notes ────────────────────────────────────────
    % Notes are stored in appData.datasets{i}.notes if a notes textarea
    % is added below the image list. For now, notes are stored in the
    % session save/load pipeline — the textarea is added in a future
    % layout pass.

    % ── Feature 17: Quick Crop to ROI ──────────────────────────────────
    % Crop to ROI is handled after any ROI measurement. The bounding box
    % from the last ROI is used for cropping. Uses existing crop logic.

    % ── Feature 19: Measurement Overlay Toggle ─────────────────────────
    % Overlay visibility toggling uses the existing HandleVisibility
    % mechanism. A master toggle sets Visible on/off for all measurement
    % overlay handles.

    % ── Feature 20: Right-Click Context Menu ───────────────────────────
    function buildContextMenu()
        if isempty(ax) || ~isvalid(ax), return; end
        cm = uicontextmenu(fig);
        uimenu(cm, 'Text', 'Auto Contrast', 'MenuSelectedFcn', @(~,~) onAutoContrast());
        uimenu(cm, 'Text', 'Copy to Clipboard', 'MenuSelectedFcn', @(~,~) onCopyClipboard([], []));
        uimenu(cm, 'Text', 'Save Image...', 'MenuSelectedFcn', @(~,~) onSaveImage([], []));
        uimenu(cm, 'Text', 'Measure Distance', 'Separator', 'on', ...
            'MenuSelectedFcn', @(~,~) onArmDistance([], []));
        uimenu(cm, 'Text', 'Line Profile', 'MenuSelectedFcn', @(~,~) onArmLineProfile([], []));
        uimenu(cm, 'Text', 'ROI Statistics', 'MenuSelectedFcn', @(~,~) onArmROIStats([], []));
        uimenu(cm, 'Text', 'Zoom to Fit', 'Separator', 'on', ...
            'MenuSelectedFcn', @(~,~) onResetZoom([], []));
        uimenu(cm, 'Text', 'Refresh State (F5)', 'Separator', 'on', ...
            'MenuSelectedFcn', @(~,~) refreshState());
        ax.ContextMenu = cm;
    end

    function refreshState()
    %REFRESHSTATE  Flush caches and re-sync display without losing data.
    %  Bound to F5.  Clears stale display state, persistent caches, and
    %  forces a full image redraw — without destroying loaded images.
        % Clear persistent caches in calc modules
        clear calc.constants;
        clear calc.elementData;
        clear calc.unitConvert;
        clear calc.crystalCache;

        % Cancel any in-progress capture
        if ~isempty(appData.captureMode)
            cancelCapture();
        end

        % Re-display current image
        if appData.activeIdx > 0 && ~isempty(appData.rawPixels)
            displayImage();
        end

        setStatus('State refreshed.');
    end

    % ════════════════════════════════════════════════════════════════════
    %  EELS CALLBACKS
    % ════════════════════════════════════════════════════════════════════

    function onEnterEELS(~, ~)
    %ONENTEREELS  Enter EELS spectrum analysis mode.
        if isempty(appData.images), return; end

        % Exit other exclusive modes first
        if appData.edsMode
            onExitEDS();
        end
        if appData.compareMode
            exitCompareMode();
        end

        if ~appData.eelsMode
            appData.eelsMode = true;
            btnEnterEELS.Text = 'Exit EELS';
            btnEnterEELS.BackgroundColor = BTN_DANGER;

            % Try to load spectrum data from current image metadata
            idx = appData.activeIdx;
            if idx > 0 && idx <= numel(appData.images)
                ps = appData.images{idx}.metadata.parserSpecific;
                if isfield(ps, 'spectrumData')
                    appData.eelsData = ps.spectrumData;
                    appData.eelsEnergyAxis = ps.spectrumData.energyAxis;
                    if isfield(ps, 'spectrumImage')
                        appData.eelsCube = ps.spectrumImage.cube;
                    end
                end
            end

            if ~isempty(appData.eelsData)
                showEELSSpectrum();
            end

            setStatus('EELS mode active');
        else
            onExitEELS();
        end
    end

    function onExitEELS()
    %ONEXITEELS  Exit EELS mode and clean up.
        appData.eelsMode       = false;
        appData.eelsData       = [];
        appData.eelsCube       = [];
        appData.eelsEnergyAxis = [];
        btnEnterEELS.Text = 'Enter EELS';
        btnEnterEELS.BackgroundColor = BTN_PRIMARY;

        if ~isempty(appData.eelsFig) && isvalid(appData.eelsFig)
            close(appData.eelsFig);
        end
        appData.eelsFig = [];

        displayImage();
        setStatus('');
    end

    function showEELSSpectrum()
    %SHOWEELSSPECTRUM  Open or refresh the EELS spectrum figure.
        if isempty(appData.eelsData), return; end

        E = appData.eelsData.energyAxis;
        I = double(appData.eelsData.counts);

        if isempty(appData.eelsFig) || ~isvalid(appData.eelsFig)
            appData.eelsFig = uifigure('Name', 'EELS Spectrum', ...
                'Position', [100 100 700 400]);
            eelsAx = uiaxes(appData.eelsFig, ...
                'Position', [60 50 600 320]);
        else
            figure(appData.eelsFig);
            eelsAx = findobj(appData.eelsFig, 'Type', 'axes');
            if isempty(eelsAx)
                eelsAx = uiaxes(appData.eelsFig, 'Position', [60 50 600 320]);
            end
            eelsAx = eelsAx(1);
        end

        cla(eelsAx);
        plot(eelsAx, E, I, 'k-', 'LineWidth', 1);
        xlabel(eelsAx, 'Energy Loss (eV)');
        ylabel(eelsAx, 'Counts');
        title(eelsAx, 'EELS Spectrum');
        grid(eelsAx, 'on');
    end

    function onEELSFitBackground(~, ~)
    %ONEELSFITBACKGROUND  Fit and subtract pre-edge background.
        if isempty(appData.eelsData), return; end

        E = appData.eelsData.energyAxis;
        I = double(appData.eelsData.counts);

        E1 = str2double(edtEELSPreEdgeStart.Value);
        E2 = str2double(edtEELSPreEdgeEnd.Value);
        if isnan(E1) || isnan(E2) || E1 >= E2
            setStatus('Invalid pre-edge window');
            return;
        end

        method = ddEELSMethod.Value;

        try
            [signal, bg, params] = imaging.eelsBackground(E, I, ...
                'FitWindow', [E1 E2], 'Method', method);
        catch ME
            setStatus(['EELS background error: ' ME.message]);
            return;
        end

        % Update spectrum plot
        if ~isempty(appData.eelsFig) && isvalid(appData.eelsFig)
            eelsAx = findobj(appData.eelsFig, 'Type', 'axes');
            if ~isempty(eelsAx)
                eelsAx = eelsAx(1);
                cla(eelsAx);
                hold(eelsAx, 'on');
                plot(eelsAx, E, I, 'k-', 'LineWidth', 0.5, 'DisplayName', 'Raw');
                plot(eelsAx, E, bg, 'r--', 'LineWidth', 1, 'DisplayName', 'Background');
                plot(eelsAx, E, max(signal, 0), 'b-', 'LineWidth', 1, 'DisplayName', 'Signal');
                hold(eelsAx, 'off');
                legend(eelsAx, 'show');
                if strcmp(method, 'powerlaw') && isstruct(params) && isfield(params, 'A')
                    title(eelsAx, sprintf('BG: A=%.2g, r=%.3f', params.A, params.r));
                end
            end
        end

        setStatus(sprintf('Background fit: %s', method));
    end

    function onEELSShowEdges(~, ~)
    %ONEELSSHOWEDEGS  Toggle reference edge markers on the EELS spectrum.
        if isempty(appData.eelsFig) || ~isvalid(appData.eelsFig), return; end

        eelsAx = findobj(appData.eelsFig, 'Type', 'axes');
        if isempty(eelsAx), return; end
        eelsAx = eelsAx(1);

        % Remove existing edge markers
        delete(findobj(eelsAx, 'Tag', 'eels_edge'));

        if ~chkShowEdges.Value, return; end

        try
            edges = imaging.eelsEdgeTable();
        catch
            setStatus('imaging.eelsEdgeTable not available');
            return;
        end

        % Filter by selected element if not 'All'
        filterElem = ddEdgeFilter.Value;
        if ~strcmp(filterElem, 'All') && ~isempty(edges)
            mask = strcmp({edges.element}, filterElem);
            edges = edges(mask);
        end

        hold(eelsAx, 'on');
        for k = 1:numel(edges)
            xline(eelsAx, edges(k).onsetEV, ':', 'Color', [0.8 0 0], ...
                'LineWidth', 0.8, 'Tag', 'eels_edge', ...
                'Label', edges(k).symbol, 'LabelVerticalAlignment', 'bottom');
        end
        hold(eelsAx, 'off');
    end

    function onEELSExtractMap(~, ~)
    %ONEELSEXTRACTMAP  Extract a net-signal elemental map from spectrum image cube.
        if isempty(appData.eelsCube)
            setStatus('No spectrum image loaded');
            return;
        end

        E1 = str2double(edtEELSSignalStart.Value);
        E2 = str2double(edtEELSSignalEnd.Value);
        if isnan(E1) || isnan(E2)
            setStatus('Invalid signal window');
            return;
        end

        bgE1 = str2double(edtEELSPreEdgeStart.Value);
        bgE2 = str2double(edtEELSPreEdgeEnd.Value);
        if ~isnan(bgE1) && ~isnan(bgE2) && bgE1 < bgE2
            bgWin = [bgE1 bgE2];
        else
            bgWin = [];
        end

        try
            map = imaging.eelsExtractMap(appData.eelsCube, appData.eelsEnergyAxis, ...
                [E1 E2], 'BackgroundWindow', bgWin);
        catch ME
            setStatus(['EELS extract error: ' ME.message]);
            return;
        end

        % Display map on main axes
        cla(ax);
        imagesc(ax, map);
        colorbar(ax);
        colormap(ax, 'hot');
        title(ax, sprintf('EELS Map: %.0f-%.0f eV', E1, E2));
        axis(ax, 'image');

        setStatus(sprintf('Extracted map: %.0f-%.0f eV', E1, E2));
    end

    function onEELSThicknessMap(~, ~)
    %ONEELSTHICKNESSMAP  Compute t/lambda thickness map via log-ratio method.
        if isempty(appData.eelsCube)
            setStatus('No spectrum image loaded');
            return;
        end

        try
            [tMap, mask] = imaging.eelsThicknessMap(appData.eelsCube, appData.eelsEnergyAxis);
        catch ME
            setStatus(['Thickness map error: ' ME.message]);
            return;
        end

        cla(ax);
        imagesc(ax, tMap);
        colorbar(ax);
        colormap(ax, 'parula');
        title(ax, 't/\lambda thickness map');
        axis(ax, 'image');

        validVals = tMap(mask);
        setStatus(sprintf('Thickness map: mean t/lambda=%.2f', mean(validVals)));
    end

    function onEELSAlignZLP(~, ~)
    %ONEELSALIGNZLP  Align zero-loss peak across all frames of spectrum image.
        if isempty(appData.eelsCube)
            setStatus('No spectrum image loaded');
            return;
        end

        try
            [appData.eelsCube, shifts] = imaging.eelsAlignZLP( ...
                appData.eelsCube, appData.eelsEnergyAxis);
        catch ME
            setStatus(['ZLP alignment error: ' ME.message]);
            return;
        end

        % Rebuild sum spectrum
        appData.eelsData.counts = squeeze(sum(sum(double(appData.eelsCube), 1), 2));
        showEELSSpectrum();

        setStatus(sprintf('ZLP aligned: max shift=%.0f channels', max(abs(shifts(:)))));
    end

    % API helpers for EELS
    function eelsBackgroundAPI(fitWin)
    %EELSBACKGROUNDAPI  Programmatic EELS background fitting.
        edtEELSPreEdgeStart.Value = num2str(fitWin(1));
        edtEELSPreEdgeEnd.Value   = num2str(fitWin(2));
        onEELSFitBackground([], []);
    end

    function eelsExtractMapAPI(sigWin, bgWin)
    %EELSEXTRACTMAPAPI  Programmatic EELS map extraction.
        edtEELSSignalStart.Value = num2str(sigWin(1));
        edtEELSSignalEnd.Value   = num2str(sigWin(2));
        if nargin >= 2 && ~isempty(bgWin)
            edtEELSPreEdgeStart.Value = num2str(bgWin(1));
            edtEELSPreEdgeEnd.Value   = num2str(bgWin(2));
        end
        onEELSExtractMap([], []);
    end

    % ════════════════════════════════════════════════════════════════════
    %  EELS ADVANCED CALLBACKS (Deconvolve / ELNES / KK / Pixel Nav)
    % ════════════════════════════════════════════════════════════════════

    function onEELSDeconvolve(~, ~)
    %ONEELSDECONVOLVE  Fourier-log plural scattering removal.
        if isempty(appData.eelsData), return; end
        E = appData.eelsData.energyAxis;
        I = double(appData.eelsData.counts);
        try
            [ssd, tl] = imaging.eelsFourierLog(E, I);
            appData.eelsSSD = ssd;
            if ~isempty(appData.eelsFig) && isvalid(appData.eelsFig)
                ax2 = findobj(appData.eelsFig, 'Type', 'axes');
                if ~isempty(ax2)
                    hold(ax2(1), 'on');
                    plot(ax2(1), E, ssd, 'm-', 'LineWidth', 1.2, 'DisplayName', 'SSD');
                    hold(ax2(1), 'off');
                    legend(ax2(1), 'show');
                end
            end
            setStatus(sprintf('Deconvolved: t/lambda=%.2f', tl));
        catch ME
            setStatus(sprintf('Deconvolution failed: %s', ME.message));
        end
    end

    function onEELSExtractELNES(~, ~)
    %ONEELSEXTRACTELNES  Extract near-edge fine structure (ELNES).
        if isempty(appData.eelsData), return; end
        onset = str2double(edtEELSEdgeOnset.Value);
        if isnan(onset), setStatus('Invalid edge onset'); return; end
        E = appData.eelsData.energyAxis;
        I = double(appData.eelsData.counts);
        if ~isempty(appData.eelsSSD), I = appData.eelsSSD; end
        E1 = str2double(edtEELSPreEdgeStart.Value);
        E2 = str2double(edtEELSPreEdgeEnd.Value);
        if isnan(E1) || isnan(E2), setStatus('Set pre-edge window first'); return; end
        try
            res = imaging.eelsELNES(E, I, 'EdgeOnset', onset, 'FitWindow', [E1 E2]);
            eFig = figure('Name', 'ELNES');
            plot(res.relativeEnergy, res.intensity, 'b-', 'LineWidth', 1.5);
            xlabel('Energy relative to onset (eV)'); ylabel('Normalized intensity');
            title(sprintf('ELNES at %.0f eV (jump=%.1f)', onset, res.edgeJump));
            grid on;
            setStatus(sprintf('ELNES extracted: onset=%.0f eV', onset));
        catch ME
            setStatus(sprintf('ELNES failed: %s', ME.message));
        end
    end

    function onEELSKramersKronig(~, ~)
    %ONEELSKRAMERSKRONIG  Compute dielectric function from low-loss EELS via KK analysis.
        if isempty(appData.eelsData), return; end
        E = appData.eelsData.energyAxis;
        I = double(appData.eelsData.counts);
        try
            res = imaging.eelsKramersKronig(E, I);
            appData.eelsKKResult = res;
            kkFig = figure('Name', 'Kramers-Kronig Analysis');
            subplot(2,1,1);
            plot(res.energy, res.eps1, 'b-', res.energy, res.eps2, 'r-', 'LineWidth', 1.2);
            xlabel('Energy (eV)'); ylabel('\epsilon');
            legend('\epsilon_1 (real)', '\epsilon_2 (imag)'); grid on;
            title('Dielectric function');
            subplot(2,1,2);
            plot(res.energy, res.opticalConductivity, 'k-', 'LineWidth', 1.2);
            xlabel('Energy (eV)'); ylabel('\sigma_1 (S/m)');
            title('Optical conductivity'); grid on;
            setStatus('Kramers-Kronig analysis complete');
        catch ME
            setStatus(sprintf('KK failed: %s', ME.message));
        end
    end

    function onEELSSVD(~, ~)
    %ONEELSSVD  SVD / MSA decomposition of the EELS spectrum image cube.
    %   Opens a results figure with scree plot, eigenspectra, and score maps.
    %   Optionally replaces the cube with a denoised reconstruction.
        if isempty(appData.eelsCube)
            setStatus('No spectrum image loaded'); return;
        end
        E = appData.eelsEnergyAxis;
        [Ny, Nx, nE] = size(appData.eelsCube);
        nPix = Ny * Nx;
        kDefault = min(10, min(nPix, nE));

        setStatus('Running SVD decomposition...');
        fig.Pointer = 'watch'; drawnow;
        try
            res = imaging.eelsSVD(appData.eelsCube, E, NumComponents=kDefault);
        catch ME
            fig.Pointer = 'arrow';
            setStatus(sprintf('SVD failed: %s', ME.message));
            return;
        end
        fig.Pointer = 'arrow';

        appData.eelsSVDResult = res;

        % ── Build results figure ──────────────────────────────────────────
        nShow = min(4, kDefault);  % show top 4 components
        svdFig = figure('Name', 'EELS SVD Decomposition', ...
            'NumberTitle', 'off', 'Color', [0.12 0.12 0.14], ...
            'Position', [100 100 900 700]);

        % Row 1: scree plot (left) + cumulative (right)
        axScree = subplot(nShow+1, 2, 1, 'Parent', svdFig);
        bar(axScree, res.explained(1:kDefault), 'FaceColor', [0.30 0.55 0.85]);
        xlabel(axScree, 'Component'); ylabel(axScree, 'Variance (%)');
        title(axScree, 'Scree Plot');
        axScree.Color = [0.18 0.18 0.20]; axScree.XColor = 'w'; axScree.YColor = 'w';
        axScree.Title.Color = 'w';

        axCum = subplot(nShow+1, 2, 2, 'Parent', svdFig);
        plot(axCum, 1:kDefault, res.cumulative(1:kDefault), 'o-', ...
            'Color', [0.85 0.35 0.15], 'LineWidth', 1.5, 'MarkerFaceColor', [0.85 0.35 0.15]);
        xlabel(axCum, 'Components'); ylabel(axCum, 'Cumulative (%)');
        title(axCum, 'Cumulative Variance');
        axCum.Color = [0.18 0.18 0.20]; axCum.XColor = 'w'; axCum.YColor = 'w';
        axCum.Title.Color = 'w';
        ylim(axCum, [0 100]);

        % Rows 2+: eigenspectrum (left) + score map (right)
        cmpColors = lines(nShow);
        for ci = 1:nShow
            axSpec = subplot(nShow+1, 2, 2*ci+1, 'Parent', svdFig);
            plot(axSpec, E, res.eigenspectra(:,ci), '-', ...
                'Color', cmpColors(ci,:), 'LineWidth', 1.2);
            xlabel(axSpec, 'Energy (eV)'); ylabel(axSpec, 'Weight');
            title(axSpec, sprintf('Eigenspectrum %d  (%.1f%%)', ci, res.explained(ci)));
            axSpec.Color = [0.18 0.18 0.20]; axSpec.XColor = 'w'; axSpec.YColor = 'w';
            axSpec.Title.Color = 'w';

            axMap = subplot(nShow+1, 2, 2*ci+2, 'Parent', svdFig);
            imagesc(axMap, res.scoreMaps(:,:,ci));
            axis(axMap, 'image'); colorbar(axMap);
            title(axMap, sprintf('Score Map %d', ci));
            axMap.Color = [0.18 0.18 0.20]; axMap.XColor = 'w'; axMap.YColor = 'w';
            axMap.Title.Color = 'w';
            colormap(axMap, 'parula');
        end

        % ── Offer to denoise ──────────────────────────────────────────────
        % Find the knee: first k where cumulative > 95%, or prompt user
        kneeK = find(res.cumulative >= 95, 1);
        if isempty(kneeK), kneeK = kDefault; end

        sel = uiconfirm(fig, ...
            sprintf(['SVD complete: top %d components explain %.1f%% of variance.\n\n' ...
                     'Denoise the spectrum image using the top %d components?\n' ...
                     '(This replaces the current EELS cube — undo via reload)'], ...
                kDefault, res.cumulative(end), kneeK), ...
            'SVD Denoise', ...
            'Options', {'Denoise', 'Skip'}, ...
            'DefaultOption', 2, 'CancelOption', 2);

        if strcmp(sel, 'Denoise')
            setStatus(sprintf('Denoising with %d components...', kneeK));
            fig.Pointer = 'watch'; drawnow;
            resDenoise = imaging.eelsSVD(appData.eelsCube, E, ...
                NumComponents=kneeK, Denoise=true);
            appData.eelsCube = resDenoise.denoisedCube;
            % Update summed spectrum
            appData.eelsData.counts = squeeze(sum(sum(double(appData.eelsCube), 1), 2));
            if ~isempty(appData.eelsFig) && isvalid(appData.eelsFig)
                ax2 = findobj(appData.eelsFig, 'Type', 'axes');
                if ~isempty(ax2)
                    cla(ax2(1));
                    plot(ax2(1), E, appData.eelsData.counts, 'k-', 'LineWidth', 1);
                    xlabel(ax2(1), 'Energy Loss (eV)'); ylabel(ax2(1), 'Counts');
                    title(ax2(1), 'EELS Spectrum (SVD denoised)');
                end
            end
            fig.Pointer = 'arrow';
            setStatus(sprintf('Denoised with %d components (%.1f%% variance)', ...
                kneeK, resDenoise.cumulative(end)));
        else
            setStatus(sprintf('SVD: %d components, top explains %.1f%%', ...
                kDefault, res.explained(1)));
        end
    end

    function onEELSNavigateToggle(src, ~)
    %ONEELSNAVIGATETOGGLE  Toggle pixel-spectrum navigator mode.
        if src.Value
            if isempty(appData.eelsCube)
                setStatus('No spectrum image loaded');
                src.Value = false;
                return;
            end
            appData.captureMode = 'specnav';
            fig.WindowButtonDownFcn = @onCaptureClick;
            fig.Pointer = 'crosshair';
            setStatus('Click on image to show pixel spectrum');
        else
            appData.captureMode = '';
            fig.WindowButtonDownFcn = @onIdleMouseDown;
            fig.Pointer = 'arrow';
            delete(findobj(ax, 'Tag', 'specnav_marker'));
            setStatus('');
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  DIFFRACTION INDEXING CALLBACKS
    % ════════════════════════════════════════════════════════════════════

    function onAutoDetectSpots(~, ~)
    %ONAUTODETECTSPOTS  Automatically find diffraction spots.
        if isempty(appData.images), return; end

        idx = appData.activeIdx;
        if idx < 1, return; end
        pixels = double(appData.images{idx}.metadata.parserSpecific.imageData.pixels);

        try
            spots = imaging.findDiffractionSpots(pixels);
        catch ME
            setStatus(['Spot detection error: ' ME.message]);
            return;
        end

        appData.diffSpots = spots;
        drawDiffSpots();
        lblSpotCount.Text = sprintf('%d spots', size(spots, 1));
        setStatus(sprintf('Found %d diffraction spots', size(spots, 1)));
    end

    function onClickDiffSpot(~, ~)
    %ONCLICKDIFFSPOT  Enable manual click-to-add diffraction spots.
        if isempty(appData.images), return; end
        appData.captureMode   = 'diffspot';
        appData.captureClicks = [];
        fig.WindowButtonDownFcn = @onCaptureClick;
        fig.Pointer = 'crosshair';
        setStatus('Click to mark diffraction spots; press Escape when done');
    end

    function onClearDiffSpots(~, ~)
    %ONCLEARDIFFSPOTS  Remove all diffraction spot markers and results.
        appData.diffSpots   = [];
        appData.diffResults = [];
        delete(findobj(ax, 'Tag', 'diff_spot'));
        delete(findobj(ax, 'Tag', 'diff_ring'));
        lblSpotCount.Text = '0 spots';
        lblZoneAxis.Text  = '';
        lbxDiffResults.Items = {};
        setStatus('Spots cleared');
    end

    function drawDiffSpots()
    %DRAWDIFFSPOTS  Render current diffraction spot markers on main axes.
        delete(findobj(ax, 'Tag', 'diff_spot'));
        if isempty(appData.diffSpots), return; end
        hold(ax, 'on');
        plot(ax, appData.diffSpots(:,2), appData.diffSpots(:,1), ...
            'ro', 'MarkerSize', 10, 'LineWidth', 1.5, 'Tag', 'diff_spot', ...
            'HandleVisibility', 'off');
        hold(ax, 'off');
    end

    function onMatchDiffraction(~, ~)
    %ONMATCHDIFFRACTION  Index diffraction pattern and match to crystal phases.
        if isempty(appData.diffSpots) || size(appData.diffSpots, 1) < 2
            setStatus('Need at least 2 spots to index');
            return;
        end

        idx = appData.activeIdx;
        if idx < 1, return; end
        imgData = appData.images{idx}.metadata.parserSpecific.imageData;
        imgSz   = [size(imgData.pixels, 1), size(imgData.pixels, 2)];

        camLen = str2double(edtCameraLen.Value);
        if isnan(camLen), camLen = NaN; end

        kVstr = ddAccVoltage.Value;
        kV    = str2double(regexp(kVstr, '\d+', 'match', 'once'));

        pxSz  = 1;
        pxUnit = 'px';
        if imgData.calibrated
            pxSz   = imgData.pixelSize;
            pxUnit = imgData.pixelUnit;
        end

        try
            result = imaging.indexDiffraction(appData.diffSpots, imgSz, ...
                'PixelSize', pxSz, 'PixelUnit', pxUnit, ...
                'CameraLength', camLen, 'AccVoltage', kV);
        catch ME
            setStatus(['Indexing error: ' ME.message]);
            return;
        end

        appData.diffResults = result;

        % Populate results listbox
        items = {};
        for k = 1:numel(result.candidates)
            c = result.candidates(k);
            items{end+1} = sprintf('%s (%s) — %d/%d matched, score=%.2f', ...  %#ok<AGROW>
                c.phaseName, c.formula, c.nMatched, c.nSpots, c.score);
        end
        lbxDiffResults.Items = items;
        if ~isempty(items)
            lbxDiffResults.Value = items{1};
        end

        % Zone axis for top candidate
        if ~isempty(result.candidates) && ~any(isnan(result.candidates(1).zoneAxis))
            za = result.candidates(1).zoneAxis;
            lblZoneAxis.Text = sprintf('[%d %d %d]', za(1), za(2), za(3));
        else
            lblZoneAxis.Text = 'N/A';
        end

        setStatus(sprintf('Indexed: top=%s (score=%.2f)', ...
            result.candidates(1).phaseName, result.candidates(1).score));
    end

    function onOverlayDiffRings(~, ~)
    %ONOVERLAYDFFRINGS  Draw d-spacing rings for the selected diffraction phase.
        if isempty(appData.diffResults), return; end

        delete(findobj(ax, 'Tag', 'diff_ring'));

        selVal = lbxDiffResults.Value;
        if isempty(selVal), return; end
        selIdx = find(strcmp(lbxDiffResults.Items, selVal), 1);
        if isempty(selIdx), selIdx = 1; end

        if selIdx > numel(appData.diffResults.candidates), return; end
        cand   = appData.diffResults.candidates(selIdx);
        center = appData.diffResults.center;

        theta = linspace(0, 2*pi, 100);
        hold(ax, 'on');
        for k = 1:numel(cand.matchedD)
            R  = appData.diffResults.measuredR(k);
            cx = center(2) + R * cos(theta);
            cy = center(1) + R * sin(theta);
            plot(ax, cx, cy, 'g-', 'LineWidth', 0.8, 'Tag', 'diff_ring', ...
                'HandleVisibility', 'off');
            if ~isempty(cand.matchedHKL) && size(cand.matchedHKL, 1) >= k
                hkl = cand.matchedHKL(k,:);
                text(ax, center(2) + R*1.05, center(1), ...
                    sprintf('(%d%d%d)', hkl(1), hkl(2), hkl(3)), ...
                    'Color', 'g', 'FontSize', 9, 'Tag', 'diff_ring');
            end
        end
        hold(ax, 'off');
    end

    function onSimulateDiffraction(~, ~)
    %ONSIMULATEDDIFFRACTION  Kinematic diffraction simulation for matched phase.
        if isempty(appData.diffResults) || isempty(appData.diffResults.candidates)
            setStatus('Match phases first');
            return;
        end
        phaseName = appData.diffResults.candidates(1).phaseName;
        zaStr = edtZoneAxis.Value;
        za = sscanf(zaStr, '%d %d %d', [1 3]);
        if numel(za) ~= 3, setStatus('Invalid zone axis'); return; end
        kVstr = ddAccVoltage.Value;
        kV = str2double(regexprep(kVstr, '[^0-9]', ''));
        camLen = str2double(edtCameraLen.Value);
        if isnan(camLen), camLen = 200; end
        try
            res = imaging.simulateDiffraction(phaseName, 'ZoneAxis', za, ...
                'AccVoltage', kV, 'CameraLength', camLen);
            simFig = figure('Name', sprintf('Simulated: %s [%d%d%d]', phaseName, za));
            imagesc(log10(res.image + 1)); colormap gray; axis image;
            title(sprintf('%s — [%d%d%d] zone axis', phaseName, za));
            setStatus(sprintf('Simulated %s [%d%d%d]: %d spots', phaseName, za, numel(res.spots)));
        catch ME
            setStatus(sprintf('Simulation failed: %s', ME.message));
        end
    end

    function onVirtualDarkField(~, ~)
    %ONVIRTUALDARKFIELD  Select an FFT spot for virtual dark-field imaging.
        if isempty(appData.images), return; end
        appData.captureMode = 'vdf_select';
        fig.WindowButtonDownFcn = @onCaptureClick;
        fig.Pointer = 'crosshair';
        setStatus('Click on FFT spot for virtual dark-field');
    end

    % ════════════════════════════════════════════════════════════════════
    %  EDS QUANTIFICATION CALLBACKS
    % ════════════════════════════════════════════════════════════════════

    function onAssignElements(~, ~)
    %ONASSIGNELEMENTS  Assign element symbols to loaded EDS channels.
        if ~appData.edsMode || isempty(appData.edsChannels), return; end

        nCh      = numel(appData.edsChannels);
        elements = cell(1, nCh);

        % Auto-detect element symbol from channel label (e.g. "Fe_Ka" → "Fe")
        for k = 1:nCh
            lbl = appData.edsChannels{k}.label;
            tok = regexp(lbl, '^([A-Z][a-z]?)', 'tokens', 'once');
            if ~isempty(tok)
                elements{k} = tok{1};
            else
                elements{k} = sprintf('El%d', k);
            end
        end

        % Ask user to confirm / override
        prompt   = cell(1, nCh);
        defaults = cell(1, nCh);
        for k = 1:nCh
            prompt{k}   = sprintf('Channel %d (%s):', k, appData.edsChannels{k}.label);
            defaults{k} = elements{k};
        end

        answer = inputdlg(prompt, 'Assign Elements', 1, defaults);
        if isempty(answer), return; end

        appData.edsElements = answer';
        setStatus(sprintf('Elements assigned: %s', strjoin(appData.edsElements, ', ')));
    end

    function onQuantifyCL(~, ~)
    %ONQUANTIFYCL  Quantify EDS composition using the Cliff-Lorimer method.
        if ~appData.edsMode || isempty(appData.edsChannels)
            return;
        end
        if isempty(appData.edsElements)
            setStatus('Assign elements first');
            return;
        end

        nCh  = numel(appData.edsChannels);
        maps = cell(1, nCh);
        for k = 1:nCh
            chIdx  = appData.edsChannels{k}.imageIdx;
            maps{k} = double(appData.images{chIdx}.metadata.parserSpecific.imageData.pixels);
        end

        try
            result = imaging.cliffLorimer(maps, appData.edsElements);
        catch ME
            setStatus(['Cliff-Lorimer error: ' ME.message]);
            return;
        end

        appData.edsAtomicPct  = result.atomicPctMaps;
        appData.edsWeightPct  = result.weightPctMaps;
        appData.edsQuantified = true;

        % Build summary status string
        msg = 'Composition (at%): ';
        for k = 1:nCh
            msg = [msg sprintf('%s=%.1f%% ', appData.edsElements{k}, result.meanAtomicPct(k))]; %#ok<AGROW>
        end
        setStatus(msg);
    end

    function onCompositionProfile(~, ~)
    %ONCOMPOSITIONPROFILE  Draw a line-scan composition profile from EDS quantification.
        if ~appData.edsQuantified
            setStatus('Run quantification first');
            return;
        end
        appData.captureMode   = 'edsprofile';
        appData.captureClicks = [];
        fig.WindowButtonDownFcn = @onCaptureClick;
        fig.Pointer = 'crosshair';
        setStatus('Click 2 points for composition profile (Escape to cancel)');
    end

    function onROIComposition(~, ~)
    %ONROICOMPOSITION  Compute mean composition in a rectangular ROI.
        if ~appData.edsQuantified
            setStatus('Run quantification first');
            return;
        end
        appData.captureMode   = 'edsroi';
        appData.captureClicks = [];
        fig.WindowButtonDownFcn = @onCaptureClick;
        fig.Pointer = 'crosshair';
        setStatus('Click 2 corners for ROI composition (Escape to cancel)');
    end

    % API helper for EDS element assignment
    function edsAssignAPI(elems)
    %EDSASSIGNAPI  Programmatically assign element symbols to EDS channels.
        appData.edsElements = elems;
    end

    function onQuantifyZAF(~, ~)
    %ONQUANTIFYZAF  ZAF-corrected EDS quantification for thick specimens.
        if ~appData.edsMode || isempty(appData.edsChannels), return; end
        if isempty(appData.edsElements), setStatus('Assign elements first'); return; end
        nCh = numel(appData.edsChannels);
        maps = cell(1, nCh);
        for k = 1:nCh
            chIdx = appData.edsChannels{k}.imageIdx;
            maps{k} = double(appData.images{chIdx}.metadata.parserSpecific.imageData.pixels);
        end
        thickness = str2double(edtEDSThickness.Value);
        takeoff   = str2double(edtEDSTakeOff.Value);
        if isnan(thickness), thickness = 100; end
        if isnan(takeoff),   takeoff   = 20;  end
        try
            result = imaging.zafCorrection(maps, appData.edsElements, ...
                'Thickness', thickness, 'TakeOffAngle', takeoff);
            appData.edsAtomicPct  = result.atomicPctMaps;
            appData.edsWeightPct  = result.weightPctMaps;
            appData.edsQuantified = true;
            msg = 'ZAF (at%): ';
            for k = 1:nCh
                msg = [msg sprintf('%s=%.1f%% ', appData.edsElements{k}, result.meanAtomicPct(k))]; %#ok<AGROW>
            end
            setStatus(msg);
        catch ME
            setStatus(sprintf('ZAF failed: %s', ME.message));
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  API HELPERS: Advanced EELS, Diffraction, ZAF
    % ════════════════════════════════════════════════════════════════════

    function eelsELNESAPI(onset)
    %EELSELNESAPI  Programmatic ELNES extraction at given onset energy.
        edtEELSEdgeOnset.Value = num2str(onset);
        onEELSExtractELNES([], []);
    end

    function eelsNavigateAPI(row, col)
    %EELSNAVIGATEAPI  Programmatic spectrum navigation to pixel [row, col].
        if isempty(appData.eelsCube), return; end
        [Ny, Nx, ~] = size(appData.eelsCube);
        if row >= 1 && row <= Ny && col >= 1 && col <= Nx
            spec = squeeze(double(appData.eelsCube(row, col, :)));
            showEELSSpectrum();
            ax2 = findobj(appData.eelsFig, 'Type', 'axes');
            if ~isempty(ax2)
                cla(ax2(1));
                plot(ax2(1), appData.eelsEnergyAxis, spec, 'k-', 'LineWidth', 1);
                title(ax2(1), sprintf('Pixel [%d, %d]', row, col));
            end
        end
    end

    function res = eelsSVDAPI(nComp)
    %EELSSVDAPI  Programmatic SVD decomposition of the EELS cube.
        if isempty(appData.eelsCube)
            res = []; return;
        end
        res = imaging.eelsSVD(appData.eelsCube, appData.eelsEnergyAxis, ...
            NumComponents=nComp);
        appData.eelsSVDResult = res;
    end

    function simDiffAPI(phase, za)
    %SIMDIFFAPI  Programmatic diffraction simulation for given phase and zone axis.
        edtZoneAxis.Value = sprintf('%d %d %d', za);
        % Temporarily store phase name so onSimulateDiffraction can find it
        if ~isempty(appData.diffResults) && ~isempty(appData.diffResults.candidates)
            appData.diffResults.candidates(1).phaseName = phase;
        end
        onSimulateDiffraction([], []);
    end

    function vdfAPI(center, radius)
    %VDFAPI  Programmatic virtual dark-field image from mask center and radius.
        idx = appData.activeIdx;
        if idx > 0 && idx <= numel(appData.images)
            pixels = double(appData.images{idx}.metadata.parserSpecific.imageData.pixels);
            vdf = imaging.virtualDarkField(pixels, 'MaskCenter', center, 'MaskRadius', radius);
            imagesc(ax, vdf); colormap(ax, 'gray'); axis(ax, 'image');
        end
    end

    function quantifyZAFAPI(t, angle)
    %QUANTIFYZAFAPI  Programmatic ZAF quantification with given thickness and take-off angle.
        edtEDSThickness.Value = num2str(t);
        edtEDSTakeOff.Value   = num2str(angle);
        onQuantifyZAF([], []);
    end

end
