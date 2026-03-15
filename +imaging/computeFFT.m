function [magImg, phaseImg] = computeFFT(img)
%COMPUTEFFT  2-D FFT magnitude and phase of a grayscale image.
%
%   Syntax:
%       magImg            = imaging.computeFFT(img)
%       [magImg, phaseImg] = imaging.computeFFT(img)
%
%   Computes the 2-D discrete Fourier transform, shifts the DC component
%   to the centre, and returns the log-scaled magnitude for display.
%   The phase image is only computed when a second output is requested.
%
%   Inputs:
%       img      — [H x W] numeric matrix (any integer or float type)
%
%   Outputs:
%       magImg   — [H x W] double; log10(1 + |F|) after fftshift
%       phaseImg — [H x W] double; angle(F) in radians (optional)
%
%   Examples:
%       mag = imaging.computeFFT(rawImg);
%       imagesc(mag); colormap gray; colorbar; title('FFT magnitude');
%
%       [mag, ph] = imaging.computeFFT(rawImg);
%
%   See also imaging.adjustContrast, imaging.lineProfile

% ════════════════════════════════════════════════════════════════════════
%  Transform
% ════════════════════════════════════════════════════════════════════════
F = fft2(double(img));
F = fftshift(F);

% ════════════════════════════════════════════════════════════════════════
%  Outputs
% ════════════════════════════════════════════════════════════════════════
magImg = log10(1 + abs(F));

if nargout > 1
    phaseImg = angle(F);
end

end
