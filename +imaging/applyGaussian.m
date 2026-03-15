function outImg = applyGaussian(img, options)
%APPLYGAUSSIAN  2-D Gaussian blur using a manually constructed kernel.
%
%   Syntax:
%       outImg = imaging.applyGaussian(img)
%       outImg = imaging.applyGaussian(img, Sigma=2.0)
%
%   Builds a 2-D Gaussian kernel with half-width ceil(3*Sigma) and applies
%   it via conv2.  No Image Processing Toolbox required.
%
%   Inputs:
%       img   — [H x W] numeric matrix (any integer or float type)
%
%   Optional Name-Value:
%       Sigma — Gaussian standard deviation in pixels (default: 1.0, must be > 0)
%
%   Output:
%       outImg — [H x W] double matrix; same spatial dimensions as img
%
%   Examples:
%       blurred = imaging.applyGaussian(rawImg, Sigma=1.5);
%
%   See also imaging.applyMedian, imaging.adjustContrast

% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    img           (:,:) {mustBeNumeric}
    options.Sigma (1,1) double {mustBePositive} = 1.0
end

% ════════════════════════════════════════════════════════════════════════
%  Build Gaussian kernel
% ════════════════════════════════════════════════════════════════════════
hw = ceil(3 * options.Sigma);           % half-width: 3-sigma truncation
kernelSize = 2 * hw + 1;

ax = (-hw : hw);                        % 1-D axis centred at 0
[X, Y] = meshgrid(ax, ax);

h = exp(-0.5 * (X.^2 + Y.^2) / options.Sigma^2);
h = h / sum(h(:));                      % normalise so energy is preserved

% ════════════════════════════════════════════════════════════════════════
%  Apply convolution
% ════════════════════════════════════════════════════════════════════════
outImg = conv2(double(img), h, 'same');

end
