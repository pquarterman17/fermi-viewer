%TEST_SCALEBARPERSISTSTHROUGH  Verify that the FermiViewer scale bar overlay
%  survives image-processing operations without requiring the user to toggle
%  the checkbox off/on.
%
%  Regression test for the bug where filters, rotate/flip, crop, and undo
%  would erase scale bar graphics handles without consulting cbScaleBar.Value.
%
%  Run standalone:  cd tests; run imaging/test_scaleBarPersistsThroughProcessing
%  Run via suite:   runAllTests(Group="emgui")

clear; clc;

thisDir = fileparts(mfilename('fullpath'));
rootDir = fileparts(fileparts(thisDir));
if ~contains(path, rootDir)
    addpath(rootDir);
end

% ── Build a calibrated synthetic TIFF ─────────────────────────────────────
tmpDir = fullfile(tempdir, ...
    'sb_persist_test_' + string(datetime('now','Format','yyyyMMdd_HHmmss')));
mkdir(tmpDir);
cleanupTmp = onCleanup(@() rmdir(tmpDir, 's'));

tiffPath = fullfile(tmpDir, 'calib_synth.tif');
synthPx  = uint16(reshape(linspace(0, 65535, 64*64), 64, 64));
imwrite(synthPx, tiffPath);

passed = 0;
failed = 0;

% ────────────────────────────────────────────────────────────────────────────
%  Helpers
% ────────────────────────────────────────────────────────────────────────────
function tf = scaleBarPresent(api)
%SCALEBARPRESENT  Return true if the single-view scale bar handles are valid.
    ov = api.getOverlays();
    sb = ov.scalebar;
    tf = ~isempty(sb) && isstruct(sb) && ...
         isfield(sb, 'bar') && isvalid(sb.bar) && ...
         isfield(sb, 'label') && isvalid(sb.label);
end

function api = launch()
%LAUNCH  Start FermiViewer hidden.
    api = FermiViewer();
    api.fig.Visible = 'off';
    drawnow;
end

