function palette = buildCommandPalette(parentFig, tk, cb)
%BUILDCOMMANDPALETTE  ⌘K / Ctrl-K command palette for FermiViewer.
%
%   palette = fermiViewer.buildCommandPalette(parentFig, tk, cb)
%
%   A modal search-and-run palette over every menu action. Discoverability
%   for new users + keyboard speed for power users, in one widget. The action
%   registry is derived from the SAME callback struct (cb / menuCb_) the menu
%   bar uses, so there's a single source of truth for what actions exist.
%
%   Inputs:
%       parentFig — the main FermiViewer uifigure (palette centers on it).
%       tk        — fermiViewer.chrome.uxTokens(theme) token struct.
%       cb        — the menuCb_ struct of callback handles from FermiViewer.m.
%
%   Output: palette — struct:
%       .fig       — the modal child uifigure (Visible='off' until shown)
%       .show()    — populate + reveal, focus the search field
%       .hide()    — hide
%       .setQuery(q) — set the search text and refilter (headless/testing)
%       .items()   — current filtered label list (cellstr)
%       .dispatch(label) — run the action for `label` (headless/testing)
%
%   No external toolboxes.
%
%   See also fermiViewer.buildMenuBar

    arguments
        parentFig (1,1) matlab.ui.Figure
        tk        (1,1) struct
        cb        (1,1) struct
    end

    % ── Action registry: {label, cb-field}. Only entries whose field exists
    %    as a callable handle in `cb` are offered. ──────────────────────────
    reg = registrySpec();
    labels  = {};
    handles = {};
    for i = 1:size(reg, 1)
        f = reg{i, 2};
        if isfield(cb, f) && isa(cb.(f), 'function_handle')
            labels{end+1}  = reg{i, 1};   %#ok<AGROW>
            handles{end+1} = cb.(f);      %#ok<AGROW>
        end
    end

    % ── Modal window centred on the parent ──────────────────────────────
    palette.fig = uifigure('Name', 'Command Palette', ...
        'WindowStyle', 'modal', 'Resize', 'off', 'Visible', 'off', ...
        'Color', tk.color.bgPanel, ...
        'Position', centerOn(parentFig, 560, 420));
    palette.fig.WindowKeyPressFcn = @(~, e) onKey(e);

    gl = uigridlayout(palette.fig, [3 1], ...
        'RowHeight', {44, '1x', 26}, 'Padding', [0 0 0 0], 'RowSpacing', 0, ...
        'BackgroundColor', tk.color.bgPanel);

    search = uieditfield(gl, 'Placeholder', 'Search every action…', ...
        'BackgroundColor', tk.color.bgInput, 'FontColor', tk.color.text, ...
        'FontSize', 15);
    search.Layout.Row = 1;
    search.ValueChangedFcn  = @(s, ~) refilter(s.Value);
    if ~isMATLABReleaseOlderThan('R2023a')
        % ValueChangingFcn gives live filtering as the user types.
        search.ValueChangingFcn = @(~, e) refilter(e.Value);
    end

    list = uilistbox(gl, 'Items', labels, ...
        'BackgroundColor', tk.color.bgInput, 'FontColor', tk.color.text, ...
        'FontSize', 13);
    list.Layout.Row = 2;
    list.ValueChangedFcn = @(s, ~) dispatchLabel(s.Value);

    hint = uilabel(gl, 'Text', '  Enter/Click to run  ·  Esc to close', ...
        'FontColor', tk.color.textDim, 'FontSize', 11);
    hint.Layout.Row = 3;

    % ── Public handles ───────────────────────────────────────────────────
    palette.show     = @showPalette;
    palette.hide     = @() set(palette.fig, 'Visible', 'off');
    palette.setQuery = @(q) refilter(q);
    palette.items    = @() string(list.Items);
    palette.dispatch = @dispatchLabel;

    % ════════════════════════════════════════════════════════════════════
    %  Nested helpers
    % ════════════════════════════════════════════════════════════════════
    function refilter(q)
        q = char(q);
        if isempty(q)
            list.Items = labels;
            return;
        end
        keep = contains(lower(labels), lower(q));
        list.Items = labels(keep);
    end

    function dispatchLabel(label)
        idx = find(strcmp(labels, label), 1);
        set(palette.fig, 'Visible', 'off');
        if ~isempty(idx)
            h = handles{idx};
            try
                h([], []);     % menu callbacks take (src,evt)
            catch
                try
                    h();
                catch
                end
            end
        end
    end

    function showPalette()
        search.Value = '';
        list.Items = labels;
        palette.fig.Position = centerOn(parentFig, 560, 420);
        palette.fig.Visible = 'on';
        try
            focus(search);
        catch
        end
    end

    function onKey(e)
        if strcmp(e.Key, 'escape')
            set(palette.fig, 'Visible', 'off');
        end
    end
end

