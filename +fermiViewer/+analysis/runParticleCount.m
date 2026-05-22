function appData = runParticleCount(appData, fig, setStatus)
%RUNPARTICLECOUNT  Threshold-and-count workflow with dialog and result record.
%
%   appData = fermiViewer.analysis.runParticleCount(appData, fig, setStatus)
%
%   Prompts for threshold + min-area, runs particle count on
%   appData.filteredPixels, records the result on the processing
%   workshop model. Accept-and-return: caller must capture the returned
%   appData (procWorkshop.recordParticleResult mutates workshop state).

    if isempty(appData.filteredPixels), return; end
    dMin = min(appData.filteredPixels(:));
    dMax = max(appData.filteredPixels(:));
    defThresh = num2str(round((dMin + dMax) / 2));
    answer = inputdlg( ...
        {sprintf('Threshold (%.0f – %.0f):', dMin, dMax), ...
         'Min particle area (pixels):'}, ...
        'Particle Detection', [1 44], {defThresh, '10'});
    if isempty(answer), return; end
    thresh = str2double(answer{1});
    minArea = str2double(answer{2});
    if isnan(thresh) || isnan(minArea) || minArea < 1
        fermiViewer.chrome.quietAlert(fig, 'Invalid parameters.', 'Error', 'Icon', 'error');
        return;
    end
    pixSz = NaN; pixUnit = 'px'; cal = false;
    if appData.activeIdx >= 1
        imgInfo = appData.images{appData.activeIdx}.metadata.parserSpecific.imageData;
        pixSz = imgInfo.pixelSize; pixUnit = imgInfo.pixelUnit; cal = imgInfo.calibrated;
    end
    fig.Pointer = 'watch'; drawnow;
    r = fermiViewer.analysis.executeParticleCount(appData.filteredPixels, thresh, minArea, pixSz, pixUnit, cal);
    fig.Pointer = 'arrow';
    setStatus(r.statusMsg);
    appData.procWorkshop.recordParticleResult(r.nParticles, thresh, minArea);
end
