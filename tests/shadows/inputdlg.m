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
        nFields = numel(prompt);
    else
        promptStr = char(string(prompt));
        nFields = 1;
    end
    % Preset-answer path: setappdata(0,'SHADOW_INPUTDLG', {'a','b',...}) to
    % return values instead of the default cancel ({}). Used to exercise
    % dialog-driven flows (e.g. journal export) headlessly.
    preset = getappdata(0, 'SHADOW_INPUTDLG');
    if ~isempty(preset) && iscell(preset)
        answer = preset(:);
        if numel(answer) < nFields, answer(end+1:nFields) = {''}; end
        fprintf('[shadow:inputdlg][%s] %s -> preset %s\n', titleStr, promptStr, strjoin(answer', ','));
        return;
    end
    fprintf('[shadow:inputdlg][%s] %s -> cancelled\n', titleStr, promptStr);
    answer = {};
end
