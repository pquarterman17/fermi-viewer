%TEST_EELS_REAL_DM4  Real-instrument DM4 EELS spectrum-image regression tests.
%
%   Validates importDM4/importDM3 3D SI handling against real GMS files:
%   energy-dimension detection (energy is the LAST dimension in real SI
%   cubes), the DM calibration convention value = (index − origin) × scale,
%   and the EELS pipeline (background, extract map, Fourier-log thickness)
%   on real spectra. Physics oracles, not golden numbers: the ZLP must sit
%   at ≈0 eV, core-loss power-law exponents must be physical, known edges
%   must fall inside their acquisition windows.
%
%   Data: +test_datasets/EELS/ — local-only, gitignored. Fetched via
%   tests/fetchRealEelsData.m. Provenance: Zenodo 8403583 (CC-BY 4.0,
%   Burgess et al., lunar sample 79221) + hyperspy/rosettasciio corpus.
%   ALL TESTS SKIP when the data folder is absent (e.g. fresh clone / CI).
%
%   Run standalone:  cd tests; run imaging/test_eels_real_dm4
%   Run from root:   runAllTests(Group="eels_adv")

clear; clc;
fprintf('\n═══ test_eels_real_dm4 ═══\n');

thisDir = fileparts(mfilename('fullpath'));
rootDir = fileparts(fileparts(thisDir));
if ~contains(path, rootDir)
    addpath(rootDir);
end

nPass = 0;
nFail = 0;
nSkip = 0;

eelsDir = fullfile(rootDir, '+test_datasets', 'EELS');

% ════════════════════════════════════════════════════════════════════
%  Skip the whole suite when the local-only data is absent
% ════════════════════════════════════════════════════════════════════
requiredFiles = { ...
    'FigS6_apatite_ZLP.dm4', ...
    'Fig4_apatite79221_OKedge_vesicle.dm4', ...
    'FigS4_apatite79221_F_Fe.dm4', ...
    'Fig4_apatite79221_lowloss_vesicle.dm4', ...
    'rosettasciio_EELS_SI.dm4'};
present = cellfun(@(f) isfile(fullfile(eelsDir, f)), requiredFiles);

if ~all(present)
    nSkip = numel(requiredFiles);
    fprintf(['  – SKIP: real EELS data not present (%d/%d files).\n' ...
             '    Fetch with: run tests/fetchRealEelsData.m\n'], ...
        sum(present), numel(present));
    fprintf('\n═══ Results: %d passed, %d failed, %d skipped ═══\n\n', ...
        nPass, nFail, nSkip);
    return;
end

try  % outer guard — keeps runner from hanging on unexpected errors

