function appData = runQuantifyCL(appData, setStatus)
%RUNQUANTIFYCL  Cliff-Lorimer quantification across assigned EDS channels.
%
%   appData = fermiViewer.eds.runQuantifyCL(appData, setStatus)
%
%   Reads appData.edsChannels (must be populated) and appData.edsElements
%   (must be assigned), pulls the underlying pixel maps from
%   appData.images, runs imaging.eds.cliffLorimer, and stores the
%   atomic-% and weight-% maps back into appData.
%
%   Blank at%-map suppression (imaging.eds.mapIsBlank): Cliff-Lorimer
%   normalizes atomic-% per pixel, so an element that isn't really present
%   still spikes to ~100 at% in stray noise/vacuum pixels — coverage, not
%   peak value, tells present from absent. Elements judged blank are
%   dropped from appData.edsElements/edsAtomicPct/edsWeightPct (the three
%   stay index-aligned) so they don't clutter downstream tools (ROI/profile,
%   the EDS workshop panel) with noise; the status message names them.
%   Syncs the EDS workshop. Accept-and-return.

    if ~appData.edsMode || isempty(appData.edsChannels)
        return;
    end
    if isempty(appData.edsElements)
        setStatus('Assign elements first');
        return;
    end

    nCh  = numel(appData.edsChannels);
    maps = cell(1, nCh);
    for k = 1:nCh
        ch = appData.edsChannels{k};
        if isfield(ch, 'map') && ~isempty(ch.map)
            % Cube-derived element channel: its map IS the intensity map.
            maps{k} = double(ch.map);
        else
            chIdx  = ch.imageIdx;
            maps{k} = double(appData.images{chIdx}.metadata.parserSpecific.imageData.pixels);
        end
    end

    try
        result = imaging.eds.cliffLorimer(maps, appData.edsElements);
    catch ME
        setStatus(['Cliff-Lorimer error: ' ME.message]);
        return;
    end

    msg = 'Composition (at%): ';
    for k = 1:nCh
        msg = [msg sprintf('%s=%.1f%% ', appData.edsElements{k}, result.meanAtomicPct(k))]; %#ok<AGROW>
    end

    blank = false(1, nCh);
    for k = 1:nCh
        blank(k) = imaging.eds.mapIsBlank(result.atomicPctMaps{k});
    end
    keep = ~blank;

    appData.edsAtomicPct  = result.atomicPctMaps(keep);
    appData.edsWeightPct  = result.weightPctMaps(keep);
    suppressed            = appData.edsElements(blank);
    appData.edsElements   = appData.edsElements(keep);
    appData.edsQuantified = true;

    if any(blank)
        n = nnz(blank);
        suffix = ''; if n ~= 1, suffix = 's'; end
        msg = [msg sprintf('| %d element%s suppressed as blank: %s', ...
            n, suffix, strjoin(suppressed, ', '))];
    end
    setStatus(msg);
    appData.edsWorkshop.sync(appData);
end
