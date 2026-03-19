function result = planeLevel(img, opts)
%PLANELEVEL  Subtract a best-fit polynomial surface from a 2-D image.
%
%   Syntax:
%       result = imaging.planeLevel(img)
%       result = imaging.planeLevel(img, Order=2)
%       result = imaging.planeLevel(img, Order=1, Mask=roiMask)
%
%   Fits a 2-D polynomial surface of the requested order to the image (or
%   to a masked sub-region) and subtracts it.  Useful for removing tilt,
%   bow, and low-order background from AFM/SPM height maps and similar data.
%
%   Inputs:
%       img   — [H x W] numeric matrix (grayscale image or height map)
%
%   Optional Name-Value:
%       Order — polynomial order: 1 (plane), 2 (quadratic), 3 (cubic).
%               Default: 1.
%       Mask  — [H x W] logical matrix; when supplied only pixels where
%               Mask==true are used for the least-squares fit. The full
%               grid is still evaluated and subtracted.  Default: all true.
%
%   Output:
%       result — struct with fields:
%           .leveled — [H x W] double; img - fittedSurface
%           .surface — [H x W] double; the polynomial surface evaluated on
%                      the full pixel grid
%           .coeffs  — column vector of polynomial coefficients (length
%                      depends on Order: 3, 6, or 10 terms)
%           .order   — polynomial order used (echoed back)
%
%   Examples:
%       % Remove tilt from an AFM scan
%       r = imaging.planeLevel(heightMap);
%       imagesc(r.leveled); colormap gray; colorbar;
%
%       % Quadratic background removal with an ROI mask
%       mask = false(size(heightMap));
%       mask(50:200, 50:200) = true;   % fit only to this region
%       r = imaging.planeLevel(heightMap, Order=2, Mask=mask);
%
%   See also imaging.surfaceRoughness, imaging.adjustContrast

% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    img             (:,:) {mustBeNumeric}
    opts.Order      (1,1) {mustBeMember(opts.Order, [1 2 3])} = 1
    opts.Mask       (:,:) logical = true(0,0)   % empty sentinel → use all
end

% ════════════════════════════════════════════════════════════════════════
%  Setup
% ════════════════════════════════════════════════════════════════════════
img = double(img);
[rows, cols] = size(img);

[X, Y] = meshgrid(1:cols, 1:rows);   % X = column index, Y = row index

% Determine active mask
if isempty(opts.Mask)
    mask = true(rows, cols);
else
    if ~isequal(size(opts.Mask), [rows, cols])
        error('imaging:planeLevel:maskSizeMismatch', ...
            'Mask must be the same size as img ([%d x %d]).', rows, cols);
    end
    mask = opts.Mask;
end

if ~any(mask(:))
    error('imaging:planeLevel:emptyMask', ...
        'Mask contains no true pixels; cannot fit a surface.');
end

% ════════════════════════════════════════════════════════════════════════
%  Flatten to column vectors (fitting pixels only)
% ════════════════════════════════════════════════════════════════════════
xFlat = X(mask);   % column coords of fitting pixels
yFlat = Y(mask);   % row    coords of fitting pixels
zFlat = img(mask); % height values at fitting pixels

% ════════════════════════════════════════════════════════════════════════
%  Design matrix
% ════════════════════════════════════════════════════════════════════════
switch opts.Order
    case 1
        % 3 terms: 1, x, y
        A = [ones(numel(xFlat),1), xFlat, yFlat];
    case 2
        % 6 terms: 1, x, y, x^2, x*y, y^2
        A = [ones(numel(xFlat),1), xFlat, yFlat, ...
             xFlat.^2, xFlat.*yFlat, yFlat.^2];
    case 3
        % 10 terms: 1, x, y, x^2, x*y, y^2, x^3, x^2*y, x*y^2, y^3
        A = [ones(numel(xFlat),1), xFlat, yFlat, ...
             xFlat.^2, xFlat.*yFlat, yFlat.^2, ...
             xFlat.^3, xFlat.^2.*yFlat, xFlat.*yFlat.^2, yFlat.^3];
end

% ════════════════════════════════════════════════════════════════════════
%  Least-squares solve
% ════════════════════════════════════════════════════════════════════════
coeffs = A \ zFlat(:);

% ════════════════════════════════════════════════════════════════════════
%  Evaluate surface on full grid
% ════════════════════════════════════════════════════════════════════════
xAll = X(:);
yAll = Y(:);

switch opts.Order
    case 1
        Afull = [ones(numel(xAll),1), xAll, yAll];
    case 2
        Afull = [ones(numel(xAll),1), xAll, yAll, ...
                 xAll.^2, xAll.*yAll, yAll.^2];
    case 3
        Afull = [ones(numel(xAll),1), xAll, yAll, ...
                 xAll.^2, xAll.*yAll, yAll.^2, ...
                 xAll.^3, xAll.^2.*yAll, xAll.*yAll.^2, yAll.^3];
end

surface = reshape(Afull * coeffs, rows, cols);

% ════════════════════════════════════════════════════════════════════════
%  Subtract and assemble output
% ════════════════════════════════════════════════════════════════════════
result.leveled = img - surface;
result.surface = surface;
result.coeffs  = coeffs;
result.order   = opts.Order;

end
