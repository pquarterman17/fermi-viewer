%TEST_FV_IMAGE_CLICK_HANDLER  Regression: image must have non-empty ButtonDownFcn.
%
%   Catches the silent-click-swallow bug class fixed in commit 3da1886.
%   Background: a MATLAB uifigure image with HitTest='on' +
%   PickableParts='visible' + empty ButtonDownFcn silently consumes
%   left-clicks without firing fig.WindowButtonDownFcn. Every two-click
%   capture mode (Distance, Line Profile, ROIs, annotations) breaks --
%   the button enters capture mode (cursor changes to crosshair) but
%   clicking on the image registers nothing.
%
%   Existing tests (test_fv_capture_modes, test_fv_interactive_flows) miss
%   this because they invoke the dispatcher directly via api.simulateClick
%   or by firing fig.WindowButtonDownFcn from the script, bypassing the
%   real mouse-event chain that depends on image.ButtonDownFcn.
%
%   See memory: feedback_simulate_click_blind_spot,
%               project_fermiviewer_image_click_contract.
%
%   Run standalone:  run tests/smoke/test_fv_image_click_handler
%   Run via group :  runAllTests(Group="smoke")

clear; clc;

thisDir = fileparts(mfilename('fullpath'));
rootDir = fileparts(fileparts(thisDir));
if ~contains(path, rootDir)
    addpath(rootDir);
end

fprintf('\n=== test_fv_image_click_handler ===\n');

passed = 0;
failed = 0;

% ── TEST 1: synthetic TIFF -- image ButtonDownFcn must be set after load ─
fprintf('\n-- TEST 1: synthetic TIFF --\n');
try
    tmpDir = tempdir;
    tiffPath = fullfile(tmpDir, sprintf('clickhandler_%d.tif', randi(1e9)));
    img = uint16(reshape(linspace(0, 60000, 64*48), 64, 48));
    imwrite(img, tiffPath);
    cleanupTiff = onCleanup(@() delete(tiffPath));

    api = FermiViewer();
    api.fig.Visible = 'off';
    cleanupApi = onCleanup(@() safeClose(api));
    drawnow;
    api.loadImages({tiffPath});
    drawnow;

    im = findobj(api.fig, 'Type', 'image');
    im = filterMainImage(im);
    assert(~isempty(im), 'No main image object found after load');

    assert(~isempty(im(1).ButtonDownFcn), ...
        ['IMAGE.ButtonDownFcn IS EMPTY -- left-clicks will be silently ' ...
         'swallowed and every two-click capture mode is broken. ' ...
         'See feedback_simulate_click_blind_spot + ' ...
         'project_fermiviewer_image_click_contract memory.']);
    assert(strcmp(char(im(1).HitTest), 'on'), 'image HitTest must be on');

    fprintf('  ButtonDownFcn non-empty: yes\n');
    fprintf('  HitTest=%s  PickableParts=%s\n', ...
        char(im(1).HitTest), char(im(1).PickableParts));
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ── TEST 2: real DM3 file (when available) ───────────────────────────────
fprintf('\n-- TEST 2: real DM3 --\n');
try
    dm3 = fullfile(rootDir, '+test_datasets', 'Microscopy', 'EDW087-1.dm3');
    if ~isfile(dm3)
        fprintf('  SKIP (no DM3 in +test_datasets/Microscopy/)\n');
    else
        api = FermiViewer();
        api.fig.Visible = 'off';
        cleanupApi = onCleanup(@() safeClose(api));
        drawnow;
        api.loadImages({dm3});
        drawnow;

        im = filterMainImage(findobj(api.fig, 'Type', 'image'));
        assert(~isempty(im), 'No main image object found after DM3 load');
        assert(~isempty(im(1).ButtonDownFcn), ...
            'IMAGE.ButtonDownFcn empty on DM3 load -- click pipeline broken');
        fprintf('  ButtonDownFcn non-empty: yes\n');
        fprintf('  PASS\n');
        passed = passed + 1;
    end
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ── TEST 3: ButtonDownFcn survives a second loadImages call (re-display) ─
fprintf('\n-- TEST 3: ButtonDownFcn survives re-display --\n');
try
    tmpDir = tempdir;
    p1 = fullfile(tmpDir, sprintf('clickhandler_%d_a.tif', randi(1e9)));
    p2 = fullfile(tmpDir, sprintf('clickhandler_%d_b.tif', randi(1e9)));
    imwrite(uint16(reshape(linspace(0, 60000, 64*48), 64, 48)), p1);
    imwrite(uint16(randi([0 60000], 64, 48, 'uint16')), p2);
    cleanupFiles = onCleanup(@() cellfun(@delete, {p1, p2}));

    api = FermiViewer();
    api.fig.Visible = 'off';
    cleanupApi = onCleanup(@() safeClose(api));
    drawnow;
    api.loadImages({p1});
    drawnow;
    api.loadImages({p2});  % triggers another display
    drawnow;

    im = filterMainImage(findobj(api.fig, 'Type', 'image'));
    assert(~isempty(im), 'No image found after second load');
    assert(~isempty(im(1).ButtonDownFcn), ...
        'IMAGE.ButtonDownFcn empty after second load -- re-display path broken');
    fprintf('  ButtonDownFcn survives re-display: yes\n');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

fprintf('\n============================================================\n');
fprintf('  Image-click handler: %d passed, %d failed\n', passed, failed);
fprintf('============================================================\n');

if failed > 0
    error('test_fv_image_click_handler:failed', '%d test(s) failed.', failed);
end


% ── Local helpers ────────────────────────────────────────────────────────
function im = filterMainImage(im)
%FILTERMAINIMAGE  Drop minimap and overview-thumbnail images, keep only the
%   primary display image.
    if isempty(im), return; end
    keep = false(size(im));
    for k = 1:numel(im)
        p = im(k).Parent;
        if isgraphics(p) && (isempty(p.Tag) || ...
                ~any(strcmp(char(p.Tag), {'minimap', 'thumbnail'})))
            keep(k) = true;
        end
    end
    im = im(keep);
end

function safeClose(api)
    try
        if isstruct(api) && isfield(api, 'close') && isvalid(api.fig)
            api.close();
        end
    catch
    end
end
