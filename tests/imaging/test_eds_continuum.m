%TEST_EDS_CONTINUUM  Unit tests for the EDS Kramers continuum background.
%
%   Tests use purely synthetic data so no external files are required.
%   Each test prints a tick (pass) or cross (fail) with a brief description.
%
%   Functions tested:
%       imaging.eds.elementMap        (Background='bremsstrahlung')
%       imaging.eds.extractElementMaps (bremsstrahlung passthrough)
%       imaging.eds.fitContinuum
%       imaging.eds.subtractContinuum
%
%   Run standalone:  cd tests; run test_eds_continuum
%   Run from root:   run tests/imaging/test_eds_continuum
%       runAllTests(Group="fv")

clear; clc;
fprintf('\n═══ test_eds_continuum ═══\n');

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
%  1. elementMap Background='bremsstrahlung' removes a per-pixel continuum
%     ramp: the continuum amplitude ramps across pixels while an identical
%     Fe-Ka peak sits everywhere. A correct closed-form subtraction removes
%     the ramp entirely, leaving the same (continuum-free) net peak area at
%     every pixel.
% ════════════════════════════════════════════════════════════════════════
try
    energy = linspace(0.1, 12.0, 1200)';      % ~10 eV/channel
    e0 = 15.0;
    cont = (e0 - energy) ./ energy;           % unit pure-Kramers shape
    amps = reshape(1:12, 3, 4);               % ramp 1..12 across pixels
    peak = exp(-0.5 * ((energy - 6.404) / 0.04) .^ 2);
    cube = reshape(amps, 3, 4, 1) .* reshape(cont, 1, 1, []) ...
         + 500.0 * reshape(peak, 1, 1, []);

    net = imaging.eds.elementMap(cube, energy, 6.254, 6.554, ...
        Background='bremsstrahlung', BgGap=0.05, E0KeV=e0);

    peakMask = energy >= 6.254 & energy <= 6.554;
    expected = 500.0 * sum(exp(-0.5 * ((energy(peakMask) - 6.404) / 0.04) .^ 2));

    assert(max(abs(net(:) - expected)) < expected * 2e-3, ...
        sprintf('net map should match the continuum-free peak sum (%.4f), got range [%.4f %.4f]', ...
        expected, min(net(:)), max(net(:))));
    assert(max(net(:)) - min(net(:)) < expected * 2e-3, ...
        sprintf('net map should be flat across the ramp, spread=%.6f', max(net(:))-min(net(:))));

    nPass = nPass + 1;
    fprintf('  ✔ Test 1: elementMap bremsstrahlung — removes per-pixel continuum ramp, flat net\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 1: elementMap bremsstrahlung ramp: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  2. elementMap Background='bremsstrahlung' on a PEAK-FREE pure-Kramers
%     cube: the fixed Kramers shape matches the continuum exactly, so a
%     peak-free window nets to ~0 (a linear chord would over-subtract this
%     convex continuum instead). Steep low-energy region exercises curvature.
% ════════════════════════════════════════════════════════════════════════
try
    energy = linspace(0.1, 12.0, 1200)';
    e0 = 15.0;
    curve = 5.0 * (e0 - energy) ./ energy;
    cube = repmat(reshape(curve, 1, 1, []), 2, 2, 1);

    net = imaging.eds.elementMap(cube, energy, 1.0, 1.4, ...
        Background='bremsstrahlung', BgGap=0.1, E0KeV=e0);

    assert(max(abs(net(:))) < 1e-6, ...
        sprintf('peak-free pure-Kramers window should net to ~0, got %.3e', max(abs(net(:)))));

    nPass = nPass + 1;
    fprintf('  ✔ Test 2: elementMap bremsstrahlung — peak-free pure-Kramers nets to ~0\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 2: elementMap bremsstrahlung peak-free: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  3. elementMap Background='bremsstrahlung' requires a finite E0KeV
% ════════════════════════════════════════════════════════════════════════
try
    energy = linspace(0.1, 12.0, 1200)';
    cube = ones(2, 2, numel(energy));
    errored = false;
    try
        imaging.eds.elementMap(cube, energy, 6.3, 6.5, Background='bremsstrahlung');
    catch innerME
        errored = true;
        assert(contains(innerME.message, 'E0KeV'), ...
            sprintf('error message should mention E0KeV, got: %s', innerME.message));
    end
    assert(errored, 'missing E0KeV should raise an error');

    nPass = nPass + 1;
    fprintf('  ✔ Test 3: elementMap bremsstrahlung — missing E0KeV raises a clear error\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 3: elementMap bremsstrahlung missing E0KeV: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  4. elementMap Background='bremsstrahlung' — E0KeV must exceed the peak
%     window's upper edge
% ════════════════════════════════════════════════════════════════════════
try
    energy = linspace(0.1, 12.0, 1200)';
    cube = ones(2, 2, numel(energy));
    errored = false;
    try
        imaging.eds.elementMap(cube, energy, 6.3, 6.5, Background='bremsstrahlung', E0KeV=6.0);
    catch innerME
        errored = true;
        assert(contains(innerME.message, 'exceed'), ...
            sprintf('error message should mention "exceed", got: %s', innerME.message));
    end
    assert(errored, 'E0KeV below the window top should raise an error');

    nPass = nPass + 1;
    fprintf('  ✔ Test 4: elementMap bremsstrahlung — E0KeV below window top raises\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 4: elementMap bremsstrahlung E0KeV window check: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  5. extractElementMaps — Background/E0KeV/BeamKV passthrough to elementMap
% ════════════════════════════════════════════════════════════════════════
try
    energy = linspace(0.1, 12.0, 1200)';
    e0 = 15.0;
    cont = (e0 - energy) ./ energy;
    amps = reshape(1:12, 3, 4);
    peak = exp(-0.5 * ((energy - 6.404) / 0.04) .^ 2);
    cube = reshape(amps, 3, 4, 1) .* reshape(cont, 1, 1, []) ...
         + 500.0 * reshape(peak, 1, 1, []);

    maps = imaging.eds.extractElementMaps(cube, energy, {'Fe'}, HalfWindow=0.15, ...
        Background='bremsstrahlung', BeamKV=200.0, E0KeV=e0);

    assert(isscalar(maps), sprintf('expected 1 map, got %d', numel(maps)));
    assert(maps(1).total > 0, 'Fe map total should be positive');

    nPass = nPass + 1;
    fprintf('  ✔ Test 5: extractElementMaps — bremsstrahlung + E0KeV passthrough\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 5: extractElementMaps bremsstrahlung passthrough: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  6. fitContinuum recovers a known pure-Kramers amplitude exactly (no
%     peaks, no noise — a single linear-in-amp parameter with a fixed shape)
% ════════════════════════════════════════════════════════════════════════
try
    e = linspace(0.1, 20.0, 1991)';   % ~10 eV/channel
    e0 = 18.0;
    ee = max(e, 1e-9);
    truth = 500.0 * max(e0 - ee, 0) ./ ee;

    fit = imaging.eds.fitContinuum(e, truth, e0, FitAbsorption=false, Weights="none");

    assert(abs(fit.amp - 500.0) / 500.0 < 1e-3, ...
        sprintf('amp expected ~500, got %.4f', fit.amp));
    assert(max(abs(fit.continuum - truth)) < 1e-3 * max(truth), ...
        'fitted continuum should match the noiseless truth curve');
    assert(isfinite(fit.reducedChi2) && fit.reducedChi2 >= 0, ...
        'reducedChi2 must be a finite, non-negative scalar');

    nPass = nPass + 1;
    fprintf('  ✔ Test 6: fitContinuum — recovers known pure-Kramers amplitude\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 6: fitContinuum known amplitude: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  7. fitContinuum recovers the continuum amplitude UNDER two characteristic
%     peaks (Fe-Ka, Cu-Ka) once those peaks are masked out; the masked
%     channels must be excluded from keepMask.
% ════════════════════════════════════════════════════════════════════════
try
    e = linspace(0.1, 20.0, 1991)';
    e0 = 18.0;
    ee = max(e, 1e-9);
    contTrue = 400.0 * max(e0 - ee, 0) ./ ee;

    eFe = imaging.eds.lineEnergy('Fe');
    eCu = imaging.eds.lineEnergy('Cu');
    [~, sigmaFe] = imaging.eds.fanoResolution(eFe);
    [~, sigmaCu] = imaging.eds.fanoResolution(eCu);

    counts = contTrue ...
        + 8000.0 * exp(-0.5 * ((e - eFe) / sigmaFe) .^ 2) ...
        + 6000.0 * exp(-0.5 * ((e - eCu) / sigmaCu) .^ 2);

    fit = imaging.eds.fitContinuum(e, counts, e0, ...
        Elements={'Fe', 'Cu'}, FitAbsorption=false, Weights="none");

    assert(abs(fit.amp - 400.0) / 400.0 < 0.05, ...
        sprintf('amp expected ~400 (within 5%%), got %.4f', fit.amp));
    [~, idxFe] = min(abs(e - eFe));
    assert(~fit.keepMask(idxFe), 'the Fe-Ka channel must be masked out of the fit');

    nPass = nPass + 1;
    fprintf('  ✔ Test 7: fitContinuum — recovers amplitude under masked Fe/Cu peaks\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 7: fitContinuum under peaks: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  8. subtractContinuum on a synthetic spectrum (Kramers amp=300, E0=18 keV,
%     Fe-Ka + Cu-Ka Gaussian peaks at Fano widths) recovers amp within 5%
%     and the net peak areas keep the planted Cu:Fe ratio (1.5) within 5%.
% ════════════════════════════════════════════════════════════════════════
try
    e = linspace(0.1, 20.0, 1991)';
    e0 = 18.0;
    ee = max(e, 1e-9);
    contTrue = 300.0 * max(e0 - ee, 0) ./ ee;

    eFe = imaging.eds.lineEnergy('Fe');
    eCu = imaging.eds.lineEnergy('Cu');
    [~, sigmaFe] = imaging.eds.fanoResolution(eFe);
    [~, sigmaCu] = imaging.eds.fanoResolution(eCu);

    ampFe = 4000.0;
    targetRatio = 1.5;
    areaFe = ampFe * sigmaFe * sqrt(2 * pi);
    ampCu = targetRatio * areaFe / (sigmaCu * sqrt(2 * pi));

    counts = contTrue ...
        + ampFe * exp(-0.5 * ((e - eFe) / sigmaFe) .^ 2) ...
        + ampCu * exp(-0.5 * ((e - eCu) / sigmaCu) .^ 2);

    [net, fit] = imaging.eds.subtractContinuum(e, counts, e0, ...
        Elements={'Fe', 'Cu'}, FitAbsorption=false, Weights="none");

    assert(abs(fit.amp - 300.0) / 300.0 < 0.05, ...
        sprintf('amp expected ~300 (within 5%%), got %.4f', fit.amp));

    winFe = abs(e - eFe) <= 3 * sigmaFe;
    winCu = abs(e - eCu) <= 3 * sigmaCu;
    netAreaFe = sum(net(winFe));
    netAreaCu = sum(net(winCu));
    ratio = netAreaCu / netAreaFe;

    assert(abs(ratio - targetRatio) / targetRatio < 0.05, ...
        sprintf('Cu:Fe net-area ratio expected ~%.2f (within 5%%), got %.4f', targetRatio, ratio));

    nPass = nPass + 1;
    fprintf('  ✔ Test 8: subtractContinuum — amp + planted Cu:Fe area ratio recovered\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 8: subtractContinuum area ratio: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  9. fitContinuum — missing/non-finite E0KeV raises a clear error
% ════════════════════════════════════════════════════════════════════════
try
    e = linspace(0.1, 20.0, 200)';
    counts = ones(size(e));
    errored = false;
    try
        imaging.eds.fitContinuum(e, counts, NaN);
    catch innerME
        errored = true;
        assert(contains(innerME.message, 'e0KeV'), ...
            sprintf('error message should mention e0KeV, got: %s', innerME.message));
    end
    assert(errored, 'non-finite e0KeV should raise an error');

    nPass = nPass + 1;
    fprintf('  ✔ Test 9: fitContinuum — non-finite e0KeV raises a clear error\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 9: fitContinuum missing e0KeV: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════

catch fatalErr
    fprintf('  ✘ FATAL error in test harness: %s\n', fatalErr.message);
    nFail = nFail + 1;
end

% ── Summary ──────────────────────────────────────────────────────────────
fprintf('\n═══ Results: %d passed, %d failed ═══\n\n', nPass, nFail);

if nFail > 0
    error('test_eds_continuum:failures', '%d test(s) failed.', nFail);
end
