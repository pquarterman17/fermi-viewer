function h = errordlg(message, varargin)
%ERRORDLG (test shadow)  No-op stub that returns empty handle instead of opening a dialog.

    titleStr = '';
    if nargin >= 1 && (ischar(varargin{1}) || isstring(varargin{1}))
        titleStr = char(string(varargin{1}));
    end
    if isempty(titleStr)
        fprintf('[shadow:errordlg] %s\n', char(string(message)));
    else
        fprintf('[shadow:errordlg][%s] %s\n', titleStr, char(string(message)));
    end
    h = gobjects(0);
end
