function data = importImage(filepath, options)
%IMPORTIMAGE  Import a common image file (JPEG, PNG, BMP, GIF) into the
%             unified toolbox data struct using MATLAB's built-in imread.
%
%   Syntax
%   ──────
%   data = parser.importImage(filepath)
%   data = parser.importImage(filepath, Name=Value)
%
%   Inputs
%   ──────
%   filepath   (1,1) string   Path to the image file (.jpg/.jpeg, .png,
%                             .bmp, or .gif).
%
%   Name-Value Options
%   ──────────────────
%   Verbose    logical   Print a summary after import (default: false).
%
%   Outputs
%   ───────
%   data   Struct produced by parser.createDataStruct with fields:
%            .time        [Hx1]  Row pixel indices 1..H (1-D fallback axis)
%            .values      [Hx1]  Mean intensity per row (grayscale) or
%                                mean luminance per row (RGB)
%            .labels      {'Mean Intensity'}
%            .units       {'counts'}
%            .metadata    Struct — see below
%
%   Metadata fields (data.metadata)
%   ────────────────────────────────
%   .source              Full file path
%   .importDate          datetime of import
%   .parserName          'importImage'
%   .parserVersion       '1.0'
%   .xColumnName         'Row'
%   .xColumnUnit         'px'
%   .parserSpecific
%     .isImage           true
%     .imageData
%       .pixels          [HxW] uint8/uint16/single, or [HxWx3] for RGB
%       .bitDepth        Per-channel bit depth (e.g. 8 for JPEG/PNG 8-bit;
%                        JPEG reports total bits — normalized by numChannels)
%       .height          H  (pixels)
%       .width           W  (pixels)
%       .numChannels     1 (grayscale) or 3 (RGB)
%       .numFrames       1 (common image formats carry a single frame)
%       .frames          {} (empty — single-frame formats only)
%       .pixelSize       NaN (no calibration metadata in JPEG/PNG/BMP/GIF)
%       .pixelUnit       '' (empty — no calibration)
%       .calibrated      false
%       .acquiParams     Struct of available imfinfo metadata fields
%
%   Note: JPEG stores BitDepth as total bits (e.g. 24 for 8-bit RGB).
%   This parser normalizes to per-channel bit depth via:
%       bitDepth = info.BitDepth / max(1, numChannels)
%
%   Examples
%   ────────
%   % Basic import
%   data = parser.importImage('photo.jpg');
%   img  = data.metadata.parserSpecific.imageData;
%   imagesc(img.pixels);  colormap gray;
%
%   % Check channel layout
%   img = data.metadata.parserSpecific.imageData;
%   fprintf('%dx%d px | %d-bit | %d channel(s)\n', ...
%       img.width, img.height, img.bitDepth, img.numChannels);
%
%   % Auto-dispatch
%   data = parser.importAuto('screenshot.png');
%
%   See also IMPORTTIFF, IMPORTDM3, IMPORTAUTO, CREATEDATASTRUCT

    arguments
        filepath (1,1) string {mustBeFile}
        options.Verbose (1,1) logical = false
    end

    % ════════════════════════════════════════════════════════════════
    %  STEP 1: Read file info (imfinfo) — lightweight, no pixel load
    % ════════════════════════════════════════════════════════════════
    try
        info = imfinfo(char(filepath));
    catch ME
        error('parser:importImage:infofail', ...
            'imfinfo failed for "%s": %s', filepath, ME.message);
    end

    W = info(1).Width;
    H = info(1).Height;

    % ════════════════════════════════════════════════════════════════
    %  STEP 2: Load pixel data
    % ════════════════════════════════════════════════════════════════
    try
        pixels = imread(char(filepath));
    catch ME
        error('parser:importImage:readfail', ...
            'imread failed for "%s": %s', filepath, ME.message);
    end

    numChannels = size(pixels, 3);   % 1 = grayscale, 3 = RGB

    % Normalize BitDepth to per-channel (JPEG reports total bits, e.g. 24 for 8-bit RGB)
    rawBitDepth = info(1).BitDepth;
    bitDepth    = rawBitDepth / max(1, numChannels);

    % ════════════════════════════════════════════════════════════════
    %  STEP 3: Extract available imfinfo metadata fields
    % ════════════════════════════════════════════════════════════════
    acquiParams = struct();

    stdFields = {'Format', 'FormatVersion', 'Compression', ...
                 'PhotometricInterpretation', 'DateTime', ...
                 'ImageDescription', 'XResolution', 'YResolution', ...
                 'ResolutionUnit', 'Software', 'Make', 'Model', ...
                 'ColorType', 'Comment'};
    for k = 1:numel(stdFields)
        f = stdFields{k};
        if isfield(info(1), f) && ~isempty(info(1).(f))
            acquiParams.(f) = info(1).(f);
        end
    end

    % ════════════════════════════════════════════════════════════════
    %  STEP 4: Build 1-D fallback (mean intensity per row)
    % ════════════════════════════════════════════════════════════════
    timeVec = (1:H)';

    if numChannels == 1
        pixFloat   = double(pixels);
        meanPerRow = mean(pixFloat, 2);   % [H x 1]
    else
        % RGB: luminance = 0.299 R + 0.587 G + 0.114 B
        pixFloat   = double(pixels);
        luminance  = 0.299 * pixFloat(:,:,1) + ...
                     0.587 * pixFloat(:,:,2) + ...
                     0.114 * pixFloat(:,:,3);
        meanPerRow = mean(luminance, 2);
    end

    % ════════════════════════════════════════════════════════════════
    %  STEP 5: Assemble metadata struct
    % ════════════════════════════════════════════════════════════════
    meta.source        = char(filepath);
    meta.importDate    = datetime('now');
    meta.parserName    = 'importImage';
    meta.parserVersion = '1.0';
    meta.xColumnName   = 'Row';
    meta.xColumnUnit   = 'px';

    imgData.pixels      = pixels;
    imgData.bitDepth    = bitDepth;
    imgData.height      = H;
    imgData.width       = W;
    imgData.numChannels = numChannels;
    imgData.numFrames   = 1;
    imgData.frames      = {};
    imgData.pixelSize   = NaN;
    imgData.pixelUnit   = '';
    imgData.calibrated  = false;
    imgData.acquiParams = acquiParams;

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
        fprintf('importImage: %dx%d px | %d-bit/ch | %d channel(s)\n', ...
            W, H, bitDepth, numChannels);
    end
end
