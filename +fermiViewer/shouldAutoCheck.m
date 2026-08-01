function tf = shouldAutoCheck(prefs, nowNum, options)
%SHOULDAUTOCHECK  Decide whether a weekly auto update-check is due.
%
%   Syntax
%     tf = fermiViewer.shouldAutoCheck(prefs, nowNum)
%     tf = fermiViewer.shouldAutoCheck(prefs, nowNum, Name=Value)
%
%   Inputs
%     prefs   — appData.prefs struct (or any struct). Consults
%               .autoCheckUpdates (logical) and .lastUpdateCheck (a
%               datenum-style double). Missing fields, or fields of the
%               wrong type (old/hand-edited pref files), are tolerated
%               and simply return false rather than erroring.
%     nowNum  — current time as a datenum-style double, e.g. now().
%               Taken as an argument (never read internally) so this
%               function is pure and deterministic for tests.
%
%   Name-Value
%     IntervalDays (1,1) double = 7   Days required between checks.
%
%   Outputs
%     tf — true only when prefs.autoCheckUpdates is true AND at least
%          IntervalDays days have elapsed since prefs.lastUpdateCheck
%          (lastUpdateCheck = 0, i.e. "never checked", always qualifies).
%
%   Examples
%     p = struct('autoCheckUpdates', true, 'lastUpdateCheck', 0);
%     tf = fermiViewer.shouldAutoCheck(p, now());              % true
%
%     p = struct('autoCheckUpdates', true, 'lastUpdateCheck', now() - 2);
%     tf = fermiViewer.shouldAutoCheck(p, now());              % false (too soon)
%
%   See also FERMIVIEWER.AUTOCHECKUPDATES, FERMIVIEWER.CHECKFORUPDATES

    arguments
        prefs  (1,1) struct
        nowNum (1,1) double
        options.IntervalDays (1,1) double = 7
    end

    tf = false;
    try
        if ~isequal(prefs.autoCheckUpdates, true)
            return;
        end
        last = prefs.lastUpdateCheck;
        if ~isnumeric(last) || ~isscalar(last) || ~isfinite(last)
            return;
        end
        tf = (nowNum - last) >= options.IntervalDays;
    catch
        tf = false;   % missing/malformed fields -> not due, never error
    end
end
