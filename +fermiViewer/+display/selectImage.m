function [appData, directive] = selectImage(appData, idx)
%SELECTIMAGE  Set the active image index; tell the caller what to redraw.
%   directive: 'none' | 'L' | 'R' | 'single' — the caller dispatches the
%   matching closure redraw (displayCompareImage / displayImage) AFTER
%   assigning the returned appData, per the follow-up-after-assignment
%   ordering contract.

    directive = 'none';
    if idx < 1 || idx > numel(appData.images)
        return;
    end

    appData.activeIdx = idx;

    % In compare mode, update the active panel instead
    if appData.compareMode
        if appData.compareActivePanel == 'L'
            appData.compareIdxL = idx;
            directive = 'L';
        else
            appData.compareIdxR = idx;
            directive = 'R';
        end
        return;
    end

    directive = 'single';
end
