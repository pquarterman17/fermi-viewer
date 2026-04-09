%TEST_EM_GUI_REAL_DM  Drive FermiViewer GUI against real DM3/DM4 microscopy files.
%
%   Exercises the full programmatic API against every .dm3/.dm4 file in
%   +test_datasets/Microscopy, covering: load, struct validation, contrast,
%   auto-contrast, gamma, invert, colormaps, filters (gaussian/median),
%   FFT, line profile, measurements, rotate/flip, crop, zoom, export,
%   pixel-size calibration, annotations, and multi-image switching.
%
%   Run standalone:  cd tests; run test_em_gui_real_dm
%   Run from root:   run tests/imaging/test_em_gui_real_dm

clear; clc;

thisDir = fileparts(mfilename('fullpath'));
rootDir = fileparts(fileparts(thisDir));
if ~contains(path, rootDir); addpath(rootDir); end

srcDir = fullfile(rootDir, '+test_datasets', 'Microscopy');
assert(isfolder(srcDir), 'Test data folder not found: %s', srcDir);

dm3files = dir(fullfile(srcDir, '*.dm3'));
dm4files = dir(fullfile(srcDir, '*.dm4'));
allFiles = [arrayfun(@(f) fullfile(srcDir, f.name), dm3files, 'UniformOutput', false); ...
            arrayfun(@(f) fullfile(srcDir, f.name), dm4files, 'UniformOutput', false)];
assert(~isempty(allFiles), 'No DM3/DM4 files in test dataset');

fprintf('\n=== test_em_gui_real_dm: %d real files ===\n', numel(allFiles));

tmpDir = fullfile(tempdir, 'em_gui_real_dm_' + string(datetime('now','Format','yyyyMMdd_HHmmss')));
mkdir(tmpDir);
cleanupTmp = onCleanup(@() rmdir(tmpDir, 's'));

passed = 0; failed = 0;
api = [];

% ════════════════════════════════════════════════════════════════════════
% TEST A: Load every DM3/DM4 file individually through the GUI
% ════════════════════════════════════════════════════════════════════════
fprintf('\n── A. Per-file load smoke test ──\n');
for k = 1:numel(allFiles)
    [~, fname, ext] = fileparts(allFiles{k});
    label = [fname ext];
    try
        safeClose(api);
        api = FermiViewer(); api.fig.Visible = 'off'; drawnow;
        api.loadImages(allFiles(k));
        drawnow;

        imgs = api.getImages();
        assert(numel(imgs) == 1, sprintf('expected 1 image, got %d', numel(imgs)));
        assert(api.getActiveIdx() == 1, 'activeIdx should be 1');

        ps = imgs{1}.metadata.parserSpecific;
        if isfield(ps, 'imageData') && ~isempty(ps.imageData)
            imgD = ps.imageData;
            assert(imgD.width > 0 && imgD.height > 0, 'zero dimensions');
            fprintf('  [PASS] %-50s %dx%d %d-bit\n', label, imgD.width, imgD.height, imgD.bitDepth);
        else
            fprintf('  [PASS] %-50s (spectrum/SI mode)\n', label);
        end
        passed = passed + 1;
    catch ME
        fprintf('  [FAIL] %-50s %s\n', label, ME.message);
        failed = failed + 1;
    end
end

% Filter to files that load as images (skip any 1D spectra) for the
% operation tests below.
imageFiles = {};
for k = 1:numel(allFiles)
    try
        d = parser.importAuto(allFiles{k});
        ps = d.metadata.parserSpecific;
        if isfield(ps, 'imageData') && ~isempty(ps.imageData) && ...
           ps.imageData.width > 0 && ps.imageData.height > 0
            imageFiles{end+1} = allFiles{k}; %#ok<AGROW>
        end
    catch
    end
end
assert(~isempty(imageFiles), 'No image-mode files available for operation tests');
primaryFile = imageFiles{1};
fprintf('\nUsing primary file for operation tests: %s\n', primaryFile);

