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
    % Two internal interfaces (1|2 and 2|3), each 30 px tall. Each edge
    % counted ONCE → 2 interfaces * 30 rows = 60 px network length.
    % (Was pinned at 120 when the both-sides mask was summed — the ~2x
    % double-count fixed here, matching the Python port's correction.)
    assert(r.boundaryLengthPx == 60, ...
        sprintf('boundary px %d, expected 60', r.boundaryLengthPx));
    assert(r.numBoundarySegments == 2, ...
        sprintf('expected 2 boundary segments, got %d', r.numBoundarySegments));
    % Boundary must not touch image edges (grains span full height).
    assert(~any(r.boundaryMask(:, 1)) && ~any(r.boundaryMask(:, end)), ...
        'no wrap-around boundary at borders');

    fprintf('  PASS (3 grains, 2 boundaries, 60 px network)\n');
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

% ═══════════════════════════════════════════════════════════════════════
%  TEST 9: softmaxTrain/Predict — separable classes, deterministic, probs
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 9: softmax classifier ══\n');
try
    s = RandStream('twister', 'Seed', 5);
    A = randn(s, 150, 2) + [0 0];
    B = randn(s, 150, 2) + [6 0];
    X = [A; B];
    y = [ones(150, 1); 2*ones(150, 1)];

    m  = imaging.ml.softmaxTrain(X, y, MaxIter=500);
    m2 = imaging.ml.softmaxTrain(X, y, MaxIter=500);
    assert(isequal(m.W, m2.W), 'training must be deterministic');

    [pred, probs] = imaging.ml.softmaxPredict(m, X);
    acc = mean(pred == y);
    assert(acc > 0.95, sprintf('accuracy %.2f too low', acc));
    assert(isequal(size(pred), [300 1]), 'labels must be a column vector');
    assert(all(abs(sum(probs, 2) - 1) < 1e-9), 'probabilities must sum to 1');
    assert(isequal(sort(unique(pred)), [1; 2]), 'predicted labels in original space');

    fprintf('  PASS (accuracy %.2f, deterministic, probs normalized)\n', acc);
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 10: trainFromScribbles → segmentTrained recovers a 2-class split
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 10: scribble training → segmentTrained ══\n');
try
    [Xc, Yc] = meshgrid(1:128, 1:128);
    f = 2*pi/8;
    img = cos(f * Xc);                   % vertical stripes (class 1)
    img(:, 65:end) = cos(f * Yc(:, 65:end));  % horizontal stripes (class 2)

    % Sparse scribbles: a few pixels in each half.
    labelMask = zeros(128, 128);
    labelMask(30:35, 20:25) = 1;         % left half
    labelMask(90:95, 100:105) = 2;       % right half

    model = imaging.grains.trainFromScribbles(img, labelMask, Scales=[3 6]);
    assert(isfield(model, 'scales'), 'model must carry feature config');

    [labels, info] = imaging.grains.segmentTrained(img, model, MinArea=200);
    assert(info.numGrains >= 2, sprintf('expected >=2 grains, got %d', info.numGrains));

    % Pixels deep in each half should classify to different classes.
    cLeft  = mode(info.classMap(40:90, 20));
    cRight = mode(info.classMap(40:90, 110));
    assert(cLeft ~= cRight, 'left/right halves must get different classes');
    assert(all(info.maxProb(:) >= 0 & info.maxProb(:) <= 1), 'maxProb in [0,1]');

    fprintf('  PASS (numGrains=%d, halves classified differently)\n', info.numGrains);
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 11: train on image A, apply to image B (generalization)
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 11: train on A, apply to B ══\n');
try
    [Xc, Yc] = meshgrid(1:96, 1:96);
    f = 2*pi/8;
    % Image A: top half vertical, bottom half horizontal.
    A = cos(f * Xc); A(49:end, :) = cos(f * Yc(49:end, :));
    labelMask = zeros(96, 96);
    labelMask(10:15, 40:45) = 1;   % top (vertical)
    labelMask(80:85, 40:45) = 2;   % bottom (horizontal)
    model = imaging.grains.trainFromScribbles(A, labelMask, Scales=[3 6]);

    % Image B: same two textures but swapped left/right (different layout).
    B = cos(f * Yc); B(:, 49:end) = cos(f * Xc(:, 49:end));
    [~, infoB] = imaging.grains.segmentTrained(B, model, MinArea=150);

    % Left of B is horizontal (class 2), right is vertical (class 1).
    cBleft  = mode(infoB.classMap(40:60, 20));
    cBright = mode(infoB.classMap(40:60, 80));
    assert(cBleft ~= cBright, 'B halves must classify differently with A-trained model');
    assert(infoB.numGrains >= 2, 'expected >=2 grains in B');

    fprintf('  PASS (A-trained model separates B''s halves, %d grains)\n', infoB.numGrains);
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 12: BoundaryClass excluded from grain labeling
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 12: BoundaryClass exclusion ══\n');
try
    [Xc, Yc] = meshgrid(1:128, 1:128);
    f = 2*pi/8;
    img = cos(f * Xc);
    img(:, 65:end) = cos(f * Yc(:, 65:end));
    % Add a noisy vertical seam to act as a "boundary" texture.
    s = RandStream('twister', 'Seed', 9);
    img(:, 62:67) = randn(s, 128, 6);

    labelMask = zeros(128, 128);
    labelMask(30:35, 20:25)   = 1;    % left grain
    labelMask(90:95, 100:105) = 2;    % right grain
    labelMask(60:69, 62:67)   = 3;    % boundary scribble (class 3)

    model = imaging.grains.trainFromScribbles(img, labelMask, Scales=[3 6]);

    [~, infoAll]  = imaging.grains.segmentTrained(img, model, MinArea=100);
    [~, infoExcl] = imaging.grains.segmentTrained(img, model, ...
        BoundaryClass=3, MinArea=100);

    % Excluding the boundary class should not produce MORE grains than
    % including it, and class-3 regions must be absent from the grain map.
    assert(infoExcl.numGrains <= infoAll.numGrains, ...
        'excluding boundary class should not increase grain count');
    assert(any(infoAll.classMap(:) == 3), 'class 3 should be predicted somewhere');

    fprintf('  PASS (boundary class %d excluded: %d vs %d grains)\n', ...
        3, infoExcl.numGrains, infoAll.numGrains);
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 13: labelOverlay — shape, range, distinct colors, boundary draw
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 13: labelOverlay ══\n');
try
    L = zeros(30, 90);
    L(:, 1:30) = 1; L(:, 31:60) = 2; L(:, 61:90) = 3;
    img = double(L) * 10;
    r = imaging.grains.grainStats(L, img);

    rgb = imaging.grains.labelOverlay(L, Boundary=r.boundaryMask);
    assert(isequal(size(rgb), [30 90 3]), 'overlay must be HxWx3');
    assert(all(rgb(:) >= 0 & rgb(:) <= 1), 'overlay values in [0,1]');

    % Each grain region should be a single solid colour, and the three
    % grains should have different colours.
    c1 = squeeze(rgb(5, 10, :));  c2 = squeeze(rgb(5, 45, :));  c3 = squeeze(rgb(5, 75, :));
    assert(~isequal(c1, c2) && ~isequal(c2, c3) && ~isequal(c1, c3), ...
        'three grains must get three distinct colours');

    % Boundary pixels drawn black (default).
    bcols = rgb(repmat(r.boundaryMask, 1, 1, 3));
    assert(all(bcols == 0), 'boundary pixels should be black');

    % Blend over a base image preserves size.
    rgb2 = imaging.grains.labelOverlay(L, BaseImage=img, Alpha=0.5);
    assert(isequal(size(rgb2), [30 90 3]) && all(isfinite(rgb2(:))), 'blend ok');

    fprintf('  PASS (HxWx3, distinct colours, boundary drawn)\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 14: exportGrainCSV — rows, calibrated columns, file round-trip
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 14: exportGrainCSV ══\n');
try
    L = zeros(30, 90);
    L(:, 1:30) = 1; L(:, 31:60) = 2; L(:, 61:90) = 3;
    img = double(L) * 10;
    r = imaging.grains.grainStats(L, img, PixelSize=0.5, PixelUnit="nm");

    [data, header] = imaging.grains.exportGrainCSV(r);
    assert(size(data, 1) == 3, 'one row per grain');
    assert(any(strcmp(header, 'area_px')), 'area_px column present');
    assert(any(strcmp(header, 'area_nm')), 'calibrated area column with unit');
    % area_px column should be 900 for each grain.
    aCol = data(:, strcmp(header, 'area_px'));
    assert(all(aCol == 900), 'area_px must be 900');
    aCal = data(:, strcmp(header, 'area_nm'));
    assert(all(abs(aCal - 900*0.25) < 1e-9), 'calibrated area = 900 * 0.5^2');

    % Write + read back: header line + 3 data lines = 4 lines.
    tmp = [tempname '.csv'];
    imaging.grains.exportGrainCSV(r, Filename=tmp);
    txt = readlines(tmp);
    txt = txt(strlength(txt) > 0);
    assert(numel(txt) == 4, sprintf('expected 4 lines, got %d', numel(txt)));
    assert(startsWith(txt(1), 'id,'), 'first line is the header');
    delete(tmp);

    fprintf('  PASS (3 rows, calibrated cols, file round-trip)\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 15: randomForest — accuracy, determinism, nonlinear (XOR) separability
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 15: random forest ══\n');
try
    % XOR-like classes: linearly inseparable, where a forest beats softmax.
    s = RandStream('twister', 'Seed', 11);
    n = 100;
    q1 = randn(s, n, 2)*0.4 + [ 1  1];
    q2 = randn(s, n, 2)*0.4 + [-1 -1];   % class 1 = quadrants (+,+),(-,-)
    q3 = randn(s, n, 2)*0.4 + [ 1 -1];
    q4 = randn(s, n, 2)*0.4 + [-1  1];   % class 2 = quadrants (+,-),(-,+)
    X = [q1; q2; q3; q4];
    y = [ones(2*n,1); 2*ones(2*n,1)];

    m1 = imaging.ml.randomForestTrain(X, y, NumTrees=40, Seed=3);
    m2 = imaging.ml.randomForestTrain(X, y, NumTrees=40, Seed=3);
    [pred, probs] = imaging.ml.randomForestPredict(m1, X);
    [pred2, ~]    = imaging.ml.randomForestPredict(m2, X);

    assert(isequal(pred, pred2), 'same Seed must give identical predictions');
    acc = mean(pred == y);
    assert(acc > 0.9, sprintf('forest accuracy %.2f too low on XOR', acc));
    assert(isequal(size(pred), [4*n 1]), 'labels column vector');
    assert(all(abs(sum(probs,2) - 1) < 1e-9), 'vote probabilities sum to 1');
    assert(m1.type == "forest", 'model tagged as forest');

    fprintf('  PASS (XOR accuracy %.2f, deterministic)\n', acc);
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 16: trainFromScribbles Classifier="forest" → segmentTrained
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 16: forest-mode scribble training ══\n');
try
    [Xc, Yc] = meshgrid(1:128, 1:128);
    f = 2*pi/8;
    img = cos(f * Xc);
    img(:, 65:end) = cos(f * Yc(:, 65:end));

    labelMask = zeros(128, 128);
    labelMask(30:35, 20:25)   = 1;
    labelMask(90:95, 100:105) = 2;

    model = imaging.grains.trainFromScribbles(img, labelMask, ...
        Scales=[3 6], Classifier="forest", NumTrees=25, Seed=0);
    assert(model.classifierType == "forest", 'classifierType propagated');

    [labels, info] = imaging.grains.segmentTrained(img, model, MinArea=200);
    assert(info.numGrains >= 2, sprintf('forest segmentTrained >=2 grains, got %d', info.numGrains));
    cLeft  = mode(info.classMap(40:90, 20));
    cRight = mode(info.classMap(40:90, 110));
    assert(cLeft ~= cRight, 'left/right halves differ under forest classifier');

    fprintf('  PASS (forest: %d grains, halves separated)\n', info.numGrains);
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 17: SLIC — full coverage, ~requested count, deterministic
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 17: SLIC superpixels ══\n');
try
    img = peaks(120); img = img - min(img(:));
    L1 = imaging.slic(img, NumSuperpixels=100, Compactness=10);
    L2 = imaging.slic(img, NumSuperpixels=100, Compactness=10);

    assert(isequal(L1, L2), 'SLIC must be deterministic (grid seeding)');
    assert(isequal(size(L1), size(img)), 'label map matches image size');
    assert(all(L1(:) >= 1), 'every pixel labelled (no zeros)');
    M = max(L1(:));
    assert(M >= 50 && M <= 160, sprintf('superpixel count %d near target 100', M));
    assert(numel(unique(L1(:))) == M, 'labels are contiguous 1..M');

    fprintf('  PASS (%d superpixels, full coverage, deterministic)\n', M);
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 18: segmentAuto Superpixels path still finds the 2 grains
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 18: segmentAuto with Superpixels ══\n');
try
    % Two smooth intensity regions (the regime superpixels are designed for;
    % high-frequency gratings alias under superpixel averaging).
    s = RandStream('twister', 'Seed', 21);
    img = 0.3 * ones(128, 128);
    img(:, 65:end) = 0.7;
    img = img + 0.02 * randn(s, 128, 128);

    [labels, info] = imaging.grains.segmentAuto(img, ...
        K=2, Scales=[3 6], MinArea=200, Superpixels=true, NumSuperpixels=200);

    assert(info.numGrains >= 2, ...
        sprintf('superpixel path expected >=2 grains, got %d', info.numGrains));
    leftLabel  = mode(labels(40:90, 20));
    rightLabel = mode(labels(40:90, 110));
    assert(leftLabel ~= 0 && rightLabel ~= 0 && leftLabel ~= rightLabel, ...
        'the two intensity regions should be different grains via superpixels');

    fprintf('  PASS (superpixel path: %d grains, regions separated)\n', info.numGrains);
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