% ────────────────────────────────────────────────────────────────────────────
%  TEST 1 — Scale bar present immediately after load + calibration
% ────────────────────────────────────────────────────────────────────────────
fprintf('\n== TEST 1: Scale bar appears after calibrated load ==\n');
api = launch();
try
    api.loadImages({tiffPath});
    drawnow;
    api.setPixelSize(0.25, 'nm');
    % setPixelSize does NOT call rebuildScaleBar; we need to trigger displayImage
    % to honour the calibration.  Use setActiveIdxAPI (== reload).
    api.setActiveIdx(1);
    drawnow;

    assert(scaleBarPresent(api), 'Scale bar should be visible after calibrated load');
    fprintf('  Scale bar valid after load: PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end
try; api.close(); catch; end

% ────────────────────────────────────────────────────────────────────────────
%  TEST 2 — Scale bar survives a Gaussian filter (refreshDisplay path)
% ────────────────────────────────────────────────────────────────────────────
fprintf('\n== TEST 2: Scale bar survives Gaussian filter ==\n');
api = launch();
try
    api.loadImages({tiffPath});
    drawnow;
    api.setPixelSize(0.25, 'nm');
    api.setActiveIdx(1);
    drawnow;

    assert(scaleBarPresent(api), 'Pre-condition: scale bar must be present');

    api.applyFilter('gaussian', struct('Sigma', 1.5));
    drawnow;

    assert(scaleBarPresent(api), 'Scale bar should survive Gaussian filter');
    fprintf('  Scale bar valid after Gaussian filter: PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end
try; api.close(); catch; end

% ────────────────────────────────────────────────────────────────────────────
%  TEST 3 — Scale bar survives a rotate operation (full axes rebuild path)
% ────────────────────────────────────────────────────────────────────────────
fprintf('\n== TEST 3: Scale bar survives rotate 90 CW ==\n');
api = launch();
try
    api.loadImages({tiffPath});
    drawnow;
    api.setPixelSize(0.25, 'nm');
    api.setActiveIdx(1);
    drawnow;

    assert(scaleBarPresent(api), 'Pre-condition: scale bar must be present');

    api.rotateFlip('rot90cw');
    drawnow;

    assert(scaleBarPresent(api), 'Scale bar should survive rotate 90 CW');
    fprintf('  Scale bar valid after rotate: PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end
try; api.close(); catch; end

% ────────────────────────────────────────────────────────────────────────────
%  TEST 4 — Scale bar survives crop (rebuildAxesForNewSize path)
% ────────────────────────────────────────────────────────────────────────────
fprintf('\n== TEST 4: Scale bar survives crop ==\n');
api = launch();
try
    api.loadImages({tiffPath});
    drawnow;
    api.setPixelSize(0.25, 'nm');
    api.setActiveIdx(1);
    drawnow;

    assert(scaleBarPresent(api), 'Pre-condition: scale bar must be present');

    % Crop to [10 50] x [10 50]
    api.cropRect(10, 10, 50, 50);
    drawnow;

    assert(scaleBarPresent(api), 'Scale bar should survive crop');
    fprintf('  Scale bar valid after crop: PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end
try; api.close(); catch; end

% ────────────────────────────────────────────────────────────────────────────
%  TEST 5 — Scale bar survives undo after a filter (undoPop same-size path)
% ────────────────────────────────────────────────────────────────────────────
fprintf('\n== TEST 5: Scale bar survives undo after filter ==\n');
api = launch();
try
    api.loadImages({tiffPath});
    drawnow;
    api.setPixelSize(0.25, 'nm');
    api.setActiveIdx(1);
    drawnow;

    assert(scaleBarPresent(api), 'Pre-condition: scale bar must be present');

    api.applyFilter('median', struct('WindowSize', 3));
    drawnow;

    % Undo via API — FermiViewer exposes undoFilters through the processing
    % context menu callback but not directly via api.  Use applyFilter to
    % create undo state, then trigger undo via the button callback (api.fig).
    % We test the undo path by applying two filters then undoing once.
    api.applyFilter('gaussian', struct('Sigma', 1.0));
    drawnow;

    assert(scaleBarPresent(api), 'Scale bar must be present before undo');

    % Trigger undo by finding the Undo Filters button and pressing it
    undoBtns = findall(api.fig, 'Type', 'uibutton', 'Text', 'Undo Filters');
    assert(~isempty(undoBtns), 'Undo Filters button must exist');
    undoBtns(1).ButtonPushedFcn(undoBtns(1), []);
    drawnow;
    assert(scaleBarPresent(api), 'Scale bar should survive undo');
    fprintf('  Scale bar valid after undo: PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end
try; api.close(); catch; end

% ────────────────────────────────────────────────────────────────────────────
%  TEST 6 — Scale bar survives flip + filter combo
% ────────────────────────────────────────────────────────────────────────────
fprintf('\n== TEST 6: Scale bar survives flip then filter ==\n');
api = launch();
try
    api.loadImages({tiffPath});
    drawnow;
    api.setPixelSize(0.25, 'nm');
    api.setActiveIdx(1);
    drawnow;

    assert(scaleBarPresent(api), 'Pre-condition: scale bar must be present');

    api.rotateFlip('fliph');
    drawnow;
    assert(scaleBarPresent(api), 'Scale bar should survive fliph');

    api.applyFilter('gaussian', struct('Sigma', 2.0));
    drawnow;
    assert(scaleBarPresent(api), 'Scale bar should survive filter after flip');

    fprintf('  Scale bar valid after flip + filter: PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end
try; api.close(); catch; end

% ────────────────────────────────────────────────────────────────────────────
%  Summary
% ────────────────────────────────────────────────────────────────────────────
fprintf('\n════════════════════════════════════════════════════\n');
fprintf('  Scale bar persistence: %d passed, %d failed\n', passed, failed);
fprintf('════════════════════════════════════════════════════\n\n');

if failed > 0
    error('test_scaleBarPersistsThroughProcessing: %d test(s) FAILED', failed);
end