% ════════════════════════════════════════════════════════════════════════
% TEST B: Contrast controls (set, auto, reset, transform, invert, gamma)
% ════════════════════════════════════════════════════════════════════════
fprintf('\n── B. Contrast / display controls ──\n');
try
    safeClose(api);
    api = FermiViewer(); drawnow;
    api.loadImages({primaryFile}); drawnow;

    api.autoContrast();        drawnow;
    api.setContrast(10, 250);  drawnow;
    api.resetContrast();       drawnow;

    % Contrast transform modes
    for mode = {'linear', 'log', 'sqrt'}
        api.setContrastTransform(mode{1}); drawnow;
        assert(strcmp(api.getContrastTransform(), mode{1}), ...
            sprintf('transform mode mismatch: %s', mode{1}));
    end
    api.setContrastTransform('linear'); drawnow;

    api.setInvert(true);  drawnow; assert(api.isInverted(), 'invert on failed');
    api.setInvert(false); drawnow; assert(~api.isInverted(), 'invert off failed');

    api.setGamma(1.5); drawnow;
    api.setGamma(1.0); drawnow;

    fprintf('  [PASS] contrast/gamma/invert/transform cycle\n');
    passed = passed + 1;
catch ME
    fprintf('  [FAIL] contrast suite: %s\n', ME.message);
    failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
% TEST C: Colormaps (set + cycle)
% ════════════════════════════════════════════════════════════════════════
fprintf('\n── C. Colormaps ──\n');
try
    safeClose(api);
    api = FermiViewer(); drawnow;
    api.loadImages({primaryFile}); drawnow;

    for cmap = {'gray', 'parula', 'hot', 'jet', 'viridis'}
        try
            api.setColormap(cmap{1}); drawnow;
        catch
            % Some names may not be registered; skip silently
        end
    end
    api.cycleColormap(); drawnow;
    api.setColorbar(true); drawnow;
    assert(api.isColorbarVisible(), 'colorbar should be visible');
    api.setColorbar(false); drawnow;

    fprintf('  [PASS] colormap + colorbar toggles\n');
    passed = passed + 1;
catch ME
    fprintf('  [FAIL] colormap suite: %s\n', ME.message);
    failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
% TEST D: Filters (Gaussian + Median)
% ════════════════════════════════════════════════════════════════════════
fprintf('\n── D. Filters ──\n');
try
    safeClose(api);
    api = FermiViewer(); drawnow;
    api.loadImages({primaryFile}); drawnow;

    pxOrig = api.getPixels().filtered;
    api.applyFilter('gaussian', struct('Sigma', 2.0)); drawnow;
    pxGauss = api.getPixels().filtered;
    assert(~isequal(pxOrig, pxGauss), 'Gaussian filter should change pixels');

    api.applyFilter('median', struct('WindowSize', 3)); drawnow;
    fprintf('  [PASS] gaussian + median filter chain\n');
    passed = passed + 1;
catch ME
    fprintf('  [FAIL] filters: %s\n', ME.message);
    failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
% TEST E: FFT + noise estimate
% ════════════════════════════════════════════════════════════════════════
fprintf('\n── E. FFT + noise estimate ──\n');
try
    safeClose(api);
    api = FermiViewer(); api.fig.Visible = 'off'; drawnow;
    api.loadImages({primaryFile}); drawnow;

    fftRes = api.computeFFT();
    assert(isstruct(fftRes) && isfield(fftRes, 'magnitude'), 'FFT result malformed');
    assert(~isempty(fftRes.magnitude), 'FFT magnitude empty');

    noise = api.noiseEstimate();
    assert(isnumeric(noise) || isstruct(noise), 'noiseEstimate returned nothing');

    closeFiguresWithTag('fermiViewerFFT');
    fprintf('  [PASS] FFT %dx%d + noise estimate\n', size(fftRes.magnitude,1), size(fftRes.magnitude,2));
    passed = passed + 1;
catch ME
    fprintf('  [FAIL] FFT/noise: %s\n', ME.message);
    failed = failed + 1;
    closeFiguresWithTag('fermiViewerFFT');
end

