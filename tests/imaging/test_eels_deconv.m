%TEST_EELS_DECONV  Unit tests for EELS deconvolution utilities.
%
%   Covers imaging.eels.eelsFourierRatio (plural-scattering removal using
%   the low-loss spectrum as PSF, reconvolved with the ZLP) and
%   imaging.eels.eelsRichardsonLucy (multiplicative Poisson-MLE
%   deconvolution, including its internal PSF-centring rule).
%
%   Tests use purely synthetic data so no external DM3/DM4 files are
%   required. Each test prints a tick (pass) or cross (fail) with a brief
%   description.
%
%   Run standalone:  cd tests/imaging; run test_eels_deconv
%   Run from root:   run tests/imaging/test_eels_deconv
%       runAllTests(Group="fv")

clear; clc;
fprintf('\n═══ test_eels_deconv ═══\n');

% Ensure toolbox is on the path
thisDir = fileparts(mfilename('fullpath'));
rootDir = fileparts(fileparts(thisDir));
if ~contains(path, rootDir)
    addpath(rootDir);
end

nPass = 0;
nFail = 0;

% Local Gaussian helper shared by all tests below.
gaussFn = @(x, c, s, amp) amp .* exp(-0.5 * ((x - c) ./ s).^2);
halfMaxWidth = @(y) sum(y >= 0.5 * max(y));

try  % outer guard — keeps runner from hanging on unexpected errors

