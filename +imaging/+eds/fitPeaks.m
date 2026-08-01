function result = fitPeaks(energy, counts, elements, options)
%FITPEAKS  Constrained multi-Gaussian EDS peak deconvolution.
%
%   Syntax
%     result = imaging.eds.fitPeaks(energy, counts, elements)
%     result = imaging.eds.fitPeaks(energy, counts, elements, Name=Value)
%
%   Resolves endemic EDS line overlaps (S-Ka/Mo-La/Pb-Ma, Ti-Kb/V-Ka, ...)
%   that window-integration mis-assigns, by fitting all elements'
%   characteristic peaks jointly. Each element contributes one Gaussian whose
%   CENTER is its known line energy (imaging.eds.lineEnergy) and whose WIDTH
%   is fixed from the Fano detector-resolution model
%   (imaging.eds.fanoResolution) -- only the per-element AMPLITUDE (plus a
%   shared linear background) is free.
%
%   Because centers and widths are fixed, the core fit is LINEAR: backslash
%   on a design matrix of unit-height Gaussians plus [E, 1] background
%   columns. Negative amplitudes returned by the unconstrained solve are
%   clamped to 0 post-hoc (a documented approximation to a truly
%   non-negative-constrained fit -- see "Deviations" below). The integrated
%   net area of each peak (amp*sigma*sqrt(2*pi)) feeds
%   imaging.eds.cliffLorimer unchanged via imaging.eds.quantifyPeaks.
%
%   With CenterTolKeV > 0, each fitted center may wander +/-CenterTolKeV
%   (sigma stays fixed) to absorb a small residual energy miscalibration.
%   This is a small variable-projection search: fminsearch adjusts the few
%   center offsets, and for each trial offset the amplitudes + background are
%   re-solved linearly (the inner linear solve above) before scoring the
%   weighted sum-of-squares. No Optimization/Curve-Fitting Toolbox is used
%   (backslash + fminsearch only).
%
%   Inputs
%     energy    numeric vector, keV axis
%     counts    numeric vector, same length as ENERGY
%     elements  {1xN} cellstr of element symbols to fit
%
%   Name-Value
%     BeamKV        (1,1) double = 200   accelerating voltage passed to
%                   imaging.eds.lineEnergy for K/L/M family auto-selection
%     CenterTolKeV  (1,1) double = 0     +/- center search window (keV);
%                   0 (default) means fixed positions
%     Weights       (1,1) string {"uniform","poisson"} = "uniform"
%                   "poisson" weights each channel by 1/max(counts,1)
%                   (approximate counting statistics); "uniform" weights
%                   all channels equally.
%
%   Output
%     result  struct, all per-element fields ordered to match ELEMENTS
%             (NaN / empty for an element with no known line):
%       .elements        {1xN} cellstr, echoes the input
%       .lineEnergyKeV   [1xN] double, principal line energy used
%       .lineFamily      {1xN} cellstr, 'K'/'L'/'M' family used ('' if none)
%       .sigmaKeV        [1xN] double, fixed Fano sigma used
%       .netArea         [1xN] double, amp*sigma*sqrt(2*pi)
%       .netAreaSigma    [1xN] double, propagated 1-sigma error
%       .centerOffsetKeV [1xN] double, fitted center shift (0 unless
%                        CenterTolKeV > 0)
%       .elementCurves   {1xN} cell, each [Mx1] best-fit Gaussian curve (or
%                        [] for an element with no known line)
%       .backgroundCurve [Mx1] double, the fitted linear background alone
%       .fittedCurve     [Mx1] double, the full model (all peaks + bg) --
%                        feed "counts - result.fittedCurve" to
%                        imaging.eds.removeArtifacts as the RESIDUAL
%       .background      struct with .intercept, .slope (linear bg coeffs)
%       .reducedChi2     (1,1) double, weighted reduced chi-squared
%       .weights         (1,1) string, the Weights option used
%       .centerTolKeV    (1,1) double, the CenterTolKeV option used
%
%   Examples
%     e  = linspace(0, 20, 4001);
%     s  = imaging.eds.fanoResolution(imaging.eds.lineEnergy('Fe'));
%     y  = 5000/(s*sqrt(2*pi)) * exp(-0.5*((e-imaging.eds.lineEnergy('Fe'))/s).^2);
%     pf = imaging.eds.fitPeaks(e, y, {'Fe'}, Weights="uniform");
%     pf.netArea(1)          % -> ~5000
%
%   See also IMAGING.EDS.QUANTIFYPEAKS, IMAGING.EDS.REMOVEARTIFACTS,
%   IMAGING.EDS.FANORESOLUTION, IMAGING.EDS.LINEENERGY
%
%   Deviations from the fermiviewer Python port (calc/eds_peakfit.py):
%   the Python fit uses scipy.optimize.least_squares (trust-region
%   reflective), a true bounded nonlinear solver; this MATLAB port instead
%   exploits that, with centers/sigmas fixed, the model is LINEAR in the
%   remaining parameters and solves it directly with backslash, clamping any
%   negative amplitude to 0 afterward. For the physically realistic case of
%   well-separated-or-overlapping POSITIVE peaks (all the shipped oracles)
%   the two approaches agree to numerical precision; the clamp only
%   under-reports the covariance of a parameter that hits the amplitude>=0
%   boundary, which is documented here rather than silently absorbed.
%   Default Weights is "uniform" here (Python defaults to "poisson").

    arguments
        energy   {mustBeNumeric, mustBeVector}
        counts   {mustBeNumeric, mustBeVector}
        elements (1,:) cell
        options.BeamKV       (1,1) double = 200
        options.CenterTolKeV (1,1) double = 0
        options.Weights      (1,1) string {mustBeMember(options.Weights, ["uniform", "poisson"])} = "uniform"
    end

