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
%   Two element kinds are handled (mirrors the fermiviewer Python port):
%     0x4122 (2D image)    — first valid element imported; a multi-frame
%                            series warns and drops later frames.
%     0x4120 (1D spectra)  — a single element becomes a spectrum struct
%                            (.time = energy axis in eV, .values = counts);
%                            a scanned series (line profile / map) becomes a
%                            spectral cube in metadata.parserSpecific.edsData
%                            (same contract as importBCF, so the FermiViewer
%                            Spectrum Image workshop opens it) plus a
%                            synthesized total-counts survey image.
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

    % Validate magic. isempty guard FIRST: fread on an empty/truncated
    % file returns [], and `[] ~= 0x4949` is [] (falsey) — every magic
    % check below would silently fall through until `W <= 0 || H <= 0`
    % crashes with a cryptic MATLAB:nonLogicalConditional.
    if isempty(byteOrder) || byteOrder ~= hex2dec('4949')
        error('parser:importSER:badByteOrder', ...
            '"%s" does not appear to be a little-endian SER file (empty or ByteOrder=%s).', ...
            filePath, mat2str(byteOrder));
    end
    if seriesID ~= hex2dec('0197')
        error('parser:importSER:badSeriesID', ...
            '"%s" does not appear to be a valid SER file (SeriesID=0x%04X).', ...
            filePath, seriesID);
    end

    if validElements < 1
        error('parser:importSER:noElements', ...
            '"%s" contains no valid data elements.', filePath);
    end

    % Element-kind dispatch: 2D images (0x4122) below; 1D spectra /
    % spectrum images (0x4120) via the spectrum-series path.
    if dataTypeID == hex2dec('4120')
        serInfo = struct('byteOrder', byteOrder, 'seriesID', seriesID, ...
            'seriesVersion', seriesVersion, 'dataTypeID', dataTypeID, ...
            'tagTypeID', tagTypeID, 'totalElements', totalElements, ...
            'validElements', validElements, 'numDimensions', numDimensions);
        data = importSpectrumSeries(fid, filePath, seriesVersion, ...
            offsetArrayOffset, numDimensions, validElements, serInfo);
        return;
    elseif dataTypeID ~= hex2dec('4122')
        error('parser:importSER:unknownDataType', ...
            '"%s" has an unrecognised DataTypeID (0x%08X). Supported: 2D images (0x4122) and 1D spectra (0x4120).', ...
            filePath, dataTypeID);
    end

    % Multi-frame image series: the unified struct has no image-stack kind,
    % so only the first frame is imported — say so instead of silence.
    if validElements > 1
        warning('parser:importSER:multiFrame', ...
            '"%s" holds %d image frames; only the first is imported.', ...
            filePath, validElements);
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
    calElementX = fread(fid, 1, 'int32');

    % Y calibration: offset(f64) + delta(f64) + calElement(i32)
    calOffsetY  = fread(fid, 1, 'float64');
    calDeltaY   = fread(fid, 1, 'float64');
    calElementY = fread(fid, 1, 'int32');

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
    meta.parserVersion = '1.1';   % +0x4120 spectra, multi-frame warning
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

function data = importSpectrumSeries(fid, filePath, seriesVersion, ...
    offsetArrayOffset, numDimensions, validElements, serInfo)
