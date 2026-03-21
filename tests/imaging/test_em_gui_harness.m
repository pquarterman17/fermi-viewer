%TEST_EM_GUI_HARNESS  Automated test harness for emViewerGUI programmatic API.
%
%   Tests the EM Viewer GUI through its programmatic API interface:
%   - Launch and close
%   - Loading synthetic TIFF and RAW images
%   - Image struct field validation
%   - Contrast control (set and auto)
%   - Filter application (Gaussian, Median)
%   - FFT computation
%   - Line profile extraction
%   - Image export
%   - Multi-image management
%
%   Run standalone:  cd tests; run test_em_gui_harness
%   Run from root:   run tests/test_em_gui_harness
%
%   Each test prints PASS / FAIL. Cleanup is automatic via onCleanup.

clear; clc;

% Ensure toolbox is on the path
thisDir = fileparts(mfilename('fullpath'));
rootDir = fileparts(fileparts(thisDir));
if ~contains(path, rootDir)
    addpath(rootDir);
end

ROOT = rootDir;

% Setup temp directory for synthetic test images
tmpDir = fullfile(tempdir, 'em_gui_test_' + string(datetime('now','Format','yyyyMMdd_HHmmss')));
mkdir(tmpDir);
cleanupTmp = onCleanup(@() rmdir(tmpDir, 's'));

passed = 0;
failed = 0;

% ── Pre-create synthetic test files ──────────────────────────────────────
% Synthetic 64x48 uint16 TIFF (height=64, width=48)
tiffPath1 = fullfile(tmpDir, 'synth_01.tif');
synthPixels1 = uint16(reshape(linspace(0, 65535, 64*48), 64, 48));
imwrite(synthPixels1, tiffPath1);

% Second synthetic TIFF for multi-image tests
tiffPath2 = fullfile(tmpDir, 'synth_02.tif');
synthPixels2 = uint16(randi([0 65535], 64, 48, 'uint16'));
imwrite(synthPixels2, tiffPath2);

% Synthetic 32x24 uint16 RAW file (row-major, height=32, width=24)
rawPath = fullfile(tmpDir, 'synth_01.raw');
rawPixels = uint16(reshape(0:32*24-1, 32, 24));
fid = fopen(rawPath, 'wb');
fwrite(fid, rawPixels(:), 'uint16');
fclose(fid);

% ════════════════════════════════════════════════════════════════════════
%  1. Launch and close
% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 1: Launch and close ══\n');
try
    api = launchHeadless();

    assert(isstruct(api), 'API must be a struct');
    assert(isfield(api, 'fig'), 'missing field: fig');
    assert(isfield(api, 'loadImages'), 'missing field: loadImages');
    assert(isfield(api, 'getImages'), 'missing field: getImages');
    assert(isfield(api, 'getActiveIdx'), 'missing field: getActiveIdx');
    assert(isfield(api, 'close'), 'missing field: close');
    assert(isvalid(api.fig), 'figure should be valid after launch');

    api.close();
    assert(~isvalid(api.fig), 'figure should be invalid after close()');

    fprintf('  API fields: %d\n', numel(fieldnames(api)));
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
    try; api.close(); catch; end
end

% ════════════════════════════════════════════════════════════════════════
%  2. Load synthetic TIFF
% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 2: Load synthetic TIFF ══\n');
try
    api = launchHeadless();
    cleanupApi = onCleanup(@() safeClose(api));

    api.loadImages({tiffPath1});

    imgs = api.getImages();
    assert(numel(imgs) == 1, sprintf('expected 1 image, got %d', numel(imgs)));
    assert(api.getActiveIdx() == 1, ...
        sprintf('expected activeIdx=1, got %d', api.getActiveIdx()));

    fprintf('  Images loaded: %d\n', numel(imgs));
    fprintf('  Active index: %d\n', api.getActiveIdx());
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
%  3. Image struct fields
% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 3: Image struct fields ══\n');
try
    api = launchHeadless();
    cleanupApi = onCleanup(@() safeClose(api));

    api.loadImages({tiffPath1});

    imgs = api.getImages();
    data = imgs{1};

    assert(isfield(data, 'metadata'), 'missing data.metadata');
    assert(isfield(data.metadata, 'parserSpecific'), 'missing parserSpecific');
    ps = data.metadata.parserSpecific;

    assert(isfield(ps, 'isImage') && ps.isImage == true, ...
        'parserSpecific.isImage must be true');
    assert(isfield(ps, 'imageData'), 'missing parserSpecific.imageData');

    imgD = ps.imageData;
    assert(isfield(imgD, 'width')    && imgD.width    == 48, ...
        sprintf('expected width=48, got %d', imgD.width));
    assert(isfield(imgD, 'height')   && imgD.height   == 64, ...
        sprintf('expected height=64, got %d', imgD.height));
    assert(isfield(imgD, 'bitDepth') && imgD.bitDepth == 16, ...
        sprintf('expected bitDepth=16, got %d', imgD.bitDepth));

    fprintf('  isImage: %d\n', ps.isImage);
    fprintf('  width: %d, height: %d, bitDepth: %d\n', ...
        imgD.width, imgD.height, imgD.bitDepth);
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
%  4. Set contrast
% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 4: Set contrast ══\n');
try
    api = launchHeadless();
    cleanupApi = onCleanup(@() safeClose(api));

    api.loadImages({tiffPath1});
    api.setContrast(100, 50000);   % no error = pass

    fprintf('  setContrast(100, 50000) — no error\n');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
