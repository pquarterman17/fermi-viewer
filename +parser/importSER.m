function data = importSER(filePath)
%IMPORTSER  Import an FEI/ThermoFisher TIA SER binary image file.
%
%   Syntax
%   ──────
%   data = parser.importSER(filePath)
%
%   Inputs
%   ──────
%   filePath   (1,1) string   Path to the .ser file.
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
%   .parserName          'importSER'
%   .parserVersion       '1.0'
%   .xColumnName         'Row'
%   .xColumnUnit         'px'
%   .parserSpecific
%     .isImage           true
%     .imageData
%       .pixels          [HxW] numeric array (class matches DataType)
%       .bitDepth        Bit depth derived from DataType field
%       .height          H  (pixels)
%       .width           W  (pixels)
%       .numChannels     1
%       .pixelSize       Physical size of one pixel in X (NaN if uncalibrated)
%       .pixelUnit       'm' (raw SER unit) or '' if uncalibrated
%       .calibrated      logical — true when CalibrationDelta > 0
%       .serInfo         Struct of raw header fields
%
%   Format notes
%   ────────────
%   SER is a little-endian binary format produced by FEI/ThermoFisher TIA.
%   This parser handles DataTypeID 0x4122 (2D image) only.  The first valid
%   element is read.  1D spectrum files (DataTypeID 0x4120) are not supported.
%
%   DataType mapping:
%     1=uint8, 2=uint16, 3=uint32, 4=int8, 5=int16, 6=int32,
%     7=float32, 8=float64
%
%   Examples
%   ────────
%   data = parser.importSER('image.ser');
%   img  = data.metadata.parserSpecific.imageData;
%   imagesc(img.pixels);  colormap gray;
%
%   if img.calibrated
%       fprintf('Pixel size: %.4g %s\n', img.pixelSize, img.pixelUnit);
%   end
%
%   See also IMPORTTIFF, IMPORTDM3, IMPORTAUTO, CREATEDATASTRUCT

    arguments
        filePath (1,1) string {mustBeFile}
    end

    % ════════════════════════════════════════════════════════════════
    %  STEP 1: Open file
    % ════════════════════════════════════════════════════════════════
    fid = fopen(char(filePath), 'r', 'ieee-le');
    if fid == -1
        error('parser:importSER:openFailed', ...
            'Cannot open file: "%s"', filePath);
    end
    cleanObj = onCleanup(@() fclose(fid));

    % ════════════════════════════════════════════════════════════════
    %  STEP 2: Read fixed-length header (bytes 0-29, 30 bytes total)
    % ════════════════════════════════════════════════════════════════
    byteOrder        = fread(fid, 1, 'uint16');   % 0x4949 = little-endian
    seriesID         = fread(fid, 1, 'uint16');   % 0x0197 expected
    seriesVersion    = fread(fid, 1, 'uint16');   % 0x0210 or 0x0220
    dataTypeID       = fread(fid, 1, 'uint32');
    tagTypeID        = fread(fid, 1, 'uint32');
    totalElements    = fread(fid, 1, 'uint32');
    validElements    = fread(fid, 1, 'uint32');
    % Version >= 0x0220 uses 64-bit offsets; older versions use 32-bit
    if seriesVersion >= hex2dec('0220')
        offsetArrayOffset = fread(fid, 1, 'uint64');
    else
        offsetArrayOffset = fread(fid, 1, 'uint32');
    end
    numDimensions    = fread(fid, 1, 'uint32');

    % Validate magic
    if byteOrder ~= hex2dec('4949')
        error('parser:importSER:badByteOrder', ...
            '"%s" does not appear to be a little-endian SER file (ByteOrder=0x%04X).', ...
            filePath, byteOrder);
    end
    if seriesID ~= hex2dec('0197')
        error('parser:importSER:badSeriesID', ...
            '"%s" does not appear to be a valid SER file (SeriesID=0x%04X).', ...
            filePath, seriesID);
    end

    % Only 2D images are supported
    if dataTypeID ~= hex2dec('4122')
        if dataTypeID == hex2dec('4120')
            error('parser:importSER:notAnImage', ...
                '"%s" is a 1D spectrum SER file (DataTypeID=0x4120). Only 2D images are supported.', ...
                filePath);
        else
            error('parser:importSER:unknownDataType', ...
                '"%s" has an unrecognised DataTypeID (0x%08X). Only 2D images (0x4122) are supported.', ...
                filePath, dataTypeID);
        end
    end

    if validElements < 1
        error('parser:importSER:noElements', ...
            '"%s" contains no valid data elements.', filePath);
    end

    % ════════════════════════════════════════════════════════════════
    %  STEP 3: Read offset to the first data element
    % ════════════════════════════════════════════════════════════════
    % offsetArrayOffset points to an array of offsets, one per element.
    % Version >= 0x0220 uses uint64 offsets; older uses uint32.
    fseek(fid, offsetArrayOffset, 'bof');
    if seriesVersion >= hex2dec('0220')
        dataOffset = fread(fid, 1, 'uint64');
    else
        dataOffset = fread(fid, 1, 'uint32');
    end

    % ════════════════════════════════════════════════════════════════
    %  STEP 4: Read element header (calibration + array dimensions)
    % ════════════════════════════════════════════════════════════════
    fseek(fid, dataOffset, 'bof');

    % X calibration: offset(f64) + delta(f64) + calElement(i32)
    calOffsetX  = fread(fid, 1, 'float64');
    calDeltaX   = fread(fid, 1, 'float64');
    calElementX = fread(fid, 1, 'int32'); %#ok<NASGU>

    % Y calibration: offset(f64) + delta(f64) + calElement(i32)
    calOffsetY  = fread(fid, 1, 'float64'); %#ok<NASGU>
    calDeltaY   = fread(fid, 1, 'float64'); %#ok<NASGU>
    calElementY = fread(fid, 1, 'int32'); %#ok<NASGU>

    % Array dimensions
    arrayDataType = fread(fid, 1, 'int16');
    arraySizeX    = fread(fid, 1, 'int32');
    arraySizeY    = fread(fid, 1, 'int32');

    W = arraySizeX;
    H = arraySizeY;

    if W <= 0 || H <= 0
        error('parser:importSER:badDimensions', ...
            '"%s" reports invalid image dimensions: %dx%d.', filePath, W, H);
    end

    % ════════════════════════════════════════════════════════════════
    %  STEP 5: Map DataType → MATLAB precision string + bit depth
    % ════════════════════════════════════════════════════════════════
    [precStr, bitDepth] = serDataTypeToPrec(arrayDataType);

    % ════════════════════════════════════════════════════════════════
    %  STEP 6: Read pixel data
    % ════════════════════════════════════════════════════════════════
    nPixels = W * H;
    rawPix  = fread(fid, nPixels, ['*' precStr]);

    if numel(rawPix) < nPixels
        warning('parser:importSER:shortRead', ...
            '"%s": expected %d pixels but only read %d. File may be truncated.', ...
            filePath, nPixels, numel(rawPix));
        rawPix(end+1 : nPixels) = 0;
    end

    % SER stores data column-major (X fast, Y slow) — reshape to [H x W]
    pixels = reshape(rawPix, [W, H])';   % transpose: W×H → H×W

    % ════════════════════════════════════════════════════════════════
    %  STEP 7: Determine calibration
    % ════════════════════════════════════════════════════════════════
    calibrated = (calDeltaX ~= 0);
    if calibrated
        pixelSize = abs(calDeltaX);
        pixelUnit = 'm';   % SER stores in SI units (metres)
    else
        pixelSize = NaN;
        pixelUnit = '';
    end

    % ════════════════════════════════════════════════════════════════
    %  STEP 8: Build 1-D fallback (mean intensity per row)
    % ════════════════════════════════════════════════════════════════
    timeVec    = (1:H)';
    meanPerRow = mean(double(pixels), 2);

    % ════════════════════════════════════════════════════════════════
    %  STEP 9: Assemble metadata
    % ════════════════════════════════════════════════════════════════
    serInfo.byteOrder         = byteOrder;
    serInfo.seriesID          = seriesID;
    serInfo.seriesVersion     = seriesVersion;
    serInfo.dataTypeID        = dataTypeID;
    serInfo.tagTypeID         = tagTypeID;
    serInfo.totalElements     = totalElements;
    serInfo.validElements     = validElements;
    serInfo.numDimensions     = numDimensions;
    serInfo.calOffsetX        = calOffsetX;
    serInfo.calDeltaX         = calDeltaX;
    serInfo.calElementX       = calElementX;
    serInfo.calOffsetY        = calOffsetY;
    serInfo.calDeltaY         = calDeltaY;
    serInfo.calElementY       = calElementY;
    serInfo.arrayDataType     = arrayDataType;

    imgData.pixels      = pixels;
    imgData.bitDepth    = bitDepth;
    imgData.height      = H;
    imgData.width       = W;
    imgData.numChannels = 1;
    imgData.pixelSize   = pixelSize;
    imgData.pixelUnit   = pixelUnit;
    imgData.calibrated  = calibrated;
    imgData.serInfo     = serInfo;

    meta.source        = char(filePath);
    meta.importDate    = datetime('now');
    meta.parserName    = 'importSER';
    meta.parserVersion = '1.0';
    meta.xColumnName   = 'Row';
    meta.xColumnUnit   = 'px';

    meta.parserSpecific.isImage   = true;
    meta.parserSpecific.imageData = imgData;

    % ════════════════════════════════════════════════════════════════
    %  STEP 10: Build unified struct
    % ════════════════════════════════════════════════════════════════
    data = parser.createDataStruct(timeVec, meanPerRow, ...
        'labels',   {'Mean Intensity'}, ...
        'units',    {'counts'}, ...
        'metadata', meta);
end


% ════════════════════════════════════════════════════════════════════
%  LOCAL HELPER FUNCTIONS
% ════════════════════════════════════════════════════════════════════

function [precStr, bitDepth] = serDataTypeToPrec(dataType)
%SERDATATYPETOPREC  Map SER integer DataType code to fread precision + bit depth.
%
%   DataType codes:
%     1 = uint8,  2 = uint16, 3 = uint32,
%     4 = int8,   5 = int16,  6 = int32,
%     7 = float32 (single),   8 = float64 (double)
    switch dataType
        case 1
            precStr  = 'uint8';
            bitDepth = 8;
        case 2
            precStr  = 'uint16';
            bitDepth = 16;
        case 3
            precStr  = 'uint32';
            bitDepth = 32;
        case 4
            precStr  = 'int8';
            bitDepth = 8;
        case 5
            precStr  = 'int16';
            bitDepth = 16;
        case 6
            precStr  = 'int32';
            bitDepth = 32;
        case 7
            precStr  = 'single';
            bitDepth = 32;
        case 8
            precStr  = 'double';
            bitDepth = 64;
        otherwise
            error('parser:importSER:unknownDataTypecode', ...
                'Unrecognised SER DataType code: %d. Expected 1-8.', dataType);
    end
end
