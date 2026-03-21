%TEST_EELS_ADVANCED  Unit tests for advanced EELS imaging utilities.
%
%   Tests Fourier-log deconvolution, ELNES extraction, Kramers-Kronig
%   analysis, and pixel-spectrum navigation helpers.
%
%   Run:
%       run tests/test_eels_advanced
%       runAllTests(Group="eels_adv")
%
%   Requires: +imaging/ package (eelsFourierLog, eelsELNES, eelsKramersKronig)
%   All test data is synthetic — no files required.

fprintf('\n');
fprintf('╔══════════════════════════════════════════════════════════════╗\n');
fprintf('║        EELS Advanced — Unit Test Suite                     ║\n');
fprintf('╚══════════════════════════════════════════════════════════════╝\n');

ROOT = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(ROOT);

passed = 0;
failed = 0;

% ── Helper ────────────────────────────────────────────────────────────────
function tf = hasNoNaNInf(v)
    tf = ~any(isnan(v(:))) && ~any(isinf(v(:)));
end

% ── Shared synthetic spectrum parameters ─────────────────────────────────
nE   = 512;
E    = linspace(-5, 100, nE)';      % energy axis (eV)
dE   = E(2) - E(1);

% ZLP: narrow Gaussian at 0 eV, unit area
sigma_zlp = 0.5;  % eV
ZLP = exp(-E.^2 / (2*sigma_zlp^2));
ZLP = ZLP / (sum(ZLP) * dE);

% Plasmon peak at 15 eV (t/lambda ~ 0.4)
sigma_pl  = 3;
t_over_lam = 0.4;
plasmon = t_over_lam * exp(-(E - 15).^2 / (2*sigma_pl^2));
plasmon = plasmon / (sum(plasmon) * dE);

% Convolve ZLP with (ZLP + plasmon) to create measured spectrum with plural scattering
% Simplified: measured = ZLP + plasmon_1st + plasmon_2nd (approx)
p2 = t_over_lam^2 / 2 * exp(-(E - 30).^2 / (2*(sigma_pl*sqrt(2))^2));
p2 = p2 / (sum(p2) * dE);
measured = ZLP + t_over_lam * plasmon + p2 * 0.15;
measured = max(measured, 0);

% ══════════════════════════════════════════════════════════════════════════
fprintf('\nTest 1: eelsFourierLog basic — deconvolution removes plural scattering\n');
try
    [ssd, tl] = imaging.eelsFourierLog(E, measured);

    % ssd must be non-empty and same length
    assert(~isempty(ssd), 'SSD is empty');
    assert(numel(ssd) == numel(measured), 'SSD length mismatch');

    % t/lambda must be positive
    assert(tl > 0, sprintf('t/lambda=%.4f is not positive', tl));

    % The double-plasmon region (around 30 eV) should be reduced in SSD vs measured
    E30_mask = E >= 25 & E <= 35;
    ssd_at_30    = sum(ssd(E30_mask));
    meas_at_30   = sum(measured(E30_mask));
    assert(ssd_at_30 < meas_at_30, ...
        sprintf('Double-plasmon not reduced: SSD=%.4g, measured=%.4g', ssd_at_30, meas_at_30));

    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ══════════════════════════════════════════════════════════════════════════
fprintf('\nTest 2: eelsFourierLog regularization — no NaN/Inf on low-signal input\n');
try
    lowSig = 1e-6 * ones(nE, 1) + 1e-8 * randn(nE, 1);
    lowSig = max(lowSig, 0);
    [ssd2, tl2] = imaging.eelsFourierLog(E, lowSig);

    assert(hasNoNaNInf(ssd2), 'NaN or Inf in SSD output for low-signal input');
    assert(hasNoNaNInf(tl2),  'NaN or Inf in t/lambda for low-signal input');

    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ══════════════════════════════════════════════════════════════════════════
fprintf('\nTest 3: eelsELNES basic — step edge at O-K (532 eV)\n');
try
    % Synthetic O-K edge: power-law BG + step function at 532 eV
    nE2   = 400;
    E2    = linspace(400, 650, nE2)';
    bgAmp = 1e4;
    bgExp = 3.0;
    BG    = bgAmp * (E2 ./ 400) .^ (-bgExp);
    step  = 2000 * double(E2 >= 532);
    spectrum2 = BG + step + 10 * randn(nE2, 1);
    spectrum2 = max(spectrum2, 0);

    % Pre-edge window below edge onset
    fitWin = [420 520];

    res = imaging.eelsELNES(E2, spectrum2, 'EdgeOnset', 532, 'FitWindow', fitWin);

    % Required output fields
    assert(isfield(res, 'relativeEnergy'), 'Missing field: relativeEnergy');
    assert(isfield(res, 'intensity'),      'Missing field: intensity');
    assert(isfield(res, 'edgeJump'),       'Missing field: edgeJump');

    % Relative energy starts near 0
    assert(abs(res.relativeEnergy(1)) < 5, ...
        sprintf('relativeEnergy(1)=%.2f, expected near 0', res.relativeEnergy(1)));

    % Edge jump should be positive and proportional to step height
    assert(res.edgeJump > 0, 'edgeJump is not positive');

    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ══════════════════════════════════════════════════════════════════════════
fprintf('\nTest 4: eelsKramersKronig basic — Drude-like low-loss spectrum\n');
try
    % Synthetic loss function: Lorentzian at 15 eV (plasmon)
    nE3  = 512;
    E3   = linspace(0.1, 50, nE3)';
    Ep   = 15;   % plasmon energy
    gam  = 2;    % damping
    ELF  = (gam * E3) ./ ((E3.^2 - Ep^2).^2 + (gam * E3).^2);
    ELF  = ELF / max(ELF);
    ELF  = max(ELF, 0);

    res = imaging.eelsKramersKronig(E3, ELF);

    % Required output fields
    for fld = {'eps1', 'eps2', 'elf', 'energy', 'opticalConductivity'}
        assert(isfield(res, fld{1}), sprintf('Missing field: %s', fld{1}));
    end

    % eps2 must be > 0 in the plasmon region
    Epl_mask = res.energy >= 12 & res.energy <= 18;
    assert(any(res.eps2(Epl_mask) > 0), ...
        'eps2 not positive in plasmon region');

    % No NaN/Inf
    assert(hasNoNaNInf(res.eps1), 'NaN/Inf in eps1');
    assert(hasNoNaNInf(res.eps2), 'NaN/Inf in eps2');
    assert(hasNoNaNInf(res.opticalConductivity), 'NaN/Inf in opticalConductivity');

    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ══════════════════════════════════════════════════════════════════════════
fprintf('\nTest 5: eelsKramersKronig output size consistency\n');
try
    nE4 = 256;
    E4  = linspace(0.5, 40, nE4)';
    I4  = exp(-(E4 - 12).^2 / (2*2^2));   % simple Gaussian

    res = imaging.eelsKramersKronig(E4, I4);

    n = numel(res.energy);
    assert(numel(res.eps1) == n, 'eps1 length != energy length');
    assert(numel(res.eps2) == n, 'eps2 length != energy length');

    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ══════════════════════════════════════════════════════════════════════════
%  SUMMARY
% ══════════════════════════════════════════════════════════════════════════
fprintf('\n');
fprintf('══════════════════════════════════════════════\n');
fprintf('  EELS Advanced: %d passed, %d failed (of %d)\n', ...
    passed, failed, passed + failed);
fprintf('══════════════════════════════════════════════\n\n');

if failed > 0
    error('test_eels_advanced:failures', ...
        '%d test(s) failed in test_eels_advanced.', failed);
end
