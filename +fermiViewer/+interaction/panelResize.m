function result = panelResize(action, varargin)
%PANELRESIZE  Detect / start / live-update drag-resizing of side panels.
%
%   dir = fermiViewer.interaction.panelResize('detect', ctx)
%   appData = fermiViewer.interaction.panelResize('start', appData, ctx)
%   appData = fermiViewer.interaction.panelResize('move',  appData, ctx)
%
%   ctx fields (always passed):
%       .fig         - parent uifigure
%       .listPanel   - left panel handle
%       .toolsPanel  - right panel handle
%       .mainGL      - main grid layout
%       .SNAP_PX     - snap distance constant
%       .MIN_LEFT_W  - min left-panel width
%       .MIN_TOOLS_W - min tools-panel width
%
%   'start' extra: ctx.onMove + ctx.onUp are the WindowButtonMotionFcn /
%   WindowButtonUpFcn handlers installed during drag.

    switch action
        case 'detect'
            result = doDetect(varargin{:});
        case 'start'
            result = doStart(varargin{:});
        case 'move'
            result = doMove(varargin{:});
        otherwise
            error('fermiViewer:interaction:panelResize:unknownAction', ...
                'Unknown action "%s".', action);
    end
end

function dir = doDetect(ctx)
    dir = '';
    try
        mp = ctx.fig.CurrentPoint;
        lPos = getpixelposition(ctx.listPanel, true);
        borderX = lPos(1) + lPos(3);
        if abs(mp(1) - borderX) <= ctx.SNAP_PX && ...
           mp(2) >= lPos(2) && mp(2) <= lPos(2) + lPos(4)
            dir = 'v_col12'; return;
        end
        tPos = getpixelposition(ctx.toolsPanel, true);
        borderX = tPos(1);
        if abs(mp(1) - borderX) <= ctx.SNAP_PX && ...
           mp(2) >= tPos(2) && mp(2) <= tPos(2) + tPos(4)
            dir = 'v_col23'; return;
        end
    catch
        % getpixelposition may throw on first render
    end
end

function appData = doStart(appData, ctx)
    mp = ctx.fig.CurrentPoint;
    appData.panelResizeStart = mp;

    if strcmp(appData.panelResizeDir, 'v_col12')
        try
            lPos = getpixelposition(ctx.listPanel, true);
            appData.panelResizeOrig = lPos(3);
        catch
            appData.panelResizeOrig = appData.leftPanelWidth;
        end
    elseif strcmp(appData.panelResizeDir, 'v_col23')
        try
            tPos = getpixelposition(ctx.toolsPanel, true);
            appData.panelResizeOrig = tPos(3);
        catch
            appData.panelResizeOrig = appData.toolsPanelWidth;
        end
    end

    ctx.fig.WindowButtonMotionFcn = ctx.onMove;
    ctx.fig.WindowButtonUpFcn     = ctx.onUp;
end

function appData = doMove(appData, ctx)
    if isempty(appData.panelResizeStart), return; end
    mp = ctx.fig.CurrentPoint;

    if strcmp(appData.panelResizeDir, 'v_col12')
        delta = mp(1) - appData.panelResizeStart(1);
        newW  = round(appData.panelResizeOrig + delta);
        newW  = max(ctx.MIN_LEFT_W, min(newW, 400));
        appData.leftPanelWidth = newW;
        cw = ctx.mainGL.ColumnWidth;
        cw{1} = newW;
        ctx.mainGL.ColumnWidth = cw;

    elseif strcmp(appData.panelResizeDir, 'v_col23')
        delta = mp(1) - appData.panelResizeStart(1);
        newW  = round(appData.panelResizeOrig - delta);
        newW  = max(ctx.MIN_TOOLS_W, min(newW, 500));
        appData.toolsPanelWidth = newW;
        cw = ctx.mainGL.ColumnWidth;
        cw{3} = newW;
        ctx.mainGL.ColumnWidth = cw;
    end
end
