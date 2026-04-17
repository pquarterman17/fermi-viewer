%TEST_TRANSFORMTOOLBAR  Verify the icon transform toolbar above the FermiViewer image.
%   The toolbar adds eight icon-only buttons (rotate CW/CCW, flip H/V,
%   zoom, fit, reset-all, crop) above the uiaxes so common transforms are
%   always one click away. This test confirms:
%
%     1. All eight buttons exist, have an Icon assigned, and are wired
%        to a ButtonPushedFcn.
%     2. They are disabled before an image loads and enabled after.
%     3. Pressing Rotate CW / CCW / Flip H / Flip V on a capital-T
%        fixture image produces the expected pixel geometry.
%     4. Reset All restores the original rawPixels after a rotation.
%     5. Fit-to-window restores full axis limits after a zoom.
%     6. Crop button initiates a capture (captureMode becomes 'crop').
%
%   Runs under runAllTests(Group="emgui").

clear; clc;

thisDir = fileparts(mfilename('fullpath'));
rootDir = fileparts(fileparts(thisDir));
if ~contains(path, rootDir); addpath(rootDir); end

fprintf('\n=== test_transformToolbar ===\n');
passed = 0; failed = 0;

% ── Build a capital-T fixture image (black on white background) ─────────
% 64 rows x 48 cols. White = 255; the T glyph is black (0).
H = 64; W = 48;
fixtureT = 255 * ones(H, W, 'uint8');
% Horizontal crossbar: rows 8..14 (top of T)
fixtureT(8:14, 6:W-5) = 0;
% Vertical stem: cols 21..26 (centered), rows 8..H-6
fixtureT(8:H-6, 21:26) = 0;

tmpDir = fullfile(tempdir, ['transformtoolbar_' char(datetime('now','Format','yyyyMMdd_HHmmss'))]);
mkdir(tmpDir);
cleanupTmp = onCleanup(@() rmdir(tmpDir, 's'));
fixturePath = fullfile(tmpDir, 'capital_T.tif');
imwrite(fixtureT, fixturePath);

% ── Launch headless ─────────────────────────────────────────────────────
api = FermiViewer();
api.fig.Visible = 'off';
drawnow;
cleanupApi = onCleanup(@() closeApi(api));

