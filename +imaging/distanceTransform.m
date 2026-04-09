function D = distanceTransform(bw, options)
%DISTANCETRANSFORM  Chamfer distance transform of a binary mask (no toolbox).
%
%   Syntax:
%       D = imaging.distanceTransform(bw)
%       D = imaging.distanceTransform(bw, Metric="chamfer34")
%       D = imaging.distanceTransform(bw, Metric="cityblock")
%
%   Computes, for every foreground pixel in `bw`, the approximate
%   Euclidean distance to the nearest background pixel. Uses the
%   classic two-pass chamfer algorithm (forward + backward scan).
%   Background pixels have distance 0.
%
%   The "chamfer34" metric uses local step costs of 3 (orthogonal
%   neighbours) and 4 (diagonal neighbours), giving ~2% max error
%   relative to true Euclidean distance when divided by 3. The
%   returned values are in the same chamfer units — divide by 3 if
%   you need Euclidean-pixel distances.
%
%   Inputs:
%       bw          — [H x W] logical or numeric (~= 0 = foreground)
%
%   Optional Name-Value:
%       Metric      — "chamfer34" (default) or "cityblock".
%                     chamfer34: orthogonal=3, diagonal=4, ~Euclidean/3.
%                     cityblock: orthogonal=1, no diagonals (pure L1).
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
[H, W] = size(mask);

% Initialize: background = 0, foreground = +Inf
BIG = Inf;
D = zeros(H, W);
D(mask)  = BIG;

if ~any(mask(:))
    return;
end

switch options.Metric
    case "chamfer34"
        c1 = 3;   % orthogonal step
        c2 = 4;   % diagonal step
        useDiag = true;
    case "cityblock"
        c1 = 1;
        c2 = Inf;
        useDiag = false;
end

% ════════════════════════════════════════════════════════════════════════
%  Forward pass: row-major, look at N, NW, NE, W
% ════════════════════════════════════════════════════════════════════════
for r = 1:H
    for c = 1:W
        if D(r, c) == 0, continue; end

        best = D(r, c);
        % W
        if c > 1
            v = D(r, c-1) + c1;
            if v < best, best = v; end
        end
        % N
        if r > 1
            v = D(r-1, c) + c1;
            if v < best, best = v; end
        end
        if useDiag
            % NW
            if r > 1 && c > 1
                v = D(r-1, c-1) + c2;
                if v < best, best = v; end
            end
            % NE
            if r > 1 && c < W
                v = D(r-1, c+1) + c2;
                if v < best, best = v; end
            end
        end
        D(r, c) = best;
    end
end

% ════════════════════════════════════════════════════════════════════════
%  Backward pass: reverse raster, look at S, SE, SW, E
% ════════════════════════════════════════════════════════════════════════
for r = H:-1:1
    for c = W:-1:1
        if D(r, c) == 0, continue; end

        best = D(r, c);
        % E
        if c < W
            v = D(r, c+1) + c1;
            if v < best, best = v; end
        end
        % S
        if r < H
            v = D(r+1, c) + c1;
            if v < best, best = v; end
        end
        if useDiag
            % SE
            if r < H && c < W
                v = D(r+1, c+1) + c2;
                if v < best, best = v; end
            end
            % SW
            if r < H && c > 1
                v = D(r+1, c-1) + c2;
                if v < best, best = v; end
            end
        end
        D(r, c) = best;
    end
end

% Replace any remaining +Inf (disconnected foreground) with max finite value
D(~isfinite(D)) = 0;
end
