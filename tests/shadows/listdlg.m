function [sel, ok] = listdlg(varargin)
%LISTDLG (test shadow)  Returns a preset selection instead of opening a dialog.
%   Default: select item 1, ok=true. Override the index via
%   setappdata(0,'SHADOW_LISTDLG', <idx>). Set to 0 to simulate cancel.
    sel = getappdata(0, 'SHADOW_LISTDLG');
    if isempty(sel), sel = 1; end
    if isequal(sel, 0)
        sel = []; ok = 0;
        fprintf('[shadow:listdlg] -> cancelled\n');
        return;
    end
    ok = 1;
    fprintf('[shadow:listdlg] -> item %d\n', sel);
end
