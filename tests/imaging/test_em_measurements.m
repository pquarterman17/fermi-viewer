%TEST_EM_MEASUREMENTS  Headless API tests for Fermion interactive measurement
%                      and ROI tools (distance, d-spacing, ellipse/polygon
%                      ROI, rectangle annotation).
%
%   These tests drive the nested execute* functions via the new api.measure*
%   / api.roi* wrappers, bypassing the two-click capture flow so they can
%   run headless.
%
%   Run:
%       run tests/imaging/test_em_measurements
%       runAllTests(Group="emgui")
%
%   All test data is synthetic.

fprintf('\n');
fprintf('╔══════════════════════════════════════════════════════════════╗\n');
fprintf('║      Fermion Measurements / ROI — API Test Suite            ║\n');
fprintf('╚══════════════════════════════════════════════════════════════╝\n');

ROOT = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(ROOT);

tmpDir = fullfile(tempdir, sprintf('emmeas_test_%s', datestr(now, 'yyyymmdd_HHMMSS')));
mkdir(tmpDir);
cleanupDir = onCleanup(@() rmdir(tmpDir, 's'));

passed = 0;
failed = 0;

% ── Synthetic 128x128 test image ───────────────────────────────────────
H = 128; W = 128;
[X, Y] = meshgrid(1:W, 1:H);
img = uint16(30000 + 10000 * sin(X/8) .* cos(Y/8));
fImg = fullfile(tmpDir, 'synthetic.tif');
imwrite(img, fImg);

function api = launchHeadless()
    api = Fermion();
    api.fig.Visible = 'off';
    drawnow;
end

function safeClose(api)
    try
        if isvalid(api.fig)
            api.close();
        end
    catch
    end
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 1: api.measureDistance appends to overlays.measurements
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 1: measureDistance adds measurement overlay ══\n');
try
    api = launchHeadless();
    cleanupApi = onCleanup(@() safeClose(api));
    api.loadImages({fImg});

    ov0 = api.getOverlays();
    n0  = numel(ov0.measurements);

    api.measureDistance(10, 20, 100, 80);

    ov1 = api.getOverlays();
    assert(numel(ov1.measurements) == n0 + 1, ...
        'measureDistance should add 1 entry to overlays.measurements');

    m = ov1.measurements{end};
    assert(strcmp(m.type, 'distance'), 'meas.type should be "distance"');
    assert(isfield(m, 'distance') && ~isnan(m.distance) && m.distance > 0, ...
        'meas.distance should be populated and positive');

    % Expected uncalibrated distance ≈ sqrt(90^2 + 60^2) ≈ 108.17
    expected = sqrt(90^2 + 60^2);
    assert(abs(m.distance - expected) < 0.5, ...
        sprintf('distance should be ~%.2f, got %.2f', expected, m.distance));

    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 2: getMeasStats aggregates distances
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 2: getMeasStats reflects multiple distances ══\n');
try
    api = launchHeadless();
    cleanupApi = onCleanup(@() safeClose(api));
    api.loadImages({fImg});

    api.measureDistance(0, 0, 30, 40);    % 50
    api.measureDistance(0, 0, 60, 80);    % 100
    api.measureDistance(10, 10, 13, 14);  % 5

    stats = api.getMeasStats();
    assert(stats.count == 3, sprintf('expected 3 distances, got %d', stats.count));
    assert(abs(stats.min - 5)   < 0.5, 'min should be ~5');
    assert(abs(stats.max - 100) < 0.5, 'max should be ~100');

    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 3: api.roiEllipse logs a circleROI measurement
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 3: roiEllipse logs circleROI stats ══\n');
try
    api = launchHeadless();
    cleanupApi = onCleanup(@() safeClose(api));
    api.loadImages({fImg});

    log0 = api.getMeasurementLog();
    n0 = numel(log0);

    api.roiEllipse(64, 64, 84, 64);  % center (64,64), radius 20

    log1 = api.getMeasurementLog();
    assert(numel(log1) == n0 + 1, 'roiEllipse should append 1 log entry');
    entry = log1{end};
    assert(strcmp(entry.type, 'circleROI'), 'log entry type should be circleROI');
    assert(abs(entry.radius - 20) < 0.01, 'radius should be 20');
    assert(entry.area > 0 && isfinite(entry.mean), 'area and mean should be populated');

    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 4: api.roiPolygon logs a polygonROI measurement
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 4: roiPolygon logs polygonROI stats ══\n');
try
    api = launchHeadless();
    cleanupApi = onCleanup(@() safeClose(api));
    api.loadImages({fImg});

    pts = [20 20; 80 20; 80 80; 20 80];  % 60x60 square
    api.roiPolygon(pts);

    log = api.getMeasurementLog();
    assert(~isempty(log), 'roiPolygon should create a log entry');
    entry = log{end};
    assert(strcmp(entry.type, 'polygonROI'), 'log entry type should be polygonROI');
    assert(isequal(size(entry.vertices), [4 2]), 'vertices should be 4x2');
    % 60x60 square → ~3721 pixels (inpolygon inclusive on edges)
    assert(entry.area > 3000 && entry.area < 4000, ...
        sprintf('area should be ~3600 px, got %d', entry.area));

    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 5: api.annotRect adds a rectangle annotation overlay
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 5: annotRect adds rectangle annotation ══\n');
try
    api = launchHeadless();
    cleanupApi = onCleanup(@() safeClose(api));
    api.loadImages({fImg});

    ov0 = api.getOverlays();
    n0 = numel(ov0.textAnnotations);

    api.annotRect(10, 10, 50, 40);

    ov1 = api.getOverlays();
    assert(numel(ov1.textAnnotations) == n0 + 1, ...
        'annotRect should add 1 textAnnotations entry');
    annot = ov1.textAnnotations{end};
    assert(strcmp(annot.type, 'rectangle'), 'annotation type should be rectangle');

    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 6: api.measureDSpacing runs without error on a 2D image
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 6: measureDSpacing runs headless ══\n');
try
    api = launchHeadless();
    cleanupApi = onCleanup(@() safeClose(api));
    api.loadImages({fImg});

    % Without pixel calibration, executeDSpacing short-circuits with a
    % status message — it should not throw.
    api.measureDSpacing(40, 64, 88, 64);

    % With calibration, it actually draws spot circles and updates status.
    api.setPixelSize(0.1, 'nm');
    api.measureDSpacing(40, 64, 88, 64);

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
    error('test_em_measurements: %d test(s) failed', failed);
end
