function result = fitContinuum(energy, counts, e0KeV, options)
%FITCONTINUUM  Fit a fittable bremsstrahlung continuum through masked peaks.
%
%   Syntax
%     result = imaging.eds.fitContinuum(energy, counts, e0KeV)
%     result = imaging.eds.fitContinuum(..., Name=Value)
%
%   Model (Kramers, detector-shaped):
%
%       I(E) = amp * (E0-E)/E .* exp(-absorption/E)     0 < E < E0
%
%   The bare (E0-E)/E is Kramers' law (continuum diverging as E->0,
%   vanishing at the Duane-Hunt limit E0). The optional exp(-absorption/E)
%   rolloff approximates the low-energy detector-window / dead-layer
%   absorption that suppresses the divergence; absorption=0 recovers pure
%   Kramers.
%
%   Characteristic peaks of the requested Elements (every K/L/M family
%   tabulated for that symbol) are masked out at +/- (ExcludeWidthFactor *
%   FanoFWHM(E)) before fitting, so the smooth continuum shape is fit
%   THROUGH the peak regions rather than distorted by them.
%
%   Inputs
%   ------
%   energy   (:,1) double   keV energy axis.
%   counts   (:,1) double   spectrum counts, same length as energy.
%   e0KeV    (1,1) double   Beam energy / Duane-Hunt cutoff (keV). Must be
%                           finite (a beam energy is always required).
%
%   Name-Value
%   ----------
%   Elements            cell   = {}          Element symbols whose K/L/M
%                                             lines (whichever are
%                                             tabulated) get masked out.
%   ExcludeWindows      (:,2) double = zeros(0,2)   Extra [lo hi] keV
%                                             windows to mask (e.g. escape
%                                             or sum peaks).
%   ExcludeWidthFactor  (1,1) double = 3.0   Peak mask half-width, in units
%                                             of the Fano-model FWHM(E)
%                                             (imaging.eds.fanoResolution).
%   FitAbsorption       (1,1) logical = true   Free the low-energy
%                                             detector-absorption rolloff;
%                                             false fixes absorption=0
%                                             (pure Kramers).
%   Weights             (1,1) string = "poisson"   "poisson" (1/max(N,1)
%                                             counting-statistics weight)
%                                             or "none" (uniform). Masked
%                                             channels always get exactly
%                                             zero weight, regardless of
%                                             scheme.
%
%   Output -- a struct with fields:
%     .continuum    [numel(energy) x 1] fitted curve over the FULL axis
%     .amp          fitted Kramers amplitude
%     .absorption   fitted absorption rolloff (0 when FitAbsorption=false)
%     .e0KeV        echoed beam energy
%     .keepMask     [numel(energy) x 1] logical, true where a channel was
%                   used in the fit (peaks and exclude windows removed)
%     .reducedChi2  weighted SSE over kept channels, divided by
%                   max(nnz(keepMask) - nParams, 1)
%     .exitFlag     fminsearch exit flag (1 = converged normally)
%
%   Positivity parameterisation
%   ----------------------------
%   fminsearch is unconstrained, so (amp, absorption) are recovered from
%   free reals (theta1, theta2) via:
%
%       amp        = exp(theta1)        always > 0
%       absorption = expm1(theta2^2)    always >= 0
%
%   Squaring theta2 makes the argument to expm1 non-negative for ANY real
%   theta2, and expm1 is the exact inverse of log1p -- hence "log1p-style".
%   theta2=0 recovers absorption=0 exactly, matching the pure-Kramers seed,
%   so the default initial guess starts exactly on the Kramers-only curve.
%
%   Example
%   -------
%     r = imaging.eds.fitContinuum(e, counts, 18.0, Elements={'Fe','Cu'});
%     plot(e, counts, e, r.continuum);
%
%   See also IMAGING.EDS.SUBTRACTCONTINUUM, IMAGING.EDS.FANORESOLUTION,
%            IMAGING.EDS.LINEENERGY, IMAGING.EDS.ELEMENTMAP
%
%   Reference: Kramers, Phil. Mag. 46 (1923) 836; Goldstein et al.,
%   Scanning Electron Microscopy and X-ray Microanalysis, 4th ed., ch. 6.
%   Port of fermiviewer calc/eds_continuum.py (fit_continuum).

    arguments
        energy  (:,1) double
        counts  (:,1) double
        e0KeV   (1,1) double
        options.Elements           cell = {}
        options.ExcludeWindows     (:,2) double = zeros(0,2)
        options.ExcludeWidthFactor (1,1) double = 3.0
        options.FitAbsorption      (1,1) logical = true
        options.Weights            (1,1) string = "poisson"
    end

    if numel(energy) ~= numel(counts)
        error('imaging:eds:fitContinuum:lengthMismatch', ...
            'energy and counts must have equal length.');
    end
    if ~isfinite(e0KeV)
        error('imaging:eds:fitContinuum:missingE0KeV', ...
            'e0KeV (beam energy, keV) must be finite.');
    end

    % ── Peak mask: keep=true where NO excluded peak sits (fit those) ──────
    keep = true(size(energy));
    for k = 1:numel(options.Elements)
        sym = options.Elements{k};
        for fam = ["K", "L", "M"]
            [eLine, used] = imaging.eds.lineEnergy(string(sym), Line=fam);
            if isempty(used) || isnan(eLine)
                continue;
            end
            fwhmEV = imaging.eds.fanoResolution(eLine);
            half = options.ExcludeWidthFactor * fwhmEV / 1000;   % eV -> keV
            keep = keep & ~(energy >= eLine - half & energy <= eLine + half);
        end
    end
    for k = 1:size(options.ExcludeWindows, 1)
        lo = options.ExcludeWindows(k, 1);
        hi = options.ExcludeWindows(k, 2);
        keep = keep & ~(energy >= lo & energy <= hi);
    end
    keep = keep & (energy < e0KeV);   % only fit the sub-beam-energy continuum
    if nnz(keep) < 2
        error('imaging:eds:fitContinuum:tooFewChannels', ...
            'Fewer than 2 channels remain after peak masking.');
    end

    % ── Weights: base scheme x keep-mask (0 under peaks => excluded) ──────
    switch lower(char(options.Weights))
        case 'poisson'
            base = 1 ./ max(counts, 1);
        case 'none'
            base = ones(size(counts));
        otherwise
            error('imaging:eds:fitContinuum:unknownWeights', ...
                'Unknown weights scheme "%s".', options.Weights);
    end
    w = base .* keep;

    amp0 = max(median(counts(keep)), 1e-6);
    fitOpts = optimset('Display', 'off');

    if options.FitAbsorption
        theta0 = [log(amp0); 0];
        [theta, ~, exitFlag] = fminsearch( ...
            @(t) weightedSSE(t, energy, counts, w, e0KeV, true), theta0, fitOpts);
        amp = exp(theta(1));
        absorption = expm1(theta(2)^2);
        nParams = 2;
    else
        theta0 = log(amp0);
        [theta, ~, exitFlag] = fminsearch( ...
            @(t) weightedSSE(t, energy, counts, w, e0KeV, false), theta0, fitOpts);
        amp = exp(theta(1));
        absorption = 0;
        nParams = 1;
    end

    continuum = kramersCurve(energy, e0KeV, amp, absorption);
    resid = (continuum - counts) .* sqrt(w);
    sse = sum(resid .^ 2);
    dof = max(nnz(keep) - nParams, 1);

    result.continuum   = continuum;
    result.amp         = amp;
    result.absorption  = absorption;
    result.e0KeV       = e0KeV;
    result.keepMask    = keep;
    result.reducedChi2 = sse / dof;
    result.exitFlag    = exitFlag;
end


function sse = weightedSSE(theta, energy, counts, w, e0KeV, fitAbsorption)
%WEIGHTEDSSE  fminsearch objective: weighted sum of squared residuals.
%   Masked (zero-weight) channels contribute exactly zero regardless of
%   their residual, so the SSE reflects only the kept channels.
    amp = exp(theta(1));
    if fitAbsorption
        absorption = expm1(theta(2)^2);
    else
        absorption = 0;
    end
    model = kramersCurve(energy, e0KeV, amp, absorption);
    resid = (model - counts) .* sqrt(w);
    sse = sum(resid .^ 2);
end


function c = kramersCurve(energy, e0KeV, amp, absorption)
%KRAMERSCURVE  Detector-shaped Kramers continuum, amp*(E0-E)/E.*exp(-absorption/E).
%   Zero at and above e0KeV. absorption=0 is pure Kramers. Port of
%   eds_continuum.py's kramers_continuum.
    e = max(energy, 1e-9);
    c = amp * max(e0KeV - e, 0) ./ e;
    if absorption > 0
        c = c .* exp(-absorption ./ e);
    end
end
