function data = importBCF(filepath, options)
%IMPORTBCF  Import a Bruker BCF EDS spectral-imaging file.
%
%   BCF is a Bruker proprietary container (SFS — Single File System) that
%   stores EDS hypercube data alongside SEM reference images and XML
%   acquisition metadata. This parser extracts the SEM image(s), sum EDS
%   spectrum, energy calibration, and key SEM/stage parameters without
%   requiring any external toolboxes.
%
%   Syntax
%   ──────
%   data = parser.importBCF(filepath)
%   data = parser.importBCF(filepath, Name=Value)
%
%   Inputs
%   ──────
%   filepath   (1,1) string   Path to a .bcf file.
%
%   Name-Value Options
%   ──────────────────
%   Verbose    logical   Print a summary after import (default: false).
%   LoadCube   logical   Reserved for future full spectral datacube read.
%                        Currently ignored; included for forward compatibility
%                        (default: false).
%
%   Outputs
%   ───────
%   data   Struct produced by parser.createDataStruct with fields:
%
%   When a SEM reference image is present:
%     .time        [Hx1]  Row pixel indices 1..H (1-D fallback axis)
%     .values      [Hx1]  Mean intensity per row
%     .labels      {'Mean Intensity'}
%     .units       {'counts'}
%
%   When no SEM image is available:
%     .time        [Nx1]  Energy axis (keV)
%     .values      [Nx1]  EDS sum spectrum counts
%     .labels      {'EDS Sum Spectrum'}
%     .units       {'counts'}
%
%   Metadata fields (data.metadata)
%   ────────────────────────────────
%   .source              Full file path
%   .importDate          datetime of import
%   .parserName          'importBCF'
%   .parserVersion       '1.0'
%   .xColumnName         'Row' | 'Energy'
%   .xColumnUnit         'px'  | 'keV'
%   .parserSpecific
%     .isImage           true when a SEM image was decoded
%     .imageData         Standard imageData struct (isImage=true only)
%       .pixels          [HxW] uint8 or uint16 SEM reference image
%       .bitDepth        8 or 16
%       .height          H (pixels)
%       .width           W (pixels)
%       .numChannels     1
%       .numFrames       1
%       .frames          {}
%       .pixelSize       Physical size per pixel in pixelUnit (NaN if unknown)
%       .pixelUnit       'um' or '' if uncalibrated
%       .calibrated      logical
%       .acquiParams     struct (empty; FEI-style tags not applicable)
%     .allImages         Struct array, one entry per TRTImageData plane
%       .pixels          [HxW] decoded image array
%       .width           W
%       .height          H
%       .itemSize        bytes per pixel
%     .edsData
%       .energyAxis      [Nx1] keV values for each channel
%       .sumSpectrum     [Nx1] integrated counts
%       .calibAbs        energy offset (keV, channel-0 energy)
%       .calibLin        energy per channel (keV/channel)
%       .nChannels       number of energy channels
%       .elements        cell array of identified element strings (may be {})
%     .semParams
%       .voltage_kV      accelerating voltage (NaN if missing)
%       .pixelSize_um    pixel size in microns  (NaN if missing)
%       .magnification   magnification value    (NaN if missing)
%       .stageX_mm       stage X (mm)           (NaN if missing)
%       .stageY_mm       stage Y (mm)           (NaN if missing)
%       .stageZ_mm       stage Z (mm)           (NaN if missing)
%       .stageTilt_deg   tilt angle (degrees)   (NaN if missing)
%       .elevationAngle_deg  EDS detector elevation (NaN if missing)
%
%   SFS Container Format
%   ─────────────────────
%   BCF uses Bruker's proprietary SFS (Single File System) container.
%   Magic bytes 'AAMVHFSS' are at offset 0x00. Data is stored as a tree of
%   variable-length chunks; compressed blocks use Java zlib via
%   java.util.zip.Inflater (always available in MATLAB). The two internal
%   files parsed are:
%       EDSDatabase/HeaderData   — XML with SEM/EDS metadata and images
%       EDSDatabase/SpectrumData0 — binary EDS hypercube (not read here)
%
%   Examples
%   ────────
%   % Basic import — SEM image
%   data = parser.importBCF('eds_map.bcf');
%   img  = data.metadata.parserSpecific.imageData;
%   imagesc(img.pixels); colormap gray; axis image;
%
%   % Sum EDS spectrum
%   eds  = data.metadata.parserSpecific.edsData;
%   plot(eds.energyAxis, eds.sumSpectrum);
%   xlabel('Energy (keV)'); ylabel('Counts');
%
%   % SEM acquisition parameters
%   sp = data.metadata.parserSpecific.semParams;
%   fprintf('HV=%.1f kV, pixel=%.3f um\n', sp.voltage_kV, sp.pixelSize_um);
%
%   See also IMPORTTIFF, IMPORTDM3, IMPORTAUTO, CREATEDATASTRUCT

    arguments
        filepath  (1,1) string {mustBeFile}
        options.Verbose  (1,1) logical = false
        options.LoadCube (1,1) logical = false   % reserved, unused
    end

    % ════════════════════════════════════════════════════════════════
    %  STEP 1: Read entire file into memory and verify SFS magic
    % ════════════════════════════════════════════════════════════════
    fid = fopen(char(filepath), 'rb');
    if fid == -1
        error('parser:importBCF:cannotOpen', ...
            'Cannot open file "%s".', filepath);
    end
    rawFile = fread(fid, Inf, '*uint8')';
    fclose(fid);

    if numel(rawFile) < 336 || ~isequal(rawFile(1:8), uint8('AAMVHFSS'))
        error('parser:importBCF:badMagic', ...
            '"%s" is not a Bruker BCF/SFS file (expected magic ''AAMVHFSS'').', ...
            filepath);
    end

    % ════════════════════════════════════════════════════════════════
    %  STEP 2: Read SFS container header (from memory)
    % ════════════════════════════════════════════════════════════════
    chunkSize   = double(typecast(rawFile(297 : 300), 'uint32'));   % offset 0x128
    usableChunk = chunkSize - 32;
    treeAddress = double(typecast(rawFile(321 : 324), 'uint32'));   % offset 0x140
    itemCount   = double(typecast(rawFile(325 : 328), 'uint32'));   % offset 0x144

    % ════════════════════════════════════════════════════════════════
    %  STEP 3: Parse SFS file tree (from memory)
    % ════════════════════════════════════════════════════════════════
    treeBase   = treeAddress * chunkSize + 312 + 1;  % 1-based
    ENTRY_SIZE = 512;
    treeEnd    = treeBase + itemCount * ENTRY_SIZE - 1;
    if treeEnd > numel(rawFile)
        error('parser:importBCF:truncatedTree', ...
            'SFS file tree is truncated in "%s".', filepath);
    end
    treeRaw = rawFile(treeBase : treeEnd);
    entries = parseSFSTree(treeRaw, itemCount, ENTRY_SIZE);

    % ════════════════════════════════════════════════════════════════
    %  STEP 4: Locate internal files of interest
    % ════════════════════════════════════════════════════════════════
    headerIdx = findEntry(entries, 'EDSDatabase/HeaderData');
    if headerIdx == 0
        error('parser:importBCF:noHeader', ...
            'Could not find "EDSDatabase/HeaderData" in "%s".', filepath);
    end

    % ════════════════════════════════════════════════════════════════
    %  STEP 5: Read and decompress HeaderData (from memory)
    % ════════════════════════════════════════════════════════════════
    hdrEntry    = entries(headerIdx);
    hdrFileSize = double(hdrEntry.fileSize);
    % Read pointer table
    ptrBase = hdrEntry.ptrTable * chunkSize + 312 + 1;  % 1-based
    nChunks = ceil(hdrFileSize / usableChunk);
    ptrBytes = rawFile(ptrBase : ptrBase + nChunks*4 - 1);
    ptrTable = double(typecast(uint8(ptrBytes(:)), 'uint32'))';  % row vector
    % Assemble file from chunks
    headerBytes = zeros(1, hdrFileSize, 'uint8');
    bytesRead = 0;
    for hc = 1:nChunks
        chunkStart = ptrTable(hc) * chunkSize + 312 + 1;  % 1-based
        remaining  = hdrFileSize - bytesRead;
        toRead     = min(remaining, usableChunk);
        chunkEnd   = chunkStart + toRead - 1;
        headerBytes(bytesRead+1 : bytesRead+toRead) = rawFile(chunkStart : chunkEnd);
        bytesRead  = bytesRead + toRead;
    end
    headerBytes = decompressIfNeeded(headerBytes);

    % ════════════════════════════════════════════════════════════════
    %  STEP 6: Parse XML metadata as text (regex-based)
    % ════════════════════════════════════════════════════════════════
    % xmlread / Java SAX cannot handle the huge base64 <Data> blocks
    % in BCF files, so we use regex-based text extraction instead.
    xmlText = char(headerBytes(:)');  % convert uint8 to char row vector
    % (steps 6-9 below extract metadata from this XML text)

    % ════════════════════════════════════════════════════════════════
    %  STEP 7: Extract SEM parameters from XML
    % ════════════════════════════════════════════════════════════════
    semParams = extractSEMParams(xmlText);

    % ════════════════════════════════════════════════════════════════
    %  STEP 8: Extract EDS sum spectrum from XML
    % ════════════════════════════════════════════════════════════════
    edsData = extractEDSData(xmlText);

    % ════════════════════════════════════════════════════════════════
    %  STEP 9: Extract SEM reference images from XML
    % ════════════════════════════════════════════════════════════════
    allImages = extractSEMImages(xmlText);

    % ════════════════════════════════════════════════════════════════
    %  STEP 10: Build unified struct
    % ════════════════════════════════════════════════════════════════
    meta.source        = char(filepath);
    meta.importDate    = datetime('now');
    meta.parserName    = 'importBCF';
    meta.parserVersion = '1.0';

    meta.parserSpecific.edsData   = edsData;
    meta.parserSpecific.semParams = semParams;
    meta.parserSpecific.allImages = allImages;

    if ~isempty(allImages)
        % Use the first image as the primary SEM image
        primaryImg = allImages(1);
        W = primaryImg.width;
        H = primaryImg.height;

        imgData.pixels      = primaryImg.pixels;
        imgData.bitDepth    = primaryImg.itemSize * 8;
        imgData.height      = H;
        imgData.width       = W;
        imgData.numChannels = 1;
        imgData.numFrames   = 1;
        imgData.frames      = {};
        imgData.acquiParams = struct();

        % Apply pixel size calibration from SEM params
        if ~isnan(semParams.pixelSize_um) && semParams.pixelSize_um > 0
            imgData.pixelSize  = semParams.pixelSize_um;
            imgData.pixelUnit  = 'um';
            imgData.calibrated = true;
        else
            imgData.pixelSize  = NaN;
            imgData.pixelUnit  = '';
            imgData.calibrated = false;
        end

        meta.parserSpecific.isImage   = true;
        meta.parserSpecific.imageData = imgData;
        meta.xColumnName = 'Row';
        meta.xColumnUnit = 'px';

        % 1-D fallback: mean intensity per row
        timeVec    = (1:H)';
        pixFloat   = double(primaryImg.pixels);
        meanPerRow = mean(pixFloat, 2);

        data = parser.createDataStruct(timeVec, meanPerRow, ...
            'labels',   {'Mean Intensity'}, ...
            'units',    {'counts'}, ...
            'metadata', meta);
    else
        % No SEM image — fall back to sum EDS spectrum
        meta.parserSpecific.isImage = false;
        meta.xColumnName = 'Energy';
        meta.xColumnUnit = 'keV';

        if isempty(edsData.energyAxis)
            error('parser:importBCF:noData', ...
                'No SEM image and no EDS spectrum found in "%s".', filepath);
        end

        data = parser.createDataStruct(edsData.energyAxis, edsData.sumSpectrum, ...
            'labels',   {'EDS Sum Spectrum'}, ...
            'units',    {'counts'}, ...
            'metadata', meta);
    end

    if options.Verbose
        hasImg  = meta.parserSpecific.isImage;
        nCh     = edsData.nChannels;
        nElem   = numel(edsData.elements);
        fprintf('importBCF: image=%d | EDS channels=%d | elements=%d', ...
            hasImg, nCh, nElem);
        if hasImg
            fprintf(' | %dx%d px', ...
                meta.parserSpecific.imageData.width, ...
                meta.parserSpecific.imageData.height);
        end
        if ~isnan(semParams.voltage_kV)
            fprintf(' | HV=%.1f kV', semParams.voltage_kV);
        end
        fprintf('\n');
    end
end


% ════════════════════════════════════════════════════════════════════
%  LOCAL HELPER FUNCTIONS
% ════════════════════════════════════════════════════════════════════

function entries = parseSFSTree(raw, nItems, entrySize)
%PARSESFSTRE  Decode the flat SFS tree byte array into a struct array.
%   Each entry occupies entrySize (512) bytes.
%   Layout (little-endian within each entry):
%     offset 0x00: int32   pointer_to_pointer_table
%     offset 0x04: uint64  file_size
%     offset 0xDC: uint8   is_dir  (0=file, 1=directory)
%     offset 0xE0: char[256] null-terminated name

    entries(nItems) = struct('ptrTable', 0, 'fileSize', uint64(0), ...
                             'isDir', false, 'name', '');
    for k = 1:nItems
        base = (k-1) * entrySize;

        % pointer_to_pointer_table: int32 at offset 0x00
        ptrBytes = raw(base+1 : base+4);
        entries(k).ptrTable = double(typecast(ptrBytes, 'int32'));

        % file_size: uint64 at offset 0x04
        szBytes = raw(base+5 : base+12);
        entries(k).fileSize = typecast(szBytes, 'uint64');

        % is_dir: uint8 at offset 0xDC (220)
        entries(k).isDir = logical(raw(base + 220 + 1));

        % name: 256-byte null-terminated char array at offset 0xE0 (224)
        nameBytes = raw(base + 224 + 1 : base + 224 + 256);
        nullPos   = find(nameBytes == 0, 1, 'first');
        if ~isempty(nullPos)
            nameBytes = nameBytes(1:nullPos-1);
        end
        entries(k).name = char(nameBytes(:)');
    end
end


function idx = findEntry(entries, targetName)
%FINDENTRY  Return the index of the first entry whose name matches.
%   Name comparison is case-insensitive and trims leading path separators.
%   Returns 0 if not found.

    targetLower = lower(strtrim(targetName));
    idx = 0;
    for k = 1:numel(entries)
        if ~entries(k).isDir
            entName = lower(strtrim(entries(k).name));
            % Match either the full path or just the trailing component
            [~, shortName, ~] = fileparts(entName);
            [~, targetShort, ~] = fileparts(targetLower);
            if strcmp(entName, targetLower) || strcmp(shortName, targetShort)
                idx = k;
                return;
            end
        end
    end
end


function bytes = readSFSFile(fid, entry, chunkSize, usableChunk)
%READSFSFILE  Reassemble a fragmented SFS file from its chunk chain.
%   The file's pointer table lives at:
%       entry.ptrTable * chunkSize + 312
%   Each element in the table is a uint32 chunk index.
%   Chunk data starts at:
%       chunkIndex * chunkSize + 312

    fileSize = double(entry.fileSize);
    if fileSize == 0
        bytes = uint8([]);
        return;
    end

    ptrTableOffset = entry.ptrTable * chunkSize + 312;
    nChunks = ceil(fileSize / usableChunk);
    % Read the pointer table
    fseek(fid, ptrTableOffset, 'bof');
    ptrTable = fread(fid, nChunks, 'uint32=>double');

    % Read and concatenate chunk data
    bytes = zeros(1, fileSize, 'uint8');
    bytesRead = 0;
    for c = 1:nChunks
        chunkOffset = ptrTable(c) * chunkSize + 312;
        remaining   = fileSize - bytesRead;
        toRead      = min(remaining, usableChunk);

        status = fseek(fid, chunkOffset, 'bof');
        if status ~= 0
            warning('fseek failed at chunk %d, offset %d', c, chunkOffset);
        end
        chunk = fread(fid, toRead, '*uint8')';
        bytes(bytesRead+1 : bytesRead+numel(chunk)) = chunk;
        bytesRead = bytesRead + numel(chunk);
    end
    bytes = bytes(1:bytesRead);
end


function out = decompressIfNeeded(bytes)
%DECOMPRESSIFNEEDED  Detect and inflate AACS-compressed SFS file data.
%   AACS signature: first 4 bytes == [65 65 67 83] ('AACS').
%   Header (128 bytes):
%     offset 0x04: uint32 uncompressed block size
%     offset 0x0C: uint32 number of blocks
%   Each block: uint32 compressed_size, 12 bytes padding, then zlib data.

    AACS_MAGIC = uint8([65 65 67 83]);
    if numel(bytes) < 128 || ~isequal(bytes(1:4), AACS_MAGIC)
        out = bytes;
        return;
    end

    % Read AACS header fields
    uncompBlockSize = double(typecast(bytes(5:8),  'uint32'));
    nBlocks         = double(typecast(bytes(13:16), 'uint32'));

    % Parse and decompress each block
    outParts = cell(1, nBlocks);
    pos = 129;   % 1-based; header is 128 bytes (0x80)

    for b = 1:nBlocks
        if pos + 3 > numel(bytes)
            break;
        end
        compSize = double(typecast(bytes(pos:pos+3), 'uint32'));
        pos = pos + 4 + 12;   % skip 4-byte size + 12 bytes padding

        if compSize == 0 || pos + compSize - 1 > numel(bytes)
            break;
        end

        compData = bytes(pos : pos + compSize - 1);
        pos      = pos + compSize;

        % Expected size for this block (last block may be smaller)
        expectedOut = uncompBlockSize;  % over-allocate is fine; inflate returns actual n
        outParts{b} = zlibInflate(compData, expectedOut);
    end

    out = horzcat(outParts{:});
end


function out = zlibInflate(compressedBytes, expectedSize)
%ZLIBINFLATE  Decompress raw deflate/zlib data using Java Inflater.
%   java.util.zip.Inflater is available in all MATLAB versions that support Java.

    try
        inflater = java.util.zip.Inflater();
        inflater.setInput(uint8(compressedBytes));
        buffer = zeros(1, max(expectedSize * 2, numel(compressedBytes) * 4), 'uint8');
        n = inflater.inflate(buffer);
        inflater.end();
        out = buffer(1:n);
    catch ME
        warning('parser:importBCF:zlibFail', ...
            'zlib decompression failed: %s. Block skipped.', ME.message);
        out = uint8([]);
    end
end



function semParams = extractSEMParams(xmlText)
%EXTRACTSEMPARAMS  Extract SEM microscope parameters from XML text (regex).

    semParams.voltage_kV        = NaN;
    semParams.pixelSize_um      = NaN;
    semParams.magnification     = NaN;
    semParams.stageX_mm         = NaN;
    semParams.stageY_mm         = NaN;
    semParams.stageZ_mm         = NaN;
    semParams.stageTilt_deg     = NaN;
    semParams.elevationAngle_deg = NaN;

    semBlock = extractClassBlock(xmlText, 'TRTSEMData');
    if ~isempty(semBlock)
        semParams.voltage_kV    = tagDouble(semBlock, 'HV');
        dx = tagDouble(semBlock, 'DX');
        if ~isnan(dx) && dx > 0
            semParams.pixelSize_um = dx;
        end
        semParams.magnification = tagDouble(semBlock, 'Mag');
    end

    stageBlock = extractClassBlock(xmlText, 'TRTSEMStageData');
    if ~isempty(stageBlock)
        semParams.stageX_mm     = tagDouble(stageBlock, 'X');
        semParams.stageY_mm     = tagDouble(stageBlock, 'Y');
        semParams.stageZ_mm     = tagDouble(stageBlock, 'Z');
        semParams.stageTilt_deg = tagDouble(stageBlock, 'Tilt');
    end

    esmaBlock = extractClassBlock(xmlText, 'TRTESMAHeader');
    if ~isempty(esmaBlock)
        semParams.elevationAngle_deg = tagDouble(esmaBlock, 'ElevationAngle');
    end
end


function edsData = extractEDSData(xmlText)
%EXTRACTEDSDATA  Extract EDS calibration and sum spectrum from XML text.

    edsData.energyAxis  = [];
    edsData.sumSpectrum = [];
    edsData.calibAbs    = NaN;
    edsData.calibLin    = NaN;
    edsData.nChannels   = 0;
    edsData.elements    = {};

    specBlock = extractClassBlock(xmlText, 'TRTSpectrumHeader');
    if ~isempty(specBlock)
        edsData.calibAbs = tagDouble(specBlock, 'CalibAbs');
        edsData.calibLin = tagDouble(specBlock, 'CalibLin');
    end

    edsData.nChannels = round(tagDouble(xmlText, 'ChCount'));
    if isnan(edsData.nChannels), edsData.nChannels = 0; end

    chText = tagText(xmlText, 'Channels');
    if ~isempty(chText)
        vals = str2double(strsplit(strtrim(chText), ','));
        vals(isnan(vals)) = 0;
        edsData.sumSpectrum = vals(:);
        if edsData.nChannels == 0
            edsData.nChannels = numel(vals);
        end
    end

    if edsData.nChannels > 0 && ~isnan(edsData.calibAbs) && ~isnan(edsData.calibLin)
        channels = (0 : edsData.nChannels - 1)';
        edsData.energyAxis = edsData.calibAbs + edsData.calibLin .* channels;
    elseif edsData.nChannels > 0
        edsData.energyAxis = (0 : edsData.nChannels - 1)';
    end

    if ~isempty(edsData.sumSpectrum) && ~isempty(edsData.energyAxis)
        n = min(numel(edsData.sumSpectrum), numel(edsData.energyAxis));
        edsData.sumSpectrum = edsData.sumSpectrum(1:n);
        edsData.energyAxis  = edsData.energyAxis(1:n);
    end

    elemBlocks = extractAllClassBlocks(xmlText, 'TRTElementInformation');
    elements = {};
    for k = 1:numel(elemBlocks)
        sym = strtrim(tagText(elemBlocks{k}, 'Symbol'));
        if ~isempty(sym)
            elements{end+1} = sym; %#ok<AGROW>
        end
    end
    edsData.elements = elements;
end


function allImages = extractSEMImages(xmlText)
%EXTRACTSEMIMAGES  Decode all TRTImageData planes from the XML text.

    allImages = struct('pixels', {}, 'width', {}, 'height', {}, 'itemSize', {});

    imgBlocks = extractAllClassBlocks(xmlText, 'TRTImageData');
    for k = 1:numel(imgBlocks)
        block = imgBlocks{k};

        W   = round(tagDouble(block, 'Width'));
        H   = round(tagDouble(block, 'Height'));
        iSz = round(tagDouble(block, 'ItemSize'));

        if isnan(W) || isnan(H) || isnan(iSz) || W <= 0 || H <= 0 || iSz <= 0
            continue;
        end

        nPlanes = round(tagDouble(block, 'PlaneCount'));
        if isnan(nPlanes) || nPlanes < 1, nPlanes = 1; end

        for p = 0 : nPlanes - 1
            planeName = sprintf('Plane%d', p);
            planeBlock = tagText(block, planeName);
            if isempty(planeBlock), continue; end

            b64Text = tagText(planeBlock, 'Data');
            if isempty(b64Text), continue; end

            rawBytes = base64DecodeBytes(strtrim(b64Text));
            if isempty(rawBytes), continue; end

            expectedBytes = W * H * iSz;
            if numel(rawBytes) < expectedBytes, continue; end
            rawBytes = rawBytes(1:expectedBytes);

            if iSz == 1
                pixels = reshape(uint8(rawBytes), W, H)';
            elseif iSz == 2
                pixels = reshape(typecast(uint8(rawBytes), 'uint16'), W, H)';
            else
                pixels = reshape(uint8(rawBytes(1:W*H)), W, H)';
            end

            entry.pixels   = pixels;
            entry.width    = W;
            entry.height   = H;
            entry.itemSize = iSz;
            allImages(end+1) = entry; %#ok<AGROW>
        end
    end
end


% ────────────────────────────────────────────────────────────────────
%  REGEX-BASED XML UTILITIES
% ────────────────────────────────────────────────────────────────────

function txt = tagText(xmlStr, tagName)
%TAGTEXT  Extract text/inner-XML of the first <tagName>...</tagName> match.
    txt = '';
    pat = ['<' tagName '>(.+?)</' tagName '>'];
    tok = regexp(xmlStr, pat, 'tokens', 'once');
    if ~isempty(tok)
        txt = tok{1};
    end
end


function val = tagDouble(xmlStr, tagName)
%TAGDOUBLE  Extract numeric value of first <tagName>, or NaN.
    txt = tagText(xmlStr, tagName);
    if isempty(txt)
        val = NaN;
    else
        val = str2double(strtrim(txt));
    end
end


function block = extractClassBlock(xmlStr, typeName)
%EXTRACTCLASSBLOCK  Return inner content of first ClassInstance with Type=typeName.
%   Handles nested ClassInstance tags by counting open/close depth.
    block = '';
    % Find opening tag using strfind (avoids regex quote issues)
    q = char(34);
    marker = ['Type=' q typeName q];
    markerIdx = strfind(xmlStr, marker);
    if isempty(markerIdx), return; end
    % Find the closing '>' of this opening tag
    startIdx = strfind(xmlStr(markerIdx(1):end), '>');
    if isempty(startIdx), return; end
    startIdx = markerIdx(1) + startIdx(1) - 1;  % absolute position of '>'
    depth = 1;
    pos = startIdx + 1;
    while pos <= numel(xmlStr) && depth > 0
        nextOpen  = strfind(xmlStr(pos:end), '<ClassInstance');
        nextClose = strfind(xmlStr(pos:end), '</ClassInstance>');
        if isempty(nextClose), break; end
        closeOff = pos - 1 + nextClose(1);
        if ~isempty(nextOpen) && (pos - 1 + nextOpen(1)) < closeOff
            openOff = pos - 1 + nextOpen(1);
            depth = depth + 1;
            pos = openOff + 14;  % skip past '<ClassInstance'
        else
            depth = depth - 1;
            if depth == 0
                block = xmlStr(startIdx + 1 : closeOff - 1);
                return;
            end
            pos = closeOff + 16;  % skip past '</ClassInstance>'
        end
    end
end


function blocks = extractAllClassBlocks(xmlStr, typeName)
%EXTRACTALLCLASSBLOCKS  Return all ClassInstance blocks with Type=typeName.
%   Uses extractClassBlock iteratively, removing found blocks.
    blocks = {};
    remaining = xmlStr;
    while true
        b = extractClassBlock(remaining, typeName);
        if isempty(b), break; end
        blocks{end+1} = b; %#ok<AGROW>
        % Remove the found block from remaining to find the next one
        idx = strfind(remaining, b);
        if isempty(idx), break; end
        remaining = remaining(idx(1) + numel(b):end);
    end
end


function bytes = base64DecodeBytes(b64str)
%BASE64DECODEBYTES  Decode a base64 string to a uint8 vector using Java.
    bytes = uint8([]);
    try
        b64str = regexprep(b64str, '\s+', '');
        decoder = java.util.Base64.getDecoder();
        jBytes  = decoder.decode(b64str);
        bytes   = typecast(int8(jBytes), 'uint8');
    catch ME
        warning('parser:importBCF:base64Fail', ...
            'Base64 decoding failed: %s', ME.message);
    end
end
