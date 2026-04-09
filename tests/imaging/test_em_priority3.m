%TEST_EM_PRIORITY3  Headless API tests for Fermion Priority-3 click-capture
%                   bypass wrappers: cropRect, zoomRect, resetZoom, fftMask.
%
%   Uses real DM3 + DM4 files from +test_datasets/Microscopy where possible
%   to exercise the pipeline on genuine microscopy data.
%
%   Run:
%       run tests/imaging/test_em_priority3
%       runAllTests(Group="emgui")

fprintf('\n');
fprintf('╔══════════════════════════════════════════════════════════════╗\n');
fprintf('║  Fermion Priority 3 — crop/zoom/fftMask headless API       ║\n');
fprintf('╚══════════════════════════════════════════════════════════════╝\n');

ROOT = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(ROOT);

passed = 0;
failed = 0;

dataDir = fullfile(ROOT, '+test_datasets', 'Microscopy');
dm3Path = fullfile(dataDir, 'EDW087-1.dm3');              % 512x512
dm4Path = fullfile(dataDir, 'openNCEM_nonSquare.dm4');    % 128x64

assert(isfile(dm3Path), 'missing DM3 test file');
assert(isfile(dm4Path), 'missing DM4 test file');

function api = launchHeadless()
    api = Fermion();
    api.fig.Visible = 'off';
    drawnow;
end

function safeClose(api)
    try
        if isvalid(api.fig), api.close(); end
    catch
    end
end

