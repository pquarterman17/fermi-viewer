function result = executeBatchProfiles(images, x1, y1, x2, y2)
%EXECUTEBATCHPROFILES  Line profile measurement across all images at same coordinates.
    arguments
        images  cell
        x1      double
        y1      double
        x2      double
        y2      double
    end

    batchFig = figure('Name', 'Batch Line Profiles', 'NumberTitle', 'off', ...
        'Tag', 'fermiViewerBatchMeas');
    batchAx = axes(batchFig);
    hold(batchAx, 'on');
    legends = {};
    for bi = 1:numel(images)
        gray = imaging.getGrayscale(images{bi});
        [dist, intensity] = imaging.lineProfile(gray, x1, y1, x2, y2);
        plot(batchAx, dist, intensity, 'LineWidth', 1.2);
        [~, fn, fe] = fileparts(images{bi}.metadata.source);
        legends{bi} = [fn fe]; %#ok<AGROW>
    end
    hold(batchAx, 'off');
    legend(batchAx, legends, 'Interpreter', 'none', 'Location', 'best');
    xlabel(batchAx, 'Distance (px)'); ylabel(batchAx, 'Intensity');
    title(batchAx, sprintf('Batch profiles: (%d,%d) to (%d,%d)', x1, y1, x2, y2));

    result.fig = batchFig;
    result.statusMsg = sprintf('Batch profiles: %d images', numel(images));
end
