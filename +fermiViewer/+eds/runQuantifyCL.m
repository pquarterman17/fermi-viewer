function appData = runQuantifyCL(appData, setStatus)
%RUNQUANTIFYCL  Cliff-Lorimer quantification across assigned EDS channels.
%
%   appData = fermiViewer.eds.runQuantifyCL(appData, setStatus)
%
%   Reads appData.edsChannels (must be populated) and appData.edsElements
%   (must be assigned), pulls the underlying pixel maps from
%   appData.images, runs imaging.eds.cliffLorimer, and stores the
%   atomic-% and weight-% maps back into appData. Syncs the EDS workshop.
%   Accept-and-return.

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
        chIdx  = appData.edsChannels{k}.imageIdx;
        maps{k} = double(appData.images{chIdx}.metadata.parserSpecific.imageData.pixels);
    end

    try
        result = imaging.eds.cliffLorimer(maps, appData.edsElements);
    catch ME
        setStatus(['Cliff-Lorimer error: ' ME.message]);
        return;
    end

    appData.edsAtomicPct  = result.atomicPctMaps;
    appData.edsWeightPct  = result.weightPctMaps;
    appData.edsQuantified = true;

    msg = 'Composition (at%): ';
    for k = 1:nCh
        msg = [msg sprintf('%s=%.1f%% ', appData.edsElements{k}, result.meanAtomicPct(k))]; %#ok<AGROW>
    end
    setStatus(msg);
    appData.edsWorkshop.sync(appData);
end
