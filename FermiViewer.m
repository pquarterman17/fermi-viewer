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
    btnEDSToolbar = tb_.btnEDSToolbar;

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
    %  CALLBACK: onMouseMotion — Track mouse over axes, show pixel info
    % ════════════════════════════════════════════════════════════════════
    function onMouseMotion(~, ~)
        % Panel resize border detection: skip during capture mode
        if isempty(appData.captureMode) || strcmp(appData.captureMode, '')
            dir = detectResizeBorder();
            appData.panelResizeDir = dir;
            if     ~isempty(dir) && startsWith(dir, 'v_'), fig.Pointer = 'left';
            elseif ~isempty(dir) && startsWith(dir, 'h_'), fig.Pointer = 'top';
            elseif appData.panMode,                        fig.Pointer = 'hand';
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
        ddScaleBarColor.Enable = onOff(isCalib);
        spnScaleBarFont.Enable  = onOff(isCalib);
        efScaleBarLen.Enable    = onOff(isCalib);
        ddScaleBarUnit.Enable   = onOff(isCalib);
        if isCalib
            rebuildScaleBar();
        end
        btnLineProfile.Enable   = 'on';
        btnBoxProfile.Enable    = 'on';
        btnDistance.Enable      = 'on';
        btnAngle.Enable        = 'on';
        btnClearOverlays.Enable = 'on';
        btnRemoveMeas.Enable    = 'on';
        spnMeasLabelFont.Enable = 'on';
        ddMeasSymbol.Enable     = 'on';
        ddMeasColor.Enable      = 'on';
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
        ddROIShape.Enable     = 'on';
        btnDrawROI.Enable     = 'on';
        btnZoomBox.Enable     = 'on';
        btnZoomDims.Enable    = 'on';
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
        btnUndoAnnot.Enable   = 'on';
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
        btnBoxProfile.Enable    = 'off';
        btnDistance.Enable      = 'off';
        btnExportProfile.Enable = 'off';
        btnAngle.Enable         = 'off';
        btnClearOverlays.Enable = 'off';
        btnRemoveMeas.Enable    = 'off';
        cbScaleBar.Enable       = 'off';
        ddScaleBarColor.Enable = 'off';
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
        ddROIShape.Enable     = 'off';
        btnDrawROI.Enable     = 'off';
        btnZoomBox.Enable     = 'off';
        btnZoomDims.Enable    = 'off';
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
        btnUndoAnnot.Enable   = 'off';
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
        taMetadata.Value = emViewer.display.formatMetadata(appData.images{appData.activeIdx});
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

        appData.imgHandle.CData = dispImg;
        appData.contrastWS.setLimits(lo, hi);
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

        pLow  = imaging.percentile(appData.filteredPixels(:), 2);
        pHigh = imaging.percentile(appData.filteredPixels(:), 98);

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

        appData.gamma = 1.0;
        sldGamma.Value = 1.0;
        efGamma.Value = 1.0;
        lblGamma.Text = 'Gamma';
        appData.contrastWS.setGamma(1.0);

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
        if isempty(appData.filteredPixels), return; end
        answer = inputdlg({'Sigma (pixels):  [positive number, e.g. 1.5]'}, ...
            'Gaussian Filter', [1 44], {'1.5'});
        if isempty(answer), return; end
        sigma = str2double(answer{1});
        if isnan(sigma) || sigma <= 0
            uialert(fig, 'Sigma must be a positive number.', 'Invalid Input', 'Icon', 'error');
            return;
        end
        fig.Pointer = 'watch'; drawnow;
        try
            undoPush();
            r = emViewer.processing.executeFilter(appData.filteredPixels, 'gaussian', struct('sigma', sigma));
            appData.filteredPixels = r.pixels;
            refreshDisplay();
            setStatus(r.statusMsg);
        catch ME
            uialert(fig, sprintf('Gaussian filter failed:\n%s', ME.message), 'Filter Error', 'Icon', 'error');
        end
        fig.Pointer = 'arrow';
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onMedianFilter — Prompt for window size and apply median
    % ════════════════════════════════════════════════════════════════════
    function onMedianFilter(~, ~)
        if isempty(appData.filteredPixels), return; end
        answer = inputdlg({'Window size (3, 5, or 7):'}, 'Median Filter', [1 36], {'3'});
        if isempty(answer), return; end
        wSize = round(str2double(answer{1}));
        if isnan(wSize) || ~ismember(wSize, [3 5 7])
            uialert(fig, 'Window size must be 3, 5, or 7.', 'Invalid Input', 'Icon', 'error');
            return;
        end
        fig.Pointer = 'watch'; drawnow;
        try
            undoPush();
            r = emViewer.processing.executeFilter(appData.filteredPixels, 'median', struct('windowSize', wSize));
            appData.filteredPixels = r.pixels;
            refreshDisplay();
            setStatus(r.statusMsg);
        catch ME
            uialert(fig, sprintf('Median filter failed:\n%s', ME.message), 'Filter Error', 'Icon', 'error');
        end
        fig.Pointer = 'arrow';
    end

    % ════════════════════════════════════════════════════════════════════
    %  CALLBACK: onShowFFT — Compute and display FFT magnitude in new figure
    % ════════════════════════════════════════════════════════════════════
    function onShowFFT(~, ~)
        if isempty(appData.filteredPixels), return; end
        fig.Pointer = 'watch'; drawnow;
        titleStr = 'FFT';
        if appData.activeIdx >= 1
            [~, fname, fext] = fileparts(appData.images{appData.activeIdx}.metadata.source);
            titleStr = sprintf('FFT — %s%s', fname, fext);
        end
        emViewer.processing.showFFT(appData.filteredPixels, titleStr);
        fig.Pointer = 'arrow';
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
        if ~ismember(appData.captureMode, {'zoom', 'crop', 'savecrop', 'rectROI', 'batchcrop'})
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
                case 'rectROI'
                    setStatus('Click second corner for Rect ROI... (Esc to cancel)');
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
                    onExportAction('saveCroppedRegion', xMin, xMax, yMin, yMax);

                case 'rectROI'
                    executeRectROI(xMin, xMax, yMin, yMax);

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
    %  HELPER: executeRectROI — Draw persistent rectangle ROI + stats
    %  Registers the ROI as a measurement record so it can be clicked to
    %  select, deleted via the Delete key or marquee, and removed by
    %  Clear All alongside distance/profile/polyline measurements.
    % ════════════════════════════════════════════════════════════════════
    function executeRectROI(xMin, xMax, yMin, yMax)
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

        % Draw the ROI rectangle on the main image (persistent overlay).
        % Leave HitTest on so the user can click it to select, and tie
        % ButtonDownFcn to selectMeasurement like other measurement types.
        measClr = ddMeasColor.Value;
        if isempty(measClr), measClr = OVERLAY_COLOR; end
        hRect = rectangle(ax, 'Position', [xMin yMin xMax-xMin yMax-yMin], ...
            'EdgeColor', measClr, ...
            'LineWidth', 1.5, ...
            'LineStyle', '-', ...
            'HandleVisibility', 'off');

        % Register as a measurement so Delete / marquee / selection work.
        meas = struct();
        meas.type      = 'rectROI';
        meas.hRect     = hRect;
        meas.hLine     = hRect;   % aliased so existing highlight paths find it
        meas.hP1       = [];
        meas.hP2       = [];
        meas.hText     = [];
        meas.lineColor = measClr;
        meas.xMin      = xMin;
        meas.xMax      = xMax;
        meas.yMin      = yMin;
        meas.yMax      = yMax;
        meas.stats     = struct('mean', roiMean, 'std', roiStd, ...
                                'min', roiMin, 'max', roiMax, 'area', roiArea);
        midx = numel(appData.overlays.measurements) + 1;
        appData.overlays.measurements{midx} = meas;
        appData.measWorkshop.sync(appData.overlays.measurements);

        % Click the rectangle outline to (re)select it.
        hRect.HitTest = 'on';
        hRect.PickableParts = 'visible';
        hRect.ButtonDownFcn = @(~,~) selectMeasurement(midx);

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

        setStatus(sprintf('Rect ROI: mean=%.1f std=%.1f min=%.0f max=%.0f area=%s', ...
            roiMean, roiStd, roiMin, roiMax, areaStr));
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

        displayCounts = counts;
        if appData.histLogScale
            displayCounts = log10(counts + 1);
        end

        cla(histAx);
        bar(histAx, binCenters, displayCounts, 1, ...
            'FaceColor', [0.5 0.5 0.5], ...
            'EdgeColor', 'none', ...
            'FaceAlpha', 0.8);

        if edges(end) > edges(1)
            histAx.XLim = [edges(1), edges(end)];
        end
        yMax = max(displayCounts);
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
    %  CALLBACK: onHistAxesClick — Detect click on histogram; start drag
    % ════════════════════════════════════════════════════════════════════
    function onHistAxesClick()
        if isempty(appData.filteredPixels), return; end
        cp = histAx.CurrentPoint;
        px = cp(1,1);
        lo = sldLow.Value;
        hi = sldHigh.Value;
        span = max(hi - lo, eps);

        % Edge-snap threshold: 8% of the contrast window or 4% of the
        % visible x-range, whichever is larger. Prevents accidental
        % handle snaps when the user really wanted brightness/contrast
        % drag inside the window.
        xSpan   = diff(histAx.XLim);
        edgeTol = max(0.08 * span, 0.04 * xSpan);

        dLo = abs(px - lo);
        dHi = abs(px - hi);
        if hi > lo
            midX = lo + span * 0.5^(1/appData.gamma);
            dMid = abs(px - midX);
        else
            dMid = Inf;
        end

        % Inside the contrast window and away from all three handles → B/C drag.
        if px > lo + edgeTol && px < hi - edgeTol && ...
                dLo > edgeTol && dHi > edgeTol && dMid > edgeTol
            startHistDrag('bc');
            return;
        end

        [~, closest] = min([dLo, dHi, dMid]);
        targets = {'lo', 'hi', 'gamma'};
        startHistDrag(targets{closest});
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: startHistDrag — Drag a histogram contrast handle
    % ════════════════════════════════════════════════════════════════════
    function startHistDrag(which)
        origMotionFcn  = fig.WindowButtonMotionFcn;
        origReleaseFcn = fig.WindowButtonUpFcn;
        fig.Pointer = 'left';
        fig.WindowButtonMotionFcn = @histDragMotion;
        fig.WindowButtonUpFcn    = @histDragRelease;

        % Initial state used by 'bc' (brightness/contrast) drag.
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
                % Brightness/contrast drag (ImageJ-style):
                %   horizontal motion → shift window (brightness)
                %   vertical motion   → resize window (contrast)
                axPos = getpixelposition(histAx, true);
                if axPos(3) <= 0 || axPos(4) <= 0, return; end
                curPt = fig.CurrentPoint;
                dxPx = curPt(1) - bcStartFigPt(1);
                dyPx = curPt(2) - bcStartFigPt(2);

                origSpan  = max(bcStartHi - bcStartLo, gap);
                dataPerPx = (lims_(2) - lims_(1)) / axPos(3);
                shift     = dxPx * dataPerPx;
                % Vertical: half-pixel up = shrink span by 0.4%/px.
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
        appData.histLogScale = src.Value;
        updateHistogram();
    end

    function setHistLogAPI(tf)
        appData.histLogScale = tf;
        btnLogHist.Value = tf;
        updateHistogram();
    end

    function onScrollWheelContrast(~, evt)
    %ONSCROLLWHEELCONTRAST  Scroll-wheel over histogram adjusts contrast window.
        if isempty(appData.filteredPixels), return; end
        if ~isvalid(histAx), return; end
        figPos = fig.CurrentPoint;
        axPos  = getpixelposition(histAx, true);
        if figPos(1) < axPos(1) || figPos(1) > axPos(1)+axPos(3) || ...
           figPos(2) < axPos(2) || figPos(2) > axPos(2)+axPos(4)
            return;
        end

        lo = sldLow.Value;
        hi = sldHigh.Value;
        span = hi - lo;
        step = span * 0.04 * evt.VerticalScrollCount;
        lims = sldLow.Limits;
        gap  = (lims(2) - lims(1)) * 0.001;
        newLo = max(lims(1), lo + step);
        newHi = min(lims(2), hi - step);
        if newHi - newLo < gap, return; end
        sldLow.Value  = newLo;
        sldHigh.Value = newHi;
        onContrastChanged([], []);
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
                if isstruct(params) && isfield(params, 'Sigma'), sigma = params.Sigma; end
                p = struct('sigma', sigma);
            case 'median'
                wSize = 3;
                if isstruct(params) && isfield(params, 'WindowSize'), wSize = params.WindowSize; end
                p = struct('windowSize', wSize);
            otherwise
                warning('FermiViewer:unknownFilter', 'Unknown filter type "%s".', type);
                return;
        end
        r = emViewer.processing.executeFilter(appData.filteredPixels, type, p);
        appData.filteredPixels = r.pixels;
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
    function rebuildScaleBar()
        % Snapshot existing bar/label positions BEFORE delete so that user
        % drag offsets survive a property change (color, font, length, unit).
        snapSingle = emViewer.snapScaleBarPos(appData.overlays.scalebar);
        snapL      = emViewer.snapScaleBarPos(appData.overlays.scalebarL);
        snapR      = emViewer.snapScaleBarPos(appData.overlays.scalebarR);

        deleteScaleBar();

        % Read RGB directly from SSoT
        barColor = appData.scaleBarColor;
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
                    tgtAx = axL;  idx = appData.compareIdxL;  prevSnap = snapL;
                else
                    tgtAx = axR;  idx = appData.compareIdxR;  prevSnap = snapR;
                end
                if isempty(tgtAx) || ~isvalid(tgtAx), continue; end
                if idx < 1 || idx > numel(appData.images), continue; end
                imgI = appData.images{idx}.metadata.parserSpecific.imageData;
                if ~imgI.calibrated, continue; end
                hB = imaging.addScaleBar(tgtAx, imgI.pixelSize, imgI.pixelUnit, ...
                    'Color', barColor, 'FontSize', fontSize, lenArgs{:});
                emViewer.applyScaleBarPos(hB, prevSnap);
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
            emViewer.applyScaleBarPos(hBar, snapSingle);
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
            appData.diffWorkshop.model.spots = appData.diffSpots;
            onDiffractionAction('drawSpots');
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
                case 'boxprofile'
                    executeBoxProfile(x1, y1, x2, y2, appData.boxProfileWidth);
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
                    onDiffractionAction('latticeExecute');
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
            'RowHeight', {32, '1x', 0}, 'Padding', [2 2 2 2], ...
            'RowSpacing', 2);

        % Re-build the icon transform toolbar (row 1). Mirrors the block
        % in the main builder above — kept inline in both places to stay
        % under MATLAB's nested-function cap.
        rcToolbarGL = uigridlayout(axGL, [1 15], ...
            'ColumnWidth', {28, 28, 4, 28, 28, 4, 28, 28, 28, 4, 28, 28, 4, 28, '1x'}, ...
            'RowHeight',   {28}, ...
            'Padding',     [2 2 2 2], ...
            'ColumnSpacing', 0);
        rcToolbarGL.Layout.Row = 1;
        rcIconDir = fullfile(fileparts(mfilename('fullpath')), ...
                             'icons', 'fermiviewer');
        rcResetFcn = @(~,~) setActiveIdxAPI(getActiveIdxAPI());
        rcSpecs = {
            'rot_cw.png',    'CW',    'Rotate 90° clockwise',                                   @(~,~) onRotateFlip('rot90cw'),  'push';
            'rot_ccw.png',   'CCW',   'Rotate 90° counter-clockwise',                           @(~,~) onRotateFlip('rot90ccw'), 'push';
            'flip_h.png',    'FH',    'Flip horizontally (left-right mirror)',                  @(~,~) onRotateFlip('fliph'),    'push';
            'flip_v.png',    'FV',    'Flip vertically (top-bottom mirror)',                    @(~,~) onRotateFlip('flipv'),    'push';
            'zoom.png',      'Z',     'Drag-to-zoom mode (toggle off for marquee-select)',      @(s,e) onDragModeToggle(s,e,'zoom'), 'state';
            'pan.png',       'Pan',   'Pan mode — drag to scroll when zoomed in (middle-drag always pans)', @(s,e) onDragModeToggle(s,e,'pan'), 'state';
            'fit.png',       'Fit',   'Fit image to window (reset zoom)',                       @onResetZoom,                    'push';
            'reset_all.png', 'Reset', 'Reset all transforms (reload original image)',           rcResetFcn,                      'push';
            'crop.png',      'Crop',  'Crop to rectangle (destructive — Undo Filters reverts)', @onCropImage,                    'push';
            'del_annot.png', '⌫',     'Delete last annotation (Delete key)',                    @(~,~) onAnnotationAction('undoLast'), 'push';
        };
        rcCols = [1, 2, 4, 5, 7, 8, 9, 11, 12, 14];
        rcBtns = gobjects(1, size(rcSpecs, 1));
        for rcK = 1:size(rcSpecs, 1)
            rcP = fullfile(rcIconDir, rcSpecs{rcK, 1});
            isState = strcmp(rcSpecs{rcK, 5}, 'state');
            cbProp  = 'ButtonPushedFcn';
            btnType = {};
            if isState
                cbProp  = 'ValueChangedFcn';
                btnType = {'state'};
            end
            if isfile(rcP)
                rcBtns(rcK) = uibutton(rcToolbarGL, btnType{:}, ...
                    'Icon', rcP, 'Text', '', 'IconAlignment', 'center', ...
                    'BackgroundColor', BTN_TOOL, ...
                    'Tooltip', rcSpecs{rcK, 3}, ...
                    cbProp, rcSpecs{rcK, 4}, ...
                    'Enable', 'on');
            else
                rcBtns(rcK) = uibutton(rcToolbarGL, btnType{:}, ...
                    'Text', rcSpecs{rcK, 2}, 'FontSize', 11, ...
                    'BackgroundColor', BTN_TOOL, ...
                    'FontColor', BTN_FG, ...
                    'Tooltip', rcSpecs{rcK, 3}, ...
                    cbProp, rcSpecs{rcK, 4}, ...
                    'Enable', 'on');
            end
            if isState
                if rcK == 5,     rcBtns(rcK).Value = appData.zoomMode;
                elseif rcK == 6, rcBtns(rcK).Value = appData.panMode;
                end
            end
            rcBtns(rcK).Layout.Row = 1;
            rcBtns(rcK).Layout.Column = rcCols(rcK);
        end
        appData.transformToolbarBtns = rcBtns;
        appData.toolbarIconPaths = cellfun( ...
            @(f) fullfile(rcIconDir, f), rcSpecs(:,1), 'UniformOutput', false)';

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
            'FontSize', 11, 'HorizontalAlignment', 'center', ...
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
        pLow  = imaging.percentile(rawGray(:), 2);
        pHigh = imaging.percentile(rawGray(:), 98);
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
            'Interpreter', 'none', 'FontSize', 11);

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
        barColor = appData.scaleBarColor;
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
        btnBoxProfile.Enable    = state;
        btnDistance.Enable      = state;
        btnAngle.Enable        = state;
        btnExportProfile.Enable = state;
        btnClearOverlays.Enable = state;
        btnRemoveMeas.Enable    = state;
        btnRotCW.Enable        = state;
        btnRotCCW.Enable       = state;
        btnFlipH.Enable        = state;
        btnFlipV.Enable        = state;
        btnGaussian.Enable     = state;
        btnMedian.Enable       = state;
        btnShowFFT.Enable      = state;
        btnCLAHE.Enable        = state;
        btnUndoFilters.Enable  = state;
        % (Rect ROI is now reached via ddROIShape + btnDrawROI above)
        btnZoomBox.Enable      = state;
        btnZoomDims.Enable     = state;
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
        btnUndoAnnot.Enable    = state;
        ddAnnotColor.Enable    = state;
        cbColorbar.Enable      = state;
        % Phase 3 buttons
        btnDSpacing.Enable      = state;
        spnProfileWidth.Enable  = state;
        ddROIShape.Enable       = state;
        btnDrawROI.Enable       = state;
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
        ddMeasSymbol.Enable       = state;
        ddMeasColor.Enable        = state;
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
    %ONIDLEMOUSEDOWN  Figure-level mouse-down in idle mode — starts resize if near border.
        if strcmp(fig.SelectionType, 'alt'), return; end   % right-click: skip
        if ~isempty(appData.panelResizeDir)
            startPanelResize();
            return;
        end
        % Click on empty canvas deselects any highlighted measurement
        % and any marquee-selected annotations. A measurement's own
        % ButtonDownFcn fires AFTER this figure-level callback, so
        % clicks directly on a measurement re-select it via
        % selectMeasurement — no flicker, no missed highlights.
        if appData.selectedMeasIdx > 0 || ~isempty(appData.selectedMeasIndices)
            deselectMeasurement();
        end
        if appData.selectedAnnotIdx > 0 || ~isempty(appData.selectedAnnotIndices)
            for ai = appData.selectedAnnotIndices(:)'
                if ai >= 1 && ai <= numel(appData.overlays.textAnnotations)
                    highlightAnnotation(appData.overlays.textAnnotations{ai}, false);
                end
            end
            if appData.selectedAnnotIdx > 0 && ...
                    appData.selectedAnnotIdx <= numel(appData.overlays.textAnnotations)
                highlightAnnotation( ...
                    appData.overlays.textAnnotations{appData.selectedAnnotIdx}, false);
            end
            appData.selectedAnnotIndices = [];
            appData.selectedAnnotIdx = 0;
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  BOX-ZOOM: click-drag rubber-band on image axes, double-click reset
    % ════════════════════════════════════════════════════════════════════
    function onAxesMouseDown(~, ~)
    %ONAXESMOUSEDOWN  Image-axes ButtonDownFcn: box-zoom, pan, or double-click reset.
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

        % Determine drag action: middle-click always pans, panMode left-click
        % pans, otherwise zoom/marquee as before.
        wantPan = strcmp(selType, 'extend') || ...
                  (appData.panMode && strcmp(selType, 'normal'));

        cp = ax.CurrentPoint;
        appData.prevMotionFcn = fig.WindowButtonMotionFcn;
        appData.prevUpFcn     = fig.WindowButtonUpFcn;

        if wantPan
            appData.dragAction   = 'pan';
            appData.panStartXY   = cp(1, 1:2);
            appData.panStartLims = struct('XLim', ax.XLim, 'YLim', ax.YLim);
            fig.Pointer = 'hand';
        else
            appData.dragAction   = 'zoomMarquee';
            appData.zoomStartXY  = cp(1, 1:2);
            appData.zoomRect     = [];
        end

        fig.WindowButtonMotionFcn = @onBoxZoomDrag;
        fig.WindowButtonUpFcn     = @onBoxZoomRelease;
    end

    function onBoxZoomDrag(~, ~)
    %ONBOXZOOMDRAG  Motion handler for drag interactions (zoom/marquee/pan).
        if strcmp(appData.dragAction, 'pan')
            if isempty(appData.panStartXY), return; end
            cp = ax.CurrentPoint;
            [H, W] = size(appData.rawPixels);
            [newXLim, newYLim] = emViewer.computePanLimits( ...
                appData.panStartXY, cp(1,1:2), appData.panStartLims, H, W);
            ax.XLim = newXLim;
            ax.YLim = newYLim;
            return;
        end

        % ── Zoom / marquee: rubber-band rectangle ──
        p0 = appData.zoomStartXY;
        if isempty(p0), return; end
        cp = ax.CurrentPoint;
        x0 = min(p0(1), cp(1,1));  x1 = max(p0(1), cp(1,1));
        y0 = min(p0(2), cp(1,2));  y1 = max(p0(2), cp(1,2));
        w = max(1e-6, x1 - x0);    h = max(1e-6, y1 - y0);
        if isempty(appData.zoomRect) || ~isvalid(appData.zoomRect)
            if w < 10 && h < 10, return; end
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
    %ONBOXZOOMRELEASE  End of drag. Pan: restores cursor. Zoom/marquee:
    %   applies box-zoom or selects items inside the rectangle.
        wasPan = strcmp(appData.dragAction, 'pan');
        appData.dragAction = '';

        if wasPan
            appData.panStartXY   = [];
            appData.panStartLims = [];
            fig.WindowButtonMotionFcn = appData.prevMotionFcn;
            fig.WindowButtonUpFcn     = appData.prevUpFcn;
            appData.prevMotionFcn = '';
            appData.prevUpFcn     = '';
            if appData.panMode
                fig.Pointer = 'hand';
            else
                fig.Pointer = 'arrow';
            end
            return;
        end

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
        % Apply only if drag covers > 15 data units in both dims — matches the
        % deferred-rectangle threshold and further rejects tiny accidental drags.
        if isempty(pos) || pos(3) < 15 || pos(4) < 15
            return;
        end
        xMin = pos(1); xMax = pos(1) + pos(3);
        yMin = pos(2); yMax = pos(2) + pos(4);
        if appData.zoomMode
            ax.XLim = [xMin, xMax];
            ax.YLim = [yMin, yMax];
        else
            applyMarqueeSelection(xMin, xMax, yMin, yMax);
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
        uimenu(cmImage, 'Text', 'Zoom Out (2×)', ...
            'MenuSelectedFcn', @(~,~) onZoomOut([], []));
        uimenu(cmImage, 'Text', 'Zoom to Dimensions…', ...
            'MenuSelectedFcn', @(~,~) onZoomBox([], [], 'dims'));
        uimenu(cmImage, 'Text', 'Toggle Pan Mode', ...
            'MenuSelectedFcn', @(~,~) onDragModeToggle(struct('Value', ~appData.panMode), [], 'pan'));
        uimenu(cmImage, 'Text', 'Copy to Clipboard', ...
            'Separator', 'on', ...
            'MenuSelectedFcn', @(~,~) onExportAction('copyClipboard'));
        uimenu(cmImage, 'Text', 'Save Image As…', ...
            'MenuSelectedFcn', @(~,~) onExportAction('saveImage'));
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
        ui_.lblSep           = lblSep;
        ui_.lblSep2          = lblSep2;
        ui_.lblSep3          = lblSep3;
        ui_.lblSep4          = lblSep4;
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
            case 'boxprofile'
                setStatus(sprintf('Box profile (width %d px): click first point... (Escape to cancel)', ...
                    appData.boxProfileWidth));
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
        measClr = ddMeasColor.Value;
        if isempty(measClr), measClr = OVERLAY_COLOR; end
        hLine = line(ax, [x1 x2], [y1 y2], ...
            'Color',            measClr, ...
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
        hP1 = createEndpointMarker(x1, y1, ddMeasSymbol.Value, measClr);
        hP2 = createEndpointMarker(x2, y2, ddMeasSymbol.Value, measClr);

        % Build measurement record
        meas.type      = 'profile';
        meas.hLine     = hLine;
        meas.hP1       = hP1;
        meas.hP2       = hP2;
        meas.hText     = [];   % profiles don't have a midpoint label
        meas.lineColor = measClr;
        meas.endSymbol = ddMeasSymbol.Value;
        midx = numel(appData.overlays.measurements) + 1;
        appData.overlays.measurements{midx} = meas;
        appData.measWorkshop.sync(appData.overlays.measurements);

        % Attach drag + selection callbacks
        hP1.ButtonDownFcn   = @(~,~) startEndpointDrag(midx, 1);
        hP2.ButtonDownFcn   = @(~,~) startEndpointDrag(midx, 2);
        hLine.ButtonDownFcn = @(~,~) selectMeasurement(midx);
        hLine.HitTest = 'on'; hLine.PickableParts = 'all';
        hLine.ContextMenu = buildMeasLineMenu(hLine);

        % Run the profile computation
        runProfile(x1, y1, x2, y2);
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: executeBoxProfile — Rotated-rectangle integrated profile
    %  Draws a rotated rectangle overlay from the two clicks expanded by
    %  ±width/2 perpendicular, then delegates computation to the shared
    %  runWidthAveragedProfile engine (used by Line Profile when the
    %  spinner value > 1). The box is tagged 'box_profile' so Clear All
    %  (via findall) can remove it.
    % ════════════════════════════════════════════════════════════════════
    function executeBoxProfile(x1, y1, x2, y2, width)
        dx = x2 - x1; dy = y2 - y1;
        L = hypot(dx, dy);
        if L < 1
            setStatus('Box profile: endpoints too close.');
            return;
        end
        ux = -dy / L; uy = dx / L;    % perpendicular unit vector
        h = width / 2;
        corners = [
            x1 + h*ux, y1 + h*uy;
            x2 + h*ux, y2 + h*uy;
            x2 - h*ux, y2 - h*uy;
            x1 - h*ux, y1 - h*uy
        ];

        % Clear temporary click markers before drawing the box
        for ci = 1:numel(appData.overlays.clickMarkers)
            hh = appData.overlays.clickMarkers{ci};
            if isvalid(hh), delete(hh); end
        end
        appData.overlays.clickMarkers = {};

        measClr = ddMeasColor.Value;
        if isempty(measClr), measClr = OVERLAY_COLOR; end

        % Filled rotated rectangle (translucent) + dashed center line
        patch(ax, corners(:,1), corners(:,2), measClr, ...
            'FaceAlpha',        0.12, ...
            'EdgeColor',        measClr, ...
            'LineWidth',        1.2, ...
            'Tag',              'box_profile', ...
            'HandleVisibility', 'off', ...
            'HitTest',          'off');
        line(ax, [x1 x2], [y1 y2], ...
            'Color',            measClr, ...
            'LineWidth',        1.2, ...
            'LineStyle',        '--', ...
            'Tag',              'box_profile', ...
            'HandleVisibility', 'off', ...
            'HitTest',          'off');

        % Compute the averaged profile using the existing engine
        try
            prof = runWidthAveragedProfile(x1, y1, x2, y2, width);
        catch ME
            uialert(fig, sprintf('Box profile failed:\n%s', ME.message), ...
                'Error', 'Icon', 'error');
            return;
        end

        dist      = prof.dist;
        intensity = prof.intensity;

        % Pixel-size calibration for the distance axis
        pu = 'px';
        if appData.activeIdx >= 1
            imgInfo = appData.images{appData.activeIdx}.metadata.parserSpecific.imageData;
            if imgInfo.calibrated && ~isnan(imgInfo.pixelSize)
                dist = dist * imgInfo.pixelSize;
                pu   = char(imgInfo.pixelUnit);
                if isempty(pu), pu = 'px'; end
            end
        end

        % Stash for CSV export (reuses the Line Profile export button)
        appData.lastProfile = struct('dist', dist, 'intensity', intensity, 'unit', pu);
        btnExportProfile.Enable = 'on';

        if ~strcmp(pu, 'px') && ~isempty(dist)
            setStatus(sprintf('Box profile: length %.4g %s, width %d px (averaged across %d lines)', ...
                dist(end), pu, width, width));
        else
            setStatus(sprintf('Box profile: length %.1f px, width %d px', L, width));
        end

        emViewer.measurement.plotProfileFigure(dist, intensity, pu, ...
            sprintf('Box Profile (width = %d px)', width), ...
            YLabel='Mean intensity');
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: executeMeasureDistance — Draw line and annotate distance
    % ════════════════════════════════════════════════════════════════════
    function executeMeasureDistance(x1, y1, x2, y2)
        measClr = ddMeasColor.Value;
        if isempty(measClr), measClr = OVERLAY_COLOR; end
        hLine = line(ax, [x1 x2], [y1 y2], ...
            'Color',            measClr, ...
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
        hP1 = createEndpointMarker(x1, y1, ddMeasSymbol.Value, measClr);
        hP2 = createEndpointMarker(x2, y2, ddMeasSymbol.Value, measClr);

        % Create midpoint distance label
        hTxt = createDistanceLabel(x1, y1, x2, y2);

        % Build measurement record
        meas.type      = 'distance';
        meas.hLine     = hLine;
        meas.hP1       = hP1;
        meas.hP2       = hP2;
        meas.hText     = hTxt;
        meas.lineColor = measClr;
        meas.endSymbol = ddMeasSymbol.Value;
        % Store distance value in calibrated units (or px if uncalibrated),
        % so emViewer.measurements('aggregateStats') can aggregate across measurements.
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
        appData.measWorkshop.sync(appData.overlays.measurements);

        % Attach drag + selection callbacks
        hP1.ButtonDownFcn   = @(~,~) startEndpointDrag(midx, 1);
        hP2.ButtonDownFcn   = @(~,~) startEndpointDrag(midx, 2);
        hLine.ButtonDownFcn = @(~,~) selectMeasurement(midx);
        hLine.HitTest = 'on'; hLine.PickableParts = 'all';

        % Right-click menu on the line handle: color + symbol per-measurement
        hLine.ContextMenu = buildMeasLineMenu(hLine);

        appData.overlays.distLabels{end+1} = hTxt;
        setStatus(sprintf('Distance: %s', hTxt.String));
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: createEndpointMarker — Draggable marker for line endpoints
    % ════════════════════════════════════════════════════════════════════
    function hMark = createEndpointMarker(x, y, symType, symColor)
        if nargin < 3, symType  = 'circle'; end
        if nargin < 4, symColor = OVERLAY_COLOR; end
        mrk   = symTypeToMarker(symType);
        mrkSz = 6; if strcmp(symType, 'none'), mrkSz = 0.1; end
        tickHalf = 4;
        hMark = line(ax, [x - tickHalf, x, x + tickHalf], [y, y, y], ...
            'Marker',           mrk, ...
            'MarkerIndices',    2, ...
            'MarkerSize',       mrkSz, ...
            'MarkerEdgeColor',  symColor, ...
            'MarkerFaceColor',  'none', ...
            'LineStyle',        '-', ...
            'LineWidth',        1.0, ...
            'Color',            symColor, ...
            'HandleVisibility', 'off');
    end

    function mrk = symTypeToMarker(sym)
        switch sym
            case 'circle', mrk = 'o';
            case 'cross',  mrk = 'x';
            case 'square', mrk = 's';
            otherwise,     mrk = 'none';
        end
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
        %   FontSize=16 bold — visible at normal zoom on 4K displays
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
        uimenu(cm, 'Text', 'Font size', ...
            'MenuSelectedFcn', @(~,~) panelApplyLabelFont());
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

        emViewer.measurement.plotProfileFigure(dist, intensity, pu, 'Line Profile');
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
            appData.measWorkshop.sync(appData.overlays.measurements);

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
    %  CALLBACK: onRotateFlip — Rotate or flip the image
    % ════════════════════════════════════════════════════════════════════
    function onRotateFlip(mode)
        if isempty(appData.rawPixels), return; end
        undoPush();
        r = emViewer.processing.executeRotateFlip(appData.rawPixels, appData.filteredPixels, mode);
        if ~r.applied, return; end
        appData.rawPixels      = r.rawPixels;
        appData.filteredPixels = r.filteredPixels;

        [H, W] = size(appData.filteredPixels);
        lo = sldLow.Value;
        hi = sldHigh.Value;
        appData.displayPixels = [];
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
        setStatus(r.msg);
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
        if strcmp(action, 'start')
            if appData.activeIdx < 1 || isempty(appData.displayImg), return; end
            if appData.compareMode, return; end
            if ~isempty(appData.captureMode), cancelCapture(); end
            appData.captureMode = 'angle';
            appData.captureClicks = [];
            fig.Pointer = 'crosshair';
            fig.WindowButtonDownFcn = @(s,e) onAngleAction('click', s, e);
            setStatus('Click vertex point (1 of 3)... (Esc to cancel)');
            return;
        end

        % --- action == 'click' ---
        if ~strcmp(appData.captureMode, 'angle'), return; end
        cp = ax.CurrentPoint;
        x = cp(1,1);
        y = cp(1,2);
        if isempty(appData.displayImg), return; end
        [H, W] = size(appData.filteredPixels);
        if x < 0.5 || x > W + 0.5 || y < 0.5 || y > H + 0.5, return; end

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
            pts = appData.captureClicks;
            hL = line(ax, [pts(1,1) pts(2,1)], [pts(1,2) pts(2,2)], ...
                'Color', OVERLAY_COLOR, 'LineWidth', 1.5, 'HandleVisibility', 'off');
            appData.overlays.lines{end+1} = hL;
            setStatus('Click second ray endpoint (3 of 3)... (Esc to cancel)');
        elseif nClicks >= 3
            pts = appData.captureClicks;
            hL2 = line(ax, [pts(1,1) pts(3,1)], [pts(1,2) pts(3,2)], ...
                'Color', OVERLAY_COLOR, 'LineWidth', 1.5, 'HandleVisibility', 'off');
            appData.overlays.lines{end+1} = hL2;

            % Compute tilt-corrected angle (pure math delegated to package)
            v1 = pts(2,:) - pts(1,:);
            v2 = pts(3,:) - pts(1,:);
            [tiltDeg, tiltAxis, tiltActive, tiltGeom] = getTiltState();
            angleDeg = emViewer.measurements('computeAngle', v1, v2, tiltDeg, tiltAxis, tiltGeom);

            % Arc annotation geometry (raw image-space vectors for visual alignment)
            arc = emViewer.measurements('arcGeometry', pts, v1, v2);
            hArc = line(ax, arc.arcX, arc.arcY, ...
                'Color', OVERLAY_COLOR, 'LineWidth', 1, ...
                'LineStyle', '--', 'HandleVisibility', 'off');
            appData.overlays.lines{end+1} = hArc;

            % Label at midpoint of arc
            labelX = pts(1,1) + arc.arcRadius * 1.4 * cosd(arc.midAngle);
            labelY = pts(1,2) + arc.arcRadius * 1.4 * sind(arc.midAngle);
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
    %  CALLBACK: onPolylineAction — Multi-point distance measurement dispatcher
    %  action='start' : begin capture; action='click' : handle each click
    % ════════════════════════════════════════════════════════════════════
    function onPolylineAction(action, ~, ~)
        if strcmp(action, 'start')
            if appData.activeIdx < 1 || isempty(appData.displayImg), return; end
            if appData.compareMode, return; end
            if ~isempty(appData.captureMode), cancelCapture(); end
            appData.captureMode = 'polyline';
            appData.captureClicks = [];
            fig.Pointer = 'crosshair';
            fig.WindowButtonDownFcn = @(s,e) onPolylineAction('click', s, e);
            setStatus('Click points to measure path length; double-click to finish (Esc to cancel)');
            return;
        end

        % --- action == 'click' ---
        if ~strcmp(appData.captureMode, 'polyline'), return; end
        cp = ax.CurrentPoint;
        x = cp(1,1);
        y = cp(1,2);
        if isempty(appData.displayImg), return; end
        [H, W] = size(appData.filteredPixels);
        if x < 0.5 || x > W + 0.5 || y < 0.5 || y > H + 0.5, return; end

        % Check for double-click BEFORE adding the point (avoids duplicate)
        isDoubleClick = isprop(fig, 'SelectionType') && strcmp(fig.SelectionType, 'open');

        if isDoubleClick && size(appData.captureClicks, 1) >= 2
            % Double-click finishes — delegate length computation to package
            pts = appData.captureClicks;
            [tiltDeg, tiltAxis, tiltActive, tiltGeom] = getTiltState();
            totalDist = emViewer.measurements('polylineLength', pts, tiltDeg, tiltAxis, tiltGeom);

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
            midIdx = max(1, round(size(pts, 1) / 2));
            labelStr = sprintf('%.2f %s', totalDist, unitStr);
            if tiltActive, labelStr = [labelStr, '*']; end
            measClr = ddMeasColor.Value;
            if isempty(measClr), measClr = OVERLAY_COLOR; end
            hLabel = text(ax, pts(midIdx, 1), pts(midIdx, 2), labelStr, ...
                'Color', measClr, 'FontSize', 11, ...
                'FontWeight', 'bold', ...
                'HorizontalAlignment', 'center', ...
                'VerticalAlignment', 'bottom', ...
                'HandleVisibility', 'off');

            % Promote the polyline graphics to a proper measurement:
            % transfer the segment lines + vertex markers out of the
            % generic overlay cells into a dedicated measurement record
            % so the user can click → select → Delete just this polyline.
            nLines = nSegs;
            nMarkers = size(pts, 1);
            hLines = gobjects(0, 1);
            if nLines > 0 && numel(appData.overlays.lines) >= nLines
                hLines = [appData.overlays.lines{end-nLines+1:end}];
                appData.overlays.lines(end-nLines+1:end) = [];
            end
            hMarkers = gobjects(0, 1);
            if nMarkers > 0 && numel(appData.overlays.clickMarkers) >= nMarkers
                hMarkers = [appData.overlays.clickMarkers{end-nMarkers+1:end}];
                appData.overlays.clickMarkers(end-nMarkers+1:end) = [];
            end

            meas = struct();
            meas.type      = 'polyline';
            meas.hLines    = hLines;
            meas.hMarkers  = hMarkers;
            meas.hText     = hLabel;
            meas.hLine     = [];
            meas.hP1       = [];
            meas.hP2       = [];
            meas.vertices  = pts;
            meas.totalDist = totalDist;
            meas.unit      = unitStr;
            meas.lineColor = measClr;
            midx = numel(appData.overlays.measurements) + 1;
            appData.overlays.measurements{midx} = meas;
            appData.measWorkshop.sync(appData.overlays.measurements);

            % Attach click-to-select on every segment and vertex marker.
            for hh = hLines(:)'
                if isvalid(hh)
                    hh.HitTest = 'on';
                    hh.PickableParts = 'all';
                    hh.ButtonDownFcn = @(~,~) selectMeasurement(midx);
                end
            end
            for hh = hMarkers(:)'
                if isvalid(hh)
                    hh.HitTest = 'on';
                    hh.PickableParts = 'all';
                    hh.ButtonDownFcn = @(~,~) selectMeasurement(midx);
                end
            end
            if isvalid(hLabel)
                hLabel.HitTest = 'on';
                hLabel.PickableParts = 'all';
                hLabel.ButtonDownFcn = @(~,~) selectMeasurement(midx);
            end

            finishCapture();
            tiltTag = '';
            if tiltActive, tiltTag = sprintf(' [tilt %.1f°]', tiltDeg); end
            setStatus(sprintf('Polyline: %.2f %s (%d segments)%s — click to select, Delete to remove', ...
                totalDist, unitStr, nSegs, tiltTag));

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

        hM = line(ax, x, y, ...
            'Marker', 'o', 'MarkerSize', 6, ...
            'MarkerFaceColor', OVERLAY_COLOR, ...
            'MarkerEdgeColor', 'none', ...
            'LineStyle', 'none', ...
            'HandleVisibility', 'off');
        appData.overlays.clickMarkers{end+1} = hM;

        if nPts >= 2
            px = appData.captureClicks(nPts-1, 1);
            py = appData.captureClicks(nPts-1, 2);
            hL = line(ax, [px x], [py y], ...
                'Color', OVERLAY_COLOR, 'LineWidth', 1.5, 'HandleVisibility', 'off');
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
    %   flow in onAngleAction.
        if appData.activeIdx < 1 || isempty(appData.displayImg)
            angleDeg = NaN; return;
        end
        if ~isequal(size(pts), [3 2])
            error('FermiViewer:badInput', 'executeAngleFromPoints: pts must be 3x2');
        end

        v1 = pts(2,:) - pts(1,:);
        v2 = pts(3,:) - pts(1,:);
        % No tilt correction in headless path (caller supplies pre-corrected pts)
        angleDeg = emViewer.measurements('computeAngle', v1, v2, 0, 'Y', 'CrossSection');
        if isnan(angleDeg), return; end

        % Draw the two rays
        hL1 = line(ax, [pts(1,1) pts(2,1)], [pts(1,2) pts(2,2)], ...
            'Color', OVERLAY_COLOR, 'LineWidth', 1.5, 'HandleVisibility', 'off');
        appData.overlays.lines{end+1} = hL1;
        hL2 = line(ax, [pts(1,1) pts(3,1)], [pts(1,2) pts(3,2)], ...
            'Color', OVERLAY_COLOR, 'LineWidth', 1.5, 'HandleVisibility', 'off');
        appData.overlays.lines{end+1} = hL2;

        % Arc annotation
        arc = emViewer.measurements('arcGeometry', pts, v1, v2);
        hArc = line(ax, arc.arcX, arc.arcY, ...
            'Color', OVERLAY_COLOR, 'LineWidth', 1, 'LineStyle', '--', ...
            'HandleVisibility', 'off');
        appData.overlays.lines{end+1} = hArc;

        labelX = pts(1,1) + arc.arcRadius * 1.4 * cosd(arc.midAngle);
        labelY = pts(1,2) + arc.arcRadius * 1.4 * sind(arc.midAngle);
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

        measClr = OVERLAY_COLOR;

        % Draw vertex markers and segments into dedicated arrays so the
        % polyline becomes one selectable/deletable measurement.
        nPts = size(pts, 1);
        hMarkers = gobjects(nPts, 1);
        hLines   = gobjects(max(0, nPts-1), 1);
        for pi = 1:nPts
            hMarkers(pi) = line(ax, pts(pi,1), pts(pi,2), ...
                'Marker', 'o', 'MarkerSize', 6, ...
                'MarkerFaceColor', measClr, ...
                'MarkerEdgeColor', 'none', ...
                'LineStyle', 'none', 'HandleVisibility', 'off');
            if pi >= 2
                hLines(pi-1) = line(ax, [pts(pi-1,1) pts(pi,1)], ...
                              [pts(pi-1,2) pts(pi,2)], ...
                    'Color', measClr, 'LineWidth', 1.5, ...
                    'HandleVisibility', 'off');
            end
        end

        % Total length (no tilt correction in headless path)
        totalDist = emViewer.measurements('polylineLength', pts, 0, 'Y', 'CrossSection');

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
            'Color', measClr, 'FontSize', 11, 'FontWeight', 'bold', ...
            'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
            'HandleVisibility', 'off');

        nSegs = nPts - 1;

        % Register as a measurement record
        meas = struct();
        meas.type      = 'polyline';
        meas.hLines    = hLines;
        meas.hMarkers  = hMarkers;
        meas.hText     = hLabel;
        meas.hLine     = [];
        meas.hP1       = [];
        meas.hP2       = [];
        meas.vertices  = pts;
        meas.totalDist = totalDist;
        meas.unit      = unitStr;
        meas.lineColor = measClr;
        midx = numel(appData.overlays.measurements) + 1;
        appData.overlays.measurements{midx} = meas;
        appData.measWorkshop.sync(appData.overlays.measurements);

        for hh = [hLines(:); hMarkers(:); hLabel]'
            if isvalid(hh)
                hh.HitTest = 'on';
                hh.PickableParts = 'all';
                hh.ButtonDownFcn = @(~,~) selectMeasurement(midx);
            end
        end

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
        [realDist, realUnit, cancelled] = emViewer.calibration.promptScaleBarDistance(pxDist);

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
            det = emViewer.calibration.detectScaleBar(appData.filteredPixels);
            fig.Pointer = 'arrow';
            if ~det.found
                uialert(fig, det.msg, 'Auto-Detect Failed', 'Icon', 'warning');
                return;
            end

            barColor = [0 1 1];
            hBarLine = line(ax, [det.barX1 det.barX2], [det.barY det.barY], ...
                'Color', barColor, 'LineWidth', 3, 'HandleVisibility', 'off');
            hBarEnd1 = line(ax, [det.barX1 det.barX1], [det.barY-8 det.barY+8], ...
                'Color', barColor, 'LineWidth', 2, 'HandleVisibility', 'off');
            hBarEnd2 = line(ax, [det.barX2 det.barX2], [det.barY-8 det.barY+8], ...
                'Color', barColor, 'LineWidth', 2, 'HandleVisibility', 'off');
            hBarLabel = text(ax, (det.barX1 + det.barX2)/2, det.barY - 12, ...
                det.msg, 'Color', barColor, 'FontSize', 11, 'FontWeight', 'bold', ...
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
        updateMetadataPanel();

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
        cm = uicontextmenu(fig);
        mC = uimenu(cm, 'Text', 'Line color');
        uimenu(mC, 'Text', 'White',  'MenuSelectedFcn', @(~,~) applyMeasColor(hLine, [1 1 1]));
        uimenu(mC, 'Text', 'Cyan',   'MenuSelectedFcn', @(~,~) applyMeasColor(hLine, [0 1 1]));
        uimenu(mC, 'Text', 'Yellow', 'MenuSelectedFcn', @(~,~) applyMeasColor(hLine, [1 1 0]));
        uimenu(mC, 'Text', 'Red',    'MenuSelectedFcn', @(~,~) applyMeasColor(hLine, [1 0 0]));
        uimenu(mC, 'Text', 'Green',  'MenuSelectedFcn', @(~,~) applyMeasColor(hLine, [0 0.8 0]));
        uimenu(mC, 'Text', 'Blue',   'MenuSelectedFcn', @(~,~) applyMeasColor(hLine, [0 0.4 1]));
        uimenu(mC, 'Text', 'Apply to all', 'Separator', 'on', ...
            'MenuSelectedFcn', @(~,~) applyMeasColorAll(hLine));
        mS = uimenu(cm, 'Text', 'Symbol');
        uimenu(mS, 'Text', 'Circle', 'MenuSelectedFcn', @(~,~) applyMeasEndSymbol(hLine, 'circle'));
        uimenu(mS, 'Text', 'Cross',  'MenuSelectedFcn', @(~,~) applyMeasEndSymbol(hLine, 'cross'));
        uimenu(mS, 'Text', 'Square', 'MenuSelectedFcn', @(~,~) applyMeasEndSymbol(hLine, 'square'));
        uimenu(mS, 'Text', 'None',   'MenuSelectedFcn', @(~,~) applyMeasEndSymbol(hLine, 'none'));
        uimenu(mS, 'Text', 'Apply to all', 'Separator', 'on', ...
            'MenuSelectedFcn', @(~,~) applyMeasEndSymbolAll(hLine));
    end

    function applyMeasColor(hLine, clr)
        for mi = 1:numel(appData.overlays.measurements)
            m = appData.overlays.measurements{mi};
            if ~isvalid(m.hLine) || m.hLine ~= hLine, continue; end
            m.lineColor = clr;
            m.hLine.Color = clr;
            if isvalid(m.hP1), m.hP1.Color = clr; m.hP1.MarkerEdgeColor = clr; end
            if isvalid(m.hP2), m.hP2.Color = clr; m.hP2.MarkerEdgeColor = clr; end
            appData.overlays.measurements{mi} = m;
            appData.measWorkshop.sync(appData.overlays.measurements);
            return;
        end
    end

    function applyMeasColorAll(hLine)
        clr = OVERLAY_COLOR;
        for mi = 1:numel(appData.overlays.measurements)
            m = appData.overlays.measurements{mi};
            if isvalid(m.hLine) && m.hLine == hLine
                if isfield(m, 'lineColor'), clr = m.lineColor; end
                break;
            end
        end
        for mi = 1:numel(appData.overlays.measurements)
            m = appData.overlays.measurements{mi};
            if isvalid(m.hLine), applyMeasColor(m.hLine, clr); end
        end
    end

    function applyMeasEndSymbol(hLine, sym)
        mrk = symTypeToMarker(sym);
        mrkSz = 6; if strcmp(sym, 'none'), mrkSz = 0.1; end
        for mi = 1:numel(appData.overlays.measurements)
            m = appData.overlays.measurements{mi};
            if ~isvalid(m.hLine) || m.hLine ~= hLine, continue; end
            m.endSymbol = sym;
            for ph = {m.hP1, m.hP2}
                hp = ph{1};
                if isvalid(hp), hp.Marker = mrk; hp.MarkerSize = mrkSz; end
            end
            appData.overlays.measurements{mi} = m;
            appData.measWorkshop.sync(appData.overlays.measurements);
            return;
        end
    end

    function applyMeasEndSymbolAll(hLine)
        sym = 'circle';
        for mi = 1:numel(appData.overlays.measurements)
            m = appData.overlays.measurements{mi};
            if isvalid(m.hLine) && m.hLine == hLine
                if isfield(m, 'endSymbol'), sym = m.endSymbol; end
                break;
            end
        end
        for mi = 1:numel(appData.overlays.measurements)
            m = appData.overlays.measurements{mi};
            if isvalid(m.hLine), applyMeasEndSymbol(m.hLine, sym); end
        end
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
        if idx < 1 || idx > numel(appData.overlays.measurements), return; end
        meas = appData.overlays.measurements{idx};
        hlClr = [1 1 0];

        % rectangle primitive uses EdgeColor, not Color; branch on type so
        % we never call .Color on an HG rectangle (would error).
        if isfield(meas, 'type') && strcmp(meas.type, 'rectROI') ...
                && isfield(meas, 'hRect') && isvalid(meas.hRect)
            meas.hRect.LineWidth = 3;
            meas.hRect.EdgeColor = hlClr;
            return;
        end

        % polyline: iterate all segment lines and all vertex markers
        if isfield(meas, 'type') && strcmp(meas.type, 'polyline')
            if isfield(meas, 'hLines')
                for h = meas.hLines(:)'
                    if isvalid(h)
                        h.LineWidth = 3;
                        h.Color = hlClr;
                    end
                end
            end
            if isfield(meas, 'hMarkers')
                for h = meas.hMarkers(:)'
                    if isvalid(h)
                        h.Color = hlClr;
                        h.MarkerEdgeColor = hlClr;
                        h.MarkerFaceColor = hlClr;
                    end
                end
            end
            return;
        end

        % Legacy line-segment measurement (distance / profile / angle).
        if ~isfield(meas, 'hLine') || ~isvalid(meas.hLine), return; end
        meas.hLine.LineWidth = 3;
        meas.hLine.Color = hlClr;
        if isfield(meas, 'hP1') && ~isempty(meas.hP1) && isvalid(meas.hP1)
            meas.hP1.Color           = hlClr;
            meas.hP1.MarkerEdgeColor = hlClr;
        end
        if isfield(meas, 'hP2') && ~isempty(meas.hP2) && isvalid(meas.hP2)
            meas.hP2.Color           = hlClr;
            meas.hP2.MarkerEdgeColor = hlClr;
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: deselectMeasurement — Restore normal styling on ALL
    %  currently-selected measurements (single-select compatible: when
    %  selectedMeasIndices is empty, falls back to the legacy single idx).
    % ════════════════════════════════════════════════════════════════════
    function deselectMeasurement()
        % Build the list of indices whose styling must be restored.
        ids = appData.selectedMeasIndices;
        if isempty(ids) && appData.selectedMeasIdx > 0
            ids = appData.selectedMeasIdx;   % backcompat with single-select callers
        end
        for idx = ids(:)'
            if idx < 1 || idx > numel(appData.overlays.measurements), continue; end
            meas = appData.overlays.measurements{idx};
            restoreClr = OVERLAY_COLOR;
            if isfield(meas, 'lineColor'), restoreClr = meas.lineColor; end

            % rectROI uses EdgeColor — branch on type.
            if isfield(meas, 'type') && strcmp(meas.type, 'rectROI') ...
                    && isfield(meas, 'hRect') && isvalid(meas.hRect)
                meas.hRect.LineWidth = 1.5;
                meas.hRect.EdgeColor = restoreClr;
                continue;
            end

            % polyline: restore each segment + vertex marker
            if isfield(meas, 'type') && strcmp(meas.type, 'polyline')
                if isfield(meas, 'hLines')
                    for h = meas.hLines(:)'
                        if isvalid(h)
                            h.LineWidth = 1.5;
                            h.Color = restoreClr;
                        end
                    end
                end
                if isfield(meas, 'hMarkers')
                    for h = meas.hMarkers(:)'
                        if isvalid(h)
                            h.Color = restoreClr;
                            h.MarkerEdgeColor = restoreClr;
                            h.MarkerFaceColor = restoreClr;
                        end
                    end
                end
                continue;
            end

            % Legacy line-segment measurements.
            if isfield(meas, 'hLine') && isvalid(meas.hLine)
                meas.hLine.LineWidth = 1.5;
                meas.hLine.Color = restoreClr;
            end
            if isfield(meas, 'hP1') && ~isempty(meas.hP1) && isvalid(meas.hP1)
                meas.hP1.Color           = restoreClr;
                meas.hP1.MarkerEdgeColor = restoreClr;
                meas.hP1.MarkerFaceColor = 'none';
            end
            if isfield(meas, 'hP2') && ~isempty(meas.hP2) && isvalid(meas.hP2)
                meas.hP2.Color           = restoreClr;
                meas.hP2.MarkerEdgeColor = restoreClr;
                meas.hP2.MarkerFaceColor = 'none';
            end
        end
        appData.selectedMeasIdx     = 0;
        appData.selectedMeasIndices = [];
    end

    % ════════════════════════════════════════════════════════════════════
    %  HELPER: applyMarqueeSelection — Select items inside a drag box
    %  Called from onBoxZoomRelease when zoomMode is OFF. Selects any
    %  measurement whose endpoints both fall inside the rectangle, and any
    %  text annotation whose anchor (x, y) falls inside.
    % ════════════════════════════════════════════════════════════════════
    function applyMarqueeSelection(xMin, xMax, yMin, yMax)
        % Drop existing selection first
        deselectMeasurement();
        % Clear annotation highlights too
        for ai = appData.selectedAnnotIndices(:)'
            if ai >= 1 && ai <= numel(appData.overlays.textAnnotations)
                highlightAnnotation(appData.overlays.textAnnotations{ai}, false);
            end
        end
        appData.selectedAnnotIndices = [];
        if appData.selectedAnnotIdx > 0 && ...
                appData.selectedAnnotIdx <= numel(appData.overlays.textAnnotations)
            highlightAnnotation( ...
                appData.overlays.textAnnotations{appData.selectedAnnotIdx}, false);
        end
        appData.selectedAnnotIdx = 0;

        % Measurements: both endpoints inside the box. createEndpointMarker
        % renders each endpoint as a 3-point tick line [x-4, x, x+4] with
        % the marker at MarkerIndices=2, so the anchor lives at index 2 —
        % not at scalar XData/YData.
        measPick = [];
        for mi = 1:numel(appData.overlays.measurements)
            m = appData.overlays.measurements{mi};

            % rectROI: include when the rectangle's bounds lie inside the box
            if isfield(m, 'type') && strcmp(m.type, 'rectROI')
                if m.xMin >= xMin && m.xMax <= xMax && ...
                        m.yMin >= yMin && m.yMax <= yMax
                    measPick(end+1) = mi; %#ok<AGROW>
                end
                continue;
            end

            % polyline: include when every vertex lies inside the box
            if isfield(m, 'type') && strcmp(m.type, 'polyline') ...
                    && isfield(m, 'vertices') && ~isempty(m.vertices)
                vx = m.vertices(:, 1); vy = m.vertices(:, 2);
                if all(vx >= xMin) && all(vx <= xMax) && ...
                        all(vy >= yMin) && all(vy <= yMax)
                    measPick(end+1) = mi; %#ok<AGROW>
                end
                continue;
            end

            % Legacy distance/profile/angle measurement: both endpoints inside.
            if ~isfield(m, 'hP1') || ~isfield(m, 'hP2'), continue; end
            if isempty(m.hP1) || isempty(m.hP2), continue; end
            if ~isvalid(m.hP1) || ~isvalid(m.hP2), continue; end
            xd1 = m.hP1.XData; yd1 = m.hP1.YData;
            xd2 = m.hP2.XData; yd2 = m.hP2.YData;
            mIdx = 2;
            if numel(xd1) < mIdx, mIdx = 1; end
            x1 = xd1(mIdx); y1 = yd1(mIdx);
            x2 = xd2(min(mIdx, numel(xd2))); y2 = yd2(min(mIdx, numel(yd2)));
            in1 = x1 >= xMin && x1 <= xMax && y1 >= yMin && y1 <= yMax;
            in2 = x2 >= xMin && x2 <= xMax && y2 >= yMin && y2 <= yMax;
            if in1 && in2
                measPick(end+1) = mi; %#ok<AGROW>
            end
        end

        % Annotations: text anchor inside the box
        annPick = [];
        for ai = 1:numel(appData.overlays.textAnnotations)
            a = appData.overlays.textAnnotations{ai};
            if ~isfield(a, 'x') || ~isfield(a, 'y'), continue; end
            if a.x >= xMin && a.x <= xMax && a.y >= yMin && a.y <= yMax
                annPick(end+1) = ai; %#ok<AGROW>
            end
        end

        % Apply highlights
        for mi = measPick
            applyMeasHighlight(mi);
        end
        for ai = annPick
            highlightAnnotation(appData.overlays.textAnnotations{ai}, true);
        end

        % Update state. The "primary" index is the last one in each set so
        % existing single-select consumers (context menus, endpoint drag,
        % measTargetIndices) stay meaningful.
        appData.selectedMeasIndices = measPick;
        appData.selectedAnnotIndices = annPick;
        if ~isempty(measPick),  appData.selectedMeasIdx  = measPick(end);  end
        if ~isempty(annPick),   appData.selectedAnnotIdx = annPick(end);   end

        nTot = numel(measPick) + numel(annPick);
        if nTot == 0
            setStatus('Marquee: no items inside the box.');
        elseif nTot == 1
            setStatus('Marquee: 1 item selected (Delete to remove).');
        else
            setStatus(sprintf('Marquee: %d items selected (Delete to remove all).', nTot));
        end
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
        if idx < 1 || idx > numel(appData.overlays.measurements)
            return;
        end

        meas = appData.overlays.measurements{idx};

        % Delete graphics objects. Different types own different handle
        % sets, so dispatch on type. Each branch tolerates missing or
        % already-deleted handles via empty/isvalid checks.
        if isfield(meas, 'type') && strcmp(meas.type, 'rectROI')
            if isfield(meas, 'hRect') && isvalid(meas.hRect), delete(meas.hRect); end
        elseif isfield(meas, 'type') && strcmp(meas.type, 'polyline')
            if isfield(meas, 'hLines')
                for h = meas.hLines(:)'
                    if isvalid(h), delete(h); end
                end
            end
            if isfield(meas, 'hMarkers')
                for h = meas.hMarkers(:)'
                    if isvalid(h), delete(h); end
                end
            end
            if isfield(meas, 'hText') && ~isempty(meas.hText) && isvalid(meas.hText)
                delete(meas.hText);
            end
        else
            if isfield(meas, 'hLine') && isvalid(meas.hLine), delete(meas.hLine); end
            if isfield(meas, 'hP1')   && ~isempty(meas.hP1)   && isvalid(meas.hP1),   delete(meas.hP1);   end
            if isfield(meas, 'hP2')   && ~isempty(meas.hP2)   && isvalid(meas.hP2),   delete(meas.hP2);   end
            if isfield(meas, 'hText') && ~isempty(meas.hText) && isvalid(meas.hText)
                delete(meas.hText);
            end
        end

        % Remove from list
        appData.overlays.measurements(idx) = [];
        appData.measWorkshop.sync(appData.overlays.measurements);

        % Re-bind drag + selection callbacks with updated indices. Only
        % legacy line-segment measurements use startEndpointDrag; rectROI
        % and polyline have no drag handles yet.
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
                for h = m.hLines(:)'
                    if isvalid(h), h.ButtonDownFcn = @(~,~) selectMeasurement(mi); end
                end
            end
        end

        appData.selectedMeasIdx = 0;
        % Keep the multi-select array consistent under the index shift:
        % drop the deleted index and decrement any indices above it.
        if ~isempty(appData.selectedMeasIndices)
            keep = appData.selectedMeasIndices ~= idx;
            appData.selectedMeasIndices = appData.selectedMeasIndices(keep);
            shift = appData.selectedMeasIndices > idx;
            appData.selectedMeasIndices(shift) = ...
                appData.selectedMeasIndices(shift) - 1;
        end
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
        if isempty(appData.filteredPixels), return; end
        fig.Pointer = 'watch'; drawnow;
        fftHook = struct( ...
            'undoPush',    @undoPush, ...
            'applyResult', @(px) applyFFTResult(px), ...
            'setStatus',   @setStatus, ...
            'btnPrimary',  BTN_PRIMARY, ...
            'btnFg',       BTN_FG);
        emViewer.processing.openFFTMaskEditor(appData.filteredPixels, fftHook);
        fig.Pointer = 'arrow';
    end

    function applyFFTResult(pixels)
        appData.filteredPixels = pixels;
        refreshDisplay();
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
        imgA = getGrayscale(appData.images{round(idxA)});
        imgB = getGrayscale(appData.images{round(idxB)});
        r = emViewer.visualization.displayColorOverlay( ...
            imgA, imgB, cmapA, cmapB, alpha, names{round(idxA)}, names{round(idxB)});
        setStatus(r.statusMsg);
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
        appData.edsWorkshop.sync(appData);
    end

    function onExitEDS()
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
        appData.edsWorkshop.sync(appData);
    end

    function compositeEDS()
        if ~appData.edsMode || isempty(appData.edsChannels), return; end

        grays = cell(1, numel(appData.images));
        for ci = 1:numel(appData.edsChannels)
            ch = appData.edsChannels{ci};
            if ~ch.visible || ch.imageIdx < 1 || ch.imageIdx > numel(appData.images)
                continue;
            end
            if isempty(grays{ch.imageIdx})
                grays{ch.imageIdx} = getGrayscale(appData.images{ch.imageIdx});
            end
        end
        composite = emViewer.eds.computeComposite(grays, appData.edsChannels);
        appData.edsComposite = composite;
        appData.displayImg   = composite;

        if ~isempty(ax) && isvalid(ax)
            delete(ax.Children); cla(ax);
            hImg = image(ax, composite);
            appData.imgHandle = hImg;
            attachImageContextMenu();
            axis(ax, 'image');
            ax.XTick = []; ax.YTick = [];
            colormap(ax, feval(ddColormap.Value, 256));
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

    function onEDSListChange(action)
        switch action
            case 'add'
                if appData.activeIdx < 1 || appData.activeIdx > numel(appData.images)
                    return;
                end
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
                if appData.edsMode, compositeEDS(); end
            case 'remove'
                idx = lbEDSChannels.Value;
                if isempty(idx) || (isnumeric(idx) && idx == 0), return; end
                if idx >= 1 && idx <= numel(appData.edsChannels)
                    appData.edsChannels(idx) = [];
                end
                refreshEDSList();
                if appData.edsMode, compositeEDS(); end
        end
    end

    function onEDSChannelPropChanged(prop)
        idx = lbEDSChannels.Value;
        if isempty(idx) || idx < 1 || idx > numel(appData.edsChannels), return; end
        switch prop
            case 'color',     appData.edsChannels{idx}.color = ddChannelColor.Value;
            case 'visible',   appData.edsChannels{idx}.visible = cbChannelVisible.Value;
            case 'intensity'
                appData.edsChannels{idx}.intensity = sldChannelIntensity.Value;
                lblEDSIntensity.Text = sprintf('Int: %.2f', sldChannelIntensity.Value);
            case 'label',     appData.edsChannels{idx}.label = efChannelLabel.Value;
        end
        refreshEDSList();
        lbEDSChannels.Value = idx;
        if ~strcmp(prop, 'label') && appData.edsMode, compositeEDS(); end
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
        if isempty(appData.filteredPixels), return; end
        emViewer.processing.showSurfacePlot(appData.filteredPixels);
        setStatus('3D surface view opened — drag to rotate');
    end

    appData.liveFFTFig = [];  % persistent live FFT figure handle

    function onLiveFFTToggle(src, ~)
        if src.Value
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
        appData.procWorkshop.setLiveFFT(src.Value);
    end

    function updateLiveFFT()
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
        r = emViewer.display.selectColormapPreset();
        if ~r.selected, return; end
        ddColormap.Value = r.cmapName;
        if ~isempty(ax) && isvalid(ax)
            colormap(ax, feval(r.cmapName, 256));
        end
        setStatus(r.statusMsg);
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
        pLow  = imaging.percentile(frame(:), 2);
        pHigh = imaging.percentile(frame(:), 98);
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
    %REFRESHHISTOGRAMMARKERS  Draw contrast handles, transfer ramp, and
    %clipping indicators on the histogram. Delegates to
    %`emViewer.drawHistogramOverlay` for the actual drawing.
        if isempty(appData.filteredPixels), return; end
        if isempty(histAx) || ~isvalid(histAx), return; end

        delete(findobj(histAx, 'Tag', 'histMarker'));

        emViewer.drawHistogramOverlay( ...
            histAx, ...
            sldLow.Value, sldHigh.Value, ...
            appData.gamma, ...
            appData.contrastTransform, ...
            appData.contrastInvert, ...
            appData.rawPixels);
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
    %  PHASE 3: Contrast Pipeline Helper
    % ════════════════════════════════════════════════════════════════════
    function dispImg = applyContrastPipeline(pixels, lo, hi)
        dispImg = emViewer.contrast.applyPipeline(pixels, lo, hi, ...
            appData.contrastTransform, appData.gamma, appData.contrastInvert);
    end

    function onContrastTransformChanged(~, ~)
        appData.contrastTransform = ddContrastTransform.Value;
        appData.contrastWS.setTransform(appData.contrastTransform);
        onContrastChanged([], []);
    end

    function onInvertToggle(~, ~)
        appData.contrastInvert = cbInvert.Value;
        appData.contrastWS.setInvert(appData.contrastInvert);
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
        if isempty(appData.images), return; end
        answer = inputdlg({'Output format (png/tiff/jpeg):', 'Output directory (blank = same as source):'}, ...
            'Batch Convert', [1 50], {'png', ''});
        if isempty(answer), return; end
        fmt = lower(strtrim(answer{1}));
        outDir = strtrim(answer{2});
        if ~any(strcmp(fmt, {'png', 'tiff', 'jpeg', 'jpg'}))
            setStatus('Unsupported format. Use png, tiff, or jpeg.'); return;
        end
        if strcmp(fmt, 'jpg'), fmt = 'jpeg'; end
        fig.Pointer = 'watch'; drawnow;
        r = emViewer.processing.batchConvertImages(appData.images, fmt, outDir);
        fig.Pointer = 'arrow';
        setStatus(r.statusMsg);
    end

    % ════════════════════════════════════════════════════════════════════
    %  PHASE 3: Custom Colormap
    % ════════════════════════════════════════════════════════════════════
    function onCustomColormap(~, ~)
        answer = inputdlg({'Color stops (e.g. "0 0 0; 1 0 0; 1 1 1" for black→red→white):'}, ...
            'Custom Colormap', [3 60], {'0 0 0; 1 0 0; 1 1 1'});
        if isempty(answer), return; end
        try
            cmap = emViewer.processing.parseColormap(answer{1});
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
            uialert(fig, emViewer.display.formatRoughnessResult(result, pu), ...
                'Roughness Statistics', 'Icon', 'info');
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
            r = emViewer.processing.visualizeMultiOtsu(appData.filteredPixels, nClass);
            setStatus(r.statusMsg);
        catch ME
            setStatus(['Multi-Otsu error: ' ME.message]);
        end
    end

    % ── Feature 1: Lattice Measure from FFT ────────────────────────────
    % onLatticeMeasure and executeLattice → onDiffractionAction('latticeMeasure'/'latticeExecute')

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
            gpaOut = emViewer.diffraction.executeGPA( ...
                double(appData.filteredPixels), pts, max(guiPixelSize(), 1));
            setStatus(gpaOut.statusMsg);
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
            ctfOut = emViewer.diffraction.executeCTF( ...
                double(appData.filteredPixels), kV, Cs, pxA);
            setStatus(ctfOut.statusMsg);
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
        if isnan(gridSp), gridSp = 50; end
        try
            dcOut = emViewer.diffraction.executeDefectCount( ...
                double(appData.filteredPixels), gridSp, ...
                max(guiPixelSize(),1), guiPixelUnit());
            uialert(fig, dcOut.dialogMsg, 'Defect Count', 'Icon', 'info');
            setStatus(dcOut.statusMsg);
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
            rowIdx = str2double(answer{2});
            bpOut = emViewer.processing.executeBackProject( ...
                appData.images, answer{1}, rowIdx);
            setStatus(bpOut.statusMsg);
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
            emViewer.processing.buildFigurePanel(imgs, nRows, nCols, gap);
            setStatus('Figure panel built.');
        catch ME
            setStatus(['Figure builder error: ' ME.message]);
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
            btnFlickerCompare.Text = 'Flicker';
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
        uimenu(cm, 'Text', 'Copy to Clipboard', 'MenuSelectedFcn', @(~,~) onExportAction('copyClipboard'));
        uimenu(cm, 'Text', 'Save Image', 'MenuSelectedFcn', @(~,~) onExportAction('saveImage'));
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
            appData.eelsWorkshop.sync(appData);
        else
            onExitEELS();
        end
    end

    function onExitEELS()
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
        appData.eelsWorkshop.sync(appData);
    end

    function showEELSSpectrum()
        if isempty(appData.eelsData), return; end
        appData.eelsFig = emViewer.eels.showSpectrum( ...
            appData.eelsData.energyAxis, double(appData.eelsData.counts), ...
            appData.eelsFig);
    end

    function onEELSAction(action)
        switch action
            case 'bgFit'
                if isempty(appData.eelsData), return; end
                E = appData.eelsData.energyAxis;
                I = double(appData.eelsData.counts);
                E1 = str2double(edtEELSPreEdgeStart.Value);
                E2 = str2double(edtEELSPreEdgeEnd.Value);
                if isnan(E1) || isnan(E2) || E1 >= E2
                    setStatus('Invalid pre-edge window'); return;
                end
                method = ddEELSMethod.Value;
                try
                    r = emViewer.eels.executeBackgroundFit(E, I, [E1 E2], method);
                catch ME
                    setStatus(['EELS background error: ' ME.message]); return;
                end
                if ~isempty(appData.eelsFig) && isvalid(appData.eelsFig)
                    eelsAx = findobj(appData.eelsFig, 'Type', 'axes');
                    if ~isempty(eelsAx)
                        eelsAx = eelsAx(1);
                        cla(eelsAx); hold(eelsAx, 'on');
                        plot(eelsAx, E, I, 'k-', 'LineWidth', 0.5, 'DisplayName', 'Raw');
                        plot(eelsAx, E, r.bg, 'r--', 'LineWidth', 1, 'DisplayName', 'Background');
                        plot(eelsAx, E, max(r.signal, 0), 'b-', 'LineWidth', 1, 'DisplayName', 'Signal');
                        hold(eelsAx, 'off'); legend(eelsAx, 'show');
                        if ~isempty(r.titleStr), title(eelsAx, r.titleStr); end
                    end
                end
                setStatus(r.statusMsg);
                appData.eelsWorkshop.sync(appData);

            case 'showEdges'
                if isempty(appData.eelsFig) || ~isvalid(appData.eelsFig), return; end
                eelsAx = findobj(appData.eelsFig, 'Type', 'axes');
                if isempty(eelsAx), return; end
                eelsAx = eelsAx(1);
                if ~chkShowEdges.Value
                    delete(findobj(eelsAx, 'Tag', 'eels_edge'));
                    return;
                end
                emViewer.eels.overlayEdges(eelsAx, ddEdgeFilter.Value);

            case 'extractMap'
                if isempty(appData.eelsCube), setStatus('No spectrum image loaded'); return; end
                E1 = str2double(edtEELSSignalStart.Value);
                E2 = str2double(edtEELSSignalEnd.Value);
                if isnan(E1) || isnan(E2), setStatus('Invalid signal window'); return; end
                bgE1 = str2double(edtEELSPreEdgeStart.Value);
                bgE2 = str2double(edtEELSPreEdgeEnd.Value);
                bgWin = [];
                if ~isnan(bgE1) && ~isnan(bgE2) && bgE1 < bgE2, bgWin = [bgE1 bgE2]; end
                try
                    map = imaging.eelsExtractMap(appData.eelsCube, appData.eelsEnergyAxis, ...
                        [E1 E2], 'BackgroundWindow', bgWin);
                catch ME
                    setStatus(['EELS extract error: ' ME.message]); return;
                end
                cla(ax); imagesc(ax, map); colorbar(ax); colormap(ax, 'hot');
                title(ax, sprintf('EELS Map: %.0f-%.0f eV', E1, E2)); axis(ax, 'image');
                setStatus(sprintf('Extracted map: %.0f-%.0f eV', E1, E2));

            case 'thicknessMap'
                if isempty(appData.eelsCube), setStatus('No spectrum image loaded'); return; end
                try
                    [tMap, mask] = imaging.eelsThicknessMap(appData.eelsCube, appData.eelsEnergyAxis);
                catch ME
                    setStatus(['Thickness map error: ' ME.message]); return;
                end
                cla(ax); imagesc(ax, tMap); colorbar(ax); colormap(ax, 'parula');
                title(ax, 't/\lambda thickness map'); axis(ax, 'image');
                setStatus(sprintf('Thickness map: mean t/lambda=%.2f', mean(tMap(mask))));

            case 'alignZLP'
                if isempty(appData.eelsCube), setStatus('No spectrum image loaded'); return; end
                try
                    [appData.eelsCube, shifts] = imaging.eelsAlignZLP( ...
                        appData.eelsCube, appData.eelsEnergyAxis);
                catch ME
                    setStatus(['ZLP alignment error: ' ME.message]); return;
                end
                appData.eelsData.counts = squeeze(sum(sum(double(appData.eelsCube), 1), 2));
                showEELSSpectrum();
                setStatus(sprintf('ZLP aligned: max shift=%.0f channels', max(abs(shifts(:)))));
                appData.eelsWorkshop.sync(appData);
        end
    end

    function eelsBackgroundAPI(fitWin)
        edtEELSPreEdgeStart.Value = num2str(fitWin(1));
        edtEELSPreEdgeEnd.Value   = num2str(fitWin(2));
        onEELSAction('bgFit');
    end

    function eelsExtractMapAPI(sigWin, bgWin)
    %EELSEXTRACTMAPAPI  Programmatic EELS map extraction.
        edtEELSSignalStart.Value = num2str(sigWin(1));
        edtEELSSignalEnd.Value   = num2str(sigWin(2));
        if nargin >= 2 && ~isempty(bgWin)
            edtEELSPreEdgeStart.Value = num2str(bgWin(1));
            edtEELSPreEdgeEnd.Value   = num2str(bgWin(2));
        end
        onEELSAction('extractMap');
    end

    function onEELSAdvanced(action)
        switch action
            case 'deconvolve'
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
            appData.eelsWorkshop.sync(appData);
        catch ME
            setStatus(sprintf('Deconvolution failed: %s', ME.message));
        end

            case 'elnes'
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
            if ishandle(appData.eelsELNESFig), close(appData.eelsELNESFig); end
            elnesOut = emViewer.eels.executeELNES(E, I, onset, [E1 E2]);
            appData.eelsELNESFig = elnesOut.elnesFig;
            setStatus(elnesOut.statusMsg);
        catch ME
            setStatus(sprintf('ELNES failed: %s', ME.message));
        end

            case 'kramersKronig'
        if isempty(appData.eelsData), return; end
        if ishandle(appData.eelsKKFig), close(appData.eelsKKFig); end
        try
            kkOut = emViewer.eels.executeKramersKronig( ...
                appData.eelsData.energyAxis, double(appData.eelsData.counts));
            appData.eelsKKResult = kkOut.kkResult;
            appData.eelsKKFig = kkOut.kkFig;
            setStatus(kkOut.statusMsg);
            appData.eelsWorkshop.sync(appData);
        catch ME
            setStatus(sprintf('KK failed: %s', ME.message));
        end

            case 'svd'
        if isempty(appData.eelsCube)
            setStatus('No spectrum image loaded'); return;
        end
        if ishandle(appData.eelsSVDFig), close(appData.eelsSVDFig); end
        setStatus('Running SVD decomposition...');
        fig.Pointer = 'watch'; drawnow;
        try
            svdOut = emViewer.eels.executeSVD(appData.eelsCube, appData.eelsEnergyAxis, fig);
        catch ME
            fig.Pointer = 'arrow';
            setStatus(sprintf('SVD failed: %s', ME.message)); return;
        end
        fig.Pointer = 'arrow';
        appData.eelsSVDResult = svdOut.svdResult;
        appData.eelsSVDFig = svdOut.svdFig;
        if svdOut.denoised
            appData.eelsCube = svdOut.denoisedCube;
            appData.eelsData.counts = svdOut.sumSpectrum;
            showEELSSpectrum();
        end
        setStatus(svdOut.statusMsg);
        appData.eelsWorkshop.sync(appData);
        end  % switch action
    end  % onEELSAdvanced

    function onEELSNavigateToggle(src, ~)
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
    %EELSELNESAPI  Programmatic ELNES extraction at given onset energy.
        edtEELSEdgeOnset.Value = num2str(onset);
        onEELSAdvanced('elnes');
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
