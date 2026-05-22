function buildMenuBar(fig, cb)
%BUILDMENUBAR  Construct the FermiViewer top-level menu bar.
%
% Syntax
%   emViewer.buildMenuBar(fig, cb)
%
% Inputs
%   fig — uifigure that should host the menu bar
%   cb  — struct of nested-function handles from FermiViewer.m. Missing
%         fields are tolerated (the corresponding menu item is omitted)
%         so the same builder works against future stripped-down builds.
%
% Mirrors the existing right-click context menus on the image (cmImage)
% and image list (cmList). The menu bar is the discoverability layer —
% power users keep using right-click for the same actions.
%
% Modeled after +bosonPlotter/buildMenuBar.m — same addItem helper,
% same handling of nargin=0 nested fns, same Separator string coercion.

    % ── &File ──────────────────────────────────────────────────────────
    fileMenu = uimenu(fig, 'Text', '&File');
    addItem(fileMenu, 'Open Files...',           cb.onOpenFiles,           'Accelerator','O');
    addItem(fileMenu, 'Batch Convert...',        cb.onBatchConvert);
    addItem(fileMenu, 'Batch Rename...',         cb.onBatchRename);
    addItem(fileMenu, 'Save Session...',         cb.onSessionSave,         'Accelerator','S', 'Separator',true);
    addItem(fileMenu, 'Load Session...',         cb.onSessionLoad);
    addItem(fileMenu, 'Save Image...',           cb.onSaveImage,           'Separator',true);
    addItem(fileMenu, 'Copy to Clipboard',       cb.onCopyClipboard);
    addItem(fileMenu, 'Save with Overlays...',   cb.onExportWithOverlays);
    addItem(fileMenu, 'Batch Export...',         cb.onBatchExport);
    addItem(fileMenu, 'Journal Export...',       cb.onJournalExport);
    addItem(fileMenu, 'Create GIF...',           cb.onCreateGIF);
    addItem(fileMenu, 'Export Profile to DP...', cb.onExportProfileToDP);
    addItem(fileMenu, 'Export EDS Composite...', cb.onExportEDSComposite);
    addItem(fileMenu, 'Preferences...',          cb.onPreferences,         'Separator',true);
    addItem(fileMenu, 'Close',                   @(~,~) close(fig),        'Accelerator','W', 'Separator',true);

    % ── &Edit ──────────────────────────────────────────────────────────
    editMenu = uimenu(fig, 'Text', '&Edit');
    addItem(editMenu, 'Undo Filters',            cb.onUndoFilters,         'Accelerator','Z');
    addItem(editMenu, 'Reset Contrast',          cb.onResetContrast);
    addItem(editMenu, 'Reset Zoom',              cb.onResetZoom);
    addItem(editMenu, 'Clear Overlays',          cb.onClearOverlays,       'Separator',true);
    addItem(editMenu, 'Rename Selected...',      cb.onRenameSelected,      'Separator',true);
    addItem(editMenu, 'Remove Selected',         cb.onRemoveSelected);
    addItem(editMenu, 'Edit Metadata...',        cb.onEditMetadata,        'Separator',true);
    addItem(editMenu, 'Set Pixel Size...',       cb.onSetPixelSize);

    % ── &View ──────────────────────────────────────────────────────────
    viewMenu = uimenu(fig, 'Text', '&View');
    addItem(viewMenu, 'Auto Contrast',           cb.onAutoContrast);
    addItem(viewMenu, 'Reset Contrast',          cb.onResetContrast);
    addItem(viewMenu, 'Show FFT',                cb.onShowFFT,             'Separator',true);
    addItem(viewMenu, 'Live FFT (toggle)',       cb.onLiveFFTToggle);
    addItem(viewMenu, 'Toggle Colorbar',         cb.onColorbarToggle,      'Separator',true);
    addItem(viewMenu, 'Toggle Histogram Log',    cb.onToggleHistLog);
    addItem(viewMenu, 'Toggle Pixel Inspector',  cb.onPixelInspectorToggle);
    addItem(viewMenu, 'Toggle Minimap',          cb.onMinimapToggle);
    addItem(viewMenu, 'Toggle Theme (Dark/Light)', cb.onThemeToggle,       'Separator',true);
    addItem(viewMenu, 'Compare Toggle',          cb.onCompareToggle,       'Separator',true);
    addItem(viewMenu, 'Flicker Compare',         cb.onFlickerCompare);
    addItem(viewMenu, 'Thumbnail Grid',          cb.onThumbnailGrid);
    addItem(viewMenu, 'Stack MIP',               cb.onStackMIP);

    % ── &Image ─────────────────────────────────────────────────────────
    imageMenu = uimenu(fig, 'Text', '&Image');
    addItem(imageMenu, 'Crop...',                cb.onCropImage);
    addItem(imageMenu, 'Zoom (Box)',             cb.onZoomBox);
    addItem(imageMenu, 'Zoom Actual (1:1)',      cb.onZoomActual);
    addItem(imageMenu, 'Zoom Fit',               cb.onZoomFit);
    addItem(imageMenu, 'Rotate / Flip...',       cb.onRotateFlip,          'Separator',true);
    addItem(imageMenu, 'Invert',                 cb.onInvertImage);
    addItem(imageMenu, 'Bin Image...',           cb.onBinImage,            'Separator',true);
    addItem(imageMenu, 'Image Math...',          cb.onImageMath);
    addItem(imageMenu, 'Stitch Images...',       cb.onStitchImages);
    addItem(imageMenu, 'Montage...',             cb.onMontage);
    addItem(imageMenu, 'Custom Colormap...',     cb.onCustomColormap,      'Separator',true);

    % ── &Filter ────────────────────────────────────────────────────────
    filterMenu = uimenu(fig, 'Text', 'F&ilter');
    addItem(filterMenu, 'Gaussian...',           cb.onGaussianFilter);
    addItem(filterMenu, 'Median...',             cb.onMedianFilter);
    addItem(filterMenu, 'CLAHE...',              cb.onCLAHE);
    addItem(filterMenu, 'Sharpen...',            cb.onSharpen);
    addItem(filterMenu, 'Butterworth...',        cb.onButterworth);
    addItem(filterMenu, 'Plane Level',           cb.onPlaneLevel,          'Separator',true);
    addItem(filterMenu, 'Morphology...',         cb.onMorphOp);
    addItem(filterMenu, 'Multi-Otsu',            cb.onMultiOtsu,           'Separator',true);
    addItem(filterMenu, 'Watershed',             cb.onWatershed);

    % ── &Analysis ──────────────────────────────────────────────────────
    analysisMenu = uimenu(fig, 'Text', '&Analysis');
    addItem(analysisMenu, 'Line Profile',        cb.onLineProfile);
    addItem(analysisMenu, 'Box Profile',         cb.onBoxProfile);
    addItem(analysisMenu, 'Radial Profile',      cb.onRadialProfile);
    addItem(analysisMenu, 'Distance',            cb.onDistance,            'Separator',true);
    addItem(analysisMenu, 'Angle (3-point)',     cb.onAngleAction);
    addItem(analysisMenu, 'Polyline Path',       cb.onPolylineAction);
    addItem(analysisMenu, 'Az. Integrate',       cb.onAzIntegrate,         'Separator',true);
    addItem(analysisMenu, 'Particle Count...',   cb.onParticleCount);
    addItem(analysisMenu, 'Defect Count...',     cb.onDefectCount);
    addItem(analysisMenu, 'Roughness',           cb.onRoughness);
    addItem(analysisMenu, 'Interface Fit...',    cb.onInterfaceFit,        'Separator',true);
    addItem(analysisMenu, 'CTF Estimate',        cb.onCTFEstimate);
    addItem(analysisMenu, 'GPA (Strain)',        cb.onGPA);
    addItem(analysisMenu, 'Composition Profile', cb.onCompositionProfile);
    addItem(analysisMenu, 'Template Match...',   cb.onTemplateMatch,       'Separator',true);
    addItem(analysisMenu, 'Noise Estimate',      cb.onNoiseEstimate);
    addItem(analysisMenu, 'Batch Measurement...', cb.onBatchMeasurement,   'Separator',true);
    addItem(analysisMenu, 'Measurement Stats',   cb.onMeasurementStats);
    addItem(analysisMenu, 'ROI Manager...',      cb.onROIManager);

    % ── S&pectroscopy ──────────────────────────────────────────────────
    specMenu = uimenu(fig, 'Text', 'S&pectroscopy');
    addItem(specMenu, 'Enter EDS Mode',          cb.onEnterEDS);
    addItem(specMenu, 'Exit EDS Mode',           cb.onExitEDS);
    addItem(specMenu, 'Quantify EDS (CL)',       cb.onQuantifyCL,          'Separator',true);
    addItem(specMenu, 'Quantify EDS (ZAF)',      cb.onQuantifyZAF);
    addItem(specMenu, 'EELS Action...',          cb.onEELSAction,          'Separator',true);
    addItem(specMenu, 'EELS Advanced...',        cb.onEELSAdvanced);
    addItem(specMenu, 'EELS Navigate (toggle)',  cb.onEELSNavigateToggle);
    addItem(specMenu, 'Diffraction Action...',   cb.onDiffractionAction,   'Separator',true);
    addItem(specMenu, 'Back Project',            cb.onBackProject);
    addItem(specMenu, 'Virtual Dark Field',      cb.onVirtualDarkField);

    % ── &Tools ─────────────────────────────────────────────────────────
    toolsMenu = uimenu(fig, 'Text', '&Tools');
    addItem(toolsMenu, 'Calibrate Scale Bar...', cb.onCalibrateBar);
    addItem(toolsMenu, 'Toggle Scale Bar',       cb.onScaleBarToggle);
    addItem(toolsMenu, 'Place Arrow',            cb.onPlaceArrow,          'Separator',true);
    addItem(toolsMenu, 'Place Circle',           cb.onPlaceCircle);
    addItem(toolsMenu, 'Place Line',             cb.onPlaceLine);
    addItem(toolsMenu, 'Place Rectangle',        cb.onPlaceRect);
    addItem(toolsMenu, 'Surface Plot...',        cb.onSurfacePlot,         'Separator',true);
    addItem(toolsMenu, 'Figure Builder...',      cb.onFigureBuilder);
    addItem(toolsMenu, 'Publication Presets...', cb.onPubPresets);
    addItem(toolsMenu, 'Stack Navigation...',    cb.onStackNav,            'Separator',true);
    addItem(toolsMenu, 'Align Stack...',         cb.onAlignStack);
    addItem(toolsMenu, 'Macro Record (toggle)',  cb.onMacroToggle,         'Separator',true);

    % ── &Help ──────────────────────────────────────────────────────────
    helpMenu = uimenu(fig, 'Text', '&Help');
    addItem(helpMenu, 'Keyboard Shortcuts',      cb.onShowEMShortcuts);
    addItem(helpMenu, 'Report a Bug...',         cb.onReportBug);
end

% ────────────────────────────────────────────────────────────────────────
function addItem(parent, label, callback, varargin)
%ADDITEM  Add a uimenu entry under `parent`. Mirrors the helper in
%   +bosonPlotter/buildMenuBar.m verbatim — kept local so this builder
%   has no cross-package dependency.
    if isempty(callback) || ~isa(callback, 'function_handle')
        return;
    end
    try
        if nargin(callback) == 0
            wrapped = @(~,~) callback();
        else
            wrapped = callback;
        end
    catch
        wrapped = callback;  % anonymous handles — nargin can throw
    end
    args = {parent, 'Text', label, 'MenuSelectedFcn', wrapped};
    if ~isempty(varargin)
        for k = 1:2:numel(varargin)
            if strcmpi(varargin{k}, 'Separator') && islogical(varargin{k+1})
                varargin{k+1} = ternary(varargin{k+1}, 'on', 'off');
            end
        end
        args = [args, varargin];
    end
    uimenu(args{:});
end

function out = ternary(cond, ifTrue, ifFalse)
    if cond, out = ifTrue; else, out = ifFalse; end
end
