%TEST_FV_GRAINWORKSHOP  Headless API test for the GrainWorkshop window.
%
%   Drives fermiViewer.grains.openGrainWorkshop through its programmatic
%   `api` (no real mouse events / dialogs) under headless figures:
%     1. window opens; automatic mode finds grains
%     2. switch to trained mode, paint scribbles via api.paint, run → grains
%     3. export CSV to a temp path (api.exportCSV bypasses uiputfile)
%     4. clear scribbles resets state
%
%   Run:
%       run tests/imaging/test_fv_grainWorkshop
%       runAllTests(Group="fvgui")

fprintf('\n');
fprintf('╔══════════════════════════════════════════════════════════════╗\n');
fprintf('║  GrainWorkshop headless API                                  ║\n');
fprintf('╚══════════════════════════════════════════════════════════════╝\n');

ROOT = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(ROOT);

passed = 0;
failed = 0;

set(groot, 'DefaultFigureVisible', 'off');

% Two-orientation synthetic image (same brightness, different stripe dir).
[Xc, Yc] = meshgrid(1:128, 1:128);
f = 2*pi/8;
img = cos(f * Xc);
img(:, 65:end) = cos(f * Yc(:, 65:end));

ctx = struct( ...
    'setStatus',    @(~) [], ...
    'guiPixelSize', @() 0.5, ...
    'guiPixelUnit', @() "nm");

api = [];

% ═══════════════════════════════════════════════════════════════════════
%  TEST 1: window opens, automatic mode finds grains
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 1: open + automatic run ══\n');
try
    api = fermiViewer.grains.openGrainWorkshop(img, ctx);
    assert(isvalid(api.fig), 'workshop figure should be valid');
    api.setMode('auto');
    api.run();
    r = api.getResult();
    assert(isfield(r, 'numGrains') && r.numGrains >= 2, ...
        sprintf('auto mode should find >=2 grains, got %d', ...
        (isfield(r,'numGrains')*r.numGrains)));
    fprintf('  PASS (auto: %d grains)\n', r.numGrains);
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 2: trained mode — paint scribbles via API, run
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 2: trained mode via api.paint ══\n');
try
    api.setMode('trained');
    api.model.paintClass  = 1;
    api.model.brushRadius = 4;
    for xy = [20 30; 24 32; 28 28]'    % left half (class 1)
        api.paint(xy(1), xy(2));
    end
    api.model.paintClass = 2;
    for xy = [100 30; 104 32; 108 28]' % right half (class 2)
        api.paint(xy(1), xy(2));
    end
    assert(api.model.hasScribbles(), 'scribbles should be recorded');

    api.run();
    r = api.getResult();
    assert(r.numGrains >= 2, sprintf('trained mode >=2 grains, got %d', r.numGrains));
    assert(api.model.isTrained(), 'a classifier should have been trained');
    fprintf('  PASS (trained: %d grains)\n', r.numGrains);
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 3: export CSV (programmatic, no dialog)
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 3: export CSV ══\n');
try
    tmp = [tempname '.csv'];
    api.exportCSV(tmp);
    assert(isfile(tmp), 'CSV file should be written');
    txt = readlines(tmp);
    txt = txt(strlength(txt) > 0);
    r = api.getResult();
    assert(numel(txt) == r.numGrains + 1, ...
        sprintf('expected %d lines (header + grains), got %d', ...
        r.numGrains + 1, numel(txt)));
    delete(tmp);
    fprintf('  PASS (CSV header + %d grain rows)\n', r.numGrains);
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 4: clear scribbles resets training state
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 4: clear scribbles ══\n');
try
    api.clearScribbles();
    assert(~api.model.hasScribbles(), 'scribbles should be cleared');
    assert(~api.model.isTrained(), 'trained model should be cleared');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ── Cleanup ──────────────────────────────────────────────────────────────
try, if ~isempty(api) && isvalid(api.fig), close(api.fig); end, catch, end

% ── Summary ────────────────────────────────────────────────────────────
fprintf('\n');
fprintf('╔══════════════════════════════════════════════════════════════╗\n');
fprintf('║ Results: %2d passed, %2d failed                                ║\n', passed, failed);
fprintf('╚══════════════════════════════════════════════════════════════╝\n');

if failed > 0
    error('test_fv_grainWorkshop: %d test(s) failed', failed);
end
