function result = grainStats(labels, img, options)
%GRAINSTATS  Grain counts, boundaries, and size distribution from a label map.
%
%   Syntax:
%       result = imaging.grains.grainStats(labels, img)
%       result = imaging.grains.grainStats(labels, img, PixelSize=0.2, PixelUnit="nm")
%
%   Turns a grain label map (from imaging.grains.segmentAuto or
%   segmentTrained) into the numbers a microscopist wants: how many grains,
%   their size distribution, and the grain-boundary network. Per-grain
%   measurements come from the SHARED imaging.regionStats core (same code
%   path as particle counting — no drift).
%
%   Boundaries are the interfaces where the label changes between two
%   adjacent grains (background excluded). Both sides of an interface are
%   marked, so boundaryLengthPx is an APPROXIMATE interface length in pixels
%   (it roughly double-counts a one-pixel-wide seam); use it for relative
%   comparison and calibrated trends, not absolute metrology.
%
%   No Image Processing Toolbox required.
%
%   Inputs:
%       labels        — [H x W] integer grain label map (0 = background).
%       img           — [H x W] intensity image (for per-grain meanIntensity).
%
%   Optional Name-Value:
%       PixelSize     — physical size of one pixel (default NaN). Populates
%                       calibrated area/diameter/length fields when set.
%       PixelUnit     — unit label for PixelSize (default "px").
%       MinArea       — drop grains below this area in pixels (default 1).
%       Connectivity  — 4 or 8 (default 8) for boundary-segment labeling.
%
%   Output: result — struct with fields:
%       .numGrains            — grain count after MinArea.
%       .grains               — [numGrains x 1] struct array (imaging.regionStats
%                               format: id/area/centroid/bbox/equivDiameter/
%                               meanIntensity/areaCalibrated/diameterCalibrated).
%       .labels               — [H x W] compacted label map (1..numGrains).
%       .areaPx               — [numGrains x 1] grain areas in pixels.
%       .equivDiameterPx      — [numGrains x 1] equivalent diameters in pixels.
%       .areaCalibrated       — [numGrains x 1] calibrated areas (NaN if uncal.).
%       .diameterCalibrated   — [numGrains x 1] calibrated diameters (NaN if uncal.).
%       .boundaryMask         — [H x W] logical grain-boundary network.
%       .numBoundarySegments  — connected components of the boundary network.
%       .boundaryLengthPx     — boundary pixel count (approximate length).
%       .boundaryLengthCalibrated — boundaryLengthPx * PixelSize (NaN if uncal.).
%       .pixelSize, .pixelUnit
%
%   See also imaging.grains.segmentAuto, imaging.regionStats,
%            imaging.connectedComponents

arguments
    labels                (:,:) {mustBeNumeric}
    img                   (:,:) {mustBeNumeric}
    options.PixelSize     (1,1) double = NaN
    options.PixelUnit     (1,1) string = "px"
    options.MinArea       (1,1) double {mustBeNonnegative, mustBeInteger} = 1
    options.Connectivity  (1,1) double {mustBeMember(options.Connectivity, [4, 8])} = 8
end

% ── Per-grain measurements (shared core) ────────────────────────────────
[grains, L, numGrains] = imaging.regionStats(labels, img, ...
    MinArea=options.MinArea, ...
    PixelSize=options.PixelSize, ...
    PixelUnit=options.PixelUnit);

% ── Grain-boundary network: label changes between adjacent grains ───────
% Slice-based neighbour comparison (no circshift wrap-around at borders).
[H, W]   = size(L);
boundary = false(H, W);

dh = (L(:, 1:end-1) ~= L(:, 2:end)) & (L(:, 1:end-1) > 0) & (L(:, 2:end) > 0);
boundary(:, 1:end-1) = boundary(:, 1:end-1) | dh;
boundary(:, 2:end)   = boundary(:, 2:end)   | dh;

dv = (L(1:end-1, :) ~= L(2:end, :)) & (L(1:end-1, :) > 0) & (L(2:end, :) > 0);
boundary(1:end-1, :) = boundary(1:end-1, :) | dv;
boundary(2:end, :)   = boundary(2:end, :)   | dv;

[~, numBoundarySegments] = imaging.connectedComponents(boundary, ...
    Connectivity=options.Connectivity);
boundaryLengthPx = sum(boundary(:));

% ── Calibration ─────────────────────────────────────────────────────────
ps     = options.PixelSize;
hasCal = ~isnan(ps) && ps > 0;
if hasCal
    boundaryLengthCalibrated = boundaryLengthPx * ps;
else
    boundaryLengthCalibrated = NaN;
end

% ── Convenience size-distribution vectors ───────────────────────────────
if numGrains > 0
    areaPx             = [grains.area]';
    equivDiameterPx    = [grains.equivDiameter]';
    areaCalibrated     = [grains.areaCalibrated]';
    diameterCalibrated = [grains.diameterCalibrated]';
else
    areaPx = []; equivDiameterPx = [];
    areaCalibrated = []; diameterCalibrated = [];
end

result = struct( ...
    'numGrains',                numGrains, ...
    'grains',                   {grains}, ...
    'labels',                   L, ...
    'areaPx',                   areaPx, ...
    'equivDiameterPx',          equivDiameterPx, ...
    'areaCalibrated',           areaCalibrated, ...
    'diameterCalibrated',       diameterCalibrated, ...
    'boundaryMask',             boundary, ...
    'numBoundarySegments',      numBoundarySegments, ...
    'boundaryLengthPx',         boundaryLengthPx, ...
    'boundaryLengthCalibrated', boundaryLengthCalibrated, ...
    'pixelSize',                ps, ...
    'pixelUnit',                options.PixelUnit);
end
