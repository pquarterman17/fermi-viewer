%TEST_MEASUREMENTWORKSHOPMODEL  Headless tests for the FermiViewer
%   measurement workshop pattern (W5 #28 / #65).
%
%   Exercises the MeasurementWorkshopModel handle class against synthetic
%   image data — no GUI launch required. Validates:
%     - Construction defaults
%     - addDistance with calibrated and uncalibrated cases
%     - addAngle (perpendicular rays = 90 degrees)
%     - addPolyline path length
%     - addLineProfile against a known ramp image
%     - removeMeas / clearAll / selectMeas list management
%     - aggregateStats over distance-like measurements
%     - exportCSV round-trip
%     - normalizeMeasurements legacy-shape upgrade (workshop contract rule #1)
%
%   Run:
%       run tests/imaging/test_measurementWorkshopModel
%       runAllTests(Group="emgui")
%
%   All test data is synthetic.

fprintf('\n');
fprintf('╔══════════════════════════════════════════════════════════════╗\n');
fprintf('║   MeasurementWorkshopModel — Headless Test Suite                ║\n');
fprintf('╚══════════════════════════════════════════════════════════════╝\n');

ROOT = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(ROOT);

tmpDir = fullfile(tempdir, sprintf('mwm_test_%s', datestr(now, 'yyyymmdd_HHMMSS')));
mkdir(tmpDir);
cleanupDir = onCleanup(@() rmdir(tmpDir, 's'));

passed = 0;
failed = 0;

% ═══════════════════════════════════════════════════════════════════════
%  TEST 1: Construction defaults
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 1: construction defaults ══\n');
try
    m = emViewer.measurement.MeasurementWorkshopModel();
    assert(isnan(m.pixelSize), 'pixelSize should default to NaN');
    assert(strcmp(m.pixelUnit, 'px'), 'pixelUnit should default to ''px''');
    assert(m.tiltAngle == 0, 'tiltAngle should default to 0');
    assert(strcmp(m.tiltAxis, 'Y'), 'tiltAxis should default to ''Y''');
    assert(strcmp(m.tiltGeom, 'CrossSection'), 'tiltGeom should default to ''CrossSection''');
    assert(m.isEmpty(), 'new model should be empty');
    assert(m.selectedIdx == 0, 'selectedIdx should default to 0');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 2: addDistance — uncalibrated 3-4-5 triangle
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 2: addDistance uncalibrated (3-4-5) ══\n');
try
    m = emViewer.measurement.MeasurementWorkshopModel();
    r = m.addDistance([0 0], [3 4]);
    assert(numel(m.measurements) == 1, 'should append 1 measurement');
    assert(strcmp(r.type, 'distance'), 'type should be ''distance''');
    assert(abs(r.value - 5) < 1e-9, sprintf('value should be 5, got %.4f', r.value));
    assert(strcmp(r.unit, 'px'), 'unit should be ''px'' when uncalibrated');
    assert(isequal(r.points, [0 0; 3 4]), 'points should be [p1;p2]');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 3: addDistance — calibrated (pixelSize = 0.5 nm)
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 3: addDistance calibrated 0.5 nm/px ══\n');
try
    m = emViewer.measurement.MeasurementWorkshopModel();
    m.pixelSize = 0.5;
    m.pixelUnit = 'nm';
    r = m.addDistance([0 0], [6 8]);     % 10 px * 0.5 = 5 nm
    assert(abs(r.value - 5) < 1e-9, sprintf('value should be 5 nm, got %.4f', r.value));
    assert(strcmp(r.unit, 'nm'), 'unit should be ''nm''');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 4: addAngle — perpendicular rays = 90 deg
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 4: addAngle perpendicular = 90 deg ══\n');
try
    m = emViewer.measurement.MeasurementWorkshopModel();
    r = m.addAngle([0 0], [10 0], [0 10]);
    assert(strcmp(r.type, 'angle'), 'type should be ''angle''');
    assert(abs(r.value - 90) < 1e-6, sprintf('angle should be 90, got %.4f', r.value));
    assert(strcmp(r.unit, 'deg'), 'unit should be ''deg''');

    % 60-degree triangle check
    m2 = emViewer.measurement.MeasurementWorkshopModel();
    r2 = m2.addAngle([0 0], [1 0], [cos(pi/3) sin(pi/3)]);
    assert(abs(r2.value - 60) < 1e-4, sprintf('angle should be 60, got %.4f', r2.value));
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 5: addPolyline — known path length
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 5: addPolyline path length ══\n');
try
    m = emViewer.measurement.MeasurementWorkshopModel();
    pts = [0 0; 3 0; 3 4];      % segments: 3 + 4 = 7
    r = m.addPolyline(pts);
    assert(strcmp(r.type, 'polyline'), 'type should be ''polyline''');
    assert(abs(r.value - 7) < 1e-9, sprintf('length should be 7, got %.4f', r.value));

    % Reject malformed input
    err = false;
    try
        m.addPolyline([1 2 3]);  %#ok<NASGU>  -- not Nx2
    catch
        err = true;
    end
    assert(err, 'addPolyline should error on non-Nx2 input');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 6: addLineProfile — sample a synthetic ramp image
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 6: addLineProfile on a synthetic ramp ══\n');
try
    m = emViewer.measurement.MeasurementWorkshopModel();
    H = 64; W = 64;
    [X, ~] = meshgrid(1:W, 1:H);
    img = double(X);   % img(row, col) = col
    % Sample a horizontal line — values should equal x coordinates
    r = m.addLineProfile([10 32], [50 32], img, nSamples=41);
    assert(strcmp(r.type, 'lineprofile'), 'type should be ''lineprofile''');
    assert(numel(r.profile) == 41, 'profile length should be nSamples');
    assert(numel(r.profileX) == 41, 'profileX length should be nSamples');
    % First sample at x=10, last at x=50 (ramp value matches x)
    assert(abs(r.profile(1) - 10) < 1e-6, sprintf('first profile sample should be ~10, got %.4f', r.profile(1)));
    assert(abs(r.profile(end) - 50) < 1e-6, sprintf('last profile sample should be ~50, got %.4f', r.profile(end)));
    % Distance sqrt(40^2 + 0^2) = 40
    assert(abs(r.value - 40) < 1e-9, sprintf('distance should be 40, got %.4f', r.value));
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 7: removeMeas / selectMeas / clearAll
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 7: list management (remove / select / clear) ══\n');
try
    m = emViewer.measurement.MeasurementWorkshopModel();
    m.addDistance([0 0], [3 4]);
    m.addDistance([0 0], [6 8]);
    m.addDistance([0 0], [9 12]);
    assert(numel(m.measurements) == 3, 'should have 3 entries');

    m.selectMeas(2);
    assert(m.selectedIdx == 2, 'selectMeas should set selectedIdx');

    m.removeMeas(2);
    assert(numel(m.measurements) == 2, 'removeMeas should drop 1 entry');
    assert(m.selectedIdx == 0, 'selectedIdx should reset when selected entry removed');

    % Out-of-range remove is a no-op
    m.removeMeas(99);
    assert(numel(m.measurements) == 2, 'out-of-range removeMeas should not modify list');

    m.clearAll();
    assert(m.isEmpty(), 'clearAll should empty the list');
    assert(m.selectedIdx == 0, 'clearAll should reset selectedIdx');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 8: aggregateStats over distance-like measurements
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 8: aggregateStats ══\n');
try
    m = emViewer.measurement.MeasurementWorkshopModel();
    m.addDistance([0 0], [3 4]);     % 5
    m.addDistance([0 0], [6 8]);     % 10
    m.addDistance([0 0], [9 12]);    % 15
    m.addAngle([0 0], [1 0], [0 1]); % 90 — should NOT be included

    s = m.aggregateStats();
    assert(s.count == 3, sprintf('expected 3 distance-like entries, got %d', s.count));
    assert(abs(s.mean - 10) < 1e-6, sprintf('mean should be 10, got %.4f', s.mean));
    assert(abs(s.min - 5) < 1e-6, 'min should be 5');
    assert(abs(s.max - 15) < 1e-6, 'max should be 15');

    % Empty stats
    m2 = emViewer.measurement.MeasurementWorkshopModel();
    s2 = m2.aggregateStats();
    assert(s2.count == 0, 'empty stats should report count=0');
    assert(isnan(s2.mean), 'empty stats mean should be NaN');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 9: exportCSV round-trip
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 9: exportCSV writes the expected rows ══\n');
try
    m = emViewer.measurement.MeasurementWorkshopModel();
    m.pixelSize = 1.0;  m.pixelUnit = 'nm';
    m.addDistance([0 0], [3 4], label='AB');     % 5 nm
    m.addPolyline([0 0; 3 0; 3 4]);               % 7 nm
    csvFile = fullfile(tmpDir, 'meas.csv');
    m.exportCSV(csvFile);
    assert(exist(csvFile, 'file') == 2, 'CSV file should exist');
    txt = fileread(csvFile);
    lines = strsplit(strtrim(txt), newline);
    assert(numel(lines) == 3, sprintf('expected header + 2 rows, got %d lines', numel(lines)));
    assert(contains(lines{1}, 'Idx,Type,Value,Unit'), 'header row missing fields');
    assert(contains(lines{2}, 'distance') && contains(lines{2}, 'AB'), 'row 1 should describe distance ''AB''');
    assert(contains(lines{3}, 'polyline'), 'row 2 should describe polyline');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 10: normalizeMeasurements upgrades legacy 4-field input
%           (workshop contract rule: legacy-shape compatibility)
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 10: normalizeMeasurements upgrades legacy structs ══\n');
try
    legacy = struct('type', {'distance','angle'}, ...
                    'points', {[0 0; 3 4], [0 0; 1 0; 0 1]}, ...
                    'value',  {5, 90}, ...
                    'unit',   {'px','deg'});
    out = emViewer.measurement.MeasurementWorkshopModel.normalizeMeasurements(legacy);
    canon = {'type','points','value','unit','label','profile','profileX'};
    for fi = 1:numel(canon)
        assert(isfield(out, canon{fi}), sprintf('output missing field ''%s''', canon{fi}));
    end
    assert(numel(out) == 2, 'should preserve element count');
    assert(strcmp(out(1).type, 'distance'), 'first element should still be distance');

    % Empty input returns canonical empty struct
    out2 = emViewer.measurement.MeasurementWorkshopModel.normalizeMeasurements([]);
    assert(numel(out2) == 0, 'empty input should yield 0-length struct');
    for fi = 1:numel(canon)
        assert(isfield(out2, canon{fi}), sprintf('empty output missing field ''%s''', canon{fi}));
    end
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 11: bindFromImage pulls calibration from imgInfo struct
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 11: bindFromImage applies pixelSize / pixelUnit ══\n');
try
    m = emViewer.measurement.MeasurementWorkshopModel();
    info = struct('pixelSize', 0.25, 'pixelUnit', 'um');
    m.bindFromImage(info);
    assert(abs(m.pixelSize - 0.25) < 1e-9, 'pixelSize should be bound from imgInfo');
    assert(strcmp(m.pixelUnit, 'um'), 'pixelUnit should be bound from imgInfo');

    % NaN pixelSize is ignored
    m2 = emViewer.measurement.MeasurementWorkshopModel();
    m2.bindFromImage(struct('pixelSize', NaN, 'pixelUnit', 'nm'));
    assert(isnan(m2.pixelSize), 'NaN pixelSize should be ignored');
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

if failed > 0
    error('test_measurementWorkshopModel: %d test(s) failed', failed);
end
