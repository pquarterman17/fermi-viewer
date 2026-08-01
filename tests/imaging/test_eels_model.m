%TEST_EELS_MODEL  Unit tests for model-based multi-edge EELS fitting.
%
%   Validates imaging.eels.eelsEdgeShape / eelsFitEdges / eelsFitEdgesMap
%   (the MATLAB port of PLAN_SPECTRAL_QUANT #2 from the Python sibling's
%   fermiviewer.calc.eels_model). Validation is by (a) parity of the
%   differential edge shape with the existing window-integration
%   cross-section (imaging.eels.eelsCrossSection), and (b) recovery of
%   known at% from synthetic model spectra — including edges that
%   OVERLAP closely enough that window-integration mis-assigns them.
%   Tests use purely synthetic data so no external DM3/DM4 files are
%   required.
%
%   Run standalone:  cd tests; run test_eels_model
%   Run from root:   run tests/imaging/test_eels_model
%       runAllTests(Group="fv")

clear; clc;
fprintf('\n═══ test_eels_model ═══\n');

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
%  1. eelsEdgeShape — window integral matches eelsCrossSection to 1e-9 rel
% ════════════════════════════════════════════════════════════════════════
try
    Z = 8; shell = "K"; onset = 532.0; e0 = 200.0; beta = 10.0; delta = 80.0;

    fn = imaging.eels.eelsEdgeShape(Z, shell, e0, beta, onset);
    E  = linspace(onset, onset + delta, 400);
    got = trapz(E, fn(E));

    expected = imaging.eels.eelsCrossSection(Z, shell, e0, beta, delta, onset);

    relErr = abs(got - expected) / abs(expected);
    assert(relErr < 1e-9, ...
        sprintf('Relative error %.3e exceeds 1e-9 (got=%.6e, expected=%.6e)', ...
        relErr, got, expected));

    nPass = nPass + 1;
    fprintf('  ✔ Test 1: eelsEdgeShape window integral matches eelsCrossSection (rel=%.2e)\n', relErr);
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 1: eelsEdgeShape integral parity: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  2. eelsEdgeShape — identically zero below onset
% ════════════════════════════════════════════════════════════════════════
try
    fn = imaging.eels.eelsEdgeShape(8, "K", 200.0, 10.0, 532.0);
    E  = linspace(400.0, 700.0, 300);
    shapeVals = fn(E);

    assert(all(shapeVals(E < 532.0) == 0.0), 'Shape must be exactly 0 below onset');
    assert(any(shapeVals(E >= 532.0) > 0.0), 'Shape must be positive above onset');

    nPass = nPass + 1;
    fprintf('  ✔ Test 2: eelsEdgeShape identically zero below onset\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 2: eelsEdgeShape zero-below-onset: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  3. eelsFitEdges — recovers at% from a self-generated 2-edge spectrum
%     (areal densities 2:1 -> at% 66.7 / 33.3, within 0.5 percentage points)
% ════════════════════════════════════════════════════════════════════════
try
    E = linspace(250.0, 950.0, 700)';
    edges = [makeEdge('O','K',8,532.0), makeEdge('Fe','L',26,708.0)];

    spec = synthSpectrum(E, edges, [2.0e27, 1.0e27], 200.0, 10.0, 5.0e5, 3.0);
    r = imaging.eels.eelsFitEdges(E, spec, edges, 200.0, 10.0);

    assert(r.success, 'fminbnd did not report success');
    assert(isequal(r.element(1), "O") && isequal(r.element(2), "Fe"), ...
        'element order mismatch');
    assert(abs(r.atomicPercent(1) - 66.667) < 0.5, ...
        sprintf('O at%% = %.3f, expected ~66.667', r.atomicPercent(1)));
    assert(abs(r.atomicPercent(2) - 33.333) < 0.5, ...
        sprintf('Fe at%% = %.3f, expected ~33.333', r.atomicPercent(2)));
    assert(numel(r.amplitudeSigma) == 2, 'amplitudeSigma must have 2 entries');

    nPass = nPass + 1;
    fprintf('  ✔ Test 3: eelsFitEdges recovers at%% (O=%.2f%%, Fe=%.2f%%)\n', ...
        r.atomicPercent(1), r.atomicPercent(2));
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 3: eelsFitEdges at%% recovery: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  4. eelsFitEdges — model decomposition identity (background + edges ==
%     model, to 1e-9)
% ════════════════════════════════════════════════════════════════════════
try
    E = linspace(250.0, 950.0, 700)';
    edges = [makeEdge('O','K',8,532.0), makeEdge('Fe','L',26,708.0)];
    spec = synthSpectrum(E, edges, [2.0e27, 1.0e27], 200.0, 10.0, 5.0e5, 3.0);
    r = imaging.eels.eelsFitEdges(E, spec, edges, 200.0, 10.0);

    reconstructed = r.background + sum(r.edgeCurves, 2);
    scaleRef = max(max(abs(r.model)), 1);
    maxAbsErr = max(abs(reconstructed - r.model));
    assert(maxAbsErr / scaleRef < 1e-9, ...
        sprintf('Decomposition identity off by %.3e (relative)', maxAbsErr / scaleRef));

    nPass = nPass + 1;
    fprintf('  ✔ Test 4: eelsFitEdges model == background + sum(edgeCurves) to 1e-9\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 4: eelsFitEdges decomposition identity: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  5. eelsFitEdges — separates OVERLAPPING edges (Mn-L 640 / Fe-L 708,
%     ~60 eV apart) that window-integration would mis-assign; recovered
%     within 1 percentage point
% ════════════════════════════════════════════════════════════════════════
try
    E = linspace(400.0, 950.0, 800)';
    edges = [makeEdge('Mn','L',25,640.0), makeEdge('Fe','L',26,708.0)];

    spec = synthSpectrum(E, edges, [3.0e27, 1.0e27], 200.0, 10.0, 5.0e5, 3.0);
    r = imaging.eels.eelsFitEdges(E, spec, edges, 200.0, 10.0);

    assert(r.success, 'fminbnd did not report success');
    assert(abs(r.atomicPercent(1) - 75.0) < 1.0, ...
        sprintf('Mn at%% = %.3f, expected ~75.0', r.atomicPercent(1)));
    assert(abs(r.atomicPercent(2) - 25.0) < 1.0, ...
        sprintf('Fe at%% = %.3f, expected ~25.0', r.atomicPercent(2)));

    nPass = nPass + 1;
    fprintf('  ✔ Test 5: eelsFitEdges resolves overlapping Mn-L/Fe-L (Mn=%.2f%%, Fe=%.2f%%)\n', ...
        r.atomicPercent(1), r.atomicPercent(2));
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 5: eelsFitEdges overlapping edges: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  6. eelsFitEdgesMap — uniform cube gives uniform maps matching the
%     scalar fit (ptp < 1e-6 across pixels)
% ════════════════════════════════════════════════════════════════════════
try
    E = linspace(250.0, 950.0, 500)';
    edges = [makeEdge('O','K',8,532.0), makeEdge('Fe','L',26,708.0)];
    spec = synthSpectrum(E, edges, [2.0e27, 1.0e27], 200.0, 10.0, 5.0e5, 3.0);

    scalarFit = imaging.eels.eelsFitEdges(E, spec, edges, 200.0, 10.0);

    Ny = 4; Nx = 5;
    cube = repmat(reshape(spec, 1, 1, []), Ny, Nx, 1);
    mp = imaging.eels.eelsFitEdgesMap(cube, E, edges, 200.0, 10.0);

    assert(isequal(size(mp.atomicPercent), [Ny Nx 2]), 'atomicPercent size mismatch');

    oVals = mp.atomicPercent(:, :, 1);
    assert(max(oVals(:)) - min(oVals(:)) < 1e-6, ...
        sprintf('Map not uniform: ptp = %.3e', max(oVals(:)) - min(oVals(:))));
    assert(abs(mp.atomicPercent(1,1,1) - scalarFit.atomicPercent(1)) < 1.0, ...
        sprintf('Map O at%% (%.3f) vs scalar fit (%.3f) mismatch', ...
        mp.atomicPercent(1,1,1), scalarFit.atomicPercent(1)));

    nPass = nPass + 1;
    fprintf('  ✔ Test 6: eelsFitEdgesMap uniform cube matches scalar fit (ptp=%.2e)\n', ...
        max(oVals(:)) - min(oVals(:)));
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 6: eelsFitEdgesMap uniform cube: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  7. eelsFitEdgesMap — two-region cube resolves left/right composition,
%     with a map(1,1) vs map(1,end) spatial-orientation guard
% ════════════════════════════════════════════════════════════════════════
try
    E = linspace(250.0, 950.0, 500)';
    edges = [makeEdge('O','K',8,532.0), makeEdge('Fe','L',26,708.0)];
    leftSpec  = synthSpectrum(E, edges, [3.0e27, 1.0e27], 200.0, 10.0, 5.0e5, 3.0); % O-rich
    rightSpec = synthSpectrum(E, edges, [1.0e27, 3.0e27], 200.0, 10.0, 5.0e5, 3.0); % Fe-rich

    Ny = 2; Nx = 2;
    cube = zeros(Ny, Nx, numel(E));
    for row = 1:Ny
        cube(row, 1, :) = reshape(leftSpec,  1, 1, []);
        cube(row, 2, :) = reshape(rightSpec, 1, 1, []);
    end

    mp = imaging.eels.eelsFitEdgesMap(cube, E, edges, 200.0, 10.0);

    oLeft  = mp.atomicPercent(1, 1, 1);
    oRight = mp.atomicPercent(1, end, 1);   % orientation guard: col 1 vs last col

    assert(oLeft > 60.0 && oRight < 40.0, ...
        sprintf('Expected O-rich left / Fe-rich right, got oLeft=%.2f oRight=%.2f', ...
        oLeft, oRight));
    assert(abs(oLeft - 75.0) < 3.0, sprintf('oLeft = %.3f, expected ~75.0', oLeft));
    assert(abs(oRight - 25.0) < 3.0, sprintf('oRight = %.3f, expected ~25.0', oRight));

    nPass = nPass + 1;
    fprintf('  ✔ Test 7: eelsFitEdgesMap two-region cube resolves left/right (O: %.2f%% / %.2f%%)\n', ...
        oLeft, oRight);
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 7: eelsFitEdgesMap two-region cube: %s\n', ME.message);
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
    error('test_eels_model:failures', '%d test(s) failed.', nFail);
end

% ── Helpers (local functions at end of script — required for R2022b) ──
function e = makeEdge(element, shell, Z, onsetEV)
%MAKEEDGE  Build one imaging.eels.eelsFitEdges `edges` struct entry.
    e = struct('element', element, 'shell', string(shell), 'Z', Z, 'onsetEV', onsetEV);
end

function spec = synthSpectrum(E, edges, areal, E0kV, betaMrad, bgAmp, r)
%SYNTHSPECTRUM  power-law background + sum(areal_X * dsigma_X/dE) — the
%   model's own generator, so recovering `areal` back out is a genuine
%   round-trip test of imaging.eels.eelsFitEdges / eelsFitEdgesMap.
    spec = bgAmp * max(E, 1e-12) .^ (-r);
    for k = 1:numel(edges)
        el = edges(k);
        fn = imaging.eels.eelsEdgeShape( ...
            double(el.Z), string(el.shell), E0kV, betaMrad, double(el.onsetEV));
        spec = spec + areal(k) * fn(E);
    end
end
