%TEST_MEASUREMENTWORKSHOP  Headless tests for the MeasurementWorkshop
%   facade (W5 #69, task 1b).
%
%   Verifies the facade lifecycle works without a hook (model-only
%   path), the hook contract is checkable via hasHook, and bind /
%   bindCalibration / selectMeas / removeMeas / clearAll / close
%   round-trip cleanly.
%
%   Run:
%       run tests/imaging/test_measurementWorkshop
%       runAllTests(Group="emgui")

fprintf('\n');
fprintf('╔══════════════════════════════════════════════════════════════╗\n');
fprintf('║   MeasurementWorkshop facade — Headless Test Suite             ║\n');
fprintf('╚══════════════════════════════════════════════════════════════╝\n');

ROOT = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(ROOT);

passed = 0;
failed = 0;

% ═══════════════════════════════════════════════════════════════════════
%  TEST 1: Construction with empty hook — model-only mode works
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 1: construction without hook ══\n');
try
    ws = emViewer.measurement.MeasurementWorkshop();
    assert(isa(ws.model, 'emViewer.measurement.MeasurementWorkshopModel'), ...
        'workshop should hold a MeasurementWorkshopModel');
    assert(ws.numMeasurements() == 0, 'should start empty');
    assert(~ws.hasHook('drawOverlay'), 'no hook fields when constructed empty');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 2: hasHook detects presence + callable function handles
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 2: hasHook contract check ══\n');
try
    hook.setStatus  = @(msg) [];
    hook.drawOverlay = @(type, args) [];
    hook.replot     = @() [];
    hook.notAHandle = 'oops';     % wrong type — hasHook must reject
    ws = emViewer.measurement.MeasurementWorkshop(hook);
    assert(ws.hasHook('setStatus'),    'setStatus should be detected');
    assert(ws.hasHook('drawOverlay'),  'drawOverlay should be detected');
    assert(ws.hasHook('replot'),       'replot should be detected');
    assert(~ws.hasHook('notAHandle'),  'non-function-handle field rejected');
    assert(~ws.hasHook('missing'),     'absent field rejected');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 3: bind / selectMeas / removeMeas / clearAll round-trip
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 3: list-management methods proxy to model ══\n');
try
    overlays = { ...
        struct('type','distance', 'distance', 5,  'unit','px'), ...
        struct('type','polyline', 'totalDist', 7, 'unit','nm', ...
               'vertices', [0 0; 3 0; 3 4]), ...
        struct('type','rectROI',  'xMin', 10, 'xMax', 30, 'yMin', 5, 'yMax', 25)};
    ws = emViewer.measurement.MeasurementWorkshop();
    ws.bind(overlays);
    assert(ws.numMeasurements() == 3, 'all 3 overlays should be preserved');
    ws.selectMeas(2);
    assert(ws.model.selectedIdx == 2, 'selectMeas should proxy to model');
    ws.removeMeas(1);
    assert(ws.numMeasurements() == 2, 'removeMeas should drop one entry');
    assert(ws.model.selectedIdx == 1, 'selection should slide down');
    ws.clearAll();
    assert(ws.numMeasurements() == 0, 'clearAll should empty');

    % bind() with no arg / empty must reset cleanly
    ws.bind(overlays);
    ws.bind({});
    assert(ws.numMeasurements() == 0, 'bind({}) should empty the workshop');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 4: bindCalibration applies pixelSize / pixelUnit to model
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 4: bindCalibration proxies to model.bindFromImage ══\n');
try
    ws = emViewer.measurement.MeasurementWorkshop();
    ws.bindCalibration(struct('pixelSize', 0.25, 'pixelUnit', 'um'));
    assert(abs(ws.model.pixelSize - 0.25) < 1e-9, 'pixelSize bound');
    assert(strcmp(ws.model.pixelUnit, 'um'), 'pixelUnit bound');
    % Empty / missing imgInfo should be a no-op
    ws.bindCalibration([]);
    assert(abs(ws.model.pixelSize - 0.25) < 1e-9, 'empty bind is no-op');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 5: show / hide are no-ops (stubs for future dialog window)
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 5: show/hide are safe no-ops ══\n');
try
    ws = emViewer.measurement.MeasurementWorkshop();
    ws.show();   % should not error
    ws.hide();   % should not error
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 6: close() with no figure is a no-op
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 6: close() is safe with no figure ══\n');
try
    ws = emViewer.measurement.MeasurementWorkshop();
    ws.close();   % should not error
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 7: sync() keeps model in sync with overlays mutations
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 7: sync() keeps model current after mutations ══\n');
try
    ws = emViewer.measurement.MeasurementWorkshop();
    overlays = { ...
        struct('type','distance', 'distance', 5, 'unit','px'), ...
        struct('type','distance', 'distance', 10, 'unit','px')};
    ws.sync(overlays);
    assert(ws.numMeasurements() == 2, 'sync should populate model with 2 entries');
    assert(abs(ws.model.measurements(1).value - 5) < 1e-9, 'first measurement value');

    % Simulate append
    overlays{3} = struct('type','distance', 'distance', 15, 'unit','nm');
    ws.sync(overlays);
    assert(ws.numMeasurements() == 3, 'sync after append should show 3');

    % Simulate delete
    overlays(2) = [];
    ws.sync(overlays);
    assert(ws.numMeasurements() == 2, 'sync after delete should show 2');

    % Simulate clear
    ws.sync({});
    assert(ws.numMeasurements() == 0, 'sync({}) should empty');

    % sync swallows errors (pass garbage — should not throw)
    ws.sync({'not a struct'});
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ── Summary ────────────────────────────────────────────────────────────
fprintf('\n');
fprintf('╔══════════════════════════════════════════════════════════════╗\n');
fprintf('║ Results: %2d passed, %2d failed                                ║\n', passed, failed);
fprintf('╚══════════════════════════════════════════════════════════════╝\n');
