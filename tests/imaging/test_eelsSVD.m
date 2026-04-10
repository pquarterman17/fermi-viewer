%TEST_EELSSVD  Unit tests for imaging.eelsSVD (EELS spectrum image SVD decomposition).
%
%   Tests use purely synthetic data — no external files required.
%   Verifiable properties: reconstruction accuracy, variance accounting,
%   dimensionality, rank truncation, denoised cube fidelity, edge cases.
%
%   Run:  runAllTests(Group="eels")

clear; clc;
fprintf('\n═══ test_eelsSVD ═══\n');

thisDir = fileparts(mfilename('fullpath'));
rootDir = fileparts(fileparts(thisDir));
if ~contains(path, rootDir)
    addpath(rootDir);
end

nPass = 0;
nFail = 0;

try  % outer guard

% ════════════════════════════════════════════════════════════════════════
%  Helper: build a synthetic spectrum image with known rank
% ════════════════════════════════════════════════════════════════════════
% Cube = sum of rank-1 outer products:
%   Component 1: Gaussian peak at 300 eV, strong in top-left
%   Component 2: Gaussian peak at 500 eV, strong in bottom-right
Ny = 8; Nx = 10; nE = 100;
E = linspace(200, 600, nE)';

spec1 = exp(-((E - 300).^2) / (2*15^2));   % peak at 300 eV
spec2 = exp(-((E - 500).^2) / (2*20^2));   % peak at 500 eV

[yy, xx] = ndgrid(linspace(0,1,Ny), linspace(0,1,Nx));
map1 = 1 - sqrt(yy.^2 + xx.^2);            % strong top-left
map2 = sqrt((yy-1).^2 + (xx-1).^2);        % strong bottom-right
map1 = max(map1, 0.01);
map2 = max(map2, 0.01);

% Build clean rank-2 cube
cleanCube = zeros(Ny, Nx, nE);
for iy = 1:Ny
    for ix = 1:Nx
        cleanCube(iy,ix,:) = 100*map1(iy,ix)*spec1 + 80*map2(iy,ix)*spec2;
    end
end

% Add small noise for realistic test
rng(42);
noisyCube = cleanCube + 0.5*randn(Ny, Nx, nE);

% ════════════════════════════════════════════════════════════════════════
%  TEST 1: Basic output structure and dimensions
% ════════════════════════════════════════════════════════════════════════
try
    res = imaging.eelsSVD(noisyCube, E, NumComponents=5);

    assert(isstruct(res), 'Output must be struct');
    assert(isfield(res, 'eigenspectra'),   'Missing eigenspectra');
    assert(isfield(res, 'scoreMaps'),      'Missing scoreMaps');
    assert(isfield(res, 'singularValues'), 'Missing singularValues');
    assert(isfield(res, 'explained'),      'Missing explained');
    assert(isfield(res, 'cumulative'),     'Missing cumulative');
    assert(isfield(res, 'meanSpectrum'),   'Missing meanSpectrum');
    assert(size(res.eigenspectra, 1) == nE,   'eigenspectra rows must match nE');
    assert(size(res.eigenspectra, 2) == 5,    'eigenspectra cols must match NumComponents');
    assert(size(res.scoreMaps, 1) == Ny,      'scoreMaps Ny mismatch');
    assert(size(res.scoreMaps, 2) == Nx,      'scoreMaps Nx mismatch');
    assert(size(res.scoreMaps, 3) == 5,       'scoreMaps k mismatch');
    assert(numel(res.singularValues) == 5,    'singularValues length mismatch');
    assert(numel(res.explained) == 5,         'explained length mismatch');
    assert(numel(res.meanSpectrum) == nE,     'meanSpectrum length mismatch');

    fprintf('  PASS: output structure and dimensions correct\n');
    nPass = nPass + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); nFail = nFail + 1;
end