% ════════════════════════════════════════════════════════════════════════
% TEST F: Line profile + measurements (distance, d-spacing)
% ════════════════════════════════════════════════════════════════════════
fprintf('\n── F. Line profile + measurements ──\n');
try
    safeClose(api);
    api = FermiViewer(); drawnow;
    api.loadImages({primaryFile}); drawnow;

    dims = api.getImageDimensions();   % [rows cols] = [height width]
    w = dims(2); h = dims(1);
    x2 = max(2, round(w * 0.8));
    y2 = max(2, round(h * 0.8));

    prof = api.getLineProfile(1, 1, x2, y2);
    assert(~isempty(prof.dist) && ~isempty(prof.intensity), 'empty profile');

    api.measureDistance(1, 1, x2, y2);
    api.measureDSpacing(round(w*0.3), round(h*0.3), round(w*0.7), round(h*0.7));

    log = api.getMeasurementLog();
    assert(~isempty(log), 'measurement log should be populated');

    closeFiguresWithTag('fermiViewerProfile');
    fprintf('  [PASS] profile (%d pts) + %d measurements\n', numel(prof.dist), numel(log));
    passed = passed + 1;
catch ME
    fprintf('  [FAIL] profile/measure: %s\n', ME.message);
    failed = failed + 1;
    closeFiguresWithTag('fermiViewerProfile');
end

% ════════════════════════════════════════════════════════════════════════
% TEST G: Rotate / Flip round-trip
% ════════════════════════════════════════════════════════════════════════
fprintf('\n── G. Rotate / flip ──\n');
try
    safeClose(api);
    api = FermiViewer(); drawnow;
    api.loadImages({primaryFile}); drawnow;

    dimsBefore = api.getImageDimensions();
    pxOrig = api.getPixels().filtered;

    api.rotateFlip('rot90cw');  drawnow;
    dimsRot = api.getImageDimensions();
    assert(dimsRot(1) == dimsBefore(2) && dimsRot(2) == dimsBefore(1), ...
        'CW rotation should swap dimensions');

    api.rotateFlip('rot90ccw'); drawnow;
    assert(isequal(api.getPixels().filtered, pxOrig), 'CW/CCW round-trip mismatch');

    api.rotateFlip('fliph'); drawnow;
    api.rotateFlip('fliph'); drawnow;
    assert(isequal(api.getPixels().filtered, pxOrig), 'double fliph should restore');

    api.rotateFlip('flipv'); drawnow;
    api.rotateFlip('flipv'); drawnow;
    assert(isequal(api.getPixels().filtered, pxOrig), 'double flipv should restore');

    fprintf('  [PASS] rot90 CW/CCW + fliph/flipv round-trips\n');
    passed = passed + 1;
catch ME
    fprintf('  [FAIL] rotate/flip: %s\n', ME.message);
    failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
% TEST H: Crop + zoom + reset
% ════════════════════════════════════════════════════════════════════════
fprintf('\n── H. Crop / zoom ──\n');
try
    safeClose(api);
    api = FermiViewer(); drawnow;
    api.loadImages({primaryFile}); drawnow;

    dims = api.getImageDimensions();
    w = dims(2); h = dims(1);

    api.zoomRect(round(w*0.2), round(h*0.2), round(w*0.8), round(h*0.8)); drawnow;
    lims = api.getAxLimits();
    assert(~isempty(lims.XLim) && ~isempty(lims.YLim), 'axis limits empty after zoom');

    api.resetZoom(); drawnow;

    api.cropRect(round(w*0.25), round(h*0.25), round(w*0.75), round(h*0.75)); drawnow;
    dimsCrop = api.getImageDimensions();
    assert(dimsCrop(1) < dims(1) && dimsCrop(2) < dims(2), ...
        sprintf('crop should shrink dims: %dx%d -> %dx%d', dims(1), dims(2), dimsCrop(1), dimsCrop(2)));

    fprintf('  [PASS] zoom + crop %dx%d -> %dx%d\n', dims(1), dims(2), dimsCrop(1), dimsCrop(2));
    passed = passed + 1;
catch ME
    fprintf('  [FAIL] crop/zoom: %s\n', ME.message);
    failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
% TEST I: Annotations + pixel-size calibration
% ════════════════════════════════════════════════════════════════════════
fprintf('\n── I. Annotations + pixel calibration ──\n');
try
    safeClose(api);
    api = FermiViewer(); drawnow;
    api.loadImages({primaryFile}); drawnow;

    dims = api.getImageDimensions();
    api.placeAnnotation(round(dims(2)/2), round(dims(1)/2), 'test', 12, [1 0 0]);
    api.annotRect(1, 1, round(dims(2)/3), round(dims(1)/3));
    api.clearAnnotations();

    api.setPixelSize(0.5, 'nm');

    fprintf('  [PASS] annotations + pixel-size set\n');
    passed = passed + 1;