%  5. Auto contrast
% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 5: Auto contrast ══\n');
try
    api = launchHeadless();
    cleanupApi = onCleanup(@() safeClose(api));

    api.loadImages({tiffPath1});
    api.autoContrast();   % no error = pass

    fprintf('  autoContrast() — no error\n');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
%  6. Apply Gaussian filter
% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 6: Apply Gaussian filter ══\n');
try
    api = launchHeadless();
    cleanupApi = onCleanup(@() safeClose(api));

    api.loadImages({tiffPath1});
    api.applyFilter('gaussian', struct('Sigma', 2.0));   % no error = pass

    fprintf('  applyFilter gaussian (Sigma=2.0) — no error\n');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
%  7. Apply Median filter
% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 7: Apply Median filter ══\n');
try
    api = launchHeadless();
    cleanupApi = onCleanup(@() safeClose(api));

    api.loadImages({tiffPath1});
    api.applyFilter('median', struct('WindowSize', 3));   % no error = pass

    fprintf('  applyFilter median (WindowSize=3) — no error\n');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
%  8. Compute FFT
% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 8: Compute FFT ══\n');
try
    api = launchHeadless();
    cleanupApi = onCleanup(@() safeClose(api));

    api.loadImages({tiffPath1});
    result = api.computeFFT();

    assert(isstruct(result), 'computeFFT must return a struct');
    assert(isfield(result, 'magnitude'), 'missing result.magnitude');
    assert(isfield(result, 'phase'),     'missing result.phase');
    assert(~isempty(result.magnitude),   'magnitude is empty');

    % Close any FFT figures that were opened
    closeFiguresWithTag('emViewerFFT');

    fprintf('  magnitude size: %dx%d\n', size(result.magnitude, 1), size(result.magnitude, 2));
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
    closeFiguresWithTag('emViewerFFT');
end

% ════════════════════════════════════════════════════════════════════════
%  9. Line profile
% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 9: Line profile ══\n');
try
    api = launchHeadless();
    cleanupApi = onCleanup(@() safeClose(api));

    api.loadImages({tiffPath1});
    result = api.getLineProfile(1, 1, 48, 64);

    assert(isstruct(result), 'getLineProfile must return a struct');
    assert(isfield(result, 'dist'),      'missing result.dist');
    assert(isfield(result, 'intensity'), 'missing result.intensity');
    assert(~isempty(result.dist),        'dist is empty');
    assert(~isempty(result.intensity),   'intensity is empty');

    % Close any profile figures that were opened
    closeFiguresWithTag('emViewerProfile');

    fprintf('  profile length: %d points\n', numel(result.dist));
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
    closeFiguresWithTag('emViewerProfile');
end

% ════════════════════════════════════════════════════════════════════════
%  10. Export image
% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 10: Export image ══\n');
try
    api = launchHeadless();
    cleanupApi = onCleanup(@() safeClose(api));

    api.loadImages({tiffPath1});

    exportPath = fullfile(tmpDir, 'export_test.png');
    api.exportImage(exportPath);

    assert(isfile(exportPath), 'exported file does not exist');
    d = dir(exportPath);
    assert(d.bytes > 0, 'exported file is empty');

    delete(exportPath);   % cleanup

    fprintf('  File written: %s (%d bytes)\n', exportPath, d.bytes);
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
%  11. Multiple images
% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 11: Multiple images ══\n');
try
    api = launchHeadless();
    cleanupApi = onCleanup(@() safeClose(api));

    api.loadImages({tiffPath1, tiffPath2});

    imgs = api.getImages();
    assert(numel(imgs) == 2, sprintf('expected 2 images, got %d', numel(imgs)));

    api.setActiveIdx(2);
    assert(api.getActiveIdx() == 2, ...
        sprintf('expected activeIdx=2 after setActiveIdx(2), got %d', api.getActiveIdx()));

    api.setActiveIdx(1);
    assert(api.getActiveIdx() == 1, ...
        sprintf('expected activeIdx=1 after switching back, got %d', api.getActiveIdx()));

    fprintf('  Images loaded: %d\n', numel(imgs));
    fprintf('  Index switching: 1 -> 2 -> 1 verified\n');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
