%TEST_PHYSICS_CORRECTIONS  Regression tests for EDS/crystallography fixes.
%
%   Run from root:  runAllTests(Group="edsquant")
%
%   Covers three physics-correctness bugs found in the 2026-05-24 audit:
%     1. massAbsorptionCoeff used a constant ~10^44 too small, returning
%        ~1e-41 cm^2/g for every pair -> the ZAF absorption correction was
%        silently disabled (all A-factors = 1.0). Calibrated C=1.0e22.
%     2. planeSpacings R-centering used the REVERSE setting (h-k+l) instead
%        of the IUCr-standard obverse (-h+k+l), wrongly forbidding e.g.
%        hematite's strongest lines (012) and (104).
%     3. zafCorrection accepted TakeOffAngle=0 -> csc(0)=Inf -> all-NaN maps.

clear; clc;
thisDir = fileparts(mfilename('fullpath'));
ROOT    = fileparts(fileparts(thisDir));
if ~contains(path, ROOT), addpath(ROOT); end

passed = 0; failed = 0;

% ════════════════════════════════════════════════════════════════════════
%  1. massAbsorptionCoeff returns physical values (vs NIST mass attenuation)
% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 1: massAbsorptionCoeff physical magnitude ══\n');
try
    feO  = imaging.eds.massAbsorptionCoeff('Fe', 'O');    % NIST ~19 cm^2/g
    niFe = imaging.eds.massAbsorptionCoeff('Ni', 'Fe');   % NIST ~380 cm^2/g
    assert(feO  > 10 && feO  < 40,  sprintf('Fe->O mac=%.2g, expected ~19', feO));
    assert(niFe > 200 && niFe < 600, sprintf('Ni->Fe mac=%.2g, expected ~380', niFe));
    fprintf('  Fe->O = %.1f (NIST ~19), Ni->Fe = %.0f (NIST ~380)\n', feO, niFe);
    fprintf('  PASS\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
%  2. planeSpacings R-centering uses obverse (-h+k+l=3n)
% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 2: R-centering obverse selection rule ══\n');
try
    r = calc.crystal.planeSpacings(5.0, Centering='R', MaxHKL=4);
    % (012) is obverse-allowed (−h+k+l=3) but reverse-FORBIDDEN (h−k+l=1):
    % its presence is a clean discriminator that the obverse fix is applied.
    % (We check (012) specifically, not (104), because planeSpacings lists
    % one symmetry representative per family and (104)'s rep is e.g. (024).)
    has012 = ismember([0 1 2], r.hkl, 'rows');
    assert(has012, '(012) missing — R-centering still on the reverse setting');
    % Every listed reflection must satisfy obverse −h+k+l ≡ 0 (mod 3)
    okAll = all(mod(-r.hkl(:,1) + r.hkl(:,2) + r.hkl(:,3), 3) == 0);
    assert(okAll, 'a listed R reflection violates the obverse rule');
    fprintf('  (012) allowed (reverse-forbidden); all reflections obverse-consistent\n');
    fprintf('  PASS\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
%  3. zafCorrection rejects TakeOffAngle = 0 (was silent all-NaN)
% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 3: zafCorrection guards TakeOffAngle=0 ══\n');
try
    maps = {ones(3,3)*100, ones(3,3)*50};
    threw = false;
    try
        imaging.eds.zafCorrection(maps, {'Fe','O'}, 'TakeOffAngle', 0);
    catch
        threw = true;   % MATLAB validator error is acceptable
    end
    assert(threw, 'TakeOffAngle=0 should be rejected, not produce NaN maps');
    % And a valid angle must produce finite, non-trivial absorption factors
    res = imaging.eds.zafCorrection(maps, {'Fe','O'}, 'TakeOffAngle', 20, 'Thickness', 50);
    assert(all(isfinite(res.zafFactors.A)), 'A-factors must be finite');
    assert(any(res.zafFactors.A > 1.01), ...
        'absorption correction should be active (A>1), not disabled (A=1)');
    fprintf('  0deg rejected; A-factors finite and active: A=[%s]\n', ...
        num2str(res.zafFactors.A(:)', '%.2f '));
    fprintf('  PASS\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ── Summary ────────────────────────────────────────────────────────────
fprintf('\n════════════════════════════════════════════════\n');
fprintf('  PHYSICS CORRECTIONS: %d / %d passed\n', passed, passed + failed);
fprintf('════════════════════════════════════════════════\n');
if failed > 0
    error('test_physics_corrections:failures', '%d test(s) failed.', failed);
end
fprintf('\n✓ Physics corrections intact.\n\n');