% ════════════════════════════════════════════════════════════════════════
%  Validate + normalise inputs
% ════════════════════════════════════════════════════════════════════════
energy = double(energy(:));
counts = double(counts(:));
if numel(energy) ~= numel(counts)
    error('fitPeaks:sizeMismatch', 'energy and counts must have equal length.');
end
if isempty(elements)
    error('fitPeaks:noElements', 'need at least one element.');
end
elements = elements(:).';
nElem = numel(elements);
nData = numel(energy);

% ════════════════════════════════════════════════════════════════════════
%  Resolve each element's line + Fano sigma (imaging.eds is the single
%  source of truth for both -- see module docs)
% ════════════════════════════════════════════════════════════════════════
lineEnergyKeV = nan(1, nElem);
lineFamily    = repmat({''}, 1, nElem);
sigmaKeV      = nan(1, nElem);
fittable      = false(1, nElem);

for i = 1:nElem
    sym = elements{i};
    [eLine, fam] = imaging.eds.lineEnergy(sym, BeamKV=options.BeamKV);
    if isempty(fam) || isnan(eLine)
        warning('fitPeaks:noLine', 'no characteristic line for ''%s''', sym);
        continue
    end
    [~, sig] = imaging.eds.fanoResolution(eLine);
    lineEnergyKeV(i) = eLine;
    lineFamily{i}    = fam;
    sigmaKeV(i)       = max(sig, 1e-9);
    fittable(i)       = true;
end

if ~any(fittable)
    error('fitPeaks:noFittableLines', 'no fittable element lines');
end

fitIdx = find(fittable);
nFit   = numel(fitIdx);
centers0 = lineEnergyKeV(fitIdx);
sigmasFit = sigmaKeV(fitIdx);

% ════════════════════════════════════════════════════════════════════════
%  Weights (1/sigma^2 per channel)
% ════════════════════════════════════════════════════════════════════════
if options.Weights == "poisson"
    w = 1 ./ max(counts, 1);
else
    w = ones(nData, 1);
end
sqrtW = sqrt(w);

% ════════════════════════════════════════════════════════════════════════
%  Center refinement (variable projection) or fixed-position solve
% ════════════════════════════════════════════════════════════════════════
if options.CenterTolKeV > 0
    tol = options.CenterTolKeV;
    objective = @(offsets) vpObjective(offsets, tol, energy, counts, sqrtW, centers0, sigmasFit, nFit);
    fmOpts = optimset('Display', 'off');
    offsetsOpt = fminsearch(objective, zeros(1, nFit), fmOpts);
    offsetsOpt = max(min(offsetsOpt, tol), -tol);
else
    offsetsOpt = zeros(1, nFit);
