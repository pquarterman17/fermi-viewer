function outImg = butterworthFilter(img, options)
%BUTTERWORTHFILTER  Frequency-domain Butterworth bandpass filter (no toolbox).
%
%   Syntax:
%       outImg = imaging.butterworthFilter(img)
%       outImg = imaging.butterworthFilter(img, HighCutoff=0.3)
%       outImg = imaging.butterworthFilter(img, LowCutoff=0.05, HighCutoff=0.4, Order=4)
%
%   Filters the image in the frequency domain using a Butterworth transfer
%   function.  Cutoff frequencies are expressed as fractions of the Nyquist
%   frequency (0 = DC, 1 = Nyquist).
%
%   Steps:
%     1. FFT the image: F = fft2(double(img))
%     2. Build a normalised radial frequency grid D in [0, 1] centred on DC.
%     3. Construct the Butterworth transfer function:
%          H_lp = 1 ./ (1 + (D ./ HighCutoff).^(2*Order))   [low-pass]
%          H_hp = 1 ./ (1 + (LowCutoff ./ D).^(2*Order))    [high-pass, LowCutoff>0]
%          H    = H_lp .* H_hp
%     4. Apply: outImg = real(ifft2(fftshift(H) .* F))
%
%   The D==0 singularity in the high-pass term is handled by setting H_hp=1
%   at D==0 (DC component passes through unchanged when LowCutoff > 0).
%   No Image Processing Toolbox required.
%
%   Inputs:
%       img              — [H x W] numeric matrix (any integer or float type)
%
%   Optional Name-Value:
%       LowCutoff  — High-pass edge: normalised frequency below which content
%                    is attenuated (default: 0 — high-pass stage disabled).
%                    Set > 0 to suppress low-frequency background or drift.
%       HighCutoff — Low-pass edge: normalised frequency above which content
%                    is attenuated (default: 0.5 — half Nyquist).
%                    Must be in (0, 1].
%       Order      — Butterworth filter order; higher values give a sharper
%                    rolloff at the cutoff (default: 2).
%
%   Output:
%       outImg — [H x W] double matrix in the spatial domain.
%
%   Examples:
%       % Low-pass: suppress high-frequency noise
%       smooth = imaging.butterworthFilter(rawImg, HighCutoff=0.3, Order=4);
%
%       % High-pass: remove slowly varying background
%       detail = imaging.butterworthFilter(rawImg, LowCutoff=0.05, HighCutoff=1.0);
%
%       % Bandpass: keep a specific frequency band
%       band = imaging.butterworthFilter(rawImg, LowCutoff=0.05, HighCutoff=0.4);
%
%   See also imaging.applyGaussian, imaging.computeFFT, imaging.applyMedian

% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    img                 (:,:) {mustBeNumeric}
    options.LowCutoff  (1,1) double {mustBeNonnegative}                   = 0
    options.HighCutoff (1,1) double {mustBePositive}                      = 0.5
    options.Order      (1,1) double {mustBePositive, mustBeInteger}       = 2
end

% ════════════════════════════════════════════════════════════════════════
%  FFT
% ════════════════════════════════════════════════════════════════════════
d = double(img);
F = fft2(d);                        % F is in standard (unshifted) order

% ════════════════════════════════════════════════════════════════════════
%  Build normalised radial frequency grid
%   freqs run from 0 to 1 along each axis (DC at centre after fftshift).
%   We work in the *shifted* domain, then un-shift H before applying.
% ════════════════════════════════════════════════════════════════════════
[H, W] = size(d);

% Normalised frequency axes: 0 at DC, 1 at Nyquist
fu = linspace(-1, 1, W);
fv = linspace(-1, 1, H);
[U, V] = meshgrid(fu, fv);
D = sqrt(U.^2 + V.^2);             % radial normalised frequency [0 … sqrt(2)]
D = D / max(D(:));                  % scale so Nyquist corner = 1

% ════════════════════════════════════════════════════════════════════════
%  Butterworth transfer function (in shifted domain)
% ════════════════════════════════════════════════════════════════════════
n = 2 * options.Order;

% Low-pass component
H_lp = 1 ./ (1 + (D / options.HighCutoff).^n);

% High-pass component (skip if LowCutoff == 0)
if options.LowCutoff > 0
    H_hp        = 1 ./ (1 + (options.LowCutoff ./ D).^n);
    H_hp(D == 0) = 1;               % avoid 0/0 at DC; let DC pass through
else
    H_hp = ones(size(D));
end

H_shifted = H_lp .* H_hp;

% ════════════════════════════════════════════════════════════════════════
%  Apply filter and inverse FFT
%   ifftshift moves H back from centred to standard FFT order so it
%   aligns correctly with the unshifted F.
% ════════════════════════════════════════════════════════════════════════
outImg = real(ifft2(ifftshift(H_shifted) .* F));

end
