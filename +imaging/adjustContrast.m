function outImg = adjustContrast(img, options)
%ADJUSTCONTRAST  Linear window/level contrast stretch on a 2-D image.
%
%   Syntax:
%       outImg = imaging.adjustContrast(img, Low=lo, High=hi)
%       outImg = imaging.adjustContrast(img, Low=lo, High=hi, Clamp=false)
%
%   Applies a linear stretch so that pixel value Low maps to 0 and High
%   maps to 1.  Values outside [Low, High] are clamped to [0, 1] by
%   default.  When Low == High the output is all zeros.
%
%   Inputs:
%       img   — [H x W] numeric matrix (any integer or float type)
%       Low   — lower window bound (scalar double)
%       High  — upper window bound (scalar double)
%
%   Optional Name-Value:
%       Clamp — logical; clamp output to [0,1] (default: true)
%
%   Output:
%       outImg — [H x W] double matrix in [0, 1] (or wider if Clamp=false)
%
%   Examples:
%       % Stretch a 16-bit image to display range
%       img16  = uint16(rand(512,512) * 65535);
%       dispImg = imaging.adjustContrast(img16, Low=1000, High=50000);
%
%       % Without clamping (values outside window are preserved as <0 or >1)
%       dispImg = imaging.adjustContrast(img16, Low=1000, High=50000, Clamp=false);
%
%   See also imaging.applyGaussian, imaging.applyMedian, imaging.generateThumbnail

% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    img    (:,:) {mustBeNumeric}
    options.Low   (1,1) double
    options.High  (1,1) double
    options.Clamp (1,1) logical = true
end

% ════════════════════════════════════════════════════════════════════════
%  Stretch
% ════════════════════════════════════════════════════════════════════════
d = double(img);

span = options.High - options.Low;

if span == 0
    outImg = zeros(size(d));
    return
end

outImg = (d - options.Low) / span;

if options.Clamp
    outImg = max(0, min(1, outImg));
end

end
