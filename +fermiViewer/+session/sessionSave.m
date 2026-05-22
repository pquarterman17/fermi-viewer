function appData = sessionSave(appData, fig, sldLow, sldHigh, ddColormap, outPath, setStatus)
%SESSIONSAVE  Persist a FermiViewer session to a .mat file.
%
%   appData = fermiViewer.session.sessionSave(appData, fig, sldLow, sldHigh, ddColormap, outPath, setStatus)
%
%   Bundles loaded images, active index, gamma, ROI list, measurement
%   log, current contrast slider values, current colormap selection,
%   user prefs, and EDS channel state into a 'session' struct; writes
%   it to outPath with -v7.3 (large-data support). Stores outPath into
%   appData.sessionFile on success. Accept-and-return.

    fig.Pointer = 'watch'; drawnow;
    try
        session.images     = appData.images;
        session.activeIdx  = appData.activeIdx;
        session.gamma      = appData.gamma;
        session.roiList    = appData.roiList;
        session.measureLog = appData.measurementLog;
        session.contrastLow  = sldLow.Value;
        session.contrastHigh = sldHigh.Value;
        session.colormap     = ddColormap.Value;
        session.prefs        = appData.prefs;
        session.edsChannels  = appData.edsChannels;
        save(outPath, 'session', '-v7.3');
        appData.sessionFile = outPath;
        setStatus(sprintf('Session saved: %s', outPath));
    catch ME
        fermiViewer.chrome.quietAlert(fig, sprintf('Save failed:\n%s', ME.message), ...
            'Session Error', 'Icon', 'error');
    end
    fig.Pointer = 'arrow';
end
