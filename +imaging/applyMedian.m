function outImg = applyMedian(img, options)
%APPLYMEDIAN  2-D median filter (no Image Processing Toolbox required).
%
%   Syntax:
%       outImg = imaging.applyMedian(img)
%       outImg = imaging.applyMedian(img, WindowSize=5)
%
%   Replaces each pixel with the median of its WindowSize x WindowSize
%   neighbourhood.  Edge pixels are handled with zero-padding.
%
%   Implementation uses vectorised column-stack extraction to avoid nested
%   loops: for each of the WindowSize^2 offsets the image is shifted and
%   stacked into a [H x W x WindowSize^2] array, then the median is
%   computed along the third dimension.  This keeps the operation purely
%   in MATLAB built-ins with no toolboxes.
%
%   Note: For large images (>2048 px) with WindowSize>3 the memory
%   footprint is O(H*W*WindowSize^2) doubles.  On a 4096x4096 image with
%   a 5x5 window this is ~3.2 GB — reduce WindowSize or pre-crop.
%
%   Inputs:
%       img        — [H x W] numeric matrix (any integer or float type)
%
%   Optional Name-Value:
%       WindowSize — odd integer in {3, 5, 7}; size of the filter window
%                    (default: 3)
%
%   Output:
%       outImg — [H x W] double matrix
%
%   Examples:
%       clean = imaging.applyMedian(noisyImg, WindowSize=3);
%
%   See also imaging.applyGaussian, imaging.adjustContrast

% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    img              (:,:) {mustBeNumeric}
    options.WindowSize (1,1) double ...
        {mustBeInteger, mustBeMember(options.WindowSize, [3 5 7])} = 3
end

% ════════════════════════════════════════════════════════════════════════
%  Setup
% ════════════════════════════════════════════════════════════════════════
W  = options.WindowSize;
hw = (W - 1) / 2;           % half-width: 1 for 3x3, 2 for 5x5, 3 for 7x7

d  = double(img);
[H, Wid] = size(d);

% Zero-pad on all four sides by hw pixels
padded = zeros(H + 2*hw, Wid + 2*hw);
padded(hw+1:hw+H, hw+1:hw+Wid) = d;

% ════════════════════════════════════════════════════════════════════════
%  Vectorised neighbourhood stack
%  For each (dr, dc) offset in [-hw..hw] x [-hw..hw], extract the shifted
%  sub-image that corresponds to that offset for every pixel.  Stack all
%  W^2 such sub-images along dimension 3, then median along dim 3.
% ════════════════════════════════════════════════════════════════════════
nPix    = W * W;
stack   = zeros(H, Wid, nPix);
k       = 0;

for dr = 0 : W-1
    for dc = 0 : W-1
        k = k + 1;
        stack(:, :, k) = padded(dr+1 : dr+H, dc+1 : dc+Wid);
    end
end

outImg = median(stack, 3);

end
