function h = warndlg(message, varargin)
%WARNDLG (test shadow)  No-op stub that returns empty handle instead of opening a dialog.

    titleStr = '';
    if nargin >= 1 && (ischar(varargin{1}) || isstring(varargin{1}))
        titleStr = char(string(varargin{1}));
    end
    if isempty(titleStr)
        fprintf('[shadow:warndlg] %s\n', char(string(message)));
    else
        fprintf('[shadow:warndlg][%s] %s\n', titleStr, char(string(message)));
    end
    h = gobjects(0);
end
