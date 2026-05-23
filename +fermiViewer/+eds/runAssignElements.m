function appData = runAssignElements(appData, setStatus)
%RUNASSIGNELEMENTS  Prompt user to assign element symbols to EDS channels.
%
%   appData = fermiViewer.eds.runAssignElements(appData, setStatus)
%
%   Auto-detects an element symbol from each channel label
%   (e.g. "Fe_Ka" -> "Fe"), prompts the user via inputdlg to confirm or
%   override, then stores the result in appData.edsElements and syncs
%   the EDS workshop. No-op if EDS mode is off or no channels loaded.
%   User-cancel preserves existing assignments. Accept-and-return.

    if ~appData.edsMode || isempty(appData.edsChannels)
        return;
    end

    nCh      = numel(appData.edsChannels);
    elements = cell(1, nCh);

    for k = 1:nCh
        lbl = appData.edsChannels{k}.label;
        tok = regexp(lbl, '^([A-Z][a-z]?)', 'tokens', 'once');
        if ~isempty(tok)
            elements{k} = tok{1};
        else
            elements{k} = sprintf('El%d', k);
        end
    end

    prompt   = cell(1, nCh);
    defaults = cell(1, nCh);
    for k = 1:nCh
        prompt{k}   = sprintf('Channel %d (%s):', k, appData.edsChannels{k}.label);
        defaults{k} = elements{k};
    end

    answer = inputdlg(prompt, 'Assign Elements', 1, defaults);
    if isempty(answer)
        return;
    end

    appData.edsElements = answer';
    setStatus(sprintf('Elements assigned: %s', strjoin(appData.edsElements, ', ')));
    appData.edsWorkshop.sync(appData);
end
