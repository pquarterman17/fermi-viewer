%TEST_EDS_COMPOSITE  Headless API tests for Fermion EDS composite mode.
%
%   Tests the multi-channel EDS false-color compositing feature:
%   enter/exit EDS mode, channel manipulation (color, visibility,
%   intensity, label), composite blending, and export.
%
%   Run:
%       run tests/test_eds_composite
%       runAllTests(Group="eds")
%
%   Requires: Fermion.m, +imaging/ package, +parser/ package
%   All test data is synthetic (created in temp directory).

fprintf('\n');
fprintf('╔══════════════════════════════════════════════════════════════╗\n');
fprintf('║      EDS Multi-Channel Composite — API Test Suite          ║\n');
fprintf('╚══════════════════════════════════════════════════════════════╝\n');

% ── Setup ───────────────────────────────────────────────────────────────
ROOT = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(ROOT);

tmpDir = fullfile(tempdir, sprintf('eds_test_%s', datestr(now, 'yyyymmdd_HHMMSS')));
mkdir(tmpDir);
cleanupDir = onCleanup(@() rmdir(tmpDir, 's'));

passed = 0;
failed = 0;

% ── Create 3 synthetic TIFF images (different patterns) ────────────────
H = 64; W = 64;

% Image 1: horizontal gradient (bright left)
img1 = uint16(repmat(linspace(65535, 0, W), H, 1));
f1 = fullfile(tmpDir, 'Fe_Ka.tif');
imwrite(img1, f1);

