function answer = questdlg(question, varargin)
%QUESTDLG (test shadow)  No-op stub that returns '' (user-closed) instead of prompting.
%
%   Shadows the built-in questdlg() so headless test runs never block.
%   Empty char return mirrors the "user closed dialog without choosing"
%   sentinel that questdlg callers must already handle.

    titleStr = 'Question';
    if nargin >= 2 && (ischar(varargin{1}) || isstring(varargin{1}))
        titleStr = char(string(varargin{1}));
    end
    fprintf('[shadow:questdlg][%s] %s -> ''''\n', titleStr, char(string(question)));
    answer = '';
end
