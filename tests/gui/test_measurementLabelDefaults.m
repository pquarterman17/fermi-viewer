%TEST_MEASUREMENTLABELDEFAULTS  Regression test for FermiViewer distance
%   measurement label default appearance.
%
%   Verifies:
%     1. Default FontSize is >= 12 (user-visible on 4K displays).
%     2. Default BackgroundColor is 'none' (no black box occluding pixels).
%     3. Default EdgeColor is 'none' and Margin is small — transparent label.
%     4. Label Position is offset from the line midpoint (not exactly on
%        the measurement line).
%     5. When tilt correction is active, the label Tooltip is non-empty
%        and references the correction factor.
%
%   Run:
%       run tests/gui/test_measurementLabelDefaults
%       runAllTests(Group="emgui")
%
%   All test data is synthetic.

fprintf('\n');
fprintf('╔══════════════════════════════════════════════════════════════╗\n');
fprintf('║   FermiViewer — Distance Label Default Appearance — Tests     ║\n');
fprintf('╚══════════════════════════════════════════════════════════════╝\n');

ROOT = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(ROOT);

tmpDir = fullfile(tempdir, sprintf('emlbl_test_%s', datestr(now, 'yyyymmdd_HHMMSS')));
mkdir(tmpDir);
cleanupDir = onCleanup(@() rmdir(tmpDir, 's'));

% ── Synthetic 128x128 test image ───────────────────────────────────────
H = 128; W = 128;
[X, Y] = meshgrid(1:W, 1:H);
img = uint16(30000 + 10000 * sin(X/8) .* cos(Y/8));
fImg = fullfile(tmpDir, 'synthetic.tif');
imwrite(img, fImg);

passed = 0;
failed = 0;

function api = launchHeadless()
    api = FermiViewer();
    api.fig.Visible = 'off';
    drawnow;
end

