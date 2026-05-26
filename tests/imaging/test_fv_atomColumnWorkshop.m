%TEST_FV_ATOMCOLUMNWORKSHOP  Headless API test for the atom-column window.
%
%   Drives fermiViewer.atomcolumns.openAtomColumnWorkshop through its
%   programmatic `api` (no real mouse / dialogs) under headless figures:
%     1. window opens; Detect + Fit finds the lattice columns
%     2. PPA strain computes against the average lattice
%     3. overlay switching (markers / sublattice / strain) does not error
%     4. CSV export writes header + one row per column
%     5. dark-polarity detection works
%
%   Run:
%       run tests/imaging/test_fv_atomColumnWorkshop
%       runAllTests(Group="fvgui")

fprintf('\n');
fprintf('╔══════════════════════════════════════════════════════════════╗\n');
fprintf('║  AtomColumnWorkshop headless API                             ║\n');
fprintf('╚══════════════════════════════════════════════════════════════╝\n');

ROOT = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(ROOT);

passed = 0;
failed = 0;

set(groot, 'DefaultFigureVisible', 'off');

% Synthetic 8x8 square lattice of bright Gaussian columns.
d = 16; nx = 8; ny = 8; sigma = 2.5;
[Mg, Ng] = meshgrid(0:nx, 0:ny);
pos = [28 28] + Mg(:) .* [d 0] + Ng(:) .* [0 d];
[Xc, Yc] = meshgrid(1:170, 1:170);
img = zeros(170, 170);
for i = 1:size(pos,1)
    img = img + exp(-0.5 * ((Xc - pos(i,1)).^2 + (Yc - pos(i,2)).^2) / sigma^2);
end
nTrue = size(pos, 1);

ctx = struct('setStatus', @(~) [], 'guiPixelSize', @() 0.2, 'guiPixelUnit', @() "nm");
api = [];

% ═══════════════════════════════════════════════════════════════════════
%  TEST 1: open + detect/fit
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 1: open + detect/fit ══\n');
try
    api = fermiViewer.atomcolumns.openAtomColumnWorkshop(img, ctx);
    assert(isvalid(api.fig), 'workshop figure should be valid');
    api.model.minSep = 10; api.model.threshold = 0.15;
    api.detect();
    r = api.getResult();
    n = size(r.positions, 1);
    assert(n >= 0.9 * nTrue && n <= nTrue + 4, ...
        sprintf('detect should find ~%d columns, got %d', nTrue, n));
    assert(r.lattice.valid, 'lattice vectors should resolve');
    assert(r.meanRsq > 0.9, sprintf('median fit R^2 low: %.3f', r.meanRsq));
    fprintf('  PASS (%d columns, R²=%.3f)\n', n, r.meanRsq);
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 2: PPA strain
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 2: PPA strain ══\n');
try
    api.computeStrain();
    r = api.getResult();
    assert(r.strain.valid, 'strain should be valid');
    % Unstrained synthetic lattice -> near-zero median strain.
    assert(abs(median(r.strain.exx, 'omitnan')) < 0.01, 'unstrained exx should be ~0');
    fprintf('  PASS (median εxx=%.4f)\n', median(r.strain.exx, 'omitnan'));
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 3: overlay switching does not error
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 3: overlay switching ══\n');
try
    for o = ["markers", "sublattice", "exx", "eyy", "exy", "rotation"]
        api.setOverlay(o);
    end
    assert(isvalid(api.fig), 'figure should survive overlay switching');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 4: CSV export (programmatic, no dialog)
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 4: export CSV ══\n');
try
    tmp = [tempname '.csv'];
    api.exportCSV(tmp);
    assert(isfile(tmp), 'CSV should be written');
    txt = readlines(tmp);
    txt = txt(strlength(txt) > 0);
    n = size(api.getResult().positions, 1);
    assert(numel(txt) == n + 1, ...
        sprintf('expected %d lines (header + columns), got %d', n + 1, numel(txt)));
    delete(tmp);
    fprintf('  PASS (header + %d column rows)\n', n);
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 5: dark polarity
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 5: dark polarity ══\n');
try
    darkApi = fermiViewer.atomcolumns.openAtomColumnWorkshop(max(img(:)) - img, ctx);
    darkApi.setPolarity('dark');
    darkApi.model.minSep = 10; darkApi.model.threshold = 0.15;
    darkApi.detect();
    n = size(darkApi.getResult().positions, 1);
    assert(n >= 0.9 * nTrue, sprintf('dark detect found %d of %d', n, nTrue));
    close(darkApi.fig);
    fprintf('  PASS (dark: %d columns)\n', n);
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ── Cleanup ──────────────────────────────────────────────────────────────
try, if ~isempty(api) && isvalid(api.fig), close(api.fig); end, catch, end

% ── Summary ────────────────────────────────────────────────────────────
fprintf('\n');
fprintf('╔══════════════════════════════════════════════════════════════╗\n');
fprintf('║ Results: %2d passed, %2d failed                                ║\n', passed, failed);
fprintf('╚══════════════════════════════════════════════════════════════╝\n');

if failed > 0
    error('test_fv_atomColumnWorkshop: %d test(s) failed', failed);
end
