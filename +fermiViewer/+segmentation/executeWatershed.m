function result = executeWatershed(px, thresh, minArea)
%EXECUTEWATERSHED  Watershed segmentation with distance transform.
    arguments
        px          double
        thresh      double
        minArea     double
    end

    bw = px > thresh;

    dist = zeros(size(bw));
    current = bw;
    level = 0;
    while any(current(:))
        level = level + 1;
        dist(current) = level;
        eroded = current;
        eroded(1:end-1, :) = eroded(1:end-1, :) & current(2:end, :);
        eroded(2:end, :)   = eroded(2:end, :)   & current(1:end-1, :);
        eroded(:, 1:end-1) = eroded(:, 1:end-1) & current(:, 2:end);
        eroded(:, 2:end)   = eroded(:, 2:end)   & current(:, 1:end-1);
        current = eroded;
    end

    seeds = true(size(dist));
    padD = padarray(dist, [1 1], 0);
    for dr = -1:1
        for dc = -1:1
            if dr == 0 && dc == 0, continue; end
            seeds = seeds & (dist > padD((2:end-1)+dr, (2:end-1)+dc));
        end
    end
    seeds = seeds & (dist > 1);

    seedLabel = imaging.bwlabel(seeds);
    nSeeds = max(seedLabel(:));

    labelMap = zeros(size(bw));
    labelMap(seeds) = seedLabel(seeds);

    [sortDist, sortIdx] = sort(dist(:), 'descend');
    for si = 1:numel(sortIdx)
        if sortDist(si) == 0, break; end
        [sr, sc] = ind2sub(size(bw), sortIdx(si));
        if labelMap(sr, sc) > 0, continue; end
        neighbors = zeros(1, 4);
        nNbr = 0;
        if sr > 1 && labelMap(sr-1, sc) > 0, nNbr = nNbr+1; neighbors(nNbr) = labelMap(sr-1, sc); end
        if sr < size(bw,1) && labelMap(sr+1, sc) > 0, nNbr = nNbr+1; neighbors(nNbr) = labelMap(sr+1, sc); end
        if sc > 1 && labelMap(sr, sc-1) > 0, nNbr = nNbr+1; neighbors(nNbr) = labelMap(sr, sc-1); end
        if sc < size(bw,2) && labelMap(sr, sc+1) > 0, nNbr = nNbr+1; neighbors(nNbr) = labelMap(sr, sc+1); end
        if nNbr > 0
            un = unique(neighbors(1:nNbr));
            if isscalar(un)
                labelMap(sr, sc) = un;
            end
        end
    end

    areas = [];
    for li = 1:nSeeds
        a = sum(labelMap(:) == li);
        if a < minArea
            labelMap(labelMap == li) = 0;
        else
            areas(end+1) = a; %#ok<AGROW>
        end
    end

    wFig = figure('Name', 'Watershed Segmentation', 'NumberTitle', 'off', ...
        'Units', 'pixels', 'Position', [280 200 550 450]);
    wLayout = uigridlayout(wFig, [2 1], ...
        'RowHeight', {'1x', '1x'}, 'Padding', [10 10 10 10]);

    wAx1 = uiaxes(wLayout); wAx1.Layout.Row = 1;
    imagesc(wAx1, labelMap);
    colormap(wAx1, [0 0 0; lines(max(1, nSeeds))]);
    axis(wAx1, 'image'); wAx1.XTick = []; wAx1.YTick = [];
    title(wAx1, sprintf('Watershed: %d segments', numel(areas)), 'Interpreter', 'none');

    wAx2 = uiaxes(wLayout); wAx2.Layout.Row = 2;
    if ~isempty(areas)
        histogram(wAx2, areas, min(30, numel(areas)), ...
            'FaceColor', [0.4 0.7 0.4], 'EdgeColor', 'none');
    end
    xlabel(wAx2, 'Area (px)'); ylabel(wAx2, 'Count');
    title(wAx2, 'Size Distribution', 'Interpreter', 'none');

    result.fig = wFig;
    result.nSegments = numel(areas);
    result.areas = areas;
    result.labelMap = labelMap;
    result.statusMsg = sprintf('Watershed: %d segments (threshold=%.0f)', numel(areas), thresh);
end
