function model = randomForestTrain(X, y, options)
%RANDOMFORESTTRAIN  Random-forest classifier (CART trees), pure base MATLAB.
%
%   Syntax:
%       model = imaging.ml.randomForestTrain(X, y)
%       model = imaging.ml.randomForestTrain(X, y, NumTrees=50, Seed=1)
%
%   Bagged ensemble of CART classification trees (Gini impurity), each grown
%   on a bootstrap sample with a random feature subset evaluated at every
%   split. A reusable learning kernel (NOT grain-specific); pairs with
%   imaging.ml.randomForestPredict.
%
%   Compared with imaging.ml.softmaxTrain, a forest captures nonlinear
%   feature interactions and needs no standardization — useful when the
%   orientation features separate classes in a way logistic regression
%   underfits. Deterministic for a given Seed (private RandStream).
%
%   No Statistics or Deep Learning Toolbox.
%
%   Inputs:
%       X            — [N x F] feature matrix.
%       y            — [N x 1] class labels (any numeric; mapped internally).
%
%   Optional Name-Value:
%       NumTrees     — number of trees (default 40).
%       MaxDepth     — maximum tree depth (default 12).
%       MinLeaf      — minimum samples to split a node (default 3).
%       NumFeatures  — features sampled per split (default 0 → round(sqrt(F))).
%       MaxThresholds— candidate thresholds evaluated per feature (default 24;
%                      bounds split-search cost on features with many values).
%       Seed         — RNG seed (default 0) for reproducible forests.
%
%   Output: model — struct:
%       .trees       — {NumTrees x 1} cell of tree node structs.
%       .classes     — [1 x C] original class labels.
%       .numClasses  — C.
%       .numFeatures — F (for input validation at predict).
%       .type        — "forest".
%
%   See also imaging.ml.randomForestPredict, imaging.ml.softmaxTrain

arguments
    X                    (:,:) {mustBeNumeric}
    y                    (:,1) {mustBeNumeric}
    options.NumTrees     (1,1) double {mustBePositive, mustBeInteger} = 40
    options.MaxDepth     (1,1) double {mustBePositive, mustBeInteger} = 12
    options.MinLeaf      (1,1) double {mustBePositive, mustBeInteger} = 3
    options.NumFeatures  (1,1) double {mustBeNonnegative, mustBeInteger} = 0
    options.MaxThresholds(1,1) double {mustBePositive, mustBeInteger} = 24
    options.Seed         (1,1) double {mustBeInteger} = 0
end

X = double(X);
N = size(X, 1);
F = size(X, 2);
if numel(y) ~= N
    error('randomForestTrain:sizeMismatch', 'X has %d rows but y has %d.', N, numel(y));
end

classes = unique(y(:))';
C = numel(classes);
yIdx = zeros(N, 1);
for c = 1:C
    yIdx(y == classes(c)) = c;
end

mtry = options.NumFeatures;
if mtry == 0
    mtry = max(1, round(sqrt(F)));
end
mtry = min(mtry, F);

maxDepth = options.MaxDepth;
minLeaf  = options.MinLeaf;
maxThr   = options.MaxThresholds;

s = RandStream('twister', 'Seed', options.Seed);

trees = cell(options.NumTrees, 1);
for t = 1:options.NumTrees
    boot = randi(s, N, N, 1);            % bootstrap sample (with replacement)
    trees{t} = growTree(boot, 1);
end

model = struct( ...
    'trees',       {trees}, ...
    'classes',     classes, ...
    'numClasses',  C, ...
    'numFeatures', F, ...
    'type',        "forest");

% ════════════════════════════════════════════════════════════════════════
%  Nested helpers (capture X, yIdx, C, mtry, maxDepth, minLeaf, maxThr, s)
% ════════════════════════════════════════════════════════════════════════
    function node = growTree(rows, depth)
        counts = accumarray(yIdx(rows), 1, [C 1]);
        node = struct();

        % Stop: max depth, too few samples, or pure node.
        if depth >= maxDepth || numel(rows) < 2*minLeaf || nnz(counts) <= 1
            node.isLeaf = true;
            node.probs  = (counts / sum(counts))';
            return;
        end

        [fi, thr, ok] = bestSplit(rows);
        if ~ok
            node.isLeaf = true;
            node.probs  = (counts / sum(counts))';
            return;
        end

        goLeft   = X(rows, fi) <= thr;
        leftRows = rows(goLeft);
        rightRows= rows(~goLeft);
        if numel(leftRows) < minLeaf || numel(rightRows) < minLeaf
            node.isLeaf = true;
            node.probs  = (counts / sum(counts))';
            return;
        end

        node.isLeaf    = false;
        node.feature   = fi;
        node.threshold = thr;
        node.left      = growTree(leftRows, depth + 1);
        node.right     = growTree(rightRows, depth + 1);
    end

    function [bestFi, bestThr, ok] = bestSplit(rows)
        bestFi = 0; bestThr = 0; ok = false;
        bestGini = inf;

        feats = randperm(s, F, mtry);   % random feature subset
        yr = yIdx(rows);
        n  = numel(rows);

        for fi = feats
            vals = X(rows, fi);
            uv = unique(vals);
            if numel(uv) < 2
                continue;
            end
            % Candidate thresholds = midpoints; subsample if too many.
            mids = (uv(1:end-1) + uv(2:end)) / 2;
            if numel(mids) > maxThr
                pick = round(linspace(1, numel(mids), maxThr));
                mids = mids(pick);
            end
            for thr = mids'
                leftMask = vals <= thr;
                nl = sum(leftMask);
                nr = n - nl;
                if nl == 0 || nr == 0
                    continue;
                end
                cl = accumarray(yr(leftMask),  1, [C 1]);
                cr = accumarray(yr(~leftMask), 1, [C 1]);
                gL = 1 - sum((cl / nl).^2);
                gR = 1 - sum((cr / nr).^2);
                g  = (nl * gL + nr * gR) / n;
                if g < bestGini
                    bestGini = g; bestFi = fi; bestThr = thr; ok = true;
                end
            end
        end
    end
end
