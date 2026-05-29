function key = extractCalibrationKey(src)
%EXTRACTCALIBRATIONKEY  Pull (instrument, mode, mag|camera-length) from metadata.
%
%   key = fermiViewer.calibration.extractCalibrationKey(src)
%
%   Inspects an image's acquisition metadata and returns the lookup key
%   used by the calibration database. `src` may be:
%     • a full parser data struct (digs into
%       .metadata.parserSpecific.imageData), or
%     • an imageData struct directly (has .acquiParams or .pixels).
%
%   Returns a scalar struct:
%     .found       logical  — true if a magnification or camera length was found
%     .instrument  char     — microscope/system name ('' if unknown)
%     .mode        char     — 'imaging' (mag) or 'diffraction' (camera length)
%     .keyType     char     — 'mag' | 'cameraLength'
%     .keyValue    double   — magnification (×) or camera length (mm); NaN if none
%
%   Metadata field names vary by vendor (Gatan DM harvests ImageTags into
%   underscore-safe names; FEI/Bruker use their own), so the scan is
%   name-heuristic: any scalar numeric field whose name contains
%   "magnification" (preferred) or "mag" is taken as magnification; any
%   whose name contains "camera" together with "length"/"len" is taken as
%   camera length. Instrument is the first char field whose name contains
%   "microscope"+"name", "instrument", or "system".
%
%   Magnification (imaging) takes precedence over camera length when both
%   are present, since imaging is the common case.
%
% See also FERMIVIEWER.CALIBRATION.CALIBRATIONSTORE

    key = struct('found', false, 'instrument', '', 'mode', 'imaging', ...
                 'keyType', 'mag', 'keyValue', NaN);

    imgData = resolveImageData(src);
    if isempty(imgData), return; end

    % Gather candidate (name, value) pairs from imageData top-level fields
    % and from the nested acquiParams struct.
    [names, vals] = collectFields(imgData);
    if isfield(imgData, 'acquiParams') && isstruct(imgData.acquiParams)
        [n2, v2] = collectFields(imgData.acquiParams);
        names = [names, n2];
        vals  = [vals,  v2];
    end
    if isempty(names), return; end

    lower_ = lower(names);

    % ── instrument name (first matching char field) ─────────────────────
    for k = 1:numel(names)
        if ischar(vals{k}) && ~isempty(strtrim(vals{k}))
            nm = lower_{k};
            if (contains(nm, 'microscope') && contains(nm, 'name')) || ...
                    contains(nm, 'instrument') || contains(nm, 'system')
                key.instrument = strtrim(vals{k});
                break;
            end
        end
    end

    % ── magnification (preferred) ───────────────────────────────────────
    magVal = pickNumeric(lower_, vals, {'magnification'});
    if isnan(magVal)
        magVal = pickNumeric(lower_, vals, {'mag'});
    end
    if fermiViewer.calibration.isValidPixelSize(magVal)
        key.found    = true;
        key.mode     = 'imaging';
        key.keyType  = 'mag';
        key.keyValue = magVal;
        return;
    end

    % ── camera length (diffraction) ─────────────────────────────────────
    camVal = NaN;
    for k = 1:numel(names)
        nm = lower_{k};
        if contains(nm, 'camera') && (contains(nm, 'length') || contains(nm, 'len')) ...
                && isnumeric(vals{k}) && isscalar(vals{k}) && isfinite(vals{k}) && vals{k} > 0
            camVal = double(vals{k});
            break;
        end
    end
    if fermiViewer.calibration.isValidPixelSize(camVal)
        key.found    = true;
        key.mode     = 'diffraction';
        key.keyType  = 'cameraLength';
        key.keyValue = camVal;
    end
end

% ════════════════════════════════════════════════════════════════════════
function imgData = resolveImageData(src)
    imgData = [];
    if ~isstruct(src), return; end
    if isfield(src, 'metadata') && isstruct(src.metadata) && ...
            isfield(src.metadata, 'parserSpecific') && ...
            isstruct(src.metadata.parserSpecific) && ...
            isfield(src.metadata.parserSpecific, 'imageData') && ...
            isstruct(src.metadata.parserSpecific.imageData)
        imgData = src.metadata.parserSpecific.imageData;
    elseif isfield(src, 'acquiParams') || isfield(src, 'pixels') || ...
            isfield(src, 'pixelSize')
        imgData = src;   % already an imageData struct
    end
end

function [names, vals] = collectFields(s)
%COLLECTFIELDS  Scalar numeric / char fields of a struct as parallel lists.
    names = {};
    vals  = {};
    if ~isstruct(s) || ~isscalar(s), return; end
    fn = fieldnames(s);
    for k = 1:numel(fn)
        v = s.(fn{k});
        if (isnumeric(v) && isscalar(v)) || ischar(v)
            names{end+1} = fn{k}; %#ok<AGROW>
            vals{end+1}  = v;     %#ok<AGROW>
        end
    end
end

function val = pickNumeric(lowerNames, vals, needles)
%PICKNUMERIC  First positive scalar numeric whose name contains any needle.
    val = NaN;
    for k = 1:numel(lowerNames)
        v = vals{k};
        if ~(isnumeric(v) && isscalar(v) && isfinite(v) && v > 0), continue; end
        for n = 1:numel(needles)
            if contains(lowerNames{k}, needles{n})
                val = double(v);
                return;
            end
        end
    end
end
