function overlayEdges(eelsAx, filterElem)
%OVERLAYEDGES  Draw EELS edge markers on an axes.
    arguments
        eelsAx      matlab.graphics.axis.Axes
        filterElem  char = 'All'
    end

    delete(findobj(eelsAx, 'Tag', 'eels_edge'));

    try
        edges = imaging.eelsEdgeTable();
    catch
        return;
    end

    if ~strcmp(filterElem, 'All') && ~isempty(edges)
        edges = edges(strcmp({edges.element}, filterElem));
    end

    hold(eelsAx, 'on');
    for k = 1:numel(edges)
        xline(eelsAx, edges(k).onsetEV, ':', 'Color', [0.8 0 0], ...
            'LineWidth', 0.8, 'Tag', 'eels_edge', ...
            'Label', edges(k).symbol, 'LabelVerticalAlignment', 'bottom');
    end
    hold(eelsAx, 'off');
end