% ════════════════════════════════════════════════════════════════════════
%  TEST 2: Variance explained sums correctly
% ════════════════════════════════════════════════════════════════════════
try
    res = imaging.eelsSVD(noisyCube, E, NumComponents=min(Ny*Nx, nE));

    % Total explained must be ~100% when all components kept
    assert(abs(res.cumulative(end) - 100) < 0.01, ...
        sprintf('Cumulative should be ~100%%, got %.4f%%', res.cumulative(end)));

    % Explained values must be non-negative and non-increasing
    assert(all(res.explained >= 0), 'Explained values must be non-negative');
    assert(all(diff(res.explained) <= 1e-10), 'Explained must be non-increasing');

    % Cumulative must be monotonically increasing
    assert(all(diff(res.cumulative) >= -1e-10), 'Cumulative must be non-decreasing');

    fprintf('  PASS: variance accounting correct\n');
    nPass = nPass + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); nFail = nFail + 1;
end

% ════════════════════════════════════════════════════════════════════════
%  TEST 3: Rank-2 data should concentrate >99% in first 2 components
% ════════════════════════════════════════════════════════════════════════
try
    res = imaging.eelsSVD(cleanCube, E, NumComponents=5);

    assert(res.cumulative(2) > 99.9, ...
        sprintf('Clean rank-2 cube: top 2 should explain >99.9%%, got %.2f%%', ...
            res.cumulative(2)));

    fprintf('  PASS: rank-2 cube correctly identified (top 2 = %.2f%%)\n', res.cumulative(2));
    nPass = nPass + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); nFail = nFail + 1;
end

% ════════════════════════════════════════════════════════════════════════
%  TEST 4: Eigenspectra span the same subspace as the input components
% ════════════════════════════════════════════════════════════════════════
try
    res = imaging.eelsSVD(cleanCube, E, NumComponents=2);

    % With centering, eigenspectra are the PCs of the mean-subtracted data.
    % They span the same subspace as the original spectra but may be rotated.
    % Verify by projecting original spectra onto the 2-PC subspace and
    % checking that the residual is near zero.
    V2 = res.eigenspectra;  % [nE × 2]
    proj1 = V2 * (V2' * (spec1 - res.meanSpectrum));
    proj2 = V2 * (V2' * (spec2 - res.meanSpectrum));
    residual1 = norm(proj1 - (spec1 - res.meanSpectrum)) / norm(spec1 - res.meanSpectrum);
    residual2 = norm(proj2 - (spec2 - res.meanSpectrum)) / norm(spec2 - res.meanSpectrum);

    assert(residual1 < 0.05, sprintf('spec1 projection residual too large: %.3f', residual1));
    assert(residual2 < 0.05, sprintf('spec2 projection residual too large: %.3f', residual2));

    fprintf('  PASS: eigenspectra span input subspace (residuals: %.4f, %.4f)\n', residual1, residual2);
    nPass = nPass + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); nFail = nFail + 1;
end

% ════════════════════════════════════════════════════════════════════════
%  TEST 5: Denoise reconstruction — rank-2 recovers clean cube
% ════════════════════════════════════════════════════════════════════════
try
    res = imaging.eelsSVD(noisyCube, E, NumComponents=2, Denoise=true);

    assert(~isempty(res.denoisedCube), 'denoisedCube should not be empty');
    assert(isequal(size(res.denoisedCube), [Ny Nx nE]), 'denoisedCube size mismatch');

    % Denoised should be closer to clean than noisy is
    errNoisy = norm(noisyCube(:) - cleanCube(:));
    errDenoised = norm(res.denoisedCube(:) - cleanCube(:));
    assert(errDenoised < errNoisy, ...
        sprintf('Denoised error (%.2f) should be less than noisy (%.2f)', ...
            errDenoised, errNoisy));

    fprintf('  PASS: denoised cube closer to ground truth (%.1f vs %.1f)\n', ...
        errDenoised, errNoisy);
    nPass = nPass + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); nFail = nFail + 1;
end

% ════════════════════════════════════════════════════════════════════════
%  TEST 6: Denoise=false returns empty denoisedCube
% ════════════════════════════════════════════════════════════════════════
try
    res = imaging.eelsSVD(noisyCube, E, NumComponents=3, Denoise=false);
    assert(isempty(res.denoisedCube), 'denoisedCube should be empty when Denoise=false');

    fprintf('  PASS: Denoise=false returns empty denoisedCube\n');
    nPass = nPass + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); nFail = nFail + 1;
end

