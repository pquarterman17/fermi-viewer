function data = importDM4(filepath, options)
%IMPORTDM4  Import a Gatan DigitalMicrograph DM4 file.
%   Supports 2D images, 1D EELS/EDX spectra, and 3D spectrum images (SI cubes).
%
%   Syntax
%   ──────
%   data = parser.importDM3(filepath)
%   data = parser.importDM3(filepath, Name=Value)
%
%   Inputs
%   ──────
%   filepath   (1,1) string   Path to a .dm3 or .dm4 file.
%
%   Name-Value Options
%   ──────────────────
%   Verbose    logical   Print a summary after import (default: false).
%
%   Outputs
%   ───────
%   data   Struct produced by parser.createDataStruct with fields:
%            .time        Depends on mode:
%                           2D image    — [Hx1] row pixel indices 1..H
%                           1D spectrum — [Wx1] energy axis (eV or raw channel)
%                           3D SI cube  — [nEx1] energy axis
%            .values      Depends on mode:
%                           2D image    — [Hx1] mean intensity per row
%                           1D spectrum — [Wx1] spectral counts
%                           3D SI cube  — [nEx1] spatially-summed spectrum
%            .labels      Mode-appropriate channel label
%            .units       {'counts'}
%            .metadata    Struct — see below
%
%   Metadata fields (data.metadata)
%   ────────────────────────────────
%   .source              Full file path
%   .importDate          datetime of import
%   .parserName          'importDM3'
%   .parserVersion       '1.1'
%   .xColumnName         'Row' | 'Energy Loss' depending on mode
%   .xColumnUnit         'px'  | energy unit (usually 'eV')
%   .parserSpecific
%     .isImage           true for 2D; false for 1D/3D
%     .isSpectrum        true for 1D and 3D spectrum images; false for 2D
%     .imageData         (2D only) — image struct; see below
%     .spectrumData      (1D and 3D) — spectrum struct:
%       .energyAxis      [nEx1] calibrated energy values
%       .counts          [nEx1] spectral counts (1D) or sum (3D)
%       .energyScale     eV per channel (NaN if uncalibrated)
%       .energyOrigin    energy at channel 0
%       .energyUnit      'eV' or as stored
%       .nChannels       number of energy channels
%     .spectrumImage     (3D only) — SI cube struct:
%       .cube            [Ny x Nx x nE] double array
%       .Ny              spatial rows
%       .Nx              spatial columns
%       .sumSpectrum     [nEx1] sum over all pixels
%       .pixelSize       spatial pixel size (NaN if uncalibrated)
%       .pixelUnit       spatial unit string
%
%   imageData fields (2D mode)
%   ───────────────────────────
%     .pixels          [HxW] numeric array (uint8/uint16/int32/single/double)
%     .bitDepth        Bits per pixel (8, 16, 32, or 64)
%     .height          H (pixels)
%     .width           W (pixels)
%     .numChannels     1
%     .numFrames       1
%     .frames          {}
%     .pixelSize       Physical size of one pixel (NaN if uncalibrated)
%     .pixelUnit       'nm', 'um', 'pm', etc. ('' if uncalibrated)
%     .calibrated      logical
%     .acquiParams     Struct of acquisition metadata from ImageTags
%
%   DM3/DM4 Binary Format
%   ──────────────────────
%   Gatan DigitalMicrograph stores images in a proprietary recursive tagged
%   binary format. The file header specifies version (3 or 4) and data byte
%   order. Structural integers (counts, sizes) are always big-endian. Tag
%   data values follow the byte order flag in the header.
%
%   This parser performs a two-pass read:
%     Pass 1 — Walk the tag tree; record small scalar/string values inline
%              and store file offsets for large pixel arrays.
%     Pass 2 — Seek to the pixel array offset and read image data.
%
%   Dimensionality is detected from the Dimensions sub-tags:
%     Dimensions.0 only            → 1D spectrum (W channels)
%     Dimensions.0 + .1            → 2D image (W × H pixels)
%     Dimensions.0 + .1 + .2       → 3D spectrum image (W channels × H × D spatial)
%
%   Examples
%   ────────
%   % 2D image
%   data = parser.importDM3('hrstem_image.dm3');
%   img  = data.metadata.parserSpecific.imageData;
%   imagesc(img.pixels);  colormap gray;  axis image;
%
%   % 1D EELS spectrum
%   data = parser.importDM3('eels_spectrum.dm3');
%   spec = data.metadata.parserSpecific.spectrumData;
%   plot(spec.energyAxis, spec.counts);
%   xlabel(spec.energyUnit);
%
%   % 3D spectrum image (SI cube)
%   data = parser.importDM3('si_cube.dm4');
%   si   = data.metadata.parserSpecific.spectrumImage;
%   % si.cube is [Ny x Nx x nE]; plot sum spectrum:
%   plot(data.time, data.values);
%   % extract elemental map at channel k:
%   map = si.cube(:, :, k);
%   imagesc(map);  colormap hot;  axis image;
%
%   % DM4 (version 4) file — same call
%   data = parser.importDM3('eds_map.dm4');
%
%   See also IMPORTTIFF, IMPORTRAWIMAGE, IMPORTAUTO, CREATEDATASTRUCT

    arguments
        filepath (1,1) string {mustBeFile}
        options.Verbose (1,1) logical = false
    end

    % ════════════════════════════════════════════════════════════════
    %  STEP 1: Open file and read header
    % ════════════════════════════════════════════════════════════════
    fid = fopen(char(filepath), 'r', 'b');   % big-endian for structural reads
    if fid == -1
        error('parser:importDM3:openFailed', ...
            'Cannot open file "%s".', filepath);
    end
    cleanFid = onCleanup(@() fclose(fid));

    % Read version (always big-endian, always at offset 0)
    version = fread(fid, 1, 'uint32', 0, 'b');
    if version ~= 4
        error('parser:importDM4:badVersion', ...
            'Not a DM4 file (version %d in "%s"). Expected version 4.', ...
            version, filepath);
    end

    % Read root tag directory size (8 bytes for DM4)
    fread(fid, 1, 'uint64', 0, 'b');   % rootDirSize — skip
    intSize = 8;

    % Byte order for data values: 0 = big-endian, 1 = little-endian
    byteOrderFlag = fread(fid, 1, 'uint32', 0, 'b');
    if byteOrderFlag == 0
        dataByteOrder = 'b';   % big-endian
    else
        dataByteOrder = 'l';   % little-endian
    end

    % ════════════════════════════════════════════════════════════════
    %  STEP 2: Parse the tag tree (Pass 1)
    %
    %  tagMap — containers.Map: dotted path → scalar/string/offset-record
    %  Large pixel arrays (>1000 elements) are stored as offset records:
    %    struct with .offset, .nElements, .elemTypeCode
    %  Small scalars and strings are stored as their values directly.
    % ════════════════════════════════════════════════════════════════
    tagMap = containers.Map('KeyType', 'char', 'ValueType', 'any');

    MAX_DEPTH = 50;

    readTagGroup(fid, '', 0, intSize, dataByteOrder, tagMap, MAX_DEPTH);

    % ════════════════════════════════════════════════════════════════
    %  STEP 3: Identify the real image in ImageList
    % ════════════════════════════════════════════════════════════════
    % ImageList is a tag group whose children are indexed 0, 1, 2...
    % ImageList.0 is usually the thumbnail (DataType=23).
    % We want the entry where DataType is NOT 23 and NOT 8.
    THUMBNAIL_DTYPE  = 23;
    BOOLEAN_DTYPE    = 8;

    imageIdx = -1;
    for k = 0:99
        dtKey = sprintf('ImageList.%d.ImageData.DataType', k);
        if ~isKey(tagMap, dtKey)
            % Entry might not have ImageData subtree (e.g. thumbnail stub);
            % keep searching higher indices instead of breaking
            continue;
        end
        dt = tagMap(dtKey);
        if ~isnumeric(dt)
            continue;
        end
        if dt ~= THUMBNAIL_DTYPE && dt ~= BOOLEAN_DTYPE
            imageIdx = k;
            % Prefer the LAST valid image (highest index)
        end
    end

    if imageIdx < 0
        % Fallback: some DM4 writers omit DataType, use a non-standard code,
        % or store the real image alongside thumbnails with DataType==23.
        % Pick the ImageList entry with the largest pixel count that has both
        % a Data tag and Dimensions.0 — that's almost always the real image.
        bestIdx = -1;
        bestPx  = 0;
        for k = 0:99
            dimKey = sprintf('ImageList.%d.ImageData.Dimensions.0', k);
            datKey = sprintf('ImageList.%d.ImageData.Data', k);
            if ~isKey(tagMap, dimKey) || ~isKey(tagMap, datKey)
                continue;
            end
            w = tagMap(dimKey);
            if ~isnumeric(w) || ~isscalar(w) || ~isfinite(w)
                continue;
            end
            npx = double(w);
            hKey = sprintf('ImageList.%d.ImageData.Dimensions.1', k);
            if isKey(tagMap, hKey)
                h = tagMap(hKey);
                if isnumeric(h) && isscalar(h) && isfinite(h)
                    npx = npx * double(h);
                end
            end
            dKey = sprintf('ImageList.%d.ImageData.Dimensions.2', k);
            if isKey(tagMap, dKey)
                d = tagMap(dKey);
                if isnumeric(d) && isscalar(d) && isfinite(d)
                    npx = npx * double(d);
                end
            end
            if npx > bestPx
                bestPx  = npx;
                bestIdx = k;
            end
        end
        imageIdx = bestIdx;
    end

    if imageIdx < 0
        error('parser:importDM3:noImage', ...
            'No usable image found in "%s" (only thumbnails or no ImageList).', ...
            filepath);
    end

    base = sprintf('ImageList.%d.ImageData', imageIdx);

    % ════════════════════════════════════════════════════════════════
    %  STEP 4: Extract dimensions and data type
    % ════════════════════════════════════════════════════════════════
    W = getTagScalar(tagMap, sprintf('%s.Dimensions.0', base), NaN);
    H = getTagScalar(tagMap, sprintf('%s.Dimensions.1', base), NaN);
    D = getTagScalar(tagMap, sprintf('%s.Dimensions.2', base), NaN);
    dmDataType = getTagScalar(tagMap, sprintf('%s.DataType', base), 0);

    % Detect data dimensionality
    if isnan(W)
        error('parser:importDM3:noDimensions', ...
            'Could not read image dimensions from "%s".', filepath);
    end

    W = double(W);
    H = double(H);  % NaN for 1D spectra
    D = double(D);  % NaN for 1D and 2D data

    if isnan(H)
        % 1D spectrum: W = number of energy channels
        dataMode = '1D';
        nPx = W;
    elseif isnan(D)
        % 2D image: W x H (current behavior)
        dataMode = '2D';
        nPx = W * H;
    else
        % 3D spectrum image: W channels x H cols x D rows
        dataMode = '3D';
        nPx = W * H * D;
    end

    [matlabType, bitDepth] = dmImageTypeToMatlab(dmDataType);
    if isempty(matlabType)
        error('parser:importDM3:unsupportedDataType', ...
            'Unsupported DM image DataType %d in "%s".', dmDataType, filepath);
    end

    % ════════════════════════════════════════════════════════════════
    %  STEP 5: Read pixel data (Pass 2 — seek to stored offset)
    % ════════════════════════════════════════════════════════════════
    dataKey = sprintf('%s.Data', base);
    if ~isKey(tagMap, dataKey)
        error('parser:importDM3:noDataTag', ...
            'Image Data tag not found in tag tree for "%s".', filepath);
    end

    rec  = tagMap(dataKey);

    if isstruct(rec) && isfield(rec, 'offset')
        % Large array: stored as an offset record — seek and read
        fseek(fid, rec.offset, 'bof');
        pixels = fread(fid, nPx, ['*' matlabType], 0, dataByteOrder);
    elseif isnumeric(rec)
        % Small array: already read and stored inline in tagMap
        pixels = cast(rec(:), matlabType);
    else
        error('parser:importDM3:badDataRecord', ...
            'Image Data tag record has unexpected format in "%s".', filepath);
    end

    if numel(pixels) < nPx
        warning('parser:importDM3:truncatedData', ...
            'Expected %d pixels but read %d from "%s". Padding with zeros.', ...
            nPx, numel(pixels), filepath);
        pixels(end+1 : nPx) = cast(0, matlabType);
    end

    % DM stores pixels in row-major order (C order): X varies fastest
    switch dataMode
        case '1D'
            pixels = pixels(:);  % [W x 1] column vector
        case '2D'
            % MATLAB imagesc expects [row, col] = [y, x]
            pixels = reshape(pixels, [W, H])';   % [H x W]
        case '3D'
            % DM stores as [W x H x D] in row-major order
            % W = energy channels, H = spatial X, D = spatial Y
            pixels = reshape(pixels, [W, H, D]);
            pixels = permute(pixels, [3, 2, 1]);  % → [D x H x W] = [Ny x Nx x nE]
    end

    % ════════════════════════════════════════════════════════════════
    %  STEP 6: Extract calibration
    % ════════════════════════════════════════════════════════════════
    % Dimension 0 = X (width), Dimension 1 = Y (height)
    calBase  = sprintf('%s.Calibrations.Dimension', base);
    xScale   = getTagScalar(tagMap, sprintf('%s.0.Scale', calBase), NaN);
    xUnits   = getTagString(tagMap,  sprintf('%s.0.Units', calBase), '');
    yScale   = getTagScalar(tagMap, sprintf('%s.1.Scale', calBase), NaN);
    yUnits   = getTagString(tagMap,  sprintf('%s.1.Units', calBase), '');  %#ok<NASGU>

    % Use X calibration as the primary pixel size (both axes are usually equal)
    if ~isnan(xScale) && xScale > 0 && ~isempty(xUnits)
        pixelSize  = xScale;
        pixelUnit  = xUnits;
        calibrated = true;
    elseif ~isnan(yScale) && yScale > 0 && ~isempty(yUnits)
        pixelSize  = yScale;
        pixelUnit  = yUnits;
        calibrated = true;
    else
        pixelSize  = NaN;
        pixelUnit  = '';
        calibrated = false;
    end

    % Energy calibration for spectra
    energyScale  = NaN;
    energyOrigin = NaN;
    energyUnit   = '';
    if ~strcmp(dataMode, '2D')
        % Dimension 0 is the energy axis for spectra
        energyScale  = getTagScalar(tagMap, sprintf('%s.0.Scale',  calBase), NaN);
        energyOrigin = getTagScalar(tagMap, sprintf('%s.0.Origin', calBase), 0);
        energyUnit   = getTagString(tagMap,  sprintf('%s.0.Units',  calBase), 'eV');
    end

    % ════════════════════════════════════════════════════════════════
    %  STEP 7: Collect acquisition metadata from ImageTags
    % ════════════════════════════════════════════════════════════════
    acquiParams = struct();
    acquiParams.dmVersion  = version;
    acquiParams.dataType   = dmDataType;

    % Harvest any scalar/string tags under ImageTags into acquiParams
    imgTagsPrefix = sprintf('ImageList.%d.ImageTags.', imageIdx);
    allKeys = keys(tagMap);
    for k = 1:numel(allKeys)
        key = allKeys{k};
        if startsWith(key, imgTagsPrefix)
            suffix = key(numel(imgTagsPrefix)+1:end);
            % Replace dots with underscores for field name safety
            safeName = regexprep(suffix, '[^a-zA-Z0-9_]', '_');
            if isempty(safeName) || ~isletter(safeName(1))
                safeName = ['x_' safeName]; %#ok<AGROW>
            end
            val = tagMap(key);
            if ischar(val) || (isnumeric(val) && isscalar(val))
                try
                    acquiParams.(safeName) = val;
                catch
                    % Skip fields whose name is not a valid identifier
                end
            end
        end
    end

    % ════════════════════════════════════════════════════════════════
    %  STEP 8 & 9: Assemble metadata and unified struct (mode-aware)
    % ════════════════════════════════════════════════════════════════
    meta.source        = char(filepath);
    meta.importDate    = datetime('now');
    meta.parserName    = 'importDM4';
    meta.parserVersion = '1.1';

    switch dataMode
        case '1D'
            % 1D Spectrum: energy axis as time, spectrum as values
            if ~isnan(energyScale) && energyScale ~= 0
                energyAxis = energyOrigin + (0:W-1)' * energyScale;
            else
                energyAxis = (0:W-1)';
            end

            timeVec = energyAxis;
            valVec  = double(pixels);

            meta.xColumnName = 'Energy Loss';
            meta.xColumnUnit = energyUnit;

            specData.energyAxis   = energyAxis;
            specData.counts       = double(pixels);
            specData.energyScale  = energyScale;
            specData.energyOrigin = energyOrigin;
            specData.energyUnit   = energyUnit;
            specData.nChannels    = W;

            meta.parserSpecific.isImage      = false;
            meta.parserSpecific.isSpectrum   = true;
            meta.parserSpecific.spectrumData = specData;

            data = parser.createDataStruct(timeVec, valVec, ...
                'labels',   {'EELS Counts'}, ...
                'units',    {'counts'}, ...
                'metadata', meta);

        case '2D'
            % 2D Image: existing behavior (mean per row as fallback)
            timeVec    = (1:H)';
            meanPerRow = mean(double(pixels), 2);

            meta.xColumnName = 'Row';
            meta.xColumnUnit = 'px';

            imgData.pixels      = pixels;
            imgData.bitDepth    = bitDepth;
            imgData.height      = H;
            imgData.width       = W;
            imgData.numChannels = 1;
            imgData.numFrames   = 1;
            imgData.frames      = {};
            imgData.pixelSize   = pixelSize;
            imgData.pixelUnit   = pixelUnit;
            imgData.calibrated  = calibrated;
            imgData.acquiParams = acquiParams;

            meta.parserSpecific.isImage    = true;
            meta.parserSpecific.isSpectrum = false;
            meta.parserSpecific.imageData  = imgData;

            data = parser.createDataStruct(timeVec, meanPerRow, ...
                'labels',   {'Mean Intensity'}, ...
                'units',    {'counts'}, ...
                'metadata', meta);

        case '3D'
            % 3D Spectrum Image: cube is [Ny x Nx x nE]
            nE = W;  % energy channels
            Ny = double(D);
            Nx = double(H);

            if ~isnan(energyScale) && energyScale ~= 0
                energyAxis = energyOrigin + (0:nE-1)' * energyScale;
            else
                energyAxis = (0:nE-1)';
            end

            % 1D fallback: spatially-summed spectrum
            sumSpectrum = squeeze(sum(sum(double(pixels), 1), 2));
            timeVec = energyAxis;

            % Spatial calibration from dimension 1
            spatCalBase = sprintf('%s.Calibrations.Dimension', base);
            spScale = getTagScalar(tagMap, sprintf('%s.1.Scale', spatCalBase), NaN);
            spUnit  = getTagString(tagMap,  sprintf('%s.1.Units', spatCalBase), '');

            meta.xColumnName = 'Energy Loss';
            meta.xColumnUnit = energyUnit;

            siData.cube         = pixels;  % [Ny x Nx x nE]
            siData.energyAxis   = energyAxis;
            siData.energyScale  = energyScale;
            siData.energyOrigin = energyOrigin;
            siData.energyUnit   = energyUnit;
            siData.nChannels    = nE;
            siData.Ny           = Ny;
            siData.Nx           = Nx;
            siData.sumSpectrum  = sumSpectrum;
            siData.pixelSize    = spScale;
            siData.pixelUnit    = spUnit;

            meta.parserSpecific.isImage       = false;
            meta.parserSpecific.isSpectrum    = true;
            meta.parserSpecific.spectrumImage = siData;
            meta.parserSpecific.spectrumData  = struct( ...
                'energyAxis',   energyAxis, ...
                'counts',       sumSpectrum, ...
                'energyScale',  energyScale, ...
                'energyOrigin', energyOrigin, ...
                'energyUnit',   energyUnit, ...
                'nChannels',    nE);

            data = parser.createDataStruct(timeVec, sumSpectrum, ...
                'labels',   {'Sum EELS Counts'}, ...
                'units',    {'counts'}, ...
                'metadata', meta);
    end

    if options.Verbose
        switch dataMode
            case '1D'
                fprintf('importDM3: DM%d | 1D spectrum | %d channels\n', version, W);
            case '2D'
                fprintf('importDM3: DM%d | %dx%d px | %d-bit | calibrated=%d\n', ...
                    version, W, H, bitDepth, calibrated);
                if calibrated
                    fprintf('  Pixel size: %.4g %s\n', pixelSize, pixelUnit);
                end
            case '3D'
                fprintf('importDM3: DM%d | SI %dx%d px | %d channels\n', ...
                    version, double(H), double(D), W);
        end
    end
