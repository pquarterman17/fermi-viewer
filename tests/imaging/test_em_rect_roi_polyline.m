%TEST_EM_RECT_ROI_POLYLINE  Rect ROI replaces Polygon ROI; polyline is now
%   a proper measurement record (selectable + deletable + marquee-able).
%
%   Changes tested (all landed 2026-04-22):
%     1. api.rectROI(xMin, xMax, yMin, yMax) registers a 'rectROI' meas
%        with stats struct; the drawn rectangle persists on the axes.
%     2. api.measurePolyline(pts) registers a 'polyline' meas with hLines,
%        hMarkers, hText, vertices — findable + removable.
%     3. Clear All removes both types.
%     4. api.removeSelected (with the rect ROI selected) removes just
%        that one entry.
%
%   Run:  runAllTests(Group="emgui")

clear; clc;

thisDir = fileparts(mfilename('fullpath'));
rootDir = fileparts(fileparts(thisDir));
if ~contains(path, rootDir); addpath(rootDir); end

srcDir = fullfile(rootDir, '+test_datasets', 'Microscopy');
dm3 = fullfile(srcDir, 'EDW087-1.dm3');
assert(isfile(dm3), 'Test DM3 not found: %s', dm3);

fprintf('\n=== test_em_rect_roi_polyline ===\n');
passed = 0; failed = 0;

api = FermiViewer();
api.fig.Visible = 'off';
cleanup = onCleanup(@() api.close());

api.loadImages({dm3});

% ── 1. rectROI registers a measurement record ───────────────────────────
api.rectROI(50, 150, 50, 150);
ov = api.getOverlays();
if numel(ov.measurements) == 1 && strcmp(ov.measurements{1}.type, 'rectROI')
    m = ov.measurements{1};
    if m.stats.area == 101*101 && isvalid(m.hRect)
        fprintf('  PASS: rectROI registered as measurement, area=%d\n', m.stats.area);
        passed = passed + 1;
    else
        fprintf('  FAIL: rectROI stats/handle wrong\n');
        failed = failed + 1;
    end
else
    fprintf('  FAIL: expected 1 rectROI measurement, got %d\n', numel(ov.measurements));
    failed = failed + 1;
end

% ── 2. measurePolyline registers a polyline measurement ────────────────
api.measurePolyline([200 200; 300 250; 400 200]);
ov = api.getOverlays();
if numel(ov.measurements) == 2 && strcmp(ov.measurements{2}.type, 'polyline')
    p = ov.measurements{2};
    hasLines   = isfield(p, 'hLines')   && numel(p.hLines)   == 2;
    hasMarkers = isfield(p, 'hMarkers') && numel(p.hMarkers) == 3;
    hasText    = isfield(p, 'hText')    && isvalid(p.hText);
    if hasLines && hasMarkers && hasText
        fprintf('  PASS: polyline registered with 2 lines + 3 markers + label\n');
        passed = passed + 1;
    else
        fprintf('  FAIL: polyline graphics incomplete (lines=%d markers=%d text=%d)\n', ...
            numel(p.hLines), numel(p.hMarkers), hasText);
        failed = failed + 1;
    end
else
    fprintf('  FAIL: expected polyline at index 2, got type=%s\n', ...
        ov.measurements{end}.type);
    failed = failed + 1;
end

% ── 3. marqueeSelect picks up both types ───────────────────────────────
api.setZoomMode(false);
api.marqueeSelect(0, 1e4, 0, 1e4);
mIdx = api.getSelectedMeasIndices();
if numel(mIdx) == 2
    fprintf('  PASS: wide marquee picked rectROI + polyline (2 items)\n');
    passed = passed + 1;
else
    fprintf('  FAIL: marquee picked %d items (expected 2)\n', numel(mIdx));
    failed = failed + 1;
end

% ── 4. removeSelected deletes both ─────────────────────────────────────
api.removeSelected();
ov = api.getOverlays();
if isempty(ov.measurements)
    fprintf('  PASS: removeSelected cleared rectROI + polyline\n');
    passed = passed + 1;
else
    fprintf('  FAIL: %d measurements remain after removeSelected\n', ...
        numel(ov.measurements));
    failed = failed + 1;
end

% ── 5. Second round: individual rectROI delete via primary-selection ──
api.rectROI(10, 60, 10, 60);
api.rectROI(100, 160, 100, 160);
ov = api.getOverlays();
assert(numel(ov.measurements) == 2, 'setup: need 2 ROIs');
% Select only the first by marquee around its bounds
api.marqueeSelect(0, 70, 0, 70);
mIdx = api.getSelectedMeasIndices();
if numel(mIdx) == 1 && mIdx == 1
    api.removeSelected();
    ov = api.getOverlays();
    if numel(ov.measurements) == 1 && ov.measurements{1}.stats.area == 61*61
        fprintf('  PASS: deleted ROI 1 only; ROI 2 remains\n');
        passed = passed + 1;
    else
        fprintf('  FAIL: after deleting ROI 1, wrong state remains\n');
        failed = failed + 1;
    end
else
    fprintf('  FAIL: narrow marquee picked %s (expected [1])\n', num2str(mIdx));
    failed = failed + 1;
end

% ── 6. Clear All removes the remaining ROI ─────────────────────────────
api.clearOverlays();
ov = api.getOverlays();
if isempty(ov.measurements)
    fprintf('  PASS: clearOverlays cleared remaining ROI\n');
    passed = passed + 1;
else
    fprintf('  FAIL: %d measurements remain after clearOverlays\n', ...
        numel(ov.measurements));
    failed = failed + 1;
end

fprintf('\n%d passed, %d failed\n', passed, failed);
if failed > 0
    error('test_em_rect_roi_polyline: %d failures', failed);
end
