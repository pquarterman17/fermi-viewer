function [labels, info] = segmentAuto(img, options)
%SEGMENTAUTO  Unsupervised grain segmentation via feature clustering.
%
%   Syntax:
%       [labels, info] = imaging.grains.segmentAuto(img)
%       [labels, info] = imaging.grains.segmentAuto(img, K=5, Scales=[2 4 8])
%       [labels, info] = imaging.grains.segmentAuto(img, Features=cube)
%
%   Pipeline:
%     1. Build the per-pixel feature cube (imaging.grains.extractGrainFeatures),
%        or reuse a precomputed one passed via Features.
%     2. Standardize features (imaging.ml.standardizeFeatures).
%     3. Cluster pixels into K classes (imaging.ml.kmeansLite). Clusters are
%        grain TYPES (similar appearance/orientation), not grain instances.
%     4. Within each cluster, label spatially connected components
%        (imaging.connectedComponents) so two separate grains that happen to
%        share a cluster become distinct grains.
%     5. Drop components below MinArea. The result tiles the image with one
%        integer label per grain; boundaries are the lines where the label
%        changes (see imaging.grains.grainStats).
%
%   Deterministic for a given Seed (kmeansLite uses a private RandStream).
%   No Image Processing Toolbox required.
%
%   Inputs:
%       img            — [H x W] numeric grayscale image.
%
%   Optional Name-Value:
%       K              — number of feature clusters (grain types), default 4.
%                        Raise if distinct grains are being merged; lower if
%                        single grains are fragmenting.
%       Scales         — feature scales in pixels (default [2 4]); ignored
%                        when Features is supplied.
%       GradientSigma  — pre-smoothing for features (default 0).
%       Features       — [H x W x F] precomputed feature cube (default []:
%                        compute internally). Lets the GUI reuse its cache.
%       Seed           — RNG seed (default 0) for reproducible clustering.
%       Replicates     — k-means restarts, keep best (default 3).
%       MinArea        — minimum grain area in pixels (default 25). Smaller
%                        connected regions are dropped (label 0).
%       Connectivity   — 4 or 8 (default 8) for connected components.
%
%   Outputs:
%       labels         — [H x W] grain label map (0 = dropped/background,
%                        1..numGrains otherwise).
%       info           — struct: .numGrains, .K, .clusterMap [H x W],
%                        .inertia (k-means within-cluster SS).
%
%   See also imaging.grains.extractGrainFeatures, imaging.grains.grainStats,
%            imaging.ml.kmeansLite

arguments
    img                   (:,:) {mustBeNumeric}
    options.K             (1,1) double {mustBePositive, mustBeInteger} = 4
    options.Scales        (1,:) double {mustBePositive} = [2 4]
    options.GradientSigma (1,1) double {mustBeNonnegative} = 0
    options.Features      double = []
    options.Seed          (1,1) double {mustBeInteger} = 0
    options.Replicates    (1,1) double {mustBePositive, mustBeInteger} = 3
    options.MinArea       (1,1) double {mustBeNonnegative, mustBeInteger} = 25
    options.Connectivity  (1,1) double {mustBeMember(options.Connectivity, [4, 8])} = 8
end

% ── Features ────────────────────────────────────────────────────────────
if isempty(options.Features)
    feats = imaging.grains.extractGrainFeatures(img, ...
        Scales=options.Scales, GradientSigma=options.GradientSigma);
else
    feats = double(options.Features);
end
[H, W, F] = size(feats);

% ── Cluster ─────────────────────────────────────────────────────────────
X = reshape(feats, H * W, F);
Z = imaging.ml.standardizeFeatures(X);
[cl, ~, kinfo] = imaging.ml.kmeansLite(Z, options.K, ...
    Seed=options.Seed, Replicates=options.Replicates);
clusterMap = reshape(cl, H, W);

% ── Connected components within each cluster → individual grains ────────
labels = zeros(H, W);
g = 0;
for c = 1:kinfo.k
    mask = (clusterMap == c);
    if ~any(mask(:))
        continue;
    end
    [Lc, nc] = imaging.connectedComponents(mask, Connectivity=options.Connectivity);
    for j = 1:nc
        comp = (Lc == j);
        if sum(comp(:)) >= options.MinArea
            g = g + 1;
            labels(comp) = g;
        end
    end
end

info = struct( ...
    'numGrains',  g, ...
    'K',          kinfo.k, ...
    'clusterMap', clusterMap, ...
    'inertia',    kinfo.inertia);
end
