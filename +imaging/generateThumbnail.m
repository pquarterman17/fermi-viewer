function thumb = generateThumbnail(img, options)
%GENERATETHUMBNAIL  Downsample an image to a maximum dimension (no imresize).
%
%   Syntax:
%       thumb = imaging.generateThumbnail(img)
%       thumb = imaging.generateThumbnail(img, MaxSize=128)
%
%   Downsamples img so its largest dimension is at most MaxSize pixels,
%   preserving the aspect ratio.  Uses bilinear interpolation via interp2
%   — no Image Processing Toolbox required.
%
%   If the image is already smaller than MaxSize in both dimensions it is
%   returned unchanged.
%
%   Inputs:
%       img     — [H x W] numeric matrix (any integer or float type)
%
%   Optional Name-Value:
%       MaxSize — maximum output dimension in pixels (default: 256)
%
%   Output:
%       thumb — downsampled array cast back to the same class as img
%
%   Examples:
%       t = imaging.generateThumbnail(bigImg);            % ≤256 px
%       t = imaging.generateThumbnail(bigImg, MaxSize=64);% ≤64 px
%
%   See also imaging.adjustContrast, imaging.applyGaussian

% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    img             (:,:) {mustBeNumeric}
    options.MaxSize (1,1) double {mustBePositive, mustBeInteger} = 256
end

% ════════════════════════════════════════════════════════════════════════
%  Compute output dimensions
% ════════════════════════════════════════════════════════════════════════
[H, W]   = size(img);
maxDim   = max(H, W);

if maxDim <= options.MaxSize
    % Already within bounds — return unchanged
    thumb = img;
    return
end

scale = options.MaxSize / maxDim;
newH  = max(1, round(H * scale));
newW  = max(1, round(W * scale));

% ════════════════════════════════════════════════════════════════════════
%  Bilinear downsample via interp2
%  Sample grid: linspace(1, H, newH) gives evenly spaced row centres;
%  interp2 uses (Xq, Yq) = (column, row), so swap to (cols, rows).
% ════════════════════════════════════════════════════════════════════════
rowQ = linspace(1, H, newH)';       % [newH x 1] row query points
colQ = linspace(1, W, newW);        % [1 x newW] column query points

% Expand to grids for interp2 (Xq = column, Yq = row)
[colGrid, rowGrid] = meshgrid(colQ, rowQ);

d     = double(img);
dThumb = interp2(d, colGrid, rowGrid, 'linear');

% ════════════════════════════════════════════════════════════════════════
%  Cast back to original type
% ════════════════════════════════════════════════════════════════════════
thumb = cast(dThumb, class(img));

end
