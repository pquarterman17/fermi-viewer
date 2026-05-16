function varargout = scaleBar(action, varargin)
%SCALEBAR  Scale bar helper functions extracted from FermiViewer.
%
% Syntax:
%   emViewer.meas.scaleBar('deleteHandle', sb)
%   cm = emViewer.meas.scaleBar('buildLineMenu', fig, measurements, overlayColor, applyColorFn, applyColorAllFn, applySymFn, applySymAllFn)
%
% 'deleteHandle'
%   sb  — scale bar struct with fields .bar (rectangle) and .label (text)
%
% 'buildLineMenu'
%   Returns a uicontextmenu for a measurement line that provides color and
%   symbol sub-menus.
%   fig             — uifigure handle
%   hLine           — line graphics handle (target for menu actions)
%   applyColorFn    — @(hLine, clr)    apply color to one measurement
%   applyColorAllFn — @(hLine)          apply current color to all
%   applySymFn      — @(hLine, sym)    apply symbol to one measurement
%   applySymAllFn   — @(hLine)          apply current symbol to all
%
% Examples:
%   emViewer.meas.scaleBar('deleteHandle', appData.overlays.scalebar);

% ════════════════════════════════════════════════════════════════════
switch lower(action)
    case 'deletehandle'
        sb = varargin{1};
        deleteScaleBarHandle(sb);

    case 'buildlinemenu'
        [fig, hLine, applyColorFn, applyColorAllFn, applySymFn, applySymAllFn] = varargin{:};
        varargout{1} = buildMeasLineMenu(fig, hLine, applyColorFn, applyColorAllFn, applySymFn, applySymAllFn);

    otherwise
        error('emViewer:meas:scaleBar:unknownAction', ...
            'Unknown action "%s". Valid: deleteHandle, buildLineMenu', action);
end

% ════════════════════════════════════════════════════════════════════
function deleteScaleBarHandle(sb)
    if ~isempty(sb) && isstruct(sb)
        if isfield(sb, 'bar')   && isvalid(sb.bar),   delete(sb.bar);   end
        if isfield(sb, 'label') && isvalid(sb.label), delete(sb.label); end
    end

% ════════════════════════════════════════════════════════════════════
function cm = buildMeasLineMenu(fig, hLine, applyColorFn, applyColorAllFn, applySymFn, applySymAllFn)
    cm = uicontextmenu(fig);
    mC = uimenu(cm, 'Text', 'Line color');
    uimenu(mC, 'Text', 'White',  'MenuSelectedFcn', @(~,~) applyColorFn(hLine, [1 1 1]));
    uimenu(mC, 'Text', 'Cyan',   'MenuSelectedFcn', @(~,~) applyColorFn(hLine, [0 1 1]));
    uimenu(mC, 'Text', 'Yellow', 'MenuSelectedFcn', @(~,~) applyColorFn(hLine, [1 1 0]));
    uimenu(mC, 'Text', 'Red',    'MenuSelectedFcn', @(~,~) applyColorFn(hLine, [1 0 0]));
    uimenu(mC, 'Text', 'Green',  'MenuSelectedFcn', @(~,~) applyColorFn(hLine, [0 0.8 0]));
    uimenu(mC, 'Text', 'Blue',   'MenuSelectedFcn', @(~,~) applyColorFn(hLine, [0 0.4 1]));
    uimenu(mC, 'Text', 'Apply to all', 'Separator', 'on', ...
        'MenuSelectedFcn', @(~,~) applyColorAllFn(hLine));
    mS = uimenu(cm, 'Text', 'Symbol');
    uimenu(mS, 'Text', 'Circle', 'MenuSelectedFcn', @(~,~) applySymFn(hLine, 'circle'));
    uimenu(mS, 'Text', 'Cross',  'MenuSelectedFcn', @(~,~) applySymFn(hLine, 'cross'));
    uimenu(mS, 'Text', 'Square', 'MenuSelectedFcn', @(~,~) applySymFn(hLine, 'square'));
    uimenu(mS, 'Text', 'None',   'MenuSelectedFcn', @(~,~) applySymFn(hLine, 'none'));
    uimenu(mS, 'Text', 'Apply to all', 'Separator', 'on', ...
        'MenuSelectedFcn', @(~,~) applySymAllFn(hLine));
