function [net, fitResult] = subtractContinuum(energy, counts, e0KeV, options)
%SUBTRACTCONTINUUM  Background-subtract the fitted bremsstrahlung continuum.
%
%   [net, fitResult] = imaging.eds.subtractContinuum(energy, counts, e0KeV)
%   fits imaging.eds.fitContinuum(energy, counts, e0KeV, ...) and returns
%   net = counts - fitResult.continuum, clamped at 0 by default.
%
%   Name-Value
%   ----------
%   Clip   (1,1) logical = true   Clamp net at 0 (over-subtraction guard).
%
%   All other Name-Value pairs (Elements, ExcludeWindows,
%   ExcludeWidthFactor, FitAbsorption, Weights) pass through unchanged to
%   imaging.eds.fitContinuum.
%
%   Outputs
%   -------
%   net        [numel(energy) x 1] background-subtracted spectrum.
%   fitResult  the full struct from imaging.eds.fitContinuum (includes the
%              fitted .continuum curve, .amp, .absorption, .keepMask,
%              .reducedChi2).
%
%   Example
%   -------
%     [net, fit] = imaging.eds.subtractContinuum(e, counts, 18.0, Elements={'Fe'});
%     fprintf('Fe net area: %.1f (reducedChi2=%.2f)\n', sum(net), fit.reducedChi2);
%
%   See also IMAGING.EDS.FITCONTINUUM
%   Port of fermiviewer calc/eds_continuum.py (subtract_continuum).

    arguments
        energy  (:,1) double
        counts  (:,1) double
        e0KeV   (1,1) double
        options.Clip               (1,1) logical = true
        options.Elements           cell = {}
        options.ExcludeWindows     (:,2) double = zeros(0,2)
        options.ExcludeWidthFactor (1,1) double = 3.0
        options.FitAbsorption      (1,1) logical = true
        options.Weights            (1,1) string = "poisson"
    end

    fitResult = imaging.eds.fitContinuum(energy, counts, e0KeV, ...
        Elements=options.Elements, ...
        ExcludeWindows=options.ExcludeWindows, ...
        ExcludeWidthFactor=options.ExcludeWidthFactor, ...
        FitAbsorption=options.FitAbsorption, ...
        Weights=options.Weights);

    net = counts - fitResult.continuum;
    if options.Clip
        net = max(net, 0);
    end
end
