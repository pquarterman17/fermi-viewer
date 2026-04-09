function [L, numComponents] = connectedComponents(bw, options)
%CONNECTEDCOMPONENTS  Label connected regions in a binary mask (no toolbox).
%
%   Syntax:
%       [L, n] = imaging.connectedComponents(bw)
%       [L, n] = imaging.connectedComponents(bw, Connectivity=4)
%       [L, n] = imaging.connectedComponents(bw, Connectivity=8)
%
%   Implements two-pass labeling with union-find:
%     Pass 1 — raster-scan the mask assigning provisional labels from
%              already-seen neighbours; record equivalences in a DSU.
%     Pass 2 — replace every provisional label with the representative
%              of its DSU class and compact the label set to 1..numComponents.
%
%   Drop-in replacement for bwlabel from the Image Processing Toolbox
%   (which this codebase cannot use). The output label image uses 0 for
%   background and 1..n for foreground components.
%
%   Inputs:
%       bw                  — [H x W] logical (or numeric, interpreted
%                             as logical via `~= 0`)
%
%   Optional Name-Value:
%       Connectivity        — 4 (N/S/E/W) or 8 (plus diagonals).
%                             Default: 8.
%
%   Outputs:
%       L             — [H x W] double label image, 0 = background.
%       numComponents — number of connected foreground components.
%
%   Examples:
%       bw = gray < 50;
%       [L, n] = imaging.connectedComponents(bw);
%       fprintf('%d particles found\n', n);
%
%   See also imaging.particleAnalysis, imaging.multiOtsu, imaging.morphOp

% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    bw                         (:,:) {mustBeNumericOrLogical}
    options.Connectivity       (1,1) double {mustBeMember(options.Connectivity, [4, 8])} = 8
end

mask = logical(bw);
[H, W] = size(mask);
L = zeros(H, W);
if ~any(mask(:))
    numComponents = 0;
    return;
end

% Union-find over provisional labels.
% parent(k) is the parent of class k; self-parent = root.
maxLabels = ceil(H * W / 2) + 1;
parent = zeros(1, maxLabels);

next = 0;   % next provisional label to assign

% ════════════════════════════════════════════════════════════════════════
%  Pass 1: raster scan
% ════════════════════════════════════════════════════════════════════════
for r = 1:H
    for c = 1:W
        if ~mask(r, c)
            continue;
        end

        % Collect labels of already-scanned neighbours.
        nbrs = zeros(1, 4);
        k = 0;

        % West (r, c-1)
        if c > 1 && L(r, c-1) > 0
            k = k + 1; nbrs(k) = L(r, c-1);
        end
        % North (r-1, c)
        if r > 1 && L(r-1, c) > 0
            k = k + 1; nbrs(k) = L(r-1, c);
        end

        if options.Connectivity == 8
            % NW (r-1, c-1)
            if r > 1 && c > 1 && L(r-1, c-1) > 0
                k = k + 1; nbrs(k) = L(r-1, c-1);
            end
            % NE (r-1, c+1)
            if r > 1 && c < W && L(r-1, c+1) > 0
                k = k + 1; nbrs(k) = L(r-1, c+1);
            end
        end

        if k == 0
            % No labeled neighbour — new component
            next = next + 1;
            parent(next) = next;
            L(r, c) = next;
        else
            % Assign the smallest neighbour label, union the rest.
            base = nbrs(1);
            for ii = 2:k
                base = min(base, nbrs(ii));
            end
            L(r, c) = base;
            for ii = 1:k
                parent = ufUnion(parent, nbrs(ii), base);
            end
        end
    end
end

% ════════════════════════════════════════════════════════════════════════
%  Pass 2: flatten via union-find + compact labels to 1..n
% ════════════════════════════════════════════════════════════════════════
relabel = zeros(1, next);
numComponents = 0;
for r = 1:H
    for c = 1:W
        lbl = L(r, c);
        if lbl == 0, continue; end
        root = ufFind(parent, lbl);
        if relabel(root) == 0
            numComponents = numComponents + 1;
            relabel(root) = numComponents;
        end
        L(r, c) = relabel(root);
    end
end

end   % main function


% ════════════════════════════════════════════════════════════════════════
%  Union-find helpers
% ════════════════════════════════════════════════════════════════════════
function root = ufFind(parent, x)
    root = x;
    while parent(root) ~= root
        root = parent(root);
    end
end

function parent = ufUnion(parent, a, b)
    ra = ufFind(parent, a);
    rb = ufFind(parent, b);
    if ra == rb, return; end
    % Union by lower root index (deterministic)
    if ra < rb
        parent(rb) = ra;
    else
        parent(ra) = rb;
    end
end
