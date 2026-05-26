%TEST_EELSQUANTIFICATION  Unit tests for EELS quantitative composition.
%
%   Tests use purely synthetic data so no external files are required.
%   Each test prints a tick (pass) or cross (fail) with a brief description.
%
%   Functions tested:
%       imaging.eels.eelsCrossSection   (hydrogenic SIGMAK2/SIGMAL2 model)
%       imaging.eels.eelsQuantify       (at% from edge intensities)
%
%   Run standalone:  cd tests; run test_eelsQuantification
%   Run from root:   run tests/imaging/test_eelsQuantification
%       runAllTests(Group="edsquant")   % (after registration)

clear; clc;
fprintf('\n═══ test_eelsQuantification ═══\n');

% Ensure toolbox is on the path
thisDir = fileparts(mfilename('fullpath'));
rootDir = fileparts(fileparts(thisDir));
if ~contains(path, rootDir)
    addpath(rootDir);
end

nPass = 0;
nFail = 0;

try  % outer guard — keeps runner from hanging on unexpected errors

% ════════════════════════════════════════════════════════════════════════
%  1. eelsCrossSection — positive, finite, reasonable magnitude for C-K
%     at 100 keV and 200 keV.  K-shell partial cross-sections are ~1e-24
%     to ~1e-22 m^2 (Egerton 2011, hydrogenic SIGMAK2).
% ════════════════════════════════════════════════════════════════════════
try
    sC100 = imaging.eels.eelsCrossSection(6, "K", 100, 10, 100, 284);
    sC200 = imaging.eels.eelsCrossSection(6, "K", 200, 10, 100, 284);

    assert(isfinite(sC100) && isfinite(sC200), 'sigma must be finite');
    assert(sC100 > 0 && sC200 > 0, 'sigma must be positive');

    % Order of magnitude: 1e-25 .. 1e-21 m^2 (generous band around 1e-23..-22)
    assert(sC100 > 1e-25 && sC100 < 1e-21, ...
        sprintf('C-K 100 keV sigma out of band: %.3e m^2', sC100));
    assert(sC200 > 1e-25 && sC200 < 1e-21, ...
        sprintf('C-K 200 keV sigma out of band: %.3e m^2', sC200));

    nPass = nPass + 1;
    fprintf('  ✔ Test 1: eelsCrossSection — C-K finite & order-of-magnitude (100/200 keV)\n');
    fprintf('      sigma(C-K,100kV)=%.3e  sigma(C-K,200kV)=%.3e m^2\n', sC100, sC200);
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 1: eelsCrossSection magnitude: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  2. Monotonic trends:
%       (a) sigma increases with integration window Delta (more states).
%       (b) sigma for a higher-Z/higher-onset K edge (O-K, Z=8, 532 eV)
%           is smaller than C-K under identical conditions (1/E, 1/onset
%           scaling of the hydrogenic GOS).
%       (c) sigma increases with collection angle beta (ln(beta) aperture
%           dependence).
% ════════════════════════════════════════════════════════════════════════
try
    sSmallDelta = imaging.eels.eelsCrossSection(6, "K", 200, 10, 50,  284);
    sLargeDelta = imaging.eels.eelsCrossSection(6, "K", 200, 10, 150, 284);
    assert(sLargeDelta > sSmallDelta, ...
        sprintf('sigma should grow with Delta (%.3e !> %.3e)', sLargeDelta, sSmallDelta));

    sC = imaging.eels.eelsCrossSection(6, "K", 200, 10, 100, 284);
    sO = imaging.eels.eelsCrossSection(8, "K", 200, 10, 100, 532);
    assert(sO < sC, ...
        sprintf('O-K should be smaller than C-K (%.3e !< %.3e)', sO, sC));

    sBetaSmall = imaging.eels.eelsCrossSection(6, "K", 200, 5,  100, 284);
    sBetaLarge = imaging.eels.eelsCrossSection(6, "K", 200, 20, 100, 284);
    assert(sBetaLarge > sBetaSmall, ...
        sprintf('sigma should grow with beta (%.3e !> %.3e)', sBetaLarge, sBetaSmall));

    nPass = nPass + 1;
    fprintf('  ✔ Test 2: eelsCrossSection — monotonic in Delta, Z/onset, beta\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 2: eelsCrossSection trends: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  3. eelsQuantify — synthetic two-element spectrum with KNOWN intensities.
%
%     Build a power-law background plus two "edges". Each edge is a sharp
%     step at onset followed by a decaying tail, riding on top of the
%     background.  We construct the edges so the TRUE background-subtracted
%     integrated intensity over each signal window is a known value
%     (I_A_true, I_B_true).  Then the expected at% follows from
%        r_X = I_X / sigma_X  ->  at%_A = 100 r_A/(r_A+r_B).
%
%     Because the background subtraction recovers the planted edge intensity
%     (the background is an exact power law inside the fit window), the
%     recovered I_X should match the planted I_X well, and the recovered at%
%     should match the expected at% computed from the SAME sigma values.
% ════════════════════════════════════════════════════════════════════════
try
    % --- energy axis ---
    E = (200:1:900).';            % eV, 1 eV channels

    % --- power-law background: bg = A * E^(-r) ---
    Abg = 5e7; rbg = 2.5;
    bg  = Abg * E.^(-rbg);

    % --- element A: C-K at 284 eV ---
    onsetA = 284;  sigWinA = [284 384];  bgWinA = [220 280];
    % planted edge A: hydrogenic-like decaying tail above onset
    %   edgeA(E) = hA * (onsetA/E)^pA for E >= onsetA, else 0
    hA = 4000; pA = 3.0;
    edgeA = zeros(size(E));
    mA = E >= onsetA;
    edgeA(mA) = hA * (onsetA ./ E(mA)).^pA;

    % --- element B: O-K at 532 eV ---
    onsetB = 532;  sigWinB = [532 632];  bgWinB = [470 525];
    hB = 9000; pB = 3.0;
    edgeB = zeros(size(E));
    mB = E >= onsetB;
    edgeB(mB) = hB * (onsetB ./ E(mB)).^pB;

    % NOTE: element B sits on top of background + tail of A. The power-law
    % background fit for B in its pre-edge window [470 525] will absorb the
    % smooth (background + A-tail) continuum, so the recovered B signal is
    % the planted edgeB. For A, its pre-edge window [220 280] sees only the
    % background, so recovered A signal is planted edgeA. This is exactly the
    % standard EELS workflow (each edge gets its own local pre-edge fit).

    spectrum = bg + edgeA + edgeB;

    % --- true planted integrated intensities over the signal windows -------
    iaMask = E >= sigWinA(1) & E <= sigWinA(2);
    ibMask = E >= sigWinB(1) & E <= sigWinB(2);
    IA_true = trapz(E(iaMask), edgeA(iaMask));
    IB_true = trapz(E(ibMask), edgeB(ibMask));

    % --- elements struct ---
    el(1) = struct('element','C','shell',"K",'Z',6,'onsetEV',onsetA, ...
                   'signalWindow',sigWinA,'bgWindow',bgWinA);
    el(2) = struct('element','O','shell',"K",'Z',8,'onsetEV',onsetB, ...
                   'signalWindow',sigWinB,'bgWindow',bgWinB);

    r = imaging.eels.eelsQuantify(E, spectrum, el, 200, 10);

    % --- expected at% from planted intensities and the model sigmas --------
    sA = imaging.eels.eelsCrossSection(6, "K", 200, 10, diff(sigWinA), onsetA);
    sB = imaging.eels.eelsCrossSection(8, "K", 200, 10, diff(sigWinB), onsetB);
    rA = IA_true / sA;
    rB = IB_true / sB;
    expAtPctC = 100 * rA / (rA + rB);
    expAtPctO = 100 * rB / (rA + rB);

    % recovered values
    idxC = find(r.element == "C");
    idxO = find(r.element == "O");
    gotC = r.atomicPercent(idxC);
    gotO = r.atomicPercent(idxO);

    % The recovered intensities should be close to planted (background fit is
    % near-exact in the pre-edge window). Allow a few % for the A-tail under B
    % and discretisation.
    assert(abs(r.intensity(idxC) - IA_true)/IA_true < 0.05, ...
        sprintf('Recovered I_C off: got %.4g, planted %.4g', r.intensity(idxC), IA_true));
    assert(abs(r.intensity(idxO) - IB_true)/IB_true < 0.05, ...
        sprintf('Recovered I_O off: got %.4g, planted %.4g', r.intensity(idxO), IB_true));

    % at% must match expectation within a few absolute percent.
    assert(abs(gotC - expAtPctC) < 3, ...
        sprintf('at%% C: got %.2f, expected %.2f', gotC, expAtPctC));
    assert(abs(gotO - expAtPctO) < 3, ...
        sprintf('at%% O: got %.2f, expected %.2f', gotO, expAtPctO));

    nPass = nPass + 1;
    fprintf('  ✔ Test 3: eelsQuantify — synthetic C/O at%% (%.1f / %.1f, expected %.1f / %.1f)\n', ...
        gotC, gotO, expAtPctC, expAtPctO);
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 3: eelsQuantify synthetic ratio: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  4. eelsQuantify — at% vector sums to 100 and fields well-formed.
% ════════════════════════════════════════════════════════════════════════
try
    E = (200:1:900).';
    bg = 5e7 * E.^(-2.5);
    edgeA = zeros(size(E)); mA = E >= 284; edgeA(mA) = 4000*(284./E(mA)).^3;
    edgeB = zeros(size(E)); mB = E >= 532; edgeB(mB) = 9000*(532./E(mB)).^3;
    spectrum = bg + edgeA + edgeB;

    el(1) = struct('element','C','shell',"K",'Z',6,'onsetEV',284, ...
                   'signalWindow',[284 384],'bgWindow',[220 280]);
    el(2) = struct('element','O','shell',"K",'Z',8,'onsetEV',532, ...
                   'signalWindow',[532 632],'bgWindow',[470 525]);

    r = imaging.eels.eelsQuantify(E, spectrum, el, 200, 10);

    assert(isfield(r,'element') && isfield(r,'atomicPercent') && ...
           isfield(r,'intensity') && isfield(r,'sigma') && ...
           isfield(r,'arealRatio'), 'result missing required fields');
    assert(numel(r.atomicPercent) == 2, 'Expected 2 at%% entries');
    assert(abs(sum(r.atomicPercent) - 100) < 1e-6, ...
        sprintf('at%% must sum to 100, got %.6f', sum(r.atomicPercent)));
    assert(all(r.atomicPercent >= 0), 'at%% must be non-negative');
    assert(all(r.sigma > 0), 'sigma must be positive for all elements');

    nPass = nPass + 1;
    fprintf('  ✔ Test 4: eelsQuantify — at%% sums to 100, fields well-formed\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 4: eelsQuantify sum-to-100: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════

catch fatalErr
    fprintf('  ✘ FATAL error in test harness: %s\n', fatalErr.message);
    nFail = nFail + 1;
end

% ── Summary ──────────────────────────────────────────────────────────────
fprintf('\n═══ Results: %d passed, %d failed ═══\n\n', nPass, nFail);

if nFail > 0
    error('test_eelsQuantification:failures', '%d test(s) failed.', nFail);
end
