function [file, path] = uiputfile(varargin)
%UIPUTFILE (test shadow)  Returns a preset target instead of opening a dialog.
%   Set via setappdata(0,'SHADOW_UIPUTFILE','<fullpath>') before the call.
%   Returns {0,0} (cancelled) if unset.
    target = getappdata(0, 'SHADOW_UIPUTFILE');
    if isempty(target)
        file = 0; path = 0;
        fprintf('[shadow:uiputfile] no target set -> cancelled\n');
        return;
    end
    [p, n, e] = fileparts(target);
    file = [n e];
    path = [p filesep];
    fprintf('[shadow:uiputfile] -> %s\n', target);
end
