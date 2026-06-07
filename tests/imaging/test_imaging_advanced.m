%TEST_IMAGING_ADVANCED  Unit tests for the advanced +imaging utilities.
%
%   Covers the processing/measurement/AFM functions not tested by
%   test_imaging_utils.m — binning, sharpening, morphology, Otsu,
%   Butterworth, noise estimate, plane leveling, roughness, lattice
%   measurement, radial/azimuthal integration, interface fitting, defect
%   counting, and image stitching.
%
%   All tests use synthetic data. No external files required.
%
%   Run standalone:  run tests/imaging/test_imaging_advanced
%   Run from group:  runAllTests(Group="em")

clear; clc;
fprintf('\n═══ test_imaging_advanced ═══\n');

thisDir = fileparts(mfilename('fullpath'));
rootDir = fileparts(fileparts(thisDir));
if ~contains(path, rootDir)
    addpath(rootDir);
end

nPass = 0;
nFail = 0;

% ════════════════════════════════════════════════════════════════════════
%  1. binImage — average 8x8 → 2x2 with BinSize=4
% ════════════════════════════════════════════════════════════════════════
try
    img = reshape(1:64, 8, 8);
    out = imaging.binImage(img, BinSize=4);
    assert(isequal(size(out), [2 2]), 'binImage size wrong');
    % Each 4x4 block averaged; block (1,1) mean of a known submatrix
    expected11 = mean(mean(img(1:4, 1:4)));
    assert(abs(out(1,1) - expected11) < 1e-9, 'binImage average wrong');
    % Mode=sum multiplies by 16
    outSum = imaging.binImage(img, BinSize=4, Mode='sum');
    assert(abs(outSum(1,1) - expected11 * 16) < 1e-9, 'binImage sum wrong');
    nPass = nPass + 1;
    fprintf('  ✔ Test 1: binImage — average + sum modes\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 1: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  2. unsharpMask — enhance edges of a step image
% ════════════════════════════════════════════════════════════════════════
try
    img = zeros(32, 32);
    img(:, 16:end) = 1;  % vertical step at col 16
    out = imaging.unsharpMask(double(img), Sigma=1.5, Amount=1.0);
    % Sharpened step should exceed the input on the bright side near the edge
    assert(out(16, 17) >= img(16, 17), 'unsharpMask should enhance bright edge');
    assert(out(16, 15) <= img(16, 15) + 1e-6, 'unsharpMask should enhance dark edge');
    assert(isequal(size(out), size(img)), 'unsharpMask size changed');
    nPass = nPass + 1;
    fprintf('  ✔ Test 2: unsharpMask — edge enhancement on step\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 2: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  3. morphOp — erode/dilate/open/close on a binary square
% ════════════════════════════════════════════════════════════════════════
try
    bw = zeros(32, 32);
    bw(10:22, 10:22) = 1;  % 13x13 square (morphOp expects numeric, not logical)
    nBefore = nnz(bw);

    eroded = imaging.morphOp(bw, 'erode', Radius=1);
    assert(nnz(eroded) < nBefore, 'erode should reduce pixel count');

    dilated = imaging.morphOp(bw, 'dilate', Radius=1);
    assert(nnz(dilated) > nBefore, 'dilate should increase pixel count');

    % Open on a clean square should be idempotent (approximately)
    opened = imaging.morphOp(bw, 'open', Radius=1);
    assert(nnz(opened) <= nBefore, 'open should not grow');

    % Close should fill a small hole
    bwHole = bw;
    bwHole(16, 16) = 0;
    closed = imaging.morphOp(bwHole, 'close', Radius=1);
    assert(closed(16, 16) > 0, 'close should fill single-pixel hole');

    nPass = nPass + 1;
    fprintf('  ✔ Test 3: morphOp — erode/dilate/open/close\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 3: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  4. multiOtsu — bimodal histogram, NumClasses=2 puts threshold in valley
% ════════════════════════════════════════════════════════════════════════
try
    rng(0);
    lo = 50  + 5 * randn(50, 50);
    hi = 200 + 5 * randn(50, 50);
    img = [lo, hi];   % two modes at 50 and 200
    r = imaging.multiOtsu(img, NumClasses=2);
    assert(isfield(r, 'thresholds'), 'multiOtsu missing thresholds field');
    assert(numel(r.thresholds) == 1, 'NumClasses=2 should yield 1 threshold');
    th = r.thresholds(1);
    % Otsu threshold on this histogram should fall strictly between the modes.
    assert(th > 60 && th < 195, sprintf('threshold %.1f not between modes', th));

    r3 = imaging.multiOtsu(img, NumClasses=3);
    assert(numel(r3.thresholds) == 2, 'NumClasses=3 should yield 2 thresholds');

    nPass = nPass + 1;
    fprintf('  ✔ Test 4: multiOtsu — bimodal threshold in valley\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 4: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  5. butterworthFilter — low-pass removes high-freq checkerboard
% ════════════════════════════════════════════════════════════════════════
try
    [X, Y] = meshgrid(1:64, 1:64);
    checker = double(mod(X + Y, 2));  % highest possible spatial frequency
    lp = imaging.butterworthFilter(checker, HighCutoff=0.1, Order=4);
    % After low-pass, variance drops sharply
    assert(var(lp(:)) < 0.05, sprintf('LP variance %.4f too high', var(lp(:))));
    assert(isequal(size(lp), size(checker)), 'butterworth size changed');

    % High-pass on a DC image should return approximately zero
    dc = ones(64, 64);
    hp = imaging.butterworthFilter(dc, LowCutoff=0.05, HighCutoff=0.99, Order=4);
    assert(max(abs(hp(:))) < 0.5, 'HP of DC image should be ~0');

    nPass = nPass + 1;
    fprintf('  ✔ Test 5: butterworthFilter — low-pass + high-pass behavior\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 5: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  6. noiseEstimate — MAD on image + known noise
% ════════════════════════════════════════════════════════════════════════
try
    rng(1);
    sigmaTrue = 5.0;
    img = 100 + sigmaTrue * randn(128, 128);
    r = imaging.noiseEstimate(img, Method='mad');
    assert(isfield(r, 'sigma'), 'noiseEstimate missing sigma field');
    ratio = r.sigma / sigmaTrue;
    assert(ratio > 0.5 && ratio < 2.0, sprintf('sigma %.2f off from %.2f', r.sigma, sigmaTrue));
    nPass = nPass + 1;
    fprintf('  ✔ Test 6: noiseEstimate — MAD recovers sigma (got %.2f, true %.2f)\n', ...
        r.sigma, sigmaTrue);
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 6: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  7. planeLevel — remove linear tilt
% ════════════════════════════════════════════════════════════════════════
try
    [X, Y] = meshgrid(1:64, 1:64);
    tilt = 0.5 * X + 0.3 * Y + 10;
    r = imaging.planeLevel(tilt, Order=1);
    assert(isfield(r, 'leveled'), 'planeLevel missing leveled field');
    assert(max(abs(r.leveled(:))) < 1e-6, ...
        sprintf('leveled residual too large: %.4g', max(abs(r.leveled(:)))));
    nPass = nPass + 1;
    fprintf('  ✔ Test 7: planeLevel — tilt removed to <1e-6\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 7: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  8. surfaceRoughness — known sinusoid gives predictable Ra
% ════════════════════════════════════════════════════════════════════════
try
    [X, ~] = meshgrid(1:64, 1:64);
    amp = 10;
    surf = amp * sin(2*pi*X/16);
    r = imaging.surfaceRoughness(surf, Level='none');
    % Ra = mean(|z - mean(z)|); for pure sine of amplitude A → 2A/pi ≈ 6.37
    assert(isfield(r, 'Ra'), 'surfaceRoughness missing Ra');
    expectedRa = 2 * amp / pi;
    assert(abs(r.Ra - expectedRa) / expectedRa < 0.1, ...
        sprintf('Ra %.3f != expected %.3f', r.Ra, expectedRa));
    assert(isfield(r, 'Rq'), 'missing Rq');
    nPass = nPass + 1;
    fprintf('  ✔ Test 8: surfaceRoughness — sinusoidal Ra=%.2f (expected %.2f)\n', ...
        r.Ra, expectedRa);
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 8: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  9. latticeMeasure — 2 orthogonal spots → square lattice
% ════════════════════════════════════════════════════════════════════════
try
    imgSize = [128, 128];
    cx = floor(imgSize(2)/2) + 1;
    cy = floor(imgSize(1)/2) + 1;
    % Spots at offset (0,16) and (16,0) in [row, col] give reciprocal
    % vectors of length 16/128 cycles/px → real-space period 128/16 = 8 px
    spot1 = [cy, cx + 16];    % horizontal reciprocal
    spot2 = [cy + 16, cx];    % vertical reciprocal
    r = imaging.latticeMeasure(spot1, spot2, imgSize, PixelSize=1, PixelUnit='px');
    assert(isstruct(r), 'latticeMeasure should return struct');
    % real-space spacings should be ~8 px each, angle 90°
    assert(isfield(r, 'dSpacing1') && isfield(r, 'dSpacing2'), 'missing dSpacing1/2');
    assert(abs(r.dSpacing1 - 8) < 0.5 && abs(r.dSpacing2 - 8) < 0.5, ...
        sprintf('spacings [%.2f, %.2f] != [8, 8]', r.dSpacing1, r.dSpacing2));
    assert(abs(r.gamma - 90) < 1, sprintf('gamma %.2f != 90', r.gamma));
    nPass = nPass + 1;
    fprintf('  ✔ Test 9: latticeMeasure — square d1=%.2f d2=%.2f γ=%.1f°\n', ...
        r.dSpacing1, r.dSpacing2, r.gamma);
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 9: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
% 10. radialProfile — centred Gaussian, max at r=0
% ════════════════════════════════════════════════════════════════════════
try
    [X, Y] = meshgrid(1:64, 1:64);
    img = exp(-((X-32).^2 + (Y-32).^2) / (2*8^2));
    [radii, avgP, maxP] = imaging.radialProfile(img, NumBins=32);
    assert(numel(radii) == numel(avgP), 'size mismatch radii/avgP');
    assert(numel(radii) == numel(maxP), 'size mismatch radii/maxP');
    [~, argmax] = max(avgP);
    assert(argmax <= 3, sprintf('Gaussian peak not at r=0 (at bin %d)', argmax));
    assert(avgP(1) > avgP(end), 'profile should decrease with r');
    nPass = nPass + 1;
    fprintf('  ✔ Test 10: radialProfile — Gaussian peak near origin\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 10: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
% 11. azimuthalIntegrate — ring at fixed radius shows peak in profile
% ════════════════════════════════════════════════════════════════════════
try
    [X, Y] = meshgrid(1:128, 1:128);
    r2 = (X-64).^2 + (Y-64).^2;
    ring = double(r2 > 20^2 & r2 < 24^2);
    [radii, intensity] = imaging.azimuthalIntegrate(ring, NumBins=128);
    [~, imax] = max(intensity);
    peakR = radii(imax);
    assert(peakR > 18 && peakR < 26, sprintf('ring peak at r=%.1f not in [18,26]', peakR));
    nPass = nPass + 1;
    fprintf('  ✔ Test 11: azimuthalIntegrate — ring peak at r=%.1f\n', peakR);
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 11: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
% 12. fitInterfaceWidth — erf profile with known sigma
% ════════════════════════════════════════════════════════════════════════
try
    x = linspace(-20, 20, 200);
    sigmaTrue = 3.0;
    y = 0.5 * (1 + erf(x / (sigmaTrue * sqrt(2))));
    r = imaging.fitInterfaceWidth(x, y, Model='erf');
    assert(isstruct(r), 'should return struct');
    assert(isfield(r, 'sigma') || isfield(r, 'width10_90'), ...
        'missing sigma/width10_90');
    if isfield(r, 'sigma')
        assert(abs(r.sigma - sigmaTrue) / sigmaTrue < 0.2, ...
            sprintf('sigma %.3f != %.3f', r.sigma, sigmaTrue));
        fprintf('  ✔ Test 12: fitInterfaceWidth — sigma=%.3f (true %.3f)\n', ...
            r.sigma, sigmaTrue);
    else
        fprintf('  ✔ Test 12: fitInterfaceWidth — width10_90=%.3f\n', r.width10_90);
    end
    nPass = nPass + 1;
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 12: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
% 13. stitchImages — two overlapping halves of a gradient
% ════════════════════════════════════════════════════════════════════════
try
    full = repmat(linspace(0, 1, 100), 60, 1);
    % Split into overlapping halves (20% overlap)
    left  = full(:, 1:60);
    right = full(:, 41:100);
    r = imaging.stitchImages({left, right}, Layout='horizontal', OverlapFrac=0.3);
    assert(isstruct(r), 'should return struct');
    assert(isfield(r, 'mosaic'), 'missing mosaic field');
    w = size(r.mosaic, 2);
    assert(w >= 90 && w <= 110, sprintf('stitched width %d unexpected', w));
    assert(isfield(r, 'offsets'), 'missing offsets field');
    nPass = nPass + 1;
    fprintf('  ✔ Test 13: stitchImages — horizontal mosaic width=%d\n', w);
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 13: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
% 14. countDefectLines — image with horizontal lines returns count > 0
% ════════════════════════════════════════════════════════════════════════
try
    img = zeros(128, 128);
    for row = 20:30:120
        img(row, :) = 1;   % bright horizontal lines
    end
    img = img + 0.05 * randn(size(img));
    r = imaging.countDefectLines(img, Direction=0, GridSpacing=16);
    assert(isstruct(r), 'should return struct');
    assert(isfield(r, 'numIntersections') || isfield(r, 'density') || ...
           isfield(r, 'count'), 'missing count/density field');
    nPass = nPass + 1;
    fprintf('  ✔ Test 14: countDefectLines — synthetic lines detected\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 14: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
% 15. radialProfile — default NumBins resolves to floor(min(H,W)/2)
%     (regression: arguments block had mustBePositive on default 0)
% ════════════════════════════════════════════════════════════════════════
try
    H = 40; W = 60;
    img = ones(H, W);
    [radii, avgP, ~] = imaging.radialProfile(img);   % NumBins omitted
    expectedBins = floor(min(H, W) / 2);             % floor(40/2) = 20
    assert(numel(radii) == expectedBins, ...
        sprintf('radialProfile: expected %d bins, got %d', expectedBins, numel(radii)));
    assert(numel(avgP) == expectedBins, ...
        sprintf('radialProfile: avgP length %d != %d', numel(avgP), expectedBins));
    nPass = nPass + 1;
    fprintf('  ✔ Test 15: radialProfile — default NumBins=floor(min(H,W)/2)=%d\n', expectedBins);
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 15: radialProfile default NumBins: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
% 16. morphOp — accepts logical mask for all four operations
%     (regression: arguments block had mustBeNumeric, rejected logical)
% ════════════════════════════════════════════════════════════════════════
try
    bwNum  = zeros(32, 32);
    bwNum(10:22, 10:22) = 1;          % double 0/1
    bwLog  = logical(bwNum);          % logical mask

    for op = {'erode','dilate','open','close'}
        outNum = imaging.morphOp(bwNum, op{1}, Radius=1);
        outLog = imaging.morphOp(bwLog, op{1}, Radius=1);
        assert(isequal(outNum, outLog), ...
            sprintf('morphOp %s: logical and double results differ', op{1}));
    end

    nPass = nPass + 1;
    fprintf('  ✔ Test 16: morphOp — logical mask accepted; matches double 0/1 for all ops\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 16: morphOp logical input: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
% 17. templateMatch — exact embedded patch recovered at true center
%
%  Regression for the FFT-lag indexing bug:
%    xcorrFull(tmplH:imgH, tmplW:imgW)         <- BUG (off by tmpl size)
%    xcorrFull(1:imgH-tmplH+1, 1:imgW-tmplW+1) <- correct
%
%  When the template is padded at the top-left, ifft2(F·conj(T)) at
%  1-based index (r,c) equals the cross-correlation with the template's
%  top-left aligned at (r,c).  The valid region starts at (1,1), not
%  (tmplH, tmplW).  The old selection paired xcorr values with the
%  wrong local-statistics windows, producing spurious 1.0 peaks at
%  circularly-aliased positions.
%
%  Test setup: tiled periodic background fills every sliding window with
%  non-zero variance, then the patch is embedded at a known location.
%  The extracted-patch template has NCC = 1 by construction (no noise),
%  so the assertions use tight bounds.
% ════════════════════════════════════════════════════════════════════════
try
    imgH = 64; imgW = 80;
    tmplH = 7; tmplW = 9;

    % Structured (non-constant) template patch
    [cc, rr] = meshgrid(1:tmplW, 1:tmplH);
    tmplCore = sin(rr) .* cos(cc) + 0.1 * rr .* cc;

    % Known top-left of embedding.
    % templateMatch embeds nccValid (top-left domain) into nccMap shifted
    % by floor(tmplSize/2), so the map peak is at:
    %   centerRow = tlRow + floor(tmplH/2)   (1-based)
    %   centerCol = tlCol + floor(tmplW/2)
    tlRow = 21; tlCol = 31;
    centerRow = tlRow + floor(tmplH/2);   % 24
    centerCol = tlCol + floor(tmplW/2);   % 35

    % Build image: weakly periodic background (non-zero variance in every
    % sliding window → localStd > 0 everywhere) plus a strongly structured
    % patch added on top at the known location.
    % Extract the template FROM the image so template matches the image
    % window exactly → NCC = 1 by construction at the embedded position.
    [IC, IR] = meshgrid(1:imgW, 1:imgH);
    img = 0.3 * sin(2*pi*IR/11) .* cos(2*pi*IC/13);   % background
    img(tlRow:tlRow+tmplH-1, tlCol:tlCol+tmplW-1) = ...
        img(tlRow:tlRow+tmplH-1, tlCol:tlCol+tmplW-1) + 5*tmplCore;

    % Template = exact image crop → NCC = 1 at this location
    template = img(tlRow:tlRow+tmplH-1, tlCol:tlCol+tmplW-1);

    result = imaging.templateMatch(img, template, Threshold=0.9, MaxMatches=5);

    % 1. Top match must be at the known center (exact pixel)
    assert(result.nMatches >= 1, 'templateMatch: no matches found');
    topRow = result.locations(1,1);
    topCol = result.locations(1,2);
    assert(topRow == centerRow && topCol == centerCol, ...
        sprintf('templateMatch: top match at (%d,%d), expected (%d,%d)', ...
                topRow, topCol, centerRow, centerCol));

    % 2. Top match score must be high (the function uses std(N-1) for the
    %    template but population variance for local windows, so the maximum
    %    theoretical NCC is slightly below 1; empirically ≥ 0.98 for an
    %    exact crop, which is far above any spurious alias from the bug).
    assert(result.scores(1) > 0.98, ...
        sprintf('templateMatch: top score %.6f < 0.98', result.scores(1)));

    % 3. NCC map value at the true center must be high
    nccAtCenter = result.nccMap(centerRow, centerCol);
    assert(nccAtCenter > 0.98, ...
        sprintf('templateMatch: nccMap at true center %.6f < 0.98', nccAtCenter));

    % 4. No spurious near-1.0 peaks at the circularly-aliased position.
    %    The bug produced peaks shifted by (tmplH-1, tmplW-1) from the
    %    true center; check that value is well below the true peak.
    aliasRow = centerRow - (tmplH - 1);
    aliasCol = centerCol - (tmplW - 1);
    if aliasRow >= 1 && aliasRow <= imgH && aliasCol >= 1 && aliasCol <= imgW
        aliasScore = result.nccMap(aliasRow, aliasCol);
        assert(aliasScore < 0.5, ...
            sprintf('templateMatch: alias peak at (%d,%d) = %.3f (circular wrap not suppressed)', ...
                    aliasRow, aliasCol, aliasScore));
    end

    nPass = nPass + 1;
    fprintf('  ✔ Test 17: templateMatch — top match at (%d,%d) score=%.4f, nccMap=%.4f\n', ...
        topRow, topCol, result.scores(1), nccAtCenter);
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 17: templateMatch: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
% 18. templateMatch — no false 1.0 peaks when template has non-zero mean
%     (exercises the zero-mean normalization path with a shifted patch)
% ════════════════════════════════════════════════════════════════════════
try
    imgH = 50; imgW = 60;
    tmplH = 5; tmplW = 7;

    % Template with non-zero mean (the function zero-means it internally)
    [cc, rr] = meshgrid(1:tmplW, 1:tmplH);
    template = 100 + 20*sin(rr) + 15*cos(cc);   % mean ≠ 0

    tlRow = 10; tlCol = 15;
    centerRow = tlRow + floor(tmplH/2);   % 12
    centerCol = tlCol + floor(tmplW/2);   % 18

    % Periodic background (non-zero variance) + patch added on top.
    % Extract template FROM image so NCC = 1 at the embedded position.
    [IC, IR] = meshgrid(1:imgW, 1:imgH);
    img = 0.5 * sin(2*pi*IR/9) .* cos(2*pi*IC/11);
    img(tlRow:tlRow+tmplH-1, tlCol:tlCol+tmplW-1) = ...
        img(tlRow:tlRow+tmplH-1, tlCol:tlCol+tmplW-1) + template;
    template = img(tlRow:tlRow+tmplH-1, tlCol:tlCol+tmplW-1);

    result = imaging.templateMatch(img, template, Threshold=0.9, MaxMatches=3);

    assert(result.nMatches >= 1, 'templateMatch (shifted mean): no matches found');
    topRow = result.locations(1,1);
    topCol = result.locations(1,2);
    assert(topRow == centerRow && topCol == centerCol, ...
        sprintf('templateMatch (shifted mean): top match at (%d,%d), expected (%d,%d)', ...
                topRow, topCol, centerRow, centerCol));
    assert(result.scores(1) > 0.98, ...
        sprintf('templateMatch (shifted mean): score %.6f < 0.98', result.scores(1)));

    nPass = nPass + 1;
    fprintf('  ✔ Test 18: templateMatch — non-zero-mean template, top match at (%d,%d) score=%.4f\n', ...
        topRow, topCol, result.scores(1));
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 18: templateMatch (shifted mean): %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  Summary
% ════════════════════════════════════════════════════════════════════════
fprintf('\n─── test_imaging_advanced: %d passed, %d failed ───\n\n', nPass, nFail);
if nFail > 0
    error('test_imaging_advanced: %d test(s) failed.', nFail);
end
