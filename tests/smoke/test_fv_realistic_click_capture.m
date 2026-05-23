%TEST_FV_REALISTIC_CLICK_CAPTURE  Models a REAL uifigure click for capture.
%
%   The decisive regression test for the "measurements don't work" saga.
%
%   A real left-click on the displayed image in a MATLAB uifigure fires
%   BOTH the image object's ButtonDownFcn AND the figure's
%   WindowButtonDownFcn. The correct (quantized-matching) wiring is:
%       image.ButtonDownFcn     = onMouseOp('axesDown')   % no-ops in capture
%       fig.WindowButtonDownFcn = onCaptureClick          % does the capture
%   So one physical click => one capture click, and TWO physical clicks
%   complete ONE two-point measurement.
%
%   This test fires BOTH handlers per simulated physical click (unlike
%   api.simulateClick, which calls the dispatcher once and bypasses the
%   real dual-fire). It therefore catches BOTH failure modes:
%     - DEAD capture (neither handler advances) -> 0 measurements
%     - DOUBLE-FIRE (both handlers run onCaptureClick) -> 2+ measurements
%       from a single physical click (the bug introduced + reverted in
%       c8bbcec/f3b6bce)
%
%   Run standalone:  run tests/smoke/test_fv_realistic_click_capture
%   Run via group :  runAllTests(Group="smoke")

clear; clc;
thisDir = fileparts(mfilename('fullpath'));
rootDir = fileparts(fileparts(thisDir));
if ~contains(path, rootDir), addpath(rootDir); end

fprintf('\n=== test_fv_realistic_click_capture ===\n');
passed = 0; failed = 0;

tmpDir = tempdir;
tp = fullfile(tmpDir, sprintf('realclick_%d.tif', randi(1e9)));
imwrite(uint16(reshape(linspace(0,60000,256*256),256,256)), tp);
cleanupTiff = onCleanup(@() delete(tp));

api = FermiViewer();
api.fig.Visible = 'off';
cleanupApi = onCleanup(@() safeCloseR(api));
drawnow;
api.loadImages({tp});
drawnow;

img = localMainImage(api.fig);

% ── TEST 1: Distance — 2 physical clicks must yield exactly 1 measurement ─
fprintf('\n-- TEST 1: Distance, 2 physical clicks -> 1 measurement --\n');
try
    n0 = numel(api.getOverlays().measurements);
    fireBtnR(api.fig, 'Distance');
    assert(strcmp(api.getCaptureMode(), 'distance'), 'should enter distance capture');
    physicalClickR(api.fig, img);
    assert(strcmp(api.getCaptureMode(), 'distance'), ...
        'after 1 physical click should still be capturing (got "%s") — DOUBLE-FIRE if empty', ...
        api.getCaptureMode());
    physicalClickR(api.fig, img);
    nFinal = numel(api.getOverlays().measurements);
    d = nFinal - n0;
    assert(d == 1, '2 physical clicks must create exactly 1 measurement, got %d', d);
    assert(isempty(api.getCaptureMode()), 'capture should reset after 2 clicks');
    fprintf('  2 clicks -> %d measurement, mode reset. PASS\n', d);
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
    try; api.cancelCapture(); catch; end
end

% ── TEST 2: Line Profile, same invariant ─────────────────────────────────
fprintf('\n-- TEST 2: Line Profile, 2 physical clicks -> 1 measurement --\n');
try
    api.cancelCapture();
    n0 = numel(api.getOverlays().measurements);
    fireBtnR(api.fig, 'Line Profile');
    physicalClickR(api.fig, img);
    physicalClickR(api.fig, img);
    d = numel(api.getOverlays().measurements) - n0;
    assert(d == 1, 'profile: 2 clicks must create exactly 1 measurement, got %d', d);
    fprintf('  2 clicks -> %d measurement. PASS\n', d);
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
    try; api.cancelCapture(); catch; end
end

fprintf('\n============================================================\n');
fprintf('  Realistic-click capture: %d passed, %d failed\n', passed, failed);
fprintf('============================================================\n');
if failed > 0
    error('test_fv_realistic_click_capture:failed', '%d test(s) failed.', failed);
end


function physicalClickR(fig, img)
%PHYSICALCLICKR  Fire BOTH handlers a real uifigure click would fire.
    if ~isempty(img) && ~isempty(img.ButtonDownFcn), img.ButtonDownFcn(img, []); end
    if ~isempty(fig.WindowButtonDownFcn),            fig.WindowButtonDownFcn(fig, []); end
    drawnow;
end

function im = localMainImage(fig)
    im = findobj(fig, 'Type', 'image');
    keep = arrayfun(@(h) ~strcmp(get(h.Parent,'Tag'),'minimap'), im);
    im = im(keep);
    if ~isempty(im), im = im(1); end
end

function fireBtnR(fig, label)
    b = findobj(fig, 'Text', label, '-and', 'Type', 'uibutton');
    assert(~isempty(b), 'button "%s" not found', label);
    b(1).ButtonPushedFcn(b(1), []); drawnow;
end

function safeCloseR(api)
    try
        if isstruct(api) && isfield(api,'close') && isvalid(api.fig), api.close(); end
    catch
    end
end
