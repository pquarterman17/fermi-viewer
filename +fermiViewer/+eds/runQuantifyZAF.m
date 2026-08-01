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
%   when callers pass NaN.
%
%   Blank at%-map suppression (imaging.eds.mapIsBlank): an element that
%   isn't really present still spikes to ~100 at% in stray noise/vacuum
%   pixels once normalized per pixel — coverage, not peak value, tells
%   present from absent. Elements judged blank are dropped from
%   appData.edsElements/edsAtomicPct/edsWeightPct (the three stay
%   index-aligned) so they don't clutter downstream tools (ROI/profile, the
%   EDS workshop panel) with noise; the status message names them.
%   Syncs the EDS workshop. Accept-and-return.

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
        result = imaging.eds.zafCorrection(maps, appData.edsElements, ...
            'Thickness', thickness, 'TakeOffAngle', takeoff);
    catch ME
        setStatus(sprintf('ZAF failed: %s', ME.message));
        return;
    end

    msg = 'ZAF (at%): ';
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
