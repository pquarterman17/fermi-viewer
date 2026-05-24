function runExportProfileToDP(fig, appData, setStatus)
%RUNEXPORTPROFILETODP  Export the last line profile as a CSV for BosonPlotter.
%
%   fermiViewer.export.runExportProfileToDP(fig, appData, setStatus)
%
%   FermiViewer was split out of quantized_matlab, where BosonPlotter now
%   lives in its own repo and its own MATLAB session. Two sessions can't
%   share base-workspace variables, so the interop bridge is file-based: we
%   write the profile to a CSV that BosonPlotter imports with
%   parser.importCSV (see docs/development.md "Interop"). This used to assignin a
%   struct to the base workspace and launch a now-nonexistent BosonPlotter;
%   that both failed silently AND crashed earlier on a malformed
%   createDataStruct call. This version saves a CSV and tells the user the
%   exact import command — no cross-repo coupling, gentle on every failure.
%
%   Inputs:
%       fig       - parent figure (for dialogs)
%       appData   - viewer state (reads lastProfile + active image name)
%       setStatus - @(msg) status-bar updater
%   No return value (no appData mutation).

    lastProfile = appData.lastProfile;
    if isempty(lastProfile) || ~isfield(lastProfile, 'dist') || isempty(lastProfile.dist)
        fermiViewer.chrome.quietAlert(fig, ...
            'No line profile available. Draw a Line Profile first.', ...
            'Export Profile', 'Icon', 'warning');
        return;
    end

    % Default filename from the active image, mirroring the Export CSV path.
    if appData.activeIdx >= 1
        [~, bname] = fileparts(appData.images{appData.activeIdx}.metadata.source);
        defName = [bname '_profile.csv'];
    else
        defName = 'line_profile.csv';
    end
    startPath = appData.lastDir;
    if isempty(startPath) || ~isfolder(startPath)
        startPath = pwd;
    end

    [saveName, saveDir] = uiputfile('*.csv', ...
        'Export Line Profile for BosonPlotter', fullfile(startPath, defName));
    if isequal(saveName, 0)
        return;   % user cancelled — not an error
    end
    outPath = fullfile(saveDir, saveName);

    % Write a CSV BosonPlotter's parser.importCSV reads directly: a single
    % header line (calibrated distance unit preserved) + two columns.
    try
        M       = [lastProfile.dist(:), lastProfile.intensity(:)];
        unitStr = lastProfile.unit;
        if isempty(unitStr), unitStr = 'px'; end
        header  = sprintf('Distance (%s),Intensity', unitStr);

        fid = fopen(outPath, 'w');
        if fid == -1
            error('fermiViewer:export:cannotWrite', ...
                'Cannot open file for writing:\n%s', outPath);
        end
        fprintf(fid, '%s\n', header);
        fclose(fid);
        writematrix(M, outPath, 'WriteMode', 'append');

        setStatus(sprintf('Profile saved: %s  —  in BosonPlotter: parser.importCSV(''%s'')', ...
            saveName, strrep(outPath, '''', '''''')));
    catch ME
        fermiViewer.chrome.quietAlert(fig, ...
            sprintf('Could not export the profile CSV:\n%s', ME.message), ...
            'Export Profile', 'Icon', 'error');
    end
end