%  12. Load RAW via API
% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 12: Load RAW via API ══\n');
try
    api = launchHeadless();
    cleanupApi = onCleanup(@() safeClose(api));

    % RAW requires dimension metadata passed as a struct
    rawSpec = struct('path', rawPath, 'Width', 24, 'Height', 32, 'BitDepth', 16);
    api.loadImages({rawSpec});

    imgs = api.getImages();
    assert(numel(imgs) == 1, sprintf('expected 1 image, got %d', numel(imgs)));
    assert(api.getActiveIdx() == 1, ...
        sprintf('expected activeIdx=1, got %d', api.getActiveIdx()));

    % Verify dimensions
    data = imgs{1};
    imgD = data.metadata.parserSpecific.imageData;
    assert(imgD.width  == 24, sprintf('expected width=24, got %d',  imgD.width));
    assert(imgD.height == 32, sprintf('expected height=32, got %d', imgD.height));

    fprintf('  RAW loaded: %dx%d px, bitDepth=%d\n', imgD.width, imgD.height, imgD.bitDepth);
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
%  13. Failed file load keeps GUI functional (error recovery)
% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 13: Failed file load recovery ══\n');
try
    safeClose(api);
    api = launchHeadless();

    % Try loading a non-existent file
    api.loadImages({'C:\nonexistent_test_image.tif'});
    drawnow;

    imgs = api.getImages();
    assert(isempty(imgs), ...
        sprintf('Expected 0 images from bad path, got %d', numel(imgs)));
    assert(api.getActiveIdx() == 0, 'Active index should be 0');
    assert(isvalid(api.fig), 'Figure should still be valid');
    fprintf('  Images after bad load: %d (expected 0)\n', numel(imgs));

    % Now load a valid file — GUI should still work
    api.loadImages({tiffPath1});
    drawnow;
    imgs = api.getImages();
    assert(numel(imgs) == 1, 'Should load valid image after failed one');
    assert(api.getActiveIdx() == 1, 'Active index should be 1');
    fprintf('  Valid image loaded after failure: yes\n');

    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
%  14. Corrupted TIFF load keeps GUI functional
% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 14: Corrupted TIFF load recovery ══\n');
try
    safeClose(api);
    api = launchHeadless();

    % Create a garbage file with .tif extension
    corruptTiff = fullfile(tmpDir, 'corrupt_test.tif');
    fid = fopen(corruptTiff, 'wb');
    fwrite(fid, uint8(randi([0 255], 1, 100)), 'uint8');
    fclose(fid);

    api.loadImages({corruptTiff});
    drawnow;

    imgs = api.getImages();
    assert(isempty(imgs), ...
        sprintf('Expected 0 images from corrupt TIFF, got %d', numel(imgs)));
    assert(isvalid(api.fig), 'Figure should still be valid');
    fprintf('  Images after corrupt load: %d (expected 0)\n', numel(imgs));

    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
%  15. Rotate 90 CW changes dimensions
% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 15: Rotate 90 CW changes dimensions ══\n');
try
    % Use a fresh visible instance for rotation/flip tests
    % (displayImage needs UI elements accessible to populate pixels)
    safeClose(api);
    api = emViewerGUI();
    drawnow;
    api.loadImages({tiffPath1});
    drawnow;

    dimsBefore = api.getImageDimensions();
    fprintf('  Before: %dx%d\n', dimsBefore(1), dimsBefore(2));
    assert(all(dimsBefore > 0), 'Image should have non-zero dimensions after load');

    api.rotateFlip('rot90cw');
    drawnow;

    dimsAfter = api.getImageDimensions();
    fprintf('  After:  %dx%d\n', dimsAfter(1), dimsAfter(2));
    assert(dimsAfter(1) == dimsBefore(2) && dimsAfter(2) == dimsBefore(1), ...
        sprintf('Expected %dx%d after CW rotation, got %dx%d', ...
        dimsBefore(2), dimsBefore(1), dimsAfter(1), dimsAfter(2)));

    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
%  16. Rotate 90 CCW changes dimensions
% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 16: Rotate 90 CCW changes dimensions ══\n');
try
    safeClose(api);
    api = emViewerGUI();
    drawnow;
    api.loadImages({tiffPath1});
    drawnow;

    dimsBefore = api.getImageDimensions();
    api.rotateFlip('rot90ccw');
    drawnow;

    dimsAfter = api.getImageDimensions();
    assert(dimsAfter(1) == dimsBefore(2) && dimsAfter(2) == dimsBefore(1), ...
        sprintf('Expected %dx%d after CCW rotation, got %dx%d', ...
        dimsBefore(2), dimsBefore(1), dimsAfter(1), dimsAfter(2)));
    fprintf('  Dims swapped: %dx%d -> %dx%d\n', dimsBefore(1), dimsBefore(2), dimsAfter(1), dimsAfter(2));

    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
