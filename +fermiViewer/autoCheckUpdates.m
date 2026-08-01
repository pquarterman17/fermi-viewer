function prefs = autoCheckUpdates(fig, prefs, prefsFilePath, setStatus)
%AUTOCHECKUPDATES  Opt-in weekly update check, deferred off the launch path.
%
%   Syntax
%     prefs = fermiViewer.autoCheckUpdates(fig, prefs, prefsFilePath, setStatus)
%
%   Inputs
%     fig           — FermiViewer uifigure (parent). The deferred timer
%                     checks isvalid(fig) before touching any UI, since
%                     the user may close the window before it fires.
%     prefs         — appData.prefs struct; consulted via
%                     fermiViewer.shouldAutoCheck.
%     prefsFilePath — path to .emviewer_prefs.mat. The check-due stamp is
%                     persisted here BEFORE the network call, so a
%                     hung/failing check cannot force a re-check on every
%                     subsequent launch.
%     setStatus     — function handle, setStatus(msg), used to report a
%                     quiet status-bar message if a newer release exists.
%
%   Outputs
%     prefs — updated prefs struct (accept-and-return convention; caller
%             assigns appData.prefs = fermiViewer.autoCheckUpdates(...)).
%
%   Returns prefs unchanged, with no timer created, when running headless
%   (fermiViewer.chrome.isHeadless) or when fermiViewer.shouldAutoCheck
%   says a check is not due yet — critical so headless/automated test
%   runs never make a network call.
%
%   Otherwise the actual GitHub check is deferred to a one-shot timer
%   (StartDelay ~4s) so launch is never blocked by network latency. The
%   timer is tagged 'fermiViewerUpdateCheck' so FermiViewer's close path
%   can find and delete a still-pending one
%   (delete(timerfindall('Tag','fermiViewerUpdateCheck'))), and the timer
%   deletes itself once it fires. Quiet by design: unlike the manual
%   Help > Check for Updates action, this never shows a modal dialog —
%   it only ever reports 'update' via setStatus, and stays silent for
%   'current' / 'offline' / 'unknown'.
%
%   Examples
%     appData.prefs = fermiViewer.autoCheckUpdates(fig, appData.prefs, ...
%                          prefsFilePath, @setStatus);
%
%   See also FERMIVIEWER.SHOULDAUTOCHECK, FERMIVIEWER.CHECKFORUPDATES,
%   FERMIVIEWER.PROMPTCHECKUPDATES

    if fermiViewer.chrome.isHeadless()
        return;
    end
    if ~fermiViewer.shouldAutoCheck(prefs, now())
        return;
    end

    prefs.lastUpdateCheck = now();
    try
        save(prefsFilePath, 'prefs');
    catch
        % Non-fatal -- the check still runs; the next launch may re-stamp.
    end

    t = timer('StartDelay', 4, 'ExecutionMode', 'singleShot', ...
               'Tag', 'fermiViewerUpdateCheck', ...
               'TimerFcn', @(src, ~) onAutoCheckFire(src, fig, setStatus));
    start(t);
end

% ────────────────────────────────────────────────────────────────────────
function onAutoCheckFire(src, fig, setStatus)
%ONAUTOCHECKFIRE  Timer callback: run the deferred check, then self-delete.
    try
        if isvalid(fig)
            r = fermiViewer.checkForUpdates('Timeout', 4);
            if isvalid(fig) && strcmp(r.status, 'update')
                setStatus(sprintf(['Update available: v%s (you have v%s) — ' ...
                    'see Help > Check for Updates...'], r.latest, r.current));
            end
        end
    catch
        % Swallow -- this is a background, non-blocking, quiet check.
    end
    if isvalid(src)
        stop(src);
        delete(src);
    end
end
