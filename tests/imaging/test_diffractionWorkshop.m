%TEST_DIFFRACTIONWORKSHOP  Headless tests for the DiffractionWorkshop
%   facade and DiffractionWorkshopModel.
%
%   Run:
%       run tests/imaging/test_diffractionWorkshop
%       runAllTests(Group="emgui")

fprintf('\n');
fprintf('%s\n', repmat(char(9552), 1, 62));
fprintf('  DiffractionWorkshop — Headless Test Suite\n');
fprintf('%s\n', repmat(char(9552), 1, 62));

ROOT = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(ROOT);

passed = 0;
failed = 0;

% ═══════════════════════════════════════════════════════════════════════
%  TEST 1: Model construction defaults
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n== TEST 1: model construction defaults ==\n');
try
    m = emViewer.diffraction.DiffractionWorkshopModel();
    assert(m.numSpots() == 0, 'should start with 0 spots');
    assert(isempty(fieldnames(m.results)) || ~isfield(m.results, 'candidates'), ...
        'results should be empty struct');
    assert(m.accVoltage == 200, 'default voltage 200 kV');
    assert(isnan(m.cameraLength), 'default camera length NaN');
    assert(~m.hasResults(), 'hasResults false when empty');
    assert(strcmp(m.pixelUnit, 'px'), 'default unit px');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 2: addSpot / addSpots / numSpots
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n== TEST 2: spot management ==\n');
try
    m = emViewer.diffraction.DiffractionWorkshopModel();
    m.addSpot(100, 200);
    assert(m.numSpots() == 1, 'one spot after addSpot');
    assert(m.spots(1,1) == 100 && m.spots(1,2) == 200, 'spot coords');
    m.addSpots([50 60; 70 80]);
    assert(m.numSpots() == 3, 'three spots after addSpots');
    m.clearSpots();
    assert(m.numSpots() == 0, 'empty after clearSpots');
    assert(~m.hasResults(), 'results cleared with spots');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 3: setResults / hasResults / getSelectedCandidate / selectCandidate
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n== TEST 3: results management ==\n');
try
    m = emViewer.diffraction.DiffractionWorkshopModel();
    res.candidates = struct( ...
        'phaseName', {'Al', 'Si'}, ...
        'formula',   {'Al', 'Si'}, ...
        'score',     {0.95, 0.80}, ...
        'nMatched',  {5, 3}, ...
        'nSpots',    {6, 6}, ...
        'zoneAxis',  {[0 0 1], [1 1 0]}, ...
        'matchedD',  {[2.338 2.024], [3.135 1.920]}, ...
        'matchedHKL',{[1 1 1; 2 0 0], [1 1 1; 2 2 0]});
    res.center = [256 256];
    res.measuredR = [50 80];
    m.setResults(res);
    assert(m.hasResults(), 'hasResults true after setResults');
    c = m.getSelectedCandidate();
    assert(strcmp(c.phaseName, 'Al'), 'default selects first candidate');
    m.selectCandidate(2);
    c2 = m.getSelectedCandidate();
    assert(strcmp(c2.phaseName, 'Si'), 'selectCandidate(2) picks Si');
    m.selectCandidate(99);
    c3 = m.getSelectedCandidate();
    assert(strcmp(c3.phaseName, 'Si'), 'out-of-range select is no-op');
    m.setResults([]);
    assert(~m.hasResults(), 'cleared after setResults([])');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 4: bindFromImage
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n== TEST 4: bindFromImage calibration ==\n');
try
    m = emViewer.diffraction.DiffractionWorkshopModel();
    imgInfo = struct('pixelSize', 0.5, 'pixelUnit', 'nm', ...
        'calibrated', true, 'pixels', zeros(512, 512));
    m.bindFromImage(imgInfo);
    assert(abs(m.pixelSize - 0.5) < 1e-9, 'pixelSize bound');
    assert(strcmp(m.pixelUnit, 'nm'), 'pixelUnit bound');
    assert(m.calibrated, 'calibrated flag');
    assert(all(m.imageSize == [512 512]), 'imageSize from pixels');
    m.bindFromImage([]);
    assert(abs(m.pixelSize - 0.5) < 1e-9, 'empty bind is no-op');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 5: sync from appData-shaped struct
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n== TEST 5: sync from appData fields ==\n');
try
    m = emViewer.diffraction.DiffractionWorkshopModel();
    s.diffSpots = [100 200; 150 250];
    s.diffCameraLen  = 500;
    s.diffAccVoltage = 300;
    m.sync(s);
    assert(m.numSpots() == 2, '2 spots after sync');
    assert(m.cameraLength == 500, 'camera length synced');
    assert(m.accVoltage == 300, 'acc voltage synced');
    s2.diffSpots = [];
    m.sync(s2);
    assert(m.numSpots() == 0, 'empty spots after nil sync');
    m.sync('garbage');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 6: summarize
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n== TEST 6: summarize ==\n');
try
    m = emViewer.diffraction.DiffractionWorkshopModel();
    s1 = m.summarize();
    assert(contains(s1, 'No spots'), 'empty state summary');
    m.addSpots([10 20; 30 40; 50 60]);
    s2 = m.summarize();
    assert(contains(s2, '3 spots'), 'spot count in summary');
    res.candidates = struct('phaseName', 'Cu', 'score', 0.88, ...
        'formula', 'Cu', 'nMatched', 4, 'nSpots', 5, ...
        'zoneAxis', [0 0 1], 'matchedD', [2.088], 'matchedHKL', [1 1 1]);
    res.center = [128 128];
    res.measuredR = [40];
    m.setResults(res);
    s3 = m.summarize();
    assert(contains(s3, 'Cu') && contains(s3, '0.88'), ...
        'summary includes phase name and score');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 7: computeDSpacings
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n== TEST 7: computeDSpacings ==\n');
try
    m = emViewer.diffraction.DiffractionWorkshopModel();
    m.imageSize = [512 512];
    m.pixelSize = 0.1;
    cx = 256; cy = 256;
    m.addSpot(cy, cx + 100);
    dVals = m.computeDSpacings();
    N = sqrt(512 * 512);
    expected = N * 0.1 / 100;
    assert(abs(dVals(1) - expected) < 1e-6, 'd-spacing calculation');
    m2 = emViewer.diffraction.DiffractionWorkshopModel();
    assert(isempty(m2.computeDSpacings()), 'empty when no spots');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 8: spotsTable
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n== TEST 8: spotsTable ==\n');
try
    m = emViewer.diffraction.DiffractionWorkshopModel();
    tbl = m.spotsTable();
    assert(height(tbl) == 0, 'empty table');
    m.addSpots([10 20; 30 40]);
    tbl = m.spotsTable();
    assert(height(tbl) == 2, '2-row table');
    assert(tbl.SpotRow(1) == 10 && tbl.SpotCol(2) == 40, 'table values');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 9: Facade construction + delegation
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n== TEST 9: facade construction + delegation ==\n');
try
    ws = emViewer.diffraction.DiffractionWorkshop();
    assert(isa(ws.model, 'emViewer.diffraction.DiffractionWorkshopModel'), ...
        'facade holds model');
    assert(ws.numSpots() == 0, 'numSpots delegates');
    assert(~ws.hasResults(), 'hasResults delegates');
    ws.model.addSpots([10 20; 30 40]);
    assert(ws.numSpots() == 2, 'numSpots reflects model');
    ws.clearSpots();
    assert(ws.numSpots() == 0, 'clearSpots delegates');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 10: Facade hasHook
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n== TEST 10: hasHook contract ==\n');
try
    hook.setStatus  = @(msg) [];
    hook.drawOverlay = @(type, args) [];
    hook.notAHandle = 'string';
    ws = emViewer.diffraction.DiffractionWorkshop(hook);
    assert(ws.hasHook('setStatus'), 'setStatus detected');
    assert(ws.hasHook('drawOverlay'), 'drawOverlay detected');
    assert(~ws.hasHook('notAHandle'), 'non-handle rejected');
    assert(~ws.hasHook('missing'), 'absent rejected');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 11: show/hide/close are safe no-ops
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n== TEST 11: show/hide/close no-ops ==\n');
try
    ws = emViewer.diffraction.DiffractionWorkshop();
    ws.show();
    ws.hide();
    ws.close();
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 12: Facade sync delegates to model
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n== TEST 12: facade sync ==\n');
try
    ws = emViewer.diffraction.DiffractionWorkshop();
    ws.sync(struct('diffSpots', [10 20; 30 40], 'diffAccVoltage', 300));
    assert(ws.numSpots() == 2, 'sync propagated spots');
    assert(ws.model.accVoltage == 300, 'sync propagated voltage');
    ws.sync(struct('diffSpots', []));
    assert(ws.numSpots() == 0, 'sync cleared');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ── Summary ────────────────────────────────────────────────────────────
fprintf('\n%s\n', repmat(char(9552), 1, 62));
fprintf('Results: %2d passed, %2d failed\n', passed, failed);
fprintf('%s\n', repmat(char(9552), 1, 62));
if failed > 0
    error('test_diffractionWorkshop:failures', '%d check(s) failed.', failed);
else
    fprintf('Status: ALL PASS\n');
end
