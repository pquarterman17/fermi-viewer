function [features, names] = extractGrainFeatures(img, options)
%EXTRACTGRAINFEATURES  Per-pixel feature stack for grain segmentation.
%
%   Syntax:
%       [features, names] = imaging.grains.extractGrainFeatures(img)
%       [...] = imaging.grains.extractGrainFeatures(img, Scales=[2 4 8])
%
%   Builds an [H x W x F] feature cube describing each pixel by intensity,
%   texture, gradient (boundary), and local lattice orientation, computed at
%   several spatial scales. This is the shared front-end for BOTH grain
%   segmentation modes (segmentAuto's clustering and segmentTrained's
%   classifier) — they differ only in what they do with this cube.
%
%   Features (F = 2 + 5*numel(Scales)):
%       scale-independent:
%           intensity   — raw pixel value
%           gradMag     — gradient magnitude (sqrt(Ix^2 + Iy^2))
%       per scale s in Scales:
%           mean_s      — Gaussian local mean (brightness contrast)
%           std_s       — Gaussian local std  (texture roughness)
%           coh_s       — structure-tensor coherence (orientation strength)
%           ocos_s      — coherence .* cos(2*theta)  (orientation, x)
%           osin_s      — coherence .* sin(2*theta)  (orientation, y)
%
%   The orientation is encoded as coherence-weighted (cos 2t, sin 2t) rather
%   than the raw angle: (a) the 2t makes it pi-periodic (a lattice at 10deg
%   equals one at 190deg), avoiding the wrap-around discontinuity that would
%   confuse a Euclidean clusterer, and (b) the coherence weight suppresses
%   spurious orientation in disordered / boundary pixels.
%
%   No Image Processing Toolbox required (reuses imaging.applyGaussian and
%   imaging.structureTensor).
%
%   Inputs:
%       img           — [H x W] numeric grayscale image.
%
%   Optional Name-Value:
%       Scales        — vector of Gaussian scales in pixels (default [2 4]).
%                       Add larger scales for coarser grains.
%       GradientSigma — pre-smoothing before gradients, in pixels (default 0).
%                       Use ~1 on noisy data.
%
%   Outputs:
%       features      — [H x W x F] double feature cube.
%       names         — {1 x F} cellstr of feature names (column order).
%
%   See also imaging.grains.segmentAuto, imaging.structureTensor,
%            imaging.ml.standardizeFeatures

arguments
    img                   (:,:) {mustBeNumeric}
    options.Scales        (1,:) double {mustBePositive} = [2 4]
    options.GradientSigma (1,1) double {mustBeNonnegative} = 0
end

d = double(img);
if options.GradientSigma > 0
    d = imaging.applyGaussian(d, Sigma=options.GradientSigma);
end

% ── Scale-independent features ──────────────────────────────────────────
[Ix, Iy] = gradient(d);
gradMag  = sqrt(Ix.^2 + Iy.^2);

layers = {d, gradMag};
names  = {'intensity', 'gradMag'};

% ── Per-scale features ──────────────────────────────────────────────────
for s = options.Scales
    localMean = imaging.applyGaussian(d, Sigma=s);
    localMsq  = imaging.applyGaussian(d.^2, Sigma=s);
    localStd  = sqrt(max(localMsq - localMean.^2, 0));

    st   = imaging.structureTensor(d, Sigma=s);
    ocos = st.coherence .* cos(2 * st.orientation);
    osin = st.coherence .* sin(2 * st.orientation);

    tag = num2str(s);
    layers = [layers, {localMean, localStd, st.coherence, ocos, osin}]; %#ok<AGROW>
    names  = [names,  { ['mean_' tag], ['std_' tag], ['coh_' tag], ...
                        ['ocos_' tag], ['osin_' tag] }];               %#ok<AGROW>
end

features = cat(3, layers{:});
end
