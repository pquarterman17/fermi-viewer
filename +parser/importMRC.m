function data = importMRC(filePath)
%IMPORTMRC  Import an MRC2014 electron microscopy image file.
%
%   Syntax
%   ──────
%   data = parser.importMRC(filePath)
%
%   Inputs
%   ──────
%   filePath   (1,1) string   Path to the .mrc or .mrcs file.
%
%   Outputs
%   ───────
%   data   Struct produced by parser.createDataStruct with fields:
%            .time        [Hx1]  Row pixel indices 1..H (1-D fallback axis)
%            .values      [Hx1]  Mean intensity per row (first section)
%            .labels      {'Mean Intensity'}
%            .units       {'counts'}
%            .metadata    Struct — see below
%
%   Metadata fields (data.metadata)
%   ────────────────────────────────
%   .source              Full file path
%   .importDate          datetime of import
%   .parserName          'importMRC'
%   .parserVersion       '1.0'
%   .xColumnName         'Row'
%   .xColumnUnit         'px'
%   .parserSpecific
%     .isImage           true
%     .imageData
%       .pixels          [HxW] numeric array of the first section
%       .bitDepth        Bit depth derived from MODE field
%       .height          H = NY (rows)
%       .width           W = NX (columns)
%       .numChannels     1
%       .numSections     NZ (total z-sections in file)
%       .pixelSize       Pixel size in Angstroms (NaN if CELLA_X==0 or NX==0)
%       .pixelUnit       'A' (Angstroms) or '' if uncalibrated
%       .calibrated      logical
%       .mrcHeader       Struct of raw header fields
%
%   Format notes
%   ────────────
%   MRC2014 uses a 1024-byte fixed header followed by an optional extended
%   header of NSYMBT bytes, then raw pixel data.  All values are
%   little-endian.  Supported MODE values:
%     0 = int8,  1 = int16,  2 = float32,  6 = uint16
%
%   Pixel size is computed as CELLA_X / NX (Angstroms per pixel).
%   The MAP stamp ('MAP ') is validated when present; files without a stamp
%   are still parsed (older CCP4 variants omit it).
%
%   Only the first section (z=1) is read as the primary image.
%
%   Examples
%   ────────
%   data = parser.importMRC('tomogram.mrc');
%   img  = data.metadata.parserSpecific.imageData;
%   imagesc(img.pixels);  colormap gray;
%
%   fprintf('%d sections in file\n', img.numSections);
%   if img.calibrated
%       fprintf('Pixel size: %.4g %s\n', img.pixelSize, img.pixelUnit);
%   end
%
%   See also IMPORTTIFF, IMPORTDM3, IMPORTSER, IMPORTAUTO, CREATEDATASTRUCT

    arguments
        filePath (1,1) string {mustBeFile}
    end

    % ════════════════════════════════════════════════════════════════
    %  STEP 1: Open file
    % ════════════════════════════════════════════════════════════════
    fid = fopen(char(filePath), 'r', 'ieee-le');
    if fid == -1
        error('parser:importMRC:openFailed', ...
            'Cannot open file: "%s"', filePath);
    end
    cleanObj = onCleanup(@() fclose(fid));

    % ════════════════════════════════════════════════════════════════
    %  STEP 2: Read 1024-byte header
    % ════════════════════════════════════════════════════════════════
    % Bytes 0-3:   NX  (int32) — number of columns
    % Bytes 4-7:   NY  (int32) — number of rows
    % Bytes 8-11:  NZ  (int32) — number of sections
    % Bytes 12-15: MODE (int32)
    % Bytes 40-51: CELLA (3x float32) — cell dimensions in Angstroms
    % Bytes 196-199: MAP  (char[4])
    % Bytes 200-203: MACHST (uint8[4])
    % Bytes 208-211: NSYMBT (int32) — bytes of extended header

    NX   = fread(fid, 1, 'int32');
    NY   = fread(fid, 1, 'int32');
    NZ   = fread(fid, 1, 'int32');
    MODE = fread(fid, 1, 'int32');

    % Validate basic dimensions
    if NX <= 0 || NY <= 0
        error('parser:importMRC:badDimensions', ...
            '"%s" reports invalid dimensions: NX=%d NY=%d.', filePath, NX, NY);
    end
    if NZ < 1
        NZ = 1;
    end

    % Skip bytes 16-39 (NXSTART, NYSTART, NZSTART, MX, MY, MZ = 6x int32)
    fseek(fid, 16, 'bof');
    fread(fid, 6, 'int32');   % NXSTART..MZ (positions 16-39)

    % CELLA: bytes 40-51 (3 x float32)
    cella = fread(fid, 3, 'float32');   % [Angstroms] X, Y, Z cell dimensions

    % Skip to byte 196 for MAP stamp
    fseek(fid, 196, 'bof');
    mapBytes = fread(fid, 4, '*uint8');
    mapStamp = char(mapBytes');

    % Validate MAP stamp if present (some older CCP4 files omit it)
    if ~isempty(mapStamp) && ~strcmp(mapStamp, 'MAP ')
        % Warn but continue — older files may lack the stamp
        warning('parser:importMRC:noMapStamp', ...
            '"%s": MAP field is "%s" instead of "MAP ". File may not be MRC2014 compliant.', ...
            filePath, mapStamp);
    end

    % MACHST: bytes 200-203 (not used for parsing, store in header)
    machst = fread(fid, 4, '*uint8');

    % Skip to byte 208 for NSYMBT
    fseek(fid, 208, 'bof');
    NSYMBT = fread(fid, 1, 'int32');
    if NSYMBT < 0
        NSYMBT = 0;
    end

    % ════════════════════════════════════════════════════════════════
    %  STEP 3: Map MODE → precision string + bit depth
    % ════════════════════════════════════════════════════════════════
    [precStr, bitDepth] = mrcModeToPrec(MODE);

    % ════════════════════════════════════════════════════════════════
    %  STEP 4: Seek to data and read first section
    % ════════════════════════════════════════════════════════════════
    dataStart = 1024 + NSYMBT;
    fseek(fid, dataStart, 'bof');

    nPixels = NX * NY;
    rawPix  = fread(fid, nPixels, ['*' precStr]);

    if numel(rawPix) < nPixels
        warning('parser:importMRC:shortRead', ...
            '"%s": expected %d pixels but only read %d. File may be truncated.', ...
            filePath, nPixels, numel(rawPix));
        rawPix(end+1 : nPixels) = 0;
    end

    % MRC is column-major (X fast): reshape to [NY x NX]
    pixels = reshape(rawPix, [NX, NY])';   % NX×NY → NY×NX = H×W

    W = NX;
    H = NY;

    % ════════════════════════════════════════════════════════════════
    %  STEP 5: Determine pixel size from CELLA_X / NX
    % ════════════════════════════════════════════════════════════════
    if cella(1) > 0 && NX > 0
        pixelSize  = cella(1) / NX;   % Angstroms per pixel
        pixelUnit  = 'A';
        calibrated = true;
    else
        pixelSize  = NaN;
        pixelUnit  = '';
        calibrated = false;
    end

    % ════════════════════════════════════════════════════════════════
    %  STEP 6: Build 1-D fallback (mean intensity per row)
    % ════════════════════════════════════════════════════════════════
    timeVec    = (1:H)';
    meanPerRow = mean(double(pixels), 2);

    % ════════════════════════════════════════════════════════════════
    %  STEP 7: Assemble metadata
    % ════════════════════════════════════════════════════════════════
    mrcHeader.NX      = NX;
    mrcHeader.NY      = NY;
    mrcHeader.NZ      = NZ;
    mrcHeader.MODE    = MODE;
    mrcHeader.cellaX  = cella(1);
    mrcHeader.cellaY  = cella(2);
    mrcHeader.cellaZ  = cella(3);
    mrcHeader.mapStamp = mapStamp;
    mrcHeader.machst  = machst;
    mrcHeader.NSYMBT  = NSYMBT;

    imgData.pixels      = pixels;
    imgData.bitDepth    = bitDepth;
    imgData.height      = H;
    imgData.width       = W;
    imgData.numChannels = 1;
    imgData.numSections = NZ;
    imgData.numFrames   = max(NZ, 1);
    imgData.frames      = {};
    imgData.pixelSize   = pixelSize;
    imgData.pixelUnit   = pixelUnit;
    imgData.calibrated  = calibrated;
    imgData.acquiParams = mrcHeader;
    imgData.mrcHeader   = mrcHeader;

    meta.source        = char(filePath);
    meta.importDate    = datetime('now');
    meta.parserName    = 'importMRC';
    meta.parserVersion = '1.0';
    meta.xColumnName   = 'Row';
    meta.xColumnUnit   = 'px';

    meta.parserSpecific.isImage   = true;
    meta.parserSpecific.imageData = imgData;

    % ════════════════════════════════════════════════════════════════
    %  STEP 8: Build unified struct
    % ════════════════════════════════════════════════════════════════
    data = parser.createDataStruct(timeVec, meanPerRow, ...
        'labels',   {'Mean Intensity'}, ...
        'units',    {'counts'}, ...
        'metadata', meta);
end


% ════════════════════════════════════════════════════════════════════
%  LOCAL HELPER FUNCTIONS
% ════════════════════════════════════════════════════════════════════

function [precStr, bitDepth] = mrcModeToPrec(mode)
%MRCMODETOPREC  Map MRC MODE integer to fread precision string + bit depth.
%
%   Supported MODE values (MRC2014 standard):
%     0 = int8   (signed byte)
%     1 = int16  (signed short)
%     2 = float32
%     6 = uint16 (unsigned short)
    switch mode
        case 0
            precStr  = 'int8';
            bitDepth = 8;
        case 1
            precStr  = 'int16';
            bitDepth = 16;
        case 2
            precStr  = 'single';
            bitDepth = 32;
        case 6
            precStr  = 'uint16';
            bitDepth = 16;
        otherwise
            error('parser:importMRC:unsupportedMode', ...
                'Unsupported MRC MODE=%d. Supported: 0 (int8), 1 (int16), 2 (float32), 6 (uint16).', mode);
    end
end
