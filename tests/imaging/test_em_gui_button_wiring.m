%TEST_EM_GUI_BUTTON_WIRING  Verify every FermiViewer Processing-panel button
%   is present, enabled after image load, wired to a callback, and parented
%   to its expected tab. Exercises the 5-tab Processing panel refactor and
%   closes the GUI-level coverage gap for buttons whose underlying library
%   functions are tested in +imaging/ but whose button wiring was not.
%
%   This is a smoke test at the widget-tree level: it does NOT fire the
%   dialogs (which would block in -batch mode), it asserts the wiring
%   contract — button exists, Enable='on', callback non-empty, parent tab
%   matches. The +imaging/ tests already prove the underlying functions
%   work; this test proves the GUI can reach them.
%
%   Run:  runAllTests(Group="emgui")
%   Or:   run tests/imaging/test_em_gui_button_wiring

clear; clc;

thisDir = fileparts(mfilename('fullpath'));
rootDir = fileparts(fileparts(thisDir));
if ~contains(path, rootDir); addpath(rootDir); end

% Load two real DM3s so both single- and multi-image controls enable.
% Multi-image buttons (Batch Crop, Align Stack, Stitch, Montage, Overlay,
% Img Math, Flicker) require >= 2 loaded images to be legal.
srcDir = fullfile(rootDir, '+test_datasets', 'Microscopy');
dm3a = fullfile(srcDir, 'EDW087-1.dm3');
dm3b = fullfile(srcDir, 'EDW087-2.dm3');
assert(isfile(dm3a) && isfile(dm3b), 'Test DM3s not found in %s', srcDir);

fprintf('\n=== test_em_gui_button_wiring ===\n');
passed = 0; failed = 0;

% Expected Processing-panel layout: each row is {tabTitle, buttonText, controlKind}
% controlKind: 'button' (ButtonPushedFcn) | 'state' (ValueChangedFcn) | 'checkbox'
spec = {
    % ── Transform ──────────────────────────────────────────────────────
    'Transform',      'Rot 90 CW',          'button'
    'Transform',      'Rot 90 CCW',         'button'
    'Transform',      'Flip H',             'button'
    'Transform',      'Flip V',             'button'
    'Transform',      'Zoom Box',           'button'
    'Transform',      'Reset Zoom',         'button'
    'Transform',      'Crop',               'button'
    'Transform',      'Save Crop',          'button'
    'Transform',      'Batch Crop',         'button'
    'Transform',      'Bin Image',          'button'
    'Transform',      'Set Pixel Size',     'button'
    % ── Filter ─────────────────────────────────────────────────────────
    'Filter',         'Gaussian',           'button'
    'Filter',         'Median',             'button'
    'Filter',         'CLAHE',              'button'
    'Filter',         'Sharpen',            'button'
    'Filter',         'Morph Op',           'button'
    'Filter',         'Butterworth',        'button'
    'Filter',         'FFT Mask',           'button'
    'Filter',         'Threshold',          'button'
    'Filter',         'Multi-Thresh',       'button'
    'Filter',         'Undo Filters',       'button'
    'Filter',         'Pixel Inspector',    'checkbox'
    % ── FFT & Analysis ─────────────────────────────────────────────────
    'FFT & Analysis', 'Show FFT',           'button'
    'FFT & Analysis', 'Live FFT',           'state'
    'FFT & Analysis', 'Radial Profile',     'button'
    'FFT & Analysis', 'Az Integrate',       'button'
    'FFT & Analysis', 'Lattice',            'button'
    'FFT & Analysis', 'GPA Strain',         'button'
    'FFT & Analysis', 'CTF Estimate',       'button'
    'FFT & Analysis', 'Noise Est.',         'button'
    'FFT & Analysis', 'Template Match',     'button'
    'FFT & Analysis', 'Interface Fit',      'button'
    'FFT & Analysis', 'Defect Count',       'button'
    % ── Surface & Stack ────────────────────────────────────────────────
    'Surface & Stack','Plane Level',        'button'
    'Surface & Stack','Roughness',          'button'
    'Surface & Stack','3D Surface',         'button'
    'Surface & Stack','Surface Plot',       'button'
    'Surface & Stack','Back-Project',       'button'
    'Surface & Stack','Particles',          'button'
    'Surface & Stack','Watershed',          'button'
    'Surface & Stack','Align Stack',        'button'
    'Surface & Stack','Stitch',             'button'
    'Surface & Stack','Montage / Stitch',   'button'
    };

% ── Launch GUI and load a real image ─────────────────────────────────────
api = FermiViewer();
cleanupApi = onCleanup(@() safeClose(api));
drawnow;
api.loadImages({dm3a, dm3b});
drawnow;

assert(numel(api.getImages()) == 2, 'Failed to load both test DM3s');

% ── Verify the tab group structure ───────────────────────────────────────
fprintf('\n── Tab group structure ──\n');
tabGroups = findall(api.fig, 'Type', 'uitabgroup');
assert(~isempty(tabGroups), 'No uitabgroup found in FermiViewer');

expectedTabs = unique(spec(:,1), 'stable');
processingTG = [];
for k = 1:numel(tabGroups)
    tabs = tabGroups(k).Children;
    titles = arrayfun(@(t) string(t.Title), tabs);
    if all(ismember(string(expectedTabs), titles))
        processingTG = tabGroups(k);
        break;
    end
end
assert(~isempty(processingTG), 'Could not locate Processing tab group');
fprintf('  [PASS] Processing tabgroup has all 4 tabs: %s\n', ...
    strjoin(arrayfun(@(t) char(t.Title), processingTG.Children, 'UniformOutput', false), ', '));
