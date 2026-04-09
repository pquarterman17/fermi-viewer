%TEST_REAL_DM3  Smoke-test importDM3 and importTIFF against real microscopy files.
%
%   Uses sample files in +test_datasets/Microscopy/ (checked into the repo).
%
%   Run standalone:  cd tests; run test_real_dm3
%   Run from root:   run tests/test_real_dm3

clear; clc;

% Ensure toolbox is on the path
thisDir = fileparts(mfilename('fullpath'));
rootDir = fileparts(fileparts(thisDir));
if ~contains(path, rootDir)
    addpath(rootDir);
end

fprintf('\n=== test_real_dm3: real Gatan DM3 + TIFF files ===\n');
pass = 0; fail = 0;

srcDir = fullfile(rootDir, '+test_datasets', 'Microscopy');
assert(isfolder(srcDir), 'Test data folder not found: %s', srcDir);

% ── DM3 files ────────────────────────────────────────────────────────
dm3files = dir(fullfile(srcDir, '*.dm3'));
assert(~isempty(dm3files), 'No .dm3 files found in +test_datasets/Microscopy');

for k = 1:numel(dm3files)
    fname = dm3files(k).name;
    fpath = fullfile(srcDir, fname);
    try
        data = parser.importDM3(fpath);

        % Basic struct validation
        assert(isstruct(data), 'output is not a struct');
        assert(isfield(data, 'time'),     'missing .time');
        assert(isfield(data, 'values'),   'missing .values');
        assert(isfield(data, 'metadata'), 'missing .metadata');

        img = data.metadata.parserSpecific.imageData;
        assert(img.height > 0, 'height <= 0');
        assert(img.width  > 0, 'width  <= 0');
        assert(~isempty(img.pixels), 'pixels empty');
        assert(numel(size(img.pixels)) >= 2, 'pixels not 2D+');

        calStr = 'uncalibrated';
        if img.calibrated
            calStr = sprintf('%.4g %s/px', img.pixelSize, img.pixelUnit);
        end
        fprintf('  [PASS] %-55s  %dx%d  %d-bit  %s\n', ...
            fname, img.width, img.height, img.bitDepth, calStr);
        pass = pass + 1;

    catch ME
        fprintf('  [FAIL] %-55s  %s\n', fname, ME.message);
        fail = fail + 1;
    end
end

% ── DM4 files ────────────────────────────────────────────────────────
dm4files = dir(fullfile(srcDir, '*.dm4'));
assert(~isempty(dm4files), 'No .dm4 files found in +test_datasets/Microscopy');

for k = 1:numel(dm4files)
    fname = dm4files(k).name;
    fpath = fullfile(srcDir, fname);
    try
        data = parser.importDM4(fpath);

        assert(isstruct(data), 'output is not a struct');
        assert(isfield(data, 'time'),     'missing .time');
        assert(isfield(data, 'values'),   'missing .values');
        assert(isfield(data, 'metadata'), 'missing .metadata');
        assert(strcmp(data.metadata.parserName, 'importDM4'), ...
            'parserName should be importDM4');

        ps = data.metadata.parserSpecific;
        assert(isfield(ps, 'is2D') || isfield(ps, 'isImage') || ...
               isfield(ps, 'isSpectrum'), ...
            'parserSpecific missing mode flag');

        if isfield(ps, 'imageData') && ~isempty(ps.imageData)
            img = ps.imageData;
            assert(img.height > 0 && img.width > 0, 'zero dimensions');
            assert(~isempty(img.pixels), 'pixels empty');
            calStr = 'uncalibrated';
            if img.calibrated
                calStr = sprintf('%.4g %s/px', img.pixelSize, img.pixelUnit);
            end
            fprintf('  [PASS] %-55s  %dx%d  %d-bit  %s\n', ...
                fname, img.width, img.height, img.bitDepth, calStr);
        else
            % 1D spectrum or 3D SI cube
            fprintf('  [PASS] %-55s  (spectrum/SI mode)\n', fname);
        end
        pass = pass + 1;

    catch ME
        fprintf('  [FAIL] %-55s  %s\n', fname, ME.message);
        fail = fail + 1;
    end
end

% importAuto dispatch for DM4
firstDM4 = fullfile(srcDir, dm4files(1).name);
try
    data = parser.importAuto(firstDM4);
    assert(strcmp(data.metadata.parserName, 'importDM4'), ...
        'importAuto should dispatch .dm4 to importDM4');
    fprintf('  [PASS] importAuto(*.dm4) dispatches correctly\n');
    pass = pass + 1;
catch ME
    fprintf('  [FAIL] importAuto(*.dm4): %s\n', ME.message);
    fail = fail + 1;
end

% ── TIFF files ───────────────────────────────────────────────────────
tiffiles = dir(fullfile(srcDir, '*.tif'));
for k = 1:numel(tiffiles)
    fname = tiffiles(k).name;
    fpath = fullfile(srcDir, fname);
    try
        data = parser.importTIFF(fpath);
        img = data.metadata.parserSpecific.imageData;
        calStr = 'uncalibrated';
        if img.calibrated
            calStr = sprintf('%.4g %s/px', img.pixelSize, img.pixelUnit);
        end
        fprintf('  [PASS] %-55s  %dx%d  %d-bit  %s\n', ...
            fname, img.width, img.height, img.bitDepth, calStr);
        pass = pass + 1;
    catch ME
        fprintf('  [FAIL] %-55s  %s\n', fname, ME.message);
        fail = fail + 1;
    end
end

% ── importAuto dispatch ──────────────────────────────────────────────
fprintf('\n  --- importAuto dispatch ---\n');
firstDM3 = fullfile(srcDir, dm3files(1).name);
try
    data = parser.importAuto(firstDM3);
    assert(data.metadata.parserSpecific.imageData.height > 0);
    fprintf('  [PASS] importAuto(*.dm3) dispatches correctly\n');
    pass = pass + 1;
catch ME
    fprintf('  [FAIL] importAuto(*.dm3): %s\n', ME.message);
    fail = fail + 1;
end

if ~isempty(tiffiles)
    firstTIF = fullfile(srcDir, tiffiles(1).name);
    try
        data = parser.importAuto(firstTIF);
        assert(data.metadata.parserSpecific.imageData.height > 0);
        fprintf('  [PASS] importAuto(*.tif) dispatches correctly\n');
        pass = pass + 1;
    catch ME
        fprintf('  [FAIL] importAuto(*.tif): %s\n', ME.message);
        fail = fail + 1;
    end
end

fprintf('\n=== Results: %d passed, %d failed ===\n\n', pass, fail);
if fail > 0
    error('test_real_dm3: %d test(s) FAILED', fail);
end
