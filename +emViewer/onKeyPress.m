function onKeyPress(evt, ax, axL, axR, appData, callbacks)
%ONKEYPRESS  Keyboard shortcut dispatcher for FermiViewer.
%
%   Syntax
%   ------
%   emViewer.onKeyPress(evt, ax, axL, axR, appData, callbacks)
%
%   Inputs
%   ------
%   evt       - KeyData event struct (from WindowKeyPressFcn)
%   ax        - Main UIAxes (single-image mode)
%   axL       - Left compare UIAxes (may be empty)
%   axR       - Right compare UIAxes (may be empty)
%   appData   - Plain struct snapshot of application state.  Read-only;
%               stateful mutations are routed through callbacks.
%               Required fields:
%                 .captureMode         char — '' when idle
%                 .selectedAnnotIdx    double
%                 .selectedMeasIdx     double
%                 .images              cell
%                 .compareMode         logical
%                 .compareActivePanel  char ('L' or 'R')
%                 .compareIdxL         double
%                 .compareIdxR         double
%                 .activeIdx           double
%                 .rawPixels           array (may be empty)
%                 .panMode             logical
%   callbacks - Struct of function handles for all side-effecting
%               operations.  Required fields:
%                 .cancelCapture           @()
%                 .setStatus               @(msg)
%                 .onAnnotationAction      @(action) or @(action, idx)
%                 .deleteSelectedMeasurement @()
%                 .updateCompareHighlight  @()
%                 .syncCompareZoom         @(src, dst)
%                 .displayCompareImage     @(side)    — 'L' or 'R'
%                 .setComparePanelToggle   @()        — toggles panel + displayCompareImage
%                 .setCompareIdxL          @(idx)     — writes compareIdxL + displayCompareImage
%                 .setCompareIdxR          @(idx)     — writes compareIdxR + displayCompareImage
%                 .onSessionSave           @(src, evt)
%                 .onSessionLoad           @(src, evt)
%                 .onOpenFiles             @(src, evt)
%                 .onExportAction          @(action)
%                 .onUndoFilters           @(src, evt)
%                 .refreshState            @()
%                 .onAutoContrast          @(src, evt)
%                 .onZoomFit               @(src, evt)
%                 .onZoomBox               @(src, evt, mode)
%                 .onDragModeToggle        @(src, evt, kind)
%                 .setActiveIdxAPI         @(idx)
%
%   Examples
%   --------
%   % Called from the thin wrapper in FermiViewer.m:
%   function onKeyPress(~, evt)
%       cb = struct('setStatus', @setStatus, ...);
%       emViewer.onKeyPress(evt, ax, axL, axR, appData, cb);
%   end

% ════════════════════════════════════════════════════════════════════
%  ESCAPE — cancel capture or deselect annotation
% ════════════════════════════════════════════════════════════════════
if strcmp(evt.Key, 'escape')
    if ~isempty(appData.captureMode)
        callbacks.cancelCapture();
        callbacks.setStatus('Capture cancelled.');
    elseif appData.selectedAnnotIdx > 0
        callbacks.onAnnotationAction('deselect');
        callbacks.setStatus('Annotation deselected.');
    end
    return;
end

% ════════════════════════════════════════════════════════════════════
%  DELETE / BACKSPACE — remove selected object or undo last annotation
% ════════════════════════════════════════════════════════════════════
if (strcmp(evt.Key, 'delete') || strcmp(evt.Key, 'backspace')) ...
        && isempty(appData.captureMode)
    if appData.selectedMeasIdx > 0
        callbacks.deleteSelectedMeasurement();
    elseif appData.selectedAnnotIdx > 0
        callbacks.onAnnotationAction('deleteOne', appData.selectedAnnotIdx);
    else
        callbacks.onAnnotationAction('undoLast');
    end
    return;
end

% Block navigation during capture
if ~isempty(appData.captureMode)
    return;
end

nImages = numel(appData.images);