% ════════════════════════════════════════════════════════════════════
%  1. ZLP spectrum image — dimension mapping + calibration oracle.
%     Energy must be the 2024-channel axis; the zero-loss peak (the
%     most intense channel by physics) must sit at ≈0 eV, which also
%     proves the (index − origin) × scale origin convention.
% ════════════════════════════════════════════════════════════════════
try
    data = parser.importAuto(fullfile(eelsDir, 'FigS6_apatite_ZLP.dm4'));
    si = data.metadata.parserSpecific.spectrumImage;

    assert(si.nChannels > 1000, ...
        sprintf('energy axis has %d channels — expected the 2024-channel dim', si.nChannels));
    assert(si.Ny < 100 && si.Nx < 100, 'spatial dims should be the small (~50 px) axes');
    assert(isequal(size(si.cube), [si.Ny, si.Nx, si.nChannels]), 'cube shape mismatch');
    assert(abs(si.energyScale - 0.05) < 1e-6, ...
        sprintf('energy scale %.4g — expected 0.05 eV/ch', si.energyScale));
    assert(min(si.energyAxis) < -1, ...
        'energy axis must start negative (ZLP tail) — origin convention broken');

    [~, zlpIdx] = max(si.sumSpectrum);
    eZLP = si.energyAxis(zlpIdx);
    assert(abs(eZLP) < 1.0, ...
        sprintf('ZLP at %.2f eV — must be within ±1 eV of zero', eZLP));

    nPass = nPass + 1;
    fprintf('  ✔ Test 1: ZLP SI — [%dx%dx%d], ZLP at %.2f eV\n', ...
        si.Ny, si.Nx, si.nChannels, eZLP);
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 1: ZLP SI: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════
%  2. ZLP file — Fourier-log thickness on real low-loss data.
%     Thin lunar FIB lamella: t/λ must be physical (0 < t/λ < 1.5).
% ════════════════════════════════════════════════════════════════════
try
    data = parser.importAuto(fullfile(eelsDir, 'FigS6_apatite_ZLP.dm4'));
    si = data.metadata.parserSpecific.spectrumImage;

    [~, tOverLambda] = imaging.eels.eelsFourierLog(si.energyAxis, si.sumSpectrum);
    assert(isfinite(tOverLambda) && tOverLambda > 0.05 && tOverLambda < 1.5, ...
        sprintf('t/lambda = %.3f — outside the physical window for a FIB lamella', tOverLambda));

    [tMap, mask] = imaging.eels.eelsThicknessMap(si.cube, si.energyAxis);
    assert(nnz(mask) > 0.5 * numel(tMap), 'thickness map: <50%% of pixels valid');
    medT = median(tMap(mask), 'omitnan');
    assert(abs(medT - tOverLambda) < 0.5, ...
        sprintf('map median %.3f vs sum-spectrum %.3f — inconsistent', medT, tOverLambda));

    nPass = nPass + 1;
    fprintf('  ✔ Test 2: Fourier-log thickness — t/λ=%.3f (map median %.3f)\n', ...
        tOverLambda, medT);
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 2: Fourier-log thickness: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════
%  3. O-K edge core-loss SI — window placement + background + map.
%     The acquisition window (490–592 eV) must bracket the O-K onset
%     (532 eV); the pre-edge power-law fit must be physical.
% ════════════════════════════════════════════════════════════════════
try
    data = parser.importAuto(fullfile(eelsDir, 'Fig4_apatite79221_OKedge_vesicle.dm4'));
    si = data.metadata.parserSpecific.spectrumImage;
    E = si.energyAxis;  I = si.sumSpectrum;

    assert(min(E) < 532 && max(E) > 532, ...
        sprintf('O-K onset 532 eV outside imported range %.0f–%.0f eV', min(E), max(E)));

    [sig, ~, p] = imaging.eels.eelsBackground(E, I, FitWindow=[min(E)+2, 524]);
    assert(p.r > 1 && p.r < 6, ...
        sprintf('power-law exponent r=%.2f — physical range is ~1–6', p.r));

    postEdge = E > 532 & E < 572;
    edgeFrac = sum(sig(postEdge)) / sum(I(postEdge));
    assert(edgeFrac > 0.05, ...
        sprintf('O-K edge only %.1f%% above background — subtraction failed', 100*edgeFrac));

    map = imaging.eels.eelsExtractMap(si.cube, E, [532, 572], ...
        BackgroundWindow=[min(E)+2, 524]);
    assert(isequal(size(map), [si.Ny, si.Nx]), 'O-K map size mismatch');
    assert(all(isfinite(map(:))) && max(map(:)) > 0, 'O-K map not finite/positive');

    nPass = nPass + 1;
    fprintf('  ✔ Test 3: O-K edge — r=%.2f, edge %.0f%% of raw, map %dx%d\n', ...
        p.r, 100*edgeFrac, si.Ny, si.Nx);
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 3: O-K edge: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════
%  4. F-K / Fe-L23 core-loss SI — non-square spatial dims (30×80).
%     Guards against x/y transposition: Ny≠Nx makes a swap detectable.
% ════════════════════════════════════════════════════════════════════
try
    data = parser.importAuto(fullfile(eelsDir, 'FigS4_apatite79221_F_Fe.dm4'));
    si = data.metadata.parserSpecific.spectrumImage;
    E = si.energyAxis;

    assert(si.nChannels == 2048, ...
        sprintf('expected 2048 channels, got %d', si.nChannels));
    assert(min([si.Ny, si.Nx]) == 30 && max([si.Ny, si.Nx]) == 80, ...
        sprintf('expected 30×80 spatial, got %dx%d', si.Ny, si.Nx));
    assert(min(E) < 685 && max(E) > 708, ...
        sprintf('F-K (685) / Fe-L23 (708) outside range %.0f–%.0f eV', min(E), max(E)));

    edges = imaging.eels.eelsEdgeTable();
    inWin = [edges.onsetEV] > min(E) & [edges.onsetEV] < max(E);
    assert(any(strcmp({edges(inWin).symbol}, 'F-K')), 'F-K not identified in window');
    assert(any(strcmp({edges(inWin).symbol}, 'Fe-L23')), 'Fe-L23 not identified in window');

    [~, ~, p] = imaging.eels.eelsBackground(E, si.sumSpectrum, ...
        FitWindow=[min(E)+2, 678]);
    assert(p.r > 1 && p.r < 6, sprintf('exponent r=%.2f not physical', p.r));

    nPass = nPass + 1;
    fprintf('  ✔ Test 4: F-K/Fe-L23 — 30×80 spatial, both edges in window, r=%.2f\n', p.r);
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 4: F-K/Fe-L23: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════
%  5. Low-loss vesicle SI — plasmon region (ZLP cut off at 2 eV).
%     Max must land in the plasmon band, not at a spatial index.
% ════════════════════════════════════════════════════════════════════
try
    data = parser.importAuto(fullfile(eelsDir, 'Fig4_apatite79221_lowloss_vesicle.dm4'));
    si = data.metadata.parserSpecific.spectrumImage;

    assert(si.nChannels == 2048, 'expected 2048 channels');
    [~, pkIdx] = max(si.sumSpectrum);
    ePk = si.energyAxis(pkIdx);
    assert(ePk > 5 && ePk < 40, ...
        sprintf('intensity max at %.1f eV — expected the 5–40 eV plasmon band', ePk));

    nPass = nPass + 1;
    fprintf('  ✔ Test 5: low-loss SI — plasmon max at %.1f eV\n', ePk);
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 5: low-loss SI: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════
%  6. rosettasciio EELS_SI — independent writer, µm spatial units.
%     Cross-checks energy-dim detection against HyperSpy's reading of
%     the same file: 2×2 px, 2048 ch, 300–2347 eV @ 1 eV/ch.
% ════════════════════════════════════════════════════════════════════
try
    data = parser.importAuto(fullfile(eelsDir, 'rosettasciio_EELS_SI.dm4'));
    si = data.metadata.parserSpecific.spectrumImage;

    assert(si.nChannels == 2048, sprintf('expected 2048 ch, got %d', si.nChannels));
    assert(si.Ny == 2 && si.Nx == 2, ...
        sprintf('expected 2×2 spatial, got %dx%d', si.Ny, si.Nx));
    assert(abs(min(si.energyAxis) - 300) < 1.5, ...
        sprintf('energy start %.1f — expected 300 eV', min(si.energyAxis)));
    assert(abs(si.energyScale - 1) < 1e-6, 'expected 1 eV/ch');
    assert(~isnan(si.pixelSize) && si.pixelSize > 0, 'spatial calibration lost');

    nPass = nPass + 1;
    fprintf('  ✔ Test 6: rosettasciio SI — 2×2×2048, 300–%.0f eV\n', max(si.energyAxis));
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 6: rosettasciio SI: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════
%  7. eelsAlignZLP on the real ZLP cube — after alignment every pixel's
%     ZLP must sit on the same channel (the global ZLP channel).
% ════════════════════════════════════════════════════════════════════
try
    data = parser.importAuto(fullfile(eelsDir, 'FigS6_apatite_ZLP.dm4'));
    si = data.metadata.parserSpecific.spectrumImage;

    [aligned, shifts] = imaging.eels.eelsAlignZLP(si.cube, si.energyAxis);
    assert(isequal(size(aligned), size(si.cube)), 'aligned cube size changed');
    assert(isequal(size(shifts), [si.Ny, si.Nx]), 'shifts map size wrong');

    % Per-pixel argmax after alignment: all on one channel (±1 for noise)
    [~, refCh] = max(si.sumSpectrum);
    nE = si.nChannels;
    flat = reshape(double(aligned), [], nE);
    [~, pkCh] = max(flat, [], 2);
    fracAligned = mean(abs(pkCh - refCh) <= 1);
    assert(fracAligned > 0.95, ...
        sprintf('only %.0f%% of pixels aligned to the ZLP channel', 100*fracAligned));

    nPass = nPass + 1;
    fprintf('  ✔ Test 7: eelsAlignZLP — %.1f%% pixels on ZLP channel (max |shift| %d ch)\n', ...
        100*fracAligned, max(abs(shifts(:))));
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 7: eelsAlignZLP: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════
%  8. Kramers-Kronig on the real low-loss sum spectrum — dielectric
%     function must be physical: finite ε, Im(ε)≥0 in the plasmon band,
%     positive thickness estimate.
% ════════════════════════════════════════════════════════════════════
try
    data = parser.importAuto(fullfile(eelsDir, 'FigS6_apatite_ZLP.dm4'));
    si = data.metadata.parserSpecific.spectrumImage;

    kk = imaging.eels.eelsKramersKronig(si.energyAxis, si.sumSpectrum, ...
        AccVoltage=200, CollectionAngle=10);

    assert(all(isfinite(kk.eps1)) && all(isfinite(kk.eps2)), 'ε not finite');
    band = kk.energy > 8 & kk.energy < 30;            % plasmon band
    assert(any(band), 'no samples in the 8–30 eV band');
    assert(median(kk.eps2(band)) > 0, 'Im(ε) not positive in the plasmon band');
    assert(isfinite(kk.thickness) && kk.thickness > 0, ...
        sprintf('thickness estimate %.3g not physical', kk.thickness));

    nPass = nPass + 1;
    fprintf('  ✔ Test 8: Kramers-Kronig — ε finite, Im(ε)>0 in plasmon band, t=%.0f nm\n', ...
        kk.thickness);
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 8: Kramers-Kronig: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════
%  9. eelsSVD on the real O-K core-loss cube — variance ordering and
%     shape contracts on real (noisy, correlated) data.
% ════════════════════════════════════════════════════════════════════
try
    data = parser.importAuto(fullfile(eelsDir, 'Fig4_apatite79221_OKedge_vesicle.dm4'));
    si = data.metadata.parserSpecific.spectrumImage;

    res = imaging.eels.eelsSVD(si.cube, si.energyAxis, NumComponents=5);

    assert(size(res.eigenspectra, 1) == si.nChannels, 'eigenspectra length wrong');
    assert(isequal(size(res.scoreMaps), [si.Ny, si.Nx, 5]), 'scoreMaps size wrong');
    assert(issorted(res.explained, 'descend'), 'explained variance not ordered');
    assert(issorted(res.cumulative, 'ascend') && res.cumulative(end) <= 100 + 1e-6, ...
        'cumulative variance malformed');
    % Real SI data is highly correlated: the first component must
    % dominate the kept set by a wide margin.
    assert(res.explained(1) > 5 * res.explained(2), ...
        sprintf('component 1 (%.1f%%) does not dominate component 2 (%.1f%%)', ...
        res.explained(1), res.explained(2)));

    nPass = nPass + 1;
    fprintf('  ✔ Test 9: eelsSVD — comp 1 explains %.1f%%, contracts hold\n', ...
        res.explained(1));
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 9: eelsSVD: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════

catch fatalErr
    fprintf('  ✘ FATAL error in test harness: %s\n', fatalErr.message);
    nFail = nFail + 1;
end

% ── Summary ──────────────────────────────────────────────────────────
fprintf('\n═══ Results: %d passed, %d failed, %d skipped ═══\n\n', ...
    nPass, nFail, nSkip);

if nFail > 0
    error('test_eels_real_dm4:failures', '%d test(s) failed.', nFail);
end
