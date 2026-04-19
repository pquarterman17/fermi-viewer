function [ssd, tOverLambda] = eelsFourierLog(energyAxis, spectrum, opts)
%EELSFOURIERLOG  Remove plural scattering via Fourier-log deconvolution.
%
%   Syntax:
%       [ssd, tOverLambda] = imaging.eelsFourierLog(energyAxis, spectrum)
%       [ssd, tOverLambda] = imaging.eelsFourierLog(energyAxis, spectrum, ...
%           ZLPWindow=[-5 5], Regularize=1e-6)
%       [ssd, tOverLambda] = imaging.eelsFourierLog(energyAxis, spectrum, ...
%           ZLPRef=zlpVector)
%
%   Applies the Fourier-log method (Egerton, "Electron Energy-Loss
%   Spectroscopy in the Electron Microscope", Ch. 4) to isolate the
%   single-scattering distribution (SSD) from a measured EELS spectrum
%   that contains contributions from plural (multiple) scattering events.
%
%   Inputs:
%       energyAxis — [N x 1] energy-loss axis (eV), monotonically increasing
%       spectrum   — [N x 1] measured EELS intensity (counts or cps)
%
%   Optional Name-Value:
%       ZLPWindow   — [E_lo, E_hi] eV window used to extract the zero-loss
%                     peak from the spectrum itself.  Default: [-5, 5] eV.
%       ZLPRef      — [N x 1] externally measured ZLP vector (same energy
%                     axis as spectrum).  When provided, ZLPWindow is
%                     ignored.
%       Regularize  — Floor fraction applied to |FFT(ZLP)| before division
%                     to suppress noise amplification.  Default: 1e-6.
%
%   Outputs:
%       ssd         — [N x 1] single-scattering distribution (non-negative)
%       tOverLambda — scalar relative specimen thickness  t/λ = ln(I_t/I_0)
%
%   Examples:
%       % Deconvolve using the ZLP extracted automatically from the spectrum
%       [ssd, tL] = imaging.eelsFourierLog(E, I);
%       fprintf('t/lambda = %.3f\n', tL);
%       plot(E, I, E, ssd); legend('Measured','SSD');
%
%       % Supply an externally acquired vacuum ZLP
%       [ssd, tL] = imaging.eelsFourierLog(E, I, ZLPRef=zlp_vacuum);
%
%   See also imaging.eelsBackground, imaging.eelsELNES,
%            imaging.eelsKramersKronig

% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    energyAxis (:,1) double {mustBeNonempty}
    spectrum   (:,1) double {mustBeNonempty}
    opts.ZLPWindow   (1,2) double  = [-5, 5]
    opts.ZLPRef      (:,1) double  = []
    opts.Regularize  (1,1) double  {mustBePositive} = 1e-6
end

energyAxis = double(energyAxis(:));
spectrum   = double(spectrum(:));
N          = numel(energyAxis);

if numel(spectrum) ~= N
    error('imaging:eelsFourierLog:sizeMismatch', ...
        'energyAxis and spectrum must have the same number of elements.');
end

% ════════════════════════════════════════════════════════════════════════
%  Extract / validate ZLP
% ════════════════════════════════════════════════════════════════════════
if isempty(opts.ZLPRef)
    % Build ZLP from the spectrum: copy counts inside the ZLP window,
    % set everything outside to zero.
    zlpMask = energyAxis >= opts.ZLPWindow(1) & energyAxis <= opts.ZLPWindow(2);
    if sum(zlpMask) < 2
        error('imaging:eelsFourierLog:tooFewZLPPoints', ...
            'ZLPWindow [%.1f, %.1f] eV contains fewer than 2 data points.', ...
            opts.ZLPWindow(1), opts.ZLPWindow(2));
    end
    zlp        = zeros(N, 1);
    zlp(zlpMask) = spectrum(zlpMask);
else
    zlp = double(opts.ZLPRef(:));
    if numel(zlp) ~= N
        error('imaging:eelsFourierLog:zlpSizeMismatch', ...
            'ZLPRef must have the same length as energyAxis (%d), got %d.', ...
            N, numel(zlp));
    end
end

% Guard against negative or zero values before log operations
specGuard = max(spectrum, eps);
zlpGuard  = max(zlp,      eps);

% ════════════════════════════════════════════════════════════════════════
%  Relative thickness
% ════════════════════════════════════════════════════════════════════════
I_t     = sum(specGuard);   % total integrated intensity
I_0     = sum(zlpGuard);    % ZLP-only integrated intensity
tOverLambda = log(I_t / I_0);

% ════════════════════════════════════════════════════════════════════════
%  Fourier-log deconvolution
% ════════════════════════════════════════════════════════════════════════
% Zero-pad to next power of 2 beyond 2*N to avoid circular wrap-around
N2 = 2 ^ nextpow2(2 * N);

S = fft(specGuard, N2);
Z = fft(zlpGuard,  N2);

% Regularize: floor tiny ZLP spectral values to avoid division blow-up
zThresh   = opts.Regularize * max(abs(Z));
smallMask = abs(Z) < zThresh;
Z(smallMask) = zThresh * exp(1i * angle(Z(smallMask)));  % keep phase, raise magnitude

% Core Fourier-log formula (Egerton eq. 4.11):
%   J_1(E) = IFT{ Z(nu) * ln[ S(nu) / Z(nu) ] }
%
% Normalization: evaluating the frequency-zero component gives
%   Z(0) * ln(S(0)/Z(0)) = I_0 * ln(I_t / I_0) = I_0 * (t/lambda),
% so sum(ssd)*dE = I_0 * (t/lambda) — the expected SSD integral for
% low t/lambda. No additional I_0 scaling is required.
ratio = S ./ Z;

% Regularize the ratio: floor tiny-magnitude values while preserving
% phase — matches the Z-floor at line 111 and avoids a spurious branch
% cut. The previous implementation clamped only `real(ratio)` to eps,
% leaving `imag(ratio)` untouched, which creates a discontinuous branch
% wherever Re(ratio) crossed zero (and silently broke ln's branch
% choice). Magnitude regularization is the physically correct form for
% a complex log and is what Egerton Ch. 4.3.2 recommends.
rThresh  = opts.Regularize * max(abs(ratio));
smallR   = abs(ratio) < rThresh;
ratio(smallR) = rThresh * exp(1i * angle(ratio(smallR)));

ssdPad = real(ifft(Z .* log(ratio)));

% ════════════════════════════════════════════════════════════════════════
%  Truncate and clamp
% ════════════════════════════════════════════════════════════════════════
ssd = ssdPad(1:N);
ssd = max(ssd, 0);

end