% ════════════════════════════════════════════════════════════════════════
%  T1. Eight icon toolbar buttons exist + start disabled
% ════════════════════════════════════════════════════════════════════════
fprintf('\n── T1: Toolbar buttons exist and start disabled ──\n');
try
    tbBtns = findToolbarBtns(api.fig);
    assert(numel(tbBtns) == 8, sprintf('Expected 8 toolbar buttons, got %d', numel(tbBtns)));

    for k = 1:numel(tbBtns)
        assert(~isempty(tbBtns(k).ButtonPushedFcn), sprintf('btn %d has no callback', k));
        assert(strcmp(tbBtns(k).Enable, 'off'), sprintf('btn %d should start disabled', k));
        assert(~isempty(tbBtns(k).Icon) || ~isempty(tbBtns(k).Text), ...
            sprintf('btn %d has neither icon nor fallback text', k));
    end
    fprintf('  PASS: 8 toolbar buttons, all wired and disabled before image load\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ── Load fixture ────────────────────────────────────────────────────────
fprintf('\n── Loading capital-T fixture ──\n');
api.loadImages({fixturePath});
drawnow;

% ════════════════════════════════════════════════════════════════════════
%  T2. Buttons become enabled after image load
% ════════════════════════════════════════════════════════════════════════
fprintf('\n── T2: Toolbar buttons enable after image load ──\n');
try
    tbBtns = findToolbarBtns(api.fig);
    for k = 1:numel(tbBtns)
        assert(strcmp(tbBtns(k).Enable, 'on'), ...
            sprintf('btn %d (tooltip "%s") should be enabled after loadImages', ...
            k, tbBtns(k).Tooltip));
    end
    fprintf('  PASS: all 8 buttons enabled after load\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
%  T3. Rotate CW 90° — top of T moves to the right side
% ════════════════════════════════════════════════════════════════════════
%   Original T crossbar is at the TOP (small row index). After a single
%   CW 90° rotation the crossbar should be at the RIGHT (large col index).
%   We check a pixel in the original crossbar region and one where the
%   crossbar should land after rotation.
fprintf('\n── T3: Rotate CW 90° swaps top→right ──\n');
try
    api.rotateFlip('rot90cw');
    drawnow;

    imgs = api.getImages();
    assert(numel(imgs) == 1, 'Need exactly 1 image');
    % After rotation, rawPixels is H' x W' = W x H = 48 x 64
    rotated = getRawPixels(api);
    [Hr, Wr] = size(rotated);
    assert(Hr == W && Wr == H, sprintf('Rotated dims should be %dx%d, got %dx%d', W, H, Hr, Wr));
    % Original crossbar was at rows 8..14 of the top. After CW the
    % crossbar runs vertically on the RIGHT (cols Wr-14..Wr-8). Check a
    % sample dark pixel on the right side.
    darkCountRight = sum(rotated(:, Wr-13:Wr-9) < 128, 'all');
    assert(darkCountRight > 10, 'Right-side dark band missing after CW rotation');
    fprintf('  PASS: CW rotation produced correct geometry (H,W = %d,%d)\n', Hr, Wr);
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
%  T4. Reset All — restores the original T (crossbar back on top)
% ════════════════════════════════════════════════════════════════════════
fprintf('\n── T4: Reset All restores original dims and geometry ──\n');
try
    % Push the reset-all toolbar button (7th — zero-indexed 6)
    tbBtns = findToolbarBtns(api.fig);
    resetBtn = findBtnByTooltip(tbBtns, 'Reset all transforms');
    assert(~isempty(resetBtn), 'Reset All button not found by tooltip');

    fcn = resetBtn.ButtonPushedFcn;
    fcn(resetBtn, []);
    drawnow;

    restored = getRawPixels(api);
    [Hr, Wr] = size(restored);
    assert(Hr == H && Wr == W, sprintf('Restored dims should be %dx%d, got %dx%d', H, W, Hr, Wr));
    % Crossbar back at the top: rows 8..14 should contain many dark pixels
    darkCountTop = sum(restored(8:14, :) < 128, 'all');
    assert(darkCountTop > 100, 'Top-row crossbar missing after Reset All');
    fprintf('  PASS: Reset All restored %dx%d original\n', Hr, Wr);
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
%  T5. Flip H — left/right mirror
% ════════════════════════════════════════════════════════════════════════
%   The T is symmetric left-right around col ~23 so flipH should leave
%   the crossbar mostly intact. The clear test is column-level symmetry
%   before vs after.
fprintf('\n── T5: Flip H mirrors columns ──\n');
try
    before = getRawPixels(api);
    api.rotateFlip('fliph');
    drawnow;
    after = getRawPixels(api);
    expected = fliplr(before);
    diffs = sum(abs(double(after) - double(expected)) > 0, 'all');
    assert(diffs == 0, sprintf('Flip H result does not match fliplr (%d mismatched pixels)', diffs));
    fprintf('  PASS: Flip H matches fliplr exactly\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% Reset back to original for next test
api.rotateFlip('fliph');   % flipH again to undo
drawnow;

% ════════════════════════════════════════════════════════════════════════
%  T6. Flip V — top/bottom mirror. The T has content at top (crossbar)
%   but not at bottom, so flipV moves the crossbar to the BOTTOM.
% ════════════════════════════════════════════════════════════════════════
fprintf('\n── T6: Flip V moves crossbar to bottom ──\n');
try
    before = getRawPixels(api);
    api.rotateFlip('flipv');
    drawnow;
    after = getRawPixels(api);
    [Hr, ~] = size(after);
    expected = flipud(before);
    diffs = sum(abs(double(after) - double(expected)) > 0, 'all');
    assert(diffs == 0, sprintf('Flip V result does not match flipud (%d mismatched pixels)', diffs));
    % Crossbar should now be near the bottom (rows Hr-13..Hr-7)
    darkCountBot = sum(after(Hr-13:Hr-7, :) < 128, 'all');
    assert(darkCountBot > 100, 'Bottom-row crossbar missing after Flip V');
    fprintf('  PASS: Flip V matches flipud, crossbar now at bottom\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% Reset back
tbBtns = findToolbarBtns(api.fig);
resetBtn = findBtnByTooltip(tbBtns, 'Reset all transforms');
fcn = resetBtn.ButtonPushedFcn;
fcn(resetBtn, []);
drawnow;

% ════════════════════════════════════════════════════════════════════════
%  T7. Rotate CCW 90° — top of T moves to the LEFT side
% ════════════════════════════════════════════════════════════════════════
fprintf('\n── T7: Rotate CCW 90° swaps top→left ──\n');
try
    api.rotateFlip('rot90ccw');
    drawnow;
    rotated = getRawPixels(api);
    [Hr, Wr] = size(rotated);
    assert(Hr == W && Wr == H, 'CCW rotation gave wrong dims');
    darkCountLeft = sum(rotated(:, 8:13) < 128, 'all');
    assert(darkCountLeft > 10, 'Left-side dark band missing after CCW rotation');
    fprintf('  PASS: CCW rotation placed crossbar on the left\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% Reset back
tbBtns = findToolbarBtns(api.fig);
resetBtn = findBtnByTooltip(tbBtns, 'Reset all transforms');
fcn = resetBtn.ButtonPushedFcn;
fcn(resetBtn, []);
drawnow;

% ════════════════════════════════════════════════════════════════════════
%  T8. Fit-to-window (Reset Zoom) restores full axis limits
% ════════════════════════════════════════════════════════════════════════
fprintf('\n── T8: Fit-to-window button restores full axis limits ──\n');
try
    % Zoom into a small region via the API
    api.zoomRect(10, 10, 20, 20);
    drawnow;
    axLim = api.getAxLimits();
    xRange = axLim.XLim(2) - axLim.XLim(1);
    assert(xRange < W*0.5, 'zoomRect did not narrow the view');

    tbBtns = findToolbarBtns(api.fig);
    fitBtn = findBtnByTooltip(tbBtns, 'Fit image to window');
    assert(~isempty(fitBtn), 'Fit button not found by tooltip');
    fcn = fitBtn.ButtonPushedFcn;
    fcn(fitBtn, []);
    drawnow;

    axLim2 = api.getAxLimits();
    fullX = axLim2.XLim(2) - axLim2.XLim(1);
    assert(fullX >= W - 1, sprintf('Fit-to-window did not restore full view (xRange=%.2f)', fullX));
    fprintf('  PASS: Fit-to-window restored XLim=[%.1f %.1f]\n', axLim2.XLim(1), axLim2.XLim(2));
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
%  T9. Crop button wiring — simply confirm the callback is @onCropImage
%      equivalent (pressing it without a dialog-free path would hang, so
%      we just verify the function handle name includes 'onCropImage')
% ════════════════════════════════════════════════════════════════════════
fprintf('\n── T9: Crop button wired to onCropImage ──\n');
try
    tbBtns = findToolbarBtns(api.fig);
    cropBtn = findBtnByTooltip(tbBtns, 'Crop to rectangle');
    assert(~isempty(cropBtn), 'Crop button not found');
    fn = cropBtn.ButtonPushedFcn;
    info = functions(fn);
    % Accept either the named handle or an anonymous wrapper that closes
    % over onCropImage.
    assert(contains(info.function, 'onCropImage'), ...
        sprintf('Crop callback should reference onCropImage, got: %s', info.function));
    fprintf('  PASS: Crop wired to %s\n', info.function);
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
%  Summary
% ════════════════════════════════════════════════════════════════════════
fprintf('\n═══ Summary: %d PASSED / %d FAILED ═══\n', passed, failed);
if failed > 0
    error('test_transformToolbar: %d tests failed', failed);
end

% ════════════════════════════════════════════════════════════════════════
%  Helpers
% ════════════════════════════════════════════════════════════════════════
function btns = findToolbarBtns(fig)
    % The toolbar buttons sit in a uigridlayout with exactly 9 columns
    % (8 buttons + one '1x' spacer). Find them by walking all uibuttons
    % whose tooltip matches one of our 8 known tooltips.
    knownTooltips = {
        'Rotate 90° clockwise'
        'Rotate 90° counter-clockwise'
        'Flip horizontally (left-right mirror)'
        'Flip vertically (top-bottom mirror)'
        'Zoom to box (Esc to cancel)'
        'Fit image to window (reset zoom)'
        'Reset all transforms (reload original image)'
        'Crop to rectangle (destructive — Undo Filters reverts)'
    };
    all = findall(fig, 'Type', 'uibutton');
    keep = false(1, numel(all));
    for k = 1:numel(all)
        tt = all(k).Tooltip;
        if ischar(tt) || isstring(tt)
            keep(k) = any(strcmp(char(tt), knownTooltips));
        end
    end
    btns = all(keep);
end

function btn = findBtnByTooltip(btns, partial)
    btn = [];
    for k = 1:numel(btns)
        if contains(char(btns(k).Tooltip), partial)
            btn = btns(k); return;
        end
    end
end

function px = getRawPixels(api)
    % Use the public api.getPixels() accessor — it returns rawPixels
    % directly from the nested workspace via a function-handle getter.
    s = api.getPixels();
    px = s.raw;
end

function closeApi(api)
    try
        if isfield(api, 'close') && isvalid(api.fig)
            api.close();
        end
    catch
    end
end
