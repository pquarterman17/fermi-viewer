%TEST_HISTOGRAM_OVERLAY  Smoke test for emViewer.drawHistogramOverlay.
%   Verifies the helper draws the expected overlay primitives (lo/hi handles,
%   gamma midpoint, transfer-function ramp, clipping indicators) on a uiaxes
%   without erroring. Tests the contract used by FermiViewer's
%   refreshHistogramMarkers() callback.
%
%   Covers W2 #5 (transfer ramp), W2 #7 (clipping indicators), and the
%   long-standing lo/hi/gamma marker behaviour.
%
%   Run:  runAllTests(Group="emgui")
%   Or:   run tests/imaging/test_histogram_overlay

clear; clc;

thisDir = fileparts(mfilename('fullpath'));
rootDir = fileparts(fileparts(thisDir));
if ~contains(path, rootDir); addpath(rootDir); end

fprintf('\n=== test_histogram_overlay ===\n');
passed = 0; failed = 0;

fig = uifigure('Visible','off','Position',[100 100 400 200]);
cleanup = onCleanup(@() delete(fig));
ax = uiaxes(fig);
ax.XLim = [0 100];
ax.YLim = [0 50];

% ── Test 1: bare overlay (linear, gamma=1, no invert) draws lo/hi/ramp ──
try
    rawPx = randn(1000, 1) * 20 + 50;        % range roughly [-10, 110]
    emViewer.drawHistogramOverlay(ax, 30, 70, 1.0, 'linear', false, rawPx);
    n_lo_hi = numel(findobj(ax, 'Tag', 'histMarker', 'Type', 'line'));
    assert(n_lo_hi >= 2, 'Expected >=2 line markers (lo/hi); got %d', n_lo_hi);
    n_patch = numel(findobj(ax, 'Tag', 'histMarker', 'Type', 'patch'));
    assert(n_patch >= 1, 'Expected >=1 patch (window tint); got %d', n_patch);
    fprintf('  [PASS] linear/gamma=1 — markers + ramp drawn\n');
    passed = passed + 1;
catch ME
    fprintf(2, '  [FAIL] linear/gamma=1: %s\n', ME.message);
    failed = failed + 1;
end

% ── Test 2: gamma != 1 adds the dashed midpoint line ────────────────────
try
    delete(findobj(ax, 'Tag', 'histMarker'));
    rawPx = rand(500, 1) * 100;
    emViewer.drawHistogramOverlay(ax, 20, 80, 2.5, 'linear', false, rawPx);
    dashed = findobj(ax, 'Tag', 'histMarker', 'Type', 'line', 'LineStyle', '--');
    assert(~isempty(dashed), 'Gamma midpoint dashed line not drawn');
    fprintf('  [PASS] gamma=2.5 — midpoint guide drawn\n');
    passed = passed + 1;
catch ME
    fprintf(2, '  [FAIL] gamma midpoint: %s\n', ME.message);
    failed = failed + 1;
end

% ── Test 3: clipping indicators appear when fractions exceed 1% ─────────
try
    delete(findobj(ax, 'Tag', 'histMarker'));
    % 10% pixels below lo, 20% above hi.
    rawPx = [zeros(100,1); linspace(15, 85, 700).'; 95*ones(200,1)];
    ax.XLim = [0 100];
    emViewer.drawHistogramOverlay(ax, 10, 90, 1.0, 'linear', false, rawPx);
    nPatch = numel(findobj(ax, 'Tag', 'histMarker', 'Type', 'patch'));
    % Window tint (1) + 2 clipping strips = 3
    assert(nPatch >= 3, 'Expected >=3 patches (tint + 2 clip strips); got %d', nPatch);
    fprintf('  [PASS] clipping indicators — %d patches drawn\n', nPatch);
    passed = passed + 1;
catch ME
    fprintf(2, '  [FAIL] clipping indicators: %s\n', ME.message);
    failed = failed + 1;
end

% ── Test 4: showRamp=false, showClipping=false suppresses overlays ─────
try
    delete(findobj(ax, 'Tag', 'histMarker'));
    emViewer.drawHistogramOverlay(ax, 30, 70, 1.0, 'linear', false, rand(500,1)*100, ...
        'showRamp', false, 'showClipping', false);
    % Should still have the 2 handle lines + 1 window patch = 3 objects.
    nObj = numel(findobj(ax, 'Tag', 'histMarker'));
    assert(nObj == 3, 'Expected exactly 3 objects with overlays disabled; got %d', nObj);
    fprintf('  [PASS] overlay-suppression flags honoured\n');
    passed = passed + 1;
catch ME
    fprintf(2, '  [FAIL] overlay flags: %s\n', ME.message);
    failed = failed + 1;
end

% ── Test 5: log/sqrt/power transforms don't error and produce finite ramp ─
try
    for tf = {'log','sqrt','power','linear'}
        delete(findobj(ax, 'Tag', 'histMarker'));
        emViewer.drawHistogramOverlay(ax, 5, 95, 1.5, tf{1}, false, rand(500,1)*100);
        rampLine = findobj(ax, 'Tag', 'histMarker', 'Type', 'line', 'LineStyle', '-');
        rampLine = rampLine(arrayfun(@(h) numel(h.XData) > 4, rampLine));   % the >2-pt one
        assert(~isempty(rampLine), 'Ramp line missing for transform=%s', tf{1});
        ydata = rampLine(1).YData;
        assert(all(isfinite(ydata)), 'Non-finite ramp Y for transform=%s', tf{1});
    end
    fprintf('  [PASS] all transforms produce finite ramps\n');
    passed = passed + 1;
catch ME
    fprintf(2, '  [FAIL] transform ramps: %s\n', ME.message);
    failed = failed + 1;
end

% ── Test 6: invert=true flips ramp endpoints ────────────────────────────
try
    delete(findobj(ax, 'Tag', 'histMarker'));
    emViewer.drawHistogramOverlay(ax, 20, 80, 1.0, 'linear', true, rand(500,1)*100);
    rampLine = findobj(ax, 'Tag', 'histMarker', 'Type', 'line', 'LineStyle', '-');
    rampLine = rampLine(arrayfun(@(h) numel(h.XData) > 4, rampLine));
    assert(~isempty(rampLine), 'Ramp line missing under invert');
    ydata = rampLine(1).YData;
    % Inverted ramp: at x=lo it's at y=ax.YLim(2), at x=hi it's at 0.
    assert(ydata(1) > ydata(end), ...
        'Inverted ramp should slope down (start=%.3g, end=%.3g)', ydata(1), ydata(end));
    fprintf('  [PASS] invert flips ramp slope\n');
    passed = passed + 1;
catch ME
    fprintf(2, '  [FAIL] invert: %s\n', ME.message);
    failed = failed + 1;
end

fprintf('\n=== Results: %d passed, %d failed ===\n', passed, failed);
if failed > 0
    error('test_histogram_overlay: %d failure(s)', failed);
end
