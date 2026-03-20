function spots = findDiffractionSpots(img, opts)
%FINDDIFFRACTIONSPOTS  Detect bright spots in a diffraction pattern or FFT image.
%
%   Syntax:
%       spots = imaging.findDiffractionSpots(img)
%       spots = imaging.findDiffractionSpots(img, MinRadius=15, Threshold=0.08)
%
%   Uses Gaussian pre-smoothing followed by local-maximum detection with
%   intensity thresholding, center-exclusion, and non-maximum suppression
%   to return the N strongest isolated spots in the image.
%
%   No Image Processing Toolbox required.
%
%   Inputs:
%       img — [H x W] numeric matrix (diffraction pattern or FFT magnitude)
%
%   Optional Name-Value:
%       MinRadius     — minimum distance from image center to accept a spot,
%                       in pixels; used to reject the direct beam / DC peak
%                       (default: 10)
%       Threshold     — intensity threshold as fraction of the global maximum;
%                       pixels below Threshold*max(img(:)) are ignored
%                       (default: 0.05)
%       MinSeparation — minimum pixel distance between two accepted spots;
%                       enforces non-maximum suppression (default: 8)
%       MaxSpots      — maximum number of spots to return (default: 50)
%       Sigma         — standard deviation of the Gaussian pre-smooth kernel
%                       in pixels (default: 1.5)
%
%   Output:
%       spots — [N x 2] double matrix of [row, col] pixel positions,
%               sorted by smoothed intensity descending.
%               Returns an empty [0 x 2] matrix when no spots are found.
%
%   Examples:
%       % Detect spots in an FFT magnitude image
%       [mag, ~] = imaging.computeFFT(img);
%       spots = imaging.findDiffractionSpots(mag, MinRadius=20, MaxSpots=30);
%
%       % Overlay detected spots on the FFT
%       imagesc(mag); colormap gray; axis image; hold on;
%       plot(spots(:,2), spots(:,1), 'r+', 'MarkerSize', 12, 'LineWidth', 1.5);
%
%   See also imaging.computeFFT, imaging.latticeMeasure, imaging.indexDiffraction

% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    img                         (:,:) {mustBeNumeric}
    opts.MinRadius     (1,1) double {mustBeNonnegative} = 10
    opts.Threshold     (1,1) double {mustBeInRange(opts.Threshold, 0, 1)} = 0.05
    opts.MinSeparation (1,1) double {mustBePositive}    = 8
    opts.MaxSpots      (1,1) double {mustBePositive, mustBeInteger} = 50
    opts.Sigma         (1,1) double {mustBePositive}    = 1.5
end

% ════════════════════════════════════════════════════════════════════════
%  Gaussian pre-smooth  (manual kernel, same approach as applyGaussian.m)
% ════════════════════════════════════════════════════════════════════════
hw = ceil(3 * opts.Sigma);
ax = (-hw : hw);
[X, Y] = meshgrid(ax, ax);
kernel  = exp(-0.5 * (X.^2 + Y.^2) / opts.Sigma^2);
kernel  = kernel / sum(kernel(:));

smoothed = conv2(double(img), kernel, 'same');

% ════════════════════════════════════════════════════════════════════════
%  Local maximum detection (8-connected neighbourhood)
% ════════════════════════════════════════════════════════════════════════
[nRows, nCols] = size(smoothed);

% Pad by 1 on each side so that border pixels can be compared without
% index-out-of-range issues.
% Manual padding (no toolbox required)
pad = -Inf(nRows + 2, nCols + 2);
pad(2:end-1, 2:end-1) = smoothed;

% A pixel is a local max if it is >= all 8 neighbours in the padded image.
% Slice out each of the 8 neighbours by shifting the padded array.
center = pad(2:end-1, 2:end-1);
isMax  = true(nRows, nCols);
for dr = -1:1
    for dc = -1:1
        if dr == 0 && dc == 0, continue; end
        neighbour = pad((2+dr):(end-1+dr), (2+dc):(end-1+dc));
        isMax     = isMax & (center >= neighbour);
    end
end

% ════════════════════════════════════════════════════════════════════════
%  Intensity threshold
% ════════════════════════════════════════════════════════════════════════
globalMax = max(smoothed(:));
if globalMax <= 0
    spots = zeros(0, 2);
    return;
end

isMax = isMax & (smoothed >= opts.Threshold * globalMax);

% ════════════════════════════════════════════════════════════════════════
%  Center-distance filter  (reject direct beam / DC peak)
% ════════════════════════════════════════════════════════════════════════
centerRow = floor(nRows / 2) + 1;
centerCol = floor(nCols / 2) + 1;

[rowIdx, colIdx] = find(isMax);
if isempty(rowIdx)
    spots = zeros(0, 2);
    return;
end

dr = rowIdx - centerRow;
dc = colIdx - centerCol;
R  = sqrt(dr.^2 + dc.^2);

keep  = R >= opts.MinRadius;
rowIdx = rowIdx(keep);
colIdx = colIdx(keep);
R      = R(keep);

if isempty(rowIdx)
    spots = zeros(0, 2);
    return;
end

% ════════════════════════════════════════════════════════════════════════
%  Sort by smoothed intensity descending (for greedy NMS below)
% ════════════════════════════════════════════════════════════════════════
intensities = smoothed(sub2ind([nRows, nCols], rowIdx, colIdx));
[~, sortOrd] = sort(intensities, 'descend');
rowIdx = rowIdx(sortOrd);
colIdx = colIdx(sortOrd);

% ════════════════════════════════════════════════════════════════════════
%  Non-maximum suppression
%
%  Greedy: accept the strongest remaining candidate, then discard all
%  others within MinSeparation pixels.
% ════════════════════════════════════════════════════════════════════════
nCandidates = numel(rowIdx);
accepted    = false(nCandidates, 1);
suppressed  = false(nCandidates, 1);

for i = 1:nCandidates
    if suppressed(i), continue; end
    accepted(i) = true;
    if sum(accepted) >= opts.MaxSpots, break; end
    % Suppress all later candidates within MinSeparation
    distSq = (rowIdx((i+1):end) - rowIdx(i)).^2 + ...
             (colIdx((i+1):end) - colIdx(i)).^2;
    tooClose = distSq < opts.MinSeparation^2;
    suppressed((i+1):end) = suppressed((i+1):end) | tooClose;
end

% ════════════════════════════════════════════════════════════════════════
%  Assemble output  [N x 2]  [row, col]
% ════════════════════════════════════════════════════════════════════════
spots = [rowIdx(accepted), colIdx(accepted)];

end