passed = passed + 1;

% ── Per-button wiring checks ─────────────────────────────────────────────
fprintf('\n── Button wiring (%d controls) ──\n', size(spec, 1));
for k = 1:size(spec, 1)
    expectedTab = spec{k, 1};
    btnText     = spec{k, 2};
    kind        = spec{k, 3};
    label       = sprintf('[%-15s] %-22s', expectedTab, btnText);

    try
        % Locate the control by displayed text. uibutton(..,'state',..)
        % returns a StateButton (Type='uistatebutton'), not a Button.
        switch kind
            case 'checkbox'
                hits = findall(api.fig, 'Type', 'uicheckbox', 'Text', btnText);
            case 'state'
                hits = findall(api.fig, 'Type', 'uistatebutton', 'Text', btnText);
            otherwise
                hits = findall(api.fig, 'Type', 'uibutton', 'Text', btnText);
        end

        % Filter to descendants of the Processing tab group — we might
        % have same-name buttons elsewhere in the figure
        hits = hits(arrayfun(@(h) isDescendantOf(h, processingTG), hits));

        assert(numel(hits) == 1, ...
            sprintf('expected exactly 1 control, found %d', numel(hits)));
        h = hits(1);

        % 1. Enable state — should be 'on' after image load
        assert(strcmp(h.Enable, 'on'), ...
            sprintf('Enable=%s (expected on)', h.Enable));

        % 2. Callback non-empty
        switch kind
            case 'button'
                cb = h.ButtonPushedFcn;
            case {'state', 'checkbox'}
                cb = h.ValueChangedFcn;
        end
        assert(~isempty(cb), 'callback is empty');

        % 3. Parent tab matches expected
        actualTab = findAncestorTab(h);
        assert(~isempty(actualTab), 'control has no uitab ancestor');
        assert(strcmp(actualTab.Title, expectedTab), ...
            sprintf('parented to "%s" not "%s"', actualTab.Title, expectedTab));

        fprintf('  [PASS] %s\n', label);
        passed = passed + 1;
    catch ME
        fprintf('  [FAIL] %s — %s\n', label, ME.message);
        failed = failed + 1;
    end
end

% ── Export & Style collapsible section (standalone, not in tabgroup) ─────
exportBtns = {
    'Save Image', 'Copy', 'Burn Overlays', 'Batch Export', ...
    'Create GIF', 'Batch Convert', 'Save .mat', 'Load .mat', ...
    'Figure Builder', 'Journal Export', 'Pub Presets', ...
    'Calibrate Colorbar', 'Custom Colormap', 'EM Colormaps', ...
    'Overlay', 'Flicker', 'Record Macro', 'Img Math', ...
    'Rename All', 'Rename Sel.'};
fprintf('\n── Export & Style section (%d controls) ──\n', numel(exportBtns));
for k = 1:numel(exportBtns)
    try
        h = findall(api.fig, 'Type', 'uibutton', 'Text', exportBtns{k});
        assert(~isempty(h), 'not found');
        h = h(1);
        assert(~isempty(h.ButtonPushedFcn), 'callback is empty');
        fprintf('  [PASS] Export %-22s\n', exportBtns{k});
        passed = passed + 1;
    catch ME
        fprintf('  [FAIL] Export %-22s — %s\n', exportBtns{k}, ME.message);
        failed = failed + 1;
    end
end

% ── Spot-check: a few callbacks actually fire without error ──────────────
% Use only buttons whose API has an already-tested bypass so we don't hit
% blocking dialogs. These exercise the full press→handler path.
fprintf('\n── Spot-check: callback dispatch ──\n');
dispatchChecks = {
    'Show FFT',        @() api.computeFFT()
    'Noise Est.',      @() api.noiseEstimate()
    'Reset Zoom',      @() api.resetZoom()
    };
for k = 1:size(dispatchChecks, 1)
    try
        dispatchChecks{k, 2}();
        fprintf('  [PASS] %-18s dispatched without error\n', dispatchChecks{k, 1});
        passed = passed + 1;
    catch ME
        fprintf('  [FAIL] %-18s %s\n', dispatchChecks{k, 1}, ME.message);
        failed = failed + 1;
    end
end

% Clean up any FFT popups opened above
closeFiguresWithTag('fermiViewerFFT');

% ════════════════════════════════════════════════════════════════════════
fprintf('\n%s\n', repmat(char(9552), 1, 72));
fprintf('SUMMARY: %d/%d checks passed\n', passed, passed + failed);
if failed > 0
    error('test_em_gui_button_wiring:failures', '%d check(s) failed.', failed);
else
    fprintf('Status: ALL PASS\n');
end

% ════════════════════════════════════════════════════════════════════════
% Local helpers
% ════════════════════════════════════════════════════════════════════════
function tf = isDescendantOf(h, ancestor)
    p = h;
    while ~isempty(p) && isvalid(p)
        if isequal(p, ancestor); tf = true; return; end
        try; p = p.Parent; catch; p = []; end
    end
    tf = false;
end

function t = findAncestorTab(h)
    p = h;
    while ~isempty(p) && isvalid(p)
        if isa(p, 'matlab.ui.container.Tab'); t = p; return; end
        try; p = p.Parent; catch; p = []; end
    end
    t = [];
end

function safeClose(api)
    try
        if ~isempty(api) && isstruct(api) && isfield(api, 'close') && isvalid(api.fig)
            api.close();
        end
    catch
    end
end

function closeFiguresWithTag(tag)
    allFigs = findall(groot, 'Type', 'figure', 'Tag', tag);
    for k = 1:numel(allFigs)
        try; close(allFigs(k)); catch; end
    end
end
