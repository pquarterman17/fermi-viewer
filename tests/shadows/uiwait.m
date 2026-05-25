function uiwait(varargin)
%UIWAIT (test shadow)  Non-blocking stub so headless tests never hang on a
%   modal dialog's uiwait — and never leave the dialog window open.
%
%   The built-in uiwait(h) blocks until uiresume(h) or h is deleted. In a
%   headless test run there is no user to click OK/Cancel, so a real uiwait
%   blocks forever: the suite hangs, per-suite cleanup never runs, and the
%   modal window (e.g. "Zoom to Dimensions", "Scale Bar Distance") is left
%   open. Many such windows pile up across a session.
%
%   This stub returns immediately. If the waited-on handle is a *modal*
%   dialog figure, it is deleted here so it doesn't linger — production
%   dialogs (zoomToDimensions, promptScaleBarDistance) are all
%   WindowStyle='modal'. The main app figure is WindowStyle='normal', so a
%   uiwait(fig) on it (interactive placement) is a harmless no-op and the
%   window is preserved.
%
%   Paired with the uiresume shadow (no-op), since production uiresume()
%   calls then have nothing to resume.

    fprintf('[shadow:uiwait]\n');
    if nargin < 1, return; end
    h = varargin{1};
    try
        if ~isempty(h) && isscalar(h) && ishghandle(h) ...
                && strcmp(get(h, 'Type'), 'figure') ...
                && isprop(h, 'WindowStyle') && strcmp(h.WindowStyle, 'modal')
            delete(h);
        end
    catch
        % invalid/stale handle — nothing to clean up
    end
end
