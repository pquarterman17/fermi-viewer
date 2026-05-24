%TEST_UNDORESTORESSTATE  Undo must restore image DATA, not just redraw.
%
%   Run from root:  runAllTests(Group="fvgui")
%
%   Regression for the closure-mutation-ordering bug ("can't undo a crop"):
%   package functions (captureDispatch crop, filterOps, processActions,
%   rotateFlip) pushed/popped undo state via fire-and-forget closure
%   callbacks (cb.undoPush / cb.undoPop), then returned their own local
%   appData which clobbered the push/pop. The snapshot was silently lost,
%   so operations that change rawPixels (crop, rotate) could not be undone.
%   Fixed by accept-and-return: fermiViewer.display.pushUndo(appData) for
%   pushes, and handling 'undoFilters' in the onFilterOp closure for pops.
%
%   These assert the DATA EXTENT is restored (image XData/YData), which is
%   the ground truth — CData can legitimately differ when the display
%   buffer is downsampled for rendering.

clear; clc;
thisDir = fileparts(mfilename('fullpath'));
ROOT    = fileparts(fileparts(thisDir));
if ~contains(path, ROOT), addpath(ROOT); end

passed = 0; failed = 0;

% Synthetic non-uniform image so filters/rotate are observable.
img = uint16(repmat(linspace(0, 60000, 128), 128, 1) + (1:128)');
tf  = fullfile(tempdir, 'undo_regression.tif'); imwrite(img, tf);
cleanupTif = onCleanup(@() iSafeDelete(tf));

% ════════════════════════════════════════════════════════════════════════
%  TEST 1 — Crop, then undo restores full dimensions
% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 1: undo a crop ══\n');
api = FermiViewer('Visible', 'off');
try
    api.loadImages({tf}); api.setActiveIdx(1); drawnow;
    sz0 = mainExtent(api.fig);
    assert(isequal(sz0, [128 128]), sprintf('pre-crop extent %dx%d', sz0(1), sz0(2)));

    api.cropRect(10, 10, 50, 50); drawnow;
    szc = mainExtent(api.fig);
    assert(~isequal(szc, sz0), 'crop should shrink the image');

    pressUndo(api); drawnow;
    szu = mainExtent(api.fig);
    assert(isequal(szu, sz0), ...
        sprintf('crop-undo must restore %dx%d, got %dx%d', sz0(1), sz0(2), szu(1), szu(2)));
    fprintf('  Crop undo restored %dx%d: PASS\n', szu(1), szu(2));
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end
try, api.close(); catch, end

% ════════════════════════════════════════════════════════════════════════
%  TEST 2 — Rotate 90°, then undo restores orientation/dimensions
% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 2: undo a rotate ══\n');
api = FermiViewer('Visible', 'off');
try
    api.loadImages({tf}); api.setActiveIdx(1); drawnow;
    % rot90cw changes dims (square here) and pixel arrangement; detect via
    % a horizontal line profile, which differs after a 90° rotation and
    % must be restored on undo.
    before = api.getLineProfile(1, 64, 128, 64);

    api.rotateFlip('rot90cw'); drawnow;
    rotated = api.getLineProfile(1, 64, 128, 64);
    assert(max(abs(rotated.intensity - before.intensity)) > 1e-6, ...
        'rotate should change the profile');

    pressUndo(api); drawnow;
    after = api.getLineProfile(1, 64, 128, 64);
    assert(max(abs(after.intensity - before.intensity)) < 1e-6, ...
        'rotate-undo must restore the original profile');
    fprintf('  Rotate undo restored original profile: PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end
try, api.close(); catch, end

% ════════════════════════════════════════════════════════════════════════
%  TEST 3 — Filter, then undo restores pixel values
% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 3: undo a filter (pixel values) ══\n');
api = FermiViewer('Visible', 'off');
try
    api.loadImages({tf}); api.setActiveIdx(1); drawnow;
    before = api.getLineProfile(1, 64, 128, 64);

    api.applyFilter('gaussian', struct('Sigma', 3.0)); drawnow;
    blurred = api.getLineProfile(1, 64, 128, 64);
    assert(max(abs(blurred.intensity - before.intensity)) > 1e-6, ...
        'filter should change pixel values');

    pressUndo(api); drawnow;
    after = api.getLineProfile(1, 64, 128, 64);
    assert(max(abs(after.intensity - before.intensity)) < 1e-6, ...
        'filter-undo must restore original pixel values');
    fprintf('  Filter undo restored pixel values: PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end
try, api.close(); catch, end

% ── Summary ────────────────────────────────────────────────────────────
fprintf('\n════════════════════════════════════════════════\n');
fprintf('  UNDO RESTORE: %d / %d passed\n', passed, passed + failed);
fprintf('════════════════════════════════════════════════\n');
if failed > 0
    error('test_undoRestoresState:failures', '%d test(s) failed.', failed);
end
fprintf('\n✓ Undo restores state.\n\n');

% ── Helpers (local functions at end of script — required for R2022b) ──
function s = mainExtent(fig)
    axs = findall(fig, 'Type', 'axes');
    if isempty(axs), s = [0 0]; return; end
    areas = arrayfun(@(a) a.Position(3)*a.Position(4), axs);
    [~, k] = max(areas);
    h = findall(axs(k), 'Type', 'image');
    if isempty(h), s = [0 0]; return; end
    s = [round(h(1).YData(end)), round(h(1).XData(end))];
end

function pressUndo(api)
    b = findall(api.fig, 'Type', 'uibutton', 'Text', 'Undo Filters');
    assert(~isempty(b), 'Undo Filters button must exist');
    b(1).ButtonPushedFcn(b(1), []);
end

function iSafeDelete(p)
    if isfile(p), try, delete(p); catch, end, end
end
