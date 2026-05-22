function runTemplateMatch(fig, ax, filteredPixels, setStatus)
%RUNTEMPLATEMATCH  Prompt for region, run template match, plot hits.
%
%   fermiViewer.processing.runTemplateMatch(fig, ax, filteredPixels, setStatus)
%
%   Pure side-effect: draws red '+' markers on ax for each match.
%   Does not mutate appData.

    if isempty(filteredPixels), return; end
    answer = inputdlg({'X start:', 'Y start:', 'Width:', 'Height:'}, ...
        'Select Template Region', 1, {'10', '10', '50', '50'});
    if isempty(answer), return; end
    x1 = str2double(answer{1}); y1 = str2double(answer{2});
    tw = str2double(answer{3}); th = str2double(answer{4});
    fig.Pointer = 'watch'; drawnow;
    try
        r = fermiViewer.processing.executeTemplateMatch(filteredPixels, x1, y1, tw, th);
        fig.Pointer = 'arrow';
        if r.nMatches > 0
            hold(ax, 'on');
            for mi = 1:r.nMatches
                plot(ax, r.locations(mi,2), r.locations(mi,1), 'r+', ...
                    'MarkerSize', 12, 'LineWidth', 2, 'HandleVisibility', 'off');
            end
            hold(ax, 'off');
        end
        setStatus(r.statusMsg);
    catch ME
        fig.Pointer = 'arrow';
        fermiViewer.chrome.quietAlert(fig, sprintf('Template match failed:\n%s', ME.message), 'Error', 'Icon', 'error');
    end
end