% ════════════════════════════════════════════════════════════════════
%  COMPARE MODE
% ════════════════════════════════════════════════════════════════════
if appData.compareMode
    % Tab → switch active panel
    if strcmp(evt.Key, 'tab')
        callbacks.setComparePanelToggle();   % mutates compareActivePanel
        return;
    end

    % +/= → zoom in on active panel, sync to other
    if strcmp(evt.Key, 'equal') || strcmp(evt.Key, 'add')
        if appData.compareActivePanel == 'L' && ~isempty(axL) && isvalid(axL)
            cx = mean(axL.XLim); cy = mean(axL.YLim);
            hw = diff(axL.XLim) / 4; hh = diff(axL.YLim) / 4;
            axL.XLim = [cx - hw, cx + hw];
            axL.YLim = [cy - hh, cy + hh];
            callbacks.syncCompareZoom(axL, axR);
        elseif ~isempty(axR) && isvalid(axR)
            cx = mean(axR.XLim); cy = mean(axR.YLim);
            hw = diff(axR.XLim) / 4; hh = diff(axR.YLim) / 4;
            axR.XLim = [cx - hw, cx + hw];
            axR.YLim = [cy - hh, cy + hh];
            callbacks.syncCompareZoom(axR, axL);
        end
        return;
    end

    % - → zoom out on active panel, sync to other
    if strcmp(evt.Key, 'hyphen') || strcmp(evt.Key, 'subtract')
        if appData.compareActivePanel == 'L' && ~isempty(axL) && isvalid(axL)
            cx = mean(axL.XLim); cy = mean(axL.YLim);
            hw = diff(axL.XLim); hh = diff(axL.YLim);
            axL.XLim = [cx - hw, cx + hw];
            axL.YLim = [cy - hh, cy + hh];
            callbacks.syncCompareZoom(axL, axR);
        elseif ~isempty(axR) && isvalid(axR)
            cx = mean(axR.XLim); cy = mean(axR.YLim);
            hw = diff(axR.XLim); hh = diff(axR.YLim);
            axR.XLim = [cx - hw, cx + hw];
            axR.YLim = [cy - hh, cy + hh];
            callbacks.syncCompareZoom(axR, axL);
        end
        return;
    end

    % F → fit both panels
    if strcmp(evt.Key, 'f')
        if ~isempty(axL) && isvalid(axL)
            cdata = axL.Children;
            if ~isempty(cdata)
                axL.XLim = [0.5, size(cdata(1).CData, 2) + 0.5];
                axL.YLim = [0.5, size(cdata(1).CData, 1) + 0.5];
            end
        end
        if ~isempty(axR) && isvalid(axR)
            cdata = axR.Children;
            if ~isempty(cdata)
                axR.XLim = [0.5, size(cdata(1).CData, 2) + 0.5];
                axR.YLim = [0.5, size(cdata(1).CData, 1) + 0.5];
            end
        end
        return;
    end

    if nImages < 2, return; end

    % Left/Right arrows → scroll images in active panel
    delta = 0;
    if strcmp(evt.Key, 'rightarrow'), delta =  1; end
    if strcmp(evt.Key, 'leftarrow'),  delta = -1; end
    if delta == 0, return; end

    if appData.compareActivePanel == 'L'
        newIdx = appData.compareIdxL + delta;
        if newIdx < 1,       newIdx = nImages; end
        if newIdx > nImages, newIdx = 1;       end
        callbacks.setCompareIdxL(newIdx);   % mutates compareIdxL + calls displayCompareImage
    else
        newIdx = appData.compareIdxR + delta;
        if newIdx < 1,       newIdx = nImages; end
        if newIdx > nImages, newIdx = 1;       end
        callbacks.setCompareIdxR(newIdx);   % mutates compareIdxR + calls displayCompareImage
    end
    return;
end

% ════════════════════════════════════════════════════════════════════
%  SINGLE-IMAGE MODE — modifier detection
% ════════════════════════════════════════════════════════════════════
hasMod   = ~isempty(evt.Modifier);
hasCtrl  = hasMod && any(strcmp(evt.Modifier, 'control'));
hasShift = hasMod && any(strcmp(evt.Modifier, 'shift'));

% Ctrl+Shift+S → Session save (must precede Ctrl+S check)
if hasCtrl && hasShift && strcmp(evt.Key, 's')
    callbacks.onSessionSave([], []);
    return;
end
% Ctrl+Shift+L → Session load
if hasCtrl && hasShift && strcmp(evt.Key, 'l')
    callbacks.onSessionLoad([], []);
    return;
end
% Ctrl+O → Open files
if hasCtrl && strcmp(evt.Key, 'o')
    callbacks.onOpenFiles([], []);
    return;
end
% Ctrl+S → Save image
if hasCtrl && strcmp(evt.Key, 's')
    callbacks.onExportAction('saveImage');
    return;
end
% Ctrl+Z → Undo filters
if hasCtrl && strcmp(evt.Key, 'z')
    callbacks.onUndoFilters([], []);
    return;
end

% F5 → Refresh state
if strcmp(evt.Key, 'f5')
    callbacks.refreshState();
    return;
end

% ── No-modifier shortcuts ────────────────────────────────────────────
if ~hasMod
    % A → Auto contrast
    if strcmp(evt.Key, 'a')
        callbacks.onAutoContrast([], []);
        return;
    end
    % F → Fit to window
    if strcmp(evt.Key, 'f')
        callbacks.onZoomFit([], []);
        return;
    end
    % +/= → Zoom in (2x)
    if strcmp(evt.Key, 'equal') || strcmp(evt.Key, 'add')
        if appData.activeIdx >= 1 && ~isempty(appData.rawPixels)
            cx = mean(ax.XLim);
            cy = mean(ax.YLim);
            hw = diff(ax.XLim) / 4;
            hh = diff(ax.YLim) / 4;
            ax.XLim = [cx - hw, cx + hw];
            ax.YLim = [cy - hh, cy + hh];
        end
        return;
    end
    % - → Zoom out (2x)
    if strcmp(evt.Key, 'hyphen') || strcmp(evt.Key, 'subtract')
        if appData.activeIdx >= 1 && ~isempty(appData.rawPixels)
            cx = mean(ax.XLim);
            cy = mean(ax.YLim);
            hw = diff(ax.XLim);
            hh = diff(ax.YLim);
            ax.XLim = [cx - hw, cx + hw];
            ax.YLim = [cy - hh, cy + hh];
        end
        return;
    end
    % D → Zoom to dimensions
    if strcmp(evt.Key, 'd')
        callbacks.onZoomBox([], [], 'dims');
        return;
    end
    % P → Toggle pan mode
    if strcmp(evt.Key, 'p')
        callbacks.onDragModeToggle(struct('Value', ~appData.panMode), [], 'pan');
        return;
    end
end

% ════════════════════════════════════════════════════════════════════
%  Normal mode: left/right arrows cycle through images
% ════════════════════════════════════════════════════════════════════
if nImages < 2, return; end

if strcmp(evt.Key, 'rightarrow')
    newIdx = appData.activeIdx + 1;
    if newIdx > nImages, newIdx = 1; end
    callbacks.setActiveIdxAPI(newIdx);
elseif strcmp(evt.Key, 'leftarrow')
    newIdx = appData.activeIdx - 1;
    if newIdx < 1, newIdx = nImages; end
    callbacks.setActiveIdxAPI(newIdx);
end

end