catch ME
    fprintf('  [FAIL] annotations/calibration: %s\n', ME.message);
    failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
% TEST J: Export PNG + TIFF
% ════════════════════════════════════════════════════════════════════════
fprintf('\n── J. Export ──\n');
try
    safeClose(api);
    api = FermiViewer(); api.fig.Visible = 'off'; drawnow;
    api.loadImages({primaryFile}); drawnow;

    pngPath = fullfile(tmpDir, 'real_dm_export.png');
    tifPath = fullfile(tmpDir, 'real_dm_export.tif');
    api.exportImage(pngPath);
    api.exportImage(tifPath);

    assert(isfile(pngPath), 'PNG not written');
    assert(isfile(tifPath), 'TIFF not written');
    dPng = dir(pngPath); dTif = dir(tifPath);
    assert(dPng.bytes > 0 && dTif.bytes > 0, 'export files empty');

    fprintf('  [PASS] PNG (%d B) + TIFF (%d B)\n', dPng.bytes, dTif.bytes);
    passed = passed + 1;
catch ME
    fprintf('  [FAIL] export: %s\n', ME.message);
    failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
% TEST K: Multi-image load + index switching
% ════════════════════════════════════════════════════════════════════════
fprintf('\n── K. Multi-image switching ──\n');
try
    safeClose(api);
    api = FermiViewer(); api.fig.Visible = 'off'; drawnow;

    nLoad = min(5, numel(imageFiles));
    api.loadImages(imageFiles(1:nLoad)); drawnow;
    imgs = api.getImages();
    assert(numel(imgs) == nLoad, sprintf('expected %d images, got %d', nLoad, numel(imgs)));

    for k = 1:nLoad
        api.setActiveIdx(k); drawnow;
        assert(api.getActiveIdx() == k, sprintf('setActiveIdx(%d) failed', k));
    end
    fprintf('  [PASS] loaded %d images, cycled through all indices\n', nLoad);
    passed = passed + 1;
catch ME
    fprintf('  [FAIL] multi-image: %s\n', ME.message);
    failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
% TEST L: Session save + load round-trip
% ════════════════════════════════════════════════════════════════════════
fprintf('\n── L. Session save/load ──\n');
try
    safeClose(api);
    api = FermiViewer(); api.fig.Visible = 'off'; drawnow;
    api.loadImages({primaryFile}); drawnow;
    api.setContrast(20, 200); drawnow;

    sessPath = fullfile(tmpDir, 'session.mat');
    api.sessionSave(sessPath);
    assert(isfile(sessPath), 'session file not written');

    safeClose(api);
    api = FermiViewer(); api.fig.Visible = 'off'; drawnow;
    api.sessionLoad(sessPath); drawnow;
    imgs = api.getImages();
    assert(numel(imgs) >= 1, 'session did not restore image');

    fprintf('  [PASS] session round-trip (%d images)\n', numel(imgs));
    passed = passed + 1;
catch ME
    fprintf('  [FAIL] session: %s\n', ME.message);
    failed = failed + 1;
end

safeClose(api);

% ════════════════════════════════════════════════════════════════════════
fprintf('\n%s\n', repmat(char(9552), 1, 72));
fprintf('SUMMARY: %d/%d tests passed\n', passed, passed + failed);
if failed > 0
    error('test_em_gui_real_dm:failures', '%d test(s) failed.', failed);
else
    fprintf('Status: ALL PASS\n');
end

% ════════════════════════════════════════════════════════════════════════
% Local helpers
% ════════════════════════════════════════════════════════════════════════
function safeClose(api)
    try
        if ~isempty(api) && isstruct(api) && isfield(api, 'close') && isvalid(api.fig)
            api.close();
        end
    catch
    end
end

function closeFiguresWithTag(tag)
    allFigs = findall(groot, 'Type', 'figure', 'Tag', tag);
    for k = 1:numel(allFigs)
        try; close(allFigs(k)); catch; end
    end
end