end
centersUsed = centers0 + offsetsOpt;

X = buildDesignMatrix(energy, centersUsed, sigmasFit);
[beta, cov, reducedChi2] = solveLinearPeaks(X, counts, sqrtW, nFit);
model = X * beta;

% ════════════════════════════════════════════════════════════════════════
%  Assemble per-element outputs (NaN / [] for elements with no known line)
% ════════════════════════════════════════════════════════════════════════
netArea        = nan(1, nElem);
netAreaSigma   = nan(1, nElem);
centerOffsetKeV = zeros(1, nElem);
elementCurves  = cell(1, nElem);

for k = 1:nFit
    i = fitIdx(k);
    scale = sigmasFit(k) * sqrt(2 * pi);
    netArea(i)         = beta(k) * scale;
    netAreaSigma(i)     = sqrt(max(cov(k, k), 0)) * scale;
    centerOffsetKeV(i) = offsetsOpt(k);
    elementCurves{i}   = X(:, k) * beta(k);
end

backgroundCurve = X(:, nFit + 1) * beta(nFit + 1) + X(:, nFit + 2) * beta(nFit + 2);

result.elements        = elements;
result.lineEnergyKeV   = lineEnergyKeV;
result.lineFamily      = lineFamily;
result.sigmaKeV        = sigmaKeV;
result.netArea         = netArea;
result.netAreaSigma    = netAreaSigma;
result.centerOffsetKeV = centerOffsetKeV;
result.elementCurves   = elementCurves;
result.backgroundCurve = backgroundCurve;
result.fittedCurve     = model;
result.background      = struct('intercept', beta(nFit + 2), 'slope', beta(nFit + 1));
result.reducedChi2     = reducedChi2;
result.weights         = options.Weights;
result.centerTolKeV    = options.CenterTolKeV;

end


% ════════════════════════════════════════════════════════════════════════
%  Local helpers
% ════════════════════════════════════════════════════════════════════════

function X = buildDesignMatrix(energy, centers, sigmas)
%BUILDDESIGNMATRIX  [unit Gaussians per fitted element | E | 1] columns.
    nFit = numel(centers);
    X = zeros(numel(energy), nFit + 2);
    for k = 1:nFit
        X(:, k) = exp(-0.5 * ((energy - centers(k)) / sigmas(k)) .^ 2);
    end
    X(:, nFit + 1) = energy;
    X(:, nFit + 2) = 1;
end


function [beta, cov, reducedChi2] = solveLinearPeaks(X, y, sqrtW, nAmpCols)
%SOLVELINEARPEAKS  Weighted linear least squares + amplitude clamp + the
%   covariance the constrained nonlinear fit would report at this solution:
%   cov = inv(X'*W*X) * reducedChi2, matching the Jacobian-based formula the
%   Python port derives from scipy's least_squares (for this LINEAR model,
%   the residual Jacobian is exactly sqrt(W).*X).
    Xw = X .* sqrtW;
    yw = y .* sqrtW;
    beta = Xw \ yw;
    beta(1:nAmpCols) = max(beta(1:nAmpCols), 0);   % see file docstring: documented clamp

    [nData, nParam] = size(X);
    dof = max(nData - nParam, 1);
    resid = (X * beta - y) .* sqrtW;
    reducedChi2 = sum(resid .^ 2) / dof;

    XtWX = Xw' * Xw;
    if rcond(XtWX) > eps
        covBase = inv(XtWX);
    else
        covBase = pinv(XtWX);
    end
    cov = covBase * reducedChi2;
end


function sse = vpObjective(offsets, tol, energy, counts, sqrtW, centers0, sigmas, nFit)
%VPOBJECTIVE  Variable-projection objective for the CenterTolKeV search:
%   clip the trial offsets to +/-tol, re-solve amplitudes+background
%   linearly at the resulting centers, and return the weighted SSE.
    offsets = max(min(offsets, tol), -tol);
    X = buildDesignMatrix(energy, centers0 + offsets, sigmas);
    Xw = X .* sqrtW;
    yw = counts .* sqrtW;
    beta = Xw \ yw;
    beta(1:nFit) = max(beta(1:nFit), 0);
    resid = (X * beta - counts) .* sqrtW;
    sse = sum(resid .^ 2);
end
