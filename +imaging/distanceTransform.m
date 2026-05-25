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
%   Implemented as a pure two-pass chamfer transform (NO Image Processing
%   Toolbox — `bwdist` is IPT, not base MATLAB). Metrics:
%
%       chamfer34 → orthogonal step 3, diagonal step 4 (≈ 3× Euclidean;
%                   divide by 3 for approximate Euclidean pixel distance)
%       cityblock → orthogonal step 1, no diagonal moves (exact L1)
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
%  Two-pass chamfer distance transform (NO Image Processing Toolbox).
%  Distance from each foreground pixel to the nearest background pixel.
%  Background = 0, foreground = Inf; a forward (raster) pass then a backward
%  pass propagate the minimum accumulated step cost. chamfer34 uses
%  orthogonal=3 / diagonal=4 (the classic integer approximation to 3×
%  Euclidean); cityblock uses orthogonal=1 with no diagonal moves (exact L1).
%
%  This replaces a former bwdist() call — bwdist is Image Processing
%  Toolbox, NOT base MATLAB, so it was undefined on toolbox-free installs
%  (CI, .mltbx users). The pure pass also gives identical results in every
%  environment (no IPT-vs-not numeric divergence).
% ════════════════════════════════════════════════════════════════════════
switch options.Metric
    case "chamfer34"
        dOrt = 3; dDiag = 4;
    case "cityblock"
        dOrt = 1; dDiag = Inf;   % Inf => diagonal moves never chosen
end

[H, W] = size(mask);
D = inf(H, W);
D(~mask) = 0;

% Forward pass: causal neighbors (up, left, and upper diagonals).
for r = 1:H
    for c = 1:W
        v = D(r, c);
        if r > 1,            v = min(v, D(r-1, c)   + dOrt);  end
        if c > 1,            v = min(v, D(r, c-1)   + dOrt);  end
        if isfinite(dDiag)
            if r > 1 && c > 1, v = min(v, D(r-1, c-1) + dDiag); end
            if r > 1 && c < W, v = min(v, D(r-1, c+1) + dDiag); end
        end
        D(r, c) = v;
    end
end

% Backward pass: anti-causal neighbors (down, right, and lower diagonals).
for r = H:-1:1
    for c = W:-1:1
        v = D(r, c);
        if r < H,            v = min(v, D(r+1, c)   + dOrt);  end
        if c < W,            v = min(v, D(r, c+1)   + dOrt);  end
        if isfinite(dDiag)
            if r < H && c < W, v = min(v, D(r+1, c+1) + dDiag); end
            if r < H && c > 1, v = min(v, D(r+1, c-1) + dDiag); end
        end
        D(r, c) = v;
    end
end

D = double(D);
D(~mask) = 0;   % background distance is 0

end
