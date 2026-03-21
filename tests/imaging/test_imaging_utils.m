%TEST_IMAGING_UTILS  Unit tests for all +imaging utility functions.
%
%   Tests use purely synthetic data so no external files are required.
%   Each test prints a tick (pass) or cross (fail) with a brief description.
%
%   Run standalone:  cd tests; run test_imaging_utils
%   Run from root:   run tests/test_imaging_utils
%       runAllTests(Group="em")

clear; clc;
fprintf('\n═══ test_imaging_utils ═══\n');

% Ensure toolbox is on the path
thisDir = fileparts(mfilename('fullpath'));
rootDir = fileparts(fileparts(thisDir));
if ~contains(path, rootDir)
    addpath(rootDir);
end

ROOT = rootDir;

nPass = 0;
nFail = 0;

try  % outer guard — keeps runner from hanging on unexpected errors

% ════════════════════════════════════════════════════════════════════════
%  1. adjustContrast — known-value stretch
% ════════════════════════════════════════════════════════════════════════
try
    img = [0 100 200; 50 150 255];
    out = imaging.adjustContrast(img, Low=50, High=200);

    % (0-50)/(200-50) = -1/3 → clamped to 0
    assert(abs(out(1,1) - 0)   < 1e-9, 'Expected 0 at (1,1)');
    % (100-50)/150 = 1/3
    assert(abs(out(1,2) - 1/3) < 1e-9, 'Expected 1/3 at (1,2)');
    % (200-50)/150 = 1
    assert(abs(out(1,3) - 1)   < 1e-9, 'Expected 1 at (1,3)');
    % (50-50)/150 = 0
    assert(abs(out(2,1) - 0)   < 1e-9, 'Expected 0 at (2,1)');
    % (150-50)/150 = 2/3
    assert(abs(out(2,2) - 2/3) < 1e-9, 'Expected 2/3 at (2,2)');
    % (255-50)/150 > 1 → clamped to 1
    assert(abs(out(2,3) - 1)   < 1e-9, 'Expected 1 at (2,3) (clamped)');

    nPass = nPass + 1;
    fprintf('  ✔ Test 1a: adjustContrast — known-value stretch\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 1a: adjustContrast — known-value stretch: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  2. adjustContrast — Clamp=false allows values outside [0,1]
% ════════════════════════════════════════════════════════════════════════
try
    img = [0 100 200];
    out = imaging.adjustContrast(img, Low=50, High=150, Clamp=false);

    % (0-50)/100 = -0.5 — must NOT be clamped
    assert(abs(out(1) - (-0.5)) < 1e-9, 'Expected -0.5 with Clamp=false');
    % (200-50)/100 = 1.5 — must NOT be clamped
    assert(abs(out(3) - 1.5)    < 1e-9, 'Expected 1.5 with Clamp=false');

    nPass = nPass + 1;
    fprintf('  ✔ Test 1b: adjustContrast — Clamp=false\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 1b: adjustContrast — Clamp=false: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  3. adjustContrast — Low == High edge case → all zeros
% ════════════════════════════════════════════════════════════════════════
try
    img = magic(4);
    out = imaging.adjustContrast(img, Low=5, High=5);
    assert(all(out(:) == 0), 'Expected all-zero output when Low==High');

    nPass = nPass + 1;
    fprintf('  ✔ Test 1c: adjustContrast — Low==High edge case\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 1c: adjustContrast — Low==High edge case: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  4. applyGaussian — impulse response is symmetric and sums to ~1
% ════════════════════════════════════════════════════════════════════════
try
    N   = 51;
    img = zeros(N, N);
    img(ceil(N/2), ceil(N/2)) = 1;   % single bright pixel at centre

    out = imaging.applyGaussian(img, Sigma=2.0);

    % Energy should be approximately preserved (some lost at edges)
    assert(sum(out(:)) > 0.95, 'Energy loss > 5% (unexpected)');
    assert(sum(out(:)) <= 1.0 + 1e-9, 'Energy gain (impossible)');

    % Peak must be at the centre
    [~, peakIdx] = max(out(:));
    [pr, pc] = ind2sub(size(out), peakIdx);
    ctr = ceil(N/2);
    assert(pr == ctr && pc == ctr, 'Peak not at centre of impulse response');

    % Symmetry: output must be (approximately) symmetric about centre
    rowSlice = out(ctr, :);
    assert(max(abs(rowSlice - flip(rowSlice))) < 1e-12, ...
        'Row slice not symmetric');
    colSlice = out(:, ctr);
    assert(max(abs(colSlice - flip(colSlice))) < 1e-12, ...
        'Column slice not symmetric');

    nPass = nPass + 1;
    fprintf('  ✔ Test 2: applyGaussian — impulse response symmetry & energy\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 2: applyGaussian — impulse response: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  5. applyMedian — noise reduction on salt-and-pepper image
% ════════════════════════════════════════════════════════════════════════
try
    rng(42);
    base  = ones(32, 32) * 128;
    noisy = base;
    % Inject 10% salt-and-pepper noise
    noisy(rand(32,32) < 0.05) = 0;
    noisy(rand(32,32) < 0.05) = 255;

    out = imaging.applyMedian(double(noisy), WindowSize=3);

    % After filtering, most pixels should be close to 128
    residual = abs(out - 128);
    % Count pixels within 10 of the base value
    closeCount = sum(residual(:) < 10);
    assert(closeCount > 0.85 * numel(out), ...
        'Median filter did not suppress enough noise');

    nPass = nPass + 1;
    fprintf('  ✔ Test 3a: applyMedian — noise reduction\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 3a: applyMedian — noise reduction: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  6. applyMedian — uniform image is unchanged
% ════════════════════════════════════════════════════════════════════════
try
    img = ones(16, 16) * 42;
    out = imaging.applyMedian(img, WindowSize=3);
    assert(max(abs(out(:) - 42)) < 1e-9, 'Uniform image not preserved by median filter');

    nPass = nPass + 1;
    fprintf('  ✔ Test 3b: applyMedian — uniform image unchanged\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 3b: applyMedian — uniform image unchanged: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  7. computeFFT — constant image → single bright DC pixel at centre
% ════════════════════════════════════════════════════════════════════════
try
    N   = 64;
    img = ones(N, N) * 100;
    mag = imaging.computeFFT(img);

    % DC component is the maximum
    [~, peakIdx] = max(mag(:));
    [pr, pc] = ind2sub(size(mag), peakIdx);
    ctr = N/2 + 1;    % fftshift places DC here for even N
    assert(pr == ctr && pc == ctr, 'DC not at centre for constant image');

    % All other values should be log10(1+0) = 0
    mag(pr, pc) = 0;  % zero out DC
    assert(max(mag(:)) < 1e-9, 'Non-DC components non-zero for constant image');

    nPass = nPass + 1;
    fprintf('  ✔ Test 4a: computeFFT — constant image DC at centre\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 4a: computeFFT — constant image DC: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  8. computeFFT — two outputs (magnitude + phase)
% ════════════════════════════════════════════════════════════════════════
try
    img = rand(32, 32);
    [mag, ph] = imaging.computeFFT(img);

    assert(isequal(size(mag), [32 32]), 'Magnitude size mismatch');
    assert(isequal(size(ph),  [32 32]), 'Phase size mismatch');
    assert(all(mag(:) >= 0),            'Magnitude must be non-negative');
    assert(all(ph(:) >= -pi - 1e-9 & ph(:) <= pi + 1e-9), ...
        'Phase out of [-pi, pi]');

    nPass = nPass + 1;
    fprintf('  ✔ Test 4b: computeFFT — two-output form\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 4b: computeFFT — two-output form: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  9. lineProfile — horizontal line across gradient → linear ramp
% ════════════════════════════════════════════════════════════════════════
try
    W = 100;
    img = repmat((1:W), W, 1);   % each row is 1,2,...,100

    % Profile along row 50, columns 1 to 100
    [dist, intensity] = imaging.lineProfile(img, 1, 50, 100, 50);

    assert(numel(dist) > 1, 'Profile is empty');
    % First sample should be ~1, last should be ~100
    assert(abs(intensity(1)   - 1)   < 0.5, 'First intensity wrong');
    assert(abs(intensity(end) - 100) < 0.5, 'Last intensity wrong');
    % Profile should be monotonically increasing
    assert(all(diff(intensity) >= 0), 'Profile not monotone on gradient image');

    nPass = nPass + 1;
    fprintf('  ✔ Test 5a: lineProfile — horizontal on gradient\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 5a: lineProfile — horizontal on gradient: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  10. lineProfile — diagonal length equals expected pixel distance
% ════════════════════════════════════════════════════════════════════════
try
    img = ones(100, 100) * 50;
    X1=1; Y1=1; X2=41; Y2=31;   % expected pixel dist = sqrt(40^2+30^2)=50
    expectedDist = sqrt((X2-X1)^2 + (Y2-Y1)^2);

    [dist, ~] = imaging.lineProfile(img, X1, Y1, X2, Y2);

    assert(abs(dist(end) - expectedDist) < 0.5, ...
        sprintf('End distance %.3f differs from expected %.3f', dist(end), expectedDist));

    nPass = nPass + 1;
    fprintf('  ✔ Test 5b: lineProfile — diagonal distance correct\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 5b: lineProfile — diagonal distance: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  11. lineProfile — calibrated PixelSize scales the distance axis
% ════════════════════════════════════════════════════════════════════════
try
    img  = ones(64, 64);
    [dPx, ~] = imaging.lineProfile(img, 1, 32, 64, 32);              % pixel units
    [dNm, ~] = imaging.lineProfile(img, 1, 32, 64, 32, PixelSize=2.4, PixelUnit='nm');

    ratio = dNm(end) / dPx(end);
    assert(abs(ratio - 2.4) < 1e-9, 'PixelSize scaling incorrect');

    nPass = nPass + 1;
    fprintf('  ✔ Test 5c: lineProfile — calibrated distance scaling\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 5c: lineProfile — calibrated distance scaling: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  12. measureDistance — (0,0)→(3,4) = 5 px
% ════════════════════════════════════════════════════════════════════════
try
    [d, u] = imaging.measureDistance(0, 0, 3, 4);
    assert(abs(d - 5) < 1e-9, sprintf('Expected 5, got %.6f', d));
    assert(strcmp(u, 'px'), 'Expected unit px');

    nPass = nPass + 1;
    fprintf('  ✔ Test 6a: measureDistance — (0,0)→(3,4) = 5 px\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 6a: measureDistance — pixel: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  13. measureDistance — calibrated: 5 px × 2 nm/px = 10 nm
% ════════════════════════════════════════════════════════════════════════
try
    [d, u] = imaging.measureDistance(0, 0, 3, 4, PixelSize=2, PixelUnit='nm');
    assert(abs(d - 10) < 1e-9, sprintf('Expected 10, got %.6f', d));
    assert(strcmp(u, 'nm'), 'Expected unit nm');

    nPass = nPass + 1;
    fprintf('  ✔ Test 6b: measureDistance — calibrated 10 nm\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 6b: measureDistance — calibrated: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  14. addScaleBar — graphics objects created and have correct handles
% ════════════════════════════════════════════════════════════════════════
try
    fig = figure('Visible', 'off');
    ax  = axes(fig);
    img = rand(256, 256);
    imagesc(ax, img);

    hBar = imaging.addScaleBar(ax, 2.4, 'nm');

    assert(isstruct(hBar),                  'Return value must be a struct');
    assert(isfield(hBar, 'bar'),            'Missing field: bar');
    assert(isfield(hBar, 'label'),          'Missing field: label');
    assert(isvalid(hBar.bar),               'Bar handle invalid');
    assert(isvalid(hBar.label),             'Label handle invalid');
    assert(isa(hBar.bar,   'matlab.graphics.primitive.Rectangle'), ...
        'Bar must be a Rectangle');
    assert(isa(hBar.label, 'matlab.graphics.primitive.Text'), ...
        'Label must be a Text');

    % HandleVisibility must be 'off' (per GUI convention)
    assert(strcmp(hBar.bar.HandleVisibility,   'off'), 'Bar HandleVisibility not off');
    assert(strcmp(hBar.label.HandleVisibility, 'off'), 'Label HandleVisibility not off');

    close(fig);
    nPass = nPass + 1;
    fprintf('  ✔ Test 7: addScaleBar — graphics objects and HandleVisibility\n');
catch ME
    try; close(fig); catch; end
    nFail = nFail + 1;
    fprintf('  ✘ Test 7: addScaleBar: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  15. generateThumbnail — 512x256 → MaxSize=128 preserves aspect ratio
% ════════════════════════════════════════════════════════════════════════
try
    img   = uint16(rand(512, 256) * 65535);
    thumb = imaging.generateThumbnail(img, MaxSize=128);

    [H, W] = size(thumb);
    % Largest dim must be exactly MaxSize (or the rounded value)
    assert(H == 128, sprintf('Expected height 128, got %d', H));
    assert(W == 64,  sprintf('Expected width 64, got %d',   W));

    nPass = nPass + 1;
    fprintf('  ✔ Test 8a: generateThumbnail — 512x256 → 128x64\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 8a: generateThumbnail — size: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  16. generateThumbnail — output class matches input class
% ════════════════════════════════════════════════════════════════════════
try
    img8  = uint8(rand(400, 300) * 255);
    t8    = imaging.generateThumbnail(img8, MaxSize=128);
    assert(isa(t8, 'uint8'), 'Output class should match input (uint8)');

    imgF  = single(rand(400, 300));
    tF    = imaging.generateThumbnail(imgF, MaxSize=64);
    assert(isa(tF, 'single'), 'Output class should match input (single)');

    nPass = nPass + 1;
    fprintf('  ✔ Test 8b: generateThumbnail — class preservation\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 8b: generateThumbnail — class: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  17. generateThumbnail — already-small image returned unchanged
% ════════════════════════════════════════════════════════════════════════
try
    img   = uint8(magic(16));   % 16x16 — smaller than default MaxSize=256
    thumb = imaging.generateThumbnail(img);
    assert(isequal(size(thumb), [16 16]), 'Small image should not be resized');
    assert(isequal(thumb, img),           'Small image content changed');

    nPass = nPass + 1;
    fprintf('  ✔ Test 8c: generateThumbnail — already-small image unchanged\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 8c: generateThumbnail — small image: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════

catch fatalErr
    fprintf('  ✘ FATAL error in test harness: %s\n', fatalErr.message);
    nFail = nFail + 1;
end

% ── Summary ──────────────────────────────────────────────────────────────
fprintf('\n═══ Results: %d passed, %d failed ═══\n\n', nPass, nFail);

if nFail > 0
    error('test_imaging_utils:failures', '%d test(s) failed.', nFail);
end
