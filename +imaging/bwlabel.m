function [L, numComponents] = bwlabel(bw, conn)
%BWLABEL  Connected-component labeling without Image Processing Toolbox.
%
%   L = imaging.bwlabel(bw)              % 8-connected (default)
%   L = imaging.bwlabel(bw, 4)           % 4-connected
%   [L, n] = imaging.bwlabel(bw, conn)   % n = number of components
%
%   Pure-MATLAB union-find labeler (no Image Processing Toolbox). Returns a
%   label matrix L (0 = background, 1..n = components in raster order of
%   first appearance) and the component count. conn is 4 or 8.
%
%   Single raster pass collecting already-labeled causal neighbors (up &
%   left for 4-conn; plus the two upper diagonals for 8-conn), unioning
%   their labels; then a root-resolve + consecutive remap pass.

    arguments
        bw          logical
        conn  (1,1) double {mustBeMember(conn, [4, 8])} = 8
    end

    [H, W] = size(bw);
    L = zeros(H, W);
    nextLabel = 1;
    parent = (1:H*W);

    for r = 1:H
        for c = 1:W
            if ~bw(r, c), continue; end
            neighbors = [];
            if r > 1 && bw(r-1, c)
                neighbors(end+1) = L(r-1, c); %#ok<AGROW>
            end
            if c > 1 && bw(r, c-1)
                neighbors(end+1) = L(r, c-1); %#ok<AGROW>
            end
            if conn == 8 && r > 1
                if c > 1 && bw(r-1, c-1)
                    neighbors(end+1) = L(r-1, c-1); %#ok<AGROW>
                end
                if c < W && bw(r-1, c+1)
                    neighbors(end+1) = L(r-1, c+1); %#ok<AGROW>
                end
            end
            if isempty(neighbors)
                L(r, c) = nextLabel;
                nextLabel = nextLabel + 1;
            else
                minL = min(neighbors);
                L(r, c) = minL;
                for ni = 1:numel(neighbors)
                    rootA = minL;
                    while parent(rootA) ~= rootA, rootA = parent(rootA); end
                    rootB = neighbors(ni);
                    while parent(rootB) ~= rootB, rootB = parent(rootB); end
                    if rootA ~= rootB, parent(rootB) = rootA; end
                end
            end
        end
    end

    % Path-compress every label to its root.
    for k = 1:nextLabel-1
        root = k;
        while parent(root) ~= root, root = parent(root); end
        j = k;
        while parent(j) ~= root
            next = parent(j); parent(j) = root; j = next;
        end
    end

    % Remap roots to consecutive labels 1..n.
    remap = zeros(1, nextLabel-1);
    newLabel = 0;
    for k = 1:nextLabel-1
        root = k;
        while parent(root) ~= root, root = parent(root); end
        if remap(root) == 0
            newLabel = newLabel + 1;
            remap(root) = newLabel;
        end
        remap(k) = remap(root);
    end

    for r = 1:H
        for c = 1:W
            if L(r, c) > 0
                L(r, c) = remap(L(r, c));
            end
        end
    end

    numComponents = newLabel;
end