% ════════════════════════════════════════════════════════════════════════
%  Local (no-closure) helpers
% ════════════════════════════════════════════════════════════════════════
function pos = centerOn(parentFig, w, h)
    try
        p = parentFig.Position;
        cx = p(1) + p(3)/2;  cy = p(2) + p(4)/2;
        pos = [round(cx - w/2), round(cy - h/2), w, h];
    catch
        pos = [200 200 w h];
    end
end

function reg = registrySpec()
%REGISTRYSPEC  {display label, menuCb field}. Curated, grouped by area.
    reg = {
        % File
        'Open Files…',            'onOpenFiles'
        'Save Session…',          'onSessionSave'
        'Load Session…',          'onSessionLoad'
        'Save Image…',            'onSaveImage'
        'Copy to Clipboard',      'onCopyClipboard'
        'Save with Overlays…',    'onExportWithOverlays'
        'Batch Export…',          'onBatchExport'
        'Preferences…',           'onPreferences'
        % View
        'Auto Contrast',          'onAutoContrast'
        'Reset Contrast',         'onResetContrast'
        'Reset Zoom',             'onResetZoom'
        'Show FFT',               'onShowFFT'
        'Toggle Colorbar',        'onColorbarToggle'
        'Toggle Theme (Dark/Light)', 'onThemeToggle'
        'Toggle Pixel Inspector', 'onPixelInspectorToggle'
        'Toggle Minimap',         'onMinimapToggle'
        'Compare Toggle',         'onCompareToggle'
        'Flicker Compare',        'onFlickerCompare'
        'Thumbnail Grid',         'onThumbnailGrid'
        % Image
        'Crop…',                  'onCropImage'
        'Rotate / Flip…',         'onRotateFlip'
        'Invert',                 'onInvertImage'
        'Bin Image…',             'onBinImage'
        'Image Math…',            'onImageMath'
        'Stitch Images…',         'onStitchImages'
        'Montage…',               'onMontage'
        'Custom Colormap…',       'onCustomColormap'
        % Filters
        'Gaussian Filter…',       'onGaussianFilter'
        'Median Filter…',         'onMedianFilter'
        'CLAHE…',                 'onCLAHE'
        'Sharpen…',               'onSharpen'
        'Butterworth…',           'onButterworth'
        'Plane Level',            'onPlaneLevel'
        'Morphology…',            'onMorphOp'
        'Multi-Otsu',             'onMultiOtsu'
        'Watershed',              'onWatershed'
        % Scale bar / annotations
        'Calibrate Scale Bar…',   'onCalibrateBar'
        'Toggle Scale Bar',       'onScaleBarToggle'
        'Place Arrow',            'onPlaceArrow'
        'Place Circle',           'onPlaceCircle'
        'Place Line',             'onPlaceLine'
        'Place Rectangle',        'onPlaceRect'
        % Publication
        'Surface Plot…',          'onSurfacePlot'
        'Figure Builder…',        'onFigureBuilder'
        'Publication Presets…',   'onPubPresets'
        % Analysis
        'Line Profile',           'onLineProfile'
        'Box Profile',            'onBoxProfile'
        'Radial Profile',         'onRadialProfile'
        'Distance',               'onDistance'
        'Angle (3-point)',        'onAngleAction'
        'Polyline Path',          'onPolylineAction'
        'Azimuthal Integrate',    'onAzIntegrate'
        'Particle Count…',        'onParticleCount'
        'Grain ID…',              'onGrainID'
        'Defect Count…',          'onDefectCount'
        'Roughness',              'onRoughness'
        'Interface Fit…',         'onInterfaceFit'
        'CTF Estimate',           'onCTFEstimate'
        'GPA (Strain)',           'onGPA'
        'Composition Profile',    'onCompositionProfile'
        'Template Match…',        'onTemplateMatch'
        'Noise Estimate',         'onNoiseEstimate'
        'Batch Measurement…',     'onBatchMeasurement'
        'Measurement Stats',      'onMeasurementStats'
        'ROI Manager…',           'onROIManager'
        % Spectroscopy / workshops
        'Enter EDS Mode',         'onEnterEDS'
        'Exit EDS Mode',          'onExitEDS'
        'Quantify EDS (CL)',      'onQuantifyCL'
        'Quantify EDS (ZAF)',     'onQuantifyZAF'
        'EELS Action…',           'onEELSAction'
        'EELS Advanced…',         'onEELSAdvanced'
        'Diffraction Action…',    'onDiffractionAction'
        'Virtual Dark Field',     'onVirtualDarkField'
        % Stack / macro
        'Stack Navigation…',      'onStackNav'
        'Align Stack…',           'onAlignStack'
        'Macro Record (toggle)',  'onMacroToggle'
        % Help
        'Keyboard Shortcuts',     'onShowEMShortcuts'
        'Report a Bug…',          'onReportBug'
    };
end
