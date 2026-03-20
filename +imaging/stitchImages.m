function result = stitchImages(images, opts)
%STITCHIMAGES  Stitch overlapping images into a panoramic mosaic.
%
%   Uses cross-correlation at overlap regions to determine relative
%   offsets between adjacent images, then blends them into a single
%   composite.
%
%   Syntax:
%       result = imaging.stitchImages({img1, img2, img3})
%       result = imaging.stitchImages(images, Layout='horizontal')
%       result = imaging.stitchImages(images, OverlapFrac=0.2)
%
%   Inputs:
%       images      — cell array of [H x W] grayscale images (numeric)
%
%   Name-Value:
%       Layout      — 'horizontal' (default) | 'vertical' | 'auto'
%                     'auto' tries both orientations and picks the one
%                     with higher peak cross-correlation.
%       OverlapFrac — Expected overlap fraction in [0, 0.5], default 0.2
%       BlendWidth  — Blending transition width in pixels, default 50
%
%   Outputs:
%       result.mosaic    — [H' x W'] stitched composite image (double)
%       result.offsets   — [N x 2] cumulative [dy, dx] offsets for each
%                          image, relative to the first image (which is
%                          always [0, 0])
%       result.nImages   — number of input images
%       result.layout    — layout string actually used ('horizontal' or
%                          'vertical')
%
%   Examples:
%       imgs = {imread('tile1.tif'), imread('tile2.tif'), imread('tile3.tif')};
%       imgs = cellfun(@(x) double(x), imgs, 'UniformOutput', false);
%       r = imaging.stitchImages(imgs);
%       imagesc(r.mosaic); colormap gray; axis image;
%
%       % Vertical strip layout with 30 % overlap
%       r = imaging.stitchImages(imgs, Layout='vertical', OverlapFrac=0.3);
%
%   See also imaging.computeFFT, imaging.lineProfile

% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    images           (1,:) cell
    opts.Layout      (1,1) string  {mustBeMember(opts.Layout, ...
                         {'horizontal','vertical','auto'})} = 'horizontal'
    opts.OverlapFrac (1,1) double  {mustBeInRange(opts.OverlapFrac,0,0.5)} = 0.2
    opts.BlendWidth  (1,1) double  {mustBePositive}                        = 50
end

nImages = numel(images);
if nImages < 2
    error('imaging:stitchImages:tooFewImages', ...
          'At least 2 images are required for stitching.');
end

% Convert all images to double for consistent arithmetic
for k = 1:nImages
    images{k} = double(images{k});
    if ~ismatrix(images{k})
        error('imaging:stitchImages:notGrayscale', ...
              'Image %d is not a 2-D grayscale array.', k);
    end
end

% ════════════════════════════════════════════════════════════════════════
%  Layout selection
% ════════════════════════════════════════════════════════════════════════
if strcmp(opts.Layout, 'auto')
    layout = selectLayout(images, opts.OverlapFrac);
else
    layout = char(opts.Layout);
end

% ════════════════════════════════════════════════════════════════════════
%  Compute pairwise offsets via cross-correlation
% ════════════════════════════════════════════════════════════════════════
% offsets(k,:) = cumulative [dy, dx] of image k relative to image 1
offsets = zeros(nImages, 2);

for k = 1:(nImages - 1)
    imgA = images{k};
    imgB = images{k+1};

    [dy, dx] = computePairOffset(imgA, imgB, layout, opts.OverlapFrac);

    offsets(k+1, :) = offsets(k, :) + [dy, dx];
end

% ════════════════════════════════════════════════════════════════════════
%  Allocate output canvas
% ════════════════════════════════════════════════════════════════════════
[imgH, imgW] = size(images{1});

minDy = min(offsets(:,1));
maxDy = max(offsets(:,1));
minDx = min(offsets(:,2));
maxDx = max(offsets(:,2));

canvasH = imgH + maxDy - minDy;
canvasW = imgW + maxDx - minDx;

% Shift all offsets so the top-left of the canvas is (1,1) in 1-based coords
rowOrigin = 1 - minDy;   % row in canvas where image 1 starts (1-based)
colOrigin = 1 - minDx;   % col in canvas where image 1 starts

mosaic  = zeros(canvasH, canvasW);
weights = zeros(canvasH, canvasW);

% ════════════════════════════════════════════════════════════════════════
%  Place each image onto the canvas with linear alpha blending
% ════════════════════════════════════════════════════════════════════════
for k = 1:nImages
    dy = offsets(k, 1);
    dx = offsets(k, 2);

    rowStart = rowOrigin + dy;          % 1-based
    colStart = colOrigin + dx;
    rowEnd   = rowStart + imgH - 1;
    colEnd   = colStart + imgW - 1;

    [h, w] = size(images{k});

    alpha = buildAlpha(h, w, layout, opts.BlendWidth, k, nImages);

    mosaic(rowStart:rowEnd, colStart:colEnd) = ...
        mosaic(rowStart:rowEnd, colStart:colEnd) + images{k} .* alpha;
    weights(rowStart:rowEnd, colStart:colEnd) = ...
        weights(rowStart:rowEnd, colStart:colEnd) + alpha;
end

% Normalise by accumulated weights; avoid divide-by-zero in empty regions
validMask = weights > 0;
mosaic(validMask)  = mosaic(validMask) ./ weights(validMask);

% ════════════════════════════════════════════════════════════════════════
%  Assemble result struct
% ════════════════════════════════════════════════════════════════════════
result.mosaic  = mosaic;
result.offsets = offsets;
result.nImages = nImages;
result.layout  = layout;