end


% ════════════════════════════════════════════════════════════════════
%  RECURSIVE TAG TREE PARSER
% ════════════════════════════════════════════════════════════════════

function readTagGroup(fid, path, depth, intSize, dataByteOrder, tagMap, maxDepth)
%READTAGGROUP  Parse a DM3/DM4 tag group (sorted/open flags + child tags).

    if depth > maxDepth
        return;
    end

    % Sorted and open flags (1 byte each)
    fread(fid, 1, 'uint8');   % sorted
    fread(fid, 1, 'uint8');   % open

    % Number of child tags
    if intSize == 4
        nTags = double(fread(fid, 1, 'uint32', 0, 'b'));
    else
        nTags = double(fread(fid, 1, 'uint64', 0, 'b'));
    end

    for k = 0:nTags-1
        readTagEntry(fid, path, k, depth, intSize, dataByteOrder, tagMap, maxDepth);
    end
end


function readTagEntry(fid, parentPath, tagIdx, depth, intSize, dataByteOrder, tagMap, maxDepth)
%READTAGENTRY  Parse one entry from a tag group: type byte, label, then content.

    if feof(fid)
        return;
    end

    typeCode = fread(fid, 1, 'uint8');
    if isempty(typeCode)
        return;
    end

    % Tag label
    labelLen = fread(fid, 1, 'uint16', 0, 'b');
    if labelLen > 0
        labelBytes = fread(fid, labelLen, '*uint8');
        label = char(labelBytes');
    else
        label = num2str(tagIdx);
    end

    % Build dotted path
    if isempty(parentPath)
        myPath = label;
    else
        myPath = [parentPath '.' label];
    end

    switch typeCode
        case 20   % 0x14 — Tag Group (sub-directory)
            readTagGroup(fid, myPath, depth+1, intSize, dataByteOrder, tagMap, maxDepth);

        case 21   % 0x15 — Tag Data (leaf)
            readTagData(fid, myPath, intSize, dataByteOrder, tagMap);

        case 0    % End of directory
            % Nothing to do

        otherwise
            % Unknown tag type — cannot safely skip; stop parsing this branch
    end
end


function readTagData(fid, path, intSize, dataByteOrder, tagMap)
%READTAGDATA  Parse a leaf tag: delimiter, info array, then data payload.

    % DM4 has an 8-byte total-data-size field before the delimiter
    if intSize == 8
        fread(fid, 1, 'uint64', 0, 'b');   % totalSize — skip
    end

    % Delimiter: 4 bytes = 0x25 0x25 0x25 0x25 ("%%%%")
    delim = fread(fid, 4, '*uint8');
    if numel(delim) < 4 || ~all(delim == 0x25)
        % Malformed tag — cannot reliably continue
        return;
    end

    % Info array length (always big-endian, always 4 bytes even in DM4)
    infoLen = fread(fid, 1, 'uint32', 0, 'b');
    if infoLen == 0
        return;
    end

    % Info array values (4 bytes each, big-endian)
    info = fread(fid, infoLen, 'uint32', 0, 'b');
    if numel(info) < infoLen
        return;
    end

    % Dispatch by info[1] (the "meta-type" code)
    metaType = info(1);

    LARGE_ARRAY_THRESHOLD = 1000;

    switch metaType
        case 15   % Struct
            val = readInfoStruct(fid, info, dataByteOrder);
            if ~isempty(val)
                tagMap(path) = val; %#ok<NASGU> — containers.Map handle
            end

        case 18   % String
            if infoLen >= 2
                charCount = info(2);
                if charCount > 0
                    charVals = fread(fid, charCount, 'uint16', 0, dataByteOrder);
                    tagMap(path) = char(charVals'); %#ok<NASGU>
                end
            end

        case 20   % Array
            if infoLen >= 3
                elemType  = info(2);
                arrayLen  = info(3);
            elseif infoLen == 2
                elemType  = info(2);
                arrayLen  = 0;
            else
                return;
            end

            % Distinguish: simple array vs array of structs
            if elemType == 15 && infoLen > 3
                % Array of structs — skip (too complex for the values we
                % need; the image pixel array has elemType != 15).
                %
                % Info layout for struct arrays:
                %   [20, 15, structNameLen(=0), numFields, 0, type0, 0, type1, ..., arrayLen]
                %   info(3:end) = [0, numFields, 0, type0, 0, type1, ..., arrayLen]
                %
                % The array length is the LAST element; info(3) is the
                % struct name length (always 0), NOT the array length.
                structArrayLen = double(info(end));
                bytesPerStruct = computeStructBytes(info(3:end));
                totalBytes = bytesPerStruct * structArrayLen;
                if totalBytes > 0
                    fseek(fid, totalBytes, 'cof');
                end
                return;
            end

            bytes = typeCodeToBytes(elemType);
            totalBytes = bytes * double(arrayLen);

            if arrayLen > LARGE_ARRAY_THRESHOLD
                % Large array: record offset and skip — read in pass 2 if needed
                offset = ftell(fid);
                rec.offset      = offset;
                rec.nElements   = arrayLen;
                rec.elemTypeCode = elemType;
                tagMap(path) = rec; %#ok<NASGU>
                fseek(fid, totalBytes, 'cof');
            else
                mtype = typeCodeToMatlab(elemType);
                if ~isempty(mtype) && arrayLen > 0
                    vals = fread(fid, arrayLen, ['*' mtype], 0, dataByteOrder);
                    if isscalar(vals)
                        tagMap(path) = double(vals); %#ok<NASGU>
                    else
                        tagMap(path) = vals; %#ok<NASGU>
                    end
                elseif totalBytes > 0
                    fseek(fid, totalBytes, 'cof');
                end
            end

        otherwise
            % Simple scalar type
            bytes = typeCodeToBytes(metaType);
            if bytes > 0
                mtype = typeCodeToMatlab(metaType);
                if ~isempty(mtype)
                    val = fread(fid, 1, ['*' mtype], 0, dataByteOrder);
                    if ~isempty(val)
                        tagMap(path) = double(val); %#ok<NASGU>
                    end
                else
                    fseek(fid, bytes, 'cof');
                end
            end
    end
end


function val = readInfoStruct(fid, info, dataByteOrder)
%READINFOSTRUCT  Read a struct payload described by an info array.
%   info(1) = 15 (struct), info(2) = 0, info(3) = numFields,
%   info(4) = 0, info(5) = type1, info(6) = 0, info(7) = type2, ...
    val = [];

    if numel(info) < 3
        return;
    end

    numFields = info(3);
    if numFields == 0
        return;
    end

    % Field types start at info(5), every other entry (pairs of 0, typeCode)
    fieldOffset = 5;
    vals = zeros(1, numFields);
    for k = 1:numFields
        typeIdx = fieldOffset + (k-1)*2;
        if typeIdx > numel(info)
            return;
        end
        fType = info(typeIdx);
        mtype = typeCodeToMatlab(fType);
        bytes = typeCodeToBytes(fType);
        if ~isempty(mtype)
            v = fread(fid, 1, ['*' mtype], 0, dataByteOrder);
            if ~isempty(v)
                vals(k) = double(v);
            end
        elseif bytes > 0
            fseek(fid, bytes, 'cof');
        end
    end
    val = vals;
end


function totalBytes = computeStructBytes(infoSubset)
%COMPUTESTRUCTBYTES  Estimate byte size of one struct from the info array tail.
%   infoSubset layout (from array-of-structs info, starting after [20, 15]):
%     [structNameLen(=0), numFields, fieldNameLen0(=0), type0,
%      fieldNameLen1(=0), type1, ..., arrayLength]
%
%   infoSubset(1) = 0            (struct name length, always 0)
%   infoSubset(2) = numFields
%   infoSubset(3) = 0            (field 0 name length)
%   infoSubset(4) = type0        (field 0 type code)
%   infoSubset(5) = 0            (field 1 name length)
%   infoSubset(6) = type1        (field 1 type code)
%   ...
%   infoSubset(end) = arrayLength (consumed by caller, not used here)
    totalBytes = 0;
    if numel(infoSubset) < 2
        return;
    end
    numFields = double(infoSubset(2));
    fieldOffset = 4;   % first type code is at index 4
    for k = 1:numFields
        typeIdx = fieldOffset + (k-1)*2;
        if typeIdx > numel(infoSubset)
            break;
        end
        totalBytes = totalBytes + typeCodeToBytes(infoSubset(typeIdx));
    end
end


% ════════════════════════════════════════════════════════════════════
%  TYPE CODE HELPERS
% ════════════════════════════════════════════════════════════════════

function mtype = typeCodeToMatlab(code)
%TYPECODETOMATLAB  Map DM info-array type code to MATLAB fread precision string.
%   These codes apply to INFO ARRAY elements (NOT the same as image DataType).
    switch code
        case 2,  mtype = 'int16';
        case 3,  mtype = 'int32';
        case 4,  mtype = 'uint16';
        case 5,  mtype = 'uint32';
        case 6,  mtype = 'single';
        case 7,  mtype = 'double';
        case 8,  mtype = 'uint8';    % bool
        case 9,  mtype = 'int8';
        case 10, mtype = 'uint8';
        case 11, mtype = 'int64';
        case 12, mtype = 'uint64';
        otherwise, mtype = '';
    end
end


function n = typeCodeToBytes(code)
%TYPECODETOBYTES  Return byte size for a given type code.
    switch code
        case {2, 4},        n = 2;
        case {3, 5, 6},     n = 4;
        case {7, 11, 12},   n = 8;
        case {8, 9, 10},    n = 1;
        otherwise,          n = 0;
    end
end


function [mtype, bitDepth] = dmImageTypeToMatlab(dmDataType)
%DMIMAGETYPETOMATLAB  Map DM image DataType code to MATLAB type + bitDepth.
%   These codes are DIFFERENT from info-array type codes.
    switch dmDataType
        case 1,  mtype = 'int16';   bitDepth = 16;
        case 2,  mtype = 'single';  bitDepth = 32;
        case 6,  mtype = 'uint8';   bitDepth = 8;
        case 7,  mtype = 'int32';   bitDepth = 32;
        case 9,  mtype = 'int8';    bitDepth = 8;
        case 10, mtype = 'uint16';  bitDepth = 16;
        case 11, mtype = 'uint32';  bitDepth = 32;
        case 12, mtype = 'double';  bitDepth = 64;
        otherwise
            mtype    = '';
            bitDepth = 0;
    end
end


% ════════════════════════════════════════════════════════════════════
%  MAP ACCESSOR HELPERS
% ════════════════════════════════════════════════════════════════════

function val = getTagScalar(tagMap, key, defaultVal)
%GETTAGSCALAR  Return a numeric scalar from tagMap, or defaultVal if missing.
    if isKey(tagMap, key)
        v = tagMap(key);
        if isnumeric(v) && ~isempty(v)
            val = double(v(1));
            return;
        end
    end
    val = defaultVal;
end


function val = getTagString(tagMap, key, defaultVal)
%GETTAGSTRING  Return a char string from tagMap, or defaultVal if missing.
%   DM3 strings may be stored as char (from type 18) or as uint16 arrays
%   (from type 20 with element type 4).  Both cases are handled here.
    if isKey(tagMap, key)
        v = tagMap(key);
        if ischar(v)
            val = v;
            return;
        elseif isa(v, 'uint16')
            % UTF-16 code points stored as uint16 array — convert to char
            val = char(v(:)');
            return;
        end
    end
    val = defaultVal;
end
