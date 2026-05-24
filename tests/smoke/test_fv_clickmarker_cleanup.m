%TEST_FV_CLICKMARKER_CLEANUP  Regression: no leftover click marker after capture.
%
%   Bug: after completing a two-click measurement (Distance/Profile/etc.),
%   the temporary click marker (blue dot) from the SECOND click was left
%   orphaned on the axes. doCaptureClick creates the 2nd marker on its LOCAL
%   appData; the execute* callback then runs on the CLOSURE appData (which
%   doesn't have the 2nd marker yet) and can only clean up the 1st — so the
%   2nd marker's graphics persisted, untracked, with no handle to delete it.
%   Fix: doCaptureClick deletes all click markers in its completion branch
%   (where the local copy holds both) before executing.
%
%   NOTE: detection uses findall (not findobj) — click markers have
%   HandleVisibility='off' which findobj skips.
%
%   Run standalone:  run tests/smoke/test_fv_clickmarker_cleanup
%   Run via group :  runAllTests(Group="smoke")

clear; clc;
thisDir = fileparts(mfilename('fullpath'));
rootDir = fileparts(fileparts(thisDir));
if ~contains(path, rootDir), addpath(rootDir); end

fprintf('\n=== test_fv_clickmarker_cleanup ===\n');
passed = 0; failed = 0;

tmpDir = tempdir;
tp = fullfile(tmpDir, sprintf('clkmark_%d.tif', randi(1e9)));
imwrite(uint16(reshape(linspace(0,60000,256*256),256,256)), tp);
cleanupTiff = onCleanup(@() delete(tp));

api = FermiViewer(); api.fig.Visible = 'off';
cleanupApi = onCleanup(@() safeCloseCM(api));
drawnow;
api.loadImages({tp}); drawnow;

ax = findall(api.fig, 'Type', 'axes');
ax = ax(arrayfun(@(a) ~strcmp(a.Tag,'minimap') && ~isempty(findall(a,'Type','image')), ax));
ax = ax(1);
img = findall(api.fig, 'Type', 'image');
img = img(arrayfun(@(h) ~strcmp(get(h.Parent,'Tag'),'minimap'), img)); img = img(1);

modes = {'Distance', 'Line Profile'};
for mi = 1:numel(modes)
    label = modes{mi};
    fprintf('\n-- %s: no leftover click marker --\n', label);
    try
        b = findall(api.fig, 'Type', 'uibutton', 'Text', label);
        assert(~isempty(b), 'button "%s" not found', label);
        b(1).ButtonPushedFcn(b(1), []); drawnow;
        for c = 1:2
            if ~isempty(img.ButtonDownFcn), img.ButtonDownFcn(img, []); end
            if ~isempty(api.fig.WindowButtonDownFcn), api.fig.WindowButtonDownFcn(api.fig, []); end
            drawnow;
        end
        ov = api.getOverlays();
        tracked = gobjects(0);
        for k = 1:numel(ov.measurements)
            m = ov.measurements{k};
            for fn = {'hLine','hP1','hP2'}
                if isfield(m,fn{1}) && ~isempty(m.(fn{1})) && isvalid(m.(fn{1}))
                    tracked(end+1) = m.(fn{1}); %#ok<AGROW>
                end
            end
        end
        markers = findall(ax, 'Type', 'line', 'LineStyle', 'none');
        orphan = sum(arrayfun(@(h) ~any(h == tracked), markers));
        assert(orphan == 0, '%d orphaned click marker(s) left on axes', orphan);
        fprintf('  no orphaned markers (tracked=%d). PASS\n', numel(tracked));
        passed = passed + 1;
        api.clearOverlays(); drawnow;   % reset for next mode
    catch ME
        fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
        try; api.cancelCapture(); api.clearOverlays(); catch; end
    end
end

fprintf('\n============================================================\n');
fprintf('  Click-marker cleanup: %d passed, %d failed\n', passed, failed);
fprintf('============================================================\n');
if failed > 0
    error('test_fv_clickmarker_cleanup:failed', '%d test(s) failed.', failed);
end

function safeCloseCM(api)
    try
        if isstruct(api) && isfield(api,'close') && isvalid(api.fig), api.close(); end
    catch
    end
end
