%TEST_ATOMCOLUMNS  Unit tests for the atom-column analysis suite.
%
%   Purely synthetic lattices — no external files. Each test prints a tick
%   (pass) or cross (fail). Validates the full pipeline against ground truth:
%       imaging.atoms.detectColumns
%       imaging.atoms.fitGaussian2D
%       imaging.atoms.findLatticeVectors
%       imaging.atoms.assignSublattice
%       imaging.atoms.peakPairStrain
%
%   Run from root:  run tests/imaging/test_atomColumns
%       runAllTests(Group="atoms")

clear; clc;
fprintf('\n═══ test_atomColumns ═══\n');

thisDir = fileparts(mfilename('fullpath'));
rootDir = fileparts(fileparts(thisDir));
if ~contains(path, rootDir)
    addpath(rootDir);
end

nPass = 0;
nFail = 0;

try  % outer guard

% ════════════════════════════════════════════════════════════════════════
%  1. detectColumns — recovers a clean square lattice
% ════════════════════════════════════════════════════════════════════════
try
    d = 15; nx = 10; ny = 10; sigma = 2.5;
    [pos, ~] = makeLattice([d 0], [0 d], nx, ny, [30 30]);
    img = renderImage(pos, [200 200], sigma, 1.0, 0.05);

    res = imaging.atoms.detectColumns(img, Sigma=2, Threshold=0.15, MinSeparation=10);
    nDet = size(res.positions, 1);
    nTrue = size(pos, 1);

    assert(nDet >= 0.9 * nTrue && nDet <= nTrue + 3, ...
        sprintf('detected %d columns, expected ~%d', nDet, nTrue));

    % Every detection lands within 2 px of a true column.
    D2 = pairwiseMinDist(res.positions, pos);
    assert(median(D2) < 2, sprintf('median detection error %.2f px too large', median(D2)));

    nPass = nPass + 1;
    fprintf('  ✔ Test 1: detectColumns — %d/%d columns, median err %.2f px\n', nDet, nTrue, median(D2));
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 1: detectColumns: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  2. fitGaussian2D — sub-pixel accuracy on known fractional centers
% ════════════════════════════════════════════════════════════════════════
try
    d = 16; sigma = 2.2;
    [pos, ~] = makeLattice([d 0], [0 d], 8, 8, [24 24]);
    % Shift truth by a known sub-pixel offset so integer seeds are wrong.
    pos = pos + 0.37;
    img = renderImage(pos, [180 180], sigma, 1.0, 0.02);

    det = imaging.atoms.detectColumns(img, Sigma=2, Threshold=0.15, MinSeparation=10);
    fit = imaging.atoms.fitGaussian2D(img, det.positions, WinRadius=6);

    % Match each fitted column to nearest truth; sub-pixel error should be small.
    err = pairwiseMinDist(fit.positions, pos);
    assert(median(err) < 0.25, sprintf('median sub-pixel error %.3f px too large', median(err)));
    assert(mean(fit.converged) > 0.8, 'too many fits failed to converge');

    nPass = nPass + 1;
    fprintf('  ✔ Test 2: fitGaussian2D — median err %.3f px, %.0f%% converged\n', ...
        median(err), 100 * mean(fit.converged));
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 2: fitGaussian2D: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  3. findLatticeVectors — recovers square + oblique bases
% ════════════════════════════════════════════════════════════════════════
try
    d = 15;
    [posSq, ~] = makeLattice([d 0], [0 d], 12, 12, [20 20]);
    lvSq = imaging.atoms.findLatticeVectors(posSq);
    assert(lvSq.valid, 'square lattice not resolved');
    % Lengths within 5%; the two vectors near-orthogonal.
    L1 = norm(lvSq.a1); L2 = norm(lvSq.a2);
    assert(abs(L1 - d)/d < 0.05 && abs(L2 - d)/d < 0.05, ...
        sprintf('square vector lengths off: %.2f, %.2f (want %.0f)', L1, L2, d));
    ang = acosd(abs(dot(lvSq.a1, lvSq.a2)) / (L1 * L2));
    assert(abs(ang - 90) < 8, sprintf('square inter-vector angle %.1f deg', ang));

    % Oblique lattice (60 deg).
    a1 = [d 0]; a2 = [d*cosd(60) d*sind(60)];
    [posOb, ~] = makeLattice(a1, a2, 12, 12, [40 20]);
    lvOb = imaging.atoms.findLatticeVectors(posOb);
    assert(lvOb.valid, 'oblique lattice not resolved');
    assert(abs(norm(lvOb.a1) - d)/d < 0.06, 'oblique a1 length off');

    nPass = nPass + 1;
    fprintf('  ✔ Test 3: findLatticeVectors — square 90°≈%.1f°, oblique resolved\n', ang);
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 3: findLatticeVectors: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  4. assignSublattice — separates two intensity populations
% ════════════════════════════════════════════════════════════════════════
try
    amp = [ones(20,1)*1.0; ones(20,1)*0.4];   % 20 bright, 20 dim
    labels = imaging.atoms.assignSublattice(amp, 2, Seed=1);
    % Label 1 = brightest by contract.
    assert(all(labels(1:20) == 1), 'bright columns not all in sublattice 1');
    assert(all(labels(21:40) == 2), 'dim columns not all in sublattice 2');

    % k==1 returns all ones.
    assert(all(imaging.atoms.assignSublattice(amp, 1) == 1), 'k=1 must be all ones');

    nPass = nPass + 1;
    fprintf('  ✔ Test 4: assignSublattice — bright/dim split correct\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 4: assignSublattice: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  5. peakPairStrain — recovers a known uniform strain
% ════════════════════════════════════════════════════════════════════════
try
    d = 15; origin = [90 90];
    [ideal, ~] = makeLattice([d 0], [0 d], 12, 12, origin);
    % Centre the lattice on the origin so displacements stay < half-spacing.
    ideal = ideal - mean(ideal, 1) + origin;

    exxT = 0.02; eyyT = -0.01; exyT = 0.005;
    F = [exxT exyT; exyT eyyT];
    rel = ideal - origin;
    strained = ideal + (F * rel')';

    res = imaging.atoms.peakPairStrain(strained, ...
        RefVectors=[d 0; 0 d], Origin=origin, Neighbors=8);
    assert(res.valid, 'PPA returned invalid');

    mxx = median(res.exx, 'omitnan');
    myy = median(res.eyy, 'omitnan');
    mxy = median(res.exy, 'omitnan');
    assert(abs(mxx - exxT) < 0.004, sprintf('exx %.4f vs %.4f', mxx, exxT));
    assert(abs(myy - eyyT) < 0.004, sprintf('eyy %.4f vs %.4f', myy, eyyT));
    assert(abs(mxy - exyT) < 0.004, sprintf('exy %.4f vs %.4f', mxy, exyT));

    nPass = nPass + 1;
    fprintf('  ✔ Test 5: peakPairStrain — exx=%.4f eyy=%.4f exy=%.4f\n', mxx, myy, mxy);
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 5: peakPairStrain: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  6. detectColumns — dark polarity
% ════════════════════════════════════════════════════════════════════════
try
    d = 15;
    [pos, ~] = makeLattice([d 0], [0 d], 8, 8, [30 30]);
    G = renderImage(pos, [160 160], 2.5, 1.0, 0.0);
    img = max(G(:)) - G;                                    % invert: dark columns on bright bg
    res = imaging.atoms.detectColumns(img, Sigma=2, Threshold=0.15, ...
        MinSeparation=10, Polarity="dark");
    nDet = size(res.positions, 1); nTrue = size(pos, 1);
    assert(nDet >= 0.9 * nTrue && nDet <= nTrue + 4, ...
        sprintf('dark-polarity detected %d, expected ~%d', nDet, nTrue));
    err = pairwiseMinDist(res.positions, pos);
    assert(median(err) < 2, sprintf('dark median err %.2f px', median(err)));
    nPass = nPass + 1;
    fprintf('  ✔ Test 6: detectColumns (dark polarity) — %d/%d columns\n', nDet, nTrue);
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 6: detectColumns dark: %s\n', ME.message);
end

catch fatalErr
    fprintf('  ✘ FATAL error in test harness: %s\n', fatalErr.message);
    nFail = nFail + 1;
end

% ── Summary ──────────────────────────────────────────────────────────────
fprintf('\n═══ Results: %d passed, %d failed ═══\n\n', nPass, nFail);

if nFail > 0
    error('test_atomColumns:failures', '%d test(s) failed.', nFail);
end

% ══════════════════════════════════════════════════════════════════════════
%  Local helpers (kept at EOF — R2022b parses local functions only at end)
% ══════════════════════════════════════════════════════════════════════════
function [pos, origin] = makeLattice(a1, a2, nx, ny, origin)
%   Generate (nx+1)x(ny+1) lattice points: origin + m*a1 + n*a2.
    [M, NN] = meshgrid(0:nx, 0:ny);
    M = M(:); NN = NN(:);
    pos = origin + M .* a1 + NN .* a2;
end

function img = renderImage(pos, sz, sigma, amp, bg)
%   Render a sum of 2D Gaussians at pos=[x y] onto an sz=[H W] image.
    H = sz(1); W = sz(2);
    [X, Y] = meshgrid(1:W, 1:H);
    img = bg * ones(H, W);
    for i = 1:size(pos, 1)
        img = img + amp * exp(-0.5 * ((X - pos(i,1)).^2 + (Y - pos(i,2)).^2) / sigma^2);
    end
end

function dmin = pairwiseMinDist(A, B)
%   For each row of A, distance to the nearest row of B.
    D2 = sum(A.^2, 2) - 2 * (A * B') + sum(B.^2, 2)';
    D2(D2 < 0) = 0;
    dmin = sqrt(min(D2, [], 2));
end
