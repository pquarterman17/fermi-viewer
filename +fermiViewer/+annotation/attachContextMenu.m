function attachContextMenu(fig, a, idx, dispatchFn)
%ATTACHCONTEXTMENU  Build and attach a right-click context menu to an annotation.
%
%   fermiViewer.annotation.attachContextMenu(fig, a, idx, dispatchFn)
%
%   Builds a uicontextmenu with Color submenu (7 named colors), Font size /
%   Edit text items (for text annotations with hText), and Delete; binds it
%   to every visual handle on the annotation struct (hText/hLine/hHead/
%   hRect/hCircle).
%
%   INPUTS:
%       fig         - parent uifigure for the context menu
%       a           - annotation struct (must have at least one valid hX handle)
%       idx         - 1-based index of this annotation in the workshop list
%       dispatchFn  - function handle for dispatching menu actions; called as
%                     dispatchFn(action, idx [, extra]) where action is one of
%                     'setColor', 'setFontSize', 'editText', 'deleteOne', 'startDrag'
%
%   See also fermiViewer.annotation.onAnnotationAction.

    cm = uicontextmenu(fig);
    colors = struct('White',[1 1 1], 'Cyan',[0 1 1], 'Yellow',[1 1 0], ...
                    'Red',[1 0 0], 'Green',[0 0.8 0], 'Blue',[0 0.4 1], 'Black',[0 0 0]);
    cmColor = uimenu(cm, 'Text', 'Color');
    cNames = fieldnames(colors);
    for ck = 1:numel(cNames)
        cn = cNames{ck};
        uimenu(cmColor, 'Text', cn, ...
            'MenuSelectedFcn', @(~,~) dispatchFn('setColor', idx, colors.(cn)));
    end
    if isfield(a, 'hText') && ~isempty(a.hText)
        uimenu(cm, 'Text', 'Font size', ...
            'MenuSelectedFcn', @(~,~) dispatchFn('setFontSize', idx));
        uimenu(cm, 'Text', 'Edit text', ...
            'MenuSelectedFcn', @(~,~) dispatchFn('editText', idx));
    end
    uimenu(cm, 'Text', 'Delete', 'Separator', 'on', ...
        'MenuSelectedFcn', @(~,~) dispatchFn('deleteOne', idx));

    for fk = {'hText','hLine','hHead','hRect','hCircle'}
        fn = fk{1};
        if isfield(a, fn) && ~isempty(a.(fn)) && isvalid(a.(fn))
            a.(fn).ContextMenu = cm;
            a.(fn).HitTest = 'on';
            a.(fn).PickableParts = 'all';
            a.(fn).ButtonDownFcn = @(~,~) dispatchFn('startDrag', idx);
        end
    end
end
