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
%  9. eelsQuantify + eelsAtomicSigma — at% sums to 100, and the propagated
%     Poisson 1-sigma error matches a hand-computed value obtained by
%     re-deriving the trapezoid-weight + delta-method formula independently
%     in this test (guards the eelsQuantify <-> eelsAtomicSigma wiring:
%     right spectrum, right energy subset, right element order).
% ════════════════════════════════════════════════════════════════════════
try
    E = (200:1:900).';
    Abg = 5e7; rbg = 2.5;
    bg  = Abg * E.^(-rbg);

    onsetA = 284; sigWinA = [284 384]; bgWinA = [220 280];
    hA = 4000; pA = 3.0;
    edgeA = zeros(size(E)); mA = E >= onsetA;
    edgeA(mA) = hA * (onsetA ./ E(mA)).^pA;

    onsetB = 532; sigWinB = [532 632]; bgWinB = [470 525];
    hB = 9000; pB = 3.0;
    edgeB = zeros(size(E)); mB = E >= onsetB;
    edgeB(mB) = hB * (onsetB ./ E(mB)).^pB;

    spectrum = bg + edgeA + edgeB;   % GROSS counts — Poisson stats apply here

    el(1) = struct('element','C','shell',"K",'Z',6,'onsetEV',onsetA, ...
                   'signalWindow',sigWinA,'bgWindow',bgWinA);
    el(2) = struct('element','O','shell',"K",'Z',8,'onsetEV',onsetB, ...
                   'signalWindow',sigWinB,'bgWindow',bgWinB);

    r = imaging.eels.eelsQuantify(E, spectrum, el, 200, 10);

    % --- at% sums to 100 ---------------------------------------------------
    assert(abs(sum(r.atomicPercent) - 100) < 1e-6, ...
        sprintf('at%% must sum to 100, got %.6f', sum(r.atomicPercent)));
    assert(isfield(r, 'atomicPercentSigma'), 'result missing atomicPercentSigma field');
    assert(numel(r.atomicPercentSigma) == 2, 'expected 2 atomicPercentSigma entries');
    assert(all(isfinite(r.atomicPercentSigma)) && all(r.atomicPercentSigma > 0), ...
        'atomicPercentSigma must be finite and positive for a well-conditioned system');

    % --- hand-computed expectation: re-derive the SAME weight formula -------
    sigWinAll = [sigWinA; sigWinB];
    M = 2;
    varI = zeros(M, 1);
    for k = 1:M
        mask = E >= sigWinAll(k,1) & E <= sigWinAll(k,2);
        x = E(mask);
        n = numel(x);
        w = zeros(n, 1);
        w(1)       = 0.5 * (x(2)   - x(1));
        w(end)     = 0.5 * (x(end) - x(end-1));
        w(2:end-1) = 0.5 * (x(3:end) - x(1:end-2));
        c = max(spectrum(mask), 0);
        varI(k) = sum(w.^2 .* c);
    end
    varR = varI ./ (r.sigma(:)).^2;
    q = r.arealRatio(:);
    S = sum(q);
    frac = q / S;
    jacMat = (eye(M) - frac) / S;
    varAt = sum((jacMat.^2) .* varR(:)', 2);
    expectedSigma = 100 * sqrt(varAt)';

    relErr = max(abs(r.atomicPercentSigma - expectedSigma) ./ expectedSigma);
    assert(relErr < 1e-9, ...
        sprintf('atomicPercentSigma deviates from hand-computed expectation: got [%s], expected [%s]', ...
            num2str(r.atomicPercentSigma), num2str(expectedSigma)));

    nPass = nPass + 1;
    fprintf('  ✔ Test 9: eelsQuantify+eelsAtomicSigma — at%% sums to 100, sigma matches hand-computed weights\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 9: eelsQuantify+eelsAtomicSigma sigma path: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  10. eelsQuantifyMap — uniform-cube oracle.  A cube whose every pixel
%      holds the SAME spectrum must reproduce eelsQuantify's scalar result
%      to floating-point round-off.
% ════════════════════════════════════════════════════════════════════════
try
    E = (200:1:900).';
    bg = 5e7 * E.^(-2.5);
    edgeA = zeros(size(E)); mA = E >= 284; edgeA(mA) = 4000*(284./E(mA)).^3;
    edgeB = zeros(size(E)); mB = E >= 532; edgeB(mB) = 9000*(532./E(mB)).^3;
    spectrum = bg + edgeA + edgeB;

    el = struct( ...
        'element', {'C','O'}, 'shell', {"K","K"}, 'Z', {6,8}, ...
        'onsetEV', {284,532}, ...
        'signalWindow', {[284 384],[532 632]}, ...
        'bgWindow', {[220 280],[470 525]});

    rScalar = imaging.eels.eelsQuantify(E, spectrum, el, 200, 10);

    Ny = 3; Nx = 4;
    cube = repmat(reshape(spectrum, 1, 1, []), Ny, Nx, 1);
    rMap = imaging.eels.eelsQuantifyMap(cube, E, el, 200, 10);

    for k = 1:2
        atMap = rMap.atomicPercent(:, :, k);
        assert(max(abs(atMap(:) - rScalar.atomicPercent(k))) < 1e-9, ...
            sprintf('eelsQuantifyMap uniform cube: element %d deviates from scalar by %.3e', ...
                k, max(abs(atMap(:) - rScalar.atomicPercent(k)))));
    end

    nPass = nPass + 1;
    fprintf('  ✔ Test 10: eelsQuantifyMap uniform cube — matches eelsQuantify to 1e-9\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 10: eelsQuantifyMap uniform cube: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  11. eelsQuantifyMap — two-region gradient cube.  Left half element-A-rich,
%      right half element-B-rich; also guards against a transpose slip in
%      the [M x Np] <-> [Ny x Nx x M] reshape (Ny != Nx would not by itself
%      catch a transpose, so map(1,1) vs map(1,6) checks the column order
%      directly on a single row).
% ════════════════════════════════════════════════════════════════════════
try
    E = (200:1:900).';
    bg = 5e7 * E.^(-2.5);
    edgeA = zeros(size(E)); mA = E >= 284; edgeA(mA) = 4000*(284./E(mA)).^3;
    edgeB = zeros(size(E)); mB = E >= 532; edgeB(mB) = 9000*(532./E(mB)).^3;

    Ny = 4; Nx = 6; nE = numel(E);
    cube = zeros(Ny, Nx, nE);
    specL = bg + 5.0*edgeA + 0.2*edgeB;     % element-A-rich (left half)
    specR = bg + 0.2*edgeA + 5.0*edgeB;     % element-B-rich (right half)
    cube(:, 1:Nx/2,     :) = repmat(reshape(specL, 1, 1, []), Ny, Nx/2, 1);
    cube(:, Nx/2+1:end, :) = repmat(reshape(specR, 1, 1, []), Ny, Nx/2, 1);

    el = struct( ...
        'element', {'C','O'}, 'shell', {"K","K"}, 'Z', {6,8}, ...
        'onsetEV', {284,532}, ...
        'signalWindow', {[284 384],[532 632]}, ...
        'bgWindow', {[220 280],[470 525]});

    rMap = imaging.eels.eelsQuantifyMap(cube, E, el, 200, 10);
    idxA = find(rMap.element == "C");
    aMap = rMap.atomicPercent(:, :, idxA);

    assert(min(aMap(:, 1:Nx/2), [], 'all') > 60, ...
        sprintf('left (A-rich) half should exceed 60%% A, got min %.1f%%', ...
            min(aMap(:, 1:Nx/2), [], 'all')));
    assert(max(aMap(:, Nx/2+1:end), [], 'all') < 40, ...
        sprintf('right (B-rich) half should be below 40%% A, got max %.1f%%', ...
            max(aMap(:, Nx/2+1:end), [], 'all')));

    % transpose-slip guard
    assert(aMap(1,1) > aMap(1,6), ...
        sprintf('transpose-slip guard failed: map(1,1)=%.2f not > map(1,6)=%.2f', ...
            aMap(1,1), aMap(1,6)));

    nPass = nPass + 1;
    fprintf('  ✔ Test 11: eelsQuantifyMap two-region gradient — A-rich left/right + transpose guard\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 11: eelsQuantifyMap two-region gradient: %s\n', ME.message);
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
