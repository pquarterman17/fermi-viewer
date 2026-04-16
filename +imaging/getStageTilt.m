function [tiltDeg, source] = getStageTilt(imgInfo)
%GETSTAGETILT  Extract SEM stage tilt angle from image metadata.
%
%   Syntax:
%       [tiltDeg, source] = imaging.getStageTilt(imgInfo)
%
%   Reads the stage tilt angle from a unified-struct image's
%   metadata.parserSpecific.imageData entry (or a full data struct).
%   Supports FEI/Thermo Fisher TIFF tag 34682 metadata (stored under
%   acquiParams.feiMetadata.Stage.StageT or .StageTa) and Bruker BCF
%   metadata (metadata.parserSpecific.semParams.stageTilt_deg).
%
%   Inputs:
%       imgInfo — one of:
%          * imageData struct  (has .acquiParams field)
%          * full data struct  (from parser.importTIFF / importBCF)
%          * metadata struct   (from data.metadata)
%
%   Outputs:
%       tiltDeg — stage tilt in degrees, NaN if not available
%       source  — descriptive string: 'FEI StageT', 'Bruker Tilt', or ''
%
%   FEI StageT Unit Heuristic
%   ─────────────────────────
%   FEI tag values are stored as strings and the unit (radians vs degrees)
%   varies across instruments. If |value| < pi we assume radians and
%   convert; otherwise we treat it as degrees. Real FIB/SEM stage tilts
%   rarely exceed 70 degrees so the boundary is unambiguous in practice.
%
%   Examples:
%       data = parser.importTIFF('fib_cross_section.tif');
%       imgInfo = data.metadata.parserSpecific.imageData;
%       [tilt, src] = imaging.getStageTilt(imgInfo);
%       if ~isnan(tilt)
%           fprintf('Stage tilt: %.2f deg (source: %s)\n', tilt, src);
%       end
%
%   See also imaging.measureDistance, imaging.lineProfile

arguments
    imgInfo (1,1) struct
end

tiltDeg = NaN;
source  = '';

% Accept a full data struct, a metadata struct, or an imageData struct.
acquiParams = [];
semParams   = [];

if isfield(imgInfo, 'metadata') && isfield(imgInfo.metadata, 'parserSpecific')
    ps = imgInfo.metadata.parserSpecific;
    if isfield(ps, 'imageData') && isfield(ps.imageData, 'acquiParams')
        acquiParams = ps.imageData.acquiParams;
    end
    if isfield(ps, 'semParams')
        semParams = ps.semParams;
    end
elseif isfield(imgInfo, 'parserSpecific')
    ps = imgInfo.parserSpecific;
    if isfield(ps, 'imageData') && isfield(ps.imageData, 'acquiParams')
        acquiParams = ps.imageData.acquiParams;
    end
    if isfield(ps, 'semParams')
        semParams = ps.semParams;
    end
elseif isfield(imgInfo, 'acquiParams')
    acquiParams = imgInfo.acquiParams;
end

% ── FEI/Thermo Fisher ────────────────────────────────────────────────
if isstruct(acquiParams) && isfield(acquiParams, 'feiMetadata')
    fei = acquiParams.feiMetadata;
    if isstruct(fei) && isfield(fei, 'Stage') && isstruct(fei.Stage)
        candidates = {'StageT', 'StageTa', 'Tilt'};
        for k = 1:numel(candidates)
            if isfield(fei.Stage, candidates{k})
                raw = fei.Stage.(candidates{k});
                val = localParseScalar(raw);
                if ~isnan(val)
                    tiltDeg = localNormalizeAngle(val);
                    source  = sprintf('FEI %s', candidates{k});
                    return;
                end
            end
        end
    end
end

% ── Bruker BCF ───────────────────────────────────────────────────────
if isstruct(semParams) && isfield(semParams, 'stageTilt_deg')
    val = semParams.stageTilt_deg;
    if isnumeric(val) && isscalar(val) && ~isnan(val)
        tiltDeg = double(val);
        source  = 'Bruker Tilt';
        return;
    end
end

end


% ════════════════════════════════════════════════════════════════════════
%  LOCAL HELPERS
% ════════════════════════════════════════════════════════════════════════
function v = localParseScalar(raw)
    v = NaN;
    if isnumeric(raw) && isscalar(raw)
        v = double(raw);
    elseif ischar(raw) || isstring(raw)
        v = str2double(raw);
    end
end

function deg = localNormalizeAngle(val)
    % Heuristic: |val| < pi implies radians; otherwise already degrees.
    if abs(val) < pi
        deg = val * 180 / pi;
    else
        deg = val;
    end
end
