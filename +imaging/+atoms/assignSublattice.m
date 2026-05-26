function labels = assignSublattice(features, k, opts)
%ASSIGNSUBLATTICE  Group atom columns into k sublattices by intensity.
%
%   Syntax:
%       labels = imaging.atoms.assignSublattice(features, k)
%       labels = imaging.atoms.assignSublattice(features, k, Seed=0)
%
%   Clusters columns into k sublattices (e.g. cation/anion in a perovskite)
%   using k-means on the supplied per-column feature(s) — typically the
%   fitted Gaussian amplitude. Wraps imaging.ml.kmeansLite (pure base
%   MATLAB, deterministic for a given Seed); standardizes features first so
%   no single column dominates.
%
%   Inputs:
%       features — [N x 1] or [N x F] per-column features (amplitude, and
%                  optionally sigma / local contrast).
%       k        — number of sublattices (>= 1). k==1 returns all ones.
%
%   Optional Name-Value:
%       Seed     — RNG seed for reproducible clusters (default 0).
%
%   Output:
%       labels   — [N x 1] integer sublattice label in 1..k, ordered so that
%                  label 1 has the highest mean feature (brightest columns).

arguments
    features          (:,:) double
    k          (1,1) double {mustBePositive, mustBeInteger}
    opts.Seed  (1,1) double = 0
end

N = size(features, 1);
if k == 1 || N == 0
    labels = ones(N, 1);
    return;
end

Xs = imaging.ml.standardizeFeatures(features);
[raw, ~] = imaging.ml.kmeansLite(Xs, k, Seed=opts.Seed);

% Re-order labels so 1 = brightest sublattice (stable, interpretable).
meanFeat = zeros(k, 1);
primary = features(:, 1);
for c = 1:k
    meanFeat(c) = mean(primary(raw == c));
end
[~, rank] = sort(meanFeat, 'descend');
remap = zeros(k, 1);
remap(rank) = 1:k;
labels = remap(raw);
end
