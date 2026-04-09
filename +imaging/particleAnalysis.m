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
    [L, n] = imaging.watershed(mask, ...
        MinMarkerDistance=options.MinMarkerDistance, ...
        Connectivity=options.Connectivity);
else
    [L, n] = imaging.connectedComponents(mask, ...
        Connectivity=options.Connectivity);
end

% ── Measure per component ──────────────────────────────────────────────
particles = struct('id', {}, 'area', {}, 'centroid', {}, 'bbox', {}, ...
    'equivDiameter', {}, 'meanIntensity', {}, ...
    'areaCalibrated', {}, 'diameterCalibrated', {});

[H, W] = size(L);
[RR, CC] = ndgrid(1:H, 1:W);

ps  = options.PixelSize;
hasCal = ~isnan(ps) && ps > 0;

kept = 0;
for lbl = 1:n
    sel = (L == lbl);
    area = sum(sel(:));
    if area < options.MinArea
        continue;
    end

    rs = RR(sel);
    cs = CC(sel);
    p.id        = lbl;
    p.area      = area;
    p.centroid  = [mean(rs), mean(cs)];
    p.bbox      = [min(rs), min(cs), max(rs), max(cs)];
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

% If any labels were dropped by MinArea, renumber `labels` compactly so
% the displayed map matches particles(k).id.
if kept < n
    newL = zeros(H, W);
    for k = 1:kept
        newL(L == particles(k).id) = k;
        particles(k).id = k;
    end
    L = newL;
end

result.mask         = mask;
result.labels       = L;
result.numParticles = kept;
result.threshold    = thr;
result.particles    = particles;
result.pixelSize    = ps;
result.pixelUnit    = options.PixelUnit;
end
