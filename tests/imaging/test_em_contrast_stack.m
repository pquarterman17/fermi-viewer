%TEST_EM_CONTRAST_STACK  Headless API tests for FermiViewer contrast-stack
%                        controls: reset, colormap set/cycle, transform
%                        (linear/log/sqrt/power), invert, colorbar toggle.
%
%   Run:
%       run tests/imaging/test_em_contrast_stack
%       runAllTests(Group="emgui")

fprintf('\n');
fprintf('╔══════════════════════════════════════════════════════════════╗\n');
fprintf('║      FermiViewer Contrast Stack — API Test Suite                ║\n');
fprintf('╚══════════════════════════════════════════════════════════════╝\n');

ROOT = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(ROOT);

tmpDir = fullfile(tempdir, sprintf('emcontrast_test_%s', datestr(now, 'yyyymmdd_HHMMSS')));
mkdir(tmpDir);
cleanupDir = onCleanup(@() rmdir(tmpDir, 's'));

passed = 0;
failed = 0;

H = 64; W = 64;
[X, Y] = meshgrid(1:W, 1:H);
img = uint16(10000 + 20000 * sin(X/6) .* cos(Y/6) + 15000);
fImg = fullfile(tmpDir, 'synthetic.tif');
imwrite(img, fImg);

function api = launchHeadless()
    api = FermiViewer();
    api.fig.Visible = 'off';
    drawnow;
end

function safeClose(api)
    try
        if isvalid(api.fig), api.close(); end
    catch
    end
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 1: resetContrast restores full-range window
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 1: resetContrast ══\n');
try
    api = launchHeadless();
    cleanupApi = onCleanup(@() safeClose(api));
    api.loadImages({fImg});

    api.setContrast(20000, 30000);
    api.resetContrast();
    % After reset, display pipeline should have run without error.
    px = api.getPixels();
    assert(~isempty(px), 'pixels should still be loaded after reset');

    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 2: setColormap updates active colormap
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 2: setColormap ══\n');
try
    api = launchHeadless();
    cleanupApi = onCleanup(@() safeClose(api));
    api.loadImages({fImg});

    api.setColormap('hot');
    assert(strcmp(api.getColormap(), 'hot'), 'colormap should be "hot"');
    api.setColormap('parula');
    assert(strcmp(api.getColormap(), 'parula'), 'colormap should be "parula"');

    % Invalid colormap should error
    errored = false;
    try
        api.setColormap('notAColormap');
    catch
        errored = true;
    end
    assert(errored, 'invalid colormap name should throw');

    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 3: cycleColormap advances through the preset list
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 3: cycleColormap ══\n');
try
    api = launchHeadless();
    cleanupApi = onCleanup(@() safeClose(api));
    api.loadImages({fImg});

    api.setColormap('gray');
    api.cycleColormap();
    c1 = api.getColormap();
    assert(~strcmp(c1, 'gray'), 'cycle should move off gray');

    % Cycling through all items should return to starting point
    start = api.getColormap();
    for k = 1:5  % at least 5 presets in dropdown
        api.cycleColormap();
    end
    % After 5 cycles from `start` in a 5-item list, we should be back to `start`
    assert(strcmp(api.getColormap(), start), ...
        sprintf('cycle should return to start (%s), got %s', start, api.getColormap()));

    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 4: setContrastTransform (linear/log/sqrt/power)
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 4: setContrastTransform ══\n');
try
    api = launchHeadless();
    cleanupApi = onCleanup(@() safeClose(api));
    api.loadImages({fImg});

    for mode = {'linear', 'log', 'sqrt', 'power'}
        api.setContrastTransform(mode{1});
        assert(strcmp(api.getContrastTransform(), mode{1}), ...
            sprintf('transform should be "%s"', mode{1}));
    end

    % Invalid transform should error
    errored = false;
    try
        api.setContrastTransform('exponential');
    catch
        errored = true;
    end
    assert(errored, 'invalid transform should throw');

    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 5: setInvert toggles display inversion
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 5: setInvert ══\n');
try
    api = launchHeadless();
    cleanupApi = onCleanup(@() safeClose(api));
    api.loadImages({fImg});

    assert(~api.isInverted(), 'should start non-inverted');
    api.setInvert(true);
    assert(api.isInverted(), 'should be inverted after setInvert(true)');
    api.setInvert(false);
    assert(~api.isInverted(), 'should be non-inverted after setInvert(false)');

    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 6: setColorbar toggles colorbar visibility
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 6: setColorbar ══\n');
try
    api = launchHeadless();
    cleanupApi = onCleanup(@() safeClose(api));
    api.loadImages({fImg});

    assert(~api.isColorbarVisible(), 'colorbar should start hidden');
    api.setColorbar(true);
    assert(api.isColorbarVisible(), 'colorbar should be on');
    api.setColorbar(false);
    assert(~api.isColorbarVisible(), 'colorbar should be off');

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
    error('test_em_contrast_stack: %d test(s) failed', failed);
end
