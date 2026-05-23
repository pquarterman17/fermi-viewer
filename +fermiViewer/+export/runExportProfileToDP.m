function runExportProfileToDP(fig, lastProfile, setStatus)
%RUNEXPORTPROFILETODP  Push last line profile to base workspace + launch BosonPlotter.
%
%   fermiViewer.export.runExportProfileToDP(fig, lastProfile, setStatus)
%
%   Wraps the profile (distance + intensity + unit) in a unified
%   parser.createDataStruct, assigns it to base workspace as
%   'profileData', and attempts to launch BosonPlotter so the user can
%   inspect/plot the profile in the broader workflow. No appData mutation
%   (no return value). Warns via fermiViewer.chrome.quietAlert if the
%   profile cache is empty.

    if isempty(lastProfile.dist)
        fermiViewer.chrome.quietAlert(fig, 'No line profile available. Draw one first.', ...
            'Export', 'Icon', 'warning');
        return;
    end

    data = parser.createDataStruct( ...
        lastProfile.dist, ...
        lastProfile.intensity, ...
        {'Intensity'}, ...
        {lastProfile.unit}, ...
        struct('source', 'FermiViewer line profile', 'parserName', 'FermiViewer'));

    assignin('base', 'profileData', data);
    setStatus('Line profile exported to workspace as ''profileData''. Launch BosonPlotter to load.');

    try
        BosonPlotter;
    catch
        % BosonPlotter may not be on path; profileData remains in base.
    end
end
