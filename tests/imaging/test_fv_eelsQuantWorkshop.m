%TEST_FV_EELSQUANTWORKSHOP  Headless API test for the EELS quant window.
%
%   Drives fermiViewer.eels.openEELSQuantWorkshop through its programmatic
%   `api` (no dialogs) under headless figures:
%     1. window opens on a synthetic two-edge (C-K + O-K) spectrum
%     2. set beam + edges, compute → at% for both elements, sums to 100
%     3. CSV export writes header + one row per element
%     4. single-edge guard rejects incomplete input
%     5. SI cube → per-pixel composition maps (computeMaps/getMapResult)
%     6. no-cube guard: computeMaps without a cube yields no result
%     7. result table's "± at%" column is positive/finite (window integration)
%     8. sigma-absent fallback renders at% alone, never "NaN" (.renderResult)
%     9. Method="Model fit" at% sums to 100 and agrees with window
%        integration within a few points on well-separated edges
%    10. model-fit overlay curves replace (not stack) on re-run, and clear
%        on a Method switch
%
%   Run:
%       run tests/imaging/test_fv_eelsQuantWorkshop
%       runAllTests(Group="fvgui")

fprintf('\n');
fprintf('╔══════════════════════════════════════════════════════════════╗\n');
fprintf('║  EELS Quantification headless API                            ║\n');
fprintf('╚══════════════════════════════════════════════════════════════╝\n');

ROOT = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(ROOT);

passed = 0;
failed = 0;
set(groot, 'DefaultFigureVisible', 'off');

% Synthetic spectrum: power-law background + C-K (284) and O-K (532) edges.
E = (200:1:800)';
bg = 1e6 * E .^ (-2.0);
cK = 60  * max(E - 284, 0) ./ E .* (284 ./ max(E, 284)) .^ 1.5;
oK = 600 * max(E - 532, 0) ./ E .* (532 ./ max(E, 532)) .^ 1.5;
I = bg + cK + oK;

ctx = struct('setStatus', @(~) []);
api = [];

