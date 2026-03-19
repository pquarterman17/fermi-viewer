function result = fitInterfaceWidth(x, y, opts)
%FITINTERFACEWIDTH  Fit an error-function or sigmoid to a 1-D intensity
%   profile to measure interface width.
%
%   Syntax:
%       result = imaging.fitInterfaceWidth(x, y)
%       result = imaging.fitInterfaceWidth(x, y, Model='sigmoid')
%
%   Uses fminsearch (no toolbox) to fit a 4-parameter erf or sigmoid model
%   to the transition region.  The 10-90% width is derived analytically
%   from the fitted sigma.
%
%   Inputs:
%       x     — [Nx1] or [1xN] position vector (e.g., nm along a line profile)
%       y     — [Nx1] or [1xN] intensity vector; same length as x
%
%   Optional Name-Value:
%       Model — 'erf' (default) or 'sigmoid'
%
%   Output:
%       result — struct with fields:
%           .center    — interface centre position (same units as x)
%           .sigma     — Gaussian sigma of the transition (same units as x)
%           .width1090 — 10-90% transition width (= 2.5631 * sigma for erf;
%                        = 2 * sigma * log(9) for sigmoid)
%           .amplitude — transition height (fitted max - min)
%           .offset    — fitted baseline level
%           .rSquared  — coefficient of determination (goodness of fit)
%           .xFit      — [500x1] fine position grid for plotting
%           .yFit      — [500x1] fitted curve evaluated on xFit
%           .model     — model string used ('erf' or 'sigmoid')
%
%   Examples:
%       [d, I] = imaging.lineProfile(img, 10, 128, 300, 128, PixelSize=2.4, PixelUnit='nm');
%       r = imaging.fitInterfaceWidth(d, I);
%       fprintf('Interface width (10-90%%): %.2f nm\n', r.width1090);
%       plot(d, I, 'k.', r.xFit, r.yFit, 'r-');
%
%       % Sigmoid model
%       r = imaging.fitInterfaceWidth(d, I, Model='sigmoid');
%
%   See also imaging.lineProfile, imaging.measureDistance

% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    x    (1,:) double {mustBeVector, mustBeFinite}
    y    (1,:) double {mustBeVector, mustBeFinite}
    opts.Model (1,1) string {mustBeMember(opts.Model, {'erf','sigmoid'})} = 'erf'
end

% Ensure column vectors for consistent indexing
x = x(:);
y = y(:);

if numel(x) ~= numel(y)
    error('imaging:fitInterfaceWidth:sizeMismatch', ...
        'x and y must have the same number of elements.');
end
if numel(x) < 4
    error('imaging:fitInterfaceWidth:tooFewPoints', ...
        'At least 4 data points are required for fitting.');
end

% ════════════════════════════════════════════════════════════════════════
%  Initial parameter guess
% ════════════════════════════════════════════════════════════════════════
xRange   = max(x) - min(x);
center0  = (min(x) + max(x)) / 2;
sigma0   = xRange / 8;
amp0     = max(y) - min(y);
offset0  = min(y);

% Determine transition direction: positive if intensity rises left-to-right
% (compare first-half mean vs second-half mean)
midIdx = floor(numel(y) / 2);
if mean(y(1:midIdx)) > mean(y(midIdx+1:end))
    amp0 = -amp0;               % falling transition
end

p0 = [center0, sigma0, amp0, offset0];

% ════════════════════════════════════════════════════════════════════════
%  Model definitions
% ════════════════════════════════════════════════════════════════════════
switch opts.Model
    case 'erf'
        modelFn = @(p, xv) p(3)/2 .* erf((xv - p(1)) ./ (p(2) * sqrt(2))) ...
                            + p(4) + p(3)/2;
    case 'sigmoid'
        modelFn = @(p, xv) p(3) ./ (1 + exp(-(xv - p(1)) ./ p(2))) + p(4);
end

costFn = @(p) sum((y - modelFn(p, x)).^2);

% ════════════════════════════════════════════════════════════════════════
%  Optimisation
% ════════════════════════════════════════════════════════════════════════
fminsearchOpts = optimset('Display', 'off', 'MaxFunEvals', 5000, 'MaxIter', 5000, ...
                           'TolFun', 1e-10, 'TolX', 1e-10);
pFit = fminsearch(costFn, p0, fminsearchOpts);

center    = pFit(1);
sigma     = abs(pFit(2));       % sigma must be positive
amplitude = pFit(3);
offset    = pFit(4);

% ════════════════════════════════════════════════════════════════════════
%  Derived quantities
% ════════════════════════════════════════════════════════════════════════
% 10-90% width: analytically derived from model
switch opts.Model
    case 'erf'
        % erf^{-1}(0.8) - erf^{-1}(-0.8) = 2 * erfinv(0.8) * sigma * sqrt(2)
        width1090 = 2 * erfinv(0.8) * sigma * sqrt(2);
    case 'sigmoid'
        % solve 1/(1+exp(-t/sigma)) = 0.9 => t = sigma*log(9)
        width1090 = 2 * sigma * log(9);
end

% R-squared
yHat      = modelFn(pFit, x);
residuals = y - yHat;
ssTot     = sum((y - mean(y)).^2);
if ssTot == 0
    rSq = 1;
else
    rSq = 1 - sum(residuals.^2) / ssTot;
end

% Fine curve for plotting
xFit = linspace(min(x), max(x), 500)';
yFit = modelFn(pFit, xFit);

% ════════════════════════════════════════════════════════════════════════
%  Assemble result
% ════════════════════════════════════════════════════════════════════════
result.center    = center;
result.sigma     = sigma;
result.width1090 = width1090;
result.amplitude = amplitude;
result.offset    = offset;
result.rSquared  = rSq;
result.xFit      = xFit;
result.yFit      = yFit;
result.model     = opts.Model;

end