%IMPORTSPECTRUMSERIES  0x4120 elements: single spectrum or scanned series.
%   Ports the Python fermiviewer ser.py spectrum path. A single element
%   becomes a 1-D spectrum struct (.time = energy axis); a scanned series
%   (line profile or 2-D map) becomes a spectral cube published through
%   metadata.parserSpecific.edsData — the same contract parser.importBCF
%   uses — with a synthesized total-counts survey image so the entry
%   displays normally and the Spectrum Image workshop can open it.

    % ── Dimension array (file cursor sits at its start) ──────────────
    dims        = zeros(1, numDimensions);
    dimCalDelta = NaN;
    for d = 1:numDimensions
        sz = fread(fid, 1, 'int32');
        if isempty(sz), break; end
        dims(d) = sz;
        fread(fid, 1, 'float64');                     % dim cal offset
        delta = fread(fid, 1, 'float64');             % dim cal delta
        fread(fid, 1, 'int32');                       % dim cal element
        if d == 1 && ~isempty(delta), dimCalDelta = delta; end
        descLen = fread(fid, 1, 'uint32');
        if ~isempty(descLen) && descLen > 0, fseek(fid, descLen, 'cof'); end
        unitLen = fread(fid, 1, 'uint32');
        if ~isempty(unitLen) && unitLen > 0, fseek(fid, unitLen, 'cof'); end
    end

    % ── Element data offsets ─────────────────────────────────────────
    fseek(fid, offsetArrayOffset, 'bof');
    if seriesVersion >= hex2dec('0220')
        offsets = fread(fid, validElements, 'uint64');
    else
        offsets = fread(fid, validElements, 'uint32');
    end
    if isempty(offsets)
        error('parser:importSER:noElements', ...
            '"%s" contains no readable element offsets.', filePath);
    end

    % ── First element defines channel count + energy calibration ─────
    [spec1, calOff, calDel, calEl, dtCode, bitDepth] = ...
        readSpectrumElement(fid, offsets(1), filePath);
    nCh = numel(spec1);
    % SER 1-D calibration: value_i = calOffset + (i - calElement)*calDelta
    % with i zero-based. The element does not state units; eV is assumed
    % (TIA EELS/EDS convention — mirrors the Python port).
    energyAxis = calOff + ((0:nCh-1)' - calEl) * calDel;

    serInfo.calOffset         = calOff;
    serInfo.calDelta          = calDel;
    serInfo.calElement        = calEl;
    serInfo.arrayDataType     = dtCode;
    serInfo.energyUnitAssumed = 'eV';

    meta.source        = char(filePath);
    meta.importDate    = datetime('now');
    meta.parserName    = 'importSER';
    meta.parserVersion = '1.1';

    n = numel(offsets);
    if n == 1
        % Single spectrum → 1-D struct, no image payload (loads into the
        % viewer list the same way an EDS-only BCF does).
        meta.xColumnName = 'Energy';
        meta.xColumnUnit = 'eV';
        meta.parserSpecific.isImage = false;
        meta.parserSpecific.spectrumData = struct( ...
            'counts', double(spec1(:)), 'energyAxis', energyAxis, ...
            'bitDepth', bitDepth, 'serInfo', serInfo);
        data = parser.createDataStruct(energyAxis, double(spec1(:)), ...
            'labels', {'Counts'}, 'units', {'counts'}, 'metadata', meta);
        return;
    end

    % ── Scanned series → (ny x nx x nCh) cube ────────────────────────
    stack = zeros(n, nCh);
    stack(1, :) = double(spec1(:)).';
    for k = 2:n
        s = readSpectrumElement(fid, offsets(k), filePath);
        m = min(numel(s), nCh);
        stack(k, 1:m) = double(s(1:m)).';
    end

    posDims = dims(dims > 0);
    if numel(posDims) >= 2 && posDims(1) * posDims(2) == n
        ny = posDims(1);  nx = posDims(2);
    else
        ny = 1;  nx = n;              % line profile / unknown scan shape
    end
    % Element k maps to (y, x) row-major with x fastest — the file's scan
    % order, matching the Python port's C-order reshape.
    cube = permute(reshape(stack.', [nCh, nx, ny]), [3 2 1]);

    survey = sum(cube, 3);            % total-counts navigation map

    % Same field contract as parser.importBCF's edsData so the Spectrum
    % Image workshop (fermiViewer.spectrumImage.launch) opens SER maps
    % unmodified. The workshop labels energies in keV; convert from the
    % assumed eV.
    edsData.cube           = cube;
    edsData.cubeSize       = size(cube);
    edsData.cubeEnergyAxis = energyAxis / 1000;
    edsData.energyAxis     = energyAxis / 1000;
    edsData.sumSpectrum    = squeeze(sum(sum(cube, 1), 2));
    edsData.elements       = {};

    calibrated = ~isnan(dimCalDelta) && dimCalDelta ~= 0;
    if calibrated
        pixelSize = abs(dimCalDelta);
        pixelUnit = 'm';
    else
        pixelSize = NaN;
        pixelUnit = '';
    end

    imgData.pixels      = survey;
    imgData.bitDepth    = bitDepth;
    imgData.height      = ny;
    imgData.width       = nx;
    imgData.numChannels = 1;
    imgData.pixelSize   = pixelSize;
    imgData.pixelUnit   = pixelUnit;
    imgData.calibrated  = calibrated;
    imgData.serInfo     = serInfo;

    meta.xColumnName = 'Row';
    meta.xColumnUnit = 'px';
    meta.parserSpecific.isImage   = true;
    meta.parserSpecific.imageData = imgData;
    meta.parserSpecific.edsData   = edsData;

    data = parser.createDataStruct((1:ny)', mean(survey, 2), ...
        'labels', {'Mean Intensity'}, 'units', {'counts'}, 'metadata', meta);
end


function [vals, calOff, calDel, calEl, dtCode, bitDepth] = ...
    readSpectrumElement(fid, offset, filePath)
%READSPECTRUMELEMENT  One 0x4120 element: cal (f64, f64, i32), DataType
%   i16, length i32, then LENGTH values. Short reads zero-pad with a
%   warning — mirrors the image path's truncation handling.
    fseek(fid, offset, 'bof');
    calOff = fread(fid, 1, 'float64');
    calDel = fread(fid, 1, 'float64');
    calEl  = fread(fid, 1, 'int32');
    dtCode = fread(fid, 1, 'int16');
    len    = fread(fid, 1, 'int32');
    if isempty(len) || len <= 0
        error('parser:importSER:badSpectrumLength', ...
            '"%s": invalid SER spectrum length (%s).', filePath, mat2str(len));
    end
    [precStr, bitDepth] = serDataTypeToPrec(dtCode);
    vals = fread(fid, len, ['*' precStr]);
    if numel(vals) < len
        warning('parser:importSER:shortRead', ...
            '"%s": spectrum element truncated (%d of %d values); zero-padding.', ...
            filePath, numel(vals), len);
        vals(end+1 : len) = 0;
    end
end


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
