%TEST_FV_FILEOPEN_REGISTERS  THE regression test for "tools do nothing after open".
%
%   Bug: opening a file via the File>Open menu DISPLAYED the image but left
%   appData.images={} and activeIdx=0. Every tool that guards on
%   `activeIdx < 1` (measurements, rotate, zoom, ...) then silently
%   early-returned — so the image showed but nothing could be done to it
%   (only the scale-bar overlay, draggable without a repaint, still worked).
%
%   Root cause: onOpenFiles did `appData = imageOps('open', appData, ...)`.
%   imageOps loads via the loadImagesFromPaths CLOSURE callback (appendImage
%   appends to the live closure appData), but imageOps then returns its own
%   pre-load value copy. The reassignment overwrote the freshly-loaded
%   closure state back to empty. Fix: onOpenFiles adopts only lastDir from
%   the return, never the whole struct.
%
%   This test drives the REAL File>Open menu path (via the uigetfile shadow),
%   not api.loadImages — that is the path that was broken and the one
%   api-based tests never exercised.
%
%   Run standalone:  run tests/smoke/test_fv_fileopen_registers
%   Run via group :  runAllTests(Group="smoke")

clear; clc;
thisDir = fileparts(mfilename('fullpath'));
rootDir = fileparts(fileparts(thisDir));
if ~contains(path, rootDir), addpath(rootDir); end
% Ensure the uigetfile shadow is reachable
shadowDir = fullfile(rootDir, 'tests', 'shadows');
if ~contains(path, shadowDir), addpath(shadowDir, '-begin'); end

fprintf('\n=== test_fv_fileopen_registers ===\n');
passed = 0; failed = 0;

dm4 = fullfile(rootDir, '+test_datasets', 'Microscopy', 'Overview_0001.dm4');
useFile = dm4;
if ~isfile(dm4)
    useFile = fullfile(tempdir, sprintf('fo_%d.tif', randi(1e9)));
    imwrite(uint16(reshape(linspace(0,60000,128*128),128,128)), useFile);
end
setappdata(0, 'SHADOW_UIGETFILE', useFile);
cleanupAppd = onCleanup(@() setappdata(0, 'SHADOW_UIGETFILE', ''));

api = FermiViewer();
api.fig.Visible = 'off';
cleanupApi = onCleanup(@() safeCloseFO(api));
drawnow;

% ── TEST 1: File>Open registers the image in appData ─────────────────────
fprintf('\n-- TEST 1: File>Open populates appData.images + activeIdx --\n');
try
    openMenu = findall(api.fig, 'Type', 'uimenu', 'Text', 'Open...');
    if isempty(openMenu)
        openMenu = findall(api.fig, 'Type', 'uimenu');
        openMenu = openMenu(arrayfun(@(m) startsWith(char(m.Text),'Open'), openMenu));
    end
    assert(~isempty(openMenu), 'File>Open menu item not found');
    openMenu(1).MenuSelectedFcn(openMenu(1), []);
    drawnow;

    nImg = numel(api.getImages());
    idx  = api.getActiveIdx();
    assert(nImg == 1, 'File>Open must register 1 image, got %d (THE bug if 0)', nImg);
    assert(idx == 1, 'activeIdx must be 1 after open, got %d (THE bug if 0)', idx);
    assert(~isempty(api.getPixels().display), 'display buffer must be populated');
    fprintf('  numImages=%d activeIdx=%d display populated. PASS\n', nImg, idx);
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ── TEST 2: measurement works after File>Open (the user-visible symptom) ─
fprintf('\n-- TEST 2: Distance capture works after File>Open --\n');
try
    n0 = numel(api.getOverlays().measurements);
    bD = findobj(api.fig, 'Text', 'Distance', '-and', 'Type', 'uibutton');
    assert(~isempty(bD), 'Distance button not found');
    bD(1).ButtonPushedFcn(bD(1), []);
    drawnow;
    assert(strcmp(api.getCaptureMode(), 'distance'), ...
        'Distance must enter capture mode (was "%s") — if empty, activeIdx guard still failing', ...
        api.getCaptureMode());
    % realistic physical click: both image + figure handlers fire
    img = findobj(api.fig, 'Type', 'image');
    img = img(arrayfun(@(h) ~strcmp(get(h.Parent,'Tag'),'minimap'), img));
    for c = 1:2
        if ~isempty(img) && ~isempty(img(1).ButtonDownFcn), img(1).ButtonDownFcn(img(1), []); end
        if ~isempty(api.fig.WindowButtonDownFcn), api.fig.WindowButtonDownFcn(api.fig, []); end
        drawnow;
    end
    d = numel(api.getOverlays().measurements) - n0;
    assert(d == 1, 'expected 1 measurement from 2 clicks after File>Open, got %d', d);
    fprintf('  capture armed + 2 clicks -> 1 measurement. PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

fprintf('\n============================================================\n');
fprintf('  File>Open registers: %d passed, %d failed\n', passed, failed);
fprintf('============================================================\n');
if failed > 0
    error('test_fv_fileopen_registers:failed', '%d test(s) failed.', failed);
end


function safeCloseFO(api)
    try
        if isstruct(api) && isfield(api,'close') && isvalid(api.fig), api.close(); end
    catch
    end
end
