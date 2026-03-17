function outImg = unsharpMask(img, options)
%UNSHARPMASK  Sharpen an image using an unsharp mask (no toolbox).
%
%   Syntax:
%       outImg = imaging.unsharpMask(img)
%       outImg = imaging.unsharpMask(img, Sigma=2.0)
%       outImg = imaging.unsharpMask(img, Sigma=1.5, Amount=0.8)
%
%   Computes a Gaussian-blurred version of the image and adds back a
%   scaled high-frequency residual:
%
%       outImg = img + Amount * (img - blurred)
%
%   The Gaussian kernel is built manually via exp(-0.5*(x²+y²)/σ²) and
%   applied with conv2.  No Image Processing Toolbox required.
%
%   Inputs:
%       img            — [H x W] numeric matrix (any integer or float type)
%
%   Optional Name-Value:
%       Sigma  — Gaussian standard deviation in pixels used for the blur
%                step (default: 2.0, must be > 0)
%       Amount — Strength of the sharpening (default: 1.0, typical 0–2).
%                Values > 1 produce aggressive sharpening; 0 returns the
%                original image unmodified.
%
%   Output:
%       outImg — [H x W] double matrix; values may exceed the input range
%                if Amount > 0.  Clip or rescale afterwards if needed.
%
%   Examples:
%       sharp = imaging.unsharpMask(rawImg);
%       sharp = imaging.unsharpMask(rawImg, Sigma=1.0, Amount=1.5);
%
%   See also imaging.applyGaussian, imaging.adjustContrast

% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    img             (:,:) {mustBeNumeric}
    options.Sigma  (1,1) double {mustBePositive} = 2.0
    options.Amount (1,1) double                  = 1.0
end

% ════════════════════════════════════════════════════════════════════════
%  Build Gaussian kernel (matches applyGaussian kernel construction)
% ════════════════════════════════════════════════════════════════════════
hw = ceil(3 * options.Sigma);       % half-width: 3-sigma truncation
ax = (-hw : hw);                    % 1-D axis centred at 0
[X, Y] = meshgrid(ax, ax);

h = exp(-0.5 * (X.^2 + Y.^2) / options.Sigma^2);
h = h / sum(h(:));                  % normalise to preserve energy

% ════════════════════════════════════════════════════════════════════════
%  Compute unsharp mask and add residual
% ════════════════════════════════════════════════════════════════════════
d       = double(img);
blurred = conv2(d, h, 'same');
outImg  = d + options.Amount * (d - blurred);

end
