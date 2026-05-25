function [labels, centers, info] = kmeansLite(X, k, options)
%KMEANSLITE  k-means clustering (k-means++ init), pure base MATLAB.
%
%   Syntax:
%       [labels, centers, info] = imaging.ml.kmeansLite(X, k)
%       [...] = imaging.ml.kmeansLite(X, k, Seed=7, Replicates=5)
%
%   Lloyd's algorithm with k-means++ seeding. Deterministic for a given
%   Seed (uses a private RandStream — never touches the global RNG, so it
%   won't perturb other code's randomness). A reusable learning kernel
%   (NOT grain-specific): also intended for EDS phase clustering,
%   diffraction-pattern grouping, etc.
%
%   No Statistics Toolbox required: no kmeans/pdist2/randsample. Pairwise
%   squared distances use the (a-b)^2 = a^2 + b^2 - 2ab expansion.
%
%   Inputs:
%       X            — [N x F] data matrix (N samples, F features). Standardize
%                      first (imaging.ml.standardizeFeatures) so no single
%                      feature dominates the Euclidean distance.
%       k            — number of clusters (clamped to N if larger).
%
%   Optional Name-Value:
%       MaxIter      — max Lloyd iterations per replicate (default 100).
%       Tol          — convergence tol on max center movement (default 1e-4).
%       Seed         — RNG seed; fixed default 0 for REPRODUCIBLE clusters.
%       Replicates   — independent restarts; keep the lowest-inertia run
%                      (default 1). Each replicate uses Seed+rep-1.
%
%   Outputs:
%       labels       — [N x 1] cluster index in 1..k for each sample.
%       centers      — [k x F] final cluster centroids.
%       info         — struct: .inertia (within-cluster sum of squares),
%                      .iters (iterations of the best replicate), .k.
%
%   See also imaging.ml.standardizeFeatures, imaging.connectedComponents

arguments
    X                 (:,:) {mustBeNumeric}
    k                 (1,1) double {mustBePositive, mustBeInteger}
    options.MaxIter   (1,1) double {mustBePositive, mustBeInteger} = 100
    options.Tol       (1,1) double {mustBeNonnegative} = 1e-4
    options.Seed      (1,1) double {mustBeInteger} = 0
    options.Replicates(1,1) double {mustBePositive, mustBeInteger} = 1
end

X = double(X);
N = size(X, 1);
k = min(k, N);

bestInertia = inf;
labels  = ones(N, 1);
centers = X(1, :);
bestIters = 0;

for rep = 1:options.Replicates
    s = RandStream('twister', 'Seed', options.Seed + rep - 1);

    C = kmeansppInit(X, k, s);
    prevC = C;
    % MaxIter is mustBePositive, so this loop always runs at least once and
    % assigns both `it` and `lab` before they are read below.
    for it = 1:options.MaxIter
        D = pairwiseSqDist(X, C);          % [N x k]
        [~, lab] = min(D, [], 2);

        for j = 1:k
            m = (lab == j);
            if any(m)
                C(j, :) = mean(X(m, :), 1);
            else
                % Empty cluster: reseed it on a random sample.
                C(j, :) = X(randi(s, N), :);
            end
        end

        if max(abs(C(:) - prevC(:))) < options.Tol
            break;
        end
        prevC = C;
    end

    D = pairwiseSqDist(X, C);
    [dmin, lab] = min(D, [], 2);
    inertia = sum(dmin);

    if inertia < bestInertia
        bestInertia = inertia;
        labels      = lab;
        centers     = C;
        bestIters   = it;
    end
end

info = struct('inertia', bestInertia, 'iters', bestIters, 'k', k);
end

% ════════════════════════════════════════════════════════════════════════
%  Local helpers
% ════════════════════════════════════════════════════════════════════════
function D = pairwiseSqDist(X, C)
%PAIRWISESQDIST  [N x k] squared Euclidean distances, no Stats Toolbox.
D = sum(X.^2, 2) + sum(C.^2, 2)' - 2 * (X * C');
D = max(D, 0);   % clamp tiny negatives from round-off
end

function C = kmeansppInit(X, k, s)
%KMEANSPPINIT  k-means++ seeding using RandStream s.
N = size(X, 1);
C = zeros(k, size(X, 2));

C(1, :) = X(randi(s, N), :);
d2 = sum((X - C(1, :)).^2, 2);

for j = 2:k
    total = sum(d2);
    if total <= 0 || ~isfinite(total)
        % All remaining points coincide with chosen centers: pick at random.
        C(j, :) = X(randi(s, N), :);
    else
        r   = rand(s) * total;
        idx = find(cumsum(d2) >= r, 1, 'first');
        if isempty(idx)
            idx = N;
        end
        C(j, :) = X(idx, :);
    end
    d2 = min(d2, sum((X - C(j, :)).^2, 2));
end
end
