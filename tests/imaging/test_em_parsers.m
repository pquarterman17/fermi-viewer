%TEST_EM_PARSERS  Synthetic-data smoke tests for EM image parsers.
%
%   Tests cover:
%     - importTIFF: 8-bit grayscale, 16-bit grayscale, RGB, multi-page stack
%     - importRawImage: 16-bit read/roundtrip, 8-bit, wrong-size error
%     - importDM3: struct fields, dimensions, pixel values, calibration
%     - importAuto dispatch for .tif and .dm3 extensions
%     - resolveParser dispatch for .dm3 and .dm4 extensions
%
%   All test data is generated synthetically via imwrite/fwrite into
%   tempdir. Temp files are cleaned up on exit.
%
%   Run standalone:  cd tests; run test_em_parsers
%   Run from root:   run tests/test_em_parsers
%       runAllTests(Group="em")

clear; clc;
fprintf('\n═══ test_em_parsers ═══\n');

% Ensure toolbox is on the path
thisDir = fileparts(mfilename('fullpath'));
rootDir = fileparts(fileparts(thisDir));
if ~contains(path, rootDir)
    addpath(rootDir);
end

ROOT = rootDir;

nPass = 0;
nFail = 0;
tmpFiles = {};

try  % outer catch — clean up temp files even on unexpected error

% ════════════════════════════════════════════════════════════════════════
%  importTIFF tests
% ════════════════════════════════════════════════════════════════════════

% ── Test 1: 8-bit grayscale TIFF ─────────────────────────────────────
try
    fp = tempname_ext('.tif');
    tmpFiles{end+1} = fp;

    img8 = uint8(reshape(0:255, [16, 16]));   % 16x16 ramp
    imwrite(img8, fp);

    d = parser.importTIFF(fp);

    assert(isstruct(d),                         'output must be struct');
    assert(isfield(d, 'time'),                  'missing field: time');
    assert(isfield(d, 'values'),                'missing field: values');
    assert(isfield(d, 'labels'),                'missing field: labels');
    assert(isfield(d, 'units'),                 'missing field: units');
    assert(isfield(d, 'metadata'),              'missing field: metadata');
    assert(numel(d.time) == 16,                 'time length should equal H=16');
    assert(size(d.values, 1) == 16,             'values rows should equal H=16');
    assert(size(d.values, 2) == 1,              'values should be 1 column (mean per row)');

    img = d.metadata.parserSpecific.imageData;
    assert(img.bitDepth    == 8,                'bitDepth should be 8');
    assert(img.height      == 16,               'height should be 16');
    assert(img.width       == 16,               'width should be 16');
    assert(img.numChannels == 1,                'numChannels should be 1 (grayscale)');
    assert(img.numFrames   == 1,                'numFrames should be 1');
    assert(isempty(img.frames),                 'frames should be empty for single image');
    assert(isnan(img.pixelSize),                'pixelSize should be NaN (no metadata)');
    assert(~img.calibrated,                     'calibrated should be false');
    assert(d.metadata.parserSpecific.isImage,   'isImage should be true');
    assert(isa(img.pixels, 'uint8'),            'pixels should be uint8 for 8-bit TIFF');
    assert(isequal(size(img.pixels), [16, 16]), 'pixels should be [16 x 16]');

    nPass = nPass + 1;
    fprintf('  ✔ Test 1: importTIFF 8-bit grayscale\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 1: %s\n', ME.message);
end

% ── Test 2: 16-bit grayscale TIFF ────────────────────────────────────
try
    fp = tempname_ext('.tif');
    tmpFiles{end+1} = fp;

    img16 = uint16(reshape(linspace(0, 65535, 48*64), [48, 64]));
    imwrite(img16, fp);

    d = parser.importTIFF(fp);

    img = d.metadata.parserSpecific.imageData;
    assert(img.bitDepth    == 16,               'bitDepth should be 16');
    assert(img.height      == 48,               'height should be 48');
    assert(img.width       == 64,               'width should be 64');
    assert(numel(d.time)   == 48,               'time length should equal H=48');
    assert(isa(img.pixels, 'uint16'),           'pixels should be uint16 for 16-bit TIFF');
    % Verify mean row profile is monotonically increasing (ramp image)
    assert(all(diff(d.values) >= 0),            'mean per row should be non-decreasing for ramp');

    nPass = nPass + 1;
    fprintf('  ✔ Test 2: importTIFF 16-bit grayscale\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 2: %s\n', ME.message);
