%TEST_EM_CLEAR_OVERLAYS_DIFF_RINGS  Regression test: api.clearOverlays() must
%   remove diffraction rings and diffraction spots drawn onto the image axes.
%
%   Before the 2026-04-22 fix, rings drawn by the Diff Rings button were
%   untagged and clearAllOverlays only iterated appData.overlays.*, so the
%   rings survived Clear All. This test paints tagged diff_ring / diff_spot
%   objects directly onto the axes and asserts they disappear after the
%   public clearOverlays() call.
%
%   Run:  runAllTests(Group="emgui")
%   Or:   run tests/imaging/test_em_clear_overlays_diff_rings

clear; clc;

thisDir = fileparts(mfilename('fullpath'));
rootDir = fileparts(fileparts(thisDir));
if ~contains(path, rootDir); addpath(rootDir); end

srcDir = fullfile(rootDir, '+test_datasets', 'Microscopy');
dm3 = fullfile(srcDir, 'EDW087-1.dm3');
assert(isfile(dm3), 'Test DM3 not found: %s', dm3);

fprintf('\n=== test_em_clear_overlays_diff_rings ===\n');
passed = 0; failed = 0;

api = FermiViewer();
api.fig.Visible = 'off';
cleanup = onCleanup(@() api.close());

api.loadImages({dm3});

% The main image axes is the one whose child is an image object.
% Use findall, not findobj, because many axes objects are created with
% HandleVisibility='off' in the FermiViewer figure.
allAxes = findall(api.fig, 'Type', 'axes');
ax = [];
for k = 1:numel(allAxes)
    if ~isempty(findall(allAxes(k), 'Type', 'image', '-depth', 1))
        ax = allAxes(k);
        break;
    end
end
assert(~isempty(ax) && isvalid(ax), 'Could not find main image axes');

% Paint a synthetic ring + spot with the tags the production code uses.
hold(ax, 'on');
th = linspace(0, 2*pi, 60);
plot(ax, 100 + 20*cos(th), 100 + 20*sin(th), 'r-', ...
    'Tag', 'diff_ring', 'HandleVisibility', 'off', 'HitTest', 'off');
text(ax, 115, 90, '2.34 A', 'Tag', 'diff_ring', ...
    'HandleVisibility', 'off', 'HitTest', 'off');
plot(ax, 120, 80, 'ro', 'MarkerSize', 10, 'Tag', 'diff_spot', ...
    'HandleVisibility', 'off');
hold(ax, 'off');

ringsBefore = numel(findall(api.fig, 'Tag', 'diff_ring'));
spotsBefore = numel(findall(api.fig, 'Tag', 'diff_spot'));
if ringsBefore >= 2 && spotsBefore >= 1
    fprintf('  PASS: painted %d diff_ring and %d diff_spot handles\n', ...
        ringsBefore, spotsBefore);
    passed = passed + 1;
else
    fprintf('  FAIL: synthetic overlays not painted (%d rings, %d spots)\n', ...
        ringsBefore, spotsBefore);
    failed = failed + 1;
end

% Call Clear Overlays and verify every tagged handle is gone.
api.clearOverlays();

ringsAfter = numel(findall(api.fig, 'Tag', 'diff_ring'));
spotsAfter = numel(findall(api.fig, 'Tag', 'diff_spot'));
if ringsAfter == 0 && spotsAfter == 0
    fprintf('  PASS: diff_ring + diff_spot removed by clearOverlays\n');
    passed = passed + 1;
else
    fprintf('  FAIL: diff_ring=%d diff_spot=%d after clearOverlays\n', ...
        ringsAfter, spotsAfter);
    failed = failed + 1;
end

fprintf('\n%d passed, %d failed\n', passed, failed);
if failed > 0
    error('test_em_clear_overlays_diff_rings: %d failures', failed);
end
