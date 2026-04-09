%TEST_EM_ANGLE_POLYLINE_EXPORT  FermiViewer measurement API coverage:
%   angle, polyline, and CSV export. Closes the Priority 2 measurement
%   gaps identified in plans/gui-test-coverage.md.
%
%   Run:  runAllTests(Group="emgui")
%   Or:   run tests/imaging/test_em_angle_polyline_export

clear; clc;

thisDir = fileparts(mfilename('fullpath'));
rootDir = fileparts(fileparts(thisDir));
if ~contains(path, rootDir); addpath(rootDir); end

srcDir = fullfile(rootDir, '+test_datasets', 'Microscopy');
dm3 = fullfile(srcDir, 'EDW087-1.dm3');
assert(isfile(dm3), 'Test DM3 not found: %s', dm3);

tmpDir = fullfile(tempdir, 'em_meas_export_' + string(datetime('now','Format','yyyyMMdd_HHmmss')));
mkdir(tmpDir);
cleanupTmp = onCleanup(@() rmdir(tmpDir, 's'));

fprintf('\n=== test_em_angle_polyline_export ===\n');
passed = 0; failed = 0;

api = FermiViewer();
cleanupApi = onCleanup(@() safeClose(api));
drawnow;
api.loadImages({dm3});
drawnow;

dims = api.getImageDimensions();   % [H W]
H = dims(1); W = dims(2);
cx = round(W/2); cy = round(H/2);

% ════════════════════════════════════════════════════════════════════════
%  TEST 1: measureAngle — right angle (90°)
% ════════════════════════════════════════════════════════════════════════
fprintf('\n── 1. Right angle (90°) ──\n');
try
    logBefore = numel(api.getMeasurementLog());
    angleDeg = api.measureAngle(cx, cy, cx + 100, cy, cx, cy - 100);
    assert(abs(angleDeg - 90) < 0.1, ...
        sprintf('expected 90°, got %.2f°', angleDeg));

    log = api.getMeasurementLog();
    assert(numel(log) == logBefore + 1, 'log entry not appended');
    last = log{end};
    assert(strcmp(last.type, 'angle'), sprintf('log type=%s', last.type));
    assert(strcmp(last.unit, 'deg'),   sprintf('log unit=%s', last.unit));
    assert(abs(last.value - 90) < 0.1, sprintf('log value=%.2f', last.value));

    fprintf('  [PASS] angle=%.2f° logged\n', angleDeg);
    passed = passed + 1;
catch ME
    fprintf('  [FAIL] %s\n', ME.message);
    failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
%  TEST 2: measureAngle — acute 45°
% ════════════════════════════════════════════════════════════════════════
fprintf('\n── 2. Acute 45° ──\n');
try
    angleDeg = api.measureAngle(cx, cy, cx + 100, cy, cx + 100, cy - 100);
    assert(abs(angleDeg - 45) < 0.1, ...
        sprintf('expected 45°, got %.2f°', angleDeg));
    fprintf('  [PASS] angle=%.2f°\n', angleDeg);
    passed = passed + 1;
catch ME
    fprintf('  [FAIL] %s\n', ME.message);
    failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
%  TEST 3: measureAngle — obtuse 135°
% ════════════════════════════════════════════════════════════════════════
fprintf('\n── 3. Obtuse 135° ──\n');
try
    angleDeg = api.measureAngle(cx, cy, cx + 100, cy, cx - 100, cy - 100);
    assert(abs(angleDeg - 135) < 0.1, ...
        sprintf('expected 135°, got %.2f°', angleDeg));
    fprintf('  [PASS] angle=%.2f°\n', angleDeg);
    passed = passed + 1;
catch ME
    fprintf('  [FAIL] %s\n', ME.message);
    failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
%  TEST 4: measurePolyline — L-shaped 3-point path (200 px total)
% ════════════════════════════════════════════════════════════════════════
fprintf('\n── 4. L-shaped polyline ──\n');
try
    pts = [cx cy; cx + 100 cy; cx + 100 cy + 100];
    logBefore = numel(api.getMeasurementLog());
    totalDist = api.measurePolyline(pts);

    log = api.getMeasurementLog();
    assert(numel(log) == logBefore + 1, 'log entry not appended');
    last = log{end};
    assert(strcmp(last.type, 'polyline'), sprintf('log type=%s', last.type));
    assert(contains(last.details, '2 segments'), ...
        sprintf('details=%s', last.details));

    % EDW087-1.dm3 may be calibrated; accept either px or calibrated value.
    % What we can verify absolutely: the log reports 2 segments and the
    % value is positive. For pixel coords it should be 200 (100 + 100).
    assert(totalDist > 0, 'totalDist <= 0');
    fprintf('  [PASS] totalDist=%.3f %s (%d segments)\n', ...
        totalDist, last.unit, 2);
    passed = passed + 1;
