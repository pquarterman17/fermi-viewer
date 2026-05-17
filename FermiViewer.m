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
%   api.setPanMode(true/false)       — enable/disable drag-to-pan mode
%   api.getPanMode()                 — query current pan mode state
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
    appData.measWorkshop  = emViewer.measurement.MeasurementWorkshop();
    appData.diffWorkshop  = emViewer.diffraction.DiffractionWorkshop();
    appData.contrastWS    = emViewer.contrast.ContrastWorkshop();
    appData.annotWorkshop = emViewer.annotation.AnnotationWorkshop();
    appData.eelsWorkshop  = emViewer.eels.EELSWorkshop();
    appData.edsWorkshop   = emViewer.eds.EDSWorkshop();
    appData.procWorkshop  = emViewer.processing.ProcessingWorkshop();
    appData.calibWS       = emViewer.calibration.CalibrationWorkshop();
    appData.captureMode   = '';     % '' | 'profile' | 'boxprofile' | 'distance' | 'zoom' | 'crop' | 'savecrop' | 'annotation' | 'angle' | 'polyline' | 'rectROI' | 'scalebar' | 'dspacing' | 'roiellipse' | 'arrow' | 'annotline' | 'annotrect' | 'annotcircle' | 'lattice' | 'gpa'
    appData.captureClicks = [];     % [Nx2] accumulated click coords (x y per row)
    appData.boxProfileWidth = 10;   % width (px) for the next Box Profile capture
    appData.selectedMeasIdx = 0;    % primary-selection index (last-clicked); 0 = none
    appData.selectedMeasIndices = []; % full multi-select set from marquee; scalar or array of indices
    appData.selectedAnnotIndices = [];% full multi-select set for annotations
    appData.zoomMode        = false; % false = drag marquee-selects, true = drag box-zooms
    appData.panMode         = false; % true = left-drag pans (middle-drag always pans)
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
    appData.eelsKKFig      = [];      % handle to KK results figure
    appData.eelsSVDResult  = [];      % SVD decomposition result struct
    appData.eelsSVDFig     = [];      % handle to SVD results figure
    appData.eelsELNESFig   = [];      % handle to ELNES results figure

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
    appData.annotationColor    = [1 1 1];    % white
    appData.selectedAnnotIdx   = 0;          % 0 = none selected
    appData.dragAnnotIdx       = 0;          % annotation being dragged
    appData.dragLastPt         = [0 0];      % last mouse position during drag
    appData.scaleBarColor      = [1 1 1];    % RGB tuple — SSoT for scale bar colour
    appData.histLogScale       = false;      % log-scale Y axis on histogram

    % Box-zoom / pan state (image axes rubber-band drag)
    appData.dragAction      = '';   % '' | 'zoom' | 'marquee' | 'pan'
    appData.zoomStartXY     = [];   % [x y] in data coords at drag start
    appData.zoomRect        = [];   % rectangle handle used for live preview
    appData.panStartXY      = [];   % [x y] in data coords at pan start
    appData.panStartLims    = [];   % struct with XLim, YLim at pan start
    appData.prevMotionFcn   = '';   % saved WindowButtonMotionFcn during box-zoom/pan
    appData.prevUpFcn       = '';   % saved WindowButtonUpFcn during box-zoom/pan
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

    % Theme — read persisted preference (shared with BosonPlotter via
    % bosonPlotter.themePref). Pref may be 'Dark', 'Light', or 'Auto';
    % bosonPlotter.resolveTheme turns 'Auto' into a concrete Dark/Light
    % value at startup (re-resolved on each toggle).
    appData.themePref = 'Dark';
    appData.darkMode  = true;
    try
        appData.themePref = bosonPlotter.themePref('read');
        appData.darkMode  = strcmpi(bosonPlotter.resolveTheme(appData.themePref), 'Dark');
    catch
        % Historical default if pref read fails.
    end

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
    fig.WindowScrollWheelFcn = @onScrollWheelContrast;

    % Drag-and-drop file loading (requires MATLAB R2022b+)
    try
        fig.DropFcn = @onFileDrop;
    catch
        % DropFcn not supported on older MATLAB versions — ignore
    end

    % ── Top-level menu bar ───────────────────────────────────────────────
    % Pure builder in +emViewer/buildMenuBar.m wired with the nested-fn
    % handles below. Mirrors the right-click context menus (cmImage / cmList).
    menuCb_ = struct( ...
        'onOpenFiles',@onOpenFiles, 'onBatchConvert',@onBatchConvert, 'onBatchRename',@onBatchRename, ...
        'onSessionSave',@onSessionSave, 'onSessionLoad',@onSessionLoad, ...
        'onSaveImage',@(~,~) onExportAction('saveImage'), ...
        'onCopyClipboard',@(~,~) onExportAction('copyClipboard'), ...
        'onExportWithOverlays',@(~,~) onExportAction('exportWithOverlays'), ...
        'onBatchExport',@(~,~) onExportAction('batchExport'), ...
        'onJournalExport',@(~,~) onExportAction('journalExport'), ...
        'onCreateGIF',@(~,~) onExportAction('createGIF'), ...
        'onExportProfileToDP',@onExportProfileToDP, 'onExportEDSComposite',@onExportEDSComposite, ...
        'onPreferences',@onPreferences, ...
        'onUndoFilters',@onUndoFilters, 'onResetContrast',@onResetContrast, 'onResetZoom',@onResetZoom, ...
        'onClearOverlays',@onClearOverlays, 'onRenameSelected',@onRenameSelected, 'onRemoveSelected',@onRemoveSelected, ...
        'onEditMetadata',@onEditMetadata, 'onSetPixelSize',@onSetPixelSize, ...
        'onAutoContrast',@onAutoContrast, 'onShowFFT',@onShowFFT, 'onLiveFFTToggle',@onLiveFFTToggle, ...
        'onColorbarToggle',@onColorbarToggle, 'onToggleHistLog',@onToggleHistLog, ...
        'onPixelInspectorToggle',@onPixelInspectorToggle, 'onMinimapToggle',@onMinimapToggle, ...
        'onThemeToggle',@onThemeToggle, 'onCompareToggle',@onCompareToggle, 'onFlickerCompare',@onFlickerCompare, ...
        'onThumbnailGrid',@onThumbnailGrid, 'onStackMIP',@onStackMIP, ...
        'onCropImage',@onCropImage, 'onZoomBox',@onZoomBox, 'onZoomOut',@onZoomOut, 'onZoomActual',@onZoomActual, 'onZoomFit',@onZoomFit, ...
        'onRotateFlip',@onRotateFlip, 'onInvertImage',@onInvertImage, 'onBinImage',@onBinImage, ...
        'onImageMath',@onImageMath, 'onStitchImages',@onStitchImages, 'onMontage',@onMontage, ...
        'onCustomColormap',@onCustomColormap, ...
        'onGaussianFilter',@onGaussianFilter, 'onMedianFilter',@onMedianFilter, 'onCLAHE',@onCLAHE, ...
        'onSharpen',@onSharpen, 'onButterworth',@onButterworth, 'onPlaneLevel',@onPlaneLevel, ...
        'onMorphOp',@onMorphOp, 'onMultiOtsu',@onMultiOtsu, 'onWatershed',@onWatershed, ...
        'onLineProfile',@onLineProfile, 'onBoxProfile',@onBoxProfile, 'onRadialProfile',@onRadialProfile, ...
        'onDistance',@onDistance, 'onAngleAction',@onAngleAction, 'onPolylineAction',@onPolylineAction, ...
        'onAzIntegrate',@onAzIntegrate, 'onParticleCount',@onParticleCount, 'onDefectCount',@onDefectCount, ...
        'onRoughness',@onRoughness, 'onInterfaceFit',@onInterfaceFit, 'onCTFEstimate',@onCTFEstimate, ...
        'onGPA',@onGPA, 'onCompositionProfile',@onCompositionProfile, 'onTemplateMatch',@onTemplateMatch, ...
        'onNoiseEstimate',@onNoiseEstimate, 'onBatchMeasurement',@onBatchMeasurement, ...
        'onMeasurementStats',@onMeasurementStats, 'onROIManager',@onROIManager, ...
        'onEnterEDS',@onEnterEDS, 'onExitEDS',@onExitEDS, 'onQuantifyCL',@onQuantifyCL, 'onQuantifyZAF',@onQuantifyZAF, ...
        'onEELSAction',@onEELSAction, 'onEELSAdvanced',@onEELSAdvanced, 'onEELSNavigateToggle',@onEELSNavigateToggle, ...
        'onDiffractionAction',@onDiffractionAction, 'onBackProject',@onBackProject, 'onVirtualDarkField',@onVirtualDarkField, ...
        'onCalibrateBar',@onCalibrateBar, 'onScaleBarToggle',@onScaleBarToggle, ...
        'onPlaceArrow',@onPlaceArrow, 'onPlaceCircle',@onPlaceCircle, 'onPlaceLine',@onPlaceLine, 'onPlaceRect',@onPlaceRect, ...
        'onSurfacePlot',@onSurfacePlot, 'onFigureBuilder',@onFigureBuilder, 'onPubPresets',@onPubPresets, ...
        'onStackNav',@onStackNav, 'onAlignStack',@onAlignStack, 'onMacroToggle',@onMacroToggle, ...
        'onShowEMShortcuts',@onShowEMShortcuts, ...
        'onReportBug',@(~,~) bugReport.reportBug(Source="FermiViewer"));
    emViewer.buildMenuBar(fig, menuCb_);

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
    %  ROW 1: TOOLBAR  — built by +emViewer/buildToolbar.m
    % ════════════════════════════════════════════════════════════════════
    tbCb_ = struct( ...
        'onOpenFiles',         @onOpenFiles, ...
        'onRecentFileSelected',@onRecentFileSelected, ...
        'onRemoveImage',       @onRemoveImage, ...
        'onZoomFit',           @onZoomFit, ...
        'onZoomActual',        @onZoomActual, ...
        'onZoomOut',           @onZoomOut, ...
        'onCompareToggle',     @onCompareToggle, ...
        'onThumbnailGrid',     @onThumbnailGrid, ...
        'onEDSToolbarToggle',  @onEDSToolbarToggle, ...
        'onPreferences',       @onPreferences, ...
        'onThemeToggle',       @onThemeToggle, ...
        'onShowEMShortcuts',   @onShowEMShortcuts);
    tb_         = emViewer.buildToolbar(rootGL, [], bp_, tbCb_);
    toolbarGL   = tb_.toolbarGL;
    lblFilename = tb_.lblFilename;
    ddRecent    = tb_.ddRecent;
    btnCompare  = tb_.btnCompare;
    btnGrid     = tb_.btnGrid;
    btnEDSToolbar  = tb_.btnEDSToolbar;
    btnThemeToggle = tb_.btnThemeToggle;

    % ════════════════════════════════════════════════════════════════════
    %  ROW 2: MAIN CONTENT — 3 columns
    %    Col 1 (260px):  Image list panel
    %    Col 2 (1x):     Image display (uiaxes)
    %    Col 3 (290px):  Tools panel (scrollable)
    % ════════════════════════════════════════════════════════════════════
    mainGL = uigridlayout(rootGL, [1 3], ...
        'ColumnWidth', {260, '1x', 290}, ...
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
        'RowHeight', {32, '1x', 0}, ...
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
    toolbarGL = uigridlayout(axGL, [1 15], ...
        'ColumnWidth', {28, 28, 4, 28, 28, 4, 28, 28, 28, 4, 28, 28, 4, 28, '1x'}, ...
        'RowHeight',   {28}, ...
        'Padding',     [2 2 2 2], ...
        'ColumnSpacing', 0);
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

    % 5th column marks state (toggle) buttons. The zoom button toggles
    % drag-to-zoom mode; when OFF (default) drag marquee-selects instead.
    tbSpecs = {
        'rot_cw.png',    'CW',    'Rotate 90° clockwise',                                     @(~,~) onRotateFlip('rot90cw'),  'push';
        'rot_ccw.png',   'CCW',   'Rotate 90° counter-clockwise',                             @(~,~) onRotateFlip('rot90ccw'), 'push';
        'flip_h.png',    'FH',    'Flip horizontally (left-right mirror)',                    @(~,~) onRotateFlip('fliph'),    'push';
        'flip_v.png',    'FV',    'Flip vertically (top-bottom mirror)',                      @(~,~) onRotateFlip('flipv'),    'push';
        'zoom.png',      'Z',     'Drag-to-zoom mode (toggle off for marquee-select)',        @(s,e) onDragModeToggle(s,e,'zoom'), 'state';
        'pan.png',       'Pan',   'Pan mode — drag to scroll when zoomed in (middle-drag always pans)', @(s,e) onDragModeToggle(s,e,'pan'), 'state';
        'fit.png',       'Fit',   'Fit image to window (reset zoom)',                         @onResetZoom,                    'push';
        'reset_all.png', 'Reset', 'Reset all transforms (reload original image)',             resetAllFcn,                     'push';
        'crop.png',      'Crop',  'Crop to rectangle (destructive — Undo Filters reverts)',   @onCropImage,                    'push';
        'del_annot.png', '⌫',     'Delete last annotation (Delete key)',                      @(~,~) onAnnotationAction('undoLast'), 'push';
    };

    % Column mapping: groups separated by 4px spacers at cols 3,6,10,13
    % rotate(1,2) | flip(4,5) | zoom+pan+fit(7,8,9) | reset+crop(11,12) | del-annot(14)
    tbCols = [1, 2, 4, 5, 7, 8, 9, 11, 12, 14];
    tbBtns = gobjects(1, size(tbSpecs, 1));
    for tbK = 1:size(tbSpecs, 1)
        tbIconPath = fullfile(iconDir, tbSpecs{tbK, 1});
        isState = strcmp(tbSpecs{tbK, 5}, 'state');
        cbProp  = 'ButtonPushedFcn';
        btnType = {};
        if isState
            cbProp  = 'ValueChangedFcn';
            btnType = {'state'};
        end
        if isfile(tbIconPath)
            tbBtns(tbK) = uibutton(toolbarGL, btnType{:}, ...
                'Icon',            tbIconPath, ...
                'Text',            '', ...
                'IconAlignment',   'center', ...
                'BackgroundColor', BTN_TOOL, ...
                'Tooltip',         tbSpecs{tbK, 3}, ...
                cbProp,            tbSpecs{tbK, 4}, ...
                'Enable',          'off');
        else
            tbBtns(tbK) = uibutton(toolbarGL, btnType{:}, ...
                'Text',            tbSpecs{tbK, 2}, ...
                'FontSize', 11, ...
                'BackgroundColor', BTN_TOOL, ...
                'FontColor',       BTN_FG, ...
                'Tooltip',         tbSpecs{tbK, 3}, ...
                cbProp,            tbSpecs{tbK, 4}, ...
                'Enable',          'off');
        end
        tbBtns(tbK).Layout.Row = 1;
        tbBtns(tbK).Layout.Column = tbCols(tbK);
    end
    appData.transformToolbarBtns = tbBtns;
    appData.toolbarIconPaths = cellfun( ...
        @(f) fullfile(iconDir, f), tbSpecs(:,1), 'UniformOutput', false)';

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
        'FontSize', 11, 'HorizontalAlignment', 'center', ...
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
    SECT_CONTRAST   = struct('name','Contrast',    'headerRow',1, 'panelRow',2,  'openHeight',250, 'collapsed',true);
    SECT_HISTOGRAM  = struct('name','Histogram',   'headerRow',3, 'panelRow',4,  'openHeight',107, 'collapsed',true);
    SECT_MEASURE    = struct('name','Measurement', 'headerRow',5, 'panelRow',6,  'openHeight',510, 'collapsed',true);
    SECT_PROCESS    = struct('name','Processing',  'headerRow',7, 'panelRow',8,  'openHeight',230, 'collapsed',true);
    SECT_ANNOT      = struct('name','Annotations',  'headerRow',9,  'panelRow',10, 'openHeight',165, 'collapsed',true);
    SECT_EDS        = struct('name','EDS Channels', 'headerRow',11, 'panelRow',12, 'openHeight',520, 'collapsed',true);
    SECT_META       = struct('name','Metadata',     'headerRow',13, 'panelRow',14, 'openHeight',120, 'collapsed',true);
    SECT_EXPORT     = struct('name','Export & Style','headerRow',19, 'panelRow',20, 'openHeight',370, 'collapsed',true);
    SECT_EELS       = struct('name','EELS Spectrum','headerRow',15, 'panelRow',16, 'openHeight',470, 'collapsed',true);
    SECT_DIFF       = struct('name','Diffraction',  'headerRow',17, 'panelRow',18, 'openHeight',380, 'collapsed',true);

    % Compute initial row heights: collapsed sections get 0
    initH = {22, 0, 22, 0, 22, 0, 22, 0, 22, 0, 22, 0, 22, 0, 22, 0, 22, 0, 22, 0};
    % All sections start collapsed; click header to expand

    toolsGL = uigridlayout(toolsPanel, [20 1], ...
        'RowHeight', initH, ...
        'ColumnWidth', {'1x'}, ...
        'Padding', [4 4 4 4], ...
        'RowSpacing', 1);

    % ── Section 1: Contrast ───────────────────────────────────────────────
    ARROW_OPEN = char(9660);   % ▼
    ARROW_SHUT = char(9654);   % ►
    btnContrastHeader = bosonPlotter.sectionHeader(toolsGL, [ARROW_SHUT ' Contrast'], ...
        @(~,~) toggleSection(SECT_CONTRAST));
    btnContrastHeader.Layout.Row = 1;

    contrastCbs_ = struct( ...
        'onContrastChanged',          @onContrastChanged, ...
        'onContrastEditChanged',      @onContrastEditChanged, ...
        'onAutoContrast',             @onAutoContrast, ...
        'onResetContrast',            @onResetContrast, ...
        'onColormapChanged',          @onColormapChanged, ...
        'onColorbarToggle',           @onColorbarToggle, ...
        'onGammaChanged',             @onGammaChanged, ...
        'onMinimapToggle',            @onMinimapToggle, ...
        'onContrastTransformChanged', @onContrastTransformChanged, ...
        'onInvertToggle',             @onInvertToggle);
    contrast_ = emViewer.buildContrastPanel(toolsGL, struct(), bp_, contrastCbs_);
    contrast_.pnlContrast.Layout.Row = 2;

    % Unpack contrast panel handles into closure-accessible variables
    pnlContrast         = contrast_.pnlContrast;
    sldLow              = contrast_.sldLow;
    efLow               = contrast_.efLow;
    sldHigh             = contrast_.sldHigh;
    efHigh              = contrast_.efHigh;
    sldGamma            = contrast_.sldGamma;
    efGamma             = contrast_.efGamma;
    ddColormap          = contrast_.ddColormap;
    cbColorbar          = contrast_.cbColorbar;
    hColorbar           = contrast_.hColorbar;
    cbMinimap           = contrast_.cbMinimap;
    ddContrastTransform = contrast_.ddContrastTransform;
    cbInvert            = contrast_.cbInvert;
    ddRenderMode        = contrast_.ddRenderMode;
    hMinimap            = contrast_.hMinimap;
    hMinimapRect        = contrast_.hMinimapRect;
    lblGamma            = contrast_.lblGamma;
    contrastInnerGL     = contrast_.contrastInnerGL;

    % ── Section 2: Histogram ──────────────────────────────────────────────
    btnHistogramHeader = bosonPlotter.sectionHeader(toolsGL, [ARROW_SHUT ' Histogram'], ...
        @(~,~) toggleSection(SECT_HISTOGRAM));
    btnHistogramHeader.Layout.Row = 3;

    pnlHistogram = uipanel(toolsGL, 'BorderType', 'line');
    pnlHistogram.Layout.Row = 4;

    histInnerGL = uigridlayout(pnlHistogram, [2 3], ...
        'Padding', [2 2 2 2], ...
        'RowHeight', {'1x', 22}, ...
        'ColumnWidth', {'1x', '1x', '1x'}, ...
        'RowSpacing', 2, 'ColumnSpacing', 3);

    histAx = uiaxes(histInnerGL);
    histAx.Layout.Row = 1; histAx.Layout.Column = [1 3];
    histAx.XTick = [];
    histAx.YTick = [];
    histAx.XColor = [0.5 0.5 0.5];
    histAx.YColor = [0.5 0.5 0.5];
    histAx.FontSize = 8;
    histAx.Box = 'on';
    histAx.XLim = [0 1];
    histAx.YLim = [0 1];
    histAx.Toolbar.Visible = 'off';
    histAx.ButtonDownFcn = @(~,~) onHistAxesClick();
    title(histAx, '');
    xlabel(histAx, '');
    ylabel(histAx, '');

    btnAutoC = uibutton(histInnerGL, 'Text', 'Auto', ...
        'Tooltip', 'Set contrast to 2%–98% percentile', ...
        'FontSize', 11, ...
        'ButtonPushedFcn', @onAutoContrast);
    btnAutoC.Layout.Row = 2; btnAutoC.Layout.Column = 1;

    btnResetC = uibutton(histInnerGL, 'Text', 'Reset', ...
        'Tooltip', 'Snap contrast to full data range', ...
        'FontSize', 11, ...
        'ButtonPushedFcn', @onResetContrast);
    btnResetC.Layout.Row = 2; btnResetC.Layout.Column = 2;

    btnLogHist = uibutton(histInnerGL, 'state', 'Text', 'Log', ...
        'Tooltip', 'Toggle log-scale histogram Y-axis', ...
        'FontSize', 11, ...
        'ValueChangedFcn', @(src,~) onToggleHistLog(src));
    btnLogHist.Layout.Row = 2; btnLogHist.Layout.Column = 3;

    % ── Section 3: Measurement ────────────────────────────────────────────
    btnMeasureHeader = bosonPlotter.sectionHeader(toolsGL, [ARROW_SHUT ' Measurement'], ...
        @(~,~) toggleSection(SECT_MEASURE));
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
    % Widget tree extracted to emViewer.buildMeasurementPanel.
    measCb_.onScaleBarToggle     = @onScaleBarToggle;
    measCb_.onScaleBarColorChange = @onScaleBarColorChange;
    measCb_.onScaleBarFontChange  = @onScaleBarFontChange;
    measCb_.onLineProfile         = @onLineProfile;
    measCb_.onBoxProfile          = @onBoxProfile;
    measCb_.onDistance            = @onDistance;
    measCb_.onExportProfile       = @(~,~) onExportAction('exportProfile');
    measCb_.onAngleAction         = @(s,e) onAngleAction('start', s, e);
    measCb_.onClearOverlays       = @onClearOverlays;
    measCb_.onRemoveSelected      = @(~,~) onRemoveSelected();
    measCb_.onExportMeasure       = @(~,~) onExportAction('exportMeasurements');
    measCb_.onDiffRings           = @(~,~) onDiffractionAction('rings');
    measCb_.onROIManager          = @onROIManager;
    measCb_.onCalibrateBar        = @onCalibrateBar;
    measCb_.onDSpacing            = @(~,~) onDiffractionAction('dspacing');
    measCb_.onDrawROI             = @(~,~) onDrawROI();
    measCb_.onInvertImage         = @onInvertImage;
    measCb_.onMeasurementStats    = @onMeasurementStats;
    measCb_.onBatchMeasurement    = @onBatchMeasurement;
    measCb_.onExportProfileToDP   = @onExportProfileToDP;
    measCb_.panelApplyLabelFont   = @panelApplyLabelFont;
    measCb_.panelApplySymbol      = @panelApplySymbol;
    measCb_.panelApplyColor       = @panelApplyColor;

    measPalette_.tool   = BTN_TOOL;
    measPalette_.fg     = BTN_FG;
    measPalette_.export = BTN_EXPORT;
    measPalette_.danger = BTN_DANGER;

    measW_ = emViewer.buildMeasurementPanel(pnlMeasure, measPalette_, measCb_);

    measureInnerGL  = measW_.measureInnerGL;
    cbScaleBar      = measW_.cbScaleBar;
    ddScaleBarColor = measW_.ddScaleBarColor;
    spnScaleBarFont = measW_.spnScaleBarFont;
    efScaleBarLen   = measW_.efScaleBarLen;
    ddScaleBarUnit  = measW_.ddScaleBarUnit;
    btnLineProfile  = measW_.btnLineProfile;
    btnBoxProfile   = measW_.btnBoxProfile;
    btnDistance     = measW_.btnDistance;
    btnExportProfile = measW_.btnExportProfile;
    btnAngle        = measW_.btnAngle;
    btnClearOverlays = measW_.btnClearOverlays;
    btnRemoveMeas   = measW_.btnRemoveMeas;
    cbTiltCorrect   = measW_.cbTiltCorrect;
    spnTiltAngle    = measW_.spnTiltAngle;
    ddTiltGeometry  = measW_.ddTiltGeometry;
    btnExportMeasure = measW_.btnExportMeasure;
    btnDiffRings    = measW_.btnDiffRings;
    btnROIManager   = measW_.btnROIManager;
    btnCalibrateBar = measW_.btnCalibrateBar;
    btnDSpacing     = measW_.btnDSpacing;
    spnProfileWidth = measW_.spnProfileWidth;
    ddROIShape      = measW_.ddROIShape;
    btnDrawROI      = measW_.btnDrawROI;
    btnInvertImg    = measW_.btnInvertImg;
    btnMeasStats    = measW_.btnMeasStats;
    btnBatchMeas    = measW_.btnBatchMeas;
    btnExportToDP   = measW_.btnExportToDP;
    spnMeasLabelFont = measW_.spnMeasLabelFont;
    ddMeasSymbol    = measW_.ddMeasSymbol;
    ddMeasColor     = measW_.ddMeasColor;

    % ROI Manager state
    appData.roiList = {};   % cell array of ROI structs: {name, xMin, xMax, yMin, yMax, stats}

    % ── Section 4: Processing ────────────────────────────────────────────
    btnProcessHeader = bosonPlotter.sectionHeader(toolsGL, [ARROW_SHUT ' Processing'], ...
        @(~,~) toggleSection(SECT_PROCESS));
    btnProcessHeader.Layout.Row = 7;

    pnlProcess = uipanel(toolsGL, 'BorderType', 'line');
    pnlProcess.Layout.Row = 8;

    % Build the Process tab-group (Transform / Filter / FFT & Analysis /
    % Surface & Stack) via the extracted package function.
    tfCb_ = struct( ...
        'onRotateFlip',          @onRotateFlip, ...
        'onZoomBox',             @onZoomBox, ...
        'onResetZoom',           @onResetZoom, ...
        'onCropImage',           @onCropImage, ...
        'onExportAction',        @onExportAction, ...
        'onBinImage',            @onBinImage, ...
        'onSetPixelSize',        @onSetPixelSize, ...
        'onGaussianFilter',      @onGaussianFilter, ...
        'onMedianFilter',        @onMedianFilter, ...
        'onCLAHE',               @onCLAHE, ...
        'onSharpen',             @onSharpen, ...
        'onMorphOp',             @onMorphOp, ...
        'onButterworth',         @onButterworth, ...
        'onFFTMask',             @onFFTMask, ...
        'onLiveThreshold',       @onLiveThreshold, ...
        'onMultiOtsu',           @onMultiOtsu, ...
        'onUndoFilters',         @onUndoFilters, ...
        'onPixelInspectorToggle',@onPixelInspectorToggle, ...
        'onShowFFT',             @onShowFFT, ...
        'onLiveFFTToggle',       @onLiveFFTToggle, ...
        'onRadialProfile',       @onRadialProfile, ...
        'onAzIntegrate',         @onAzIntegrate, ...
        'onDiffractionAction',   @onDiffractionAction, ...
        'onGPA',                 @onGPA, ...
        'onCTFEstimate',         @onCTFEstimate, ...
        'onNoiseEstimate',       @onNoiseEstimate, ...
        'onTemplateMatch',       @onTemplateMatch, ...
        'onInterfaceFit',        @onInterfaceFit, ...
        'onDefectCount',         @onDefectCount, ...
        'onPlaneLevel',          @onPlaneLevel, ...
        'onRoughness',           @onRoughness, ...
        'on3DSurface',           @on3DSurface, ...
        'onSurfacePlot',         @onSurfacePlot, ...
        'onBackProject',         @onBackProject, ...
        'onParticleCount',       @onParticleCount, ...
        'onWatershed',           @onWatershed, ...
        'onAlignStack',          @onAlignStack, ...
        'onStitchImages',        @onStitchImages, ...
        'onMontage',             @onMontage);

    tfPalette_ = struct('tool', BTN_TOOL, 'export', BTN_EXPORT, ...
                        'danger', BTN_DANGER, 'fg', BTN_FG);
    tf_ = emViewer.buildTransformPanel(pnlProcess, struct(), tfPalette_, tfCb_);

    % Unpack all widget handles returned by the extracted function
    btnRotCW          = tf_.btnRotCW;
    btnRotCCW         = tf_.btnRotCCW;
    btnFlipH          = tf_.btnFlipH;
    btnFlipV          = tf_.btnFlipV;
    btnZoomBox        = tf_.btnZoomBox;
    btnResetZoom      = tf_.btnResetZoom;
    btnCropImage      = tf_.btnCropImage;
    btnSaveCrop       = tf_.btnSaveCrop;
    btnBatchCrop      = tf_.btnBatchCrop;
    btnBinImage       = tf_.btnBinImage;
    btnSetPixelSize   = tf_.btnSetPixelSize;
    btnZoomDims       = tf_.btnZoomDims;
    btnGaussian       = tf_.btnGaussian;
    btnMedian         = tf_.btnMedian;
    btnCLAHE          = tf_.btnCLAHE;
    btnSharpen        = tf_.btnSharpen;
    btnMorphOp        = tf_.btnMorphOp;
    btnButterworth    = tf_.btnButterworth;
    btnFFTMask        = tf_.btnFFTMask;
    btnLiveThresh     = tf_.btnLiveThresh;
    btnMultiOtsu      = tf_.btnMultiOtsu;
    btnUndoFilters    = tf_.btnUndoFilters;
    cbPixelInspector  = tf_.cbPixelInspector;
    btnShowFFT        = tf_.btnShowFFT;
    btnLiveFFT        = tf_.btnLiveFFT;
    btnRadialProfile  = tf_.btnRadialProfile;
    btnAzIntegrate    = tf_.btnAzIntegrate;
    btnLatticeMeasure = tf_.btnLatticeMeasure;
    btnGPA            = tf_.btnGPA;
    btnCTF            = tf_.btnCTF;
    btnNoiseEstimate  = tf_.btnNoiseEstimate;
    btnTemplateMatch  = tf_.btnTemplateMatch;
    btnInterfaceFit   = tf_.btnInterfaceFit;
    btnDefectCount    = tf_.btnDefectCount;
    btnPlaneLevel     = tf_.btnPlaneLevel;
    btnRoughness      = tf_.btnRoughness;
    btn3DSurface      = tf_.btn3DSurface;
    btnSurfacePlot    = tf_.btnSurfacePlot;
    btnBackProject    = tf_.btnBackProject;
    btnParticles      = tf_.btnParticles;
    btnWatershed      = tf_.btnWatershed;
    btnAlignStack     = tf_.btnAlignStack;
    btnStitchImages   = tf_.btnStitchImages;
    btnMontage        = tf_.btnMontage;
    processTabGrids   = tf_.processTabGrids;
    processInnerGL    = tf_.processInnerGL;

    hPixelInspector = [];   % handle to pixel inspector axes overlay

    % ── Section 5: Annotations ──────────────────────────────────────────
    btnAnnotHeader = bosonPlotter.sectionHeader(toolsGL, [ARROW_SHUT ' Annotations'], ...
        @(~,~) toggleSection(SECT_ANNOT));
    btnAnnotHeader.Layout.Row = 9;

    annot_ = emViewer.buildAnnotationsPanel(toolsGL, struct(), ...
        struct('tool', BTN_TOOL, 'danger', BTN_DANGER, 'fg', BTN_FG, ...
               'overlayColor', OVERLAY_COLOR), ...
        struct('onAnnotationAction', @onAnnotationAction, ...
               'onPlaceArrow',       @onPlaceArrow, ...
               'onPlaceLine',        @onPlaceLine, ...
               'onPlaceRect',        @onPlaceRect, ...
               'onPlaceCircle',      @onPlaceCircle, ...
               'onAnnotColorChange', @onAnnotColorChange));
    pnlAnnot       = annot_.pnlAnnot;
    annotInnerGL   = annot_.annotInnerGL;
    efAnnotText    = annot_.efAnnotText;
    spnAnnotFont   = annot_.spnAnnotFont;
    ddAnnotColor   = annot_.ddAnnotColor;
    btnPlaceAnnot  = annot_.btnPlaceAnnot;
    btnClearAnnot  = annot_.btnClearAnnot;
    btnPlaceArrow  = annot_.btnPlaceArrow;
    btnPlaceLine   = annot_.btnPlaceLine;
    btnPlaceRect   = annot_.btnPlaceRect;
    btnPlaceCircle = annot_.btnPlaceCircle;
    btnUndoAnnot   = annot_.btnUndoAnnot;

    % ── Section 6: EDS Channels ──────────────────────────────────────────
    btnEDSHeader = bosonPlotter.sectionHeader(toolsGL, [ARROW_SHUT ' EDS Channels'], ...
        @(~,~) toggleSection(SECT_EDS));
    btnEDSHeader.Layout.Row = 11;

    eds_ = emViewer.buildEDSPanel(toolsGL, struct(), ...
        struct('primary', BTN_PRIMARY, 'tool', BTN_TOOL, 'danger', BTN_DANGER, ...
               'export', BTN_EXPORT, 'fg', BTN_FG), ...
        struct('onEnterEDS',              @onEnterEDS, ...
               'onEDSListChange',         @onEDSListChange, ...
               'onEDSChannelSelected',    @onEDSChannelSelected, ...
               'onEDSChannelPropChanged', @onEDSChannelPropChanged, ...
               'onExportEDSComposite',    @onExportEDSComposite, ...
               'onAssignElements',        @onAssignElements, ...
               'onQuantifyCL',            @onQuantifyCL, ...
               'onCompositionProfile',    @onCompositionProfile, ...
               'onROIComposition',        @onROIComposition, ...
               'onQuantifyZAF',           @(~,~) onQuantifyZAF()));
    pnlEDS              = eds_.pnlEDS;
    btnEnterEDS         = eds_.btnEnterEDS;
    btnAddChannel       = eds_.btnAddChannel;
    btnRemoveChannel    = eds_.btnRemoveChannel;
    lbEDSChannels       = eds_.lbEDSChannels;
    EDS_COLORS          = eds_.EDS_COLORS;
    ddChannelColor      = eds_.ddChannelColor;
    cbChannelVisible    = eds_.cbChannelVisible;
    lblEDSIntensity     = eds_.lblEDSIntensity;
    sldChannelIntensity = eds_.sldChannelIntensity;
    efChannelLabel      = eds_.efChannelLabel;
    btnExportComposite  = eds_.btnExportComposite;
    btnAssignElements   = eds_.btnAssignElements;
    btnQuantifyCL       = eds_.btnQuantifyCL;
    btnCompositionProfile = eds_.btnCompositionProfile;
    btnROIComposition   = eds_.btnROIComposition;
    edtEDSThickness     = eds_.edtEDSThickness;
    edtEDSTakeOff       = eds_.edtEDSTakeOff;
    btnQuantifyZAF      = eds_.btnQuantifyZAF;
    edsInnerGL          = eds_.edsInnerGL;

    % ── Section 7: Metadata (moved here from rows 19-20) ────────────────
    btnMetaHeader = bosonPlotter.sectionHeader(toolsGL, [ARROW_SHUT ' Metadata'], ...
        @(~,~) toggleSection(SECT_META));
    btnMetaHeader.Layout.Row = 13;

    pnlMeta = uipanel(toolsGL, 'BorderType', 'none');
    pnlMeta.Layout.Row = 14;
    metaInnerGL = uigridlayout(pnlMeta, [2 1], ...
        'RowHeight', {'1x', 28}, 'Padding', 0, 'RowSpacing', 2);
    taMetadata = uitextarea(metaInnerGL, ...
        'Value', {'(no image loaded)'}, ...
        'Editable', 'off', ...
        'FontName', 'Courier New', ...
        'FontSize', 11);
    btnEditMetadata = uibutton(metaInnerGL, 'Text', 'Edit Metadata', ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, ...
        'Tooltip', 'Override image metadata (sample name, pixel size, etc.)', ...
        'ButtonPushedFcn', @(~,~) onEditMetadata());

    % ── Section 8: EELS Spectrum ──────────────────────────────────────────
    btnEELSHeader = bosonPlotter.sectionHeader(toolsGL, [ARROW_SHUT ' EELS Spectrum'], ...
        @(~,~) toggleSection(SECT_EELS));
    btnEELSHeader.Layout.Row = 15;

    eels_ = emViewer.buildEELSPanel(toolsGL, struct(), ...
        struct('primary', BTN_PRIMARY, 'tool', BTN_TOOL, 'fg', BTN_FG), ...
        struct('onEnterEELS',          @onEnterEELS, ...
               'onEELSAction',         @onEELSAction, ...
               'onEELSAdvanced',       @onEELSAdvanced, ...
               'onEELSNavigateToggle', @(src,~) onEELSNavigateToggle(src)));
    pnlEELS            = eels_.pnlEELS;
    btnEnterEELS       = eels_.btnEnterEELS;
    edtEELSPreEdgeStart = eels_.edtEELSPreEdgeStart;
    edtEELSPreEdgeEnd  = eels_.edtEELSPreEdgeEnd;
    btnEELSFitBG       = eels_.btnEELSFitBG;
    ddEELSMethod       = eels_.ddEELSMethod;
    chkShowEdges       = eels_.chkShowEdges;
    ddEdgeFilter       = eels_.ddEdgeFilter;
    edtEELSSignalStart = eels_.edtEELSSignalStart;
    edtEELSSignalEnd   = eels_.edtEELSSignalEnd;
    btnEELSExtractMap  = eels_.btnEELSExtractMap;
    btnEELSThickness   = eels_.btnEELSThickness;
    btnEELSAlignZLP    = eels_.btnEELSAlignZLP;
    btnEELSDeconvolve  = eels_.btnEELSDeconvolve;
    btnEELSELNES       = eels_.btnEELSELNES;
    edtEELSEdgeOnset   = eels_.edtEELSEdgeOnset;
    btnEELSKK          = eels_.btnEELSKK;
    btnEELSNavigate    = eels_.btnEELSNavigate;
    btnEELSSVD         = eels_.btnEELSSVD;

    % ── Section 9: Diffraction Indexing ──────────────────────────────────
    btnDiffHeader = bosonPlotter.sectionHeader(toolsGL, [ARROW_SHUT ' Diffraction'], ...
        @(~,~) toggleSection(SECT_DIFF));
    btnDiffHeader.Layout.Row = 17;

    pnlDiff = uipanel(toolsGL, 'BorderType', 'line');
    pnlDiff.Layout.Row = 18;

    diffInnerGL = uigridlayout(pnlDiff, [9 2], ...
        'RowHeight', {28, 28, 28, 28, 28, 28, '1x', 28, 28}, ...
        'ColumnWidth', {'1x', '1x'}, ...
        'Padding', [4 4 4 4], ...
        'RowSpacing', 3);

    btnAutoDetectSpots = uibutton(diffInnerGL, 'Text', 'Auto-detect Spots', ...
        'ButtonPushedFcn', @(~,~) onDiffractionAction('autoDetect'), ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, ...
        'Enable', 'off', ...
        'Tooltip', 'Automatically find diffraction spots');
    btnAutoDetectSpots.Layout.Row = 1; btnAutoDetectSpots.Layout.Column = 1;

    btnClickDiffSpot = uibutton(diffInnerGL, 'Text', 'Click Spots', ...
        'ButtonPushedFcn', @(~,~) onDiffractionAction('clickSpot'), ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, ...
        'Enable', 'off', ...
        'Tooltip', 'Click to manually mark diffraction spots');
    btnClickDiffSpot.Layout.Row = 1; btnClickDiffSpot.Layout.Column = 2;

    btnClearDiffSpots = uibutton(diffInnerGL, 'Text', 'Clear Spots', ...
        'ButtonPushedFcn', @(~,~) onDiffractionAction('clearSpots'), ...
        'BackgroundColor', BTN_DANGER, 'FontColor', BTN_FG, ...
        'Enable', 'off', ...
        'Tooltip', 'Remove all diffraction spot markers');
    btnClearDiffSpots.Layout.Row = 2; btnClearDiffSpots.Layout.Column = 1;

    lblSpotCount = uilabel(diffInnerGL, 'Text', '0 spots', ...
        'FontSize', 11, 'HorizontalAlignment', 'center');
    lblSpotCount.Layout.Row = 2; lblSpotCount.Layout.Column = 2;

    lblCameraLen = uilabel(diffInnerGL, 'Text', 'Camera Length (mm):', ...
        'FontSize', 11, 'HorizontalAlignment', 'left');
    lblCameraLen.Layout.Row = 3; lblCameraLen.Layout.Column = 1;

    edtCameraLen = uieditfield(diffInnerGL, 'text', ...
        'Value', '', 'Placeholder', 'e.g. 200', 'FontSize', 11);
    edtCameraLen.Layout.Row = 3; edtCameraLen.Layout.Column = 2;

    lblAccVoltage = uilabel(diffInnerGL, 'Text', 'Voltage (kV):', ...
        'FontSize', 11, 'HorizontalAlignment', 'left');
    lblAccVoltage.Layout.Row = 4; lblAccVoltage.Layout.Column = 1;

    ddAccVoltage = uidropdown(diffInnerGL, ...
        'Items', {'80 kV', '100 kV', '120 kV', '200 kV', '300 kV'}, ...
        'Value', '200 kV', ...
        'Enable', 'off', ...
        'Tooltip', 'Electron accelerating voltage');
    ddAccVoltage.Layout.Row = 4; ddAccVoltage.Layout.Column = 2;

    btnMatchDiffraction = uibutton(diffInnerGL, 'Text', 'Match Phases', ...
        'ButtonPushedFcn', @(~,~) onDiffractionAction('match'), ...
        'BackgroundColor', BTN_PRIMARY, 'FontColor', BTN_FG, ...
        'FontWeight', 'bold', ...
        'Enable', 'off', ...
        'Tooltip', 'Index diffraction pattern and match to crystal phases');
    btnMatchDiffraction.Layout.Row = 5; btnMatchDiffraction.Layout.Column = 1;

    btnOverlayDiffRings = uibutton(diffInnerGL, 'Text', 'Overlay Rings', ...
        'ButtonPushedFcn', @(~,~) onDiffractionAction('overlayRings'), ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, ...
        'Enable', 'off', ...
        'Tooltip', 'Overlay d-spacing rings for selected phase');
    btnOverlayDiffRings.Layout.Row = 5; btnOverlayDiffRings.Layout.Column = 2;

    lblZoneAxisLabel = uilabel(diffInnerGL, 'Text', 'Zone Axis:', ...
        'FontSize', 11, 'HorizontalAlignment', 'left');
    lblZoneAxisLabel.Layout.Row = 6; lblZoneAxisLabel.Layout.Column = 1;

    lblZoneAxis = uilabel(diffInnerGL, 'Text', '', ...
        'FontSize', 11, 'HorizontalAlignment', 'left', 'FontWeight', 'bold');
    lblZoneAxis.Layout.Row = 6; lblZoneAxis.Layout.Column = 2;

    lbxDiffResults = uilistbox(diffInnerGL, ...
        'Items', {}, ...
        'FontSize', 11);
    lbxDiffResults.Layout.Row = 7; lbxDiffResults.Layout.Column = [1 2];

    % Row 8: Zone axis + Simulate
    edtZoneAxis = uieditfield(diffInnerGL, 'text', ...
        'Value', '0 0 1', 'Placeholder', 'Zone axis [u v w]');
    edtZoneAxis.Layout.Row = 8; edtZoneAxis.Layout.Column = 1;

    btnSimDiffraction = uibutton(diffInnerGL, 'Text', 'Simulate', ...
        'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, ...
        'Tooltip', 'Kinematic diffraction simulation', ...
        'Enable', 'off', ...
        'ButtonPushedFcn', @(~,~) onDiffractionAction('simulate'));
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
    btnExportHeader = uibutton(toolsGL, 'Text', [ARROW_SHUT ' Export & Style'], ...
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

    % ── Build export panel widgets via package helper ─────────────────
    expCb_.onSaveImage            = @(~,~) onExportAction('saveImage');
    expCb_.onCopyClipboard        = @(~,~) onExportAction('copyClipboard');
    expCb_.onExportWithOverlays   = @(~,~) onExportAction('exportWithOverlays');
    expCb_.onBatchExport          = @(~,~) onExportAction('batchExport');
    expCb_.onSessionSave          = @onSessionSave;
    expCb_.onSessionLoad          = @onSessionLoad;
    expCb_.onFigureBuilder        = @onFigureBuilder;
    expCb_.onJournalExport        = @(~,~) onExportAction('journalExport');
    expCb_.onPubPresets           = @onPubPresets;
    expCb_.onCalibratedColorbar   = @onCalibratedColorbar;
    expCb_.onCustomColormap       = @onCustomColormap;
    expCb_.onColormapPreset       = @onColormapPreset;
    expCb_.onCreateGIF            = @(~,~) onExportAction('createGIF');
    expCb_.onBatchConvert         = @onBatchConvert;
    expCb_.onColorOverlay         = @onColorOverlay;
    expCb_.onFlickerCompare       = @onFlickerCompare;
    expCb_.onMacroToggle          = @onMacroToggle;
    expCb_.onImageMath            = @onImageMath;
    expCb_.onBatchRename          = @onBatchRename;
    expCb_.onRenameSelected       = @onRenameSelected;

    expPalette_.export = BTN_EXPORT;
    expPalette_.tool   = BTN_TOOL;
    expPalette_.fg     = BTN_FG;

    expW_ = emViewer.buildExportPanel(exportInnerGL, expPalette_, expCb_);

    % Unpack handles into closure locals (same names used by callbacks below)
    btnSaveImage      = expW_.btnSaveImage;
    btnCopyClipboard  = expW_.btnCopyClipboard;
    btnExportOverlays = expW_.btnExportOverlays;
    btnBatchExport    = expW_.btnBatchExport;
    btnSessionSave    = expW_.btnSessionSave;
    btnSessionLoad    = expW_.btnSessionLoad;
    lblDPI            = expW_.lblDPI;
    ddExportDPI       = expW_.ddExportDPI;
    lblPubHeader      = expW_.lblPubHeader;
    btnFigureBuilder  = expW_.btnFigureBuilder;
    btnJournalExport  = expW_.btnJournalExport;
    btnPubPresets     = expW_.btnPubPresets;
    btnCalibColorbar  = expW_.btnCalibColorbar;
    btnCustomCmap     = expW_.btnCustomCmap;
    btnColormapPreset = expW_.btnColormapPreset;
    btnCreateGIF      = expW_.btnCreateGIF;
    btnBatchConvert   = expW_.btnBatchConvert;
    lblUtilHeader     = expW_.lblUtilHeader;
    btnColorOverlay   = expW_.btnColorOverlay;
    btnFlickerCompare = expW_.btnFlickerCompare;
    btnMacroRecord    = expW_.btnMacroRecord;
    btnImgMath        = expW_.btnImgMath;
    lblRename         = expW_.lblRename;
    efRenameBase      = expW_.efRenameBase;
    btnBatchRename    = expW_.btnBatchRename;
    btnRenameSelected = expW_.btnRenameSelected;

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
        'FontSize', 11, 'FontColor', [0.45 0.45 0.45]);
    lblStatusDims.Layout.Row = 1; lblStatusDims.Layout.Column = 1;

    lblStatusBits = uilabel(statusGL, 'Text', '--bit', ...
        'FontSize', 11, 'FontColor', [0.45 0.45 0.45]);
    lblStatusBits.Layout.Row = 1; lblStatusBits.Layout.Column = 2;

    lblStatusPixSize = uilabel(statusGL, 'Text', 'uncalibrated', ...
        'FontSize', 11, 'FontColor', [0.45 0.45 0.45]);
    lblStatusPixSize.Layout.Row = 1; lblStatusPixSize.Layout.Column = 3;

    lblStatusMouse = uilabel(statusGL, 'Text', '', ...
        'FontSize', 11, 'FontColor', [0.45 0.45 0.45]);
    lblStatusMouse.Layout.Row = 1; lblStatusMouse.Layout.Column = 4;

    % Discreet loading indicator — appears during file I/O, hidden otherwise
    lblLoadStatus = uilabel(statusGL, 'Text', '', ...
        'FontSize', 11, 'FontColor', [0.35 0.65 0.85], ...
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
        api.boxProfile     = @(x1,y1,x2,y2,w) executeBoxProfile(x1,y1,x2,y2,w);
        api.setZoomMode    = @setZoomModeAPI;
        api.getZoomMode    = @getZoomModeAPI;
        api.setPanMode     = @(v) onDragModeToggle(struct('Value', v), [], 'pan');
        api.getPanMode     = @() appData.panMode;
        api.marqueeSelect  = @applyMarqueeSelection;
        api.getSelectedMeasIndices  = @getSelectedMeasIndicesAPI;
        api.getSelectedAnnotIndices = @getSelectedAnnotIndicesAPI;
        api.removeSelected = @onRemoveSelected;

        % Phase 6 — processing & export
        api.applyFilter    = @(type, params) applyFilterAPI(type, params);
        api.computeFFT     = @() computeFFTAPI();
        api.exportImage    = @(path) onExportAction('saveImageAPI', path);

        % Comparison mode
        api.enterCompare    = @() enterCompareMode();
        api.exitCompare     = @() exitCompareMode();
        api.isCompareMode   = @() appData.compareMode;

        % Annotations
        api.placeAnnotation  = @(x, y, str, sz, col) placeAnnotationAPI(x, y, str, sz, col);
        api.clearAnnotations = @() onAnnotationAction('clear');
        api.clearOverlays    = @() onClearOverlays([], []);
        api.selectAnnotation = @(idx) onAnnotationAction('select', idx);
        api.deselectAnnotation = @() onAnnotationAction('deselect');
        api.deleteAnnotation = @(idx) onAnnotationAction('deleteOne', idx);
        api.setAnnotationColor = @(idx, col) onAnnotationAction('setColor', idx, col);
        api.getAnnotations   = @() appData.overlays.textAnnotations;
        api.getSelectedAnnotIdx = @() appData.selectedAnnotIdx;

        % Histogram
        api.setHistLogScale  = @(tf) setHistLogAPI(tf);

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
        api.getMeasStats    = @getMeasStatsAPI;
        api.getMeasModel    = @getMeasModelAPI;
        api.measWorkshop    = appData.measWorkshop;
        api.diffWorkshop    = appData.diffWorkshop;
        api.contrastWS      = appData.contrastWS;
        api.annotWorkshop   = appData.annotWorkshop;
        api.eelsWorkshop    = appData.eelsWorkshop;
        api.edsWorkshop     = appData.edsWorkshop;
        api.procWorkshop    = appData.procWorkshop;
        api.calibWS         = appData.calibWS;

        % Interactive measurement/ROI tools — headless wrappers around the
        % nested execute* functions so tests can drive them with explicit
        % coordinates (bypassing the two-click capture flow).
        api.measureDistance = @(x1,y1,x2,y2) executeMeasureDistance(x1,y1,x2,y2);
        api.measureDSpacing = @(x1,y1,x2,y2) executeDSpacing(x1,y1,x2,y2);
        api.measureAngle    = @(vx,vy,r1x,r1y,r2x,r2y) ...
                               executeAngleFromPoints([vx vy; r1x r1y; r2x r2y]);
        api.measurePolyline = @(pts) executePolylineFromPoints(pts);
        api.roiEllipse      = @(cx,cy,ex,ey) executeEllipseROI(cx,cy,ex,ey);
        api.rectROI         = @(xMin, xMax, yMin, yMax) executeRectROI(xMin, xMax, yMin, yMax);
        api.annotRect       = @(x1,y1,x2,y2) executeAnnotRect(x1,y1,x2,y2);
        api.getOverlays        = @getOverlaysAPI;
        api.getMeasurementLog  = @getMeasurementLogAPI;
        api.exportMeasurements = @(path) onExportAction('writeMeasurementsCSV', path);

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
        api.eelsDeconvolve    = @() onEELSAdvanced('deconvolve');
        api.eelsELNES         = @(onset) eelsELNESAPI(onset);
        api.eelsKramersKronig = @() onEELSAdvanced('kramersKronig');
        api.eelsNavigate      = @(row, col) eelsNavigateAPI(row, col);
        api.eelsSVD           = @(nComp) eelsSVDAPI(nComp);

        % Diffraction API
        api.findDiffSpots       = @() onDiffractionAction('autoDetect');
        api.matchDiffraction    = @() onDiffractionAction('match');
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
        api.close          = @closeAll;
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
    %ONOPENFILES  Browse for image files -- delegates to emViewer.imageOps.
        appData = emViewer.imageOps('open', appData, buildImageCtx());
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onRemoveImage — Remove selected image(s) from the list
    % ════════════════════════════════════════════════════════════════════
    function onRemoveImage(~, ~)
    %ONREMOVEIMAGE  Remove selected images -- delegates to emViewer.imageOps.
        appData = emViewer.imageOps('remove', appData, buildImageCtx());
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
        if appData.activeIdx < 1 || isempty(appData.rawPixels), return; end
        [H, W] = size(appData.rawPixels);
        axPos = getpixelposition(ax, true);
        [ax.XLim, ax.YLim] = emViewer.computeActualZoomLimits( ...
            mean(ax.XLim), mean(ax.YLim), axPos(3), axPos(4), H, W);
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onZoomOut — Zoom out by 2× centred on current view
    % ════════════════════════════════════════════════════════════════════
    function onZoomOut(~, ~)
        if appData.activeIdx < 1 || isempty(appData.rawPixels), return; end
        [H, W] = size(appData.rawPixels);
        cx = mean(ax.XLim); cy = mean(ax.YLim);
        hw = diff(ax.XLim); hh = diff(ax.YLim);
        xl = [max(cx-hw, 0.5), min(cx+hw, W+0.5)];
        yl = [max(cy-hh, 0.5), min(cy+hh, H+0.5)];
        if diff(xl) >= W && diff(yl) >= H
            onZoomFit([], []);
        else
            ax.XLim = xl; ax.YLim = yl;
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onMouseMotion — delegates to emViewer.mouseOps
    % ════════════════════════════════════════════════════════════════════
    function onMouseMotion(~, ~)
        appData = emViewer.mouseOps('motion', appData, buildMouseCtx());
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
        % ── wrapper: delegates to emViewer.displayImage ──────────────────
        ui_ = struct( ...
            'ax', ax, ...
            'sldLow', sldLow, 'sldHigh', sldHigh, ...
            'sldGamma', sldGamma, 'efLow', efLow, 'efHigh', efHigh, ...
            'efGamma', efGamma, 'lblGamma', lblGamma, ...
            'ddColormap', ddColormap, 'ddContrastTransform', ddContrastTransform, ...
            'cbInvert', cbInvert, 'lblFilename', lblFilename, ...
            'cbScaleBar', cbScaleBar, 'ddScaleBarColor', ddScaleBarColor, ...
            'spnScaleBarFont', spnScaleBarFont, 'efScaleBarLen', efScaleBarLen, ...
            'ddScaleBarUnit', ddScaleBarUnit, ...
            'btnLineProfile', btnLineProfile, 'btnBoxProfile', btnBoxProfile, ...
            'btnDistance', btnDistance, 'btnAngle', btnAngle, ...
            'btnClearOverlays', btnClearOverlays, 'btnRemoveMeas', btnRemoveMeas, ...
            'spnMeasLabelFont', spnMeasLabelFont, 'ddMeasSymbol', ddMeasSymbol, ...
            'ddMeasColor', ddMeasColor, ...
            'spnTiltAngle', spnTiltAngle, 'cbTiltCorrect', cbTiltCorrect, ...
            'ddTiltGeometry', ddTiltGeometry, ...
            'btnRotCW', btnRotCW, 'btnRotCCW', btnRotCCW, ...
            'btnFlipH', btnFlipH, 'btnFlipV', btnFlipV, ...
            'btnGaussian', btnGaussian, 'btnMedian', btnMedian, ...
            'btnShowFFT', btnShowFFT, 'btnCLAHE', btnCLAHE, ...
            'btnUndoFilters', btnUndoFilters, ...
            'ddROIShape', ddROIShape, 'btnDrawROI', btnDrawROI, ...
            'btnZoomBox', btnZoomBox, 'btnZoomDims', btnZoomDims, ...
            'btnResetZoom', btnResetZoom, 'btnCropImage', btnCropImage, ...
            'btnSaveCrop', btnSaveCrop, 'btnSaveImage', btnSaveImage, ...
            'btnSetPixelSize', btnSetPixelSize, 'btnFFTMask', btnFFTMask, ...
            'btnParticles', btnParticles, 'btnAlignStack', btnAlignStack, ...
            'btnColorOverlay', btnColorOverlay, 'btnExportOverlays', btnExportOverlays, ...
            'btnBatchExport', btnBatchExport, 'btnCreateGIF', btnCreateGIF, ...
            'btnCopyClipboard', btnCopyClipboard, 'cbColorbar', cbColorbar, ...
            'cbMinimap', cbMinimap, 'cbPixelInspector', cbPixelInspector, ...
            'btnLiveThresh', btnLiveThresh, 'btnImgMath', btnImgMath, ...
            'btnWatershed', btnWatershed, 'btnBatchCrop', btnBatchCrop, ...
            'btnMontage', btnMontage, 'btnSessionSave', btnSessionSave, ...
            'btnEnterEDS', btnEnterEDS, 'btnGrid', btnGrid, ...
            'btnExportMeasure', btnExportMeasure, 'btnDiffRings', btnDiffRings, ...
            'btnROIManager', btnROIManager, 'btnCalibrateBar', btnCalibrateBar, ...
            'btnBatchRename', btnBatchRename, 'btnRenameSelected', btnRenameSelected, ...
            'btnDSpacing', btnDSpacing, 'spnProfileWidth', spnProfileWidth, ...
            'btnInvertImg', btnInvertImg, ...
            'btnSharpen', btnSharpen, 'btnBinImage', btnBinImage, ...
            'btnMorphOp', btnMorphOp, 'btnButterworth', btnButterworth, ...
            'btnRadialProfile', btnRadialProfile, 'btnAzIntegrate', btnAzIntegrate, ...
            'btnSurfacePlot', btnSurfacePlot, 'btnBatchConvert', btnBatchConvert, ...
            'btnCustomCmap', btnCustomCmap, ...
            'btnPlaneLevel', btnPlaneLevel, 'btnRoughness', btnRoughness, ...
            'btnInterfaceFit', btnInterfaceFit, 'btnMultiOtsu', btnMultiOtsu, ...
            'btnLatticeMeasure', btnLatticeMeasure, 'btnGPA', btnGPA, ...
            'btnCTF', btnCTF, 'btnDefectCount', btnDefectCount, ...
            'btnBackProject', btnBackProject, 'btnFigureBuilder', btnFigureBuilder, ...
            'btnJournalExport', btnJournalExport, 'btnCalibColorbar', btnCalibColorbar, ...
            'btnMacroRecord', btnMacroRecord, 'btnFlickerCompare', btnFlickerCompare, ...
            'btn3DSurface', btn3DSurface, 'btnLiveFFT', btnLiveFFT, ...
            'btnTemplateMatch', btnTemplateMatch, 'btnStitchImages', btnStitchImages, ...
            'btnNoiseEstimate', btnNoiseEstimate, 'btnPubPresets', btnPubPresets, ...
            'btnColormapPreset', btnColormapPreset, 'btnMeasStats', btnMeasStats, ...
            'btnBatchMeas', btnBatchMeas, 'btnExportToDP', btnExportToDP, ...
            'btnPlaceAnnot', btnPlaceAnnot, 'btnClearAnnot', btnClearAnnot, ...
            'btnUndoAnnot', btnUndoAnnot, 'ddAnnotColor', ddAnnotColor, ...
            'btnPlaceArrow', btnPlaceArrow, 'btnPlaceLine', btnPlaceLine, ...
            'btnPlaceRect', btnPlaceRect, 'btnPlaceCircle', btnPlaceCircle);
        cb_ = struct( ...
            'compositeEDS',          @compositeEDS, ...
            'clearDisplay',          @(varargin) closureReturn_('clear', varargin{:}), ...
            'deselectMeasurement',   @deselectMeasurement, ...
            'cancelCapture',         @cancelCapture, ...
            'clearAllOverlays',      @clearAllOverlays, ...
            'prepareDisplayBuffer',  @(varargin) closureReturn_('prepare', varargin{:}), ...
            'applyContrastPipeline', @applyContrastPipeline, ...
            'attachImageContextMenu',@attachImageContextMenu, ...
            'showStackControls',     @showStackControls, ...
            'rebuildScaleBar',       @rebuildScaleBar, ...
            'updateMetadataPanel',   @updateMetadataPanel, ...
            'updateStatusBar',       @updateStatusBar, ...
            'updateHistogram',       @updateHistogram, ...
            'setStatus',             @setStatus, ...
            'onOff',                 @onOff, ...
            'pushAppData',           @(ad) closureReturn_('push', ad), ...
            'pullAppData',           @() closureReturn_('pull'));
        appData = emViewer.displayImage(appData, ui_, cb_);
    end

    function ad = closureReturn_(which, adIn)
    %CLOSURERETURN_  Bridge between package-function appData and closure.
        if nargin >= 2 && ~strcmp(which, 'pull')
            appData = adIn;
        end
        switch which
            case 'clear',   clearDisplay();
            case 'prepare', prepareDisplayBuffer();
            case 'push'     % push done above; no-op body
            case 'pull'     % return closure appData without overwriting
        end
        ad = appData;
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: clearDisplay — Clear the axes and reset status when no image
    % ════════════════════════════════════════════════════════════════════
    function clearDisplay()
        % ── wrapper: delegates to emViewer.clearDisplay ──────────────────
        ui_ = struct( ...
            'ax', ax, 'histAx', histAx, ...
            'lblFilename', lblFilename, ...
            'lblStatusDims', lblStatusDims, 'lblStatusBits', lblStatusBits, ...
            'lblStatusPixSize', lblStatusPixSize, 'lblStatusMouse', lblStatusMouse, ...
            'taMetadata', taMetadata, ...
            'btnLineProfile', btnLineProfile, 'btnBoxProfile', btnBoxProfile, ...
            'btnDistance', btnDistance, 'btnExportProfile', btnExportProfile, ...
            'btnAngle', btnAngle, 'btnClearOverlays', btnClearOverlays, ...
            'btnRemoveMeas', btnRemoveMeas, ...
            'cbScaleBar', cbScaleBar, 'ddScaleBarColor', ddScaleBarColor, ...
            'spnScaleBarFont', spnScaleBarFont, 'efScaleBarLen', efScaleBarLen, ...
            'ddScaleBarUnit', ddScaleBarUnit, ...
            'btnRotCW', btnRotCW, 'btnRotCCW', btnRotCCW, ...
            'btnFlipH', btnFlipH, 'btnFlipV', btnFlipV, ...
            'btnGaussian', btnGaussian, 'btnMedian', btnMedian, ...
            'btnShowFFT', btnShowFFT, 'btnCLAHE', btnCLAHE, ...
            'btnUndoFilters', btnUndoFilters, ...
            'ddROIShape', ddROIShape, 'btnDrawROI', btnDrawROI, ...
            'btnZoomBox', btnZoomBox, 'btnZoomDims', btnZoomDims, ...
            'btnResetZoom', btnResetZoom, 'btnCropImage', btnCropImage, ...
            'btnSaveCrop', btnSaveCrop, 'btnSaveImage', btnSaveImage, ...
            'btnSetPixelSize', btnSetPixelSize, 'btnFFTMask', btnFFTMask, ...
            'btnParticles', btnParticles, 'btnAlignStack', btnAlignStack, ...
            'btnColorOverlay', btnColorOverlay, 'btnExportOverlays', btnExportOverlays, ...
            'btnBatchExport', btnBatchExport, 'btnCreateGIF', btnCreateGIF, ...
            'btnCopyClipboard', btnCopyClipboard, ...
            'cbColorbar', cbColorbar, 'cbMinimap', cbMinimap, ...
            'cbPixelInspector', cbPixelInspector, ...
            'btnLiveThresh', btnLiveThresh, 'btnImgMath', btnImgMath, ...
            'btnWatershed', btnWatershed, 'btnBatchCrop', btnBatchCrop, ...
            'btnMontage', btnMontage, 'btnSessionSave', btnSessionSave, ...
            'btnEnterEDS', btnEnterEDS, 'btnEDSToolbar', btnEDSToolbar, ...
            'btnAddChannel', btnAddChannel, 'btnRemoveChannel', btnRemoveChannel, ...
            'btnExportComposite', btnExportComposite, ...
            'btnGrid', btnGrid, 'btnExportMeasure', btnExportMeasure, ...
            'btnDiffRings', btnDiffRings, 'btnROIManager', btnROIManager, ...
            'btnCalibrateBar', btnCalibrateBar, ...
            'btnBatchRename', btnBatchRename, 'btnRenameSelected', btnRenameSelected, ...
            'hColorbar', hColorbar, 'hMinimap', hMinimap, ...
            'hPixelInspector', hPixelInspector, ...
            'btnPlaneLevel', btnPlaneLevel, 'btnRoughness', btnRoughness, ...
            'btnInterfaceFit', btnInterfaceFit, 'btnMultiOtsu', btnMultiOtsu, ...
            'btnLatticeMeasure', btnLatticeMeasure, 'btnGPA', btnGPA, ...
            'btnCTF', btnCTF, 'btnDefectCount', btnDefectCount, ...
            'btnBackProject', btnBackProject, 'btnFigureBuilder', btnFigureBuilder, ...
            'btnJournalExport', btnJournalExport, 'btnCalibColorbar', btnCalibColorbar, ...
            'btnMacroRecord', btnMacroRecord, 'btnFlickerCompare', btnFlickerCompare, ...
            'btnPlaceAnnot', btnPlaceAnnot, 'btnClearAnnot', btnClearAnnot, ...
            'btnUndoAnnot', btnUndoAnnot, 'ddAnnotColor', ddAnnotColor);
        cb_ = struct('showStackControls', @showStackControls);
        appData = emViewer.clearDisplay(appData, ui_, cb_);
        % The package function called delete() on these handles if they were
        % valid. Nil the closure vars to prevent dangling handle reuse.
        if ~isempty(hColorbar) && ~isvalid(hColorbar)
            hColorbar = [];
        end
        if ~isempty(hMinimap) && ~isvalid(hMinimap)
            hMinimap = [];
        end
        if ~isempty(hPixelInspector) && ~isvalid(hPixelInspector)
            hPixelInspector = [];
        end
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
    %  HELPER: buildMeasCtx — Build context struct for measurement operations
    %  Bundles axes/fig handles, UI widget handles, and callback handles
    %  into a single struct passed to +emViewer measurement package functions.
    % ════════════════════════════════════════════════════════════════════
    function ctx = buildMeasCtx()
        ctx.ax  = ax;
        ctx.fig = fig;
        ctx.OVERLAY_COLOR = OVERLAY_COLOR;
        ctx.ui.ddMeasColor      = ddMeasColor;
        ctx.ui.ddMeasSymbol     = ddMeasSymbol;
        ctx.ui.spnProfileWidth  = spnProfileWidth;
        ctx.ui.btnExportProfile = btnExportProfile;
        ctx.ui.spnMeasLabelFont = spnMeasLabelFont;
        ctx.cb.setStatus             = @setStatus;
        ctx.cb.getTiltState          = @getTiltState;
        ctx.cb.runWidthAveragedProfile = @runWidthAveragedProfile;
        ctx.cb.selectMeasurement     = @selectMeasurement;
        ctx.cb.deselectMeasurement   = @deselectMeasurement;
        ctx.cb.startEndpointDrag     = @startEndpointDrag;
        ctx.cb.startLabelDrag        = @startLabelDrag;
        ctx.cb.buildMeasLineMenu     = @buildMeasLineMenu;
        ctx.cb.finishCapture         = @finishCapture;
        ctx.cb.cancelCapture         = @cancelCapture;
        ctx.cb.applyMeasHighlight    = @applyMeasHighlight;
        ctx.cb.highlightAnnotation   = @highlightAnnotation;
        ctx.cb.onAngleAction         = @onAngleAction;
        ctx.cb.onPolylineAction      = @onPolylineAction;
        ctx.cb.panelApplyLabelFont   = @panelApplyLabelFont;
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: buildScaleBarCtx — Build context struct for scale bar operations
    % ════════════════════════════════════════════════════════════════════
    function ctx = buildScaleBarCtx()
        ctx.ax  = ax;
        ctx.fig = fig;
        ctx.axL = axL;
        ctx.axR = axR;
        ctx.ui.spnScaleBarFont = spnScaleBarFont;
        ctx.ui.efScaleBarLen   = efScaleBarLen;
        ctx.ui.ddScaleBarUnit  = ddScaleBarUnit;
        ctx.cb.deleteScaleBar        = @deleteScaleBar;
        ctx.cb.makeScaleBarDraggable = @makeScaleBarDraggable;
        ctx.cb.setStatus             = @setStatus;
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: buildMouseCtx -- context struct for emViewer.mouseOps
    % ════════════════════════════════════════════════════════════════════
    function ctx = buildMouseCtx()
        ctx.fig              = fig;
        ctx.ax               = ax;
        ctx.lbImages         = lbImages;
        ctx.lblStatusMouse   = lblStatusMouse;
        ctx.cbPixelInspector = cbPixelInspector;
        ctx.cb.detectResizeBorder    = @detectResizeBorder;
        ctx.cb.startPanelResize      = @startPanelResize;
        ctx.cb.deselectMeasurement   = @deselectMeasurement;
        ctx.cb.highlightAnnotation   = @highlightAnnotation;
        ctx.cb.onZoomBox             = @onZoomBox;
        ctx.cb.onResetZoom           = @onResetZoom;
        ctx.cb.onZoomFit             = @onZoomFit;
        ctx.cb.onZoomActual          = @onZoomActual;
        ctx.cb.onZoomOut             = @onZoomOut;
        ctx.cb.togglePanMode         = @() onDragModeToggle(struct('Value', ~appData.panMode), [], 'pan');
        ctx.cb.onExportAction        = @onExportAction;
        ctx.cb.contextToggleScaleBar = @contextToggleScaleBar;
        ctx.cb.onClearOverlays       = @onClearOverlays;
        ctx.cb.onOpenFiles           = @onOpenFiles;
        ctx.cb.onRenameSelected      = @onRenameSelected;
        ctx.cb.onRemoveImage         = @onRemoveImage;
        ctx.cb.onBoxZoomDrag         = @onBoxZoomDrag;
        ctx.cb.onBoxZoomRelease      = @onBoxZoomRelease;
        ctx.cb.attachImageContextMenu = @attachImageContextMenu;
        ctx.cb.onAutoContrast        = @onAutoContrast;
        ctx.cb.onArmDistance         = @onArmDistance;
        ctx.cb.onArmLineProfile      = @onArmLineProfile;
        ctx.cb.onArmROIStats         = @onArmROIStats;
        ctx.cb.refreshState          = @refreshState;
        ctx.cb.cancelCapture         = @cancelCapture;
        ctx.cb.onContrastChanged     = @onContrastChanged;
        ctx.cb.updatePixelInspector  = @updatePixelInspector;
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: buildSessionCtx -- context struct for emViewer.sessionOps
    % ════════════════════════════════════════════════════════════════════
    function ctx = buildSessionCtx(inPath, idxs, evt)
        if nargin < 1, inPath = ''; end
        if nargin < 2, idxs   = []; end
        if nargin < 3, evt    = []; end
        ctx.fig          = fig;
        ctx.lbImages     = lbImages;
        ctx.sldGamma     = sldGamma;
        ctx.efGamma      = efGamma;
        ctx.ddColormap   = ddColormap;
        ctx.efRenameBase = efRenameBase;
        ctx.sldLow       = sldLow;
        ctx.sldHigh      = sldHigh;
        ctx.inPath       = inPath;
        ctx.idxs         = idxs;
        ctx.evt          = evt;
        ctx.cb.rebuildImageList    = @rebuildImageList;
        ctx.cb.displayImage        = @displayImage;
        ctx.cb.refreshDisplay      = @refreshDisplay;
        ctx.cb.setStatus           = @setStatus;
        ctx.cb.hideLoading         = @hideLoading;
        ctx.cb.loadImagesFromPaths = @loadImagesFromPaths;
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: buildImageCtx -- context struct for emViewer.imageOps
    % ════════════════════════════════════════════════════════════════════
    function ctx = buildImageCtx()
        ctx.fig           = fig;
        ctx.lbImages      = lbImages;
        ctx.btnCompare    = btnCompare;
        ctx.btnEDSToolbar = btnEDSToolbar;
        ctx.cb.loadImagesFromPaths = @loadImagesFromPaths;
        ctx.cb.hideLoading         = @hideLoading;
        ctx.cb.setStatus           = @setStatus;
        ctx.cb.rebuildImageList    = @rebuildImageList;
        ctx.cb.displayImage        = @displayImage;
        ctx.cb.clearDisplay        = @clearDisplay;
        ctx.cb.exitCompareMode     = @exitCompareMode;
        ctx.cb.onOff               = @onOff;
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: buildDisplayCtx — Context for emViewer.displayHelpers
    % ════════════════════════════════════════════════════════════════════
    function ctx = buildDisplayCtx()
        ctx.ax           = ax;
        ctx.sldLow       = sldLow;
        ctx.sldHigh      = sldHigh;
        ctx.sldGamma     = sldGamma;
        ctx.ddColormap   = ddColormap;
        ctx.cbScaleBar   = cbScaleBar;
        ctx.cbColorbar   = cbColorbar;
        ctx.cbMinimap    = cbMinimap;
        ctx.hColorbar    = hColorbar;
        ctx.hMinimap     = hMinimap;
        ctx.hPixelInspector             = hPixelInspector;
        ctx.ui.btnExportProfile         = btnExportProfile;
        ctx.cb.applyContrastPipeline    = @applyContrastPipeline;
        ctx.cb.refreshHistogramMarkers  = @refreshHistogramMarkers;
        ctx.cb.updateMinimapRect        = @updateMinimapRect;
        ctx.cb.updateLiveFFT            = @updateLiveFFT;
        ctx.cb.rebuildScaleBar          = @rebuildScaleBar;
        ctx.cb.attachImageContextMenu   = @attachImageContextMenu;
        ctx.cb.updateMetadataPanel      = @updateMetadataPanel;
        ctx.cb.updateStatusBar          = @updateStatusBar;
        ctx.cb.updateHistogram          = @updateHistogram;
        ctx.cb.setStatus                = @setStatus;
        ctx.cb.displayImage             = @displayImage;
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
    %  (Restored after the inline of #17 missed the call site in
    %  +emViewer/displayImage.m. The function is also part of the
    %  callbacks contract exposed via ctx.cb for the test harness.)
    % ════════════════════════════════════════════════════════════════════
    function updateMetadataPanel()
        if appData.activeIdx < 1 || appData.activeIdx > numel(appData.images)
            taMetadata.Value = {'(no image loaded)'};
            return;
        end
        taMetadata.Value = emViewer.display.formatMetadata(appData.images{appData.activeIdx});
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: rebuildImageList — Sync the listbox with appData.images
    % ════════════════════════════════════════════════════════════════════
    function rebuildImageList()
        emViewer.rebuildImageList(appData.images, appData.activeIdx, lbImages);
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: loadImagesFromPaths — Load files and add to appData.images
    % ════════════════════════════════════════════════════════════════════
    function loadImagesFromPaths(fpaths)
        % ── wrapper: delegates to emViewer.loadImages ─────────────────────
        ui_ = struct('fig', fig);
        cb_ = struct( ...
            'showLoading',      @showLoading, ...
            'updateLoading',    @updateLoading, ...
            'hideLoading',      @hideLoading, ...
            'appendImage',      @appendImage, ...
            'addToRecentFiles', @addToRecentFiles, ...
            'promptAndLoadRaw', @promptAndLoadRaw, ...
            'rebuildImageList', @rebuildImageList, ...
            'displayImage',     @displayImage);
        emViewer.loadImages(fpaths, appData, ui_, cb_);
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
        % ── wrapper: delegates to emViewer.loadImages (API mode) ─────────
        ui_ = struct('fig', []);   % no uialert in API mode
        cb_ = struct( ...
            'showLoading',      @(~) [], ...
            'updateLoading',    @(varargin) [], ...
            'hideLoading',      @() [], ...
            'appendImage',      @appendImage, ...
            'addToRecentFiles', @(~) [], ...
            'promptAndLoadRaw', @(~) [], ...
            'rebuildImageList', @rebuildImageList, ...
            'displayImage',     @displayImage);
        emViewer.loadImages(paths, appData, ui_, cb_);
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
    %  CALLBACK: onContrastChanged — delegates to emViewer.contrastOps
    % ════════════════════════════════════════════════════════════════════
    function onContrastChanged(src, ~)
        [ui_, cb_] = buildContrastCtx();
        appData = emViewer.contrastOps('changed', appData, ui_, cb_, src);
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onContrastEditChanged — delegates to emViewer.contrastOps
    % ════════════════════════════════════════════════════════════════════
    function onContrastEditChanged(src, ~)
        [ui_, cb_] = buildContrastCtx();
        % Store returned appData FIRST (may carry new gamma/renderMode),
        % then trigger refresh so the pipeline sees the updated state.
        appData = emViewer.contrastOps('editChanged', appData, ui_, cb_, src);
        if isequal(src, ui_.efGamma) || isequal(src, ui_.ddRenderMode)
            if isequal(src, ui_.ddRenderMode)
                prepareDisplayBuffer();
            end
            onContrastChanged([], []);
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onAutoContrast — delegates to emViewer.contrastOps
    % ════════════════════════════════════════════════════════════════════
    function onAutoContrast(~, ~)
        [ui__, cb__] = buildContrastCtx();
        appData = emViewer.contrastOps('auto', appData, ui__, cb__);
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onResetContrast — delegates to emViewer.contrastOps
    % ════════════════════════════════════════════════════════════════════
    function onResetContrast(~, ~)
        [ui__, cb__] = buildContrastCtx();
        appData = emViewer.contrastOps('reset', appData, ui__, cb__);
        onContrastChanged([], []);
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onColormapChanged — delegates to emViewer.contrastOps
    % ════════════════════════════════════════════════════════════════════
    function onColormapChanged(~, ~)
        [ui__, cb__] = buildContrastCtx();
        appData = emViewer.contrastOps('colormapChanged', appData, ui__, cb__);
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onGaussianFilter — delegates to emViewer.filterOps
    % ════════════════════════════════════════════════════════════════════
    function onGaussianFilter(~, ~)
        appData = emViewer.filterOps('gaussian', appData, fig, struct('undoPush', @undoPush, 'undoPop', @undoPop, 'refreshDisplay', @refreshDisplay, 'setStatus', @setStatus));
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onMedianFilter — delegates to emViewer.filterOps
    % ════════════════════════════════════════════════════════════════════
    function onMedianFilter(~, ~)
        appData = emViewer.filterOps('median', appData, fig, struct('undoPush', @undoPush, 'undoPop', @undoPop, 'refreshDisplay', @refreshDisplay, 'setStatus', @setStatus));
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onShowFFT — delegates to emViewer.filterOps
    % ════════════════════════════════════════════════════════════════════
    function onShowFFT(~, ~)
        appData = emViewer.filterOps('showFFT', appData, fig, struct('undoPush', @undoPush, 'undoPop', @undoPop, 'refreshDisplay', @refreshDisplay, 'setStatus', @setStatus));
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onUndoFilters — delegates to emViewer.filterOps
    % ════════════════════════════════════════════════════════════════════
    function onUndoFilters(~, ~)
        appData = emViewer.filterOps('undoFilters', appData, fig, struct('undoPush', @undoPush, 'undoPop', @undoPop, 'refreshDisplay', @refreshDisplay, 'setStatus', @setStatus));
    end

    % ════════════════════════════════════════════════════════════════════
    %  DISPATCHER: onExportAction — All export / save callbacks
    %  Collapses onSaveImage, onSaveCrop, saveCroppedRegion,
    %  onExportWithOverlays, onBatchExport, onCreateGIF, doCreateGIF,
    %  onCopyClipboard, onBatchCrop, onJournalExport into one nested
    %  function to stay within FermiViewer's parser-complexity ceiling.
    % ════════════════════════════════════════════════════════════════════
    function onExportAction(action, varargin)
        switch action
            case 'saveCrop'
                if appData.activeIdx < 1 || isempty(appData.displayImg), return; end
                startRectCapture('savecrop');
            case 'batchCrop'
                if numel(appData.images) < 2 || isempty(appData.displayImg), return; end
                setStatus('Draw crop rectangle on current image... (Esc to cancel)');
                startRectCapture('batchcrop');
            case 'createGIF'
                if numel(appData.images) < 2, return; end
                buildGIFDialog();
            otherwise
                ctx = struct( ...
                    'fig', fig, 'ax', ax, 'appData', appData, ...
                    'sldLowValue', sldLow.Value, ...
                    'sldHighValue', sldHigh.Value, ...
                    'cmapName', ddColormap.Value, ...
                    'exportDPI', ddExportDPI.Value, ...
                    'setStatus', @setStatus, ...
                    'applyContrast', @applyContrastPipeline, ...
                    'percentile', @imaging.percentile);
                emViewer.export(action, ctx, varargin{:});
        end
    end

    function buildGIFDialog()
        nImg = numel(appData.images);
        names = cell(1, nImg);
        for ni = 1:nImg
            [~, names{ni}] = fileparts(appData.images{ni}.metadata.source);
        end
        bc = struct('primary', BTN_PRIMARY, 'tool', BTN_TOOL, 'fg', BTN_FG);
        emViewer.export.buildGIFDialog(names, bc, ...
            @(dlg, lb, ef, dd, cb, dc) onExportAction('doCreateGIF', dlg, lb, ef, dd, cb, dc));
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onZoomBox — Draw rectangle or fixed-dimension zoom
    % ════════════════════════════════════════════════════════════════════
    function onZoomBox(~, ~, mode)
        if appData.activeIdx < 1 || isempty(appData.displayImg)
            return;
        end
        if nargin >= 3 && strcmp(mode, 'dims')
            imgI = appData.images{appData.activeIdx}.metadata.parserSpecific.imageData;
            [H, W] = size(appData.rawPixels);
            ps = NaN; pu = 'px';
            if imgI.calibrated && ~isnan(imgI.pixelSize)
                ps = imgI.pixelSize; pu = char(imgI.pixelUnit);
            end
            emViewer.zoomToDimensions(fig, ax, H, W, ps, pu, @setStatus);
        else
            startRectCapture('zoom');
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onDragModeToggle — Top-row icon toggle for drag behaviour
    %  When Value=true,  dragging on the axes box-zooms (the previous
    %    default behaviour).
    %  When Value=false, dragging marquee-selects measurements and
    %    annotations whose anchors fall inside the box.
    % ════════════════════════════════════════════════════════════════════
    function onDragModeToggle(src, ~, mode)
    %ONDRAGMODETOGGLE  Unified handler for zoom/pan toolbar toggles.
    %   mode='zoom' or mode='pan'. Ensures mutual exclusivity.
        val = logical(src.Value);
        btns = appData.transformToolbarBtns;
        if strcmp(mode, 'zoom')
            appData.zoomMode = val;
            if val
                appData.panMode = false;
                if numel(btns) >= 6 && isvalid(btns(6)), btns(6).Value = false; end
                fig.Pointer = 'arrow';
                setStatus('Drag to zoom into a region. Toggle off for marquee-select.');
            else
                setStatus('Drag to marquee-select items. Toggle on for box-zoom.');
            end
        else
            appData.panMode = val;
            if numel(btns) >= 6 && isvalid(btns(6)), btns(6).Value = val; end
            if val
                appData.zoomMode = false;
                if numel(btns) >= 5 && isvalid(btns(5)), btns(5).Value = false; end
                fig.Pointer = 'hand';
                setStatus('Drag to pan. Middle-drag always pans regardless of mode.');
            else
                fig.Pointer = 'arrow';
                setStatus('Pan mode off. Drag to marquee-select items.');
            end
        end
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
            case 'rectROI'
                setStatus('Click first corner of Rect ROI... (Esc to cancel)');
            case 'batchcrop'
                setStatus('Click first corner of batch crop region... (Esc to cancel)');
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onRectClick — Handle clicks during rectangle selection
    % ════════════════════════════════════════════════════════════════════
    function onRectClick(~, ~)
        appData = emViewer.captureDispatch('rectClick', appData, buildCaptureCtx());
    end

    % updateRectPreview is now inlined in +emViewer/captureDispatch.m

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: executeRectROI — Draw persistent rectangle ROI + stats
    %  Registers the ROI as a measurement record so it can be clicked to
    %  select, deleted via the Delete key or marquee, and removed by
    %  Clear All alongside distance/profile/polyline measurements.
    % ════════════════════════════════════════════════════════════════════
    function executeRectROI(xMin, xMax, yMin, yMax)
        appData = emViewer.captureDispatch('rectROI', appData, buildCaptureCtx(), ...
            xMin, xMax, yMin, yMax);
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: refreshDisplay — wrapper → emViewer.displayHelpers
    % ════════════════════════════════════════════════════════════════════
    function adOut = refreshDisplay(adIn)
        if nargin >= 1, appData = adIn; end
        appData = emViewer.displayHelpers('refresh', appData, buildDisplayCtx());
        adOut = appData;
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
        % ── wrapper: delegates to emViewer.prepareDisplayBuffer ──────────
        if nargin < 1, pushToImage = false; end
        ui_ = struct('ax', ax, 'sldLow', sldLow, 'sldHigh', sldHigh);
        cb_ = struct('applyContrastPipeline', @applyContrastPipeline);
        appData = emViewer.prepareDisplayBuffer(appData, ui_, pushToImage, cb_);
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: updateHistogram — delegates to emViewer.histogramOps
    % ════════════════════════════════════════════════════════════════════
    function updateHistogram()
        [ui__, cb__] = buildContrastCtx();
        emViewer.histogramOps('update', histAx, appData, ui__, cb__);
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onHistAxesClick — delegates to emViewer.histogramOps
    % ════════════════════════════════════════════════════════════════════
    function onHistAxesClick()
        [ui__, cb__] = buildContrastCtx();
        emViewer.histogramOps('click', histAx, appData, ui__, cb__);
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: startHistDrag — Drag a histogram contrast handle
    %  Kept inline because the doubly-nested drag callbacks need direct
    %  closure access to sldLow/sldHigh/fig/histAx.
    % ════════════════════════════════════════════════════════════════════
    function startHistDrag(which)
        origMotionFcn  = fig.WindowButtonMotionFcn;
        origReleaseFcn = fig.WindowButtonUpFcn;
        fig.Pointer = 'left';
        fig.WindowButtonMotionFcn = @histDragMotion;
        fig.WindowButtonUpFcn    = @histDragRelease;

        bcStartFigPt = fig.CurrentPoint;
        bcStartLo    = sldLow.Value;
        bcStartHi    = sldHigh.Value;

        function histDragMotion(~, ~)
            cp_ = histAx.CurrentPoint;
            newVal = cp_(1,1);
            lims_ = sldLow.Limits;
            gap = (lims_(2) - lims_(1)) * 0.001;
            newVal = max(lims_(1), min(lims_(2), newVal));
            if strcmp(which, 'lo')
                sldLow.Value = min(newVal, sldHigh.Value - gap);
                onContrastChanged([], []);
            elseif strcmp(which, 'hi')
                sldHigh.Value = max(newVal, sldLow.Value + gap);
                onContrastChanged([], []);
            elseif strcmp(which, 'bc')
                axPos = getpixelposition(histAx, true);
                if axPos(3) <= 0 || axPos(4) <= 0, return; end
                curPt = fig.CurrentPoint;
                dxPx = curPt(1) - bcStartFigPt(1);
                dyPx = curPt(2) - bcStartFigPt(2);
                origSpan  = max(bcStartHi - bcStartLo, gap);
                dataPerPx = (lims_(2) - lims_(1)) / axPos(3);
                shift     = dxPx * dataPerPx;
                scale     = exp(-0.005 * dyPx);
                newSpan = max(gap, min(lims_(2) - lims_(1), origSpan * scale));
                centre  = bcStartLo + origSpan/2 + shift;
                newLo   = centre - newSpan/2;
                newHi   = centre + newSpan/2;
                if newLo < lims_(1)
                    newLo = lims_(1); newHi = newLo + newSpan;
                end
                if newHi > lims_(2)
                    newHi = lims_(2); newLo = newHi - newSpan;
                end
                sldLow.Value  = newLo;
                sldHigh.Value = newHi;
                onContrastChanged([], []);
            else
                lo_ = sldLow.Value;
                hi_ = sldHigh.Value;
                if hi_ <= lo_, return; end
                t = (newVal - lo_) / (hi_ - lo_);
                t = max(0.01, min(0.99, t));
                newGamma = log(0.5) / log(t);
                newGamma = max(sldGamma.Limits(1), min(sldGamma.Limits(2), newGamma));
                sldGamma.Value = newGamma;
                onGammaChanged([], []);
            end
        end

        function histDragRelease(~, ~)
            fig.WindowButtonMotionFcn = origMotionFcn;
            fig.WindowButtonUpFcn    = origReleaseFcn;
            fig.Pointer = 'arrow';
        end
    end

    function onToggleHistLog(src)
    %ONTOGGLEHISTLOG  Toggle log-scale Y-axis on the histogram.
        [ui__, cb__] = buildContrastCtx();
        appData = emViewer.contrastOps('toggleHistLog', appData, ui__, cb__, src);
    end

    function setHistLogAPI(tf)
        [ui__, cb__] = buildContrastCtx();
        appData = emViewer.contrastOps('setHistLog', appData, ui__, cb__, tf);
    end

    function onScrollWheelContrast(~, evt)
    %ONSCROLLWHEELCONTRAST  Scroll-wheel over histogram adjusts contrast window.
        [ui__, cb__] = buildContrastCtx();
        appData = emViewer.contrastOps('scrollWheelContrast', appData, ui__, cb__, evt);
    end

    % ════════════════════════════════════════════════════════════════════
    %  API: setContrastAPI — delegates to emViewer.contrastOps
    % ════════════════════════════════════════════════════════════════════
    function setContrastAPI(lo, hi)
    %SETCONTRASTAPI  Set Low/High contrast sliders and refresh display.
        [ui__, cb__] = buildContrastCtx();
        appData = emViewer.contrastOps('setContrast', appData, ui__, cb__, lo, hi);
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
        if appData.activeIdx >= 1 && appData.activeIdx <= numel(appData.images)
            taMetadata.Value = emViewer.display.formatMetadata(appData.images{appData.activeIdx});
        else
            taMetadata.Value = {'(no image loaded)'};
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  API: applyFilterAPI — delegates to emViewer.filterOps
    % ════════════════════════════════════════════════════════════════════
    function applyFilterAPI(type, params)
    %APPLYFILTERAPI  Apply a named filter programmatically.
        appData = emViewer.filterOps('applyFilter', appData, fig, struct('undoPush', @undoPush, 'undoPop', @undoPop, 'refreshDisplay', @refreshDisplay, 'setStatus', @setStatus), type, params);
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

    function onScaleBarColorChange(src, ~)
        names  = {'White', 'Cyan', 'Yellow', 'Red', 'Black'};
        colors = {[1 1 1], OVERLAY_COLOR, [1 1 0], [1 0 0], [0 0 0]};
        bgs    = {[0.25 0.25 0.25], [0.15 0.15 0.15], [0.15 0.15 0.15], ...
                  [0.15 0.15 0.15], [0.85 0.85 0.85]};

        idx = find(strcmp(names, src.Value), 1);
        if isempty(idx), idx = 1; end   % defensive fallback to White

        appData.scaleBarColor           = colors{idx};
        ddScaleBarColor.FontColor       = colors{idx};
        ddScaleBarColor.BackgroundColor = bgs{idx};

        if cbScaleBar.Value
            rebuildScaleBar();
        end
        appData.calibWS.model.setScaleBarColor(colors{idx});
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
    function adOut = rebuildScaleBar(adIn)
        if nargin >= 1, appData = adIn; end
        ctx = buildScaleBarCtx();
        appData = emViewer.scaleBarOps('rebuild', appData, ctx);
        adOut = appData;
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
    %  CALLBACK: onBoxProfile — Prompt for width, then two-click capture
    %  of a rotated integration rectangle. The profile is averaged across
    %  the width and plotted along the length. Reuses the existing
    %  runWidthAveragedProfile engine; only the UX is new.
    % ════════════════════════════════════════════════════════════════════
    function onBoxProfile(~, ~)
        if appData.activeIdx < 1 || isempty(appData.displayImg)
            return;
        end
        defaultW = max(2, spnProfileWidth.Value);
        answer = inputdlg({'Integration width (px):'}, ...
            'Box Profile', [1 40], {num2str(defaultW)});
        if isempty(answer), return; end
        w = str2double(answer{1});
        if ~isfinite(w) || w < 2
            uialert(fig, 'Width must be a number ≥ 2.', 'Invalid width', 'Icon', 'warning');
            return;
        end
        appData.boxProfileWidth = round(w);
        spnProfileWidth.Value = min(appData.boxProfileWidth, spnProfileWidth.Limits(2));
        startTwoClickCapture('boxprofile');
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
        appData = emViewer.captureDispatch('captureClick', appData, buildCaptureCtx());
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onKeyPress — Escape, arrow navigation, Tab (compare)
    % ════════════════════════════════════════════════════════════════════
    function onKeyPress(~, evt)
        cb = struct( ...
            'cancelCapture',            @cancelCapture, ...
            'setStatus',                @setStatus, ...
            'onAnnotationAction',       @onAnnotationAction, ...
            'deleteSelectedMeasurement',@deleteSelectedMeasurement, ...
            'updateCompareHighlight',   @updateCompareHighlight, ...
            'syncCompareZoom',          @syncCompareZoom, ...
            'displayCompareImage',      @displayCompareImage, ...
            'setComparePanelToggle',    @kpCompareState, ...
            'setCompareIdxL',           @(idx) kpCompareState('setIdxL', idx), ...
            'setCompareIdxR',           @(idx) kpCompareState('setIdxR', idx), ...
            'onSessionSave',            @onSessionSave, ...
            'onSessionLoad',            @onSessionLoad, ...
            'onOpenFiles',              @onOpenFiles, ...
            'onExportAction',           @onExportAction, ...
            'onUndoFilters',            @onUndoFilters, ...
            'refreshState',             @refreshState, ...
            'onAutoContrast',           @onAutoContrast, ...
            'onZoomFit',                @onZoomFit, ...
            'onZoomBox',                @onZoomBox, ...
            'onDragModeToggle',         @onDragModeToggle, ...
            'setActiveIdxAPI',          @setActiveIdxAPI);
        emViewer.onKeyPress(evt, ax, axL, axR, appData, cb);
    end

    function kpCompareState(action, idx)
        % Dispatcher for the three compare-state mutations used by onKeyPress.
        % action: 'toggle' | 'setIdxL' | 'setIdxR'
        if nargin < 2, action = 'toggle'; end
        switch action
            case 'toggle'
                if appData.compareActivePanel == 'L'
                    appData.compareActivePanel = 'R';
                else
                    appData.compareActivePanel = 'L';
                end
                updateCompareHighlight();
            case 'setIdxL'
                appData.compareIdxL = idx;
                displayCompareImage('L');
            case 'setIdxR'
                appData.compareIdxR = idx;
                displayCompareImage('R');
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
        ctx = buildCompareCtx();
        [appData, h] = emViewer.compareDispatch('enter', appData, ctx);
        if ~isempty(h.axL)
            % Assign closure vars BEFORE display calls (closures capture by ref)
            axL = h.axL; axR = h.axR; compareGL = h.compareGL;
            axGL = []; ax = [];
            displayCompareImage('L');
            displayCompareImage('R');
            updateCompareHighlight();
            setToolsEnabled('off');
            setStatus('Compare mode — click or Tab to switch panel, arrows to scroll');
        end
    end

    function exitCompareMode()
        % Package handles appData cleanup (compareMode, scalebars, delete compareGL)
        appData = emViewer.compareDispatch('exit', appData, buildCompareCtx());
        compareGL = []; axL = []; axR = [];

        % Rebuild single-view panel (toolbar + axes + stack navigator)
        rcIconDir = fullfile(fileparts(mfilename('fullpath')), 'icons', 'fermiviewer');
        rcCbs = struct( ...
            'onRotateFlip',     @onRotateFlip, ...
            'onDragModeToggle', @onDragModeToggle, ...
            'onResetZoom',      @onResetZoom, ...
            'setActiveIdxAPI',  @setActiveIdxAPI, ...
            'getActiveIdxAPI',  @getActiveIdxAPI, ...
            'onCropImage',      @onCropImage, ...
            'onAnnotUndo',      @() onAnnotationAction('undoLast'), ...
            'onStackNav',       @onStackNav, ...
            'onStackSlider',    @onStackSlider, ...
            'onStackMIP',       @onStackMIP);
        rcTheme = struct('btnTool', BTN_TOOL, 'btnFg', BTN_FG);
        rcModes = struct('zoomMode', appData.zoomMode, 'panMode', appData.panMode);
        pnl = emViewer.buildSingleViewPanel(axPanel, rcIconDir, rcCbs, rcTheme, rcModes);

        axGL  = pnl.axGL;
        ax    = pnl.ax;
        stackGL       = pnl.stackGL;
        btnStackPrev  = pnl.btnStackPrev;
        btnStackNext  = pnl.btnStackNext;
        sldStackFrame = pnl.sldStackFrame;
        btnStackMIP   = pnl.btnStackMIP;
        lblStackFrame = pnl.lblStackFrame;
        appData.transformToolbarBtns = pnl.transformToolbarBtns;
        appData.toolbarIconPaths     = pnl.toolbarIconPaths;

        fig.WindowButtonMotionFcn = @onMouseMotion;
        displayImage();
    end

    function displayCompareImage(panel)
    %DISPLAYCOMPAREIMAGE  Render an image into the left or right compare axes.
        if panel == 'L'
            targetAx = axL;  idx = appData.compareIdxL;  sbField = 'scalebarL';
        else
            targetAx = axR;  idx = appData.compareIdxR;  sbField = 'scalebarR';
        end
        if isempty(targetAx) || ~isvalid(targetAx), return; end
        if idx < 1 || idx > numel(appData.images), return; end

        panelCopy = panel;
        clickCb = @(~,~) compareAxesActivate(panelCopy);

        deleteScaleBarHandle(appData.overlays.(sbField));
        appData.overlays.(sbField) = [];

        hB = emViewer.compareImage(targetAx, appData.images{idx}, idx, ...
            cbScaleBar.Value, appData.scaleBarColor, spnScaleBarFont.Value, clickCb);
        if ~isempty(hB)
            makeScaleBarDraggable(hB);
            appData.overlays.(sbField) = hB;
        end
    end

    function compareAxesActivate(panel)
    %COMPAREAXESACTIVATE  Switch active panel when user clicks on an image.
        if ~appData.compareMode, return; end
        if appData.compareActivePanel ~= panel
            appData.compareActivePanel = panel;
            updateCompareHighlight();
        end
    end

    function syncCompareZoom(sourceAx, targetAx2)
        emViewer.compareDispatch('syncZoom', appData, buildCompareCtx(), sourceAx, targetAx2);
    end

    function updateCompareHighlight()
        emViewer.compareDispatch('updateHighlight', appData, buildCompareCtx());
    end

    function setToolsEnabled(state)
    %SETTOOLSENABLED  Enable or disable measurement/processing/annotation buttons.
        % ── wrapper: delegates to emViewer.setToolsEnabled ───────────────
        ui_ = struct( ...
            'btnLineProfile', btnLineProfile, 'btnBoxProfile', btnBoxProfile, ...
            'btnDistance', btnDistance, 'btnAngle', btnAngle, ...
            'btnExportProfile', btnExportProfile, ...
            'btnClearOverlays', btnClearOverlays, 'btnRemoveMeas', btnRemoveMeas, ...
            'btnRotCW', btnRotCW, 'btnRotCCW', btnRotCCW, ...
            'btnFlipH', btnFlipH, 'btnFlipV', btnFlipV, ...
            'btnGaussian', btnGaussian, 'btnMedian', btnMedian, ...
            'btnShowFFT', btnShowFFT, 'btnCLAHE', btnCLAHE, ...
            'btnUndoFilters', btnUndoFilters, ...
            'btnZoomBox', btnZoomBox, 'btnZoomDims', btnZoomDims, ...
            'btnResetZoom', btnResetZoom, 'btnCropImage', btnCropImage, ...
            'btnSaveCrop', btnSaveCrop, 'btnSaveImage', btnSaveImage, ...
            'btnSetPixelSize', btnSetPixelSize, 'btnFFTMask', btnFFTMask, ...
            'btnParticles', btnParticles, 'btnAlignStack', btnAlignStack, ...
            'btnColorOverlay', btnColorOverlay, 'btnExportOverlays', btnExportOverlays, ...
            'btnBatchExport', btnBatchExport, 'btnCreateGIF', btnCreateGIF, ...
            'btnCopyClipboard', btnCopyClipboard, ...
            'cbMinimap', cbMinimap, 'cbPixelInspector', cbPixelInspector, ...
            'btnLiveThresh', btnLiveThresh, 'btnImgMath', btnImgMath, ...
            'btnWatershed', btnWatershed, 'btnBatchCrop', btnBatchCrop, ...
            'btnMontage', btnMontage, 'btnSessionSave', btnSessionSave, ...
            'btnGrid', btnGrid, 'btnExportMeasure', btnExportMeasure, ...
            'btnDiffRings', btnDiffRings, 'btnROIManager', btnROIManager, ...
            'btnCalibrateBar', btnCalibrateBar, ...
            'btnBatchRename', btnBatchRename, 'btnRenameSelected', btnRenameSelected, ...
            'btnPlaceAnnot', btnPlaceAnnot, 'btnClearAnnot', btnClearAnnot, ...
            'btnUndoAnnot', btnUndoAnnot, 'ddAnnotColor', ddAnnotColor, ...
            'cbColorbar', cbColorbar, ...
            'btnDSpacing', btnDSpacing, 'spnProfileWidth', spnProfileWidth, ...
            'ddROIShape', ddROIShape, 'btnDrawROI', btnDrawROI, ...
            'btnInvertImg', btnInvertImg, ...
            'btnSharpen', btnSharpen, 'btnBinImage', btnBinImage, ...
            'btnMorphOp', btnMorphOp, 'btnButterworth', btnButterworth, ...
            'btnRadialProfile', btnRadialProfile, 'btnAzIntegrate', btnAzIntegrate, ...
            'btnSurfacePlot', btnSurfacePlot, 'btnBatchConvert', btnBatchConvert, ...
            'btnCustomCmap', btnCustomCmap, ...
            'btnPlaceArrow', btnPlaceArrow, 'btnPlaceLine', btnPlaceLine, ...
            'btnPlaceRect', btnPlaceRect, 'btnPlaceCircle', btnPlaceCircle, ...
            'btnPlaneLevel', btnPlaneLevel, 'btnRoughness', btnRoughness, ...
            'btnInterfaceFit', btnInterfaceFit, 'btnMultiOtsu', btnMultiOtsu, ...
            'btnLatticeMeasure', btnLatticeMeasure, 'btnGPA', btnGPA, ...
            'btnCTF', btnCTF, 'btnDefectCount', btnDefectCount, ...
            'btnBackProject', btnBackProject, 'btnFigureBuilder', btnFigureBuilder, ...
            'btnJournalExport', btnJournalExport, 'btnCalibColorbar', btnCalibColorbar, ...
            'btnMacroRecord', btnMacroRecord, 'btnFlickerCompare', btnFlickerCompare, ...
            'btn3DSurface', btn3DSurface, 'btnLiveFFT', btnLiveFFT, ...
            'btnTemplateMatch', btnTemplateMatch, 'btnStitchImages', btnStitchImages, ...
            'btnNoiseEstimate', btnNoiseEstimate, 'btnPubPresets', btnPubPresets, ...
            'btnColormapPreset', btnColormapPreset, 'btnMeasStats', btnMeasStats, ...
            'btnBatchMeas', btnBatchMeas, 'btnExportToDP', btnExportToDP, ...
            'spnMeasLabelFont', spnMeasLabelFont, ...
            'ddMeasSymbol', ddMeasSymbol, 'ddMeasColor', ddMeasColor, ...
            'btnAddChannel', btnAddChannel, 'btnRemoveChannel', btnRemoveChannel, ...
            'ddChannelColor', ddChannelColor, 'cbChannelVisible', cbChannelVisible, ...
            'sldChannelIntensity', sldChannelIntensity, 'efChannelLabel', efChannelLabel, ...
            'btnExportComposite', btnExportComposite, ...
            'btnAssignElements', btnAssignElements, 'btnQuantifyCL', btnQuantifyCL, ...
            'btnCompositionProfile', btnCompositionProfile, 'btnROIComposition', btnROIComposition, ...
            'btnEnterEELS', btnEnterEELS, 'btnEELSFitBG', btnEELSFitBG, ...
            'ddEELSMethod', ddEELSMethod, 'chkShowEdges', chkShowEdges, ...
            'ddEdgeFilter', ddEdgeFilter, 'btnEELSExtractMap', btnEELSExtractMap, ...
            'btnEELSThickness', btnEELSThickness, 'btnEELSAlignZLP', btnEELSAlignZLP, ...
            'btnEELSDeconvolve', btnEELSDeconvolve, 'btnEELSELNES', btnEELSELNES, ...
            'btnEELSKK', btnEELSKK, 'btnEELSNavigate', btnEELSNavigate, ...
            'btnEELSSVD', btnEELSSVD, ...
            'btnAutoDetectSpots', btnAutoDetectSpots, 'btnClickDiffSpot', btnClickDiffSpot, ...
            'btnClearDiffSpots', btnClearDiffSpots, 'ddAccVoltage', ddAccVoltage, ...
            'btnMatchDiffraction', btnMatchDiffraction, 'btnOverlayDiffRings', btnOverlayDiffRings, ...
            'btnSimDiffraction', btnSimDiffraction, 'btnVDF', btnVDF, ...
            'btnQuantifyZAF', btnQuantifyZAF);
        emViewer.setToolsEnabled(state, ui_, appData);
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
            % Expand to the section's full open height. toolsPanel has
            % Scrollable='on', so overflow beyond the visible panel
            % scrolls — capping the section would silently clip its
            % inner grid and hide controls (e.g. the Line color row).
            toolsGL.RowHeight{sect.panelRow} = sect.openHeight;
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
    %ONIDLEMOUSEDOWN  Figure-level mouse-down in idle mode -- delegates to emViewer.mouseOps.
        appData = emViewer.mouseOps('idleDown', appData, buildMouseCtx());
    end

    % ════════════════════════════════════════════════════════════════════
    %  BOX-ZOOM: click-drag rubber-band on image axes, double-click reset
    % ════════════════════════════════════════════════════════════════════
    function onAxesMouseDown(~, ~)
    %ONAXESMOUSEDOWN  Image-axes ButtonDownFcn -- delegates to emViewer.mouseOps.
        appData = emViewer.mouseOps('axesDown', appData, buildMouseCtx());
    end

    function onBoxZoomDrag(~, ~)
        appData = emViewer.captureDispatch('boxZoomDrag', appData, buildCaptureCtx());
    end

    function onBoxZoomRelease(~, ~)
        appData = emViewer.captureDispatch('boxZoomRelease', appData, buildCaptureCtx());
    end

    % ════════════════════════════════════════════════════════════════════
    %  CONTEXT MENUS: right-click on image, thumbnail list, scale bar
    % ════════════════════════════════════════════════════════════════════
    function buildContextMenus()
    %BUILDCONTEXTMENUS  Attach right-click menus -- delegates to emViewer.mouseOps.
        appData = emViewer.mouseOps('buildContextMenus', appData, buildMouseCtx());
    end

    function attachImageContextMenu()
    %ATTACHIMAGECONTEXTMENU  Bind the image context menu to the current
    %  image HG object. Called from displayImage / undoPop / FFT-mask apply
    %  etc. because imagesc creates a fresh object each time and Mac
    %  uifigure delivers right-clicks to the image, not the axes wrapper.
        if isempty(appData.cmImage) || ~isvalid(appData.cmImage), return; end
        if ~isempty(appData.imgHandle) && isvalid(appData.imgHandle)
            appData.imgHandle.ContextMenu = appData.cmImage;
            appData.imgHandle.ButtonDownFcn = @onAxesMouseDown;
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
        % Quick toggle flips to the opposite of the currently-shown theme.
        % This is an explicit user action, so it also breaks out of 'Auto'
        % mode — the new pref is the concrete choice the user just picked.
        appData.darkMode = ~appData.darkMode;
        if appData.darkMode
            appData.themePref = 'Dark';
        else
            appData.themePref = 'Light';
        end
        applyTheme();
        % Persist so BosonPlotter and the next FermiViewer launch start
        % in the same mode. Best-effort — silent on prefdir write fail.
        try
            bosonPlotter.themePref('write', appData.themePref);
        catch
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  SHORTCUTS: keyboard cheat-sheet dialog
    % ════════════════════════════════════════════════════════════════════
    function onShowEMShortcuts(~, ~)
        uialert(fig, emViewer.shortcutsText(), 'Keyboard Shortcuts', 'Icon', 'info');
    end

    function applyTheme()
        % Delegate to package function — builds ui struct from closure handles.
        ui_.fig              = fig;
        ui_.ax               = ax;
        ui_.histAx           = histAx;
        ui_.listPanel        = listPanel;
        ui_.toolsPanel       = toolsPanel;
        ui_.pnlContrast      = pnlContrast;
        ui_.pnlHistogram     = pnlHistogram;
        ui_.pnlMeasure       = pnlMeasure;
        ui_.pnlProcess       = pnlProcess;
        ui_.pnlExport        = pnlExport;
        ui_.pnlAnnot         = pnlAnnot;
        ui_.pnlEDS           = pnlEDS;
        ui_.btnThemeToggle   = btnThemeToggle;
        ui_.btnContrastHeader  = btnContrastHeader;
        ui_.btnHistogramHeader = btnHistogramHeader;
        ui_.btnMeasureHeader   = btnMeasureHeader;
        ui_.btnProcessHeader   = btnProcessHeader;
        ui_.btnExportHeader    = btnExportHeader;
        ui_.btnAnnotHeader     = btnAnnotHeader;
        ui_.btnEDSHeader       = btnEDSHeader;
        ui_.btnEELSHeader      = btnEELSHeader;
        ui_.btnDiffHeader      = btnDiffHeader;
        ui_.btnMetaHeader      = btnMetaHeader;
        ui_.lblStatusDims    = lblStatusDims;
        ui_.lblStatusBits    = lblStatusBits;
        ui_.lblStatusPixSize = lblStatusPixSize;
        ui_.lblStatusMouse   = lblStatusMouse;
        ui_.lblFilename      = lblFilename;
        ui_.lblRename        = lblRename;
        ui_.lblDPI           = lblDPI;
        ui_.lblPubHeader     = lblPubHeader;
        ui_.lblUtilHeader    = lblUtilHeader;
        ui_.taMetadata       = taMetadata;
        ui_.efRenameBase     = efRenameBase;
        ui_.efAnnotText      = efAnnotText;
        ui_.lbImages         = lbImages;
        ui_.rootGL           = rootGL;
        ui_.mainGL           = mainGL;
        ui_.toolbarGL        = toolbarGL;
        ui_.statusGL         = statusGL;
        ui_.listGL           = listGL;
        ui_.toolsGL          = toolsGL;
        ui_.contrastInnerGL  = contrastInnerGL;
        ui_.measureInnerGL   = measureInnerGL;
        ui_.processInnerGL   = processInnerGL;
        ui_.exportInnerGL    = exportInnerGL;
        ui_.annotInnerGL     = annotInnerGL;
        ui_.edsInnerGL       = edsInnerGL;
        ui_.processTabGrids  = processTabGrids;
        emViewer.applyTheme(ui_, appData);
    end

    % ════════════════════════════════════════════════════════════════════
    %  ANNOTATIONS: colour selection, place, clear, API
    % ════════════════════════════════════════════════════════════════════
    function onAnnotColorChange(~, colorRGB)
        % Called by buildAnnotationsPanel after it updates the dropdown
        % visual appearance. colorRGB is the resolved [R G B] triple.
        appData.annotationColor = colorRGB;
    end

    function onAnnotationAction(action, varargin)
        ui_.ax           = ax;
        ui_.fig          = fig;
        ui_.efAnnotText  = efAnnotText;
        ui_.spnAnnotFont = spnAnnotFont;
        cb_.setAppData          = @(ad) setAppDataFn(ad);
        cb_.setStatus           = @setStatus;
        cb_.cancelCapture       = @cancelCapture;
        cb_.placeAnnotationAt   = @placeAnnotationAt;
        cb_.finishCapture       = @finishCapture;
        cb_.deleteAnnotHandles  = @deleteAnnotHandles;
        cb_.highlightAnnotation = @highlightAnnotation;
        cb_.deselectMeasurement = @deselectMeasurement;
        cb_.dispatchSelf        = @onAnnotationAction;
        emViewer.onAnnotationAction(action, appData, ui_, cb_, varargin{:});
    end

    function setAppDataFn(newAppData)
        appData = newAppData;
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
        appData.annotWorkshop.sync(appData.overlays.textAnnotations);
        attachAnnotContextMenu(annot, numel(appData.overlays.textAnnotations));
    end

    function placeAnnotationAPI(x, y, str, fontSize, color)
    %PLACEANNOTATIONAPI  Non-interactive annotation placement for testing.
        if appData.activeIdx < 1 || isempty(appData.displayImg)
            return;
        end
        placeAnnotationAt(x, y, str, fontSize, color);
    end

    function deleteAnnotHandles(a)
        emViewer.annotation.deleteAnnotHandles(a);
    end

    function highlightAnnotation(a, on)
        emViewer.annotation.highlightAnnotation(a, on);
    end

    function attachAnnotContextMenu(a, idx)
    %ATTACHANNOTCONTEXTMENU  Build and attach a right-click context menu.
        cm = uicontextmenu(fig);
        colors = struct('White',[1 1 1], 'Cyan',[0 1 1], 'Yellow',[1 1 0], ...
                        'Red',[1 0 0], 'Green',[0 0.8 0], 'Blue',[0 0.4 1], 'Black',[0 0 0]);
        cmColor = uimenu(cm, 'Text', 'Color');
        cNames = fieldnames(colors);
        for ck = 1:numel(cNames)
            cn = cNames{ck};
            uimenu(cmColor, 'Text', cn, ...
                'MenuSelectedFcn', @(~,~) onAnnotationAction('setColor', idx, colors.(cn)));
        end
        if isfield(a, 'hText') && ~isempty(a.hText)
            uimenu(cm, 'Text', 'Font size', ...
                'MenuSelectedFcn', @(~,~) onAnnotationAction('setFontSize', idx));
            uimenu(cm, 'Text', 'Edit text', ...
                'MenuSelectedFcn', @(~,~) onAnnotationAction('editText', idx));
        end
        uimenu(cm, 'Text', 'Delete', 'Separator', 'on', ...
            'MenuSelectedFcn', @(~,~) onAnnotationAction('deleteOne', idx));

        for fk = {'hText','hLine','hHead','hRect','hCircle'}
            fn = fk{1};
            if isfield(a, fn) && ~isempty(a.(fn)) && isvalid(a.(fn))
                a.(fn).ContextMenu = cm;
                a.(fn).HitTest = 'on';
                a.(fn).PickableParts = 'all';
                a.(fn).ButtonDownFcn = @(~,~) onAnnotationAction('startDrag', idx);
            end
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: startTwoClickCapture — Enter two-click capture mode
    % ════════════════════════════════════════════════════════════════════
    function startTwoClickCapture(mode)
        appData = emViewer.captureDispatch('startCapture', appData, buildCaptureCtx(), mode);
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
    %  CTX BUILDERS: capture and compare dispatchers
    % ════════════════════════════════════════════════════════════════════
    function ctx = buildCaptureCtx()
    %BUILDCAPTURECTX  Build context struct for emViewer.captureDispatch.
        ctx.ax           = ax;
        ctx.fig          = fig;
        ctx.OVERLAY_COLOR = OVERLAY_COLOR;
        ctx.ui.ddMeasColor  = ddMeasColor;
        ctx.ui.lblSpotCount = lblSpotCount;
        ctx.cb.setStatus                = @setStatus;
        ctx.cb.undoPush                 = @undoPush;
        ctx.cb.finishCapture            = @finishCapture;
        ctx.cb.cancelCapture            = @cancelCapture;
        ctx.cb.refreshDisplay           = @refreshDisplay;
        ctx.cb.onMouseMotion            = @onMouseMotion;
        ctx.cb.onIdleMouseDown          = @onIdleMouseDown;
        ctx.cb.onCaptureClick           = @onCaptureClick;
        ctx.cb.onExportAction           = @onExportAction;
        ctx.cb.applyBatchCrop           = @applyBatchCrop;
        ctx.cb.applyMarqueeSelection    = @applyMarqueeSelection;
        ctx.cb.selectMeasurement        = @selectMeasurement;
        ctx.cb.executeMeasureProfile    = @executeMeasureProfile;
        ctx.cb.executeMeasureDistance   = @executeMeasureDistance;
        ctx.cb.executeBoxProfile        = @executeBoxProfile;
        ctx.cb.executeScaleBarCalibration = @executeScaleBarCalibration;
        ctx.cb.executeDSpacing          = @executeDSpacing;
        ctx.cb.executeEllipseROI        = @executeEllipseROI;
        ctx.cb.executeArrow             = @executeArrow;
        ctx.cb.executeAnnotLine         = @executeAnnotLine;
        ctx.cb.executeAnnotRect         = @executeAnnotRect;
        ctx.cb.executeAnnotCircle       = @executeAnnotCircle;
        ctx.cb.executeGPA               = @executeGPA;
        ctx.cb.onDiffractionAction      = @onDiffractionAction;
    end

    function ctx = buildCompareCtx()
    %BUILDCOMPARECTX  Build context struct for emViewer.compareDispatch.
        ctx.fig              = fig;
        ctx.axPanel          = axPanel;
        ctx.axGL             = axGL;
        ctx.axL              = axL;
        ctx.axR              = axR;
        ctx.compareGL        = compareGL;
        ctx.OVERLAY_COLOR    = OVERLAY_COLOR;
        ctx.compareLinkedZoom = compareLinkedZoom;
        ctx.toggleValue      = false;  % caller sets before dispatch
        ctx.ui.btnFlickerCompare = btnFlickerCompare;
        ctx.cb.setStatus         = @setStatus;
        ctx.cb.setToolsEnabled   = @setToolsEnabled;
        ctx.cb.clearAllOverlays  = @clearAllOverlays;
        ctx.cb.cancelCapture     = @cancelCapture;
        ctx.cb.onExitEDS         = @onExitEDS;
        ctx.cb.displayCompareImage = @displayCompareImage;
        ctx.cb.flickerTick       = @flickerTick;
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: executeMeasureProfile — Draw line and plot profile figure
    % ════════════════════════════════════════════════════════════════════
    function executeMeasureProfile(x1, y1, x2, y2)
        ctx = buildMeasCtx();
        appData = emViewer.measExecute('profile', appData, ctx, x1, y1, x2, y2);
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: executeBoxProfile — Rotated-rectangle integrated profile
    % ════════════════════════════════════════════════════════════════════
    function executeBoxProfile(x1, y1, x2, y2, width)
        ctx = buildMeasCtx();
        appData = emViewer.measExecute('boxProfile', appData, ctx, x1, y1, x2, y2, width);
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: executeMeasureDistance — Draw line and annotate distance
    % ════════════════════════════════════════════════════════════════════
    function executeMeasureDistance(x1, y1, x2, y2)
        ctx = buildMeasCtx();
        appData = emViewer.measExecute('distance', appData, ctx, x1, y1, x2, y2);
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: createEndpointMarker — Draggable marker for line endpoints
    % ════════════════════════════════════════════════════════════════════
    function hMark = createEndpointMarker(x, y, symType, symColor)
        if nargin < 3, symType  = 'circle'; end
        if nargin < 4, symColor = OVERLAY_COLOR; end
        [~, hMark] = emViewer.measExecute('endpointMarker', appData, buildMeasCtx(), ...
            x, y, symType, symColor);
    end

    function mrk = symTypeToMarker(sym)
        mrk = emViewer.meas.symToMarker(sym);
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: createDistanceLabel — Offset annotation with distance text
    % ════════════════════════════════════════════════════════════════════
    function hTxt = createDistanceLabel(x1, y1, x2, y2)
        [appData, hTxt] = emViewer.measExecute('distLabel', appData, buildMeasCtx(), ...
            x1, y1, x2, y2);
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: runProfile — Extract and display line profile
    % ════════════════════════════════════════════════════════════════════
    function runProfile(x1, y1, x2, y2)
        appData = emViewer.measExecute('runProfile', appData, buildMeasCtx(), x1, y1, x2, y2);
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: startEndpointDrag — Drag a line endpoint to update measurement
    %  Uses anonymous motion/release callbacks (no doubly-nested fns) to
    %  stay within FermiViewer's nested-function parser budget.
    % ════════════════════════════════════════════════════════════════════
    function startEndpointDrag(measIdx, whichEnd)
        if measIdx > numel(appData.overlays.measurements), return; end
        meas = appData.overlays.measurements{measIdx};
        if ~isvalid(meas.hLine), return; end
        selectMeasurement(measIdx);
        origMotionFcn  = fig.WindowButtonMotionFcn;
        origReleaseFcn = fig.WindowButtonUpFcn;
        fig.Pointer = 'crosshair';
        % Use cell wrapper so anonymous callbacks can mutate meas by ref
        measRef = {meas};
        fig.WindowButtonMotionFcn = @(~,~) endpointDragMotion( ...
            ax, appData, whichEnd, measRef);
        fig.WindowButtonUpFcn = @(~,~) endpointDragRelease( ...
            measIdx, whichEnd, measRef, origMotionFcn, origReleaseFcn);
    end

    function endpointDragMotion(targAx, ad, whichEnd, measRef)
        cp = targAx.CurrentPoint;
        nx = cp(1,1); ny = cp(1,2);
        if ~isempty(ad.displayImg)
            [H, W] = size(ad.filteredPixels);
            nx = max(0.5, min(W + 0.5, nx));
            ny = max(0.5, min(H + 0.5, ny));
        end
        m = measRef{1};
        if whichEnd == 1
            rTick = (m.hP1.XData(end) - m.hP1.XData(1)) / 2;
            m.hP1.XData = [nx-rTick, nx, nx+rTick];
            m.hP1.YData = [ny, ny, ny];
            m.hLine.XData(1) = nx; m.hLine.YData(1) = ny;
        else
            rTick = (m.hP2.XData(end) - m.hP2.XData(1)) / 2;
            m.hP2.XData = [nx-rTick, nx, nx+rTick];
            m.hP2.YData = [ny, ny, ny];
            m.hLine.XData(2) = nx; m.hLine.YData(2) = ny;
        end
        if ~isempty(m.hText) && isvalid(m.hText)
            x1d_ = m.hLine.XData(1); y1d_ = m.hLine.YData(1);
            x2d_ = m.hLine.XData(2); y2d_ = m.hLine.YData(2);
            mx_ = (x1d_+x2d_)/2; my_ = (y1d_+y2d_)/2;
            dx_ = x2d_-x1d_; dy_ = y2d_-y1d_;
            len_ = hypot(dx_, dy_);
            if len_ < eps, nx_ = 0; ny_ = -1;
            else
                nx_ = -dy_/len_; ny_ = dx_/len_;
                if ny_ > 0, nx_ = -nx_; ny_ = -ny_; end
            end
            lx_ = mx_+14*nx_; ly_ = my_+14*ny_;
            if ~isempty(ad.filteredPixels)
                [H_,W_] = size(ad.filteredPixels);
                if lx_<1||lx_>W_||ly_<1||ly_>H_
                    lx_ = mx_-14*nx_; ly_ = my_-14*ny_;
                end
            end
            m.hText.Position = [lx_, ly_, 0];
        end
        measRef{1} = m;
    end

    function endpointDragRelease(measIdx, ~, measRef, origMotionFcn, origReleaseFcn)
        fig.WindowButtonMotionFcn = origMotionFcn;
        fig.WindowButtonUpFcn    = origReleaseFcn;
        fig.Pointer = 'arrow';
        meas = measRef{1};
        x1 = meas.hLine.XData(1); y1 = meas.hLine.YData(1);
        x2 = meas.hLine.XData(2); y2 = meas.hLine.YData(2);
        appData.overlays.measurements{measIdx} = meas;
        switch meas.type
            case 'profile'
                runProfile(x1, y1, x2, y2);
            case 'distance'
                if ~isempty(meas.hText) && isvalid(meas.hText)
                    delete(meas.hText);
                end
                newTxt = createDistanceLabel(x1, y1, x2, y2);
                meas.hText = newTxt;
                appData.overlays.measurements{measIdx} = meas;
                setStatus(sprintf('Distance: %s', newTxt.String));
                appData.overlays.distLabels{end+1} = newTxt;
        end
        appData.measWorkshop.sync(appData.overlays.measurements);
        deselectMeasurement();
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: clearAllOverlays — Delete all measurement graphics objects
    % ════════════════════════════════════════════════════════════════════
    function clearAllOverlays()
        deleteScaleBar();
        emViewer.measurement.deleteOverlayHandles(appData.overlays);

        appData.overlays.measurements    = {};
        appData.overlays.lines           = {};
        appData.overlays.clickMarkers    = {};
        appData.overlays.distLabels      = {};
        appData.overlays.textAnnotations = {};
        appData.measWorkshop.sync(appData.overlays.measurements);
        appData.annotWorkshop.clearAll();

        if ~isempty(ax) && isvalid(ax)
            delete(findall(ax, 'Tag', 'diff_ring'));
            delete(findall(ax, 'Tag', 'diff_spot'));
            delete(findall(ax, 'Tag', 'box_profile'));
        end
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
        emViewer.meas.scaleBar('deleteHandle', sb);
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
        % Uses anonymous motion/release callbacks (no doubly-nested fns)
        if isempty(sb) || ~isstruct(sb), return; end
        if isempty(dragAx) || ~isvalid(dragAx), return; end
        barPos   = sb.bar.Position;
        labelPt  = [sb.label.Position(1), sb.label.Position(2)];
        cp       = dragAx.CurrentPoint;
        startX   = cp(1,1); startY = cp(1,2);
        origMFcn = fig.WindowButtonMotionFcn;
        origRFcn = fig.WindowButtonUpFcn;
        fig.WindowButtonMotionFcn = @(~,~) scaleBarDragMotion(sb, dragAx, ...
            barPos, labelPt, startX, startY);
        fig.WindowButtonUpFcn = @(~,~) set(fig, ...
            'WindowButtonMotionFcn', origMFcn, 'WindowButtonUpFcn', origRFcn);
    end

    function scaleBarDragMotion(sb, dragAx, barPos, labelPt, startX, startY)
        cp2 = dragAx.CurrentPoint;
        dx = cp2(1,1) - startX; dy = cp2(1,2) - startY;
        sb.bar.Position(1) = barPos(1) + dx;
        sb.bar.Position(2) = barPos(2) + dy;
        sb.label.Position  = [labelPt(1)+dx, labelPt(2)+dy, 0];
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: startLabelDrag — Drag a distance label to reposition it
    %  Uses anonymous motion/release callbacks (no doubly-nested fns) to
    %  stay within FermiViewer's nested-function parser budget.
    % ════════════════════════════════════════════════════════════════════
    function startLabelDrag(hT)
        origMotionFcn  = fig.WindowButtonMotionFcn;
        origReleaseFcn = fig.WindowButtonUpFcn;
        cp0    = ax.CurrentPoint;
        origPos = hT.Position;
        fig.Pointer = 'fleur';
        fig.WindowButtonMotionFcn = @(~,~) set(hT, 'Position', ...
            [origPos(1)+(ax.CurrentPoint(1,1)-cp0(1,1)), ...
             origPos(2)+(ax.CurrentPoint(1,2)-cp0(1,2)), 0]);
        fig.WindowButtonUpFcn = @(~,~) set(fig, ...
            'WindowButtonMotionFcn', origMotionFcn, ...
            'WindowButtonUpFcn', origReleaseFcn, 'Pointer', 'arrow');
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: measTargetIndices — Selected measurement if any, else all
    % ════════════════════════════════════════════════════════════════════
    function idxs = measTargetIndices()
        sel = appData.selectedMeasIdx;
        if sel > 0 && sel <= numel(appData.overlays.measurements)
            idxs = sel;
        else
            idxs = 1:numel(appData.overlays.measurements);
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: panelApplyLabelFont — Set label font size on target measurements
    %  nargin==0: prompt user (right-click "Font size...") and apply to all labels
    %  nargin==1: use selection-aware dispatch (selected-or-all)
    % ════════════════════════════════════════════════════════════════════
    function panelApplyLabelFont(fs)
        if nargin < 1
            resp = inputdlg('Font size (pt):', 'Label font size', 1, ...
                {num2str(spnMeasLabelFont.Value)});
            if isempty(resp), return; end
            fs = str2double(resp{1});
            if isnan(fs) || fs < 6 || fs > 72, return; end
            targets = 1:numel(appData.overlays.measurements);
        else
            targets = measTargetIndices();
        end
        for k = targets
            m = appData.overlays.measurements{k};
            if isfield(m, 'hText') && ~isempty(m.hText) && isvalid(m.hText)
                m.hText.FontSize = fs;
            end
        end
        spnMeasLabelFont.Value = fs;
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: panelApplySymbol — Restyle endpoints on target measurements
    % ════════════════════════════════════════════════════════════════════
    function panelApplySymbol(sym)
        mrk   = symTypeToMarker(sym);
        mrkSz = 6; if strcmp(sym, 'none'), mrkSz = 0.1; end
        for k = measTargetIndices()
            m = appData.overlays.measurements{k};
            for endH = {m.hP1, m.hP2}
                hE = endH{1};
                if ~isempty(hE) && isvalid(hE)
                    hE.Marker     = mrk;
                    hE.MarkerSize = mrkSz;
                end
            end
            m.endSymbol = sym;
            appData.overlays.measurements{k} = m;
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: panelApplyColor — Recolor line/endpoints/label on target measurements
    % ════════════════════════════════════════════════════════════════════
    function panelApplyColor(clr)
        for k = measTargetIndices()
            m = appData.overlays.measurements{k};
            if ~isempty(m.hLine) && isvalid(m.hLine)
                m.hLine.Color = clr;
            end
            for endH = {m.hP1, m.hP2}
                hE = endH{1};
                if ~isempty(hE) && isvalid(hE)
                    hE.Color          = clr;
                    hE.MarkerEdgeColor = clr;
                end
            end
            if isfield(m, 'hText') && ~isempty(m.hText) && isvalid(m.hText)
                m.hText.Color = clr;
            end
            m.lineColor = clr;
            appData.overlays.measurements{k} = m;
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onRotateFlip — delegates to emViewer.rotateFlip
    % ════════════════════════════════════════════════════════════════════
    function onRotateFlip(mode)
        if ~isempty(hColorbar) && isvalid(hColorbar)
            delete(hColorbar); hColorbar = [];
        end
        rfUi = struct('ax', ax, 'sldLow', sldLow, 'sldHigh', sldHigh, ...
            'ddColormap', ddColormap, 'cbColorbar', cbColorbar, ...
            'hColorbar', [], 'cbScaleBar', cbScaleBar);
        rfCb = struct('undoPush', @undoPush, ...
            'applyContrastPipeline', @applyContrastPipeline, ...
            'prepareDisplayBuffer', @prepareDisplayBuffer, ...
            'attachImageContextMenu', @attachImageContextMenu, ...
            'clearAllOverlays', @clearAllOverlays, ...
            'rebuildScaleBar', @rebuildScaleBar, ...
            'setStatus', @setStatus, ...
            'recreateColorbar', @() set([], 'dummy', []));
        appData = emViewer.rotateFlip(mode, appData, rfUi, rfCb);
        if cbColorbar.Value
            hColorbar = colorbar(ax);
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onCLAHE — Contrast-Limited Adaptive Histogram Equalization
    % ════════════════════════════════════════════════════════════════════
    function onCLAHE(~, ~)
        if isempty(appData.filteredPixels), return; end
        answer = inputdlg( ...
            {'Tile size (pixels per tile, e.g. 64):', ...
             'Clip limit (contrast factor, e.g. 3.0):'}, ...
            'CLAHE Parameters', [1 44], {'64', '3.0'});
        if isempty(answer), return; end
        tileSize  = round(str2double(answer{1}));
        clipLimit = str2double(answer{2});
        if isnan(tileSize) || tileSize < 8
            uialert(fig, 'Tile size must be >= 8.', 'Invalid Input', 'Icon', 'error'); return;
        end
        if isnan(clipLimit) || clipLimit <= 0
            uialert(fig, 'Clip limit must be positive.', 'Invalid Input', 'Icon', 'error'); return;
        end
        fig.Pointer = 'watch'; drawnow;
        try
            undoPush();
            r = emViewer.processing.executeFilter(appData.filteredPixels, 'clahe', ...
                struct('tileSize', tileSize, 'clipLimit', clipLimit));
            appData.filteredPixels = r.pixels;
            refreshDisplay();
            setStatus(r.statusMsg);
        catch ME
            uialert(fig, sprintf('CLAHE failed:\n%s', ME.message), 'Filter Error', 'Icon', 'error');
        end
        fig.Pointer = 'arrow';
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onDrawROI — Start the capture matching ddROIShape.Value
    %  Consolidates what used to be three separate buttons (Rect ROI,
    %  Circle ROI, Polyline) into one shape dropdown + one Draw button.
    % ════════════════════════════════════════════════════════════════════
    function onDrawROI()
        if appData.activeIdx < 1 || isempty(appData.displayImg), return; end
        if appData.compareMode, return; end
        shape = ddROIShape.Value;
        switch shape
            case 'Rectangle'
                startRectCapture('rectROI');
            case 'Circle'
                startTwoClickCapture('roiellipse');
            case 'Polyline'
                onPolylineAction('start', [], []);
            otherwise
                setStatus(sprintf('Unknown ROI shape: %s', shape));
        end
    end


    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onAngleAction — Three-click angle measurement dispatcher
    %  action='start' : begin capture; action='click' : handle each click
    % ════════════════════════════════════════════════════════════════════
    function onAngleAction(action, ~, ~)
        ctx = buildMeasCtx();
        appData = emViewer.measInteract('onAngleAction', appData, ctx, action);
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onPolylineAction — Multi-point distance measurement dispatcher
    %  action='start' : begin capture; action='click' : handle each click
    % ════════════════════════════════════════════════════════════════════
    function onPolylineAction(action, ~, ~)
        ctx = buildMeasCtx();
        appData = emViewer.measInteract('onPolylineAction', appData, ctx, action);
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: executeAngleFromPoints — Headless angle measurement
    % ════════════════════════════════════════════════════════════════════
    function angleDeg = executeAngleFromPoints(pts)
        [appData, angleDeg] = emViewer.measExecute('angleFromPoints', appData, buildMeasCtx(), pts);
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: executePolylineFromPoints — Headless polyline length
    % ════════════════════════════════════════════════════════════════════
    function totalDist = executePolylineFromPoints(pts)
        [appData, totalDist] = emViewer.measExecute('polylineFromPoints', appData, buildMeasCtx(), pts);
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

    function executeScaleBarCalibration(x1, y1, x2, y2)
        hLine = line(ax, [x1 x2], [y1 y2], ...
            'Color', [0 1 1], 'LineWidth', 2, 'LineStyle', '--', ...
            'HandleVisibility', 'off');
        pxDist = sqrt((x2 - x1)^2 + (y2 - y1)^2);
        for ci = 1:numel(appData.overlays.clickMarkers)
            h = appData.overlays.clickMarkers{ci};
            if isvalid(h), delete(h); end
        end
        appData.overlays.clickMarkers = {};
        [realDist, realUnit, cancelled] = emViewer.calibration.promptScaleBarDistance(pxDist);
        if isvalid(hLine), delete(hLine); end
        if cancelled, return; end
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
            det = emViewer.calibration.detectScaleBar(appData.filteredPixels);
            fig.Pointer = 'arrow';
            if ~det.found
                uialert(fig, det.msg, 'Auto-Detect Failed', 'Icon', 'warning');
                return;
            end
            barColor = [0 1 1];
            hBarLine  = line(ax, [det.barX1 det.barX2], [det.barY det.barY], ...
                'Color', barColor, 'LineWidth', 3, 'HandleVisibility', 'off');
            hBarEnd1  = line(ax, [det.barX1 det.barX1], [det.barY-8 det.barY+8], ...
                'Color', barColor, 'LineWidth', 2, 'HandleVisibility', 'off');
            hBarEnd2  = line(ax, [det.barX2 det.barX2], [det.barY-8 det.barY+8], ...
                'Color', barColor, 'LineWidth', 2, 'HandleVisibility', 'off');
            hBarLabel = text(ax, (det.barX1+det.barX2)/2, det.barY-12, det.msg, ...
                'Color', barColor, 'FontSize', 11, 'FontWeight', 'bold', ...
                'HorizontalAlignment', 'center', 'BackgroundColor', [0.1 0.1 0.1], ...
                'HandleVisibility', 'off');
            drawnow;
            [realDist, realUnit, cancelled] = emViewer.calibration.promptScaleBarDistance(det.barLen);
            if isvalid(hBarLine),  delete(hBarLine);  end
            if isvalid(hBarEnd1),  delete(hBarEnd1);  end
            if isvalid(hBarEnd2),  delete(hBarEnd2);  end
            if isvalid(hBarLabel), delete(hBarLabel); end
            if cancelled, return; end
            newPixelSize = realDist / det.barLen;
            applyCalibration(newPixelSize, realUnit);
            setStatus(sprintf('Calibrated: %.4g %s/px (auto-detected %.0f px = %g %s)', ...
                newPixelSize, realUnit, det.barLen, realDist, realUnit));
        catch ME
            fig.Pointer = 'arrow';
            uialert(fig, sprintf('Auto-detect failed:\n%s', ME.message), 'Error', 'Icon', 'error');
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
        if appData.activeIdx >= 1 && appData.activeIdx <= numel(appData.images)
            taMetadata.Value = emViewer.display.formatMetadata(appData.images{appData.activeIdx});
        else
            taMetadata.Value = {'(no image loaded)'};
        end

        cbScaleBar.Enable       = 'on';
        ddScaleBarColor.Enable = 'on';
        spnScaleBarFont.Enable  = 'on';
        efScaleBarLen.Enable    = 'on';
        ddScaleBarUnit.Enable   = 'on';
        cbScaleBar.Value        = true;
        rebuildScaleBar();
        appData.calibWS.sync(appData);
    end

    % promptScaleBarDistance → emViewer.calibration.promptScaleBarDistance

    % ════════════════════════════════════════════════════════════════════
    %  HELPERS: per-measurement color + symbol — right-click menu actions
    % ════════════════════════════════════════════════════════════════════
    function cm = buildMeasLineMenu(hLine)
        cm = emViewer.meas.scaleBar('buildLineMenu', fig, hLine, ...
            @applyMeasColor, @applyMeasColorAll, ...
            @applyMeasEndSymbol, @applyMeasEndSymbolAll);
    end

    function applyMeasColor(hLine, clr)
        appData.overlays.measurements = emViewer.meas.appearance( ...
            'applyColor', appData.overlays.measurements, hLine, clr);
        appData.measWorkshop.sync(appData.overlays.measurements);
    end

    function applyMeasColorAll(hLine)
        appData.overlays.measurements = emViewer.meas.appearance( ...
            'applyColorAll', appData.overlays.measurements, hLine, OVERLAY_COLOR);
        appData.measWorkshop.sync(appData.overlays.measurements);
    end

    function applyMeasEndSymbol(hLine, sym)
        appData.overlays.measurements = emViewer.meas.appearance( ...
            'applySymbol', appData.overlays.measurements, hLine, sym);
        appData.measWorkshop.sync(appData.overlays.measurements);
    end

    function applyMeasEndSymbolAll(hLine)
        appData.overlays.measurements = emViewer.meas.appearance( ...
            'applySymbolAll', appData.overlays.measurements, hLine);
        appData.measWorkshop.sync(appData.overlays.measurements);
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: selectMeasurement — Single-select: clear all, highlight idx
    % ════════════════════════════════════════════════════════════════════
    function selectMeasurement(idx)
        deselectMeasurement();   % clears every previously highlighted meas
        % Also drop any annotation marquee-selection: clicking a single
        % measurement should not silently leave annotations highlighted.
        for ai = appData.selectedAnnotIndices(:)'
            if ai >= 1 && ai <= numel(appData.overlays.textAnnotations)
                highlightAnnotation(appData.overlays.textAnnotations{ai}, false);
            end
        end
        appData.selectedAnnotIndices = [];
        appData.selectedAnnotIdx = 0;

        if idx < 1 || idx > numel(appData.overlays.measurements)
            return;
        end
        meas = appData.overlays.measurements{idx};
        if ~isvalid(meas.hLine), return; end

        applyMeasHighlight(idx);
        appData.selectedMeasIdx     = idx;
        appData.selectedMeasIndices = idx;

        setStatus(sprintf('Selected %s measurement %d (press Delete to remove)', ...
            meas.type, idx));
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: applyMeasHighlight — Apply yellow highlight to one meas
    %  (does NOT deselect anything else; used by both single and multi
    %  select paths).
    % ════════════════════════════════════════════════════════════════════
    function applyMeasHighlight(idx)
        emViewer.meas.selection('highlight', appData.overlays.measurements, idx);
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: deselectMeasurement — Restore normal styling on ALL
    %  currently-selected measurements (single-select compatible: when
    %  selectedMeasIndices is empty, falls back to the legacy single idx).
    % ════════════════════════════════════════════════════════════════════
    function deselectMeasurement()
        [~, appData.selectedMeasIdx, appData.selectedMeasIndices] = ...
            emViewer.meas.selection('deselect', appData.overlays.measurements, ...
            appData.selectedMeasIdx, appData.selectedMeasIndices, OVERLAY_COLOR);
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: applyMarqueeSelection — Select items inside a drag box
    % ════════════════════════════════════════════════════════════════════
    function applyMarqueeSelection(xMin, xMax, yMin, yMax)
        ctx = buildMeasCtx();
        appData = emViewer.measInteract('applyMarqueeSelection', appData, ctx, ...
            xMin, xMax, yMin, yMax);
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: onRemoveSelected — Remove whichever object is selected
    %  (measurement > annotation).  Used by the Remove button and the
    %  Delete/Backspace key handler.
    % ════════════════════════════════════════════════════════════════════
    function onRemoveSelected()
        % Snapshot both multi-select arrays, then fall back to legacy
        % single-select fields if the arrays are empty. Iterate in
        % descending order so deletions don't invalidate earlier indices.
        mIdx = appData.selectedMeasIndices;
        aIdx = appData.selectedAnnotIndices;
        if isempty(mIdx) && appData.selectedMeasIdx > 0,  mIdx = appData.selectedMeasIdx;  end
        if isempty(aIdx) && appData.selectedAnnotIdx > 0, aIdx = appData.selectedAnnotIdx; end

        if isempty(mIdx) && isempty(aIdx)
            setStatus('Click a measurement or annotation to select (or drag to marquee), then Remove / Delete.');
            return;
        end

        % Delete measurements: deleteSelectedMeasurement reads selectedMeasIdx,
        % so we loop with it set per iteration.
        for ii = sort(mIdx(:)', 'descend')
            appData.selectedMeasIdx = ii;
            deleteSelectedMeasurement();
        end
        % Delete annotations via the annotation dispatcher.
        for ii = sort(aIdx(:)', 'descend')
            onAnnotationAction('deleteOne', ii);
        end

        nTot = numel(mIdx) + numel(aIdx);
        appData.selectedMeasIndices  = [];
        appData.selectedAnnotIndices = [];
        appData.selectedMeasIdx      = 0;
        appData.selectedAnnotIdx     = 0;
        if nTot > 1
            setStatus(sprintf('Deleted %d items.', nTot));
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: deleteSelectedMeasurement — Remove selected overlay
    % ════════════════════════════════════════════════════════════════════
    function deleteSelectedMeasurement()
        idx = appData.selectedMeasIdx;
        if idx < 1 || idx > numel(appData.overlays.measurements), return; end
        measType = appData.overlays.measurements{idx}.type;
        [appData.overlays.measurements, appData.selectedMeasIdx, ~] = ...
            emViewer.meas.selection('delete', appData.overlays.measurements, ...
            idx, OVERLAY_COLOR, []);
        appData.measWorkshop.sync(appData.overlays.measurements);
        % Re-bind callbacks (closure-dependent; must remain here)
        for mi = 1:numel(appData.overlays.measurements)
            m = appData.overlays.measurements{mi};
            if isfield(m, 'hP1') && ~isempty(m.hP1) && isvalid(m.hP1)
                m.hP1.ButtonDownFcn = @(~,~) startEndpointDrag(mi, 1);
            end
            if isfield(m, 'hP2') && ~isempty(m.hP2) && isvalid(m.hP2)
                m.hP2.ButtonDownFcn = @(~,~) startEndpointDrag(mi, 2);
            end
            if isfield(m, 'hLine') && isvalid(m.hLine)
                m.hLine.ButtonDownFcn = @(~,~) selectMeasurement(mi);
            end
            if isfield(m, 'type') && strcmp(m.type, 'polyline') && isfield(m, 'hLines')
                for hh = m.hLines(:)'
                    if isvalid(hh), hh.ButtonDownFcn = @(~,~) selectMeasurement(mi); end
                end
            end
        end
        % Adjust multi-select indices for the removed slot
        if ~isempty(appData.selectedMeasIndices)
            keep = appData.selectedMeasIndices ~= idx;
            appData.selectedMeasIndices = appData.selectedMeasIndices(keep);
            shift = appData.selectedMeasIndices > idx;
            appData.selectedMeasIndices(shift) = appData.selectedMeasIndices(shift) - 1;
        end
        setStatus(sprintf('Deleted %s measurement', measType));
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
    %UNDOPOP  wrapper → emViewer.displayHelpers('undoPop')
        appData = emViewer.displayHelpers('undoPop', appData, buildDisplayCtx());
        % Sync hColorbar closure var when undoPop created a new colorbar
        if isfield(appData, 'undoPop_hColorbar')
            hColorbar = appData.undoPop_hColorbar;
            appData   = rmfield(appData, 'undoPop_hColorbar');
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onFFTMask — Interactive FFT masking with inverse FFT
    % ════════════════════════════════════════════════════════════════════
    function onFFTMask(~, ~)
        cb_ = struct('undoPush', @undoPush, 'undoPop', @undoPop, 'refreshDisplay', @refreshDisplay, 'setStatus', @setStatus);
        cb_.BTN_PRIMARY = BTN_PRIMARY;
        cb_.BTN_FG      = BTN_FG;
        cb_.applyResult = @applyFFTResult;
        appData = emViewer.filterOps('fftMask', appData, fig, cb_);
    end

    function applyFFTResult(pixels)
        appData = emViewer.filterOps('applyFFTResult', appData, fig, struct('undoPush', @undoPush, 'undoPop', @undoPop, 'refreshDisplay', @refreshDisplay, 'setStatus', @setStatus), pixels);
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onParticleCount — Threshold and count connected components
    % ════════════════════════════════════════════════════════════════════
    function onParticleCount(~, ~)
        if isempty(appData.filteredPixels), return; end
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
        pixSz = NaN; pixUnit = 'px'; cal = false;
        if appData.activeIdx >= 1
            imgInfo = appData.images{appData.activeIdx}.metadata.parserSpecific.imageData;
            pixSz = imgInfo.pixelSize; pixUnit = imgInfo.pixelUnit; cal = imgInfo.calibrated;
        end
        fig.Pointer = 'watch'; drawnow;
        r = emViewer.analysis.executeParticleCount(appData.filteredPixels, thresh, minArea, pixSz, pixUnit, cal);
        fig.Pointer = 'arrow';
        setStatus(r.statusMsg);
        appData.procWorkshop.recordParticleResult(r.nParticles, thresh, minArea);
    end


    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onAlignStack — Cross-correlation drift correction
    % ════════════════════════════════════════════════════════════════════
    function onAlignStack(~, ~)
        if numel(appData.images) < 2
            uialert(fig, 'Need at least 2 images to align.', ...
                'Align Stack', 'Icon', 'warning'); return;
        end
        answer = questdlg( ...
            sprintf('Align %d loaded images using cross-correlation?\nThe first image is the reference.', ...
            numel(appData.images)), 'Drift Correction', 'Align', 'Cancel', 'Align');
        if ~strcmp(answer, 'Align'), return; end
        fig.Pointer = 'watch'; drawnow;
        try
            r = emViewer.processing.executeAlignStack(appData.images);
            appData.images = r.images;
            fig.Pointer = 'arrow';
            uialert(fig, sprintf('Alignment complete:\n\n%s', r.shiftStr), ...
                'Drift Correction', 'Icon', 'info');
            displayImage();
            setStatus(r.statusMsg);
            appData.procWorkshop.recordAlignment(r.shifts);
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
        names = cell(1, numel(appData.images));
        for ki = 1:numel(appData.images)
            [~, fn, fe] = fileparts(appData.images{ki}.metadata.source);
            names{ki} = sprintf('[%d] %s%s', ki, fn, fe);
        end
        answer = inputdlg( ...
            {'Image A index (1-based):', ...
             'Image A colormap (red, green, blue, cyan, magenta, yellow):', ...
             'Image B index (1-based):', 'Image B colormap:', ...
             'Blend alpha (0-1, for image B):'}, ...
            'Color Overlay', [1 50], {'1', 'green', '2', 'magenta', '0.5'});
        if isempty(answer), return; end
        idxA = str2double(answer{1}); cmapA = lower(strtrim(answer{2}));
        idxB = str2double(answer{3}); cmapB = lower(strtrim(answer{4}));
        alpha = max(0, min(1, str2double(answer{5})));
        if isnan(idxA) || isnan(idxB) || idxA < 1 || idxB < 1 || ...
                idxA > numel(appData.images) || idxB > numel(appData.images)
            uialert(fig, 'Invalid image indices.', 'Error', 'Icon', 'error');
            return;
        end
        imgA = emViewer.eds.getGrayscale(appData.images{round(idxA)});
        imgB = emViewer.eds.getGrayscale(appData.images{round(idxB)});
        r = emViewer.visualization.displayColorOverlay( ...
            imgA, imgB, cmapA, cmapB, alpha, names{round(idxA)}, names{round(idxB)});
        setStatus(r.statusMsg);
    end

    % ════════════════════════════════════════════════════════════════════
    %  EDS MULTI-CHANNEL COMPOSITE MODE
    %  Logic extracted to +emViewer/+eds/dispatch.m via ctx pattern.
    % ════════════════════════════════════════════════════════════════════

    function ctx = buildEDSCtx()
        ctx.ax  = ax;
        ctx.fig = fig;
        ctx.btnEDSToolbar      = btnEDSToolbar;
        ctx.btnEnterEDS        = btnEnterEDS;
        ctx.btnAddChannel      = btnAddChannel;
        ctx.btnRemoveChannel   = btnRemoveChannel;
        ctx.ddChannelColor     = ddChannelColor;
        ctx.cbChannelVisible   = cbChannelVisible;
        ctx.sldChannelIntensity = sldChannelIntensity;
        ctx.efChannelLabel     = efChannelLabel;
        ctx.btnExportComposite = btnExportComposite;
        ctx.lbEDSChannels      = lbEDSChannels;
        ctx.lblEDSIntensity    = lblEDSIntensity;
        ctx.ddColormap         = ddColormap;
        ctx.BTN_DANGER         = BTN_DANGER;
        ctx.BTN_PRIMARY        = BTN_PRIMARY;
        ctx.EDS_COLORS         = EDS_COLORS;
        ctx.cb.setStatus         = @setStatus;
        ctx.cb.setToolsEnabled   = @setToolsEnabled;
        ctx.cb.displayImage      = @displayImage;
        ctx.cb.clearDisplay      = @clearDisplay;
        ctx.cb.exitCompareMode   = @exitCompareMode;
        ctx.cb.attachImageContextMenu = @attachImageContextMenu;
        ctx.cb.onEnterEDS        = @(~,~) onEnterEDS([], []);
        ctx.cb.onExitEDS         = @onExitEDS;
    end

    function onEDSToolbarToggle(src, ~)
        if src.Value; onEnterEDS([], []); else; onExitEDS(); end
    end

    function onEnterEDS(~, ~)
        ctx = buildEDSCtx();
        appData = emViewer.eds.dispatch('enter', appData, ctx);
    end

    function onExitEDS()
        ctx = buildEDSCtx();
        appData = emViewer.eds.dispatch('exit', appData, ctx);
    end

    function compositeEDS()
        ctx = buildEDSCtx();
        appData = emViewer.eds.dispatch('composite', appData, ctx);
    end

    function refreshEDSList()
        ctx = buildEDSCtx();
        appData = emViewer.eds.dispatch('refreshList', appData, ctx);
    end

    function populateEDSControls(~)
        ctx = buildEDSCtx();
        appData = emViewer.eds.dispatch('populateControls', appData, ctx);
    end

    function onEDSChannelSelected(~, ~)
        ctx = buildEDSCtx();
        appData = emViewer.eds.dispatch('channelSelected', appData, ctx);
    end

    function onEDSListChange(action)
        ctx = buildEDSCtx();
        switch action
            case 'add';    appData = emViewer.eds.dispatch('addChannel',    appData, ctx);
            case 'remove'; appData = emViewer.eds.dispatch('removeChannel', appData, ctx);
        end
    end

    function onEDSChannelPropChanged(prop)
        ctx = buildEDSCtx();
        switch prop
            case 'color';     appData = emViewer.eds.dispatch('propColor',     appData, ctx);
            case 'visible';   appData = emViewer.eds.dispatch('propVisible',   appData, ctx);
            case 'intensity'; appData = emViewer.eds.dispatch('propIntensity', appData, ctx);
            case 'label';     appData = emViewer.eds.dispatch('propLabel',     appData, ctx);
        end
    end

    function onExportEDSComposite(~, ~)
        ctx = buildEDSCtx();
        appData = emViewer.eds.dispatch('exportComposite', appData, ctx);
    end

    function setEDSChannelAPI(idx, field, val)
        ctx = buildEDSCtx();
        ctx.apiIdx   = idx;
        ctx.apiField = field;
        ctx.apiVal   = val;
        appData = emViewer.eds.dispatch('setChannelAPI', appData, ctx);
    end

    function tf = getEDSMode()
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
        if isempty(appData.filteredPixels), return; end
        emViewer.processing.showSurfacePlot(appData.filteredPixels);
        setStatus('3D surface view opened — drag to rotate');
    end

    appData.liveFFTFig = [];  % persistent live FFT figure handle

    function onLiveFFTToggle(src, ~)
        appData = emViewer.filterOps('liveFFTToggle', appData, fig, struct('undoPush', @undoPush, 'undoPop', @undoPop, 'refreshDisplay', @refreshDisplay, 'setStatus', @setStatus), src);
    end

    function updateLiveFFT()
        appData = emViewer.filterOps('updateLiveFFT', appData, fig, struct('undoPush', @undoPush, 'undoPop', @undoPop, 'refreshDisplay', @refreshDisplay, 'setStatus', @setStatus));
    end

    function onTemplateMatch(~, ~)
        if isempty(appData.filteredPixels), return; end
        answer = inputdlg({'X start:', 'Y start:', 'Width:', 'Height:'}, ...
            'Select Template Region', 1, {'10', '10', '50', '50'});
        if isempty(answer), return; end
        x1 = str2double(answer{1}); y1 = str2double(answer{2});
        tw = str2double(answer{3}); th = str2double(answer{4});
        fig.Pointer = 'watch'; drawnow;
        try
            r = emViewer.processing.executeTemplateMatch(appData.filteredPixels, x1, y1, tw, th);
            fig.Pointer = 'arrow';
            if r.nMatches > 0
                hold(ax, 'on');
                for mi = 1:r.nMatches
                    plot(ax, r.locations(mi,2), r.locations(mi,1), 'r+', ...
                        'MarkerSize', 12, 'LineWidth', 2, 'HandleVisibility', 'off');
                end
                hold(ax, 'off');
            end
            setStatus(r.statusMsg);
        catch ME
            fig.Pointer = 'arrow';
            uialert(fig, sprintf('Template match failed:\n%s', ME.message), 'Error', 'Icon', 'error');
        end
    end

    function onStitchImages(~, ~)
        if numel(appData.images) < 2
            uialert(fig, 'Need at least 2 images to stitch.', 'Stitch', 'Icon', 'warning'); return;
        end
        layouts = {'horizontal', 'vertical', 'auto'};
        [sel, ok] = listdlg('ListString', layouts, 'SelectionMode', 'single', ...
            'PromptString', 'Layout direction:', 'ListSize', [150 60]);
        if ~ok, return; end
        fig.Pointer = 'watch'; drawnow;
        try
            r = emViewer.processing.executeStitchImages(appData.images, layouts{sel});
            fig.Pointer = 'arrow';
            setStatus(r.statusMsg);
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
        r = emViewer.display.applyPubPreset( ...
            appData.overlays.scalebar, appData.overlays.textAnnotations);
        if r.applied, setStatus(r.statusMsg); end
    end

    function onColormapPreset(~, ~)
        [ui__, cb__] = buildContrastCtx();
        appData = emViewer.contrastOps('colormapPreset', appData, ui__, cb__);
    end

    function onMeasurementStats(~, ~)
        if appData.measWorkshop.numMeasurements() == 0
            uialert(fig, 'No measurements to analyze.', 'Stats', 'Icon', 'info'); return;
        end
        stats = appData.measWorkshop.model.aggregateStats();
        if stats.count == 0
            uialert(fig, 'No distance measurements found.', 'Stats', 'Icon', 'info'); return;
        end
        r = emViewer.analysis.displayMeasurementStats(stats);
        setStatus(r.statusMsg);
    end

    function onBatchMeasurement(~, ~)
        if numel(appData.images) < 2
            uialert(fig, 'Need 2+ images for batch measurement.', 'Batch', 'Icon', 'warning'); return;
        end
        answer = inputdlg({'X1:', 'Y1:', 'X2:', 'Y2:'}, ...
            'Line Profile Coordinates (same for all images)', 1, {'10', '10', '100', '100'});
        if isempty(answer), return; end
        x1 = str2double(answer{1}); y1 = str2double(answer{2});
        x2 = str2double(answer{3}); y2 = str2double(answer{4});
        fig.Pointer = 'watch'; drawnow;
        try
            r = emViewer.analysis.executeBatchProfiles(appData.images, x1, y1, x2, y2);
            fig.Pointer = 'arrow';
            setStatus(r.statusMsg);
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

    function setZoomModeAPI(tf)
    %SETZOOMMODEAPI  Programmatically toggle drag-to-zoom vs marquee-select.
    %  Tests and scripts use this to bypass the icon-toolbar state button.
        appData.zoomMode = logical(tf);
    end

    function v = getZoomModeAPI()
        v = appData.zoomMode;
    end

    function v = getSelectedMeasIndicesAPI()
        v = appData.selectedMeasIndices;
    end

    function v = getSelectedAnnotIndicesAPI()
        v = appData.selectedAnnotIndices;
    end

    function setColormapAPI(name)
    %SETCOLORMAPAPI  Programmatically set colormap (matches dropdown items).
        [ui__, cb__] = buildContrastCtx();
        appData = emViewer.contrastOps('setColormap', appData, ui__, cb__, name);
    end

    function cycleColormapAPI()
    %CYCLECOLORMAPAPI  Advance to the next colormap in the dropdown list.
        [ui__, cb__] = buildContrastCtx();
        appData = emViewer.contrastOps('cycleColormap', appData, ui__, cb__);
    end

    function setContrastTransformAPI(mode)
    %SETCONTRASTTRANSFORMAPI  Set 'linear' | 'log' | 'sqrt' | 'power'.
        [ui__, cb__] = buildContrastCtx();
        appData = emViewer.contrastOps('setTransform', appData, ui__, cb__, mode);
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
        appData = emViewer.filterOps('fftMaskAPI', appData, fig, struct('undoPush', @undoPush, 'undoPop', @undoPop, 'refreshDisplay', @refreshDisplay, 'setStatus', @setStatus), masks);
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
    %RENAMEBATCH  Rename files on disk -- delegates to emViewer.sessionOps.
        appData = emViewer.sessionOps('renameBatch', appData, buildSessionCtx('', idxs));
    end
    function refreshImageList()
    %REFRESHIMAGELIST  Rebuild listbox items -- delegates to emViewer.sessionOps.
        appData = emViewer.sessionOps('refreshImageList', appData, buildSessionCtx());
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
    %  CALLBACK: onFileDrop — Handle drag-and-drop files onto the figure
    % ════════════════════════════════════════════════════════════════════
    function onFileDrop(~, evt)
    %ONFILEDROP  Handle drag-and-drop -- delegates to emViewer.sessionOps.
        appData = emViewer.sessionOps('fileDrop', appData, buildSessionCtx('', [], evt));
    end

    % ════════════════════════════════════════════════════════════════════
    %  STACK NAVIGATOR: frame slider, prev/next, MIP
    % ════════════════════════════════════════════════════════════════════
    function showStackControls(nFrames)
    %SHOWSTACKCONTROLS  Show/configure the frame slider for multi-frame images.
        if ~isvalid(axGL), return; end
        if nFrames <= 1
            axGL.RowHeight = {32, '1x', 0};
            appData.stackFrames = {};
            appData.stackIdx = 0;
            return;
        end
        axGL.RowHeight = {32, '1x', 28};
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
        % ── wrapper: delegates to emViewer.displayStackFrame ─────────────
        ui_ = struct('sldLow', sldLow, 'sldHigh', sldHigh);
        cb_ = struct( ...
            'prepareDisplayBuffer', @(varargin) closureReturn_('prepare', varargin{:}), ...
            'applyContrastPipeline', @applyContrastPipeline, ...
            'updateHistogram', @updateHistogram);
        appData = emViewer.displayStackFrame(idx, appData, ui_, cb_);
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
        bc = struct('primary', BTN_PRIMARY, 'fg', BTN_FG);
        hook = struct('applyResult', @applyThreshResult);
        emViewer.processing.buildThresholdDialog(appData.filteredPixels, bc, hook);

        function applyThreshResult(threshPixels, msg)
            undoPush();
            appData.filteredPixels = threshPixels;
            refreshDisplay();
            setStatus(msg);
        end
    end

    function thresh = otsuThreshold(img)
        thresh = emViewer.processing.otsuThreshold(img);
    end

    % ── Feature 2: Image Arithmetic ───────────────────────────────────
    function onImageMath(~, ~)
        if numel(appData.images) < 2, return; end
        names = cell(1, numel(appData.images));
        for mi = 1:numel(appData.images)
            [~, fn, fe] = fileparts(appData.images{mi}.metadata.source);
            names{mi} = sprintf('%d: %s%s', mi, fn, fe);
        end
        answer = inputdlg( ...
            {'Image A (index):', 'Image B (index):', ...
             'Operation (subtract, divide, ratio, add):'}, ...
            'Image Arithmetic', [1 44], {num2str(1), num2str(2), 'subtract'});
        if isempty(answer), return; end
        idxA = str2double(answer{1}); idxB = str2double(answer{2});
        op = lower(strtrim(answer{3}));
        if isnan(idxA) || isnan(idxB) || idxA < 1 || idxB < 1 || ...
                idxA > numel(appData.images) || idxB > numel(appData.images)
            uialert(fig, 'Invalid image indices.', 'Error', 'Icon', 'error');
            return;
        end
        try
            r = emViewer.processing.executeImageMath( ...
                getGrayscaleFromIdx(idxA), getGrayscaleFromIdx(idxB), op, names{idxA});
        catch ME
            uialert(fig, ME.message, 'Error', 'Icon', 'error'); return;
        end
        if appData.activeIdx >= 1 && ~isempty(appData.imgHandle) && isvalid(appData.imgHandle)
            undoPush();
            appData.rawPixels = r.pixels;
            appData.filteredPixels = r.pixels;
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
        bc = struct('primary', BTN_PRIMARY, 'export', BTN_EXPORT, 'fg', BTN_FG);
        hook = struct( ...
            'startROICapture', @() beginROICapture(), ...
            'getROIList',      @() appData.roiList, ...
            'setStatus',       @setStatus);
        emViewer.measurement.buildROIManager(appData.roiList, bc, hook);

        function beginROICapture()
            setStatus('Draw rectangle for ROI... (Esc to cancel)');
            startRectCapture('roistats');
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
    %SESSIONLOADAPI  Load a session .mat -- delegates to emViewer.sessionOps.
        appData = emViewer.sessionOps('load', appData, buildSessionCtx(inPath));
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

    % ── Feature 8: Thumbnail Grid View ────────────────────────────────
    function onThumbnailGrid(~, ~)
        if numel(appData.images) < 1, return; end
        emViewer.display.buildThumbnailGrid(appData.images, @gridJump);
        function gridJump(idx)
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
    %REFRESHHISTOGRAMMARKERS  delegates to emViewer.histogramOps
        [ui__, cb__] = buildContrastCtx();
        emViewer.histogramOps('markers', histAx, appData, ui__, cb__);
    end

    % ── Feature 10: Batch Crop Template ───────────────────────────────
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
        r = emViewer.segmentation.executeWatershed(px, thresh, minArea);
        fig.Pointer = 'arrow';
        setStatus(r.statusMsg);
    end

    % ── Feature 13: Gamma Curve ───────────────────────────────────────
    function onGammaChanged(~, ~)
        appData.gamma = sldGamma.Value;
        efGamma.Value = appData.gamma;
        lblGamma.Text = 'Gamma';
        appData.contrastWS.setGamma(appData.gamma);
        onContrastChanged([], []);
    end

    % ── Feature 14: Image Montage / Stitching ─────────────────────────
    function onMontage(~, ~)
        if numel(appData.images) < 2, return; end
        nImgs = numel(appData.images);
        defCols = ceil(sqrt(nImgs));
        answer = inputdlg({'Columns:', 'Overlap % (0-50):'}, ...
            'Montage / Stitch', [1 36], {num2str(defCols), '0'});
        if isempty(answer), return; end
        nCols = round(str2double(answer{1}));
        overlap = str2double(answer{2}) / 100;
        if isnan(nCols) || nCols < 1, nCols = defCols; end
        if isnan(overlap), overlap = 0; end
        overlap = max(0, min(0.5, overlap));
        fig.Pointer = 'watch'; drawnow;
        tiles = cell(1, nImgs);
        for ti = 1:nImgs, tiles{ti} = getGrayscaleFromIdx(ti); end
        r = emViewer.visualization.executeMontage(tiles, nCols, overlap);
        fig.Pointer = 'arrow';
        setStatus(r.statusMsg);
    end

    function onDiffractionAction(action)
        ui_ = struct( ...
            'fig',            fig, ...
            'ax',             ax, ...
            'lblSpotCount',   lblSpotCount, ...
            'lblZoneAxis',    lblZoneAxis, ...
            'lbxDiffResults', lbxDiffResults, ...
            'edtCameraLen',   edtCameraLen, ...
            'ddAccVoltage',   ddAccVoltage, ...
            'edtZoneAxis',    edtZoneAxis);
        cb_ = struct( ...
            'setStatus',             @setStatus, ...
            'guiPixelSize',          @guiPixelSize, ...
            'guiPixelUnit',          @guiPixelUnit, ...
            'startTwoClickCapture',  @startTwoClickCapture, ...
            'onCaptureClick',        @onCaptureClick);
        appData = emViewer.onDiffractionAction(action, appData, ui_, cb_);
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
    %UPDATEPIXELINSPECTOR  wrapper → emViewer.displayHelpers('pixelInspector')
        appData = emViewer.displayHelpers( ...
            'pixelInspector', appData, buildDisplayCtx(), px, py);
    end

    % ── Feature 18: Preferences Dialog ────────────────────────────────
    function onPreferences(~, ~)
        bc = struct('primary', BTN_PRIMARY, 'fg', BTN_FG);
        hook = struct('applyPrefs', @applyPrefsFromDialog);
        emViewer.buildPreferencesDialog(appData.prefs, bc, hook);

        function applyPrefsFromDialog(newPrefs)
            flds = fieldnames(newPrefs);
            for fj = 1:numel(flds)
                appData.prefs.(flds{fj}) = newPrefs.(flds{fj});
            end
            try
                prefs = appData.prefs; %#ok<NASGU>
                save(prefsFilePath, 'prefs');
            catch
            end
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
        drawnow limitrate;
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
        drawnow limitrate;
    end

    function updateLoading(current, total, fname)
    %UPDATELOADING  Update loading progress (e.g. "Loading 2/5 file.tif").
        lblLoadStatus.Text = sprintf('Loading %d/%d  %s', current, total, fname);
        drawnow limitrate;
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
    %GETLINEPROFILEAPI  wrapper → emViewer.displayHelpers('lineProfile')
        [appData, result] = emViewer.displayHelpers( ...
            'lineProfile', appData, buildDisplayCtx(), x1, y1, x2, y2);
    end


    % ════════════════════════════════════════════════════════════════════
    %  PHASE 3: Contrast Pipeline Helper + ctx builders
    % ════════════════════════════════════════════════════════════════════
    function dispImg = applyContrastPipeline(pixels, lo, hi)
        dispImg = emViewer.contrast.applyPipeline(pixels, lo, hi, ...
            appData.contrastTransform, appData.gamma, appData.contrastInvert);
    end

    % ── Shared context builders for emViewer.contrastOps / histogramOps ─
    function [ui_, cb_] = buildContrastCtx()
        ui_ = struct( ...
            'ax', ax, 'histAx', histAx, 'fig', fig, ...
            'sldLow', sldLow, 'sldHigh', sldHigh, 'sldGamma', sldGamma, ...
            'efLow', efLow, 'efHigh', efHigh, 'efGamma', efGamma, ...
            'lblGamma', lblGamma, 'ddColormap', ddColormap, ...
            'ddContrastTransform', ddContrastTransform, ...
            'ddRenderMode', ddRenderMode, 'cbInvert', cbInvert, ...
            'btnLogHist', btnLogHist);
        cb_ = struct( ...
            'onContrastChanged',    @onContrastChanged, ...
            'prepareDisplayBuffer', @prepareDisplayBuffer, ...
            'onGammaChanged',       @onGammaChanged, ...
            'setStatus',            @setStatus, ...
            'refreshHistogramMarkers', @refreshHistogramMarkers, ...
            'refreshDisplay',       @refreshDisplay, ...
            'updateHistogram',      @updateHistogram, ...
            'onInvertToggle',       @onInvertToggle, ...
            'onContrastTransformChanged', @onContrastTransformChanged, ...
            'startHistDrag',        @startHistDrag);
    end

    function ctx = buildProcessCtx()
        ctx.fig            = fig;
        ctx.ax             = ax;
        ctx.sldLow         = sldLow;
        ctx.sldHigh        = sldHigh;
        ctx.ddColormap     = ddColormap;
        ctx.cbScaleBar     = cbScaleBar;
        ctx.cbColorbar     = cbColorbar;
        ctx.btnMacroRecord = btnMacroRecord;
        ctx.BTN_TOOL       = BTN_TOOL;
        ctx.OVERLAY_COLOR  = OVERLAY_COLOR;
        ctx.undoPush             = @undoPush;
        ctx.refreshDisplay       = @refreshDisplay;
        ctx.displayImage         = @displayImage;
        ctx.rebuildAxesForNewSize = @rebuildAxesForNewSize;
        ctx.setStatus            = @setStatus;
        ctx.guiPixelSize         = @guiPixelSize;
        ctx.guiPixelUnit         = @guiPixelUnit;
        ctx.rebuildScaleBar      = @rebuildScaleBar;
        ctx.updateHistogram      = @updateHistogram;
        ctx.updateStatusBar      = @updateStatusBar;
        ctx.prepareDisplayBuffer = @prepareDisplayBuffer;
        ctx.applyContrastPipeline = @applyContrastPipeline;
    end

    function onContrastTransformChanged(~, ~)
        [ui__, cb__] = buildContrastCtx();
        appData = emViewer.contrastOps('transformChanged', appData, ui__, cb__);
        onContrastChanged([], []);
    end

    function onInvertToggle(~, ~)
        [ui__, cb__] = buildContrastCtx();
        appData = emViewer.contrastOps('invertToggle', appData, ui__, cb__);
        onContrastChanged([], []);
    end
    % ════════════════════════════════════════════════════════════════════

    function executeDSpacing(x1, y1, x2, y2)
    %EXECUTEDSPACING  Compute d-spacing from two FFT spots.
        if appData.activeIdx < 1, return; end
        imgInfo = appData.images{appData.activeIdx}.metadata.parserSpecific.imageData;
        if ~imgInfo.calibrated || isnan(imgInfo.pixelSize)
            setStatus('d-spacing requires pixel size calibration.');
            return;
        end
        [H, W] = size(appData.filteredPixels);
        r = emViewer.diffraction.computeDSpacing( ...
            [H W], imgInfo.pixelSize, imgInfo.pixelUnit, x1, y1, x2, y2);
        hold(ax, 'on');
        th = linspace(0, 2*pi, 60);
        for si = 1:numel(r.spots)
            sp = r.spots(si);
            plot(ax, sp.x + sp.radius*cos(th), sp.y + sp.radius*sin(th), '-', ...
                'Color', OVERLAY_COLOR, 'LineWidth', 1.5, ...
                'HandleVisibility', 'off', 'HitTest', 'off');
            text(ax, sp.x + sp.radius + 3, sp.y, ...
                sprintf('d=%.3f %s', sp.dSpacing, imgInfo.pixelUnit), ...
                'Color', OVERLAY_COLOR, 'FontSize', 9, ...
                'HandleVisibility', 'off', 'HitTest', 'off');
        end
        hold(ax, 'off');
        setStatus(r.statusMsg);
    end

    % ════════════════════════════════════════════════════════════════════
    %  PHASE 3: Ellipse ROI
    % ════════════════════════════════════════════════════════════════════
    % onEllipseROI → startTwoClickCapture('roiellipse') via onDrawROI('Circle')

    function executeEllipseROI(cx, cy, ex, ey)
        if isempty(appData.filteredPixels), return; end
        r = sqrt((ex - cx)^2 + (ey - cy)^2);
        if r < 1, setStatus('Circle ROI too small.'); return; end

        s = emViewer.measurement.computeCircleROI(appData.filteredPixels, cx, cy, r);
        if s.empty, setStatus('No pixels in circle ROI.'); return; end

        hold(ax, 'on');
        th = linspace(0, 2*pi, 120);
        plot(ax, cx + r*cos(th), cy + r*sin(th), '-', ...
            'Color', OVERLAY_COLOR, 'LineWidth', 1.5, ...
            'HandleVisibility', 'off', 'HitTest', 'off');
        hold(ax, 'off');

        appData.measurementLog{end+1} = struct('type', 'circleROI', ...
            'cx', cx, 'cy', cy, 'radius', r, ...
            'mean', s.mean, 'std', s.std, 'min', s.min, 'max', s.max, 'area', s.area);
        setStatus(s.statusMsg);
    end

    % ════════════════════════════════════════════════════════════════════
    %  PHASE 3: Image Inversion (Process)
    % ════════════════════════════════════════════════════════════════════
    function onInvertImage(~, ~)
        appData = emViewer.processActions('invert', appData, buildProcessCtx());
    end

    % ════════════════════════════════════════════════════════════════════
    %  PHASE 3: Unsharp Mask / Sharpen
    % ════════════════════════════════════════════════════════════════════
    function onSharpen(~, ~)
        appData = emViewer.processActions('sharpen', appData, buildProcessCtx());
    end

    % ════════════════════════════════════════════════════════════════════
    %  PHASE 3: Image Binning
    % ════════════════════════════════════════════════════════════════════
    function onBinImage(~, ~)
        appData = emViewer.processActions('binImage', appData, buildProcessCtx());
    end

    % ════════════════════════════════════════════════════════════════════
    %  PHASE 3: Morphological Operations
    % ════════════════════════════════════════════════════════════════════
    function onMorphOp(~, ~)
        appData = emViewer.processActions('morphOp', appData, buildProcessCtx());
    end

    % ════════════════════════════════════════════════════════════════════
    %  PHASE 3: Butterworth Bandpass Filter
    % ════════════════════════════════════════════════════════════════════
    function onButterworth(~, ~)
        appData = emViewer.processActions('butterworth', appData, buildProcessCtx());
    end

    function onRadialProfile(~, ~)
        if isempty(appData.filteredPixels), return; end
        try
            emViewer.processing.showRadialProfile(appData.filteredPixels);
            setStatus('Radial profile computed from FFT.');
        catch ME
            setStatus(['Radial profile failed: ' ME.message]);
        end
    end

    function onAzIntegrate(~, ~)
        if isempty(appData.filteredPixels), return; end
        try
            emViewer.processing.showAzimuthalIntegration(appData.filteredPixels);
            setStatus('Azimuthal integration complete.');
        catch ME
            setStatus(['Azimuthal integration failed: ' ME.message]);
        end
    end

    function onSurfacePlot(~, ~)
        if isempty(appData.filteredPixels), return; end
        try
            emViewer.processing.showSurfacePlot(appData.filteredPixels);
            setStatus('Surface plot opened.');
        catch ME
            setStatus(['Surface plot failed: ' ME.message]);
        end
    end

    function onBatchConvert(~, ~)
        appData = emViewer.processActions('batchConvert', appData, buildProcessCtx());
    end

    % ════════════════════════════════════════════════════════════════════
    %  PHASE 3: Custom Colormap
    % ════════════════════════════════════════════════════════════════════
    function onCustomColormap(~, ~)
        [ui__, cb__] = buildContrastCtx();
        appData = emViewer.contrastOps('customColormap', appData, ui__, cb__);
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
        coords = struct('x1',x1,'y1',y1,'x2',x2,'y2',y2);
        annot = emViewer.annotation.drawShape(ax, 'arrow', coords, appData.annotationColor);
        appData.overlays.textAnnotations{end+1} = annot;
        attachAnnotContextMenu(annot, numel(appData.overlays.textAnnotations));
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
        coords = struct('x1',x1,'y1',y1,'x2',x2,'y2',y2);
        annot = emViewer.annotation.drawShape(ax, 'line', coords, appData.annotationColor);
        appData.overlays.textAnnotations{end+1} = annot;
        attachAnnotContextMenu(annot, numel(appData.overlays.textAnnotations));
        setStatus('Line annotation placed.');
    end

    function executeAnnotRect(x1, y1, x2, y2)
        coords = struct('x1',x1,'y1',y1,'x2',x2,'y2',y2);
        annot = emViewer.annotation.drawShape(ax, 'rectangle', coords, appData.annotationColor);
        appData.overlays.textAnnotations{end+1} = annot;
        attachAnnotContextMenu(annot, numel(appData.overlays.textAnnotations));
        setStatus('Rectangle annotation placed.');
    end

    function executeAnnotCircle(cx, cy, ex, ey)
        coords = struct('cx',cx,'cy',cy,'ex',ex,'ey',ey);
        annot = emViewer.annotation.drawShape(ax, 'circle', coords, appData.annotationColor);
        if isempty(fieldnames(annot)) || annot.radius < 1, return; end
        appData.overlays.textAnnotations{end+1} = annot;
        attachAnnotContextMenu(annot, numel(appData.overlays.textAnnotations));
        setStatus(sprintf('Circle annotation placed (r=%.0f px).', annot.radius));
    end

    function profile = runWidthAveragedProfile(x1, y1, x2, y2, width)
        profile = emViewer.measurement.widthAveragedProfile( ...
            appData.filteredPixels, x1, y1, x2, y2, width);
    end

    % ════════════════════════════════════════════════════════════════════
    %  PHASE 3: Helper — rebuild axes after dimension-changing operations
    % ════════════════════════════════════════════════════════════════════
    function rebuildAxesForNewSize()
    %REBUILDAXESFORNEWSIZE  wrapper → emViewer.displayHelpers('rebuildAxes')
        appData = emViewer.displayHelpers('rebuildAxes', appData, buildDisplayCtx());
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
        appData = emViewer.processActions('planeLevel', appData, buildProcessCtx());
    end

    % ── Feature 4: Surface Roughness ───────────────────────────────────
    function onRoughness(~, ~)
        appData = emViewer.processActions('roughness', appData, buildProcessCtx());
    end

    % ── Feature 5: Interface Width Fit ─────────────────────────────────
    function onInterfaceFit(~, ~)
        appData = emViewer.processActions('interfaceFit', appData, buildProcessCtx());
    end

    % ── Feature 13: Multi-class Threshold ──────────────────────────────
    function onMultiOtsu(~, ~)
        appData = emViewer.processActions('multiOtsu', appData, buildProcessCtx());
    end

    % ── Feature 1: Lattice Measure from FFT ────────────────────────────
    % onLatticeMeasure and executeLattice → onDiffractionAction('latticeMeasure'/'latticeExecute')

    % ── Feature 3: GPA Strain Mapping ──────────────────────────────────
    function onGPA(~, ~)
        appData = emViewer.processActions('gpa', appData, buildProcessCtx());
    end

    function executeGPA()
        appData = emViewer.processActions('executeGPA', appData, buildProcessCtx());
    end

    % ── Feature 9: CTF Estimation ──────────────────────────────────────
    function onCTFEstimate(~, ~)
        appData = emViewer.processActions('ctfEstimate', appData, buildProcessCtx());
    end

    % ── Feature 11: Defect Counter ─────────────────────────────────────
    function onDefectCount(~, ~)
        appData = emViewer.processActions('defectCount', appData, buildProcessCtx());
    end

    % ── Feature 8: Back-Projection Preview ─────────────────────────────
    function onBackProject(~, ~)
        appData = emViewer.processActions('backProject', appData, buildProcessCtx());
    end

    % ── Feature 2: Figure Panel Builder ────────────────────────────────
    function onFigureBuilder(~, ~)
        appData = emViewer.processActions('figureBuilder', appData, buildProcessCtx());
    end

    % ── Feature 14: Calibrated Colorbar ────────────────────────────────
    function onCalibratedColorbar(~, ~)
        appData = emViewer.processActions('calibratedColorbar', appData, buildProcessCtx());
    end

    % ── Feature 10: Macro Recorder ─────────────────────────────────────
    function onMacroToggle(~, ~)
        appData = emViewer.processActions('macroToggle', appData, buildProcessCtx());
    end

    % ── Feature 18: Flicker Compare ────────────────────────────────────
    function onFlickerCompare(~, ~)
        appData = emViewer.compareDispatch('flicker', appData, buildCompareCtx());
    end

    function flickerTick()
    %FLICKERTICK  wrapper → emViewer.displayHelpers('flickerTick')
        appData = emViewer.displayHelpers('flickerTick', appData, buildDisplayCtx());
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
    %BUILDCONTEXTMENU  Simple axes context menu -- delegates to emViewer.mouseOps.
        appData = emViewer.mouseOps('buildContextMenu', appData, buildMouseCtx());
    end

    function stats = getMeasStatsAPI()
        stats = appData.measWorkshop.model.aggregateStats();
    end

    function model = getMeasModelAPI()
        if appData.activeIdx >= 1 && appData.activeIdx <= numel(appData.images)
            try
                imgInfo = appData.images{appData.activeIdx}.metadata.parserSpecific.imageData;
                appData.measWorkshop.bindCalibration(imgInfo);
            catch
            end
        end
        try
            [tiltDeg, tiltAxis, ~, tiltGeom] = getTiltState();
            appData.measWorkshop.model.tiltAngle = tiltDeg;
            appData.measWorkshop.model.tiltAxis  = tiltAxis;
            appData.measWorkshop.model.tiltGeom  = tiltGeom;
        catch
        end
        model = appData.measWorkshop.model;
    end

    function closeAll()
        appData.measWorkshop.close(); appData.diffWorkshop.close();
        appData.contrastWS.close(); appData.annotWorkshop.close(); appData.eelsWorkshop.close(); appData.edsWorkshop.close(); appData.procWorkshop.close(); appData.calibWS.close();
        auxFigs = [appData.eelsKKFig, appData.eelsSVDFig, appData.eelsFig, appData.eelsELNESFig];
        for f = auxFigs
            if ~isempty(f) && ishandle(f), close(f); end
        end
        close(fig);
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
    %  Logic extracted to +emViewer/+eels/dispatch.m via ctx pattern.
    % ════════════════════════════════════════════════════════════════════

    function ctx = buildEELSCtx()
        ctx.ax  = ax;
        ctx.fig = fig;
        ctx.btnEnterEELS        = btnEnterEELS;
        ctx.edtEELSPreEdgeStart = edtEELSPreEdgeStart;
        ctx.edtEELSPreEdgeEnd   = edtEELSPreEdgeEnd;
        ctx.edtEELSSignalStart  = edtEELSSignalStart;
        ctx.edtEELSSignalEnd    = edtEELSSignalEnd;
        ctx.edtEELSEdgeOnset    = edtEELSEdgeOnset;
        ctx.ddEELSMethod        = ddEELSMethod;
        ctx.chkShowEdges        = chkShowEdges;
        ctx.ddEdgeFilter        = ddEdgeFilter;
        ctx.BTN_DANGER          = BTN_DANGER;
        ctx.BTN_PRIMARY         = BTN_PRIMARY;
        ctx.cb.setStatus        = @setStatus;
        ctx.cb.setToolsEnabled  = @setToolsEnabled;
        ctx.cb.displayImage     = @displayImage;
        ctx.cb.exitCompareMode  = @exitCompareMode;
        ctx.cb.onCaptureClick   = @onCaptureClick;
        ctx.cb.onIdleMouseDown  = @onIdleMouseDown;
    end

    function onEnterEELS(~, ~)
        ctx = buildEELSCtx();
        appData = emViewer.eels.dispatch('enter', appData, ctx);
    end

    function onExitEELS()
        ctx = buildEELSCtx();
        appData = emViewer.eels.dispatch('exit', appData, ctx);
    end

    function showEELSSpectrum()
        if isempty(appData.eelsData), return; end
        appData.eelsFig = emViewer.eels.showSpectrum( ...
            appData.eelsData.energyAxis, double(appData.eelsData.counts), ...
            appData.eelsFig);
    end

    function onEELSAction(action)
        ctx = buildEELSCtx();
        appData = emViewer.eels.dispatch(action, appData, ctx);
    end

    function eelsBackgroundAPI(fitWin)
        edtEELSPreEdgeStart.Value = num2str(fitWin(1));
        edtEELSPreEdgeEnd.Value   = num2str(fitWin(2));
        onEELSAction('bgFit');
    end

    function eelsExtractMapAPI(sigWin, bgWin)
        edtEELSSignalStart.Value = num2str(sigWin(1));
        edtEELSSignalEnd.Value   = num2str(sigWin(2));
        if nargin >= 2 && ~isempty(bgWin)
            edtEELSPreEdgeStart.Value = num2str(bgWin(1));
            edtEELSPreEdgeEnd.Value   = num2str(bgWin(2));
        end
        onEELSAction('extractMap');
    end

    function onEELSAdvanced(action)
        ctx = buildEELSCtx();
        appData = emViewer.eels.dispatch(action, appData, ctx);
    end

    function onEELSNavigateToggle(src, ~)
        ctx = buildEELSCtx();
        ctx.btnNavToggle = src;
        if src.Value
            appData = emViewer.eels.dispatch('navigateOn', appData, ctx);
        else
            appData = emViewer.eels.dispatch('navigateOff', appData, ctx);
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  DIFFRACTION INDEXING CALLBACKS
    % ════════════════════════════════════════════════════════════════════

    % onAutoDetectSpots/onClickDiffSpot/onClearDiffSpots/drawDiffSpots/
    % onMatchDiffraction/onOverlayDiffRings/onSimulateDiffraction →
    % onDiffractionAction('autoDetect'/'clickSpot'/'clearSpots'/etc.)

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
        appData.edsWorkshop.sync(appData);
    end

    function onCompositionProfile(~, ~)
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
        edtEELSEdgeOnset.Value = num2str(onset);
        onEELSAdvanced('elnes');
    end

    function eelsNavigateAPI(row, col)
        ctx = buildEELSCtx();
        ctx.apiRow = row;
        ctx.apiCol = col;
        appData = emViewer.eels.dispatch('navigateAPI', appData, ctx);
    end

    function res = eelsSVDAPI(nComp)
        if isempty(appData.eelsCube), res = []; return; end
        res = imaging.eelsSVD(appData.eelsCube, appData.eelsEnergyAxis, ...
            NumComponents=nComp);
        appData.eelsSVDResult = res;
    end

    function simDiffAPI(phase, za)
    %SIMDIFFAPI  Programmatic diffraction simulation for given phase and zone axis.
        edtZoneAxis.Value = sprintf('%d %d %d', za);
        if ~isempty(appData.diffResults) && ~isempty(appData.diffResults.candidates)
            appData.diffResults.candidates(1).phaseName = phase;
            appData.diffWorkshop.model.setResults(appData.diffResults);
        end
        onDiffractionAction('simulate');
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