%  17. Flip horizontal preserves dimensions
% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 17: Flip horizontal preserves dimensions ══\n');
try
    safeClose(api);
    api = emViewerGUI();
    drawnow;
    api.loadImages({tiffPath1});
    drawnow;

    dimsBefore = api.getImageDimensions();
    pxBefore = api.getPixels();

    api.rotateFlip('fliph');
    drawnow;

    dimsAfter = api.getImageDimensions();
    pxAfter = api.getPixels();
    assert(isequal(dimsBefore, dimsAfter), 'Flip should preserve dimensions');
    assert(~isequal(pxBefore.filtered, pxAfter.filtered), 'Flip should change pixel data');
    fprintf('  Dims preserved: %dx%d, pixels changed: yes\n', dimsAfter(1), dimsAfter(2));

    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
%  18. Double rotation is reversible
% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 18: Double rotation is reversible ══\n');
try
    safeClose(api);
    api = emViewerGUI();
    drawnow;
    api.loadImages({tiffPath1});
    drawnow;

    pxOriginal = api.getPixels().filtered;
    assert(~isempty(pxOriginal), 'Pixels should be populated after load');

    api.rotateFlip('rot90cw');
    drawnow;
    api.rotateFlip('rot90ccw');
    drawnow;

    pxRestored = api.getPixels().filtered;
    assert(isequal(pxOriginal, pxRestored), ...
        'CW then CCW rotation should restore original pixels');
    fprintf('  Round-trip rotation: pixels match original\n');

    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
%  19. Mix of valid and invalid files in one load
% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 19: Mix of valid and invalid files ══\n');
try
    safeClose(api);
    api = launchHeadless();

    api.loadImages({tiffPath1, fullfile(tmpDir, 'does_not_exist.tif'), tiffPath2});
    drawnow;

    imgs = api.getImages();
    assert(numel(imgs) == 2, ...
        sprintf('Expected 2 valid images loaded, got %d', numel(imgs)));
    fprintf('  Images loaded: %d (expected 2, skipped 1 bad)\n', numel(imgs));

    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
%  20. Flip vertical preserves dimensions
% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 20: Flip vertical preserves dimensions ══\n');
try
    safeClose(api);
    api = emViewerGUI();
    drawnow;
    api.loadImages({tiffPath1});
    drawnow;

    dimsBefore = api.getImageDimensions();
    pxBefore = api.getPixels();

    api.rotateFlip('flipv');
    drawnow;

    dimsAfter = api.getImageDimensions();
    pxAfter = api.getPixels();
    assert(isequal(dimsBefore, dimsAfter), 'Flip should preserve dimensions');
    assert(~isequal(pxBefore.filtered, pxAfter.filtered), 'Flip should change pixel data');
    fprintf('  Dims preserved: %dx%d, pixels changed: yes\n', dimsAfter(1), dimsAfter(2));

    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
%  SUMMARY
% ════════════════════════════════════════════════════════════════════════
fprintf('\n%s\n', repmat(char(9552), 1, 72));
fprintf('SUMMARY: %d/%d tests passed\n', passed, passed + failed);
if failed > 0
    fprintf('Status: FAIL\n');
    error('test_em_gui_harness:failures', '%d test(s) failed.', failed);
else
    fprintf('Status: ALL PASS\n');
end

% ════════════════════════════════════════════════════════════════════════
%  Local functions  (must appear after all script code)
% ════════════════════════════════════════════════════════════════════════
function api = launchHeadless()
%LAUNCHHEADLESS  Start emViewerGUI with the figure hidden.
    api = emViewerGUI();
    api.fig.Visible = 'off';
    drawnow;
end

function safeClose(api)
%SAFECLOSE  Close GUI figure if it is still valid.
    try
        if isfield(api, 'close') && isvalid(api.fig)
            api.close();
        end
    catch
    end
end

function closeFiguresWithTag(tag)
%CLOSEFIGUREWITHTAG  Close any open figures whose Tag matches the given string.
%   Used to clean up FFT or profile figures opened by the GUI.
    allFigs = findall(groot, 'Type', 'figure', 'Tag', tag);
    for k = 1:numel(allFigs)
        try; close(allFigs(k)); catch; end
    end
    % Also close any uifigures opened by the GUI callbacks
    allUiFigs = findall(groot, 'Type', 'figure');
    for k = 1:numel(allUiFigs)
        try
            if isfield(allUiFigs(k), 'Tag') && strcmp(allUiFigs(k).Tag, tag)
                close(allUiFigs(k));
            end
        catch
        end
    end
end