% Image 2: vertical gradient (bright top)
img2 = uint16(repmat(linspace(65535, 0, H)', 1, W));
f2 = fullfile(tmpDir, 'O_Ka.tif');
imwrite(img2, f2);

% Image 3: checkerboard pattern
[X, Y] = meshgrid(1:W, 1:H);
img3 = uint16((mod(floor(X/8) + floor(Y/8), 2)) * 65535);
f3 = fullfile(tmpDir, 'Si_Ka.tif');
imwrite(img3, f3);

% Helper: launch headless GUI
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
%  TEST 1: Enter and exit EDS mode
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 1: Enter and exit EDS mode ══\n');
try
    api = launchHeadless();
    cleanupApi = onCleanup(@() safeClose(api));

    api.loadImages({f1, f2, f3});
    assert(numel(api.getImages()) == 3, 'Expected 3 images loaded');

    % Enter EDS
    api.enterEDS();
    assert(api.isEDSMode(), 'Should be in EDS mode');

    % Channels auto-populated
    chs = api.getEDSChannels();
    assert(numel(chs) == 3, 'Expected 3 auto-populated channels');

    % Exit EDS
    api.exitEDS();
    assert(~api.isEDSMode(), 'Should not be in EDS mode after exit');

    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 2: Auto-populated channel defaults
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 2: Auto-populated channel defaults ══\n');
try
    api = launchHeadless();
    cleanupApi = onCleanup(@() safeClose(api));

    api.loadImages({f1, f2, f3});
    api.enterEDS();

    chs = api.getEDSChannels();

    % Check default colors cycle: red, green, blue
    assert(strcmp(chs{1}.color, 'red'),   'Channel 1 should be red');
    assert(strcmp(chs{2}.color, 'green'), 'Channel 2 should be green');
    assert(strcmp(chs{3}.color, 'blue'),  'Channel 3 should be blue');

    % All visible with intensity 1.0
    for ci = 1:3
        assert(chs{ci}.visible == true, sprintf('Channel %d should be visible', ci));
        assert(chs{ci}.intensity == 1.0, sprintf('Channel %d intensity should be 1.0', ci));
        assert(chs{ci}.imageIdx == ci, sprintf('Channel %d imageIdx should be %d', ci, ci));
    end

    % Labels derived from filenames
    assert(contains(chs{1}.label, 'Fe_Ka'), 'Channel 1 label should contain Fe_Ka');
    assert(contains(chs{2}.label, 'O_Ka'),  'Channel 2 label should contain O_Ka');

    api.exitEDS();
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 3: Modify channel color
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 3: Modify channel color ══\n');
try
    api = launchHeadless();
    cleanupApi = onCleanup(@() safeClose(api));

    api.loadImages({f1, f2});
    api.enterEDS();

    % Change channel 1 from red to cyan
    api.setEDSChannel(1, 'color', 'cyan');
    chs = api.getEDSChannels();
    assert(strcmp(chs{1}.color, 'cyan'), 'Channel 1 color should be cyan after change');

    % Composite should exist
    comp = api.getEDSComposite();
    assert(~isempty(comp), 'Composite should not be empty');
    assert(size(comp, 3) == 3, 'Composite should be RGB (H x W x 3)');

    api.exitEDS();
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 4: Toggle channel visibility
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 4: Toggle channel visibility ══\n');
try
    api = launchHeadless();
    cleanupApi = onCleanup(@() safeClose(api));

    api.loadImages({f1, f2});
    api.enterEDS();

    % Get composite with both channels visible
    compBoth = api.getEDSComposite();

    % Hide channel 2
    api.setEDSChannel(2, 'visible', false);
    compOne = api.getEDSComposite();

    % Composites should differ (channel 2 contribution removed)
    assert(~isequal(compBoth, compOne), ...
        'Composite should change when a channel is hidden');

    % With channel 2 hidden, green channel should be zero
    % (channel 2 was green by default)
    greenSlice = compOne(:,:,2);
    assert(max(greenSlice(:)) < 1e-6, ...
        'Green channel should be zero when green channel is hidden');

    api.exitEDS();
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 5: Adjust channel intensity
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 5: Adjust channel intensity ══\n');
try
    api = launchHeadless();
    cleanupApi = onCleanup(@() safeClose(api));

    api.loadImages({f1});
    api.enterEDS();

    % Full intensity composite
    compFull = api.getEDSComposite();

    % Half intensity
    api.setEDSChannel(1, 'intensity', 0.5);
    compHalf = api.getEDSComposite();

    % Red channel should be roughly halved
    redFull = compFull(:,:,1);
    redHalf = compHalf(:,:,1);
    mask = redFull > 0.1;  % avoid near-zero pixels
    if any(mask(:))
        ratio = mean(redHalf(mask)) / mean(redFull(mask));
        assert(abs(ratio - 0.5) < 0.05, ...
            sprintf('Intensity ratio should be ~0.5, got %.3f', ratio));
    end

    api.exitEDS();
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 6: Change channel label
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 6: Change channel label ══\n');
try
    api = launchHeadless();
    cleanupApi = onCleanup(@() safeClose(api));

    api.loadImages({f1});
    api.enterEDS();

    api.setEDSChannel(1, 'label', 'Iron K-alpha');
    chs = api.getEDSChannels();
    assert(strcmp(chs{1}.label, 'Iron K-alpha'), 'Label should be updated');

    api.exitEDS();
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 7: Export EDS composite
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 7: Export EDS composite ══\n');
try
    api = launchHeadless();
    cleanupApi = onCleanup(@() safeClose(api));

    api.loadImages({f1, f2, f3});
    api.enterEDS();

    % Export via the generic exportImage API (saves displayImg)
    outPath = fullfile(tmpDir, 'eds_export.png');
    api.exportImage(outPath);

    assert(isfile(outPath), 'Exported EDS composite file should exist');

    % Read back and verify it's RGB
    info = imfinfo(outPath);
    assert(strcmp(info.ColorType, 'truecolor') || info.BitDepth >= 24, ...
        'Exported image should be RGB');

    api.exitEDS();
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 8: Single image EDS mode
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 8: Single image EDS mode ══\n');
try
    api = launchHeadless();
    cleanupApi = onCleanup(@() safeClose(api));

    api.loadImages({f1});
    api.enterEDS();

    assert(api.isEDSMode(), 'Should enter EDS mode with single image');
    chs = api.getEDSChannels();
    assert(numel(chs) == 1, 'Should have 1 channel');

    comp = api.getEDSComposite();
    assert(~isempty(comp), 'Composite should exist with single channel');
    assert(size(comp, 3) == 3, 'Single-channel composite should still be RGB');

    api.exitEDS();
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 9: Re-entering EDS preserves channels
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 9: Re-entering EDS preserves channels ══\n');
try
    api = launchHeadless();
    cleanupApi = onCleanup(@() safeClose(api));

    api.loadImages({f1, f2});
    api.enterEDS();

    % Modify a channel
    api.setEDSChannel(1, 'color', 'magenta');
    api.setEDSChannel(1, 'intensity', 0.7);

    % Exit and re-enter
    api.exitEDS();
    api.enterEDS();

    chs = api.getEDSChannels();
    assert(strcmp(chs{1}.color, 'magenta'), 'Color should persist across EDS re-entry');
    assert(abs(chs{1}.intensity - 0.7) < 1e-6, 'Intensity should persist across EDS re-entry');

    api.exitEDS();
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 10: Invalid channel index errors
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 10: Invalid channel index errors ══\n');
try
    api = launchHeadless();
    cleanupApi = onCleanup(@() safeClose(api));

    api.loadImages({f1});
    api.enterEDS();

    errored = false;
    try
        api.setEDSChannel(99, 'color', 'red');
    catch
        errored = true;
    end
    assert(errored, 'Should error on out-of-range channel index');

    errored = false;
    try
        api.setEDSChannel(1, 'badfield', 'value');
    catch
        errored = true;
    end
    assert(errored, 'Should error on unknown field name');

    api.exitEDS();
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  SUMMARY
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n──────────────────────────────────────────────────────────────\n');
fprintf('EDS Composite Tests: %d passed, %d failed (of %d)\n', ...
    passed, failed, passed + failed);
fprintf('──────────────────────────────────────────────────────────────\n');

if failed > 0
    error('test_eds_composite:failures', '%d test(s) FAILED', failed);
end
