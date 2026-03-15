function data = importRawImage(filepath, options)
%IMPORTRAWIMAGE  Import a headerless binary image file into the unified data struct.
%
%   Syntax
%   ──────
%   data = parser.importRawImage(filepath, Width=W, Height=H)
%   data = parser.importRawImage(filepath, Width=W, Height=H, BitDepth=16)
%   data = parser.importRawImage(filepath, Width=W, Height=H, ByteOrder='big-endian')
%
%   Headerless binary files contain raw pixel data with no embedded
%   dimension or type information. The caller MUST supply Width, Height,
%   and BitDepth (or accept the 16-bit default) to parse the file
%   correctly.
%
%   Inputs
%   ──────
%   filepath   (1,1) string   Path to the binary image file.
%
%   Name-Value Options (required unless noted)
%   ──────────────────
%   Width      (1,1) double   Image width in pixels.    [REQUIRED]
%   Height     (1,1) double   Image height in pixels.   [REQUIRED]
%   BitDepth   (1,1) double   Bits per pixel: 8, 16, or 32 (float32).
%                             Default: 16.
%   ByteOrder  (1,1) string   'little-endian' (default) or 'big-endian'.
%
%   Outputs
%   ───────
%   data   Struct produced by parser.createDataStruct with fields:
%            .time        [Hx1]  Row pixel indices 1..H (1-D fallback axis)
%            .values      [Hx1]  Mean intensity per row
%            .labels      {'Mean Intensity'}
%            .units       {'counts'}
%            .metadata    Struct — see below
%
%   Metadata fields (data.metadata)
%   ────────────────────────────────
%   .source              Full file path
%   .importDate          datetime of import
%   .parserName          'importRawImage'
%   .parserVersion       '1.0'
%   .xColumnName         'Row'
%   .xColumnUnit         'px'
%   .parserSpecific
%     .isImage           true
%     .imageData
%       .pixels          [HxW] numeric array (uint8 / uint16 / single)
%       .bitDepth        8, 16, or 32
%       .height          H  (pixels)
%       .width           W  (pixels)
%       .numChannels     1  (always grayscale for headerless RAW)
%       .numFrames       1
%       .frames          {}  (empty — single frame)
%       .pixelSize       NaN (no calibration data in headerless files)
%       .pixelUnit       ''
%       .calibrated      false
%       .acquiParams     struct('byteOrder', <ByteOrder>, 'bitDepth', <BitDepth>)
%
%   Errors
%   ──────
%   Throws parser:importRawImage:sizeMismatch when the file size does not
%   equal Width * Height * bytesPerPixel.
%
%   Examples
%   ────────
%   % Load a 512x512 16-bit RAW file
%   data = parser.importRawImage('capture.raw', Width=512, Height=512);
%   img  = data.metadata.parserSpecific.imageData.pixels;
%   imagesc(img);  colormap gray;
%
%   % 8-bit big-endian
%   data = parser.importRawImage('scan.raw', Width=1024, Height=768, ...
%                                BitDepth=8, ByteOrder='big-endian');
%
%   % 32-bit float
%   data = parser.importRawImage('float.raw', Width=256, Height=256, BitDepth=32);
%
%   See also IMPORTTIFF, IMPORTAUTO, CREATEDATASTRUCT

    arguments
        filepath           (1,1) string {mustBeFile}
        options.Width      (1,1) double {mustBePositive, mustBeInteger}
        options.Height     (1,1) double {mustBePositive, mustBeInteger}
        options.BitDepth   (1,1) double = 16
        options.ByteOrder  (1,1) string = "little-endian"
        options.Verbose    (1,1) logical = false
    end

    if ~ismember(options.BitDepth, [8 16 32])
        error('parser:importRawImage:badBitDepth', ...
            'BitDepth must be 8, 16, or 32; got %g.', options.BitDepth);
    end

    W        = options.Width;
    H        = options.Height;
    bitDepth = options.BitDepth;

    % Validate byte-order string
    byteOrder = lower(char(options.ByteOrder));
    if ~ismember(byteOrder, {'little-endian', 'big-endian'})
        error('parser:importRawImage:badByteOrder', ...
            'ByteOrder must be ''little-endian'' or ''big-endian''; got "%s".', byteOrder);
    end

    % ════════════════════════════════════════════════════════════════
    %  STEP 1: Determine expected file size and precision string
    % ════════════════════════════════════════════════════════════════
    switch bitDepth
        case 8
            precision      = 'uint8';
            bytesPerPixel  = 1;
        case 16
            precision      = 'uint16';
            bytesPerPixel  = 2;
        case 32
            precision      = 'single';
            bytesPerPixel  = 4;
    end

    expectedBytes = W * H * bytesPerPixel;

    % ════════════════════════════════════════════════════════════════
    %  STEP 2: Verify file size
    % ════════════════════════════════════════════════════════════════
    fileInfo = dir(char(filepath));
    if isempty(fileInfo)
        error('parser:importRawImage:notFound', ...
            'File not found: %s', filepath);
    end
    actualBytes = fileInfo.bytes;

    if actualBytes ~= expectedBytes
        error('parser:importRawImage:sizeMismatch', ...
            ['File size mismatch for "%s".\n' ...
             '  Expected: %d bytes  (%dx%d px, %d-bit = %d bytes/px)\n' ...
             '  Actual  : %d bytes\n' ...
             'Check Width, Height, and BitDepth arguments.'], ...
            filepath, expectedBytes, W, H, bitDepth, bytesPerPixel, actualBytes);
    end

    % ════════════════════════════════════════════════════════════════
    %  STEP 3: Read pixel data
    % ════════════════════════════════════════════════════════════════
    if strcmp(byteOrder, 'little-endian')
        machineFormat = 'l';
    else
        machineFormat = 'b';
    end

    fid = fopen(char(filepath), 'r', machineFormat);
    if fid == -1
        error('parser:importRawImage:openFail', ...
            'Cannot open file for reading: %s', filepath);
    end
    cleanObj = onCleanup(@() fclose(fid)); %#ok<NASGU>

    rawVec = fread(fid, W * H, ['*' precision]);

    if numel(rawVec) ~= W * H
        error('parser:importRawImage:readFail', ...
            'Expected %d pixels but read %d from "%s".', W * H, numel(rawVec), filepath);
    end

    % Reshape to [H x W] (row-major: each row of pixels is contiguous)
    pixels = reshape(rawVec, [W, H])';   % transpose: fread is column-major

    % ════════════════════════════════════════════════════════════════
    %  STEP 4: Build 1-D fallback (mean intensity per row)
    % ════════════════════════════════════════════════════════════════
    timeVec    = (1:H)';
    meanPerRow = mean(double(pixels), 2);   % [H x 1]

    % ════════════════════════════════════════════════════════════════
    %  STEP 5: Assemble metadata struct
    % ════════════════════════════════════════════════════════════════
    meta.source        = char(filepath);
    meta.importDate    = datetime('now');
    meta.parserName    = 'importRawImage';
    meta.parserVersion = '1.0';
    meta.xColumnName   = 'Row';
    meta.xColumnUnit   = 'px';

    imgData.pixels      = pixels;
    imgData.bitDepth    = bitDepth;
    imgData.height      = H;
    imgData.width       = W;
    imgData.numChannels = 1;
    imgData.numFrames   = 1;
    imgData.frames      = {};
    imgData.pixelSize   = NaN;
    imgData.pixelUnit   = '';
    imgData.calibrated  = false;
    imgData.acquiParams = struct('byteOrder', byteOrder, 'bitDepth', bitDepth);

    meta.parserSpecific.isImage   = true;
    meta.parserSpecific.imageData = imgData;

    % ════════════════════════════════════════════════════════════════
    %  STEP 6: Build unified struct
    % ════════════════════════════════════════════════════════════════
    data = parser.createDataStruct(timeVec, meanPerRow, ...
        'labels',   {'Mean Intensity'}, ...
        'units',    {'counts'}, ...
        'metadata', meta);

    if options.Verbose
        fprintf('importRawImage: %dx%d px | %d-bit | %s | %d bytes\n', ...
            W, H, bitDepth, byteOrder, actualBytes);
    end
end