% ════════════════════════════════════════════════════════════════════════
%  1. eelsFourierRatio — synthesize plural-scattered core by convolving a
%     true edge with the normalized low-loss spectrum; the +20 eV plasmon
%     replica should be strongly suppressed after deconvolution, and the
%     main peak should stay within 2 channels of its true position.
% ════════════════════════════════════════════════════════════════════════
try
    ne     = 256;
    energy = (0:ne-1)';                          % E = 0 at channel 0

    zlp     = gaussFn(energy, 0,  2, 1);
    plasmon = gaussFn(energy, 20, 3, 0.4);        % single plasmon replica
    low     = zlp + plasmon;
    singleS = gaussFn(energy, 100, 3, 1);         % the true core-loss edge
    lowNorm = low / sum(low);

    n2   = 2 ^ nextpow2(2 * ne);
    core = real(ifft(fft(singleS, n2) .* fft(lowNorm, n2)));
    core = core(1:ne);

    ssd = imaging.eels.eelsFourierRatio(energy, core, low, ZLPWindow=[-3, 3]);

    % Channels are 0-based in the physics (E==channel); MATLAB indices are +1.
    ratioCore = core(121) / core(101);            % channel 120 / channel 100
    ratioSsd  = ssd(121)  / ssd(101);

    assert(ratioSsd < 0.3 * ratioCore, ...
        sprintf('plasmon replica not suppressed: ratioSsd=%.4f, 0.3*ratioCore=%.4f', ...
        ratioSsd, 0.3 * ratioCore));

    [~, peakIdx] = max(ssd);
    peakChannel  = peakIdx - 1;
    assert(abs(peakChannel - 100) <= 2, ...
        sprintf('SSD peak expected near channel 100, got channel %d', peakChannel));

    nPass = nPass + 1;
    fprintf('  ✔ Test 1: eelsFourierRatio — plural-scattering replica suppressed\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 1: eelsFourierRatio: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  2. eelsRichardsonLucy — sharpens a broadened peak: preserved position,
%     taller peak, narrower FWHM than the observed (broadened) spectrum.
% ════════════════════════════════════════════════════════════════════════
try
    ne = 128;
    x  = (0:ne-1)';

    trueS = gaussFn(x, 64, 1.5, 1);               % sharp feature
    psf   = gaussFn(x, 64, 4.0, 1);                % centred broadening kernel
    observed = conv(trueS, psf / sum(psf), 'same');

    rl = imaging.eels.eelsRichardsonLucy(observed, psf, Iterations=40);

    [~, peakIdx] = max(rl);
    assert(abs((peakIdx - 1) - 64) <= 1, ...
        sprintf('RL peak expected near channel 64, got channel %d', peakIdx - 1));
    assert(max(rl) > max(observed), 'RL should concentrate the peak (max should increase)');
    assert(halfMaxWidth(rl) < halfMaxWidth(observed), ...
        'RL output should be sharper (smaller FWHM) than the observed spectrum');

    nPass = nPass + 1;
    fprintf('  ✔ Test 2: eelsRichardsonLucy — sharpens a broadened peak\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 2: eelsRichardsonLucy sharpening: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  3. eelsRichardsonLucy — stays non-negative under noise
% ════════════════════════════════════════════════════════════════════════
try
    rng(0);
    ne = 64;
    x  = (0:ne-1)';

    psf      = gaussFn(x, 32, 3, 1);
    observed = conv(gaussFn(x, 32, 1.0, 1), psf / sum(psf), 'same') ...
        + 1e-3 * randn(ne, 1);

    rl = imaging.eels.eelsRichardsonLucy(observed, psf, Iterations=10);

    assert(all(rl >= 0), 'RL output must remain non-negative under noise');

    nPass = nPass + 1;
    fprintf('  ✔ Test 3: eelsRichardsonLucy — non-negative under noise\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 3: eelsRichardsonLucy non-negative: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  4. eelsRichardsonLucy — a deliberately off-centre PSF (e.g. a ZLP
%     window whose peak sits far from the array midpoint) still yields an
%     unshifted deconvolved spectrum, verifying the internal centring rule.
% ════════════════════════════════════════════════════════════════════════
try
    ne = 128;
    x  = (0:ne-1)';

    trueS        = gaussFn(x, 64, 1.5, 1);
    psfCentred   = gaussFn(x, 64, 4.0, 1);         % same width, centred at midpoint
    observed     = conv(trueS, psfCentred / sum(psfCentred), 'same');
    psfOffCentre = gaussFn(x, 20, 4.0, 1);         % same shape, peak far from midpoint

    rl = imaging.eels.eelsRichardsonLucy(observed, psfOffCentre, Iterations=40);

    [~, peakIdx] = max(rl);
    peakChannel  = peakIdx - 1;
    assert(abs(peakChannel - 64) <= 2, ...
        sprintf(['off-centre PSF should still recover the peak near channel 64 ' ...
        '(centring rule failed); got channel %d'], peakChannel));
    assert(all(rl >= 0), 'RL output must remain non-negative');

    nPass = nPass + 1;
    fprintf('  ✔ Test 4: eelsRichardsonLucy — off-centre PSF still unshifted\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 4: eelsRichardsonLucy off-centre PSF: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  5. eelsFourierRatio — length mismatch raises
% ════════════════════════════════════════════════════════════════════════
try
    threw = false;
    try
        imaging.eels.eelsFourierRatio((0:9)', (0:9)', (0:8)');
    catch innerME
        threw = contains(innerME.identifier, 'eelsFourierRatio');
    end
    assert(threw, 'expected an error for mismatched core/low-loss lengths');

    nPass = nPass + 1;
    fprintf('  ✔ Test 5: eelsFourierRatio — length mismatch raises\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 5: eelsFourierRatio length mismatch: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  6. eelsRichardsonLucy — mismatched psf length and zero-sum psf raise
% ════════════════════════════════════════════════════════════════════════
try
    threw1 = false;
    try
        imaging.eels.eelsRichardsonLucy(ones(10,1), ones(9,1));
    catch innerME1
        threw1 = contains(innerME1.identifier, 'eelsRichardsonLucy');
    end
    assert(threw1, 'expected an error for mismatched spectrum/psf lengths');

    threw2 = false;
    try
        imaging.eels.eelsRichardsonLucy(ones(8,1), zeros(8,1));
    catch innerME2
        threw2 = contains(innerME2.identifier, 'eelsRichardsonLucy');
    end
    assert(threw2, 'expected an error for a zero-sum psf');

    nPass = nPass + 1;
    fprintf('  ✔ Test 6: eelsRichardsonLucy — invalid-input errors\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 6: eelsRichardsonLucy invalid input: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════

catch fatalErr
    fprintf('  ✘ FATAL error in test harness: %s\n', fatalErr.message);
    nFail = nFail + 1;
end

% ── Summary ──────────────────────────────────────────────────────────────
fprintf('\n═══ Results: %d passed, %d failed ═══\n\n', nPass, nFail);

if nFail > 0
    error('test_eels_deconv:failures', '%d test(s) failed.', nFail);
end