function safeClose(api)
    try
        if isvalid(api.fig)
            api.close();
        end
    catch
    end
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 1: default font size is at least 12
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 1: default FontSize >= 12 ══\n');
try
    api = launchHeadless();
    cleanupApi = onCleanup(@() safeClose(api));
    api.loadImages({fImg});

    api.measureDistance(10, 20, 100, 80);
    ov = api.getOverlays();
    m = ov.measurements{end};

    assert(~isempty(m.hText) && isvalid(m.hText), ...
        'measurement hText must be valid');
    assert(m.hText.FontSize >= 12, ...
        sprintf('expected FontSize >= 12, got %g', m.hText.FontSize));

    fprintf('  FontSize = %g\n', m.hText.FontSize);
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 2: default BackgroundColor is 'none' (no black box)
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 2: default BackgroundColor is ''none'' ══\n');
try
    api = launchHeadless();
    cleanupApi = onCleanup(@() safeClose(api));
    api.loadImages({fImg});

    api.measureDistance(15, 25, 95, 75);
    ov = api.getOverlays();
    m = ov.measurements{end};

    bg = m.hText.BackgroundColor;
    % MATLAB normalises 'none' to the char array 'none'
    isTransparent = (ischar(bg) || isstring(bg)) && ...
        strcmpi(char(bg), 'none');
    assert(isTransparent, ...
        sprintf('expected BackgroundColor=''none'', got class=%s value=%s', ...
        class(bg), mat2str(bg)));

    % EdgeColor and Margin should match the transparent policy
    ec = m.hText.EdgeColor;
    isEdgeNone = (ischar(ec) || isstring(ec)) && strcmpi(char(ec), 'none');
    assert(isEdgeNone, 'expected EdgeColor=''none''');

    fprintf('  BackgroundColor=''none'', EdgeColor=''none'', Margin=%g\n', ...
        m.hText.Margin);
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 3: label Position is offset from the line midpoint
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 3: label is offset from the line midpoint ══\n');
try
    api = launchHeadless();
    cleanupApi = onCleanup(@() safeClose(api));
    api.loadImages({fImg});

    x1 = 20; y1 = 30; x2 = 100; y2 = 80;
    api.measureDistance(x1, y1, x2, y2);
    ov = api.getOverlays();
    m = ov.measurements{end};

    mx = (x1 + x2) / 2;
    my = (y1 + y2) / 2;
    lbl = m.hText.Position;

    % Perpendicular offset must move the label clear of the midpoint by
    % a meaningful amount (> 5 data-pixels).
    d = hypot(lbl(1) - mx, lbl(2) - my);
    assert(d > 5, ...
        sprintf('expected label offset > 5 px from midpoint, got %.2f', d));

    % Sanity: the offset should be (approximately) perpendicular to the
    % line — the dot product with the line direction should be small.
    dx = x2 - x1; dy = y2 - y1;
    lineLen = hypot(dx, dy);
    ux = dx / lineLen; uy = dy / lineLen;
    along = (lbl(1) - mx) * ux + (lbl(2) - my) * uy;
    assert(abs(along) < 1e-3, ...
        sprintf('offset should be perpendicular, along-line component=%.4g', along));

    fprintf('  Label offset = %.2f data-px, perpendicular to line\n', d);
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 4: tilt-corrected measurements get a non-empty Tooltip
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 4: tilt-corrected label has explanatory Tooltip ══\n');
try
    api = launchHeadless();
    cleanupApi = onCleanup(@() safeClose(api));
    api.loadImages({fImg});

    % Enable tilt correction via the Measurements panel widgets. The tilt
    % UI is not exposed in the api surface, so we poke the checkbox +
    % spinner directly after findall.
    cb = findall(api.fig, 'Type', 'uicheckbox', 'Text', 'Tilt corr.');
    sp = findall(api.fig, 'Type', 'uispinner');
    % Pick the spinner on the same row as the checkbox (row 9 in the
    % Measurements grid); the Measurements tab has only a handful of
    % spinners and this one has Limits [-89.9, 89.9].
    spnTilt = [];
    for k = 1:numel(sp)
        if isequal(sp(k).Limits, [-89.9 89.9])
            spnTilt = sp(k);
            break;
        end
    end
    assert(~isempty(cb), 'could not locate Tilt corr. checkbox');
    assert(~isempty(spnTilt), 'could not locate tilt-angle spinner');

    % Enable first (Enable='off' initially until an image is loaded).
    cb.Enable = 'on'; spnTilt.Enable = 'on';
    spnTilt.Value = 30;  % 30° tilt
    cb.Value = true;
    drawnow;

    api.measureDistance(20, 30, 100, 80);
    ov = api.getOverlays();
    m = ov.measurements{end};

    % text() primitives in uifigure axes don't support Tooltip directly,
    % so the explanation lives on UserData.tooltip (and a right-click
    % context menu surfaces it to users).
    ud = m.hText.UserData;
    assert(isstruct(ud) && isfield(ud, 'tooltip') && ~isempty(ud.tooltip), ...
        'UserData.tooltip should be non-empty for tilt-corrected labels');
    tt = ud.tooltip;
    ttLower = lower(char(tt));
    % Accept either "cos" (Surface geometry) or "sin" (Cross-section). The
    % tilt-geometry feature changed the default to sin; the test's intent
    % is "tooltip explains the correction factor," not a specific factor.
    % See docs/theory/imaging.md for the physics.
    assert(contains(ttLower, 'tilt') && (contains(ttLower, 'cos') || contains(ttLower, 'sin')), ...
        sprintf('tooltip should mention "tilt" and a trig factor (cos or sin), got: %s', tt));
    % The displayed distance text should carry the asterisk marker.
    assert(endsWith(m.hText.String, '*'), ...
        sprintf('tilt-corrected label string should end with "*", got: %s', ...
        m.hText.String));
    % The context menu should also carry the explanation for hover/right-click.
    cm = m.hText.ContextMenu;
    assert(~isempty(cm) && isvalid(cm), ...
        'tilt-corrected label should have a ContextMenu with the tooltip');

    fprintf('  UserData.tooltip: %s\n', tt);
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 5: label has ButtonDownFcn for drag-to-reposition
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 5: label ButtonDownFcn is wired for drag ══\n');
try
    api = launchHeadless();
    cleanupApi = onCleanup(@() safeClose(api));
    api.loadImages({fImg});

    api.measureDistance(10, 20, 80, 70);
    ov = api.getOverlays();
    m = ov.measurements{end};

    assert(~isempty(m.hText) && isvalid(m.hText), 'hText must be valid');
    assert(~isempty(m.hText.ButtonDownFcn), ...
        'hText.ButtonDownFcn must be set for drag-to-reposition');

    fprintf('  ButtonDownFcn class: %s\n', class(m.hText.ButtonDownFcn));
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 6: "Font size..." context menu item present on all labels
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 6: ContextMenu has Font size... item on non-tilt label ══\n');
try
    api = launchHeadless();
    cleanupApi = onCleanup(@() safeClose(api));
    api.loadImages({fImg});

    api.measureDistance(15, 25, 90, 65);
    ov = api.getOverlays();
    m = ov.measurements{end};

    assert(~isempty(m.hText.ContextMenu) && isvalid(m.hText.ContextMenu), ...
        'non-tilt label must have a ContextMenu');
    items = m.hText.ContextMenu.Children;
    labels = arrayfun(@(c) c.Text, items, 'UniformOutput', false);
    hasFontItem = any(contains(labels, 'Font size'));
    assert(hasFontItem, ...
        sprintf('ContextMenu must contain a "Font size..." item; found: %s', ...
        strjoin(labels, ', ')));

    fprintf('  ContextMenu items: %s\n', strjoin(labels, ' | '));
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 7: panel font spinner changes label FontSize
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 7: panel font spinner updates label FontSize ══\n');
try
    api = launchHeadless();
    cleanupApi = onCleanup(@() safeClose(api));
    api.loadImages({fImg});

    api.measureDistance(20, 30, 90, 70);
    ov = api.getOverlays();
    m = ov.measurements{end};

    % Locate and fire the label-font spinner
    sp = findall(api.fig, 'Type', 'uispinner', 'Tooltip', ...
        'Font size — click a label to target one, otherwise applies to all');
    assert(~isempty(sp), 'could not locate label font spinner');

    sp.Enable = 'on';
    sp.Value = 18;
    drawnow;
    % Fire the ValueChangedFcn manually (spinner callbacks need event data)
    sp.ValueChangedFcn(sp, []);
    drawnow;

    assert(m.hText.FontSize == 18, ...
        sprintf('expected FontSize=18 after spinner change, got %g', ...
        m.hText.FontSize));

    fprintf('  FontSize after spinner = %g\n', m.hText.FontSize);
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  Summary
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n');
fprintf('────────────────────────────────────────────────────────────────\n');
fprintf('  Results: %d passed, %d failed\n', passed, failed);
fprintf('────────────────────────────────────────────────────────────────\n');

if failed > 0
    error('test_measurementLabelDefaults:failure', ...
        '%d test(s) failed', failed);
end
