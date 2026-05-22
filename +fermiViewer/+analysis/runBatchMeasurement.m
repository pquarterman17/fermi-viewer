function runBatchMeasurement(fig, images, setStatus)
%RUNBATCHMEASUREMENT  Prompt for line-profile coordinates and run across all images.

    if numel(images) < 2
        fermiViewer.chrome.quietAlert(fig, 'Need 2+ images for batch measurement.', 'Batch', 'Icon', 'warning'); return;
    end
    answer = inputdlg({'X1:', 'Y1:', 'X2:', 'Y2:'}, ...
        'Line Profile Coordinates (same for all images)', 1, {'10', '10', '100', '100'});
    if isempty(answer), return; end
    x1 = str2double(answer{1}); y1 = str2double(answer{2});
    x2 = str2double(answer{3}); y2 = str2double(answer{4});
    fig.Pointer = 'watch'; drawnow;
    try
        r = fermiViewer.analysis.executeBatchProfiles(images, x1, y1, x2, y2);
        fig.Pointer = 'arrow';
        setStatus(r.statusMsg);
    catch ME
        fig.Pointer = 'arrow';
        fermiViewer.chrome.quietAlert(fig, sprintf('Batch failed:\n%s', ME.message), 'Error', 'Icon', 'error');
    end
end
