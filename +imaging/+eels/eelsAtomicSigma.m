function atomicPercentSigma = eelsAtomicSigma(energyAxis, spectrum, signalWindows, arealRatio, sigma)
%EELSATOMICSIGMA  1-sigma Poisson uncertainty on EELS at% composition.
%
%   Syntax:
%       atomicPercentSigma = imaging.eels.eelsAtomicSigma(energyAxis, ...
%                                spectrum, signalWindows, arealRatio, sigma)
%
%   Companion to imaging.eels.eelsQuantify: attaches a 1-sigma error bar to
%   every at% value using Poisson counting statistics on the GROSS (not
%   background-subtracted) spectrum the quantification was run on.
%
%   PHYSICS / DERIVATION
%   ------------------------------------------------------------------------
%   1. Each recorded channel N_k is an independent Poisson count, so
%      var(N_k) = N_k.  For edge X, the background-subtracted net intensity
%      is a trapezoid integral over the signal window, I_X = sum_k w_k*N_k,
%      where w_k are the exact per-sample trapezoid weights (interior
%      w_k = (x_{k+1}-x_{k-1})/2, half-intervals at the window ends — see
%      the local trapezoidWeights helper below).  Using the GROSS counts
%      (rather than the background-subtracted signal) for the variance is
%      exactly Egerton's leading-order net-signal variance,
%      var(I_net) ~= I_net + I_bg; the background-fit extrapolation
%      refinement (his "h" factor) is a documented second-order term this
%      routine omits.  Independence of the w_k*N_k terms gives
%          var(I_X) = sum_k w_k^2 * N_k .
%   2. r_X = I_X / sigma_X with sigma_X a FIXED (pixel/noise-independent)
%      partial cross-section, so var(r_X) = var(I_X) / sigma_X^2.
%   3. The at% normalisation at%_i = 100 * r_i / sum_j r_j has Jacobian
%          J_ij = (delta_ij - frac_i) / S ,   S = sum_j r_j, frac_i = r_i/S.
%      Edges are independent counting experiments, so cov(r) is diagonal,
%      and the delta method reduces to
%          var(at%_i) = 100^2 * sum_j J_ij^2 * var(r_j) .
%      A non-positive or non-finite total S, or a zero/undefined cross-
%      section for any edge, yields NaN for ALL elements (the covariance
%      is no longer block-diagonal once any var(r_j) is NaN) — this is a
%      deliberate PINNED behaviour, not a bug.
%
%   Inputs:
%       energyAxis    — [N x 1] the GROSS energy-loss axis eelsQuantify was
%                       run on (eV)
%       spectrum      — [N x 1] the GROSS spectrum eelsQuantify was run on
%                       (counts; NOT background-subtracted — Poisson shot
%                       noise is set by the recorded events, not the
%                       subtracted signal)
%       signalWindows — [M x 2] per-edge [E1 E2] integration windows, in the
%                       SAME ORDER as arealRatio/sigma (i.e. elements order)
%       arealRatio    — [1 x M] r_X = I_X/sigma_X (eelsQuantify result.arealRatio)
%       sigma         — [1 x M] partial cross-sections (eelsQuantify result.sigma)
%
%   Outputs:
%       atomicPercentSigma — [1 x M] 1-sigma error on atomicPercent, in
%                            PERCENTAGE POINTS (matching the at% convention)
%
%   Examples:
%       r = imaging.eels.eelsQuantify(E, I, el, 200, 10);
%       sigAt = imaging.eels.eelsAtomicSigma(E, I, vertcat(el.signalWindow), ...
%                   r.arealRatio, r.sigma);
%       fprintf('%s: %.1f +/- %.1f at%%\n', r.element(1), r.atomicPercent(1), sigAt(1));
%
%   See also imaging.eels.eelsQuantify, imaging.eels.eelsCrossSection
%
% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    energyAxis    (:,1) double {mustBeNonempty}
    spectrum      (:,1) double {mustBeNonempty}
    signalWindows (:,2) double {mustBeNonempty}
    arealRatio    (1,:) double {mustBeNonempty}
    sigma         (1,:) double {mustBeNonempty}
end

energyAxis = double(energyAxis(:));
spectrum   = double(spectrum(:));

if numel(energyAxis) ~= numel(spectrum)
    error('imaging:eels:eelsAtomicSigma:sizeMismatch', ...
        'energyAxis and spectrum must have the same number of elements.');
end

M = size(signalWindows, 1);
if numel(arealRatio) ~= M || numel(sigma) ~= M
    error('imaging:eels:eelsAtomicSigma:sizeMismatch', ...
        'signalWindows (M=%d), arealRatio (%d), and sigma (%d) must have matching length.', ...
        M, numel(arealRatio), numel(sigma));
end

% ════════════════════════════════════════════════════════════════════════
%  Per-edge Poisson variance of the trapezoid-integrated GROSS intensity
% ════════════════════════════════════════════════════════════════════════
varI = zeros(M, 1);
for k = 1:M
    mask = energyAxis >= signalWindows(k,1) & energyAxis <= signalWindows(k,2);
    if sum(mask) < 2
        varI(k) = NaN;
    else
        w = trapezoidWeights(energyAxis(mask));
        c = max(spectrum(mask), 0);          % negative (over-subtracted) clamps to 0
        varI(k) = sum(w.^2 .* c);
    end
end

% r = I/sigma  =>  var(r) = var(I)/sigma^2   (sigma is a fixed cross-section)
sigmaCol = sigma(:);
varR = nan(M, 1);
safe = sigmaCol > 0;
varR(safe) = varI(safe) ./ sigmaCol(safe).^2;

% ════════════════════════════════════════════════════════════════════════
%  Delta-method propagation through the at% normalisation
% ════════════════════════════════════════════════════════════════════════
q = arealRatio(:);
S = sum(q);
if ~isfinite(S) || S <= 0
    atomicPercentSigma = nan(1, M);
    return;
end

frac   = q / S;                              % [M x 1]
jacMat = (eye(M) - frac) / S;                % J_ij = (delta_ij - frac_i)/S
varAt  = sum((jacMat .^ 2) .* varR(:)', 2);  % var(at%_i)/100^2, [M x 1]

% Clamp only genuine negative round-off; NaN must propagate (unlike
% MATLAB's max(), which silently drops NaN operands).
neg = ~isnan(varAt) & varAt < 0;
varAt(neg) = 0;

atomicPercentSigma = 100 * sqrt(varAt)';

end


% ════════════════════════════════════════════════════════════════════════
%  Local helpers
% ════════════════════════════════════════════════════════════════════════
function w = trapezoidWeights(x)
%TRAPEZOIDWEIGHTS  Per-sample weights w such that sum(w.*y) == trapz(x,y).
%   Interior sample y_k gets weight (x_{k+1}-x_{k-1})/2; the endpoints get
%   half their single adjacent interval. These weights let Poisson variance
%   flow through a trapezoid integral as var(I) = sum(w.^2 .* var(y)).
x = double(x(:));
n = numel(x);
if n < 2
    error('imaging:eels:eelsAtomicSigma:tooFewSamples', ...
        'need at least 2 samples for a trapezoid weight.');
end
w = zeros(n, 1);
w(1)       = 0.5 * (x(2)   - x(1));
w(end)     = 0.5 * (x(end) - x(end-1));
w(2:end-1) = 0.5 * (x(3:end) - x(1:end-2));
end
