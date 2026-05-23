function answer = uiconfirm(varargin)
%UICONFIRM (test shadow)  No-op stub that returns 'Cancel' instead of opening a dialog.
%
%   Shadows the built-in uiconfirm() so headless test runs never block on
%   confirmation prompts. Returns the cancellation sentinel — production
%   code that confirms before a destructive action will safely no-op.

    msg = '';
    titleStr = '';
    if nargin >= 2 && (ischar(varargin{2}) || isstring(varargin{2}))
        msg = char(string(varargin{2}));
    end
    if nargin >= 3 && (ischar(varargin{3}) || isstring(varargin{3}))
        titleStr = char(string(varargin{3}));
    end
    if isempty(titleStr)
        fprintf('[shadow:uiconfirm] %s -> Cancel\n', msg);
    else
        fprintf('[shadow:uiconfirm][%s] %s -> Cancel\n', titleStr, msg);
    end
    answer = 'Cancel';
end
