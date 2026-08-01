function promptCheckUpdates(fig)
%PROMPTCHECKUPDATES  Help-menu action: notify whether a newer release exists.
%
%   Syntax
%     fermiViewer.promptCheckUpdates(fig)
%
%   Inputs
%     fig — FermiViewer uifigure (dialog parent)
%
%   Outputs
%     (none — shows a dialog)
%
%   Notification-only: on 'update' the dialog offers to open the GitHub
%   Releases page in the browser; nothing is downloaded or installed.
%   Uses the quiet* dialog wrappers so headless test runs log instead of
%   blocking.
%
%   See also FERMIVIEWER.CHECKFORUPDATES, FERMIVIEWER.APPVERSION

    r = fermiViewer.checkForUpdates();
    switch r.status
        case 'update'
            choice = fermiViewer.chrome.quietConfirm(fig, ...
                sprintf('Update available: v%s (you have v%s).', r.latest, r.current), ...
                'FermiViewer Update', ...
                'Options', {'Open Releases', 'Close'}, ...
                'DefaultOption', 'Close');
            if strcmp(choice, 'Open Releases')
                web(r.url, '-browser');
            end
        case 'current'
            fermiViewer.chrome.quietAlert(fig, ...
                sprintf('You are up to date (v%s).', r.current), ...
                'FermiViewer Update', 'Icon', 'success');
        case 'offline'
            fermiViewer.chrome.quietAlert(fig, ...
                'Could not reach GitHub to check for updates.', ...
                'FermiViewer Update', 'Icon', 'warning');
        otherwise
            fermiViewer.chrome.quietAlert(fig, ...
                'Could not determine the latest release version.', ...
                'FermiViewer Update', 'Icon', 'warning');
    end
end