end

% ════════════════════════════════════════════════════════════════════════
%  Local: select layout by testing cross-correlation on first pair
% ════════════════════════════════════════════════════════════════════════
function layout = selectLayout(images, overlapFrac)
%SELECTLAYOUT  Pick horizontal or vertical based on higher peak CC value.

imgA = images{1};
imgB = images{2};

[~, ~, peakH] = computePairOffset(imgA, imgB, 'horizontal', overlapFrac);
[~, ~, peakV] = computePairOffset(imgA, imgB, 'vertical',   overlapFrac);

if peakH >= peakV
    layout = 'horizontal';
else
    layout = 'vertical';
end
end

% ════════════════════════════════════════════════════════════════════════
%  Local: cross-correlate one adjacent pair → integer [dy, dx] shift
% ════════════════════════════════════════════════════════════════════════
function [dy, dx, peakVal] = computePairOffset(imgA, imgB, layout, overlapFrac)
%COMPUTEPAIROFFSET  FFT cross-correlation on overlap strips.
%
%   Returns the offset of imgB relative to imgA such that
%   imgB should be placed at (rowA + dy, colA + dx).

[hA, wA] = size(imgA);
[hB, wB] = size(imgB);

% Extract overlap strips from each image
if strcmp(layout, 'horizontal')
    % imgB is to the right of imgA: use right strip of A, left strip of B
    stripW = round(min(wA, wB) * overlapFrac);
    stripW = max(stripW, 4);               % minimum 4 pixels

    stripA = imgA(:, (wA - stripW + 1):wA);
    stripB = imgB(:, 1:stripW);

    % Pad strips to the same size for FFT
    padH = max(hA, hB);
    padW = stripW;
    pA   = padarray2d(stripA, padH, padW);
    pB   = padarray2d(stripB, padH, padW);

else
    % imgB is below imgA: use bottom strip of A, top strip of B
    stripH = round(min(hA, hB) * overlapFrac);
    stripH = max(stripH, 4);

    stripA = imgA((hA - stripH + 1):hA, :);
    stripB = imgB(1:stripH, :);

    padH = stripH;
    padW = max(wA, wB);
    pA   = padarray2d(stripA, padH, padW);
    pB   = padarray2d(stripB, padH, padW);
end

% Normalise strips to zero mean to reduce DC-offset bias
pA = pA - mean(pA(:));
pB = pB - mean(pB(:));

% FFT cross-correlation: cc(r,c) = sum_ij A(i,j)*B(i-r,j-c)
cc = real(ifft2(fft2(pA) .* conj(fft2(pB))));

% Find the peak
[peakVal, idx] = max(cc(:));
[rPeak, cPeak] = ind2sub(size(cc), idx);

[ccH, ccW] = size(cc);

% Convert from 1-based FFT lag to signed shift
% Lags > half the dimension are negative (wrap-around)
if rPeak > ccH/2
    rShift = rPeak - ccH - 1;
else
    rShift = rPeak - 1;
end

if cPeak > ccW/2
    cShift = cPeak - ccW - 1;
else
    cShift = cPeak - 1;
end

% The shift gives the position of strip B's content relative to strip A.
% Map back to whole-image coordinates.
if strcmp(layout, 'horizontal')
    % imgB starts at column (wA - stripW + 1) offset by cShift
    dx = (wA - stripW) + cShift;
    dy = rShift;
else
    dx = cShift;
    dy = (hA - stripH) + rShift;
end

end

% ════════════════════════════════════════════════════════════════════════
%  Local: zero-pad a 2-D array to (targetH x targetW)
% ════════════════════════════════════════════════════════════════════════
function out = padarray2d(arr, targetH, targetW)
%PADARRAY2D  Right/bottom zero-pad arr to targetH x targetW.

[h, w] = size(arr);
out = zeros(targetH, targetW);
out(1:h, 1:w) = arr;
end

% ════════════════════════════════════════════════════════════════════════
%  Local: build per-image alpha weight matrix for seam blending
% ════════════════════════════════════════════════════════════════════════
function alpha = buildAlpha(h, w, layout, blendWidth, k, nImages)
%BUILDALPHA  Linear ramp alpha [0,1] at leading and trailing seams.
%
%   For the first image: only the trailing edge ramps down.
%   For the last image:  only the leading edge ramps up.
%   For middle images:   both edges have a ramp.

alpha = ones(h, w);

bw = round(blendWidth);
bw = max(bw, 1);

if strcmp(layout, 'horizontal')
    if k > 1           % leading (left) edge fades in
        bwLeft = min(bw, w);
        alpha(:, 1:bwLeft) = alpha(:, 1:bwLeft) .* ...
            repmat(linspace(0,1,bwLeft), h, 1);
    end
    if k < nImages     % trailing (right) edge fades out
        bwRight = min(bw, w);
        alpha(:, (w - bwRight + 1):w) = alpha(:, (w - bwRight + 1):w) .* ...
            repmat(linspace(1,0,bwRight), h, 1);
    end

else   % vertical
    if k > 1           % leading (top) edge fades in
        bwTop = min(bw, h);
        alpha(1:bwTop, :) = alpha(1:bwTop, :) .* ...
            repmat(linspace(0,1,bwTop)', 1, w);
    end
    if k < nImages     % trailing (bottom) edge fades out
        bwBot = min(bw, h);
        alpha((h - bwBot + 1):h, :) = alpha((h - bwBot + 1):h, :) .* ...
            repmat(linspace(1,0,bwBot)', 1, w);
    end
end

end
