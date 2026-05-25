function [labels, probs] = softmaxPredict(model, X)
%SOFTMAXPREDICT  Predict class labels with a softmaxTrain model.
%
%   Syntax:
%       labels = imaging.ml.softmaxPredict(model, X)
%       [labels, probs] = imaging.ml.softmaxPredict(model, X)
%
%   Applies a model from imaging.ml.softmaxTrain to new data. The model's
%   baked-in standardization (model.mu / model.sigma) is applied
%   automatically, so X must be in the SAME raw feature space as the
%   training data (same feature columns, unstandardized).
%
%   Pure base MATLAB. Pairs with imaging.ml.softmaxTrain.
%
%   Inputs:
%       model        — struct from imaging.ml.softmaxTrain.
%       X            — [M x F] feature matrix (same F as training).
%
%   Outputs:
%       labels       — [M x 1] predicted labels, in model.classes values
%                      (mapped back from the internal 1..C indices).
%       probs        — [M x C] class posterior probabilities (column c
%                      corresponds to model.classes(c)).
%
%   See also imaging.ml.softmaxTrain

arguments
    model (1,1) struct
    X     (:,:) {mustBeNumeric}
end

X = double(X);

if model.standardize
    Xs = imaging.ml.standardizeFeatures(X, Mu=model.mu, Sigma=model.sigma);
else
    Xs = X;
end

Xb = [ones(size(Xs, 1), 1), Xs];

scores = Xb * model.W;
scores = scores - max(scores, [], 2);
expS   = exp(scores);
probs  = expS ./ sum(expS, 2);

[~, idx] = max(probs, [], 2);
% Force a column vector: indexing a row vector by a column index has
% ambiguous orientation, so reshape explicitly.
labels   = reshape(model.classes(idx), [], 1);
end