% ═══════════════════════════════════════════════════════════════════════
%  TEST 1: open
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 1: open ══\n');
try
    api = fermiViewer.eels.openEELSQuantWorkshop(E, I, ctx);
    assert(isvalid(api.fig), 'workshop figure should be valid');
    fprintf('  PASS\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 2: set edges + compute → two elements, at% sums to 100
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 2: compute composition ══\n');
try
    api.setBeam(200, 10);
    api.setEdges({'C','K',284,100; 'O','K',532,100});
    api.compute();
    r = api.getResult();
    assert(isfield(r,'valid') && r.valid, 'result should be valid');
    assert(numel(r.element) == 2, sprintf('expected 2 elements, got %d', numel(r.element)));
    assert(abs(sum(r.atomicPercent) - 100) < 1e-6, 'at% should sum to 100');
    assert(all(r.atomicPercent > 0 & r.atomicPercent < 100), 'at% in (0,100)');
    assert(all(r.sigma > 0), 'cross-sections should be positive');
    fprintf('  PASS (%s %.1f%% / %s %.1f%%)\n', char(r.element(1)), r.atomicPercent(1), ...
        char(r.element(2)), r.atomicPercent(2));
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 3: CSV export
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 3: export CSV ══\n');
try
    tmp = [tempname '.csv'];
    api.exportCSV(tmp);
    assert(isfile(tmp), 'CSV should be written');
    txt = readlines(tmp); txt = txt(strlength(txt) > 0);
    assert(numel(txt) == 3, sprintf('expected header + 2 rows, got %d', numel(txt)));
    delete(tmp);
    fprintf('  PASS\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 4: too-few-edges guard (no crash, no result)
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 4: single-edge guard ══\n');
try
    api2 = fermiViewer.eels.openEELSQuantWorkshop(E, I, ctx);
    api2.setEdges({'C','K',284,100});   % only one complete row
    api2.compute();
    r2 = api2.getResult();
    assert(~(isfield(r2,'valid') && r2.valid), 'one edge must not yield a result');
    close(api2.fig);
    fprintf('  PASS (rejected single edge)\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 5: composition maps (spectrum-image cube path)
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 5: composition maps from cube ══\n');
try
    Ny = 4; Nx = 6;
    cube = repmat(reshape(I, 1, 1, []), Ny, Nx, 1);
    api3 = fermiViewer.eels.openEELSQuantWorkshop(E, I, ctx, cube);
    api3.setBeam(200, 10);
    api3.setEdges({'C','K',284,100; 'O','K',532,100});
    api3.computeMaps();
    rm = api3.getMapResult();
    assert(isfield(rm,'valid') && rm.valid, 'map result should be valid');
    assert(isequal(size(rm.atomicPercent), [Ny Nx 2]), ...
        sprintf('expected [%d %d 2] at%% maps, got %s', Ny, Nx, mat2str(size(rm.atomicPercent))));
    totalMap = sum(rm.atomicPercent, 3);
    assert(max(abs(totalMap(:) - 100)) < 1e-6, 'per-pixel at% should sum to 100');
    api3.close();   % must close BOTH the workshop and the maps figure
    fprintf('  PASS ([%d x %d] maps, per-pixel sum 100)\n', Ny, Nx);
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 6: no-cube guard — computeMaps without a cube must not produce
%  a result (and must not crash)
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 6: no-cube guard ══\n');
try
    api4 = fermiViewer.eels.openEELSQuantWorkshop(E, I, ctx);
    api4.setEdges({'C','K',284,100; 'O','K',532,100});
    api4.computeMaps();
    rm4 = api4.getMapResult();
    assert(~(isfield(rm4,'valid') && rm4.valid), 'no cube must not yield map result');
    api4.close();
    fprintf('  PASS (rejected map compute without cube)\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 7: result table "± at%" column — positive, finite (window integration)
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 7: at%% sigma column (window integration) ══\n');
try
    r7 = api.getResult();
    assert(isfield(r7, 'atomicPercentSigma') && ~isempty(r7.atomicPercentSigma), ...
        'result should carry atomicPercentSigma');
    assert(all(isfinite(r7.atomicPercentSigma)) && all(r7.atomicPercentSigma > 0), ...
        'atomicPercentSigma should be positive and finite');

    tbl7 = findResultTable(api.fig);
    data7 = tbl7.Data;
    assert(size(data7, 2) == 5, sprintf('expected 5 columns, got %d', size(data7,2)));
    for i = 1:size(data7, 1)
        sigmaVal = str2double(data7{i,3});
        assert(isfinite(sigmaVal) && sigmaVal > 0, ...
            sprintf('row %d: rendered "± at%%" = "%s" should be positive/finite', i, data7{i,3}));
    end
    fprintf('  PASS (rendered ± at%% column positive/finite)\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 8: sigma-absent fallback — renders at% alone, never "NaN"
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 8: sigma-absent fallback ══\n');
api5 = [];
try
    api5 = fermiViewer.eels.openEELSQuantWorkshop(E, I, ctx);

    % "Older cached result": no atomicPercentSigma field at all.
    fakeMissing = struct('element', ["Mg","Al"], 'atomicPercent', [55 45], ...
        'intensity', [12.3 9.8], 'sigma', [1.1e-23 1.4e-23]);
    % A degenerate fit: the field is present but non-finite.
    fakeNonFinite = struct('element', ["Mg","Al"], 'atomicPercent', [55 45], ...
        'intensity', [12.3 9.8], 'sigma', [1.1e-23 1.4e-23], ...
        'atomicPercentSigma', [NaN, Inf]);

    fakes = {fakeMissing, fakeNonFinite};
    for fk = 1:numel(fakes)
        api5.renderResult(fakes{fk}, 'Window integration');
        tbl8 = findResultTable(api5.fig);
        data8 = tbl8.Data;
        assert(strcmp(data8{1,2}, '55.0') && strcmp(data8{2,2}, '45.0'), ...
            sprintf('case %d: at%% must render even when sigma is unavailable', fk));
        assert(isempty(data8{1,3}) && isempty(data8{2,3}), ...
            sprintf('case %d: "± at%%" must render blank, not NaN, when unavailable', fk));
    end
    api5.close();
    fprintf('  PASS (blank sigma rendered without error, at%% still shown)\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
    try, if ~isempty(api5) && isvalid(api5.fig), close(api5.fig); end, catch, end
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 9: Method="Model fit" — at% sums to 100 and agrees with window
%  integration within a few percentage points on well-separated edges.
%  Spectrum built from imaging.eels.eelsEdgeShape (the same shape function
%  both eelsQuantify's cross-section and eelsFitEdges' model term key off
%  of), so this is a sanity check that the Method wiring passes the right
%  inputs through, not a numerical-accuracy test of either analysis path.
%  Uses O-K(532)/Fe-L(708) rather than this file's usual C-K/O-K pair:
%  two SAME-SHELL edges (both K, identical high-energy falloff exponent)
%  are nearly power-law-collinear with each other and the background over
%  a narrow (~4x) energy range, which starves eelsFitEdges' linear solve of
%  the conditioning it needs and its recovered ratio drifts tens of
%  points off — a real numerical-conditioning fact about the joint fit,
%  not a wiring bug. O-K/Fe-L (K vs L, differing falloff) is the same
%  well-conditioned pair test_eels_model.m validates against a known
%  planted ratio; mirroring it here isolates the sanity check this test
%  is actually for (does Method="Model fit" route the right inputs).
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 9: model fit vs window integration ══\n');
api6 = [];
try
    edges9 = [makeEdgeStruct('O','K',8,532.0), makeEdgeStruct('Fe','L',26,708.0)];
    E9 = linspace(250.0, 950.0, 700)';
    spec9 = synthEdgeSpectrum(E9, edges9, [2.0e27, 1.0e27], 200.0, 10.0, 5.0e5, 3.0);

    api6 = fermiViewer.eels.openEELSQuantWorkshop(E9, spec9, ctx);
    api6.setBeam(200, 10);
    api6.setEdges({'O','K',532,100; 'Fe','L',708,100});

    api6.setMethod('Window integration');
    api6.compute();
    rWin = api6.getResult();
    assert(isfield(rWin,'valid') && rWin.valid, 'window-integration result should be valid');

    api6.setMethod('Model fit');
    api6.compute();
    rFit = api6.getResult();
    assert(isfield(rFit,'valid') && rFit.valid, 'model-fit result should be valid');
    assert(abs(sum(rFit.atomicPercent) - 100) < 1e-6, ...
        sprintf('model-fit at%% should sum to 100, got %.6f', sum(rFit.atomicPercent)));

    idxWinO = find(rWin.element == "O"); idxFitO = find(rFit.element == "O");
    idxWinFe = find(rWin.element == "Fe"); idxFitFe = find(rFit.element == "Fe");
    diffO = abs(rFit.atomicPercent(idxFitO) - rWin.atomicPercent(idxWinO));
    diffFe = abs(rFit.atomicPercent(idxFitFe) - rWin.atomicPercent(idxWinFe));
    assert(diffO < 5 && diffFe < 5, ...
        sprintf('model fit vs window integration mismatch too large (O: %.2f, Fe: %.2f pts)', ...
        diffO, diffFe));

    api6.close();
    fprintf('  PASS (window: O=%.1f%%/Fe=%.1f%%, model: O=%.1f%%/Fe=%.1f%%)\n', ...
        rWin.atomicPercent(idxWinO), rWin.atomicPercent(idxWinFe), ...
        rFit.atomicPercent(idxFitO), rFit.atomicPercent(idxFitFe));
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
    try, if ~isempty(api6) && isvalid(api6.fig), close(api6.fig); end, catch, end
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 10: model-fit overlay curves replace (not stack) on re-run, and
%  clear when the Method is switched back to window integration.
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 10: model-fit overlay replace-not-stack ══\n');
api7 = [];
try
    api7 = fermiViewer.eels.openEELSQuantWorkshop(E, I, ctx);
    api7.setBeam(200, 10);
    api7.setEdges({'C','K',284,100; 'O','K',532,100});
    api7.setMethod('Model fit');
    api7.compute();
    n1 = numel(findobj(api7.fig, 'Tag', 'eelsFitOverlay'));
    assert(n1 > 0, 'model fit should draw tagged overlay curves');

    api7.compute();   % re-run with identical inputs: must replace, not stack
    n2 = numel(findobj(api7.fig, 'Tag', 'eelsFitOverlay'));
    assert(n2 == n1, sprintf('overlay curve count should stay constant (was %d, now %d)', n1, n2));

    api7.setMethod('Window integration');   % switching method clears the overlay
    n3 = numel(findobj(api7.fig, 'Tag', 'eelsFitOverlay'));
    assert(n3 == 0, sprintf('switching to window integration should clear overlay (found %d)', n3));

    api7.close();
    fprintf('  PASS (%d overlay curves, stable across re-run, cleared on method switch)\n', n1);
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
    try, if ~isempty(api7) && isvalid(api7.fig), close(api7.fig); end, catch, end
end

% ── Cleanup ──────────────────────────────────────────────────────────────
try, if ~isempty(api) && isvalid(api.fig), close(api.fig); end, catch, end

fprintf('\n');
fprintf('╔══════════════════════════════════════════════════════════════╗\n');
fprintf('║ Results: %2d passed, %2d failed                                ║\n', passed, failed);
fprintf('╚══════════════════════════════════════════════════════════════╝\n');

if failed > 0
    error('test_fv_eelsQuantWorkshop: %d test(s) failed', failed);
end

% ── Helpers (local functions at end of script — required for R2022b) ──
function tbl = findResultTable(fig)
%FINDRESULTTABLE  Locate the workshop's result uitable (as opposed to the
%   edges-input uitable) by column name, since findobj(fig,'Type','uitable')
%   returns both tables in this GUI.
    tbls = findobj(fig, 'Type', 'uitable');
    for k = 1:numel(tbls)
        cn = tbls(k).ColumnName;
        if iscell(cn) && ~isempty(cn) && any(strcmpi(cn, 'at%'))
            tbl = tbls(k);
            return;
        end
    end
    error('test_fv_eelsQuantWorkshop:findResultTable', 'result table not found');
end

function e = makeEdgeStruct(element, shell, Z, onsetEV)
%MAKEEDGESTRUCT  Build one imaging.eels.eelsFitEdges `edges`/eelsQuantify
%   `elements` struct entry (element/shell/Z/onsetEV subset both accept).
    e = struct('element', element, 'shell', string(shell), 'Z', Z, 'onsetEV', onsetEV);
end

function spec = synthEdgeSpectrum(E, edges, areal, E0kV, betaMrad, bgAmp, r)
%SYNTHEDGESPECTRUM  power-law background + sum(areal_X * dsigma_X/dE) —
%   built directly from imaging.eels.eelsEdgeShape (the SAME shape function
%   eelsQuantify's cross-section and eelsFitEdges' model term key off of;
%   see test_eels_model.m's identically-named helper), so recovering
%   `areal`'s ratio back out via EITHER Method is a genuine round-trip
%   check that the Method wiring passes the right inputs.
    spec = bgAmp * max(E, 1e-12) .^ (-r);
    for k = 1:numel(edges)
        el = edges(k);
        fn = imaging.eels.eelsEdgeShape( ...
            double(el.Z), string(el.shell), E0kV, betaMrad, double(el.onsetEV));
        spec = spec + areal(k) * fn(E);
    end
end
