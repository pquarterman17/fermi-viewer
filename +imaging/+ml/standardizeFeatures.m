function [Z, mu, sigma] = standardizeFeatures(X, options)
%STANDARDIZEFEATURES  Z-score feature columns (zero mean, unit variance).
%
%   Syntax:
%       [Z, mu, sigma] = imaging.ml.standardizeFeatures(X)
%       Z = imaging.ml.standardizeFeatures(X, Mu=mu, Sigma=sigma)
%
%   Standardizes each COLUMN (feature) of X to zero mean and unit standard
%   deviation. Distance-based learners (k-means) and gradient-based ones
%   (logistic regression) require this — otherwise a large-range feature
%   (e.g. raw intensity 0..65535) dominates a small-range one (e.g.
%   coherence 0..1) purely by scale.
%
%   Returns the fitted mu/sigma so the IDENTICAL transform can be re-applied
%   to new data (e.g. train a classifier on one image, apply to another):
%       [Ztrain, mu, sigma] = imaging.ml.standardizeFeatures(Xtrain);
%       Ztest = imaging.ml.standardizeFeatures(Xtest, Mu=mu, Sigma=sigma);
%
%   No Statistics Toolbox required (mean/std are base MATLAB).
%
%   Inputs:
%       X       — [N x F] feature matrix (N samples, F features).
%
%   Optional Name-Value:
%       Mu      — [1 x F] precomputed column means to apply (default []:
%                 compute from X).
%       Sigma   — [1 x F] precomputed column std devs to apply (default []:
%                 compute from X).
%
%   Outputs:
%       Z       — [N x F] standardized features.
%       mu      — [1 x F] column means used.
%       sigma   — [1 x F] column std devs used (zeros/non-finite mapped to 1
%                 so constant features pass through as zeros, never NaN/Inf).
%
%   See also imaging.ml.kmeansLite

arguments
    X             (:,:) {mustBeNumeric}
    options.Mu    double = []
    options.Sigma double = []
end

X = double(X);

if isempty(options.Mu)
    mu = mean(X, 1);
else
    mu = options.Mu;
end

if isempty(options.Sigma)
    sigma = std(X, 0, 1);
else
    sigma = options.Sigma;
end

% Guard constant or degenerate features: a zero/NaN/Inf std would produce
% NaN/Inf after division. Map to 1 so the column becomes all-zeros (after
% mean subtraction) rather than poisoning every downstream distance.
sigma(sigma == 0 | ~isfinite(sigma)) = 1;

Z = (X - mu) ./ sigma;
end
