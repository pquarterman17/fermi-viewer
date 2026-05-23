function answer = inputdlg(prompt, varargin)
%INPUTDLG (test shadow)  No-op stub that returns {} (user-cancelled) instead of prompting.
%
%   Shadows the built-in inputdlg() so headless test runs never block.
%   Empty-cell return is the standard "user cancelled" sentinel that
%   well-behaved callers (see fermiViewer.eds.runAssignElements) already
%   check via `if isempty(answer), return; end`.

    titleStr = 'Input';
    if nargin >= 2 && (ischar(varargin{1}) || isstring(varargin{1}))
        titleStr = char(string(varargin{1}));
    end
    if iscell(prompt)
        promptStr = strjoin(cellfun(@(p) char(string(p)), prompt, 'UniformOutput', false), ' | ');
    else
        promptStr = char(string(prompt));
    end
    fprintf('[shadow:inputdlg][%s] %s -> cancelled\n', titleStr, promptStr);
    answer = {};
end
