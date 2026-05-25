function model = softmaxTrain(X, y, options)
%SOFTMAXTRAIN  Multinomial logistic-regression classifier (base MATLAB).
%
%   Syntax:
%       model = imaging.ml.softmaxTrain(X, y)
%       model = imaging.ml.softmaxTrain(X, y, LearnRate=0.5, MaxIter=800)
%
%   Trains a softmax (multinomial logistic) classifier by batch gradient
%   descent with L2 regularization. Pure base MATLAB — no Statistics or
%   Deep Learning Toolbox. A reusable learning kernel (NOT grain-specific);
%   pairs with imaging.ml.softmaxPredict.
%
%   Feature standardization is fitted on the training data and BAKED INTO
%   the model (model.mu / model.sigma), so softmaxPredict applies the
%   identical transform to new data automatically. Weight initialization is
%   zeros, so training is deterministic (no RNG needed).
%
%   Inputs:
%       X            — [N x F] feature matrix (N samples, F features).
%       y            — [N x 1] class labels (any numeric values; mapped to
%                      1..C internally, original values stored in model.classes).
%
%   Optional Name-Value:
%       LearnRate    — gradient-descent step size (default 0.5).
%       MaxIter      — max iterations (default 800).
%       Lambda       — L2 regularization strength (default 1e-3). The bias
%                      row is never regularized.
%       Tol          — stop when the mean-cross-entropy loss improves by less
%                      than Tol between iterations (default 1e-7).
%       Standardize  — z-score features before training (default true).
%                      Strongly recommended; gradient descent on raw
%                      mixed-scale features converges poorly.
%
%   Output: model — struct with fields:
%       .W           — [(F+1) x C] weights (row 1 = bias).
%       .classes     — [1 x C] original class labels (model output maps back
%                      to these).
%       .numClasses  — C.
%       .mu, .sigma  — [1 x F] standardization stats (NaN-safe; see
%                      imaging.ml.standardizeFeatures). Empty if Standardize=false.
%       .standardize — logical, whether standardization is applied.
%       .iters       — iterations actually run.
%       .loss        — final mean cross-entropy loss.
%
%   See also imaging.ml.softmaxPredict, imaging.ml.standardizeFeatures

arguments
    X                  (:,:) {mustBeNumeric}
    y                  (:,1) {mustBeNumeric}
    options.LearnRate  (1,1) double {mustBePositive} = 0.5
    options.MaxIter    (1,1) double {mustBePositive, mustBeInteger} = 800
    options.Lambda     (1,1) double {mustBeNonnegative} = 1e-3
    options.Tol        (1,1) double {mustBeNonnegative} = 1e-7
    options.Standardize(1,1) logical = true
end

X = double(X);
N = size(X, 1);
if numel(y) ~= N
    error('softmaxTrain:sizeMismatch', 'X has %d rows but y has %d.', N, numel(y));
end

% ── Map class labels to 1..C ────────────────────────────────────────────
classes = unique(y(:))';
C = numel(classes);
yIdx = zeros(N, 1);
for c = 1:C
    yIdx(y == classes(c)) = c;
end

% ── Standardize (baked into model) ──────────────────────────────────────
if options.Standardize
    [Xs, mu, sigma] = imaging.ml.standardizeFeatures(X);
else
    Xs = X; mu = []; sigma = [];
end

% ── Design matrix with bias column ──────────────────────────────────────
Xb = [ones(N, 1), Xs];          % [N x (F+1)]
F1 = size(Xb, 2);

% One-hot targets.
Y = zeros(N, C);
Y(sub2ind([N, C], (1:N)', yIdx)) = 1;

% L2 mask: regularize all weights except the bias row.
regMask = ones(F1, C);
regMask(1, :) = 0;

% ── Batch gradient descent ──────────────────────────────────────────────
W = zeros(F1, C);
prevLoss = inf;
% MaxIter is mustBePositive, so the loop always runs and assigns it/loss.
for it = 1:options.MaxIter
    scores = Xb * W;                         % [N x C]
    scores = scores - max(scores, [], 2);    % numerical stability
    expS   = exp(scores);
    P      = expS ./ sum(expS, 2);           % softmax probabilities

    % Mean cross-entropy + L2 penalty.
    logLik = sum(log(P(sub2ind([N, C], (1:N)', yIdx))));
    loss   = -logLik / N + options.Lambda / 2 * sum((regMask .* W).^2, 'all');

    grad = Xb' * (P - Y) / N + options.Lambda * (regMask .* W);
    W    = W - options.LearnRate * grad;

    if abs(prevLoss - loss) < options.Tol
        break;
    end
    prevLoss = loss;
end

model = struct( ...
    'W',           W, ...
    'classes',     classes, ...
    'numClasses',  C, ...
    'mu',          mu, ...
    'sigma',       sigma, ...
    'standardize', options.Standardize, ...
    'iters',       it, ...
    'loss',        loss);
end
