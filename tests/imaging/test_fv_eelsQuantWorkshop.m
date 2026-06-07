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

% ── Cleanup ──────────────────────────────────────────────────────────────
try, if ~isempty(api) && isvalid(api.fig), close(api.fig); end, catch, end

fprintf('\n');
fprintf('╔══════════════════════════════════════════════════════════════╗\n');
fprintf('║ Results: %2d passed, %2d failed                                ║\n', passed, failed);
fprintf('╚══════════════════════════════════════════════════════════════╝\n');

if failed > 0
    error('test_fv_eelsQuantWorkshop: %d test(s) failed', failed);
end