function px = getFiltered(api)
    s = api.getPixels();
    px = s.filtered;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 1: cropRect on a DM3 file preserves post-crop dimensions
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 1: cropRect on real DM3 ══\n');
try
    api = launchHeadless();
    cleanupApi = onCleanup(@() safeClose(api));
    api.loadImages({dm3Path});

    dims0 = api.getImageDimensions();
    assert(dims0(1) == 512 && dims0(2) == 512, ...
        sprintf('DM3 should load 512x512, got %dx%d', dims0(1), dims0(2)));

    % Crop to [100..300, 150..350] → expected 201 x 201
    api.cropRect(100, 150, 300, 350);
    dims1 = api.getImageDimensions();
    assert(dims1(1) == 201 && dims1(2) == 201, ...
        sprintf('post-crop should be 201x201, got %dx%d', dims1(1), dims1(2)));

    % Pixel buffer should now match the reported dimensions
    px = getFiltered(api);
    assert(isequal(size(px), [201 201]), 'getPixels dims mismatch after crop');

    fprintf('  PASS (512x512 → 201x201)\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 2: cropRect on a DM4 file, plus out-of-bounds clamping
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 2: cropRect clamping on real DM4 ══\n');
try
    api = launchHeadless();
    cleanupApi = onCleanup(@() safeClose(api));
    api.loadImages({dm4Path});

    dims0 = api.getImageDimensions();   % 128 wide, 64 tall (W x H? depends)
    H0 = dims0(1); W0 = dims0(2);
    fprintf('  DM4 loaded: %dx%d\n', H0, W0);

    % Crop beyond the edges — expect clamping to [1..W, 1..H]
    api.cropRect(-50, -50, W0 + 999, H0 + 999);
    dims1 = api.getImageDimensions();
    assert(dims1(1) == H0 && dims1(2) == W0, ...
        sprintf('clamped crop should preserve full size, got %dx%d', ...
            dims1(1), dims1(2)));

    % Now a real crop halving the width
    api.cropRect(10, 10, 60, 40);
    dims2 = api.getImageDimensions();
    assert(dims2(1) == 31 && dims2(2) == 51, ...
        sprintf('expected 31x51, got %dx%d', dims2(1), dims2(2)));

    fprintf('  PASS (clamped OOB + %dx%d)\n', dims2(1), dims2(2));
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 3: zoomRect and resetZoom change and restore axes limits
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 3: zoomRect + resetZoom ══\n');
try
    api = launchHeadless();
    cleanupApi = onCleanup(@() safeClose(api));
    api.loadImages({dm3Path});

    lim0 = api.getAxLimits();
    assert(abs(lim0.XLim(2) - 512.5) < 1, 'initial XLim should match image width');

    api.zoomRect(100, 100, 200, 200);
    lim1 = api.getAxLimits();
    assert(lim1.XLim(1) >= 99 && lim1.XLim(2) <= 201, ...
        sprintf('zoom XLim wrong: [%.1f %.1f]', lim1.XLim(1), lim1.XLim(2)));
    assert(lim1.YLim(1) >= 99 && lim1.YLim(2) <= 201, ...
        sprintf('zoom YLim wrong: [%.1f %.1f]', lim1.YLim(1), lim1.YLim(2)));

    api.resetZoom();
    lim2 = api.getAxLimits();
    assert(abs(lim2.XLim(2) - 512.5) < 1, 'resetZoom should restore XLim');
    assert(abs(lim2.YLim(2) - 512.5) < 1, 'resetZoom should restore YLim');

    fprintf('  PASS (zoom → reset restores limits)\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 4: fftMask input validation
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 4: fftMask input validation ══\n');
try
    api = launchHeadless();
    cleanupApi = onCleanup(@() safeClose(api));
    api.loadImages({dm4Path});

    px0 = getFiltered(api);

    % Wrong shape — should short-circuit without mutating pixels
    api.fftMask([]);
    api.fftMask([1 2]);   % 1x2, not N-by-3
    px1 = getFiltered(api);
    assert(isequal(size(px0), size(px1)), 'fftMask bad input changed size');
    assert(isequal(px0, px1), 'fftMask bad input should not mutate pixels');

    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 5: fftMask on a synthetic grating actually suppresses the spot
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 5: fftMask suppresses grating spot ══\n');
try
    % Create a synthetic TIFF with a strong horizontal grating and load
    % it via the file-loading path (so the image enters the app data
    % through the normal pipeline).
    tmpDir = fullfile(tempdir, sprintf('em_p3_%s', datestr(now, 'yyyymmdd_HHMMSS')));
    mkdir(tmpDir);
    cleanupDir = onCleanup(@() rmdir(tmpDir, 's'));

    N = 128;
    [XX, ~] = meshgrid(1:N, 1:N);
    period = 8;
    img = uint16(32000 + 20000 * sin(2*pi*XX/period));
    fImg = fullfile(tmpDir, 'grating.tif');
    imwrite(img, fImg);

    api = launchHeadless();
    cleanupApi = onCleanup(@() safeClose(api));
    api.loadImages({fImg});

    pxBefore = double(getFiltered(api));
    F0 = abs(fftshift(fft2(pxBefore)));

    % Grating with period 8 in X produces spots at kx = ±N/8 from center
    % in fftshift coords. Center is at floor(N/2)+1 = 65 for N=128.
    centerX = floor(N/2) + 1;
    centerY = floor(N/2) + 1;
    spotDx  = N / period;      % 16
    spotX   = centerX + spotDx;
    spotY   = centerY;

    % Confirm the spot is actually prominent before masking
    spotBefore = F0(spotY, spotX);
    dcBefore   = F0(centerY, centerX);
    assert(spotBefore > 0.05 * dcBefore, ...
        'synthetic grating spot not prominent enough to meaningfully test');

    % Mask it (radius 4). This mirrors to the -kx spot automatically.
    api.fftMask([spotX, spotY, 4]);

    pxAfter = double(getFiltered(api));
    F1 = abs(fftshift(fft2(pxAfter)));
    spotAfter = F1(spotY, spotX);

    % The masked spot should be dramatically reduced
    assert(spotAfter < 0.1 * spotBefore, ...
        sprintf('spot not suppressed: before=%.2g after=%.2g', ...
            spotBefore, spotAfter));

    fprintf('  PASS (spot %.2g → %.2g, %.0f%% suppression)\n', ...
        spotBefore, spotAfter, 100 * (1 - spotAfter / spotBefore));
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 6: fftMask smoke test on real DM4 file
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 6: fftMask smoke test on real DM4 ══\n');
try
    api = launchHeadless();
    cleanupApi = onCleanup(@() safeClose(api));
    api.loadImages({dm4Path});

    dims = api.getImageDimensions();
    H = dims(1); W = dims(2);
    cx = floor(W/2) + 1;
    cy = floor(H/2) + 1;

    % Mask a single off-DC spot. Just verify no crash and pixels stay real.
    api.fftMask([cx + 10, cy, 3]);
    px = getFiltered(api);
    assert(isreal(px) && all(isfinite(px(:))), 'fftMask output must be real & finite');
    assert(isequal(size(px), [H W]), 'fftMask should preserve image size');

    fprintf('  PASS (DM4 %dx%d pipeline clean)\n', H, W);
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
    error('test_em_priority3: %d test(s) failed', failed);
end
