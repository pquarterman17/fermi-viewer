function folder = uigetdir(varargin)
%UIGETDIR (test shadow)  Returns a preset folder instead of opening a dialog.
%   Set via setappdata(0,'SHADOW_UIGETDIR','<dir>') before the call.
%   Returns 0 (cancelled) if unset.
    folder = getappdata(0, 'SHADOW_UIGETDIR');
    if isempty(folder)
        folder = 0;
        fprintf('[shadow:uigetdir] no target set -> cancelled\n');
        return;
    end
    fprintf('[shadow:uigetdir] -> %s\n', folder);
end