% ════════════════════════════════════════════════════════════════════════
%  TEST 7: Center=false skips mean subtraction
% ════════════════════════════════════════════════════════════════════════
try
    res = imaging.eelsSVD(noisyCube, E, NumComponents=3, Center=false);
    assert(all(res.meanSpectrum == 0), 'meanSpectrum should be all zeros when Center=false');

    fprintf('  PASS: Center=false produces zero meanSpectrum\n');
    nPass = nPass + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); nFail = nFail + 1;
end

% ════════════════════════════════════════════════════════════════════════
%  TEST 8: Sign convention — deterministic across calls
% ════════════════════════════════════════════════════════════════════════
try
    res1 = imaging.eelsSVD(noisyCube, E, NumComponents=3);
    res2 = imaging.eelsSVD(noisyCube, E, NumComponents=3);

    assert(max(abs(res1.eigenspectra(:) - res2.eigenspectra(:))) < 1e-10, ...
        'Eigenspectra should be identical across calls (sign convention)');
    assert(max(abs(res1.scoreMaps(:) - res2.scoreMaps(:))) < 1e-10, ...
        'Score maps should be identical across calls');

    fprintf('  PASS: sign convention is deterministic\n');
    nPass = nPass + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); nFail = nFail + 1;
end

% ════════════════════════════════════════════════════════════════════════
%  TEST 9: NumComponents=0 defaults to min(20, ...)
% ════════════════════════════════════════════════════════════════════════
try
    res = imaging.eelsSVD(noisyCube, E);  % no NumComponents specified
    expectedK = min(20, min(Ny*Nx, nE));
    assert(size(res.eigenspectra, 2) == expectedK, ...
        sprintf('Default k should be %d, got %d', expectedK, size(res.eigenspectra, 2)));

    fprintf('  PASS: default NumComponents = %d\n', expectedK);
    nPass = nPass + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); nFail = nFail + 1;
end

% ════════════════════════════════════════════════════════════════════════
%  TEST 10: Singular values are positive and non-increasing
% ════════════════════════════════════════════════════════════════════════
try
    res = imaging.eelsSVD(noisyCube, E, NumComponents=10);
    assert(all(res.singularValues > 0), 'Singular values must be positive');
    assert(all(diff(res.singularValues) <= 1e-10), 'Singular values must be non-increasing');

    fprintf('  PASS: singular values positive and sorted\n');
    nPass = nPass + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); nFail = nFail + 1;
end

% ════════════════════════════════════════════════════════════════════════
%  TEST 11: Energy axis size mismatch errors correctly
% ════════════════════════════════════════════════════════════════════════
try
    badE = linspace(200, 600, nE+5)';
    try
        imaging.eelsSVD(noisyCube, badE);
        fprintf('  FAIL: should have errored on size mismatch\n'); nFail = nFail + 1;
    catch ME
        assert(contains(ME.identifier, 'sizeMismatch'), ...
            sprintf('Expected sizeMismatch error, got: %s', ME.identifier));
        fprintf('  PASS: energy axis mismatch caught correctly\n');
        nPass = nPass + 1;
    end
catch ME
    fprintf('  FAIL: %s\n', ME.message); nFail = nFail + 1;
end

% ════════════════════════════════════════════════════════════════════════
%  TEST 12: Single-row cube (Ny=1) works
% ════════════════════════════════════════════════════════════════════════
try
    thinCube = noisyCube(1, :, :);  % [1 × Nx × nE]
    res = imaging.eelsSVD(thinCube, E, NumComponents=3);
    assert(size(res.scoreMaps, 1) == 1, 'Ny should be 1');
    assert(size(res.scoreMaps, 2) == Nx, 'Nx should match');

    fprintf('  PASS: single-row cube (Ny=1) works\n');
    nPass = nPass + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); nFail = nFail + 1;
end

catch ME
    fprintf('  FATAL: %s (line %d)\n', ME.message, ME.stack(1).line);
    nFail = nFail + 1;
end

fprintf('\n=== test_eelsSVD: %d passed, %d failed ===\n', nPass, nFail);
assert(nFail == 0, sprintf('%d test(s) failed', nFail));

% ════════════════════════════════════════════════════════════════════════
%  Local helper: Pearson correlation between two vectors
% ════════════════════════════════════════════════════════════════════════
function r = corrcoef_pair(a, b)
    a = a(:) - mean(a);
    b = b(:) - mean(b);
    r = (a' * b) / (norm(a) * norm(b));
end
