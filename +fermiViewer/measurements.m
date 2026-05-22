function result = measurements(action, varargin)
%MEASUREMENTS  Pure-computation helpers for FermiViewer measurement tools.
%
% Syntax:
%   angleDeg = emViewer.measurements('computeAngle', v1, v2, tiltDeg, tiltAxis, tiltGeom)
%   [arcX, arcY, midAngle, arcRadius] = emViewer.measurements('arcGeometry', pts, v1, v2)
%   totalDist = emViewer.measurements('polylineLength', pts, tiltDeg, tiltAxis, tiltGeom)
%   stats = emViewer.measurements('aggregateStats', measurementCellArray)
%
% All functions are purely computational — no GUI, no appData access.
%
% Inputs (by action):
%   'computeAngle'
%     v1, v2      — 1x2 vectors from vertex to each ray endpoint (image pixels)
%     tiltDeg     — tilt angle in degrees (0 = no correction)
%     tiltAxis    — 'X' or 'Y' — which axis is foreshortened
%     tiltGeom    — 'CrossSection' or 'Surface' — tilt geometry
%   'arcGeometry'
%     pts         — 3x2 [vertex; ray1end; ray2end] in image pixels
%     v1, v2      — 1x2 direction vectors (pts(2,:)-pts(1,:), etc.)
%   'polylineLength'
%     pts         — Nx2 vertex coordinates in image pixels
%     tiltDeg     — tilt angle in degrees (0 = no correction)
%     tiltAxis    — 'X' or 'Y'
%     tiltGeom    — 'CrossSection' or 'Surface'
%   'aggregateStats'
%     meas        — cell array of measurement structs with .distance field
%
% Outputs:
%   angleDeg    — angle at vertex in degrees
%   arcX, arcY  — 1x40 arc coordinates for overlay visualization
%   midAngle    — angle (degrees) at arc midpoint, for label placement
%   arcRadius   — arc radius in pixels
%   totalDist   — polyline path length in pixels
%   stats       — struct with .distances, .count, .mean, .std, .min, .max
%
% Examples:
%   v1 = [10 0]; v2 = [0 10];
%   deg = emViewer.measurements('computeAngle', v1, v2, 0, 'Y', 'CrossSection')
%   % deg == 90
%
%   pts = [0 0; 3 0; 4 0];
%   dist = emViewer.measurements('polylineLength', pts, 0, 'Y', 'CrossSection')
%   % dist == 4  (3 + 1)

% ════════════════════════════════════════════════════════════════════
switch lower(action)
    case 'computeangle'
        result = computeAngle(varargin{:});
    case 'arcgeometry'
        [result.arcX, result.arcY, result.midAngle, result.arcRadius] = ...
            arcGeometry(varargin{:});
    case 'polylinelength'
        result = polylineLength(varargin{:});
    case 'aggregatestats'
        result = aggregateStats(varargin{:});
    otherwise
        error('emViewer:measurements:unknownAction', ...
            'Unknown action "%s". Valid: computeAngle, arcGeometry, polylineLength, aggregateStats', ...
            action);
end
end

% ════════════════════════════════════════════════════════════════════
%  computeAngle — tilt-corrected angle at vertex between two rays
% ════════════════════════════════════════════════════════════════════
function angleDeg = computeAngle(v1, v2, tiltDeg, tiltAxis, tiltGeom)
%COMPUTEANGLE  Angle between vectors v1 and v2 with optional tilt correction.
%
% When tiltDeg is nonzero, one image axis is foreshortened. We scale that
% axis before computing the dot-product angle so the result reflects the
% true sample-frame geometry, not the projected image geometry.
% Cross-section: scale = 1/sin(tilt). Plan-view surface: scale = 1/cos(tilt).
%
% The arc visualization in FermiViewer uses raw image-space vectors; only
% the numeric angle value uses corrected vectors.

vc1 = v1;
vc2 = v2;

