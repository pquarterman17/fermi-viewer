%TEST_GRAINS  Unit tests for the grain-identification subsystem (Tier 1).
%
%   Covers the pure-MATLAB grain pipeline:
%     1. structureTensor recovers a known grating orientation + high coherence
%     2. structureTensor: low coherence on isotropic (random) texture
%     3. standardizeFeatures: zero-mean/unit-std + constant-column guard
%     4. kmeansLite: separates two well-separated blobs; deterministic by Seed
%     5. extractGrainFeatures: correct feature count + names, finite output
%     6. segmentAuto: two-orientation synthetic image → ~2 grains
%     7. grainStats: known 3-square label map → counts, boundaries, sizes
%     8. grainStats: calibration scales area/diameter/length correctly
%
%   Run:
%       run tests/imaging/test_grains
%       runAllTests(Group="grains")

fprintf('\n');
fprintf('╔══════════════════════════════════════════════════════════════╗\n');
fprintf('║  +imaging grain identification (structureTensor/ml/grains)  ║\n');
fprintf('╚══════════════════════════════════════════════════════════════╝\n');

ROOT = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(ROOT);

passed = 0;
failed = 0;

% ═══════════════════════════════════════════════════════════════════════
%  TEST 1: structureTensor recovers a known grating orientation
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 1: structureTensor orientation recovery ══\n');
try
    [Xc, Yc] = meshgrid(1:128, 1:128);
    for phiDeg = [0, 30, 60, 90, 135]
        phi = deg2rad(phiDeg);
        % Intensity varies ALONG direction phi → gradient points along phi →
        % structure-tensor orientation should recover phi (mod 180).
        wave = cos(2*pi/8 * (Xc*cos(phi) + Yc*sin(phi)));
        st   = imaging.structureTensor(wave, Sigma=4);

        % Sample orientation in the interior (avoid border conv artifacts).
        mid  = st.orientation(40:90, 40:90);
        % Compare mod pi via the doubled-angle representation.
        recovered = 0.5 * atan2(mean(sin(2*mid(:))), mean(cos(2*mid(:))));
        err = abs(angle(exp(1i*2*(recovered - phi)))) / 2;   % wrapped error
        err = min(err, abs(pi - err));                       % mod pi
        assert(err < deg2rad(5), ...
            sprintf('phi=%d°: recovered %.1f° (err %.1f°)', ...
            phiDeg, rad2deg(recovered), rad2deg(err)));

        cohMid = st.coherence(40:90, 40:90);
        assert(mean(cohMid(:)) > 0.7, ...
            sprintf('phi=%d°: coherence %.2f too low for a clean grating', ...
            phiDeg, mean(cohMid(:))));
    end
    fprintf('  PASS (orientation within 5° + coherence > 0.7 for all angles)\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 2: structureTensor — low coherence on isotropic texture
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 2: structureTensor isotropic → low coherence ══\n');
try
    s = RandStream('twister', 'Seed', 1);
    noise = rand(s, 128, 128);
    st = imaging.structureTensor(noise, Sigma=4);
    cohMid = st.coherence(20:108, 20:108);
    assert(mean(cohMid(:)) < 0.3, ...
        sprintf('isotropic coherence %.2f should be low', mean(cohMid(:))));
    fprintf('  PASS (mean coherence %.3f < 0.3)\n', mean(cohMid(:)));
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 3: standardizeFeatures — stats + constant-column guard
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 3: standardizeFeatures ══\n');
try
    s = RandStream('twister', 'Seed', 2);
    X = [randn(s, 200, 1)*10 + 5, ones(200, 1)*7, randn(s, 200, 1)*0.01];
    [Z, mu, sigma] = imaging.ml.standardizeFeatures(X);

    assert(all(abs(mean(Z, 1)) < 1e-9), 'columns should be ~zero-mean');
    % Columns 1 and 3 (non-constant) should have ~unit std.
    sd = std(Z, 0, 1);
    assert(abs(sd(1) - 1) < 1e-6 && abs(sd(3) - 1) < 1e-6, 'unit std');
    % Constant column → all zeros, no NaN/Inf.
    assert(all(Z(:, 2) == 0) && all(isfinite(Z(:))), 'constant column → 0, finite');

    % Re-apply learned transform to new data.
    Z2 = imaging.ml.standardizeFeatures(X(1:10, :), Mu=mu, Sigma=sigma);
    assert(isequal(size(Z2), [10, 3]) && all(isfinite(Z2(:))), 'reapply ok');

    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 4: kmeansLite — separates two blobs; deterministic by Seed
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 4: kmeansLite separation + determinism ══\n');
try
    s = RandStream('twister', 'Seed', 3);
    A = randn(s, 100, 2) + [ 0  0];
    B = randn(s, 100, 2) + [10 10];
    X = [A; B];

    [lab1, ~, info1] = imaging.ml.kmeansLite(X, 2, Seed=7, Replicates=3);
    [lab2, ~, ~]     = imaging.ml.kmeansLite(X, 2, Seed=7, Replicates=3);

    assert(isequal(lab1, lab2), 'same Seed must give identical labels');

    % Each true group should be (almost) pure in one cluster.
    aMode = mode(lab1(1:100));   bMode = mode(lab1(101:200));
    assert(aMode ~= bMode, 'the two blobs should land in different clusters');
    purity = (sum(lab1(1:100) == aMode) + sum(lab1(101:200) == bMode)) / 200;
    assert(purity > 0.98, sprintf('cluster purity %.2f too low', purity));
    assert(info1.inertia > 0 && isfinite(info1.inertia), 'inertia finite');

    fprintf('  PASS (purity %.2f, deterministic)\n', purity);
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 5: extractGrainFeatures — feature count, names, finite
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 5: extractGrainFeatures shape ══\n');
try
    img = peaks(64); img = img - min(img(:));
    scales = [2 4 8];
    [feats, names] = imaging.grains.extractGrainFeatures(img, Scales=scales);

    expectedF = 2 + 5*numel(scales);
    assert(size(feats, 3) == expectedF, ...
        sprintf('F=%d, expected %d', size(feats, 3), expectedF));
    assert(numel(names) == expectedF, 'names length matches F');
    assert(isequal(size(feats(:,:,1)), size(img)), 'spatial dims preserved');
    assert(all(isfinite(feats(:))), 'no NaN/Inf in features');
    assert(any(strcmp(names, 'coh_4')) && any(strcmp(names, 'intensity')), ...
        'expected feature names present');

    fprintf('  PASS (F=%d, names ok)\n', expectedF);
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 6: segmentAuto — two-orientation image → ~2 grains
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 6: segmentAuto on two-orientation synthetic ══\n');
try
    [Xc, Yc] = meshgrid(1:128, 1:128);
    f = 2*pi/8;
    left  = cos(f * Xc);                 % vertical stripes (orientation 0°)
    right = cos(f * Yc);                 % horizontal stripes (orientation 90°)
    img = left;
    img(:, 65:end) = right(:, 65:end);   % left half vs right half

    [labels, info] = imaging.grains.segmentAuto(img, ...
        K=2, Scales=[3 6], MinArea=200, Seed=0, Replicates=3);

    assert(info.numGrains >= 2, ...
        sprintf('expected >=2 grains, got %d', info.numGrains));
    % The two dominant grains should split left/right near the seam.
    big = labels(:, [20 110]);  % a column deep in each half
    leftLabel  = mode(labels(40:90, 20));
    rightLabel = mode(labels(40:90, 110));
    assert(leftLabel ~= 0 && rightLabel ~= 0 && leftLabel ~= rightLabel, ...
        'left and right halves should be different grains');

    fprintf('  PASS (numGrains=%d, halves separated)\n', info.numGrains);
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 7: grainStats — known 3-square label map
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 7: grainStats counts + boundaries on known map ══\n');
try
    % 90x30 map: three 30x30 grains side by side, labels 1,2,3 touching.
    L = zeros(30, 90);
    L(:,  1:30) = 1;
    L(:, 31:60) = 2;
    L(:, 61:90) = 3;
    img = double(L) * 10;   % arbitrary intensity

    r = imaging.grains.grainStats(L, img, MinArea=1);

    assert(r.numGrains == 3, sprintf('expected 3 grains, got %d', r.numGrains));
    assert(numel(r.areaPx) == 3 && all(r.areaPx == 900), 'each grain 900 px');
    % Two internal interfaces (1|2 and 2|3), each 30 px tall, both sides
    % marked → ~ 2 interfaces * 30 rows * 2 sides = 120 boundary px.
    assert(r.boundaryLengthPx == 120, ...
        sprintf('boundary px %d, expected 120', r.boundaryLengthPx));
    assert(r.numBoundarySegments == 2, ...
        sprintf('expected 2 boundary segments, got %d', r.numBoundarySegments));
    % Boundary must not touch image edges (grains span full height).
    assert(~any(r.boundaryMask(:, 1)) && ~any(r.boundaryMask(:, end)), ...
        'no wrap-around boundary at borders');

    fprintf('  PASS (3 grains, 2 boundaries, 120 px)\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 8: grainStats — calibration scales area/diameter/length
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 8: grainStats calibration ══\n');
try
    L = zeros(30, 90);
    L(:,  1:30) = 1; L(:, 31:60) = 2; L(:, 61:90) = 3;
    img = double(L) * 10;
    ps = 0.5;   % nm/px

    r = imaging.grains.grainStats(L, img, PixelSize=ps, PixelUnit="nm");
    assert(all(abs(r.areaCalibrated - 900*ps^2) < 1e-9), 'area calib');
    assert(all(abs(r.diameterCalibrated - sqrt(4*900/pi)*ps) < 1e-9), 'diam calib');
    assert(abs(r.boundaryLengthCalibrated - r.boundaryLengthPx*ps) < 1e-9, ...
        'boundary length calib');
    assert(r.pixelUnit == "nm", 'unit propagated');

    fprintf('  PASS (area/diameter/length scale by PixelSize)\n');
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
    error('test_grains: %d test(s) failed', failed);
end
