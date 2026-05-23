function appData = runQuantifyZAF(appData, setStatus, thickness, takeoff)
%RUNQUANTIFYZAF  ZAF-corrected EDS quantification for thick specimens.
%
%   appData = fermiViewer.eds.runQuantifyZAF(appData, setStatus, ...
%                                            thickness, takeoff)
%
%   Pulls pixel maps for each EDS channel from appData.images, runs
%   imaging.eds.zafCorrection with the supplied thickness (nm) and
%   take-off angle (deg), then stores the atomic-% and weight-% maps
%   back into appData. Sentinel defaults: thickness=100, takeoff=20
%   when callers pass NaN. Accept-and-return.

    if ~appData.edsMode || isempty(appData.edsChannels)
        return;
    end
    if isempty(appData.edsElements)
        setStatus('Assign elements first');
        return;
    end

    if nargin < 3 || isnan(thickness), thickness = 100; end
    if nargin < 4 || isnan(takeoff),   takeoff   = 20;  end

    nCh  = numel(appData.edsChannels);
    maps = cell(1, nCh);
    for k = 1:nCh
        chIdx  = appData.edsChannels{k}.imageIdx;
        maps{k} = double(appData.images{chIdx}.metadata.parserSpecific.imageData.pixels);
    end

    try
        result = imaging.eds.zafCorrection(maps, appData.edsElements, ...
            'Thickness', thickness, 'TakeOffAngle', takeoff);
    catch ME
        setStatus(sprintf('ZAF failed: %s', ME.message));
        return;
    end

    appData.edsAtomicPct  = result.atomicPctMaps;
    appData.edsWeightPct  = result.weightPctMaps;
    appData.edsQuantified = true;

    msg = 'ZAF (at%): ';
    for k = 1:nCh
        msg = [msg sprintf('%s=%.1f%% ', appData.edsElements{k}, result.meanAtomicPct(k))]; %#ok<AGROW>
    end
    setStatus(msg);
    appData.edsWorkshop.sync(appData);
end
