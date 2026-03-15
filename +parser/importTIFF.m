function data = importTIFF(filepath, options)
%IMPORTTIFF  Import a TIFF/TIF image into the unified toolbox data struct.
%
%   Syntax
%   ──────
%   data = parser.importTIFF(filepath)
%   data = parser.importTIFF(filepath, Name=Value)
%
%   Inputs
%   ──────
%   filepath   (1,1) string   Path to the .tif or .tiff file.
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
%   .parserName          'importTIFF'
%   .parserVersion       '1.0'
%   .xColumnName         'Row'
%   .xColumnUnit         'px'
%   .parserSpecific
%     .isImage           true
%     .imageData
%       .pixels          [HxW] uint8/uint16/single, or [HxWx3] for RGB
%       .bitDepth        8, 16, or 32
%       .height          H  (pixels)
%       .width           W  (pixels)
%       .numChannels     1 (grayscale) or 3 (RGB)
%       .numFrames       Number of frames in the file
%       .frames          {1xN} cell of [HxW] frames (empty {} for single)
%       .pixelSize       Physical size of one pixel (NaN if uncalibrated)
%       .pixelUnit       'nm', 'um', 'm', or '' (empty if uncalibrated)
%       .calibrated      logical — true when pixelSize was found in metadata
%       .acquiParams     Struct of instrument metadata (FEI/Thermo Fisher or
%                        TIFF standard fields)
%
%   FEI/Thermo Fisher SEM metadata is extracted from private TIFF tag 34682
%   when present. The tag contains a key=value text block with section
%   headers like [Beam], [Scan], [Stage]. PixelWidth (m) is used to set
%   pixelSize and pixelUnit.
%
%   Examples
%   ────────
%   % Basic import
%   data = parser.importTIFF('sem_image.tif');
%   img  = data.metadata.parserSpecific.imageData;
%   imagesc(img.pixels);  colormap gray;
%
%   % Check calibration
%   img = data.metadata.parserSpecific.imageData;
%   if img.calibrated
%       fprintf('Pixel size: %.2f %s\n', img.pixelSize, img.pixelUnit);
%   end
%
%   % Multi-page stack
%   data = parser.importTIFF('stack.tif');
%   img  = data.metadata.parserSpecific.imageData;
%   fprintf('%d frames loaded\n', img.numFrames);
%   frame2 = img.frames{2};
%
%   See also IMPORTRAWIMAGE, IMPORTAUTO, CREATEDATASTRUCT

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
        error('parser:importTIFF:infofail', ...
            'imfinfo failed for "%s": %s', filepath, ME.message);
    end

    numFrames = numel(info);
    W         = info(1).Width;
    H         = info(1).Height;
    bitDepth  = info(1).BitDepth;

    % ════════════════════════════════════════════════════════════════
    %  STEP 2: Load pixel data
    % ════════════════════════════════════════════════════════════════
    try
        firstFrame = imread(char(filepath), 1);
    catch ME
        error('parser:importTIFF:readfail', ...
            'imread failed for "%s": %s', filepath, ME.message);
    end

    numChannels = size(firstFrame, 3);   % 1 = grayscale, 3 = RGB

    % Load remaining frames when this is a stack
    frames = {};
    if numFrames > 1
        frames = cell(1, numFrames);
        frames{1} = firstFrame;
        for k = 2:numFrames
            try
                frames{k} = imread(char(filepath), k);
            catch
                frames{k} = firstFrame * 0;   % zero-pad on read failure
                warning('parser:importTIFF:frameFail', ...
                    'Could not read frame %d of %d in "%s"; substituted zeros.', ...
                    k, numFrames, filepath);
            end
        end
    end

    pixels = firstFrame;

    % ════════════════════════════════════════════════════════════════
    %  STEP 3: Extract standard imfinfo metadata
    % ════════════════════════════════════════════════════════════════
    acquiParams = struct();

    % Standard TIFF fields from imfinfo struct (present in most TIFFs)
    stdFields = {'Compression', 'PhotometricInterpretation', ...
                 'DateTime', 'ImageDescription', ...
                 'XResolution', 'YResolution', 'ResolutionUnit', ...
                 'Software', 'Make', 'Model'};
    for k = 1:numel(stdFields)
        f = stdFields{k};
        if isfield(info(1), f) && ~isempty(info(1).(f))
            acquiParams.(f) = info(1).(f);
        end
    end

    % ════════════════════════════════════════════════════════════════
    %  STEP 4: Extract FEI/Thermo Fisher metadata from tag 34682
    % ════════════════════════════════════════════════════════════════
    pixelSize = NaN;
    pixelUnit = '';
    calibrated = false;

    feiTag = extractFEITag(info(1));
    if ~isempty(feiTag)
        acquiParams.feiMetadata = feiTag;

        % Extract PixelWidth (stored in metres by FEI)
        if isfield(feiTag, 'Scan') && isfield(feiTag.Scan, 'PixelWidth')
            pwStr = feiTag.Scan.PixelWidth;
            pw = str2double(pwStr);
            if ~isnan(pw) && pw > 0
                [pixelSize, pixelUnit] = convertMetresToDisplayUnit(pw);
                calibrated = true;
            end
        end

        % Fallback: check top-level PixelWidth (some FEI versions)
        if ~calibrated && isfield(feiTag, 'PixelWidth')
            pw = str2double(feiTag.PixelWidth);
            if ~isnan(pw) && pw > 0
                [pixelSize, pixelUnit] = convertMetresToDisplayUnit(pw);
                calibrated = true;
            end
        end
    end

    % ════════════════════════════════════════════════════════════════
    %  STEP 5: Build 1-D fallback (mean intensity per row)
    % ════════════════════════════════════════════════════════════════
    timeVec = (1:H)';

    if numChannels == 1
        pixFloat     = double(pixels);
        meanPerRow   = mean(pixFloat, 2);   % [H x 1]
    else
        % RGB: luminance = 0.299 R + 0.587 G + 0.114 B
        pixFloat   = double(pixels);
        luminance  = 0.299 * pixFloat(:,:,1) + ...
                     0.587 * pixFloat(:,:,2) + ...
                     0.114 * pixFloat(:,:,3);
        meanPerRow = mean(luminance, 2);
    end

    % ════════════════════════════════════════════════════════════════
    %  STEP 6: Assemble metadata struct
    % ════════════════════════════════════════════════════════════════
    meta.source        = char(filepath);
    meta.importDate    = datetime('now');
    meta.parserName    = 'importTIFF';
    meta.parserVersion = '1.0';
    meta.xColumnName   = 'Row';
    meta.xColumnUnit   = 'px';

    imgData.pixels      = pixels;
    imgData.bitDepth    = bitDepth;
    imgData.height      = H;
    imgData.width       = W;
    imgData.numChannels = numChannels;
    imgData.numFrames   = numFrames;
    imgData.frames      = frames;
    imgData.pixelSize   = pixelSize;
    imgData.pixelUnit   = pixelUnit;
    imgData.calibrated  = calibrated;
    imgData.acquiParams = acquiParams;

    meta.parserSpecific.isImage   = true;
    meta.parserSpecific.imageData = imgData;

    % ════════════════════════════════════════════════════════════════
    %  STEP 7: Build unified struct
    % ════════════════════════════════════════════════════════════════
    data = parser.createDataStruct(timeVec, meanPerRow, ...
        'labels',   {'Mean Intensity'}, ...
        'units',    {'counts'}, ...
        'metadata', meta);

    if options.Verbose
        fprintf('importTIFF: %dx%d px | %d-bit | %d frame(s) | calibrated=%d\n', ...
            W, H, bitDepth, numFrames, calibrated);
        if calibrated
            fprintf('  Pixel size: %.4g %s\n', pixelSize, pixelUnit);
        end
    end