end

% ── Test 3: RGB TIFF ─────────────────────────────────────────────────
try
    fp = tempname_ext('.tif');
    tmpFiles{end+1} = fp;

    % 32x32 RGB: red channel ramp, others zero
    imgRGB = zeros(32, 32, 3, 'uint8');
    imgRGB(:,:,1) = uint8(repmat(linspace(0,255,32)', 1, 32));
    imwrite(imgRGB, fp);

    d = parser.importTIFF(fp);

    img = d.metadata.parserSpecific.imageData;
    assert(img.numChannels == 3,               'numChannels should be 3 for RGB');
    assert(img.height      == 32,              'height should be 32');
    assert(img.width       == 32,              'width should be 32');
    assert(isequal(size(img.pixels), [32,32,3]),'pixels should be [32 x 32 x 3]');
    assert(numel(d.time)   == 32,              'time length should equal H=32');

    nPass = nPass + 1;
    fprintf('  ✔ Test 3: importTIFF RGB\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 3: %s\n', ME.message);
end

% ── Test 4: Multi-page (stack) TIFF ──────────────────────────────────
try
    fp = tempname_ext('.tif');
    tmpFiles{end+1} = fp;

    frame1 = uint8(zeros(20, 30));
    frame2 = uint8(128 * ones(20, 30));
    frame3 = uint8(255 * ones(20, 30));

    imwrite(frame1, fp);
    imwrite(frame2, fp, 'WriteMode', 'append');
    imwrite(frame3, fp, 'WriteMode', 'append');

    d = parser.importTIFF(fp);

    img = d.metadata.parserSpecific.imageData;
    assert(img.numFrames == 3,                 'numFrames should be 3');
    assert(numel(img.frames) == 3,             'frames cell should have 3 entries');
    assert(isa(img.frames{1}, 'uint8'),        'frame 1 should be uint8');
    assert(isequal(size(img.frames{2}), [20,30]), 'frame 2 should be [20 x 30]');
    % Verify mean value of frame 2 (~128) differs from frame 3 (~255)
    assert(mean(img.frames{3}(:)) > mean(img.frames{1}(:)), ...
        'frame 3 should be brighter than frame 1');
    % 1-D fallback should be computed from frame 1 (H rows)
    assert(numel(d.time) == 20,                'time should have H=20 entries');

    nPass = nPass + 1;
    fprintf('  ✔ Test 4: importTIFF multi-page stack (3 frames)\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 4: %s\n', ME.message);
end

% ── Test 5: .tiff extension (not just .tif) ──────────────────────────
try
    fp = tempname_ext('.tiff');
    tmpFiles{end+1} = fp;

    imwrite(uint8(eye(8) * 200), fp);
    d = parser.importTIFF(fp);

    assert(d.metadata.parserSpecific.isImage, 'isImage should be true for .tiff file');
    assert(d.metadata.parserSpecific.imageData.height == 8, 'height should be 8');

    nPass = nPass + 1;
    fprintf('  ✔ Test 5: importTIFF with .tiff extension\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 5: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  importRawImage tests
% ════════════════════════════════════════════════════════════════════════

% ── Test 6: 16-bit RAW round-trip ────────────────────────────────────
try
    fp = tempname_ext('.raw');
    tmpFiles{end+1} = fp;

    W = 64;  H = 48;
    orig = uint16(reshape(0 : W*H-1, W, H)');   % [H x W] ramp
    writeBinaryImage(fp, orig, 'uint16');

    d = parser.importRawImage(fp, Width=W, Height=H, BitDepth=16);

    assert(isstruct(d),                         'output must be struct');
    assert(isfield(d, 'time'),                  'missing field: time');
    assert(isfield(d, 'values'),                'missing field: values');

    img = d.metadata.parserSpecific.imageData;
    assert(img.height      == H,                'height mismatch');
    assert(img.width       == W,                'width mismatch');
    assert(img.bitDepth    == 16,               'bitDepth should be 16');
    assert(img.numChannels == 1,                'numChannels should be 1');
    assert(img.numFrames   == 1,                'numFrames should be 1');
    assert(isnan(img.pixelSize),                'pixelSize should be NaN');
    assert(~img.calibrated,                     'calibrated should be false');
    assert(d.metadata.parserSpecific.isImage,   'isImage should be true');
    assert(isa(img.pixels, 'uint16'),           'pixels should be uint16');
    assert(isequal(size(img.pixels), [H, W]),   'pixels size should be [H x W]');

    % Round-trip check: pixel values must match original
    assert(isequal(img.pixels, orig), 'pixel values should match original after round-trip');

    nPass = nPass + 1;
    fprintf('  ✔ Test 6: importRawImage 16-bit round-trip\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 6: %s\n', ME.message);
end

% ── Test 7: 8-bit RAW ────────────────────────────────────────────────
try
    fp = tempname_ext('.raw');
    tmpFiles{end+1} = fp;

    W = 32;  H = 24;
    orig8 = uint8(mod(reshape(0:W*H-1, W, H)', 256));
    writeBinaryImage(fp, orig8, 'uint8');

    d = parser.importRawImage(fp, Width=W, Height=H, BitDepth=8);

    img = d.metadata.parserSpecific.imageData;
    assert(img.bitDepth == 8,                   'bitDepth should be 8');
    assert(isa(img.pixels, 'uint8'),            'pixels should be uint8');
    assert(isequal(img.pixels, orig8),          'pixel values should match original');

    nPass = nPass + 1;
    fprintf('  ✔ Test 7: importRawImage 8-bit\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 7: %s\n', ME.message);
end

% ── Test 8: Wrong-size error ─────────────────────────────────────────
try
    fp = tempname_ext('.raw');
    tmpFiles{end+1} = fp;

    % Write 64x48 uint16 but claim 100x100
    W = 64;  H = 48;
    orig = uint16(ones(H, W));
    writeBinaryImage(fp, orig, 'uint16');

    threwError = false;
    try
        parser.importRawImage(fp, Width=100, Height=100, BitDepth=16);
    catch ME2
        if contains(ME2.identifier, 'sizeMismatch')
            threwError = true;
        else
            rethrow(ME2);
        end
    end
    assert(threwError, 'Expected sizeMismatch error for wrong dimensions');

    nPass = nPass + 1;
    fprintf('  ✔ Test 8: importRawImage wrong-size error\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 8: %s\n', ME.message);
end

% ── Test 9: 32-bit float RAW ─────────────────────────────────────────
try
    fp = tempname_ext('.raw');
    tmpFiles{end+1} = fp;

    W = 16;  H = 12;
    origF = single(randn(H, W));
    writeBinaryImage(fp, origF, 'single');

    d = parser.importRawImage(fp, Width=W, Height=H, BitDepth=32);

    img = d.metadata.parserSpecific.imageData;
    assert(img.bitDepth == 32,                  'bitDepth should be 32');
    assert(isa(img.pixels, 'single'),           'pixels should be single for 32-bit');
    assert(isequal(img.pixels, origF),          'pixel values should match original');

    nPass = nPass + 1;
    fprintf('  ✔ Test 9: importRawImage 32-bit float\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 9: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  importAuto dispatch tests
% ════════════════════════════════════════════════════════════════════════

% ── Test 10: importAuto dispatches .tif → importTIFF ─────────────────
try
    fp = tempname_ext('.tif');
    tmpFiles{end+1} = fp;

    imwrite(uint8(magic(8)), fp);   % 8x8 magic square

    [d, parserName] = parser.importAuto(fp);

    assert(strcmp(parserName, 'importTIFF'),    'importAuto should dispatch to importTIFF');
    assert(isstruct(d),                         'output must be struct');
    assert(d.metadata.parserSpecific.isImage,   'isImage should be true');

    nPass = nPass + 1;
    fprintf('  ✔ Test 10: importAuto dispatch .tif → importTIFF\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 10: %s\n', ME.message);
end

% ── Test 11: importAuto dispatches .tiff → importTIFF ────────────────
try
    fp = tempname_ext('.tiff');
    tmpFiles{end+1} = fp;

    imwrite(uint8(ones(4,4)*100), fp);

    [~, parserName] = parser.importAuto(fp);
    assert(strcmp(parserName, 'importTIFF'),    'importAuto should dispatch .tiff → importTIFF');

    nPass = nPass + 1;
    fprintf('  ✔ Test 11: importAuto dispatch .tiff → importTIFF\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 11: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  importDM3 tests
% ════════════════════════════════════════════════════════════════════════

% Synthetic DM3 parameters shared across Tests 12-14
DM3_W = 8;   DM3_H = 6;
DM3_SCALE = 2.5;
DM3_UNITS = 'nm';
DM3_PIXELS = uint16(reshape(100:100+DM3_W*DM3_H-1, DM3_W, DM3_H)');

% ── Test 12: importDM3 — struct fields and dimensions ─────────────────
try
    fp = tempname_ext('.dm3');
    tmpFiles{end+1} = fp;

    writeSyntheticDM3(fp, DM3_PIXELS, DM3_SCALE, DM3_UNITS);

    d = parser.importDM3(fp);

    assert(isstruct(d),                         'output must be struct');
    assert(isfield(d, 'time'),                  'missing field: time');
    assert(isfield(d, 'values'),                'missing field: values');
    assert(isfield(d, 'labels'),                'missing field: labels');
    assert(isfield(d, 'units'),                 'missing field: units');
    assert(isfield(d, 'metadata'),              'missing field: metadata');
    assert(numel(d.time) == DM3_H,              'time length should equal H');
    assert(size(d.values, 1) == DM3_H,          'values rows should equal H');
    assert(size(d.values, 2) == 1,              'values should be 1 column');

    img = d.metadata.parserSpecific.imageData;
    assert(img.bitDepth    == 16,               'bitDepth should be 16 (uint16, DataType=10)');
    assert(img.height      == DM3_H,            'height mismatch');
    assert(img.width       == DM3_W,            'width mismatch');
    assert(img.numChannels == 1,                'numChannels should be 1');
    assert(img.numFrames   == 1,                'numFrames should be 1');
    assert(isempty(img.frames),                 'frames should be empty for single image');
    assert(d.metadata.parserSpecific.isImage,   'isImage should be true');
    assert(strcmp(d.metadata.parserName, 'importDM3'), 'parserName mismatch');

    nPass = nPass + 1;
    fprintf('  ✔ Test 12: importDM3 struct fields and dimensions\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 12: %s\n', ME.message);
end

% ── Test 13: importDM3 — pixel values round-trip ─────────────────────
try
    fp = tempname_ext('.dm3');
    tmpFiles{end+1} = fp;

    writeSyntheticDM3(fp, DM3_PIXELS, DM3_SCALE, DM3_UNITS);

    d    = parser.importDM3(fp);
    img  = d.metadata.parserSpecific.imageData;

    assert(isa(img.pixels, 'uint16'),           'pixels should be uint16');
    assert(isequal(size(img.pixels), [DM3_H, DM3_W]), 'pixels size should be [H x W]');
    assert(isequal(img.pixels, DM3_PIXELS),     'pixel values should match original');

    nPass = nPass + 1;
    fprintf('  ✔ Test 13: importDM3 pixel value round-trip\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 13: %s\n', ME.message);
end

% ── Test 14: importDM3 — calibration ─────────────────────────────────
try
    fp = tempname_ext('.dm3');
    tmpFiles{end+1} = fp;

    writeSyntheticDM3(fp, DM3_PIXELS, DM3_SCALE, DM3_UNITS);

    d   = parser.importDM3(fp);
    img = d.metadata.parserSpecific.imageData;

    assert(img.calibrated,                      'calibrated should be true');
    assert(abs(img.pixelSize - DM3_SCALE) < 1e-9, 'pixelSize should be 2.5');
    assert(strcmp(img.pixelUnit, DM3_UNITS),    'pixelUnit should be "nm"');

    nPass = nPass + 1;
    fprintf('  ✔ Test 14: importDM3 calibration (pixelSize=%.4g %s)\n', ...
        img.pixelSize, img.pixelUnit);
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 14: %s\n', ME.message);
end

% ── Test 15: importAuto dispatches .dm3 → importDM3 ──────────────────
try
    fp = tempname_ext('.dm3');
    tmpFiles{end+1} = fp;

    writeSyntheticDM3(fp, DM3_PIXELS, DM3_SCALE, DM3_UNITS);

    [d, parserName] = parser.importAuto(fp);

    assert(strcmp(parserName, 'importDM3'),     'importAuto should dispatch to importDM3');
    assert(isstruct(d),                         'output must be struct');
    assert(d.metadata.parserSpecific.isImage,   'isImage should be true');

    nPass = nPass + 1;
    fprintf('  ✔ Test 15: importAuto dispatch .dm3 → importDM3\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 15: %s\n', ME.message);
end

% ── Test 16: resolveParser returns importDM3 for .dm3 and .dm4 ───────
try
    % .dm3
    fp3 = tempname_ext('.dm3');
    tmpFiles{end+1} = fp3;
    writeSyntheticDM3(fp3, DM3_PIXELS, DM3_SCALE, DM3_UNITS);

    res3 = parser.resolveParser(fp3);
    assert(strcmp(res3.name, 'importDM3'),      'resolveParser .dm3 should return importDM3');

    % .dm4 — write a minimal valid DM4 header so the file exists
    fp4 = tempname_ext('.dm4');
    tmpFiles{end+1} = fp4;
    writeSyntheticDM3(fp4, DM3_PIXELS, DM3_SCALE, DM3_UNITS);   % DM3 content accepted by resolveParser

    res4 = parser.resolveParser(fp4);
    assert(strcmp(res4.name, 'importDM3'),      'resolveParser .dm4 should return importDM3');

    nPass = nPass + 1;
    fprintf('  ✔ Test 16: resolveParser dispatches .dm3 and .dm4 → importDM3\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 16: %s\n', ME.message);
end

catch ME
    fprintf('  ✘ FATAL: %s\n', ME.message);
    nFail = nFail + 1;
end

% ── Cleanup temp files ────────────────────────────────────────────────
for k = 1:numel(tmpFiles)
    if isfile(tmpFiles{k})
        delete(tmpFiles{k});
    end
end

% ── Summary ──────────────────────────────────────────────────────────
fprintf('\n  Results: %d passed, %d failed\n', nPass, nFail);
fprintf('═══ test_em_parsers done ═══\n\n');
if nFail > 0
    error('test_em_parsers:failures', '%d test(s) failed.', nFail);
end


% ════════════════════════════════════════════════════════════════════
%  LOCAL HELPERS
% ════════════════════════════════════════════════════════════════════

function fp = tempname_ext(ext)
%TEMPNAME_EXT  Return a unique temp file path with the given extension.
    fp = [tempname, ext];
end


function writeBinaryImage(fp, pixels, precision)
%WRITEBINARYIMAGE  Write pixel matrix to a headerless binary file.
%   pixels is written in row-major order (each row contiguous).
    fid = fopen(fp, 'w', 'l');   % little-endian
    assert(fid ~= -1, 'Cannot create temp file: %s', fp);
    cleanObj = onCleanup(@() fclose(fid)); %#ok<NASGU>
    % fwrite writes column-major; transpose so rows are contiguous on disk
    fwrite(fid, pixels', precision);
end


function writeSyntheticDM3(fp, pixels, pixelScale, pixelUnits)
%WRITESYNTHETICDM3  Write a minimal but valid DM3 binary file for testing.
%
%   Creates a DM3 version-3 file (little-endian data) containing:
%     - A root tag group with an ImageList tag group
%     - ImageList.1 (index 1) with ImageData:
%         DataType = 10 (uint16)
%         Dimensions.0 = W, Dimensions.1 = H
%         Data = H*W uint16 pixels in row-major order
%         Calibrations.Dimension.0.Scale = pixelScale (double)
%         Calibrations.Dimension.0.Units = pixelUnits (string)
%         Calibrations.Dimension.1.Scale = pixelScale (double)
%         Calibrations.Dimension.1.Units = pixelUnits (string)
%
%   pixels  — [H x W] uint16 matrix
%   The file is written big-endian for structure, little-endian for data.

    H = size(pixels, 1);
    W = size(pixels, 2);

    fid = fopen(fp, 'w', 'b');   % big-endian for structural writes
    assert(fid ~= -1, 'Cannot create temp DM3 file: %s', fp);
    cleanFid = onCleanup(@() fclose(fid));

    % ── DM3 Header ───────────────────────────────────────────────────
    % Version (big-endian)
    fwrite(fid, uint32(3), 'uint32', 0, 'b');
    % Root tag directory size (placeholder — DM3 readers tolerate wrong value)
    fwrite(fid, uint32(0), 'uint32', 0, 'b');
    % Byte order: 1 = little-endian for data
    fwrite(fid, uint32(1), 'uint32', 0, 'b');

    % ── Root tag group: 1 child ("ImageList") ────────────────────────
    fwrite(fid, uint8(0), 'uint8');    % sorted
    fwrite(fid, uint8(0), 'uint8');    % open
    fwrite(fid, uint32(1), 'uint32', 0, 'b');  % nTags=1

    % ── Tag Group: ImageList (2 children: index 0 thumbnail stub, index 1 image) ──
    writeTagEntryHeader(fid, 20, 'ImageList');
    fwrite(fid, uint8(0), 'uint8');    % sorted
    fwrite(fid, uint8(0), 'uint8');    % open
    fwrite(fid, uint32(2), 'uint32', 0, 'b');  % nTags=2

    %  ── ImageList.0: thumbnail stub (DataType=23, no real data needed) ─
    writeTagEntryHeader(fid, 20, '0');
    fwrite(fid, uint8(0), 'uint8'); fwrite(fid, uint8(0), 'uint8');
    fwrite(fid, uint32(1), 'uint32', 0, 'b');  % 1 child
    % DataType = 23 (thumbnail) — just a uint32 scalar tag
    writeUint32TagData(fid, 'DataType', uint32(23));

    %  ── ImageList.1: real image ──────────────────────────────────────
    writeTagEntryHeader(fid, 20, '1');
    fwrite(fid, uint8(0), 'uint8'); fwrite(fid, uint8(0), 'uint8');
    fwrite(fid, uint32(1), 'uint32', 0, 'b');  % 1 child: ImageData

    %  ── ImageData ────────────────────────────────────────────────────
    writeTagEntryHeader(fid, 20, 'ImageData');
    fwrite(fid, uint8(0), 'uint8'); fwrite(fid, uint8(0), 'uint8');
    fwrite(fid, uint32(4), 'uint32', 0, 'b');  % 4 children: DataType, Dimensions, Calibrations, Data

    % DataType = 10 (uint16)
    writeUint32TagData(fid, 'DataType', uint32(10));

    % Dimensions (tag group with 2 scalar children: width=W, height=H)
    writeTagEntryHeader(fid, 20, 'Dimensions');
    fwrite(fid, uint8(0), 'uint8'); fwrite(fid, uint8(0), 'uint8');
    fwrite(fid, uint32(2), 'uint32', 0, 'b');
    writeUint32TagData(fid, '0', uint32(W));
    writeUint32TagData(fid, '1', uint32(H));

    % Calibrations (tag group with 1 child: Dimension)
    writeTagEntryHeader(fid, 20, 'Calibrations');
    fwrite(fid, uint8(0), 'uint8'); fwrite(fid, uint8(0), 'uint8');
    fwrite(fid, uint32(1), 'uint32', 0, 'b');

    % Calibrations.Dimension (tag group with 2 children: dim 0 and dim 1)
    writeTagEntryHeader(fid, 20, 'Dimension');
    fwrite(fid, uint8(0), 'uint8'); fwrite(fid, uint8(0), 'uint8');
    fwrite(fid, uint32(2), 'uint32', 0, 'b');

    % Calibrations.Dimension.0: Scale + Units
    writeTagEntryHeader(fid, 20, '0');
    fwrite(fid, uint8(0), 'uint8'); fwrite(fid, uint8(0), 'uint8');
    fwrite(fid, uint32(2), 'uint32', 0, 'b');
    writeScalarTagData(fid, 'Scale', pixelScale);
    writeStringTagData(fid, 'Units', pixelUnits);

    % Calibrations.Dimension.1: Scale + Units
    writeTagEntryHeader(fid, 20, '1');
    fwrite(fid, uint8(0), 'uint8'); fwrite(fid, uint8(0), 'uint8');
    fwrite(fid, uint32(2), 'uint32', 0, 'b');
    writeScalarTagData(fid, 'Scale', pixelScale);
    writeStringTagData(fid, 'Units', pixelUnits);

    % Data: array tag (type=20, elemType=4 (uint16), count=W*H)
    % Write using little-endian for the pixel payload
    nPx = W * H;
    writeTagEntryHeader(fid, 21, 'Data');
    % Delimiter %%%%
    fwrite(fid, uint8([0x25 0x25 0x25 0x25]), 'uint8');
    % Info array length = 3 (metaType=20, elemType=4, count)
    fwrite(fid, uint32(3), 'uint32', 0, 'b');
    % Info[0]=20 (array), Info[1]=4 (uint16), Info[2]=count
    fwrite(fid, uint32(20), 'uint32', 0, 'b');
    fwrite(fid, uint32(4),  'uint32', 0, 'b');
    fwrite(fid, uint32(nPx), 'uint32', 0, 'b');
    % Pixel data: row-major (X fastest), little-endian
    % pixels is [H x W]; DM row-major means write row by row → pixels'
    % But fwrite in 'b' mode; we want LE for data so temporarily switch fid
    % Approach: close and reopen in native, write, reopen in 'b'
    % Simpler: write with explicit byte swap if needed
    pixVec = uint16(pixels');    % [W*H] column-major = row-major of [H x W]' = correct
    pixVec = pixVec(:)';         % row vector
    % Write little-endian uint16: on any platform, byteswap if needed
    pixBytes = typecast(pixVec, 'uint8');
    % pixBytes is in native byte order; for LE we need LSB first
    % On Windows (LE), this is already correct. For portability, swap explicitly:
    if ~isLittleEndianHost()
        pixBytes = reshape(pixBytes, 2, []);
        pixBytes = pixBytes([2 1], :);
        pixBytes = pixBytes(:)';
    end
    fwrite(fid, pixBytes, 'uint8');
end


function writeTagEntryHeader(fid, typeCode, label)
%WRITETAGENTRYHEADER  Write type byte + 2-byte label length + label bytes.
    fwrite(fid, uint8(typeCode), 'uint8');
    labelBytes = uint8(label);
    fwrite(fid, uint16(numel(labelBytes)), 'uint16', 0, 'b');
    if ~isempty(labelBytes)
        fwrite(fid, labelBytes, 'uint8');
    end
end


function writeUint32TagData(fid, label, val)
%WRITEUINT32TAGDATA  Write a leaf tag containing a single uint32 scalar.
%   Info array: [5] (uint32 type code)
    writeTagEntryHeader(fid, 21, label);
    fwrite(fid, uint8([0x25 0x25 0x25 0x25]), 'uint8');  % delimiter
    fwrite(fid, uint32(1), 'uint32', 0, 'b');            % info length = 1
    fwrite(fid, uint32(5), 'uint32', 0, 'b');            % type 5 = uint32
    fwrite(fid, uint32(val), 'uint32', 0, 'l');          % value (LE for data)
end


function writeScalarTagData(fid, label, val)
%WRITESCALARTAGDATA  Write a leaf tag containing a float64 scalar.
%   Info array: [7] (float64 type code)
    writeTagEntryHeader(fid, 21, label);
    fwrite(fid, uint8([0x25 0x25 0x25 0x25]), 'uint8');
    fwrite(fid, uint32(1), 'uint32', 0, 'b');            % info length = 1
    fwrite(fid, uint32(7), 'uint32', 0, 'b');            % type 7 = float64
    fwrite(fid, double(val), 'float64', 0, 'l');         % value (LE for data)
end


function writeStringTagData(fid, label, str)
%WRITESTRINGTAGDATA  Write a leaf tag containing a UTF-16 string.
%   Info array: [18, charCount]
    writeTagEntryHeader(fid, 21, label);
    fwrite(fid, uint8([0x25 0x25 0x25 0x25]), 'uint8');
    nChars = numel(str);
    fwrite(fid, uint32(2), 'uint32', 0, 'b');            % info length = 2
    fwrite(fid, uint32(18), 'uint32', 0, 'b');           % type 18 = string
    fwrite(fid, uint32(nChars), 'uint32', 0, 'b');       % char count
    % Characters as uint16 LE
    fwrite(fid, uint16(str), 'uint16', 0, 'l');
end


function tf = isLittleEndianHost()
%ISLITTLEENDIANHOST  Return true if the host machine is little-endian.
    x = uint16(1);
    b = typecast(x, 'uint8');
    tf = (b(1) == 1);
end
