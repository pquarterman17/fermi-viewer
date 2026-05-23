function uialert(varargin)
%UIALERT (test shadow)  No-op stub that logs the message instead of opening a dialog.
%
%   Shadows the built-in uialert() so headless test runs never block on
%   stray alerts. Production code should use fermiViewer.chrome.quietAlert,
%   but this catches anything that slips through.
%
%   Signature mirrors built-in: uialert(fig, msg, title, opts...)

    msg = '';
    titleStr = '';
    if nargin >= 2 && (ischar(varargin{2}) || isstring(varargin{2}))
        msg = char(string(varargin{2}));
    end
    if nargin >= 3 && (ischar(varargin{3}) || isstring(varargin{3}))
        titleStr = char(string(varargin{3}));
    end
    if isempty(titleStr)
        fprintf('[shadow:uialert] %s\n', msg);
    else
        fprintf('[shadow:uialert][%s] %s\n', titleStr, msg);
    end
end