end


% ════════════════════════════════════════════════════════════════════
%  LOCAL HELPER FUNCTIONS
% ════════════════════════════════════════════════════════════════════

function feiStruct = extractFEITag(infoEntry)
%EXTRACTFEITAG  Parse FEI/Thermo Fisher private TIFF tag 34682 into a struct.
%
%   Tag 34682 contains an ASCII key=value block with section headers in
%   square brackets, e.g.:
%       [Beam]
%       HV=15000
%       Spot=3
%       [Scan]
%       PixelWidth=4.93e-009
%
%   Returns a struct with one sub-struct per section, or empty struct on
%   failure.
    feiStruct = struct();

    % Try to get the unknown tags cell from imfinfo
    if ~isfield(infoEntry, 'UnknownTags')
        return;
    end

    tags = infoEntry.UnknownTags;
    if isempty(tags)
        return;
    end

    % UnknownTags is an array of structs with .ID and .Value fields
    tagText = '';
    for k = 1:numel(tags)
        if isfield(tags(k), 'ID') && tags(k).ID == 34682
            val = tags(k).Value;
            if ischar(val)
                tagText = val;
            elseif iscell(val) && ~isempty(val) && ischar(val{1})
                tagText = strjoin(val, newline);
            end
            break;
        end
    end

    if isempty(tagText)
        return;
    end

    % Parse the key=value / [Section] block
    lines   = strsplit(tagText, {'\n', '\r\n', '\r'});
    section = 'General';
    feiStruct.(section) = struct();

    for k = 1:numel(lines)
        ln = strtrim(lines{k});
        if isempty(ln)
            continue;
        end

        % Section header: [SectionName]
        secMatch = regexp(ln, '^\[(\w+)\]$', 'tokens', 'once');
        if ~isempty(secMatch)
            section = secMatch{1};
            if ~isfield(feiStruct, section)
                feiStruct.(section) = struct();
            end
            continue;
        end

        % key=value pair
        eqIdx = strfind(ln, '=');
        if ~isempty(eqIdx)
            key = strtrim(ln(1 : eqIdx(1)-1));
            val = strtrim(ln(eqIdx(1)+1 : end));

            % Sanitize key for use as struct field name
            key = regexprep(key, '[^a-zA-Z0-9_]', '_');
            if isempty(key) || ~isletter(key(1))
                key = ['x_' key]; %#ok<AGROW>
            end

            feiStruct.(section).(key) = val;
        end
    end
end


function [sz, unit] = convertMetresToDisplayUnit(metres)
%CONVERTMETRESTODISPLAYUNIT  Convert a pixel size in metres to a readable unit.
%   Selects nm, um, or mm based on magnitude.
    if metres < 1e-6
        sz   = metres * 1e9;
        unit = 'nm';
    elseif metres < 1e-3
        sz   = metres * 1e6;
        unit = 'um';
    else
        sz   = metres * 1e3;
        unit = 'mm';
    end
end
