function result = executeParticleCount(px, thresh, minArea, pixelSize, pixelUnit, calibrated)
%EXECUTEPARTICLECOUNT  Particle detection via threshold + connected components.
    arguments
        px          double
        thresh      double
        minArea     double
        pixelSize   double = NaN
        pixelUnit   char   = 'px'
        calibrated  logical = false
    end

    bw = px > thresh;
    labelMap = imaging.bwlabel(bw);
    nLabels = max(labelMap(:));

    areas = [];
    for li = 1:nLabels
        a = sum(labelMap(:) == li);
        if a >= minArea
            areas(end+1) = a; %#ok<AGROW>
        end
    end

    unitStr = 'px²';
    areaScale = 1;
    if calibrated && ~isnan(pixelSize)
        areaScale = pixelSize^2;
        unitStr = sprintf('%s²', pixelUnit);
    end

    pFig = figure('Name', 'Particle Analysis', 'NumberTitle', 'off', ...
        'Units', 'pixels', 'Position', [280 200 550 450]);
    pLayout = uigridlayout(pFig, [2 1], ...
        'RowHeight', {'1x', '1x'}, 'Padding', [10 10 10 10]);

    pAx1 = uiaxes(pLayout); pAx1.Layout.Row = 1;
    imagesc(pAx1, labelMap);
    colormap(pAx1, [0 0 0; lines(max(1, nLabels))]);
    axis(pAx1, 'image'); pAx1.XTick = []; pAx1.YTick = [];
    title(pAx1, sprintf('%d particles (>%d px)', numel(areas), minArea), 'Interpreter', 'none');

    pAx2 = uiaxes(pLayout); pAx2.Layout.Row = 2;
    if ~isempty(areas)
        histogram(pAx2, areas * areaScale, min(30, numel(areas)), ...
            'FaceColor', [0.4 0.7 0.4], 'EdgeColor', 'none');
    end
    xlabel(pAx2, sprintf('Area (%s)', unitStr)); ylabel(pAx2, 'Count');
    title(pAx2, 'Size Distribution', 'Interpreter', 'none');

    result.fig = pFig;
    result.nParticles = numel(areas);
    result.areas = areas;
    result.areaScale = areaScale;
    result.unitStr = unitStr;
    result.statusMsg = sprintf('Found %d particles (threshold=%.0f, minArea=%d)', ...
        numel(areas), thresh, minArea);
end
