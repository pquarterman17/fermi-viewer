function appData = mouseOps(action, appData, ctx)
%MOUSEOPS  Dispatch table for mouse-interaction callbacks extracted from
%   FermiViewer.m.
%
%   Syntax
%     appData = emViewer.mouseOps('motion',            appData, ctx)
%     appData = emViewer.mouseOps('idleDown',          appData, ctx)
%     appData = emViewer.mouseOps('axesDown',          appData, ctx)
%     appData = emViewer.mouseOps('buildContextMenus', appData, ctx)
%     appData = emViewer.mouseOps('buildContextMenu',  appData, ctx)
%
%   ctx fields (widgets)
%     ctx.fig, ctx.ax, ctx.lbImages, ctx.lblStatusMouse, ctx.cbPixelInspector
%
%   ctx.cb callbacks — see buildMouseCtx in FermiViewer.m

switch action

    % ────────────────────────────────────────────────────────────────────
    case 'motion'
    %ONMOUSEMOTION  Cursor tracking, pixel info display, resize border detection.
        fig = ctx.fig;
        ax  = ctx.ax;

        if isempty(appData.captureMode) || strcmp(appData.captureMode, '')
            dir = ctx.cb.detectResizeBorder();
            appData.panelResizeDir = dir;
            if     ~isempty(dir) && startsWith(dir, 'v_'), fig.Pointer = 'left';
            elseif ~isempty(dir) && startsWith(dir, 'h_'), fig.Pointer = 'top';
            elseif appData.panMode,                        fig.Pointer = 'hand';
            else
                fig.Pointer = 'arrow';
            end
        end

        if isempty(ax) || ~isvalid(ax)
            return;
        end
        if appData.activeIdx < 1 || isempty(appData.rawPixels)
            ctx.lblStatusMouse.Text = '';
            return;
        end

        [H, W] = size(appData.rawPixels);
        cp = ax.CurrentPoint;
        xData = cp(1, 1);
        yData = cp(1, 2);

        if xData < ax.XLim(1) || xData > ax.XLim(2) || ...
           yData < ax.YLim(1) || yData > ax.YLim(2)
            ctx.lblStatusMouse.Text = '';
            return;
        end

        col = round(xData);
        row = round(yData);

        if col < 1 || col > W || row < 1 || row > H
            ctx.lblStatusMouse.Text = '';
            return;
        end

        intensity = appData.rawPixels(row, col);

        if intensity == floor(intensity) && abs(intensity) < 1e7
            ctx.lblStatusMouse.Text = sprintf('(%d, %d) = %d', col, row, round(intensity));
        else
            ctx.lblStatusMouse.Text = sprintf('(%d, %d) = %.4g', col, row, intensity);
        end

        if ctx.cbPixelInspector.Value
            ctx.cb.updatePixelInspector(col, row);
        end

    % ────────────────────────────────────────────────────────────────────
    case 'idleDown'
    %ONIDLEMOUSEDOWN  Figure-level mouse-down: resize border or deselect.
        fig = ctx.fig;

        if strcmp(fig.SelectionType, 'alt'), return; end
        if ~isempty(appData.panelResizeDir)
            ctx.cb.startPanelResize();
            return;
        end

        if appData.selectedMeasIdx > 0 || ~isempty(appData.selectedMeasIndices)
            ctx.cb.deselectMeasurement();
        end
        if appData.selectedAnnotIdx > 0 || ~isempty(appData.selectedAnnotIndices)
            for ai = appData.selectedAnnotIndices(:)'
                if ai >= 1 && ai <= numel(appData.overlays.textAnnotations)
                    ctx.cb.highlightAnnotation(appData.overlays.textAnnotations{ai}, false);
                end
            end
            if appData.selectedAnnotIdx > 0 && ...
                    appData.selectedAnnotIdx <= numel(appData.overlays.textAnnotations)
                ctx.cb.highlightAnnotation( ...
                    appData.overlays.textAnnotations{appData.selectedAnnotIdx}, false);
            end
            appData.selectedAnnotIndices = [];
            appData.selectedAnnotIdx = 0;
        end

    % ────────────────────────────────────────────────────────────────────
    case 'axesDown'
    %ONAXESMOUSEDOWN  Image-axes ButtonDownFcn: box-zoom, pan, double-click reset.
        fig = ctx.fig;
        ax  = ctx.ax;

        if ~isempty(appData.captureMode), return; end
        if appData.compareMode, return; end
        if isempty(appData.imgHandle) || ~isvalid(appData.imgHandle), return; end

        selType = fig.SelectionType;
        if strcmp(selType, 'alt'), return; end

        nowTick = tic;
        isDouble = strcmp(selType, 'open');
        if ~isDouble && appData.lastClickTick > 0
            if toc(appData.lastClickTick) < 0.35
                isDouble = true;
            end
        end
        appData.lastClickTick = nowTick;

        if isDouble
            cdata = appData.imgHandle.CData;
            H = size(cdata, 1); W = size(cdata, 2);
            if H > 0 && W > 0
                ax.XLim = [0.5, W + 0.5];
                ax.YLim = [0.5, H + 0.5];
            end
            return;
        end

        wantPan = strcmp(selType, 'extend') || ...
                  (appData.panMode && strcmp(selType, 'normal'));

        cp = ax.CurrentPoint;
        appData.prevMotionFcn = fig.WindowButtonMotionFcn;
        appData.prevUpFcn     = fig.WindowButtonUpFcn;

        if wantPan
            appData.dragAction   = 'pan';
            appData.panStartXY   = cp(1, 1:2);
            appData.panStartLims = struct('XLim', ax.XLim, 'YLim', ax.YLim);
            fig.Pointer = 'hand';
        else
            appData.dragAction   = 'zoomMarquee';
            appData.zoomStartXY  = cp(1, 1:2);
            appData.zoomRect     = [];
        end

        fig.WindowButtonMotionFcn = ctx.cb.onBoxZoomDrag;
        fig.WindowButtonUpFcn     = ctx.cb.onBoxZoomRelease;

    % ────────────────────────────────────────────────────────────────────
    case 'buildContextMenus'
    %BUILDCONTEXTMENUS  Attach right-click menus to image axes, listbox, scale bar.
        fig = ctx.fig;
        ax  = ctx.ax;

        cmImage = uicontextmenu(fig);
        uimenu(cmImage, 'Text', 'Zoom', ...
            'MenuSelectedFcn', @(~,~) ctx.cb.onZoomBox([], []));
        uimenu(cmImage, 'Text', 'Reset Zoom', ...
            'MenuSelectedFcn', @(~,~) ctx.cb.onResetZoom([], []));
        uimenu(cmImage, 'Text', 'Fit to Window', ...
            'MenuSelectedFcn', @(~,~) ctx.cb.onZoomFit([], []));
        uimenu(cmImage, 'Text', 'Zoom 1:1 (Actual Size)', ...
            'MenuSelectedFcn', @(~,~) ctx.cb.onZoomActual([], []));
        uimenu(cmImage, 'Text', 'Zoom Out (2x)', ...
            'MenuSelectedFcn', @(~,~) ctx.cb.onZoomOut([], []));
        uimenu(cmImage, 'Text', 'Zoom to Dimensions...', ...
            'MenuSelectedFcn', @(~,~) ctx.cb.onZoomBox([], [], 'dims'));
        uimenu(cmImage, 'Text', 'Toggle Pan Mode', ...
            'MenuSelectedFcn', @(~,~) ctx.cb.togglePanMode());
        uimenu(cmImage, 'Text', 'Copy to Clipboard', ...
            'Separator', 'on', ...
            'MenuSelectedFcn', @(~,~) ctx.cb.onExportAction('copyClipboard'));
        uimenu(cmImage, 'Text', 'Save Image As...', ...
            'MenuSelectedFcn', @(~,~) ctx.cb.onExportAction('saveImage'));
        uimenu(cmImage, 'Text', 'Toggle Scale Bar', ...
            'Separator', 'on', ...
            'MenuSelectedFcn', @(~,~) ctx.cb.contextToggleScaleBar());
        uimenu(cmImage, 'Text', 'Clear Overlays', ...
            'MenuSelectedFcn', @(~,~) ctx.cb.onClearOverlays([], []));
        appData.cmImage = cmImage;
        if ~isempty(ax) && isvalid(ax)
            ax.ContextMenu = cmImage;
        end
        ctx.cb.attachImageContextMenu();

        cmList = uicontextmenu(fig);
        uimenu(cmList, 'Text', 'Open...', ...
            'MenuSelectedFcn', @(~,~) ctx.cb.onOpenFiles([], []));
        uimenu(cmList, 'Text', 'Rename Selected...', ...
            'MenuSelectedFcn', @(~,~) ctx.cb.onRenameSelected([], []));
        uimenu(cmList, 'Text', 'Remove Selected', ...
            'Separator', 'on', ...
            'MenuSelectedFcn', @(~,~) ctx.cb.onRemoveImage([], []));
        appData.cmList = cmList;
        if ~isempty(ctx.lbImages) && isvalid(ctx.lbImages)
            ctx.lbImages.ContextMenu = cmList;
        end

    % ────────────────────────────────────────────────────────────────────
    case 'buildContextMenu'
    %BUILDCONTEXTMENU  Simple axes context menu (used in secondary views).
        ax  = ctx.ax;
        fig = ctx.fig;
        if isempty(ax) || ~isvalid(ax), return; end
        cm = uicontextmenu(fig);
        uimenu(cm, 'Text', 'Auto Contrast', ...
            'MenuSelectedFcn', @(~,~) ctx.cb.onAutoContrast());
        uimenu(cm, 'Text', 'Copy to Clipboard', ...
            'MenuSelectedFcn', @(~,~) ctx.cb.onExportAction('copyClipboard'));
        uimenu(cm, 'Text', 'Save Image', ...
            'MenuSelectedFcn', @(~,~) ctx.cb.onExportAction('saveImage'));
        uimenu(cm, 'Text', 'Measure Distance', 'Separator', 'on', ...
            'MenuSelectedFcn', @(~,~) ctx.cb.onArmDistance([], []));
        uimenu(cm, 'Text', 'Line Profile', ...
            'MenuSelectedFcn', @(~,~) ctx.cb.onArmLineProfile([], []));
        uimenu(cm, 'Text', 'ROI Statistics', ...
            'MenuSelectedFcn', @(~,~) ctx.cb.onArmROIStats([], []));
        uimenu(cm, 'Text', 'Zoom to Fit', 'Separator', 'on', ...
            'MenuSelectedFcn', @(~,~) ctx.cb.onResetZoom([], []));
        uimenu(cm, 'Text', 'Refresh State (F5)', 'Separator', 'on', ...
            'MenuSelectedFcn', @(~,~) ctx.cb.refreshState());
        ax.ContextMenu = cm;

    % ────────────────────────────────────────────────────────────────────
    otherwise
        error('emViewer:mouseOps:unknownAction', ...
            'Unknown action "%s".', action);

end
end
