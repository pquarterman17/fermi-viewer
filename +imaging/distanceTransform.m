function D = distanceTransform(bw, options)
%DISTANCETRANSFORM  Distance transform of a binary mask.
%
%   Syntax:
%       D = imaging.distanceTransform(bw)
%       D = imaging.distanceTransform(bw, Metric="chamfer34")
%       D = imaging.distanceTransform(bw, Metric="cityblock")
%
%   Computes, for every foreground pixel in `bw`, the approximate
%   Euclidean distance to the nearest background pixel. Background pixels
%   have distance 0.
%
%   Implementation delegates to the base-MATLAB `bwdist` built-in
%   (available since R2006a, no Image Processing Toolbox required for
%   the Euclidean metric). The "chamfer34" and "cityblock" metrics are
%   approximated using the closest available bwdist distance method:
%
%       chamfer34 → 'euclidean' result scaled ×3  (same 3-unit step cost)
%       cityblock  → 'cityblock'
%
%   Note: previous versions returned chamfer integer values (multiples of
%   3/4). The new output scales the Euclidean result by 3 to preserve the
%   expected magnitude range for chamfer34. Divide by 3 to obtain true
%   Euclidean pixel distances.
%
%   Inputs:
%       bw          — [H x W] logical or numeric (~= 0 = foreground)
%
%   Optional Name-Value:
%       Metric      — "chamfer34" (default) or "cityblock".
%                     chamfer34: result is Euclidean distance × 3 (~Euclidean/3 when divided by 3).
%                     cityblock: pure L1 distance.
%
%   Output:
%       D — [H x W] double, distance transform. Background pixels are 0.
%
%   Examples:
%       D = imaging.distanceTransform(bw);
%       Deuclid = D / 3;                   % for chamfer34 → Euclidean px
%
%       D1 = imaging.distanceTransform(bw, Metric="cityblock");
%
%   See also imaging.watershed, imaging.connectedComponents, imaging.morphOp

% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    bw                      (:,:) {mustBeNumericOrLogical}
    options.Metric          (1,1) string {mustBeMember(options.Metric, ["chamfer34","cityblock"])} = "chamfer34"
end

mask = logical(bw);

if ~any(mask(:))
    D = zeros(size(mask));
    return;
end

% ════════════════════════════════════════════════════════════════════════
%  Delegate to bwdist (base MATLAB, R2006a+)
%  bwdist computes distance from each FG pixel to nearest BG pixel.
%  We pass the foreground mask directly — bwdist treats non-zero pixels
%  as the "objects" and returns distance for zero (background) pixels,
%  so we invert: pass the background mask to get distance from FG pixels.
% ════════════════════════════════════════════════════════════════════════
switch options.Metric
    case "chamfer34"
        % bwdist 'euclidean' gives true Euclidean distance.
        % Scale by 3 to match the chamfer34 convention (orthogonal cost = 3).
        D = bwdist(~mask, 'euclidean') * 3;
    case "cityblock"
        D = bwdist(~mask, 'cityblock');
end

D = double(D);

% Background pixels should be 0 (bwdist already does this — belt-and-braces).
D(~mask) = 0;

end
