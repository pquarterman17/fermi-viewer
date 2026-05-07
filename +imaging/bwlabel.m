function L = bwlabel(bw)
%BWLABEL  Connected-component labeling (4-connected) without Image Processing Toolbox.
    arguments
        bw  logical
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

    for k = 1:nextLabel-1
        root = k;
        while parent(root) ~= root, root = parent(root); end
        j = k;
        while parent(j) ~= root
            next = parent(j); parent(j) = root; j = next;
        end
    end

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
end
