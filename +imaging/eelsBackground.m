function [signal, background, params] = eelsBackground(energyAxis, spectrum, opts)
%EELSBACKGROUND  Power-law background subtraction for EELS core-loss spectra.
%
%   Syntax:
%       [signal, background, params] = imaging.eelsBackground( ...
%           energyAxis, spectrum, FitWindow=[E1,E2])
%       [signal, background, params] = imaging.eelsBackground( ...
%           energyAxis, spectrum, FitWindow=[E1,E2], Method='exponential')
%
%   Fits a background model in a pre-edge window and extrapolates it across
%   the full energy range, then subtracts.  Two models are supported:
%
%     'powerlaw'    — A * E^(-r)   fit via polyfit in log-log space
%     'exponential' — A * exp(b*E) fit via polyfit in log-linear space
%
%   Inputs:
%       energyAxis — [N x 1] energy-loss axis (eV), strictly positive
%       spectrum   — [N x 1] intensity (counts or cps)
%
%   Optional Name-Value:
%       FitWindow — [E_start, E_end] pre-edge energy window (eV).
%                   Must lie entirely below the edge onset.
%                   Default: first 20% of the energy range.
%       Method    — 'powerlaw' (default) | 'exponential'
%
%   Outputs:
%       signal     — [N x 1] background-subtracted spectrum (negative values
%                   clamped to 0)
%       background — [N x 1] fitted background over the full energy range
%       params     — struct with fit coefficients:
%                     powerlaw:    .A (amplitude), .r (exponent)
%                     exponential: .A (amplitude), .b (rate)
%
%   Examples:
%       % Subtract background before the O-K edge at 532 eV
%       [sig, bg, p] = imaging.eelsBackground(E, I, FitWindow=[480, 525]);
%       plot(E, I, E, bg, '--', E, sig);
%       legend('Raw','Background','Signal');
%
%       % Exponential model
%       [sig, bg, p] = imaging.eelsBackground(E, I, ...
%           FitWindow=[480, 525], Method='exponential');
%
%   See also imaging.eelsExtractMap, imaging.eelsThicknessMap,
%            imaging.eelsEdgeTable

% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    energyAxis (:,1) double {mustBeNonempty}
    spectrum   (:,1) double {mustBeNonempty}
    opts.FitWindow (1,2) double = [NaN, NaN]
    opts.Method    (1,1) string {mustBeMember(opts.Method, ...
                       {'powerlaw','exponential'})} = 'powerlaw'
end

energyAxis = double(energyAxis(:));
spectrum   = double(spectrum(:));

if numel(energyAxis) ~= numel(spectrum)
    error('imaging:eelsBackground:sizeMismatch', ...
        'energyAxis and spectrum must have the same number of elements.');
end

% ════════════════════════════════════════════════════════════════════════
%  Resolve fit window
% ════════════════════════════════════════════════════════════════════════
if any(isnan(opts.FitWindow))
    % Default: first 20 % of the energy span
    eMin = min(energyAxis);
    eMax = max(energyAxis);
    opts.FitWindow = [eMin, eMin + 0.2*(eMax - eMin)];
end

fitMask = energyAxis >= opts.FitWindow(1) & energyAxis <= opts.FitWindow(2);
if sum(fitMask) < 2
    error('imaging:eelsBackground:tooFewPoints', ...
        'FitWindow [%.1f, %.1f] eV contains fewer than 2 data points.', ...
        opts.FitWindow(1), opts.FitWindow(2));
end

Efit = energyAxis(fitMask);
Ifit = spectrum(fitMask);

% Guard against non-positive intensities before log transform
Ifit = max(Ifit, eps);

% ════════════════════════════════════════════════════════════════════════
%  Fit and extrapolate
% ════════════════════════════════════════════════════════════════════════
switch opts.Method
    case 'powerlaw'
        % log(I) = log(A) + (-r)*log(E)  →  polyfit in log-log space
        coeffs = polyfit(log(Efit), log(Ifit), 1);
        r      = -coeffs(1);          % power-law exponent (positive for EELS)
        A      = exp(coeffs(2));

        Eguard     = max(energyAxis, eps);   % avoid log(0) on extrapolation
        background = A * Eguard .^ (-r);

        params.A = A;
        params.r = r;

    case 'exponential'
        % log(I) = log(A) + b*E  →  polyfit in log-linear space
        coeffs = polyfit(Efit, log(Ifit), 1);
        b      = coeffs(1);
        A      = exp(coeffs(2));

        background = A * exp(b * energyAxis);

        params.A = A;
        params.b = b;
end

% ════════════════════════════════════════════════════════════════════════
%  Subtract and clamp
% ════════════════════════════════════════════════════════════════════════
signal = spectrum - background;
signal = max(signal, 0);

end
