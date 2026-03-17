function outImg = morphOp(img, operation, options)
%MORPHOP  Morphological erosion, dilation, opening, or closing on binary images.
%
%   Syntax:
%       outImg = imaging.morphOp(img, 'erode')
%       outImg = imaging.morphOp(img, 'dilate', Radius=2)
%       outImg = imaging.morphOp(img, 'open',   Radius=2, Shape='disk')
%       outImg = imaging.morphOp(img, 'close',  Radius=3, Shape='square')
%
%   Performs morphological operations on a binary image using a flat
%   structuring element (SE) built from MATLAB built-ins only — no Image
%   Processing Toolbox required.
%
%   Implementation:
%       Erode  — conv2(bw, SE, 'same') == sum(SE(:))  [all neighbours are 1]
%       Dilate — conv2(bw, SE, 'same') >  0           [any neighbour is 1]
%       Open   — erode then dilate (removes small bright objects)
%       Close  — dilate then erode (fills small dark holes)
%
%   Inputs:
%       img       — [H x W] logical or numeric matrix; converted to logical
%                   via img > 0 before processing
%       operation — char: 'erode' | 'dilate' | 'open' | 'close'
%
%   Optional Name-Value:
%       Radius — (1,1) double; structuring element radius in pixels
%                (default: 1 → 3x3 SE for 'square', 1-px disk for 'disk')
%       Shape  — 'square' or 'disk' (default: 'square')
%                'square' — full (2R+1) x (2R+1) block of ones
%                'disk'   — circular mask; pixels with distance <= R from
%                           centre are set to 1
%
%   Output:
%       outImg — [H x W] logical matrix
%
%   Examples:
%       bw      = img > 128;
%       eroded  = imaging.morphOp(bw, 'erode',  Radius=1);
%       dilated = imaging.morphOp(bw, 'dilate', Radius=2, Shape='disk');
%       opened  = imaging.morphOp(bw, 'open',   Radius=2);
%       closed  = imaging.morphOp(bw, 'close',  Radius=3, Shape='disk');
%
%   See also imaging.applyGaussian, imaging.applyMedian

% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    img           (:,:) {mustBeNumeric}
    operation     (1,:) char {mustBeMember(operation, ...
                      {'erode','dilate','open','close'})}
    options.Radius (1,1) double {mustBePositive} = 1
    options.Shape  (1,1) string {mustBeMember(options.Shape, ...
                      ["square","disk"])} = "square"
end

% ════════════════════════════════════════════════════════════════════════
%  Convert input to logical
% ════════════════════════════════════════════════════════════════════════
bw = img > 0;

% ════════════════════════════════════════════════════════════════════════
%  Build structuring element
% ════════════════════════════════════════════════════════════════════════
R    = options.Radius;
side = 2 * R + 1;

if options.Shape == "square"
    SE = ones(side, side);
else  % disk
    ax = (-R : R);
    [X, Y] = meshgrid(ax, ax);
    SE = double(sqrt(X.^2 + Y.^2) <= R);
end

seSum = sum(SE(:));

% ════════════════════════════════════════════════════════════════════════
%  Apply operation
% ════════════════════════════════════════════════════════════════════════
switch operation
    case 'erode'
        outImg = erode(bw, SE, seSum);
    case 'dilate'
        outImg = dilate(bw, SE);
    case 'open'
        outImg = dilate(erode(bw, SE, seSum), SE);
    case 'close'
        outImg = erode(dilate(bw, SE), SE, seSum);
end

end

% ════════════════════════════════════════════════════════════════════════
%  Local helpers
% ════════════════════════════════════════════════════════════════════════
function out = erode(bw, SE, seSum)
%ERODE  A pixel survives iff every SE neighbour is 1.
out = conv2(double(bw), SE, 'same') == seSum;
end

function out = dilate(bw, SE)
%DILATE  A pixel is set iff at least one SE neighbour is 1.
out = conv2(double(bw), SE, 'same') > 0;
end
