%TEST_EDS_ZETA  Unit tests for zeta-factor (Watanabe-Williams) EDS
%quantification.
%
%   Tests use purely synthetic data (hand-checked arithmetic plus a
%   forward-model self-consistency check for the absorption iteration) so
%   no external files are required.  Each test prints a tick (pass) or
%   cross (fail) with a brief description.
%
%   Functions tested:
%       imaging.eds.zetaQuantify
%       imaging.eds.zetaFromKFactors
%       imaging.eds.doseElectrons (indirectly, via BeamCurrentNA/LiveTimeS)
%
%   Run standalone:  cd tests; run test_eds_zeta
%   Run from root:   run tests/imaging/test_eds_zeta
%       runAllTests(Group="fv")

clear; clc;
fprintf('\n═══ test_eds_zeta ═══\n');

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
%  1. Hand-checked two-element, no-absorption arithmetic:
%     sum(zeta.*I) = 500*2000 + 1000*1000 = 2e6
%     -> w = (0.5, 0.5) exactly, rho*t = 2e6/1e10 = 2e-4 kg/m^2 exactly
% ════════════════════════════════════════════════════════════════════════
try
    r1 = imaging.eds.zetaQuantify([2000 1000], {'Fe','O'}, [500 1000], ...
        DoseElectrons=1e10, Absorption=false);

    assert(abs(r1.meanWeightFrac(1) - 0.5) < 1e-12, ...
        sprintf('Fe weight fraction expected 0.5, got %.15g', r1.meanWeightFrac(1)));
    assert(abs(r1.meanWeightFrac(2) - 0.5) < 1e-12, ...
        sprintf('O weight fraction expected 0.5, got %.15g', r1.meanWeightFrac(2)));
    assert(abs(r1.meanRhoT_kg_m2 - 2.0e-4) / 2.0e-4 < 1e-12, ...
        sprintf('rho*t expected 2e-4, got %.15g', r1.meanRhoT_kg_m2));
    assert(all(r1.absorptionFactors == 1.0), 'Absorption off must give A=1 for every element');
    assert(r1.iterations == 1, 'Absorption off must run exactly one pass');

    nPass = nPass + 1;
    fprintf('  ✔ Test 1: zetaQuantify — hand-checked two-element, no absorption\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 1: zetaQuantify hand-checked: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  2. Composition is dose-independent; mass-thickness is not.
%     Halving the dose must leave weight fractions unchanged and double
%     rho*t.
% ════════════════════════════════════════════════════════════════════════
try
    maps = [3000 1000];
    els  = {'Ni','O'};
    zeta = [800 1200];

    a = imaging.eds.zetaQuantify(maps, els, zeta, DoseElectrons=1e10, Absorption=false);
    b = imaging.eds.zetaQuantify(maps, els, zeta, DoseElectrons=2e10, Absorption=false);

    assert(max(abs(a.meanWeightFrac - b.meanWeightFrac)) < 1e-12, ...
        'Weight fractions must be identical regardless of dose');
    assert(abs(a.meanRhoT_kg_m2 - 2*b.meanRhoT_kg_m2) / a.meanRhoT_kg_m2 < 1e-12, ...
        sprintf('rho*t(dose=1e10) should be 2x rho*t(dose=2e10): got %.6g vs %.6g', ...
        a.meanRhoT_kg_m2, b.meanRhoT_kg_m2));

    nPass = nPass + 1;
    fprintf('  ✔ Test 2: zetaQuantify — composition dose-independent, thickness is not\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 2: zetaQuantify dose independence: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  3. zetaFromKFactors — k_Si = 1.00 exactly reproduces zeta_Si; other
%     elements scale by the built-in 200 kV k-table ratios.
% ════════════════════════════════════════════════════════════════════════
try
    zetaSi = 1000.0;
    els    = {'Si','Fe','Cu'};
    z      = imaging.eds.zetaFromKFactors(els, zetaSi);
    kt     = imaging.eds.edsKFactorTable();

    assert(abs(z(1) - zetaSi) < 1e-9, ...
        sprintf('zeta_Si expected %.4f, got %.4f', zetaSi, z(1)));
    assert(abs(z(2) - zetaSi*kt('Fe')) < 1e-9, ...
        sprintf('zeta_Fe expected %.4f, got %.4f', zetaSi*kt('Fe'), z(2)));
    assert(abs(z(3) - zetaSi*kt('Cu')) < 1e-9, ...
        sprintf('zeta_Cu expected %.4f, got %.4f', zetaSi*kt('Cu'), z(3)));

    % Rejects a non-positive absolute standard
    threw = false;
    try
        imaging.eds.zetaFromKFactors({'Fe'}, 0.0);
    catch
        threw = true;
    end
    assert(threw, 'zetaFromKFactors must reject zetaSi <= 0');

    nPass = nPass + 1;
    fprintf('  ✔ Test 3: zetaFromKFactors — scales the 200 kV k-table from one standard\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 3: zetaFromKFactors: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  4. Absorption iteration: forward-model a thick Fe/Ni sample (softer
%     Fe-Kalpha absorbed harder than Ni-Kalpha), then check:
%       - with absorption ON, the composition/rho*t recover the injected
%         truth and the softer line gets the larger restoring factor
%       - with absorption OFF, Fe (the softer line) reads LOW
%       - absorption ON corrects Fe UPWARD relative to absorption OFF
%       - NIter=0 reproduces the no-absorption closed-form answer exactly
% ════════════════════════════════════════════════════════════════════════
try
    elements   = {'Fe','Ni'};
    wTrue      = [0.5 0.5];
    rhoTtrue   = 2.0e-3;              % kg/m^2
    zeta       = [900 950];
    dose       = 5.0e11;
    takeoffDeg = 20;

    % Forward model built from the SAME production MAC lookup that
    % zetaQuantify itself uses, so the check is self-consistent regardless
    % of the exact mass-absorption-coefficient formula in use.
    n = numel(elements);
    macFwd = zeros(n, n);
    for i = 1:n
        for j = 1:n
            macFwd(i,j) = imaging.eds.massAbsorptionCoeff(elements{i}, elements{j}) * 0.1;
        end
    end
    cscFwd = 1 / sind(takeoffDeg);
    chi    = (macFwd * wTrue') * cscFwd;      % [n x 1]
    x      = chi * rhoTtrue;                  % [n x 1]
    fAbs   = (1 - exp(-x)) ./ x;               % thin-film absorption factor <= 1
    iGen   = (wTrue .* rhoTtrue .* dose) ./ zeta;
    iMeas  = iGen .* fAbs';                    % [1 x n] measured intensities

    rOn = imaging.eds.zetaQuantify(iMeas, elements, zeta, DoseElectrons=dose, ...
        TakeoffDeg=takeoffDeg, Absorption=true, NIter=10);

    assert(max(abs(rOn.meanWeightFrac - wTrue)) / max(wTrue) < 2e-3, ...
        sprintf('Absorption-corrected weight fractions should recover truth: got [%.4f %.4f]', ...
        rOn.meanWeightFrac(1), rOn.meanWeightFrac(2)));
    assert(abs(rOn.meanRhoT_kg_m2 - rhoTtrue) / rhoTtrue < 2e-3, ...
        sprintf('Absorption-corrected rho*t should recover truth: got %.6g vs %.6g', ...
        rOn.meanRhoT_kg_m2, rhoTtrue));
    assert(rOn.absorptionFactors(1) > rOn.absorptionFactors(2), ...
        'Softer Fe-Kalpha must get a larger absorption factor than Ni-Kalpha');
    assert(rOn.absorptionFactors(2) > 1.0, ...
        'Even the harder Ni-Kalpha line should need some restoring factor on a thick sample');

    rOff = imaging.eds.zetaQuantify(iMeas, elements, zeta, DoseElectrons=dose, ...
        TakeoffDeg=takeoffDeg, Absorption=false);

    assert(rOff.meanWeightFrac(1) < 0.5, ...
        sprintf('Ignoring absorption should bias the softer Fe line low: got %.4f', ...
        rOff.meanWeightFrac(1)));
    assert(rOff.meanRhoT_kg_m2 < rhoTtrue, ...
        sprintf('Ignoring absorption should bias rho*t low: got %.6g vs %.6g', ...
        rOff.meanRhoT_kg_m2, rhoTtrue));

    % Direction check: turning absorption ON must correct the softer Fe
    % line UPWARD relative to leaving it OFF.
    assert(rOn.meanWeightFrac(1) > rOff.meanWeightFrac(1), ...
        sprintf('Absorption ON must correct Fe upward vs OFF: on=%.4f, off=%.4f', ...
        rOn.meanWeightFrac(1), rOff.meanWeightFrac(1)));

    % NIter=0 must reproduce the no-absorption closed-form answer exactly.
    rZero = imaging.eds.zetaQuantify(iMeas, elements, zeta, DoseElectrons=dose, ...
        TakeoffDeg=takeoffDeg, Absorption=true, NIter=0);

    assert(max(abs(rZero.meanWeightFrac - rOff.meanWeightFrac)) < 1e-12, ...
        'NIter=0 must reproduce the no-absorption closed-form weight fractions');
    assert(abs(rZero.meanRhoT_kg_m2 - rOff.meanRhoT_kg_m2) / rOff.meanRhoT_kg_m2 < 1e-12, ...
        'NIter=0 must reproduce the no-absorption closed-form rho*t');
    assert(rZero.iterations == 1, 'NIter=0 must run exactly one pass');

    nPass = nPass + 1;
    fprintf('  ✔ Test 4: zetaQuantify — absorption iteration corrects the softer line upward\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 4: zetaQuantify absorption iteration: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  5. Map-shaped inputs: a uniform [2 x 2 x 2] cube must reproduce the
%     scalar answer at every pixel, to 1e-12.
% ════════════════════════════════════════════════════════════════════════
try
    feMap = ones(2,2) * 2000;
    oMap  = ones(2,2) * 1000;
    cube  = cat(3, feMap, oMap);   % [2 x 2 x 2]

    rMap = imaging.eds.zetaQuantify(cube, {'Fe','O'}, [500 1000], ...
        DoseElectrons=1e10, Absorption=false);

    assert(isequal(size(rMap.weightFrac), [2 2 2]), 'weightFrac must be [2x2x2]');
    assert(all(abs(rMap.weightFrac(:,:,1) - 0.5) < 1e-12, 'all'), ...
        'Fe weight fraction must be 0.5 at every pixel');
    assert(all(abs(rMap.weightFrac(:,:,2) - 0.5) < 1e-12, 'all'), ...
        'O weight fraction must be 0.5 at every pixel');
    assert(all(abs(rMap.rhoT_kg_m2 - 2.0e-4) / 2.0e-4 < 1e-12, 'all'), ...
        'rho*t must be 2e-4 kg/m^2 at every pixel');

    % Cross-check against the scalar answer from Test 1
    assert(abs(rMap.meanWeightFrac(1) - r1.meanWeightFrac(1)) < 1e-12, ...
        'Map-mean weight fraction must match the scalar-input answer');
    assert(abs(rMap.meanRhoT_kg_m2 - r1.meanRhoT_kg_m2) / r1.meanRhoT_kg_m2 < 1e-12, ...
        'Map-mean rho*t must match the scalar-input answer');

    nPass = nPass + 1;
    fprintf('  ✔ Test 5: zetaQuantify — map-shaped cube reproduces scalar answer per pixel\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 5: zetaQuantify map inputs: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════

catch fatalErr
    fprintf('  ✘ FATAL error in test harness: %s\n', fatalErr.message);
    nFail = nFail + 1;
end

% ── Summary ──────────────────────────────────────────────────────────────
fprintf('\n═══ Results: %d passed, %d failed ═══\n\n', nPass, nFail);

if nFail > 0
    error('test_eds_zeta:failures', '%d test(s) failed.', nFail);
end