if tiltDeg ~= 0
    if strcmpi(tiltGeom, 'Surface')
        scl = 1 / cosd(tiltDeg);
    else
        scl = 1 / sind(tiltDeg);
    end
    if strcmpi(tiltAxis, 'Y')
        vc1(2) = v1(2) * scl;
        vc2(2) = v2(2) * scl;
    else
        vc1(1) = v1(1) * scl;
        vc2(1) = v2(1) * scl;
    end
end

nrm = norm(vc1) * norm(vc2);
if nrm < eps
    angleDeg = NaN;
    return;
end
cosA = dot(vc1, vc2) / nrm;
cosA = max(-1, min(1, cosA));   % clamp for numerical safety
angleDeg = acosd(cosA);
end

% ════════════════════════════════════════════════════════════════════
%  arcGeometry — arc coordinates for angle visualization
% ════════════════════════════════════════════════════════════════════
function [arcX, arcY, midAngle, arcRadius] = arcGeometry(pts, v1, v2)
%ARCGEOMETRY  Return arc coordinates (image pixels) for angle annotation.
%
% Uses raw image-space vectors so the arc aligns visually with what the
% user drew, regardless of tilt correction applied to the numeric value.
%
% arcRadius is 30% of the shorter ray, clamped so the arc stays visible.
% The arc takes the short path between the two ray directions.

arcRadius = min(norm(v1), norm(v2)) * 0.3;
a1 = atan2d(v1(2), v1(1));
a2 = atan2d(v2(2), v2(1));

% Ensure arc goes the short way around
if abs(a2 - a1) > 180
    if a2 > a1
        a1 = a1 + 360;
    else
        a2 = a2 + 360;
    end
end

arcAngles = linspace(a1, a2, 40);
arcX = pts(1,1) + arcRadius * cosd(arcAngles);
arcY = pts(1,2) + arcRadius * sind(arcAngles);
midAngle = (a1 + a2) / 2;
end

% ════════════════════════════════════════════════════════════════════
%  polylineLength — tilt-corrected sum of segment lengths
% ════════════════════════════════════════════════════════════════════
function totalDist = polylineLength(pts, tiltDeg, tiltAxis, tiltGeom)
%POLYLINELENGTH  Sum true path length of an N-point polyline.
%
% Correcting each segment individually (not the bounding box) is correct:
% tilt stretches one axis uniformly, so total true-path = sum of
% true-segment-lengths.
%
% When tiltDeg == 0, falls back to plain Euclidean distance.

tiltActive = tiltDeg ~= 0;
totalDist = 0;
for si = 2:size(pts, 1)
    if tiltActive
        totalDist = totalDist + imaging.measureDistance( ...
            pts(si-1,1), pts(si-1,2), pts(si,1), pts(si,2), ...
            TiltAngle=tiltDeg, TiltAxis=tiltAxis, Geometry=tiltGeom);
    else
        totalDist = totalDist + sqrt( ...
            (pts(si,1) - pts(si-1,1))^2 + ...
            (pts(si,2) - pts(si-1,2))^2);
    end
end
end

% ════════════════════════════════════════════════════════════════════
%  aggregateStats — collect distances and compute summary statistics
% ════════════════════════════════════════════════════════════════════
function stats = aggregateStats(meas)
%AGGREGATESTATS  Extract distances from measurement cell array and compute stats.
%
% meas — cell array of measurement structs (appData.overlays.measurements).
%        Each element may optionally have a .distance field.
%
% Returns a struct with:
%   .distances — row vector of finite distance values
%   .count     — number of distance measurements
%   .mean/.std/.min/.max — aggregate statistics (NaN when count == 0)

dists = [];
for mi = 1:numel(meas)
    m = meas{mi};
    if isfield(m, 'distance') && ~isnan(m.distance)
        dists(end+1) = m.distance; %#ok<AGROW>
    end
end

stats.distances = dists;
stats.count     = numel(dists);
if ~isempty(dists)
    stats.mean = mean(dists);
    stats.std  = std(dists);
    stats.min  = min(dists);
    stats.max  = max(dists);
else
    stats.mean = NaN;
    stats.std  = NaN;
    stats.min  = NaN;
    stats.max  = NaN;
end
end
