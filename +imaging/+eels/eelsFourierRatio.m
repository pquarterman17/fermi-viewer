function ssd = eelsFourierRatio(energyAxis, coreSpectrum, lowLossSpectrum, opts)
%EELSFOURIERRATIO  Remove plural scattering via Fourier-ratio deconvolution.
%
%   Syntax:
%       ssd = imaging.eels.eelsFourierRatio(energyAxis, coreSpectrum, lowLossSpectrum)
%       ssd = imaging.eels.eelsFourierRatio(energyAxis, coreSpectrum, lowLossSpectrum, ...
%           ZLPWindow=[-5 5], Regularize=1e-6)
%       ssd = imaging.eels.eelsFourierRatio(energyAxis, coreSpectrum, lowLossSpectrum, ...
%           ZLPRef=zlpVector)
%
%   Applies the Fourier-ratio method (Egerton, "Electron Energy-Loss
%   Spectroscopy in the Electron Microscope", §4.3) to remove plural
%   scattering from a core-loss edge, using the low-loss spectrum as the
%   plural-scattering point-spread function:
%
%       SSD = IFFT{ FFT(core) ./ FFT(low) .* FFT(zlp) }
%
%   Dividing by the low-loss spectrum's Fourier transform undoes the
%   convolution with the plasmon/multiple-scattering series; multiplying
%   back by the zero-loss peak's transform reconvolves with the (much
%   narrower) instrument response, restoring the original energy
%   resolution and damping the high-frequency noise amplification that a
%   bare deconvolution would otherwise introduce.
%
%   Inputs:
%       energyAxis      — [N x 1] energy-loss axis (eV), shared by both
%                          spectra, monotonically increasing
%       coreSpectrum    — [N x 1] core-loss (plural-scattered) spectrum
%       lowLossSpectrum — [N x 1] low-loss spectrum acting as the PSF (its
%                          ZLP should sit near E = 0); resample to
%                          energyAxis before calling if the two spectra
%                          were acquired on different energy scales
%
%   Optional Name-Value:
%       ZLPWindow   — [E_lo, E_hi] eV window used to extract the zero-loss
%                     peak from lowLossSpectrum.  Default: [-5, 5] eV.
%       ZLPRef      — [N x 1] externally measured ZLP vector (same energy
%                     axis).  When provided, ZLPWindow is ignored.
%       Regularize  — Floor fraction applied to |FFT(lowLossSpectrum)|
%                     before division to suppress noise amplification.
%                     Default: 1e-6.
%
%   Outputs:
%       ssd — [N x 1] single-scattering core-loss distribution (non-negative)
%
%   Examples:
%       % Deconvolve using the ZLP extracted automatically from the low-loss
%       ssd = imaging.eels.eelsFourierRatio(E, coreLoss, lowLoss);
%       plot(E, coreLoss, E, ssd); legend('Plural-scattered','SSD');
%
%       % Supply an externally acquired vacuum ZLP
%       ssd = imaging.eels.eelsFourierRatio(E, coreLoss, lowLoss, ZLPRef=zlp_vacuum);
%
%   See also imaging.eels.eelsFourierLog, imaging.eels.eelsRichardsonLucy,
%            imaging.eels.eelsKramersKronig

% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    energyAxis      (:,1) double {mustBeNonempty}
    coreSpectrum    (:,1) double {mustBeNonempty}
    lowLossSpectrum (:,1) double {mustBeNonempty}
    opts.ZLPWindow   (1,2) double  = [-5, 5]
    opts.ZLPRef      (:,1) double  = []
    opts.Regularize  (1,1) double  {mustBePositive} = 1e-6
end

energyAxis      = double(energyAxis(:));
coreSpectrum    = double(coreSpectrum(:));
lowLossSpectrum = double(lowLossSpectrum(:));
N               = numel(energyAxis);

if numel(coreSpectrum) ~= N || numel(lowLossSpectrum) ~= N
    error('imaging:eels:eelsFourierRatio:sizeMismatch', ...
        'energyAxis, coreSpectrum and lowLossSpectrum must have the same number of elements.');
end

% ════════════════════════════════════════════════════════════════════════
%  Extract / validate ZLP
% ════════════════════════════════════════════════════════════════════════
if isempty(opts.ZLPRef)
    zlpMask = energyAxis >= opts.ZLPWindow(1) & energyAxis <= opts.ZLPWindow(2);
    if sum(zlpMask) < 2
        error('imaging:eels:eelsFourierRatio:tooFewZLPPoints', ...
            'ZLPWindow [%.1f, %.1f] eV contains fewer than 2 data points.', ...
            opts.ZLPWindow(1), opts.ZLPWindow(2));
    end
    zlp = zeros(N, 1);
    zlp(zlpMask) = lowLossSpectrum(zlpMask);
else
    zlp = double(opts.ZLPRef(:));
    if numel(zlp) ~= N
        error('imaging:eels:eelsFourierRatio:zlpSizeMismatch', ...
            'ZLPRef must have the same length as energyAxis (%d), got %d.', ...
            N, numel(zlp));
    end
end

% Guard the low-loss and ZLP against negative/zero values (division and
% FFT-magnitude regularization below assume strictly-positive spectra;
% the core spectrum itself is left as-is — it is only ever multiplied).
lowGuard = max(lowLossSpectrum, eps);
zlpGuard = max(zlp,             eps);

% ════════════════════════════════════════════════════════════════════════
%  Fourier-ratio deconvolution
% ════════════════════════════════════════════════════════════════════════
% Zero-pad to next power of 2 beyond 2*N to avoid circular wrap-around
N2 = 2 ^ nextpow2(2 * N);

C   = fft(coreSpectrum, N2);
Low = fft(lowGuard,     N2);
Z   = fft(zlpGuard,     N2);

% Regularize the denominator (low-loss spectrum) against division by
% near-zero values: floor tiny magnitudes while preserving phase, exactly
% as eelsFourierLog.m regularizes its ZLP transform.
lThresh   = opts.Regularize * max(abs(Low));
smallMask = abs(Low) < lThresh;
Low(smallMask) = lThresh * exp(1i * angle(Low(smallMask)));

ssdPad = real(ifft(C ./ Low .* Z));

% ════════════════════════════════════════════════════════════════════════
%  Truncate and clamp
% ════════════════════════════════════════════════════════════════════════
ssd = ssdPad(1:N);
ssd = max(ssd, 0);

end
