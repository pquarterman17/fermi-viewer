function [particles, labels, numKept] = regionStats(L, img, options)
%REGIONSTATS  Per-region measurements from a label matrix.
%
%   Syntax:
%       [particles, labels, numKept] = imaging.regionStats(L, img)
%       [...] = imaging.regionStats(L, img, MinArea=10)
%       [...] = imaging.regionStats(L, img, PixelSize=0.5, PixelUnit="nm")
%
%   Shared measurement core for region-based analysis. Given an integer
%   label matrix L (0 = background, 1..N = regions) and the intensity image
%   img, measures area, centroid, bounding box, equivalent circular
%   diameter, and mean intensity per region. Regions smaller than MinArea
%   are dropped and the returned label matrix is compactly renumbered so
%   labels(k) == particles(k).id == k.
%
%   This is called by both imaging.particleAnalysis (threshold-based
%   particle counting) and imaging.grains.grainStats (ML-segmented grains)
%   so the two share ONE measurement code path — calibration and the
%   equivDiameter formula can never silently drift between them.
%
%   No Image Processing Toolbox required.
%
%   Inputs:
%       L            — [H x W] integer label matrix (0 = background).
%       img          — [H x W] numeric intensity image (for meanIntensity).
%
%   Optional Name-Value:
%       MinArea      — minimum region area in pixels (default 1). Smaller
%                      regions are dropped and labels renumbered.
%       PixelSize    — physical size of one pixel (scalar, default NaN).
%                      When supplied, .areaCalibrated and
%                      .diameterCalibrated are populated.
%       PixelUnit    — string unit label for PixelSize (default "px").
%
%   Outputs:
%       particles    — [numKept x 1] struct array with fields:
%           .id              — compact label value (== row index k)
%           .area            — area in pixels
%           .centroid        — [row, col]
%           .bbox            — [rMin, cMin, rMax, cMax]
%           .equivDiameter   — sqrt(4*area/pi) in pixels
%           .meanIntensity   — mean img value within the region
%           .areaCalibrated      — area * PixelSize^2  (NaN if uncalibrated)
%           .diameterCalibrated  — equivDiameter * PixelSize (NaN if uncal.)
%       labels       — [H x W] compacted label matrix (0 = background).
%       numKept      — number of regions surviving the MinArea filter.
%
%   See also imaging.particleAnalysis, imaging.connectedComponents,
%            imaging.grains.grainStats

% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    L                    (:,:) {mustBeNumeric}
    img                  (:,:) {mustBeNumeric}
    options.MinArea      (1,1) double {mustBeNonnegative, mustBeInteger} = 1
    options.PixelSize    (1,1) double = NaN
    options.PixelUnit    (1,1) string = "px"
end

d = double(img);
L = double(L);
n = max(L(:));

particles = struct('id', {}, 'area', {}, 'centroid', {}, 'bbox', {}, ...
    'equivDiameter', {}, 'meanIntensity', {}, ...
    'areaCalibrated', {}, 'diameterCalibrated', {});

[H, W]   = size(L);
[RR, CC] = ndgrid(1:H, 1:W);

ps     = options.PixelSize;
hasCal = ~isnan(ps) && ps > 0;

kept = 0;
for lbl = 1:n
    sel  = (L == lbl);
    area = sum(sel(:));
    if area < options.MinArea
        continue;
    end

    rs = RR(sel);
    cs = CC(sel);
    p.id            = lbl;
    p.area          = area;
    p.centroid      = [mean(rs), mean(cs)];
    p.bbox          = [min(rs), min(cs), max(rs), max(cs)];
    p.equivDiameter = sqrt(4 * area / pi);
    p.meanIntensity = mean(d(sel));

    if hasCal
        p.areaCalibrated     = area * ps^2;
        p.diameterCalibrated = p.equivDiameter * ps;
    else
        p.areaCalibrated     = NaN;
        p.diameterCalibrated = NaN;
    end

    kept = kept + 1;
    particles(kept, 1) = p; %#ok<AGROW>
end

% Compactly renumber the label matrix so labels(k) == particles(k).id == k.
labels = L;
if kept < n
    labels = zeros(H, W);
    for k = 1:kept
        labels(L == particles(k).id) = k;
        particles(k).id = k;
    end
end

numKept = kept;
end
