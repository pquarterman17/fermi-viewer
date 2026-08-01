%TEST_EDS_PEAKFIT  EDS constrained peak deconvolution + escape/sum-peak
%   artifact tests: overlapping triplet, error-bar scaling, artifact
%   partition, removal recovery, and quantification cross-check.
%
%   Tests use purely synthetic data (planted Gaussians at known line
%   energies + known areas) so no external files are required.
%
%   Functions tested:
%       imaging.eds.fitPeaks
%       imaging.eds.quantifyPeaks
%       imaging.eds.predictArtifacts
%       imaging.eds.removeArtifacts
%
%   Run standalone:  cd tests/imaging; run test_eds_peakfit
%   Run from root:   run tests/imaging/test_eds_peakfit
%       runAllTests(Group="fv")

clear; clc;
fprintf('\n=== test_eds_peakfit ===\n');

% Ensure toolbox is on the path
thisDir = fileparts(mfilename('fullpath'));
rootDir = fileparts(fileparts(thisDir));
if ~contains(path, rootDir)
    addpath(rootDir);
end

nPass = 0;
nFail = 0;

try  % outer guard -- keeps runner from hanging on unexpected errors

% ════════════════════════════════════════════════════════════════════════
%  1. fitPeaks -- single peak net area recovered
% ════════════════════════════════════════════════════════════════════════
try
    e = linspace(0, 20, 4001);           % 5 eV/channel
    eFe = imaging.eds.lineEnergy('Fe');
    counts = gaussCurve(e, 5000, eFe);

    pf = imaging.eds.fitPeaks(e, counts, {'Fe'}, Weights="uniform");
    assert(approxRel(pf.netArea(1), 5000, 1e-3), ...
        sprintf('single-peak net area off: got %.3f', pf.netArea(1)));

    nPass = nPass + 1;
    fprintf('  Test 1: PASS -- single-peak net area recovered\n');
