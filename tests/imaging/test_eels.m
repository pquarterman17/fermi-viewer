%TEST_EELS  Unit tests for EELS imaging utilities.
%
%   Tests use purely synthetic data so no external DM3 files are required.
%   Each test prints a tick (pass), cross (fail), or dash (skip) with a
%   brief description.
%
%   Run standalone:  cd tests; run test_eels
%   Run from root:   run tests/test_eels
%       runAllTests(Group="eels")

clear; clc;
fprintf('\n═══ test_eels ═══\n');

% Ensure toolbox is on the path
thisDir = fileparts(mfilename('fullpath'));
rootDir = fileparts(fileparts(thisDir));
if ~contains(path, rootDir)
    addpath(rootDir);
end

nPass = 0;
nFail = 0;
nSkip = 0;

try  % outer guard — keeps runner from hanging on unexpected errors

% ════════════════════════════════════════════════════════════════════════
%  1. eelsEdgeTable — returns non-empty struct array with expected fields
%     and contains C-K at 284 eV and Fe-L23 at 708 eV
% ════════════════════════════════════════════════════════════════════════
try
    edges = imaging.eels.eelsEdgeTable();

    assert(isstruct(edges),       'Return value must be a struct');
    assert(numel(edges) > 0,      'Table must be non-empty');

    % Required fields
    assert(isfield(edges, 'element'), 'Missing field: element');
    assert(isfield(edges, 'edge'),    'Missing field: edge');
    assert(isfield(edges, 'onsetEV'), 'Missing field: onsetEV');
    assert(isfield(edges, 'symbol'),  'Missing field: symbol');
    assert(isfield(edges, 'Z'),       'Missing field: Z');

    % C-K at 284 eV
    ckIdx = strcmp({edges.symbol}, 'C-K');
    assert(any(ckIdx), 'C-K edge not found');
    assert(edges(ckIdx).onsetEV == 284, ...
        sprintf('C-K onset expected 284 eV, got %d', edges(ckIdx).onsetEV));
    assert(edges(ckIdx).Z == 6, 'C-K atomic number should be 6');

    % Fe-L23 at 708 eV
    feIdx = strcmp({edges.symbol}, 'Fe-L23');
    assert(any(feIdx), 'Fe-L23 edge not found');
    assert(edges(feIdx).onsetEV == 708, ...
        sprintf('Fe-L23 onset expected 708 eV, got %d', edges(feIdx).onsetEV));
    assert(edges(feIdx).Z == 26, 'Fe-L23 atomic number should be 26');

    nPass = nPass + 1;
    fprintf('  ✔ Test 1: eelsEdgeTable — fields, C-K, Fe-L23\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 1: eelsEdgeTable: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  2. eelsBackground powerlaw — synthetic Fe-L23 spectrum
%     BG = A*E^(-r), edge = Gaussian at 708 eV.
%     After subtraction, signal should isolate the peak region.
% ════════════════════════════════════════════════════════════════════════
try
    rng(1);
    E        = (200:0.5:1000)';
    bg_true  = 1e10 * E .^ (-2.5);
    peak     = 1000 * exp(-((E - 708).^2) / (2*15^2));
    spectrum = bg_true + peak + 0.01 * randn(size(E));

    % Pre-edge fit window well below Fe-L23
    [sig, bg, params] = imaging.eels.eelsBackground(E, spectrum, FitWindow=[400, 580]);

    % Fitted params must be physically reasonable
    assert(params.A > 0, 'Power-law A should be positive');
    assert(params.r > 0, 'Power-law r should be positive (EELS BG decays)');

    % Signal at the edge should be substantially positive
    peakMask = E >= 690 & E <= 730;
    assert(mean(sig(peakMask)) > 50, ...
        'Signal at Fe-L23 peak too small after BG subtraction');

    % Signal in pre-edge region should be near zero
    preMask = E >= 620 & E <= 670;
    assert(mean(sig(preMask)) < 50, ...
        'Pre-edge signal too large (background over-subtraction)');

    nPass = nPass + 1;
    fprintf('  ✔ Test 2: eelsBackground powerlaw — Fe-L23 synthetic\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 2: eelsBackground powerlaw: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  3. eelsBackground exponential — same spectrum, exponential model
% ════════════════════════════════════════════════════════════════════════
try
    rng(2);
    E        = (400:0.5:900)';
    bg_true  = 5000 * exp(-0.003 * E);
    peak     = 800 * exp(-((E - 708).^2) / (2*15^2));
    spectrum = bg_true + peak + 0.01 * randn(size(E));

    [sig, ~, params] = imaging.eels.eelsBackground(E, spectrum, ...
        FitWindow=[600, 680], Method='exponential');

    assert(params.A > 0, 'Exponential A should be positive');
    assert(isfield(params, 'b'), 'params should have field b for exponential');

    peakMask = E >= 690 & E <= 730;
    assert(mean(sig(peakMask)) > 50, ...
        'Signal at Fe-L23 peak too small (exponential BG)');

    nPass = nPass + 1;
    fprintf('  ✔ Test 3: eelsBackground exponential — synthetic\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 3: eelsBackground exponential: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  4. eelsThicknessMap — cube where ZLP counts = C0 and total = C0*e
%     Expected t/lambda = ln(e) = 1.0 for all valid pixels
% ════════════════════════════════════════════════════════════════════════
try
    Ny = 8; Nx = 8; nE = 200;
    E  = linspace(-10, 100, nE)';
    C0 = 1000;  % ZLP counts per pixel

    % All energy channels: ZLP window [-5,5] has counts C0
    % Total integral is C0 * e  →  t/lambda = ln(C0*e / C0) = 1
    cube = zeros(Ny, Nx, nE);

    zlpMask  = E >= -5 & E <= 5;
    nZLP     = sum(zlpMask);
    nTotal   = nE;

    % Per-channel ZLP intensity so that sum over ZLP window = C0
    zlpVal  = C0 / nZLP;
    % Per-channel outside-ZLP intensity so that total sum = C0 * exp(1)
    % total = C0 + (nTotal - nZLP) * extraVal = C0 * exp(1)
    extraVal = (C0 * exp(1) - C0) / (nTotal - nZLP);

    cube(:, :, :) = extraVal;                   % all channels get base value
    for k = 1:nE
        if zlpMask(k)
            cube(:, :, k) = zlpVal;             % ZLP channels get higher value
        end
    end

    [tMap, mask] = imaging.eels.eelsThicknessMap(cube, E, ZLPWindow=[-5, 5]);

    assert(all(mask(:)), 'All pixels should be valid for this synthetic cube');
    tol = 0.05;
    assert(max(abs(tMap(:) - 1.0)) < tol, ...
        sprintf('t/lambda should be ~1.0; max error = %.4f', max(abs(tMap(:) - 1.0))));

    nPass = nPass + 1;
    fprintf('  ✔ Test 4: eelsThicknessMap — t/lambda ≈ 1.0\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 4: eelsThicknessMap: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  5. eelsAlignZLP — cube with known integer shifts, verify recovery
% ════════════════════════════════════════════════════════════════════════
try
    Ny = 4; Nx = 4; nE = 100;
    E  = linspace(-20, 80, nE)';

    % Base ZLP: Gaussian centred at channel 25 (E ~ -8 eV)
    baseZLP = exp(-((1:nE) - 25).^2 / (2*4^2));

    % Build cube: first half of pixels shifted by +3, second half by -2
    cube = zeros(Ny, Nx, nE);
    expectedShifts = zeros(Ny, Nx);

    for row = 1:Ny
        for col = 1:Nx
            if row <= 2
                s = +3;
            else
                s = -2;
            end
            cube(row, col, :) = circshift(baseZLP, s);
            expectedShifts(row, col) = s;
        end
    end

    [~, shifts] = imaging.eels.eelsAlignZLP(cube, E, Window=[-20, 20]);

    % Shifts should recover the applied offsets.
    % The function returns the correction shift (opposite sign from the
    % circshift applied), so aligned = original aligned to mean.
    % Accept if: the relative shifts between pixels match within ±1 channel.
    shiftDiff = shifts(1,1) - shifts(3,1);   % should equal (+3) - (-2) = 5
    assert(abs(abs(shiftDiff) - 5) <= 2, ...
        sprintf('Shift difference expected ±5, got %d', shiftDiff));

    assert(isequal(size(shifts), [Ny, Nx]), 'shifts size mismatch');

    nPass = nPass + 1;
    fprintf('  ✔ Test 5: eelsAlignZLP — shift recovery\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 5: eelsAlignZLP: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  6. eelsExtractMap no background — verify map ≈ sum of channels in window
% ════════════════════════════════════════════════════════════════════════
try
    Ny = 6; Nx = 6; nE = 300;
    E  = linspace(0, 1000, nE)';

    % Constant cube: every pixel has value 10 at every channel
    cube = repmat(reshape(ones(nE,1)*10, [1 1 nE]), [Ny Nx 1]);

    sigWin = [700, 750];
    map    = imaging.eels.eelsExtractMap(cube, E, sigWin);

    % Number of channels in window
    nChan = sum(E >= sigWin(1) & E <= sigWin(2));
    expectedVal = 10 * nChan;

    assert(isequal(size(map), [Ny Nx]), 'map size mismatch');
    assert(max(abs(map(:) - expectedVal)) < 1, ...
        sprintf('Expected map value %.1f, got range [%.1f, %.1f]', ...
        expectedVal, min(map(:)), max(map(:))));

    nPass = nPass + 1;
    fprintf('  ✔ Test 6: eelsExtractMap no background — channel sum\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 6: eelsExtractMap no background: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  7. eelsExtractMap with background — power-law BG + Fe-L23 edge
%     Verify edge map captures ~expected edge signal
% ════════════════════════════════════════════════════════════════════════
try
    Ny = 5; Nx = 10; nE = 500;
    E    = linspace(200, 1000, nE)';

    bgSpec   = 1e10 * E .^ (-2.5);
    peakSpec = 600 * exp(-((E - 708).^2) / (2*15^2));

    % First 5 cols: BG + peak; last 5 cols: BG only
    cube = zeros(Ny, Nx, nE);
    for row = 1:Ny
        for col = 1:5
            cube(row, col, :) = bgSpec + peakSpec;
        end
        for col = 6:10
            cube(row, col, :) = bgSpec;
        end
    end

    bgWin  = [650, 695];
    sigWin = [700, 750];
    map    = imaging.eels.eelsExtractMap(cube, E, sigWin, BackgroundWindow=bgWin);

    assert(isequal(size(map), [Ny Nx]), 'map size mismatch');

    % Columns with edge should have larger map values than columns without
    meanSignal = mean(mean(map(:, 1:5)));
    meanNoise  = mean(mean(map(:, 6:10)));
    assert(meanSignal > meanNoise + 1, ...
        sprintf('Signal cols (%.1f) should be >> noise cols (%.1f)', ...
        meanSignal, meanNoise));

    nPass = nPass + 1;
    fprintf('  ✔ Test 7: eelsExtractMap with background — edge vs no-edge\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 7: eelsExtractMap with background: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  8. importDM3 2D backward compatibility — skip if no test file present
% ════════════════════════════════════════════════════════════════════════
try
    % Look for any .dm3 or .dm4 file in data/ or test_datasets/
    testDirs = {fullfile(rootDir, 'data'), ...
                fullfile(rootDir, '+test_datasets')};
    dmFile = '';
    for d = 1:numel(testDirs)
        candidates = dir(fullfile(testDirs{d}, '**', '*.dm3'));
        if isempty(candidates)
            candidates = dir(fullfile(testDirs{d}, '**', '*.dm4'));
        end
        if ~isempty(candidates)
            dmFile = fullfile(candidates(1).folder, candidates(1).name);
            break;
        end
    end

    if isempty(dmFile)
        nSkip = nSkip + 1;
        fprintf('  - Test 8: importDM3 2D backward compat — SKIP (no test DM3 file found)\n');
    else
        data = parser.importDM3(dmFile);
        assert(isstruct(data),              'importDM3 must return a struct');
        assert(isfield(data, 'time'),       'Missing field: time');
        assert(isfield(data, 'values'),     'Missing field: values');
        assert(isfield(data, 'labels'),     'Missing field: labels');
        assert(isfield(data, 'units'),      'Missing field: units');
        assert(isfield(data, 'metadata'),   'Missing field: metadata');

        nPass = nPass + 1;
        fprintf('  ✔ Test 8: importDM3 2D backward compat — struct contract\n');
    end
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 8: importDM3 2D backward compat: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  9. eelsAlignZLP SubPixel — recovers a synthetic fractional shift to
%     within 0.1 channel; the integer path (SubPixel=false, default)
%     rounds to the nearest whole channel and stays int32.
% ════════════════════════════════════════════════════════════════════════
try
    nE  = 200;
    E   = linspace(-20, 80, nE)';
    c0  = 80;           % base peak channel, well clear of the array edges
    sig = 5;
    trueShift = 2.3;    % channels, fractional

    gauss = @(c) exp(-((1:nE) - c).^2 / (2*sig^2))';

    refSpec = gauss(c0);
    cube = zeros(1, 2, nE);
    cube(1, 1, :) = refSpec;                 % pixel 1: unshifted (= reference)
    cube(1, 2, :) = gauss(c0 + trueShift);   % pixel 2: shifted +2.3 channels

    % Default (integer) path — rounds to the nearest whole channel
    [~, shiftsInt] = imaging.eels.eelsAlignZLP(cube, E, ...
        Window=[-20, 80], Reference=refSpec);
    assert(isa(shiftsInt, 'int32'), 'default shifts must remain int32');
    assert(shiftsInt(1,1) == 0, 'reference pixel should have zero integer shift');
    assert(shiftsInt(1,2) == -round(trueShift), ...
        sprintf('integer shift should round to %d, got %d', ...
        -round(trueShift), shiftsInt(1,2)));

    % Sub-pixel path — recovers the fractional shift to within 0.1 channel
    [~, shiftsSub] = imaging.eels.eelsAlignZLP(cube, E, ...
        Window=[-20, 80], Reference=refSpec, SubPixel=true);
    assert(isa(shiftsSub, 'double'), 'SubPixel shifts must be double');
    assert(abs(shiftsSub(1,2) - (-trueShift)) < 0.1, ...
        sprintf('sub-pixel shift should recover %.2f, got %.4f', ...
        -trueShift, shiftsSub(1,2)));

    nPass = nPass + 1;
    fprintf('  ✔ Test 9: eelsAlignZLP SubPixel — recovers %.2f-channel shift\n', trueShift);
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 9: eelsAlignZLP SubPixel: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  10. eelsSVD — deterministic sign convention: the largest-magnitude
%      element of each eigenspectrum is positive, and the denoised
%      reconstruction is unaffected by the flip.
% ════════════════════════════════════════════════════════════════════════
try
    Ny = 6; Nx = 6; nE = 80;
    E     = linspace(100, 500, nE)';
    spec1 = exp(-((E - 200).^2) / (2*20^2));
    spec2 = exp(-((E - 350).^2) / (2*25^2));

    [yy, xx] = ndgrid(linspace(0,1,Ny), linspace(0,1,Nx));
    cube = zeros(Ny, Nx, nE);
    for iy = 1:Ny
        for ix = 1:Nx
            % Mixed-sign combination so the raw SVD sign is not already
            % guaranteed positive at the largest-magnitude entry.
            cube(iy,ix,:) = (1+yy(iy,ix))*spec1 - (1+xx(iy,ix))*spec2;
        end
    end

    res = imaging.eels.eelsSVD(cube, E, NumComponents=4, Denoise=true);

    k = size(res.eigenspectra, 2);
    for j = 1:k
        [~, idx] = max(abs(res.eigenspectra(:,j)));
        assert(res.eigenspectra(idx, j) > 0, ...
            sprintf('component %d: largest-magnitude element is not positive', j));
    end

    errRel = norm(res.denoisedCube(:) - cube(:)) / norm(cube(:));
    assert(errRel < 1e-8, ...
        sprintf('denoised reconstruction changed by the sign flip, relErr=%.2e', errRel));

    nPass = nPass + 1;
    fprintf('  ✔ Test 10: eelsSVD — sign convention deterministic, reconstruction intact\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 10: eelsSVD sign convention: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  11. eelsKramersKronig — with no RefractiveIndex supplied, the
%      peak-normalisation fallback keeps eps1/eps2 finite and flags
%      isNormalized = false; supplying a valid RefractiveIndex flips it
%      back to true (sum-rule normalisation).
% ════════════════════════════════════════════════════════════════════════
try
    nE  = 256;
    E   = linspace(0.5, 40, nE)';
    Ep  = 15; gam = 2;
    ELF = (gam*E) ./ ((E.^2 - Ep^2).^2 + (gam*E).^2);
    ELF = max(ELF, 0);

    res = imaging.eels.eelsKramersKronig(E, ELF);   % RefractiveIndex defaults to NaN

    assert(isfield(res, 'isNormalized'), 'Missing field: isNormalized');
    assert(res.isNormalized == false, ...
        'isNormalized should be false when no RefractiveIndex is supplied');
    assert(all(isfinite(res.eps1)) && all(isfinite(res.eps2)), ...
        'eps1/eps2 must be finite under the peak-normalisation fallback');

    resN = imaging.eels.eelsKramersKronig(E, ELF, RefractiveIndex=1.5);
    assert(resN.isNormalized == true, ...
        'isNormalized should be true when a valid RefractiveIndex is supplied');

    nPass = nPass + 1;
    fprintf('  ✔ Test 11: eelsKramersKronig — unnormalised fallback flagged, eps finite\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 11: eelsKramersKronig unnormalised: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  12. eelsFourierLog — t/lambda = ln(sum(spectrum)/sum(zlp)) on a
%      synthetic ZLP + plasmon spectrum; the phase-preserving
%      regularisation must not disturb the thickness estimate.
% ════════════════════════════════════════════════════════════════════════
try
    nE  = 512;
    E   = linspace(-5, 100, nE)';
    zlp      = 1000 * exp(-E.^2 / (2*1.0^2));
    plasmon  = 300  * exp(-((E - 15).^2) / (2*4^2));
    spectrum = zlp + plasmon;

    zlpMask  = E >= -5 & E <= 5;
    expected = log(sum(spectrum) / sum(spectrum(zlpMask)));

    [ssd, tOverLambda] = imaging.eels.eelsFourierLog(E, spectrum, ZLPWindow=[-5, 5]);

    assert(abs(tOverLambda - expected) < 1e-9, ...
        sprintf('t/lambda = %.6f, expected %.6f', tOverLambda, expected));
    assert(numel(ssd) == nE, 'ssd size mismatch');
    assert(all(ssd >= 0), 'ssd must be non-negative');

    nPass = nPass + 1;
    fprintf('  ✔ Test 12: eelsFourierLog — t/lambda = %.4f matches ln(I_t/I_0)\n', tOverLambda);
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 12: eelsFourierLog t/lambda: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════

catch fatalErr
    fprintf('  ✘ FATAL error in test harness: %s\n', fatalErr.message);
    nFail = nFail + 1;
end

% ── Summary ──────────────────────────────────────────────────────────────
fprintf('\n═══ Results: %d passed, %d failed, %d skipped ═══\n\n', ...
    nPass, nFail, nSkip);

if nFail > 0
    error('test_eels:failures', '%d test(s) failed.', nFail);
end
