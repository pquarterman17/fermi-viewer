function [labels, probs] = randomForestPredict(model, X)
%RANDOMFORESTPREDICT  Predict with a randomForestTrain model.
%
%   Syntax:
%       labels = imaging.ml.randomForestPredict(model, X)
%       [labels, probs] = imaging.ml.randomForestPredict(model, X)
%
%   Averages the per-class leaf probabilities across all trees and returns
%   the majority class. No standardization is needed (trees split on raw
%   feature values). Pairs with imaging.ml.randomForestTrain.
%
%   Inputs:
%       model        — struct from imaging.ml.randomForestTrain.
%       X            — [M x F] feature matrix (same F as training).
%
%   Outputs:
%       labels       — [M x 1] predicted labels in model.classes values.
%       probs        — [M x C] averaged class probabilities (column c ↔
%                      model.classes(c)).
%
%   See also imaging.ml.randomForestTrain

arguments
    model (1,1) struct
    X     (:,:) {mustBeNumeric}
end

X = double(X);
M = size(X, 1);
C = model.numClasses;
nTrees = numel(model.trees);

probs = zeros(M, C);
for t = 1:nTrees
    probs = probs + treeProbs(model.trees{t}, X);
end
probs = probs / nTrees;

[~, idx] = max(probs, [], 2);
labels = reshape(model.classes(idx), [], 1);
end

% ════════════════════════════════════════════════════════════════════════
%  Local helper — vectorized descent of one tree for all rows
% ════════════════════════════════════════════════════════════════════════
function P = treeProbs(node, X)
%TREEPROBS  [M x C] leaf probabilities for every row of X through one tree.
M = size(X, 1);
if node.isLeaf
    P = repmat(node.probs, M, 1);
    return;
end
goLeft = X(:, node.feature) <= node.threshold;
P = zeros(M, numelProbs(node));
if any(goLeft)
    P(goLeft, :)  = treeProbs(node.left,  X(goLeft, :));
end
if any(~goLeft)
    P(~goLeft, :) = treeProbs(node.right, X(~goLeft, :));
end
end

function c = numelProbs(node)
%NUMELPROBS  Number of classes (probe a leaf under this node).
while ~node.isLeaf
    node = node.left;
end
c = numel(node.probs);
end
