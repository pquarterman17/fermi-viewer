function result = displayMeasurementStats(stats)
%DISPLAYMEASUREMENTSTATS  Show histogram and sorted plot of measurement distances.
    arguments
        stats   struct
    end

    dists = stats.distances;
    statsFig = figure('Name', 'Measurement Statistics', 'NumberTitle', 'off', ...
        'Units', 'pixels', 'Position', [300 200 500 400], 'Tag', 'fermiViewerMeasStats');
    subplot(2, 1, 1);
    histogram(dists, max(3, round(sqrt(numel(dists)))));
    xlabel('Distance'); ylabel('Count');
    title(sprintf('N=%d, Mean=%.2f, Std=%.2f, Min=%.2f, Max=%.2f', ...
        stats.count, stats.mean, stats.std, stats.min, stats.max));
    subplot(2, 1, 2);
    plot(1:numel(dists), sort(dists), 'bo-', 'LineWidth', 1.5);
    xlabel('Rank'); ylabel('Distance'); title('Sorted Measurements');

    result.fig = statsFig;
    result.statusMsg = sprintf('Stats: N=%d, mean=%.2f ± %.2f', stats.count, stats.mean, stats.std);
end
