function [file, path] = uigetfile(varargin)
%UIGETFILE (test shadow)  Returns a preset file instead of opening a dialog.
%   Set the target via setappdata(0,'SHADOW_UIGETFILE', '<fullpath>') before
%   the call. Returns {0,0} (user-cancelled) if unset.
    target = getappdata(0, 'SHADOW_UIGETFILE');
    if isempty(target)
        file = 0; path = 0;
        fprintf('[shadow:uigetfile] no target set -> cancelled\n');
        return;
    end
    [p, n, e] = fileparts(target);
    file = [n e];
    path = [p filesep];
    fprintf('[shadow:uigetfile] -> %s\n', target);
end
