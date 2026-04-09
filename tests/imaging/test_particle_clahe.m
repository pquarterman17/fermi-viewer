%TEST_PARTICLE_CLAHE  Unit + smoke tests for three new +imaging/ features:
%                     clahe, connectedComponents, particleAnalysis.
%
%   Covers:
%     1. CLAHE on synthetic gradient, bounded output, shape preservation
%     2. CLAHE on real DM3 + DM4 microscopy files — smoke test
%     3. connectedComponents on known synthetic masks (4 vs 8)
%     4. particleAnalysis on synthetic blobs — area/centroid/diameter checks
%     5. particleAnalysis on a real DM3 file (dark-particle polarity)
%     6. particleAnalysis on a real DM4 file (smoke test)
%
%   Run:
%       run tests/imaging/test_particle_clahe
%       runAllTests(Group="em")

fprintf('\n');
fprintf('╔══════════════════════════════════════════════════════════════╗\n');
fprintf('║  +imaging/ CLAHE + connectedComponents + particleAnalysis  ║\n');
fprintf('╚══════════════════════════════════════════════════════════════╝\n');

ROOT = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(ROOT);

passed = 0;
failed = 0;

dataDir = fullfile(ROOT, '+test_datasets', 'Microscopy');

% ═══════════════════════════════════════════════════════════════════════
%  TEST 1: CLAHE on synthetic ramp — output in [0,1], shape preserved
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 1: CLAHE on synthetic ramp ══\n');
try
    H = 64; W = 96;
    ramp = repmat(linspace(0, 1, W), H, 1);
    out = imaging.clahe(ramp, TileSize=[4 4], ClipLimit=0.01);

    assert(isequal(size(out), [H, W]), 'CLAHE should preserve size');
    assert(all(out(:) >= 0) && all(out(:) <= 1), 'output must be in [0,1]');
    % On a monotonic ramp, the equalized image should also be roughly
    % monotonic column-wise (allow small tile-boundary wiggle).
    colMean = mean(out, 1);
    assert(colMean(end) > colMean(1), 'ramp polarity should be preserved');

    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 2: CLAHE edge cases — constant image, integer dtype
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 2: CLAHE edge cases ══\n');
try
    flat = uint16(5000 * ones(32, 32));
    out = imaging.clahe(flat);
    assert(isequal(size(out), [32 32]), 'constant: size preserved');
    assert(all(out(:) == 0), 'constant image should map to zeros');

    % uint8 input
    img8 = uint8(randi([30 200], 48, 48));
    out8 = imaging.clahe(img8, TileSize=[4 4]);
    assert(isa(out8, 'double') && max(out8(:)) <= 1, 'uint8: bounded double output');

    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 3: CLAHE smoke test on real DM3 + DM4 files
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 3: CLAHE on real DM3 + DM4 files ══\n');
try
    dm3 = fullfile(dataDir, 'EDW087-1.dm3');
    dm4 = fullfile(dataDir, 'openNCEM_nonSquare.dm4');
    assert(isfile(dm3), 'missing DM3 test file');
    assert(isfile(dm4), 'missing DM4 test file');

    d3 = parser.importDM3(dm3);
    img3 = d3.metadata.parserSpecific.imageData.pixels;
    eq3 = imaging.clahe(img3, TileSize=[8 8], ClipLimit=0.01);
    assert(isequal(size(eq3), size(img3)), 'DM3: size preserved');
    assert(all(eq3(:) >= 0) && all(eq3(:) <= 1), 'DM3: bounded');
    fprintf('  DM3 %s: %dx%d → CLAHE OK\n', 'EDW087-1', size(img3,2), size(img3,1));

    d4 = parser.importDM4(dm4);
    img4 = d4.metadata.parserSpecific.imageData.pixels;
    eq4 = imaging.clahe(img4, TileSize=[4 4], ClipLimit=0.01);
    assert(isequal(size(eq4), size(img4)), 'DM4: size preserved');
    assert(all(eq4(:) >= 0) && all(eq4(:) <= 1), 'DM4: bounded');
    fprintf('  DM4 %s: %dx%d → CLAHE OK\n', 'openNCEM_nonSquare', size(img4,2), size(img4,1));

    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 4: connectedComponents on a known mask
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 4: connectedComponents known mask ══\n');
try
    bw = false(10, 10);
    bw(2:4, 2:4) = true;    % 3x3 square
    bw(7:9, 7:9) = true;    % 3x3 square
    bw(6, 6)     = true;    % singleton, diagonal-adjacent to second square

    % 4-connectivity: the singleton is NOT connected to the square
    [L4, n4] = imaging.connectedComponents(bw, Connectivity=4);
    assert(n4 == 3, sprintf('4-conn: expected 3 components, got %d', n4));

    % 8-connectivity: the singleton joins the second square via diagonal
    [L8, n8] = imaging.connectedComponents(bw, Connectivity=8);
    assert(n8 == 2, sprintf('8-conn: expected 2 components, got %d', n8));

    % Empty mask
    [Le, ne] = imaging.connectedComponents(false(5, 5));
    assert(ne == 0 && all(Le(:) == 0), 'empty mask should produce 0 components');

    % Single-component U-shape (tests union across multiple prior labels)
    bw2 = false(5, 5);
    bw2(2, 2:4) = true;
    bw2(4, 2:4) = true;
    bw2(2:4, 2) = true;
    [~, n2] = imaging.connectedComponents(bw2, Connectivity=4);
    assert(n2 == 1, sprintf('U-shape: expected 1 component, got %d', n2));

    fprintf('  PASS (4-conn=3, 8-conn=2, U-shape=1)\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 5: particleAnalysis on synthetic disks
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 5: particleAnalysis synthetic disks ══\n');
try
    % Make 3 bright disks of known radii on a dark background
    H = 80; W = 120;
    img = zeros(H, W);
    [XX, YY] = meshgrid(1:W, 1:H);

    disks = struct( ...
        'cx', {20, 60, 100}, ...
        'cy', {20, 40, 60}, ...
        'r',  {5, 8, 10});

    for k = 1:numel(disks)
        m = (XX - disks(k).cx).^2 + (YY - disks(k).cy).^2 <= disks(k).r^2;
        img(m) = 1;
    end

    r = imaging.particleAnalysis(img, Threshold=0.5, Polarity="bright", ...
        MinArea=10);

    assert(r.numParticles == 3, ...
        sprintf('expected 3 particles, got %d', r.numParticles));

    % Sort by area ascending to match disks() order
    areas = [r.particles.area];
    [~, idx] = sort(areas);
    sorted = r.particles(idx);

    for k = 1:3
        expectedArea = pi * disks(k).r^2;
        actual = sorted(k).area;
        relErr = abs(actual - expectedArea) / expectedArea;
        assert(relErr < 0.15, ...
            sprintf('disk %d area: expected ~%.0f got %d (rel err %.2f)', ...
                k, expectedArea, actual, relErr));

        expectedDiam = 2 * disks(k).r;
        diamErr = abs(sorted(k).equivDiameter - expectedDiam) / expectedDiam;
        assert(diamErr < 0.1, ...
            sprintf('disk %d diameter: expected ~%.1f got %.1f', ...
                k, expectedDiam, sorted(k).equivDiameter));

        % Centroid should match within 1 pixel
        assert(abs(sorted(k).centroid(1) - disks(k).cy) < 1.5, ...
            sprintf('disk %d centroid row off', k));
        assert(abs(sorted(k).centroid(2) - disks(k).cx) < 1.5, ...
            sprintf('disk %d centroid col off', k));
    end

    % MinArea should filter small specks. Add a single-pixel speck and
    % verify it is dropped.
    img2 = img;
    img2(5, 5) = 1;
    r2 = imaging.particleAnalysis(img2, Threshold=0.5, MinArea=10);
    assert(r2.numParticles == 3, 'MinArea=10 should drop single-pixel speck');

    % Calibrated diameter
    rc = imaging.particleAnalysis(img, Threshold=0.5, MinArea=10, ...
        PixelSize=0.5, PixelUnit="nm");
    calDiam = [rc.particles.diameterCalibrated];
    assert(all(calDiam > 0) && all(isfinite(calDiam)), ...
        'calibrated diameters should be finite positive');

    fprintf('  PASS (3 disks detected, areas/centroids/calibration OK)\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 6: particleAnalysis on a real DM3 file (dark polarity)
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 6: particleAnalysis on real DM3 file ══\n');
try
    dm3 = fullfile(dataDir, 'EDW087-1.dm3');
    d = parser.importDM3(dm3);
    img = double(d.metadata.parserSpecific.imageData.pixels);

    % Mildly blur first to suppress noise, then run Otsu + particle
    % analysis looking for dark features.
    blurred = imaging.applyGaussian(img, Sigma=1.5);
    r = imaging.particleAnalysis(blurred, Polarity="dark", MinArea=50, ...
        Connectivity=8);

    % This is a smoke test — just assert the pipeline completes and
    % returns a reasonable number of particles (neither 0 nor absurdly large).
    assert(r.numParticles >= 1, 'expected at least 1 dark particle');
    assert(r.numParticles < 5000, ...
        sprintf('got %d particles — threshold likely too permissive', ...
            r.numParticles));
    assert(isfield(r, 'threshold') && isfinite(r.threshold), ...
        'threshold should be set');

    fprintf('  DM3 EDW087-1: %d dark particles above MinArea=50 (thr=%.0f)\n', ...
        r.numParticles, r.threshold);
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 7: particleAnalysis on a real DM4 file (smoke test)
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 7: particleAnalysis on real DM4 file ══\n');
try
    dm4 = fullfile(dataDir, 'openNCEM_nonSquare.dm4');
    d = parser.importDM4(dm4);
    img = double(d.metadata.parserSpecific.imageData.pixels);

    r = imaging.particleAnalysis(img, Polarity="bright", MinArea=4);
    assert(isfield(r, 'particles'), 'result should have particles field');
    assert(isfield(r, 'labels') && isequal(size(r.labels), size(img)), ...
        'labels should match image size');

    fprintf('  DM4 openNCEM_nonSquare: %d particles (thr=%.2f)\n', ...
        r.numParticles, r.threshold);
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 8: distanceTransform sanity — center of a filled square
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 8: distanceTransform sanity ══\n');
try
    bw = false(21, 21);
    bw(2:20, 2:20) = true;   % 19x19 foreground region, 1-pixel border
    D = imaging.distanceTransform(bw);

    % Center pixel should have the largest distance
    [~, idx] = max(D(:));
    [cr, cc] = ind2sub(size(D), idx);
    assert(cr == 11 && cc == 11, ...
        sprintf('center max at (%d,%d), expected (11,11)', cr, cc));

    % Border pixels inside the mask should all have D = 3 (chamfer ortho step)
    assert(D(2, 11) == 3, sprintf('top-row border D=%d, expected 3', D(2,11)));
    assert(D(11, 2) == 3, sprintf('left-col border D=%d, expected 3', D(11,2)));
    assert(D(1, 1) == 0, 'background must be 0');

    % Cityblock metric
    D2 = imaging.distanceTransform(bw, Metric="cityblock");
    assert(D2(11, 11) == 10, 'cityblock center should be 10 (min dist to border)');

    fprintf('  PASS (center max OK, border D=3, cityblock=10)\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 9: watershed splits two touching disks into two regions
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 9: watershed splits touching disks ══\n');
try
    H = 60; W = 100;
    [XX, YY] = meshgrid(1:W, 1:H);
    r = 15;
    cx1 = 30; cy1 = 30;
    cx2 = 58; cy2 = 30;    % centers 28 px apart → disks touch/overlap slightly
    bw = ((XX - cx1).^2 + (YY - cy1).^2 <= r^2) | ...
         ((XX - cx2).^2 + (YY - cy2).^2 <= r^2);

    % Without watershed: 1 fused blob
    [~, nFused] = imaging.connectedComponents(bw);
    assert(nFused == 1, sprintf('expected 1 fused blob, got %d', nFused));

    % With watershed: 2 regions
    [L, nSplit] = imaging.watershed(bw, MinMarkerDistance=10);
    assert(nSplit == 2, sprintf('watershed: expected 2 regions, got %d', nSplit));
    assert(isequal(size(L), [H, W]), 'label image size');
    assert(all(L(~bw) == 0), 'background pixels must stay 0');

    % Both regions should have substantial area (not one tiny sliver)
    a1 = sum(L(:) == 1);
    a2 = sum(L(:) == 2);
    ratio = min(a1, a2) / max(a1, a2);
    assert(ratio > 0.5, ...
        sprintf('split unbalanced: %d vs %d (ratio %.2f)', a1, a2, ratio));

    fprintf('  PASS (fused=%d, split=%d, areas=%d,%d)\n', nFused, nSplit, a1, a2);
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 10: particleAnalysis with Watershed=true on touching disks
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 10: particleAnalysis with Watershed option ══\n');
try
    H = 60; W = 100;
    [XX, YY] = meshgrid(1:W, 1:H);
    r = 15;
    bw = ((XX - 30).^2 + (YY - 30).^2 <= r^2) | ...
         ((XX - 58).^2 + (YY - 30).^2 <= r^2);
    img = double(bw);   % 0/1 intensity

    rNo = imaging.particleAnalysis(img, Threshold=0.5, MinArea=10);
    rYes = imaging.particleAnalysis(img, Threshold=0.5, MinArea=10, ...
        Watershed=true, MinMarkerDistance=10);

    assert(rNo.numParticles == 1, ...
        sprintf('no-watershed: expected 1, got %d', rNo.numParticles));
    assert(rYes.numParticles == 2, ...
        sprintf('watershed: expected 2, got %d', rYes.numParticles));

    fprintf('  PASS (no-watershed=1, watershed=2)\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 11: watershed smoke test on real DM3 + DM4 files
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 11: watershed on real DM3 + DM4 files ══\n');
try
    dm3 = fullfile(dataDir, 'EDW087-1.dm3');
    d3 = parser.importDM3(dm3);
    img3 = double(d3.metadata.parserSpecific.imageData.pixels);
    blurred3 = imaging.applyGaussian(img3, Sigma=2);
    % Wider MinMarkerDistance + lower MinArea: the DM3 is noisy, a small
    % MinMarkerDistance over-fragments the single dark blob into specks
    % below any reasonable MinArea. This test is a smoke test of the
    % pipeline, not a segmentation-quality benchmark.
    r3 = imaging.particleAnalysis(blurred3, Polarity="dark", ...
        MinArea=20, Watershed=true, MinMarkerDistance=20);
    assert(r3.numParticles >= 1, ...
        sprintf('expected at least 1 region on DM3, got %d (thr=%.0f)', ...
            r3.numParticles, r3.threshold));
    fprintf('  DM3 EDW087-1: %d regions after watershed (thr=%.0f)\n', ...
        r3.numParticles, r3.threshold);

    dm4 = fullfile(dataDir, 'openNCEM_nonSquare.dm4');
    d4 = parser.importDM4(dm4);
    img4 = double(d4.metadata.parserSpecific.imageData.pixels);
    r4 = imaging.particleAnalysis(img4, Polarity="bright", ...
        MinArea=4, Watershed=true);
    assert(isfield(r4, 'particles'), 'DM4 smoke test failed');
    fprintf('  DM4 openNCEM_nonSquare: %d regions after watershed (thr=%.2f)\n', ...
        r4.numParticles, r4.threshold);

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
    error('test_particle_clahe: %d test(s) failed', failed);
end
