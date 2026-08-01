function deconv = eelsRichardsonLucy(spectrum, psf, opts)
%EELSRICHARDSONLUCY  Richardson-Lucy iterative deconvolution of an EELS spectrum.
%
%   Syntax:
%       deconv = imaging.eels.eelsRichardsonLucy(spectrum, psf)
%       deconv = imaging.eels.eelsRichardsonLucy(spectrum, psf, Iterations=40)
%
%   Recovers resolution lost to a known point-spread function (typically
%   the zero-loss peak, ZLP) via the multiplicative Richardson-Lucy update
%   (Poisson maximum-likelihood deconvolution):
%
%       u_(k+1) = u_k .* conv( d ./ conv(u_k, p, 'same'), flip(p), 'same' )
%
%   where d is the measured spectrum and p is the point-spread function,
%   normalized to unit sum.
%
%   The PSF is centred internally before iterating: its peak channel is
%   circularly shifted to floor(N/2)+1. This matters because conv(...,
%   'same') implicitly centres its kernel on the array midpoint — a PSF
%   whose peak sits elsewhere (e.g. a ZLP window cropped asymmetrically
%   about the true zero-loss channel, or one taken from a misaligned
%   region of the spectrum) silently shifts the *entire* deconvolved
%   spectrum by that same channel offset. There is no error or warning:
%   the output looks like a normal sharpened spectrum, just displaced, so
%   downstream peak-position measurements (e.g. edge onsets) would be
%   wrong without this correction.
%
%   Inputs:
%       spectrum — [N x 1] measured EELS spectrum (counts or cps)
%       psf      — [N x 1] point-spread function (e.g. an extracted ZLP
%                  window), at any position; re-centred and normalized to
%                  unit sum internally, so callers need not pre-centre it
%
%   Optional Name-Value:
%       Iterations — number of multiplicative RL update steps.
%                    Default: 15.
%
%   Outputs:
%       deconv — [N x 1] deconvolved spectrum (non-negative)
%
%   Examples:
%       % Sharpen a spectrum using its own ZLP window as the PSF
%       zlpMask = E >= -5 & E <= 5;
%       psf = zeros(size(E)); psf(zlpMask) = spectrum(zlpMask);
%       deconv = imaging.eels.eelsRichardsonLucy(spectrum, psf, Iterations=40);
%
%       % A PSF cropped off-centre is re-centred automatically
%       deconv = imaging.eels.eelsRichardsonLucy(spectrum, offCentrePSF);
%
%   See also imaging.eels.eelsFourierRatio, imaging.eels.eelsFourierLog

% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    spectrum (:,1) double {mustBeNonempty}
    psf      (:,1) double {mustBeNonempty}
    opts.Iterations (1,1) double {mustBePositive, mustBeInteger} = 15
end

d = max(double(spectrum(:)), 0);
p = double(psf(:));
N = numel(d);

if numel(p) ~= N
    error('imaging:eels:eelsRichardsonLucy:sizeMismatch', ...
        'psf must have the same number of elements as spectrum (%d), got %d.', ...
        N, numel(p));
end

pSum = sum(p);
if pSum <= 0
    error('imaging:eels:eelsRichardsonLucy:invalidPSF', ...
        'psf must have a positive sum.');
end

% ════════════════════════════════════════════════════════════════════════
%  Centre the PSF
% ════════════════════════════════════════════════════════════════════════
% conv(...,'same') centres its kernel on the array midpoint; a PSF whose
% peak sits elsewhere would otherwise shift the whole deconvolved
% spectrum by that offset with no visible error (see docstring above).
% Circularly shift the peak channel to floor(N/2)+1, matching the
% Python route's `np.roll(psf, ne // 2 - argmax(psf))` centring rule.
[~, peakIdx] = max(p);
targetIdx    = floor(N / 2) + 1;
p = circshift(p, targetIdx - peakIdx);
p = p / pSum;
pFlip = flipud(p);

% ════════════════════════════════════════════════════════════════════════
%  Multiplicative Richardson-Lucy update (Poisson MLE)
% ════════════════════════════════════════════════════════════════════════
u = d;
for k = 1:opts.Iterations
    conv1    = conv(u, p, 'same');
    relative = d ./ max(conv1, eps);
    u = u .* conv(relative, pFlip, 'same');
end

deconv = max(u, 0);

end
