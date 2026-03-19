function result = surfaceRoughness(img, opts)
%SURFACEROUGHNESS  Compute standard surface roughness parameters from a 2-D image.
%
%   Syntax:
%       result = imaging.surfaceRoughness(img)
%       result = imaging.surfaceRoughness(img, PixelSize=2.4, PixelUnit='nm')
%       result = imaging.surfaceRoughness(img, Level='quadratic', Mask=roiMask)
%
%   Computes ISO 25178-compatible surface texture parameters from a grayscale
%   image or AFM/SPM height map.  The image can optionally be pre-leveled
%   (background subtraction) before parameter extraction.
%
%   Inputs:
%       img        — [H x W] numeric matrix (grayscale image or height map)
%
%   Optional Name-Value:
%       PixelSize  — physical size of one pixel, used for area calculation
%                    (default: 1)
%       PixelUnit  — unit string label for PixelSize (default: 'px')
%       Level      — pre-level background: 'none', 'plane' (order 1), or
%                    'quadratic' (order 2).  Default: 'plane'.
%       Mask       — [H x W] logical; restrict computation to masked pixels.
%                    SAR is still computed over the full leveled image.
%
%   Output:
%       result — struct with fields:
%           .Ra           — arithmetic average roughness (mean of |z - zmean|)
%           .Rq           — root-mean-square roughness
%           .Rz           — total height (max peak to deepest valley)
%           .Rsk          — skewness of height distribution
%           .Rku          — kurtosis of height distribution
%           .Rp           — maximum peak height above mean
%           .Rv           — maximum valley depth below mean (positive value)
%           .SAR          — surface area ratio: true surface area / projected
%                           area (>=1; computed on full image, not Mask)
%           .bearingRatio — struct with:
%               .heights  — height values sorted descending (N x 1 double)
%               .fraction — cumulative material fraction in [0,1] (N x 1)
%           .pixelSize    — echo of PixelSize input
%           .pixelUnit    — echo of PixelUnit input
%           .levelMethod  — echo of Level input used
%           .nPixels      — number of pixels used for Ra/Rq/etc. computation
%
%   Examples:
%       % Basic roughness on a raw AFM image
%       r = imaging.surfaceRoughness(heightMap, PixelSize=0.5, PixelUnit='nm');
%       fprintf('Ra = %.4g nm,  Rq = %.4g nm\n', r.Ra, r.Rq);
%
%       % ROI-restricted roughness without background leveling
%       mask = false(size(heightMap));
%       mask(100:300, 100:300) = true;
%       r = imaging.surfaceRoughness(heightMap, Level='none', Mask=mask);
%
%       % Bearing ratio curve
%       plot(r.bearingRatio.fraction, r.bearingRatio.heights);
%       xlabel('Material fraction'); ylabel('Height');
%
%   See also imaging.planeLevel, imaging.lineProfile, imaging.adjustContrast

% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    img              (:,:) {mustBeNumeric}
    opts.PixelSize   (1,1) double = 1
    opts.PixelUnit   (1,1) string = 'px'
    opts.Level       (1,1) string {mustBeMember(opts.Level, ...
                         {'none','plane','quadratic'})} = 'plane'
    opts.Mask        (:,:) logical = true(0,0)   % empty sentinel → use all
end

% ════════════════════════════════════════════════════════════════════════
%  Background leveling
% ════════════════════════════════════════════════════════════════════════
img = double(img);
[rows, cols] = size(img);

% Determine mask (before leveling so it can be forwarded to planeLevel)
if isempty(opts.Mask)
    mask = true(rows, cols);
else
    if ~isequal(size(opts.Mask), [rows, cols])
        error('imaging:surfaceRoughness:maskSizeMismatch', ...
            'Mask must be the same size as img ([%d x %d]).', rows, cols);
    end
    mask = opts.Mask;
end

if ~any(mask(:))
    error('imaging:surfaceRoughness:emptyMask', ...
        'Mask contains no true pixels.');
end

