function result = particleAnalysis(img, options)
%PARTICLEANALYSIS  Threshold an image and measure per-particle statistics.
%
%   Syntax:
%       result = imaging.particleAnalysis(img)
%       result = imaging.particleAnalysis(img, Threshold=0.5)
%       result = imaging.particleAnalysis(img, Polarity="dark", MinArea=10)
%       result = imaging.particleAnalysis(img, PixelSize=0.1, PixelUnit="nm")
%
%   Pipeline:
%     1. Threshold the image. If Threshold is empty (default), two-class
%        Otsu (imaging.multiOtsu) picks the threshold automatically.
%     2. Pick the foreground side via Polarity ("bright" = pixels above
%        threshold, "dark" = pixels below).
%     3. Label connected components with imaging.connectedComponents
%        (Connectivity 4 or 8).
%     4. Measure per-component area, centroid, bounding box, equivalent
%        circular diameter, and mean intensity within the region.
%     5. Drop components smaller than MinArea (pixels).
%
%   No Image Processing Toolbox required.
%
%   Inputs:
%       img         — [H x W] numeric matrix (grayscale)
%
%   Optional Name-Value:
%       Threshold    — scalar threshold in the image's original intensity
%                      range. Empty (default) → Otsu-chosen automatically.
%       Polarity     — "bright" (default) or "dark" — which side of the
%                      threshold is considered foreground.
%       Connectivity — 4 or 8 (default 8).
%       MinArea      — minimum component area in pixels (default 1). Smaller
%                      components are dropped from the output.
%       PixelSize    — physical size of one pixel (scalar, default NaN).
%                      When supplied, .areaCalibrated and
%                      .diameterCalibrated are added to each particle.
%       PixelUnit    — string unit label for PixelSize (default "px").
%       Watershed    — if true, split touching particles via marker-
%                      controlled watershed on the distance transform
%                      of the mask. Default: false.
%       MinMarkerDistance — minimum marker separation in pixels when
%                      Watershed=true (default 3). Larger values merge
%                      closer peaks into a single particle.
%
%   Output:
%       result — struct with fields:
%         .mask          — [H x W] logical foreground mask
%         .labels        — [H x W] double label image (0 = background)
%         .numParticles  — scalar count after MinArea filter
%         .threshold     — scalar threshold actually used
%         .particles     — [numParticles x 1] struct array with fields:
%             .id              — label value in .labels
%             .area            — area in pixels
%             .centroid        — [row, col]
%             .bbox            — [rMin, cMin, rMax, cMax]
%             .equivDiameter   — sqrt(4*area/pi) in pixels
%             .meanIntensity   — mean pixel value within the component
%             .areaCalibrated      — area * PixelSize^2 (if PixelSize set)
%             .diameterCalibrated  — equivDiameter * PixelSize (if set)
%         .pixelSize     — PixelSize (or NaN)
%         .pixelUnit     — PixelUnit string
%
%   Examples:
%       r = imaging.particleAnalysis(img);                 % Otsu + bright
%       r = imaging.particleAnalysis(img, Polarity="dark", MinArea=20);
%       r = imaging.particleAnalysis(img, Threshold=120);
%
%       % Calibrated measurements
%       r = imaging.particleAnalysis(img, PixelSize=0.5, PixelUnit="nm");
%       diameters = [r.particles.diameterCalibrated];
%
%   See also imaging.connectedComponents, imaging.multiOtsu

% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    img                          (:,:) {mustBeNumeric}
    options.Threshold            double = []
    options.Polarity             (1,1) string {mustBeMember(options.Polarity, ["bright","dark"])} = "bright"
    options.Connectivity         (1,1) double {mustBeMember(options.Connectivity, [4,8])} = 8
    options.MinArea              (1,1) double {mustBeNonnegative, mustBeInteger} = 1
    options.PixelSize            (1,1) double = NaN
    options.PixelUnit            (1,1) string = "px"
    options.Watershed            (1,1) logical = false
    options.MinMarkerDistance    (1,1) double {mustBePositive} = 3
end

d = double(img);

% ── Threshold ──────────────────────────────────────────────────────────
if isempty(options.Threshold)
    ots = imaging.multiOtsu(d, NumClasses=2);
    thr = ots.thresholds(1);
else
    thr = double(options.Threshold);
end

if options.Polarity == "bright"
    mask = d >= thr;
else
    mask = d < thr;
end

% ── Label ──────────────────────────────────────────────────────────────
if options.Watershed
    % Watershed split: touching particles become separate regions
    L = imaging.watershed(mask, ...
        MinMarkerDistance=options.MinMarkerDistance, ...
        Connectivity=options.Connectivity);
else
    L = imaging.connectedComponents(mask, ...
        Connectivity=options.Connectivity);
end

% ── Measure per component ──────────────────────────────────────────────
% Shared measurement core (imaging.regionStats) — also used by
% imaging.grains.grainStats so the two never drift. n is unused now that
% regionStats derives the region count internally.
[particles, L, kept] = imaging.regionStats(L, d, ...
    MinArea=options.MinArea, ...
    PixelSize=options.PixelSize, ...
    PixelUnit=options.PixelUnit);

result.mask         = mask;
result.labels       = L;
result.numParticles = kept;
result.threshold    = thr;
result.particles    = particles;
result.pixelSize    = options.PixelSize;
result.pixelUnit    = options.PixelUnit;
end