catch ME
    nFail = nFail + 1;
    fprintf('  Test 1: FAIL -- %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  2. fitPeaks -- two well-separated peaks (Fe, Cu) recovered
% ════════════════════════════════════════════════════════════════════════
try
    e = linspace(0, 20, 4001);
    eFe = imaging.eds.lineEnergy('Fe');
    eCu = imaging.eds.lineEnergy('Cu');
    counts = gaussCurve(e, 4000, eFe) + gaussCurve(e, 6000, eCu);

    pf = imaging.eds.fitPeaks(e, counts, {'Fe', 'Cu'}, Weights="uniform");
    assert(approxRel(pf.netArea(1), 4000, 2e-3), 'Fe net area off');
    assert(approxRel(pf.netArea(2), 6000, 2e-3), 'Cu net area off');

    nPass = nPass + 1;
    fprintf('  Test 2: PASS -- two well-separated peaks (Fe, Cu) recovered\n');
catch ME
    nFail = nFail + 1;
    fprintf('  Test 2: FAIL -- %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  3. fitPeaks -- the S-Ka/Mo-La/Pb-Ma overlapping triplet (~50 eV apart)
%
%     NOTE ON BeamKV: the fermiviewer Python oracle (test_eds_peakfit.py::
%     test_overlapping_triplet_s_mo_pb) calls line_energy(sym, beam_kv=200.0)
%     for S/Mo/Pb, but at 200 kV Mo and Pb are BOTH comfortably excited on
%     their K/L lines (line_energy returns Mo->17.479 keV "K" and
%     Pb->10.551 keV "L", not the L/M lines the test's own comment claims)
%     -- verified directly against the installed fermiviewer package. The
%     Python test still numerically passes, but only because three
%     well-separated single peaks are trivially recovered independently; it
%     is not actually exercising overlap resolution. BeamKV=15 is the
%     voltage window (per the same K->L->M/overvoltage>=1.5 rule, ported
%     from lineEnergy.m into eds.line_energy) where Mo genuinely resolves to
%     La (2.293) and Pb to Ma (2.342), reproducing the genuinely-overlapping
%     triplet the task/comment describes and that window integration cannot
%     separate.
% ════════════════════════════════════════════════════════════════════════
try
    e = linspace(0, 20, 4001);
    beamKV = 15;
    [eS, famS]   = imaging.eds.lineEnergy('S',  BeamKV=beamKV);
    [eMo, famMo] = imaging.eds.lineEnergy('Mo', BeamKV=beamKV);
    [ePb, famPb] = imaging.eds.lineEnergy('Pb', BeamKV=beamKV);
    assert(strcmp(famS, 'K') && strcmp(famMo, 'L') && strcmp(famPb, 'M'), ...
        'expected S-K/Mo-L/Pb-M families at BeamKV=15');
    assert(abs(eS - 2.307) < 1e-6 && abs(eMo - 2.293) < 1e-6 && abs(ePb - 2.342) < 1e-6, ...
        'unexpected line energies for the overlap triplet');

    areasTrue = struct('S', 3000, 'Mo', 5000, 'Pb', 2000);
    counts = gaussCurve(e, areasTrue.S, eS) + gaussCurve(e, areasTrue.Mo, eMo) ...
        + gaussCurve(e, areasTrue.Pb, ePb);

    pf = imaging.eds.fitPeaks(e, counts, {'S', 'Mo', 'Pb'}, BeamKV=beamKV, Weights="uniform");
    assert(approxRel(pf.netArea(1), areasTrue.S, 0.05), ...
        sprintf('S net area off by >5%%: got %.1f', pf.netArea(1)));
    assert(approxRel(pf.netArea(2), areasTrue.Mo, 0.05), ...
        sprintf('Mo net area off by >5%%: got %.1f', pf.netArea(2)));
    assert(approxRel(pf.netArea(3), areasTrue.Pb, 0.05), ...
        sprintf('Pb net area off by >5%%: got %.1f', pf.netArea(3)));

    nPass = nPass + 1;
    fprintf('  Test 3: PASS -- overlapping S-Ka/Mo-La/Pb-Ma triplet recovered within 5%%\n');
catch ME
    nFail = nFail + 1;
    fprintf('  Test 3: FAIL -- %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  4. fitPeaks -- net-area 1-sigma error bars: finite, positive, and grow
%     with plant area roughly like sqrt(area) (counting statistics), using
%     Poisson-weighted fits over a Gaussian approximation to Poisson noise
%     (no Statistics Toolbox: randn + sqrt(counts), not poissrnd)
% ════════════════════════════════════════════════════════════════════════
try
    e = linspace(0, 20, 4001);
    center = imaging.eds.lineEnergy('Fe');
    areasTrue = [1000, 4000, 16000];     % ratios 1:4:16 -> sqrt ratios 1:2:4
    sigmas = zeros(1, numel(areasTrue));

    rng(42);
    for ai = 1:numel(areasTrue)
        clean = gaussCurve(e, areasTrue(ai), center);
        noisy = max(clean + randn(size(clean)) .* sqrt(max(clean, 1)), 0);
        pf = imaging.eds.fitPeaks(e, noisy, {'Fe'}, Weights="poisson");
        assert(isfinite(pf.netAreaSigma(1)) && pf.netAreaSigma(1) > 0, ...
            sprintf('netAreaSigma must be finite and positive (area=%d)', areasTrue(ai)));
        sigmas(ai) = pf.netAreaSigma(1);
    end

    assert(sigmas(2) > sigmas(1) && sigmas(3) > sigmas(2), ...
        'netAreaSigma should grow monotonically with plant area');
    ratio2 = sigmas(2) / sigmas(1);      % expected ~ sqrt(4)  = 2
    ratio3 = sigmas(3) / sigmas(1);      % expected ~ sqrt(16) = 4
    assert(ratio2 > 1.0 && ratio2 < 4.0, ...
        sprintf('sigma(4000)/sigma(1000) = %.2f, not sqrt-like', ratio2));
    assert(ratio3 > 2.0 && ratio3 < 8.0, ...
        sprintf('sigma(16000)/sigma(1000) = %.2f, not sqrt-like', ratio3));

    nPass = nPass + 1;
    fprintf('  Test 4: PASS -- netAreaSigma positive, grows ~sqrt(area) with plant area\n');
catch ME
    nFail = nFail + 1;
    fprintf('  Test 4: FAIL -- %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  5. fitPeaks -- unknown element line warns + NaNs; known line unaffected
% ════════════════════════════════════════════════════════════════════════
try
    e = linspace(0, 20, 4001);
    eFe = imaging.eds.lineEnergy('Fe');
    counts = gaussCurve(e, 3000, eFe);

    warnState = warning('off', 'fitPeaks:noLine');
    cleanupWarn = onCleanup(@() warning(warnState));
    lastwarn('');
    pf = imaging.eds.fitPeaks(e, counts, {'Fe', 'Xx'}, Weights="uniform");
    [~, warnID] = lastwarn();

    assert(strcmp(warnID, 'fitPeaks:noLine'), 'expected fitPeaks:noLine warning');
    assert(isnan(pf.netArea(2)), 'unknown element should get NaN net area');
    assert(approxRel(pf.netArea(1), 3000, 1e-2), 'Fe net area should still be recovered');

    nPass = nPass + 1;
    fprintf('  Test 5: PASS -- unknown line warns + NaNs, known line unaffected\n');
catch ME
    nFail = nFail + 1;
    fprintf('  Test 5: FAIL -- %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  6. predictArtifacts -- Fe+Cu at 20 kV: escape/sum positions (+/-0.001)
%     and the classic Cu-escape-on-Fe-Ka partition
% ════════════════════════════════════════════════════════════════════════
try
    [eFe, ~] = imaging.eds.lineEnergy('Fe', BeamKV=20);
    [eCu, ~] = imaging.eds.lineEnergy('Cu', BeamKV=20);
    arts = imaging.eds.predictArtifacts({'Fe', 'Cu'}, [eFe eCu]);
    names = {arts.name};

    assert(numel(arts) == 5, sprintf('expected 5 artifacts, got %d', numel(arts)));
    iEscFe   = find(strcmp(names, 'esc_Fe'), 1);
    iEscCu   = find(strcmp(names, 'esc_Cu'), 1);
    iSumFeFe = find(strcmp(names, 'sum_Fe_Fe'), 1);
    iSumFeCu = find(strcmp(names, 'sum_Fe_Cu'), 1);
    iSumCuCu = find(strcmp(names, 'sum_Cu_Cu'), 1);
    assert(~isempty(iEscFe) && ~isempty(iEscCu) && ~isempty(iSumFeFe) ...
        && ~isempty(iSumFeCu) && ~isempty(iSumCuCu), 'missing an expected artifact name');

    assert(abs(arts(iEscFe).energyKeV   - 4.664)  < 1e-3, 'Fe escape energy mismatch');
    assert(abs(arts(iEscCu).energyKeV   - 6.308)  < 1e-3, 'Cu escape energy mismatch');
    assert(abs(arts(iSumFeFe).energyKeV - 12.808) < 1e-3, 'Fe+Fe sum energy mismatch');
    assert(abs(arts(iSumFeCu).energyKeV - 14.452) < 1e-3, 'Fe+Cu sum energy mismatch');
    assert(abs(arts(iSumCuCu).energyKeV - 16.096) < 1e-3, 'Cu+Cu sum energy mismatch');

    assert(arts(iEscCu).blocked, 'Cu escape (6.308) should be BLOCKED -- sits on Fe-Ka (6.404)');
    assert(~arts(iEscFe).blocked, 'Fe escape should be free');

    nPass = nPass + 1;
    fprintf('  Test 6: PASS -- predictArtifacts Fe+Cu@20kV: positions + Cu-escape blocked\n');
catch ME
    nFail = nFail + 1;
    fprintf('  Test 6: FAIL -- %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  7. predictArtifacts -- edge cases: no escape below the Si K edge, and
%     the EMaxKeV range filter drops off-axis sums
% ════════════════════════════════════════════════════════════════════════
try
    eO = imaging.eds.lineEnergy('O');
    artsO = imaging.eds.predictArtifacts({'O'}, eO);
    assert(isscalar(artsO) && strcmp(artsO(1).kind, 'sum'), ...
        'O (below the Si K edge) should produce only its self-sum, no escape');

    [eFe, ~] = imaging.eds.lineEnergy('Fe', BeamKV=20);
    [eCu, ~] = imaging.eds.lineEnergy('Cu', BeamKV=20);
    artsRanged = imaging.eds.predictArtifacts({'Fe', 'Cu'}, [eFe eCu], EMaxKeV=10.0);
    namesRanged = {artsRanged.name};
    assert(~any(strcmp(namesRanged, 'sum_Fe_Fe')) && ~any(strcmp(namesRanged, 'sum_Cu_Cu')), ...
        'EMaxKeV range filter should drop off-axis sums');
    assert(any(strcmp(namesRanged, 'esc_Fe')) && any(strcmp(namesRanged, 'esc_Cu')), ...
        'escapes should remain within range');

    nPass = nPass + 1;
    fprintf('  Test 7: PASS -- predictArtifacts edge cases (no escape below edge, range filter)\n');
catch ME
    nFail = nFail + 1;
    fprintf('  Test 7: FAIL -- %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  8. removeArtifacts -- the full recovery oracle. Fe(4000)+Cu(6000) plus
%     their escapes (at 1%% of parent) and one Fe+Cu sum peak: naive
%     fitPeaks over-counts Fe (Cu-escape 6.308 sits on Fe-Ka 6.404);
%     predict -> measure/model -> subtract -> refit restores Fe to truth.
% ════════════════════════════════════════════════════════════════════════
try
    e = linspace(0, 20, 4001);
    FE = imaging.eds.lineEnergy('Fe', BeamKV=200);
    CU = imaging.eds.lineEnergy('Cu', BeamKV=200);
    FRACTION = 0.01;
    SI_ESCAPE_KEV = 1.740;

    counts = gaussCurve(e, 4000, FE) + gaussCurve(e, 6000, CU) ...
        + gaussCurve(e, FRACTION * 4000, FE - SI_ESCAPE_KEV) ...
        + gaussCurve(e, FRACTION * 6000, CU - SI_ESCAPE_KEV) ...
        + gaussCurve(e, 30, FE + CU);

    pf0 = imaging.eds.fitPeaks(e, counts, {'Fe', 'Cu'}, Weights="uniform");
    naiveFe = pf0.netArea(1);
    assert(naiveFe > 4010, sprintf('naive Fe area should be inflated by the Cu escape, got %.2f', naiveFe));

    % NOTE: counts is a 1xN row (built from the row vector e) while
    % pf0.fittedCurve is Nx1 (fitPeaks reshapes internally) -- subtracting
    % them directly would implicitly broadcast into an NxN matrix instead
    % of the intended elementwise residual, so reshape counts to a column
    % first.
    removal = imaging.eds.removeArtifacts(e, counts, {'Fe', 'Cu'}, pf0.lineEnergyKeV, ...
        Residual=counts(:) - pf0.fittedCurve, ParentAreas=pf0.netArea, EscapeFraction=FRACTION);

    assert(approxRel(removal.measured("esc_Fe"), 40.0, 0.1), 'esc_Fe measured area mismatch');
    assert(approxRel(removal.measured("sum_Fe_Cu"), 30.0, 0.1), 'sum_Fe_Cu measured area mismatch');
    assert(approxRel(removal.modeled("esc_Cu"), 60.0, 0.05), 'esc_Cu modeled area mismatch');
    assert(isempty(removal.skipped), 'no artifacts should be skipped in this scenario');

    pf1 = imaging.eds.fitPeaks(e, removal.corrected, {'Fe', 'Cu'}, Weights="uniform");
    assert(approxRel(pf1.netArea(1), 4000, 0.005), ...
        sprintf('Fe not restored to within 0.5%%: got %.3f', pf1.netArea(1)));
    assert(approxRel(pf1.netArea(2), 6000, 0.005), ...
        sprintf('Cu not restored to within 0.5%%: got %.3f', pf1.netArea(2)));
    assert(abs(pf1.netArea(1) - 4000) < abs(naiveFe - 4000), ...
        'post-removal Fe area should be closer to truth than the naive fit');

    nPass = nPass + 1;
    fprintf('  Test 8: PASS -- removeArtifacts + refit restores Fe to within 0.5%%\n');
catch ME
    nFail = nFail + 1;
    fprintf('  Test 8: FAIL -- %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  9. removeArtifacts -- a blocked escape with no ParentAreas is skipped,
%     never modeled (can't fabricate a correction from nothing)
% ════════════════════════════════════════════════════════════════════════
try
    e = linspace(0, 20, 4001);
    FE = imaging.eds.lineEnergy('Fe', BeamKV=200);
    CU = imaging.eds.lineEnergy('Cu', BeamKV=200);
    FRACTION = 0.01;
    SI_ESCAPE_KEV = 1.740;
    counts = gaussCurve(e, 4000, FE) + gaussCurve(e, 6000, CU) ...
        + gaussCurve(e, FRACTION * 4000, FE - SI_ESCAPE_KEV) ...
        + gaussCurve(e, FRACTION * 6000, CU - SI_ESCAPE_KEV) ...
        + gaussCurve(e, 30, FE + CU);

    removalNoParents = imaging.eds.removeArtifacts(e, counts, {'Fe', 'Cu'}, [FE CU]);
    assert(any(removalNoParents.skipped == "esc_Cu"), 'esc_Cu should be skipped without ParentAreas');
    assert(~isKey(removalNoParents.modeled, "esc_Cu"), 'esc_Cu should not be modeled without ParentAreas');

    nPass = nPass + 1;
    fprintf('  Test 9: PASS -- blocked escape without ParentAreas is skipped, not modeled\n');
catch ME
    nFail = nFail + 1;
    fprintf('  Test 9: FAIL -- %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  10. quantifyPeaks -- matches cliffLorimer called directly on the true
%      planted areas (clean, well-separated peaks recover to ~1e-9 rel)
% ════════════════════════════════════════════════════════════════════════
try
    e = linspace(0, 20, 4001);
    eFe = imaging.eds.lineEnergy('Fe', BeamKV=200);
    eO  = imaging.eds.lineEnergy('O',  BeamKV=200);
    trueAreas = [3200, 4700];
    counts = gaussCurve(e, trueAreas(1), eFe) + gaussCurve(e, trueAreas(2), eO);

    [pf, cl] = imaging.eds.quantifyPeaks(e, counts, {'Fe', 'O'}, KFactors=[1.21, 1.80]);
    clDirect = imaging.eds.cliffLorimer({trueAreas(1), trueAreas(2)}, {'Fe', 'O'}, KFactors=[1.21, 1.80]);

    assert(max(abs((pf.netArea - trueAreas) ./ trueAreas)) < 1e-9, ...
        'fitPeaks should recover the true areas to ~1e-9 relative (clean, well-separated peaks)');
    assert(max(abs(cl.meanWeightPct - clDirect.meanWeightPct)) < 1e-6, ...
        'quantifyPeaks weight%% should match cliffLorimer(true areas)');
    assert(max(abs(cl.meanAtomicPct - clDirect.meanAtomicPct)) < 1e-6, ...
        'quantifyPeaks atomic%% should match cliffLorimer(true areas)');

    nPass = nPass + 1;
    fprintf('  Test 10: PASS -- quantifyPeaks matches cliffLorimer(true areas)\n');
catch ME
    nFail = nFail + 1;
    fprintf('  Test 10: FAIL -- %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  11. Error paths: size mismatch, empty elements, all-unknown lines,
%      bad EscapeFraction
% ════════════════════════════════════════════════════════════════════════
try
    threw = false;
    try
        imaging.eds.fitPeaks(1:5, 1:4, {'Fe'});
    catch e2
        threw = strcmp(e2.identifier, 'fitPeaks:sizeMismatch');
    end
    assert(threw, 'size mismatch should raise fitPeaks:sizeMismatch');

    threw = false;
    try
        imaging.eds.fitPeaks(linspace(0, 20, 100), zeros(1, 100), {});
    catch e2
        threw = strcmp(e2.identifier, 'fitPeaks:noElements');
    end
    assert(threw, 'empty elements should raise fitPeaks:noElements');

    warnState = warning('off', 'fitPeaks:noLine');
    cleanupWarn = onCleanup(@() warning(warnState));
    threw = false;
    try
        imaging.eds.fitPeaks(linspace(0, 20, 100), ones(1, 100), {'Xx', 'Yy'});
    catch e2
        threw = strcmp(e2.identifier, 'fitPeaks:noFittableLines');
    end
    assert(threw, 'all-unknown lines should raise fitPeaks:noFittableLines');

    threw = false;
    try
        imaging.eds.removeArtifacts(linspace(0, 20, 100), zeros(1, 100), {'Fe'}, ...
            imaging.eds.lineEnergy('Fe'), EscapeFraction=1.5);
    catch e2
        threw = strcmp(e2.identifier, 'removeArtifacts:badEscapeFraction');
    end
    assert(threw, 'EscapeFraction >= 1 should raise removeArtifacts:badEscapeFraction');

    nPass = nPass + 1;
    fprintf('  Test 11: PASS -- error paths (size mismatch, empty/unknown elements, bad EscapeFraction)\n');
catch ME
    nFail = nFail + 1;
    fprintf('  Test 11: FAIL -- %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════

catch fatalErr
    fprintf('  FATAL error in test harness: %s\n', fatalErr.message);
    nFail = nFail + 1;
end

% ── Summary ──────────────────────────────────────────────────────────────
fprintf('\n=== Results: %d passed, %d failed ===\n\n', nPass, nFail);

if nFail > 0
    error('test_eds_peakfit:failures', '%d test(s) failed.', nFail);
end


% ════════════════════════════════════════════════════════════════════════
%  Local helpers (script-local functions -- supported since R2016b)
% ════════════════════════════════════════════════════════════════════════

function c = gaussCurve(e, area, centerKeV)
%GAUSSCURVE  Area-parametrised Gaussian at the Fano (detector) width -- the
%   same "plant a known peak" construction imaging.eds.removeArtifacts uses
%   internally, duplicated here (test-local) to build synthetic spectra with
%   known ground-truth areas.
    [~, sigma] = imaging.eds.fanoResolution(centerKeV);
    amp = area / (sigma * sqrt(2 * pi));
    c = amp * exp(-0.5 * ((e - centerKeV) / sigma) .^ 2);
end


function ok = approxRel(x, expected, relTol)
%APPROXREL  True when x is within relTol (relative) of expected.
    ok = abs(x - expected) <= relTol * abs(expected);
end
