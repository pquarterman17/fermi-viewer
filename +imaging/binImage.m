function outImg = binImage(img, options)
%BINIMAGE  Spatially bin (downsample) an image by summing or averaging NxN blocks.
%
%   Syntax:
%       outImg = imaging.binImage(img)
%       outImg = imaging.binImage(img, BinSize=4)
%       outImg = imaging.binImage(img, BinSize=2, Mode='sum')
%
%   Divides the image into non-overlapping BinSize×BinSize blocks and
%   replaces each block with its mean (Mode='average') or total
%   (Mode='sum').  Rows and columns that do not form a complete block at
%   the edge are discarded.  No Image Processing Toolbox required.
%
%   Inputs:
%       img             — [H x W] numeric matrix (any integer or float type)
%
%   Optional Name-Value:
%       BinSize — side length of the square binning block in pixels
%                 (default: 2, must be a positive integer ≥ 1)
%       Mode    — 'average' (default) divides by BinSize²; 'sum' keeps total
%                 counts (useful for photon-counting detectors)
%
%   Output:
%       outImg — [floor(H/BinSize) x floor(W/BinSize)] double matrix
%
%   Examples:
%       binned = imaging.binImage(rawImg);                    % 2×2 average
%       binned = imaging.binImage(rawImg, BinSize=4);
%       binned = imaging.binImage(rawImg, BinSize=2, Mode='sum');
%
%   See also imaging.generateThumbnail, imaging.adjustContrast

% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    img              (:,:) {mustBeNumeric}
    options.BinSize (1,1) double {mustBePositive, mustBeInteger} = 2
    options.Mode    (1,1) string {mustBeMember(options.Mode, {'average','sum'})} = 'average'
end

% ════════════════════════════════════════════════════════════════════════
%  Trim image so dimensions are divisible by BinSize
% ════════════════════════════════════════════════════════════════════════
N        = options.BinSize;
[H, W]   = size(img);
H2       = floor(H / N) * N;
W2       = floor(W / N) * N;
img2     = double(img(1:H2, 1:W2));

% ════════════════════════════════════════════════════════════════════════
%  Reshape into blocks and reduce
%   reshape to [N, H2/N, N, W2/N] interleaves pixel and block indices:
%     dim 1: pixel row within block
%     dim 2: block row index
%     dim 3: pixel col within block
%     dim 4: block col index
% ════════════════════════════════════════════════════════════════════════
tmp = reshape(img2, N, H2/N, N, W2/N);

if strcmp(options.Mode, 'sum')
    outImg = squeeze(sum(sum(tmp, 1), 3));
else
    outImg = squeeze(mean(mean(tmp, 1), 3));
end

end
