%TEST_FV_REAL_CLICK_CAPTURE  Regression: real image clicks must drive capture.
%
%   Catches the bug where two-click capture (Distance/Profile/Angle/ROI)
%   and rect capture (zoom/crop) were silently dead in the live GUI even
%   though every dispatcher-level test passed.
%
%   Root cause: in a MATLAB uifigure, a left-click on the displayed image
%   fires the IMAGE object's ButtonDownFcn, NOT fig.WindowButtonDownFcn.
%   The capture system only installed its handler on fig.WindowButtonDownFcn,
%   so real clicks never reached it. Fix: capture-start also points the
%   image+axes ButtonDownFcn at the capture handler (see
%   +fermiViewer/+interaction/setClickHandler.m).
%
%   WHY EXISTING TESTS MISSED IT: test_fv_interactive_flows uses
%   api.simulateClick(x,y), a test hook that calls the dispatcher directly,
%   bypassing the image-vs-figure event routing entirely. THIS test instead
%   invokes the IMAGE object's actual ButtonDownFcn — the exact callback a
%   real mouse click triggers — so it exercises the routing that broke.
%
%   Run standalone:  run tests/smoke/test_fv_real_click_capture
%   Run via group :  runAllTests(Group="smoke")

clear; clc;

thisDir = fileparts(mfilename('fullpath'));
rootDir = fileparts(fileparts(thisDir));
if ~contains(path, rootDir), addpath(rootDir); end

fprintf('\n=== test_fv_real_click_capture ===\n');
passed = 0; failed = 0;

tmpDir = tempdir;
tiffPath = fullfile(tmpDir, sprintf('realclick_%d.tif', randi(1e9)));
imwrite(uint16(reshape(linspace(0, 60000, 128*128), 128, 128)), tiffPath);
cleanupTiff = onCleanup(@() delete(tiffPath));

api = FermiViewer();
api.fig.Visible = 'off';
cleanupApi = onCleanup(@() safeCloseRC(api));
drawnow;
api.loadImages({tiffPath});
drawnow;

% Helper to grab the live main-image object
getImg = @() localGetMainImage(api.fig);

% ── TEST 1: Distance via real image-click path ──────────────────────────
fprintf('\n-- TEST 1: Distance (2 image clicks) --\n');
try
    nStart = numel(api.getOverlays().measurements);
    fireButtonRC(api.fig, 'Distance');
    assert(strcmp(api.getCaptureMode(), 'distance'), 'should be in distance capture');
    im = getImg();
    assert(~isempty(im) && ~isempty(im.ButtonDownFcn), ...
        'image ButtonDownFcn must be wired during capture (else real clicks are dead)');
    im.ButtonDownFcn(im, []); drawnow;   % click 1
    im.ButtonDownFcn(im, []); drawnow;   % click 2
    nEnd = numel(api.getOverlays().measurements);
    assert(nEnd > nStart, ...
        sprintf('real image clicks did not create a measurement (%d -> %d)', nStart, nEnd));
    assert(isempty(api.getCaptureMode()), 'capture mode should reset after 2 clicks');
    fprintf('  measurement created via image-click path (%d -> %d)\n', nStart, nEnd);
    fprintf('  PASS\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
    try; api.cancelCapture(); catch; end
end

% ── TEST 2: Line Profile via real image-click path ──────────────────────
fprintf('\n-- TEST 2: Line Profile (2 image clicks) --\n');
try
    api.cancelCapture();
    nStart = numel(api.getOverlays().measurements);
    fireButtonRC(api.fig, 'Line Profile');
    assert(strcmp(api.getCaptureMode(), 'profile'), 'should be in profile capture');
    im = getImg();
    im.ButtonDownFcn(im, []); drawnow;
    im.ButtonDownFcn(im, []); drawnow;
    nEnd = numel(api.getOverlays().measurements);
    assert(nEnd > nStart, 'real image clicks did not create a profile measurement');
    fprintf('  profile created via image-click path (%d -> %d)\n', nStart, nEnd);
    fprintf('  PASS\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
    try; api.cancelCapture(); catch; end
end

% ── TEST 3: handler restored to non-capture after finish ────────────────
fprintf('\n-- TEST 3: image handler restored after capture ends --\n');
try
    api.cancelCapture();
    drawnow;
    im = getImg();
    s = func2str(im.ButtonDownFcn);
    assert(contains(s, 'axesDown'), ...
        sprintf('after capture, image handler should be axesDown, got: %s', s));
    fprintf('  restored to: %s\n', s);
    fprintf('  PASS\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

fprintf('\n============================================================\n');
fprintf('  Real-click capture: %d passed, %d failed\n', passed, failed);
fprintf('============================================================\n');
if failed > 0
    error('test_fv_real_click_capture:failed', '%d test(s) failed.', failed);
end


function im = localGetMainImage(fig)
    im = findobj(fig, 'Type', 'image');
    keep = arrayfun(@(h) ~strcmp(get(h.Parent,'Tag'),'minimap'), im);
    im = im(keep);
    if ~isempty(im), im = im(1); end
end

function fireButtonRC(fig, label)
    b = findobj(fig, 'Text', label, '-and', 'Type', 'uibutton');
    assert(~isempty(b), 'button "%s" not found', label);
    b(1).ButtonPushedFcn(b(1), []);
    drawnow;
end

function safeCloseRC(api)
    try
        if isstruct(api) && isfield(api,'close') && isvalid(api.fig), api.close(); end
    catch
    end
end