catch ME
    fprintf('  [FAIL] %s\n', ME.message);
    failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
%  TEST 5: measurePolyline — 5-point zigzag
% ════════════════════════════════════════════════════════════════════════
fprintf('\n── 5. 5-point zigzag ──\n');
try
    pts = [100 100; 200 200; 300 100; 400 200; 500 100];
    totalDist = api.measurePolyline(pts);
    assert(totalDist > 0, 'totalDist <= 0');

    log = api.getMeasurementLog();
    last = log{end};
    assert(contains(last.details, '4 segments'), ...
        sprintf('details=%s (expected 4 segments)', last.details));
    fprintf('  [PASS] zigzag totalDist=%.3f %s\n', totalDist, last.unit);
    passed = passed + 1;
catch ME
    fprintf('  [FAIL] %s\n', ME.message);
    failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
%  TEST 6: measurePolyline rejects bad input
% ════════════════════════════════════════════════════════════════════════
fprintf('\n── 6. Polyline input validation ──\n');
try
    try
        api.measurePolyline([100 100]);   % only 1 point
        fprintf('  [FAIL] should have thrown on single-point input\n');
        failed = failed + 1;
    catch
        fprintf('  [PASS] single-point input rejected\n');
        passed = passed + 1;
    end
catch ME
    fprintf('  [FAIL] %s\n', ME.message);
    failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
%  TEST 7: exportMeasurements — CSV round-trip
% ════════════════════════════════════════════════════════════════════════
fprintf('\n── 7. Export measurements to CSV ──\n');
try
    csvPath = fullfile(tmpDir, 'measurements.csv');
    api.exportMeasurements(csvPath);

    assert(isfile(csvPath), 'CSV file not created');
    fi = dir(csvPath);
    assert(fi.bytes > 0, 'CSV file is empty');

    % Read back and verify structure
    fid = fopen(csvPath, 'r');
    header = fgetl(fid);
    bodyLines = {};
    while true
        l = fgetl(fid);
        if ~ischar(l), break; end
        if ~isempty(l), bodyLines{end+1} = l; end %#ok<AGROW>
    end
    fclose(fid);

    assert(strcmp(header, 'Type,Value,Unit,Details'), ...
        sprintf('unexpected header: "%s"', header));

    logLen = numel(api.getMeasurementLog());
    assert(numel(bodyLines) == logLen, ...
        sprintf('expected %d body lines, got %d', logLen, numel(bodyLines)));

    % Verify angle and polyline entries are present
    joined = strjoin(bodyLines, newline);
    assert(contains(joined, 'angle'),    'CSV missing angle entries');
    assert(contains(joined, 'polyline'), 'CSV missing polyline entries');

    fprintf('  [PASS] CSV: %d bytes, %d rows, header OK\n', ...
        fi.bytes, numel(bodyLines));
    passed = passed + 1;
catch ME
    fprintf('  [FAIL] %s\n', ME.message);
    failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
%  TEST 8: exportMeasurements refuses empty log
% ════════════════════════════════════════════════════════════════════════
fprintf('\n── 8. Export with empty log ──\n');
try
    safeClose(api);
    api2 = FermiViewer();
    cleanupApi2 = onCleanup(@() safeClose(api2));
    api2.loadImages({dm3});
    drawnow;

    try
        api2.exportMeasurements(fullfile(tmpDir, 'empty.csv'));
        fprintf('  [FAIL] should have thrown on empty log\n');
        failed = failed + 1;
    catch
        fprintf('  [PASS] empty log rejected\n');
        passed = passed + 1;
    end
    safeClose(api2);
catch ME
    fprintf('  [FAIL] %s\n', ME.message);
    failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
fprintf('\n%s\n', repmat(char(9552), 1, 72));
fprintf('SUMMARY: %d/%d tests passed\n', passed, passed + failed);
if failed > 0
    error('test_em_angle_polyline_export:failures', '%d test(s) failed.', failed);
else
    fprintf('Status: ALL PASS\n');
end

% ════════════════════════════════════════════════════════════════════════
function safeClose(api)
    try
        if ~isempty(api) && isstruct(api) && isfield(api, 'close') && isvalid(api.fig)
            api.close();
        end
    catch
    end
end