switch opts.Level
    case 'plane'
        lr = imaging.planeLevel(img, Order=1, Mask=mask);
        img = lr.leveled;
    case 'quadratic'
        lr = imaging.planeLevel(img, Order=2, Mask=mask);
        img = lr.leveled;
    otherwise
        % 'none' — use as-is
end

% ════════════════════════════════════════════════════════════════════════
%  Extract pixels for scalar roughness parameters
% ════════════════════════════════════════════════════════════════════════
z = img(mask);          % column vector of height values in ROI
N = numel(z);

zmean = mean(z);
zc    = z - zmean;      % mean-centred heights

% ════════════════════════════════════════════════════════════════════════
%  Scalar roughness parameters
% ════════════════════════════════════════════════════════════════════════
Ra  = mean(abs(zc));
Rq  = sqrt(mean(zc .^ 2));
Rz  = max(z) - min(z);
Rp  = max(zc);
Rv  = abs(min(zc));

% Guard against a perfectly flat image (Rq == 0) for normalised moments
if Rq > 0
    Rsk = mean(zc .^ 3) / Rq ^ 3;
    Rku = mean(zc .^ 4) / Rq ^ 4;
else
    Rsk = 0;
    Rku = 0;
end

% ════════════════════════════════════════════════════════════════════════
%  Surface area ratio (full image, not masked)
% ════════════════════════════════════════════════════════════════════════
% Each pixel quad (i,j)-(i,j+1)-(i+1,j)-(i+1,j+1) is split into two
% triangles.  For each triangle the 3-D area is 0.5 * |A x B|, where A
% and B are edge vectors with x/y components equal to PixelSize and z
% components equal to the finite-difference height change.  The whole
% computation is vectorised over all (rows-1)*(cols-1) quads.
ps = opts.PixelSize;   % dx = dy = ps

% Corner height matrices (each (rows-1) x (cols-1))
z00 = img(1:end-1, 1:end-1);
z01 = img(1:end-1, 2:end  );
z10 = img(2:end,   1:end-1);
z11 = img(2:end,   2:end  );

% Triangle 1: origin at (i,j), edges A=[ps,0,dz1] and B=[0,ps,dz2]
% A x B = [-ps*dz2, -ps*dz1, ps^2]  (verified by expanding the determinant)
dz1 = z01 - z00;   % height change along +col direction
dz2 = z10 - z00;   % height change along +row direction
tri1Area = 0.5 * sqrt( (ps .* dz2).^2 + (ps .* dz1).^2 + ps^4 );

% Triangle 2: origin at (i+1,j+1), edges A=[0,-ps,dz3] and B=[-ps,0,dz4]
% A x B = [-ps*dz4, -ps*dz3, ps^2]  (same magnitude structure)
dz3 = z01 - z11;   % height change from (i+1,j+1) to (i,j+1)
dz4 = z10 - z11;   % height change from (i+1,j+1) to (i+1,j)
tri2Area = 0.5 * sqrt( (ps .* dz4).^2 + (ps .* dz3).^2 + ps^4 );

totalTriArea  = sum(tri1Area(:)) + sum(tri2Area(:));
projectedArea = (rows - 1) * (cols - 1) * ps^2;

if projectedArea > 0
    SAR = totalTriArea / projectedArea;
else
    SAR = 1;
end

% ════════════════════════════════════════════════════════════════════════
%  Bearing ratio
% ════════════════════════════════════════════════════════════════════════
% Sort heights descending; cumulative fraction represents material ratio
% at each height level (fraction of surface at or above that height).
sortedHeights = sort(z, 'descend');
fraction      = (1:N)' / N;

% ════════════════════════════════════════════════════════════════════════
%  Assemble output
% ════════════════════════════════════════════════════════════════════════
result.Ra    = Ra;
result.Rq    = Rq;
result.Rz    = Rz;
result.Rsk   = Rsk;
result.Rku   = Rku;
result.Rp    = Rp;
result.Rv    = Rv;
result.SAR   = SAR;

result.bearingRatio.heights  = sortedHeights;
result.bearingRatio.fraction = fraction;

result.pixelSize   = opts.PixelSize;
result.pixelUnit   = opts.PixelUnit;
result.levelMethod = opts.Level;
result.nPixels     = N;

end
