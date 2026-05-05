function zoomToDimensions(fig, ax, imgH, imgW, pixelSize, pixelUnit, setStatusFcn)
%ZOOMTODIMENSIONS  Zoom to a user-specified rectangular region.
%
%   emViewer.zoomToDimensions(fig, ax, imgH, imgW, pixelSize, pixelUnit, statusFcn)
%
%   Shows a dialog for width × height, then the user clicks to place a
%   rectangle and can drag to reposition.  Enter confirms the zoom,
%   Escape cancels.

arguments
    fig         (1,1) matlab.ui.Figure
    ax          (1,1) matlab.ui.control.UIAxes
    imgH        (1,1) double
    imgW        (1,1) double
    pixelSize   (1,1) double = NaN
    pixelUnit   (1,:) char   = 'px'
    setStatusFcn function_handle = @(~) []
end

isCalib = ~isnan(pixelSize) && pixelSize > 0;

% ── Phase 1: Dimension input dialog ─────────────────────────────────
if isCalib
    unitStr  = pixelUnit;
    defaultW = diff(ax.XLim) * pixelSize / 2;
    defaultH = diff(ax.YLim) * pixelSize / 2;
else
    unitStr  = 'px';
    defaultW = round(diff(ax.XLim) / 2);
    defaultH = round(diff(ax.YLim) / 2);
end

[dimW, dimH, cancelled] = showDimDialog(fig, defaultW, defaultH, unitStr, isCalib);
if cancelled, return; end

% Convert to pixel units
if isCalib
    wPx = dimW / pixelSize;
    hPx = dimH / pixelSize;
else
    wPx = dimW;
    hPx = dimH;
end

wPx = min(wPx, imgW);
hPx = min(hPx, imgH);
if wPx < 1 || hPx < 1
    setStatusFcn('Zoom dimensions too small.');
    return;
end

% ── Phase 2: Interactive placement ───────────────────────────────────
savedBDF = fig.WindowButtonDownFcn;
savedBMF = fig.WindowButtonMotionFcn;
savedBUF = fig.WindowButtonUpFcn;
savedKPF = fig.WindowKeyPressFcn;
savedPtr = fig.Pointer;

cx = mean(ax.XLim);
cy = mean(ax.YLim);

hRect = rectangle(ax, ...
    'Position', clampRect(cx, cy, wPx, hPx, imgW, imgH), ...
    'EdgeColor', [0 1 0.5], 'LineWidth', 1.5, 'LineStyle', '--', ...
    'HitTest', 'off', 'PickableParts', 'none');

if isCalib
    dimStr = sprintf('%.4g %s %s %.4g %s', dimW, unitStr, char(215), dimH, unitStr);
else
    dimStr = sprintf('%d %s %d px', round(wPx), char(215), round(hPx));
end
hLabel = text(ax, cx, cy - hPx/2 - 5, dimStr, ...
    'Color', [0 1 0.5], 'FontSize', 9, ...
    'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
    'HitTest', 'off', 'PickableParts', 'none');

fig.Pointer = 'crosshair';
setStatusFcn('Click to place region, drag to reposition.  Enter = zoom, Escape = cancel.');

state = 'follow';
dragOffset = [0 0];
confirmed = false;

fig.WindowButtonMotionFcn = @onMotion;
fig.WindowButtonDownFcn   = @onDown;
fig.WindowButtonUpFcn     = @onUp;
fig.WindowKeyPressFcn     = @onKey;

uiwait(fig);

% ── Phase 3: Cleanup ────────────────────────────────────────────────
finalPos = [];
if confirmed && isvalid(hRect)
    finalPos = hRect.Position;
end

if isvalid(hRect), delete(hRect); end
if isvalid(hLabel), delete(hLabel); end

if isvalid(fig)
    fig.WindowButtonDownFcn   = savedBDF;
    fig.WindowButtonMotionFcn = savedBMF;
    fig.WindowButtonUpFcn     = savedBUF;
    fig.WindowKeyPressFcn     = savedKPF;
    fig.Pointer               = savedPtr;
end

if ~isempty(finalPos) && isvalid(ax)
    ax.XLim = [finalPos(1), finalPos(1) + finalPos(3)];
    ax.YLim = [finalPos(2), finalPos(2) + finalPos(4)];
    setStatusFcn(sprintf('Zoomed to %.0f %s %.0f px region.', ...
        finalPos(3), char(215), finalPos(4)));
end

% ── Nested callbacks ─────────────────────────────────────────────────

    function onMotion(~, ~)
        if ~isvalid(ax), return; end
        cp = ax.CurrentPoint;
        mx = cp(1,1); my = cp(1,2);

        switch state
            case 'follow'
                moveRect(mx, my);
            case 'dragging'
                moveRect(mx - dragOffset(1), my - dragOffset(2));
        end
    end

    function onDown(~, ~)
        if ~isvalid(ax), return; end
        cp = ax.CurrentPoint;
        mx = cp(1,1); my = cp(1,2);

        switch state
            case 'follow'
                moveRect(mx, my);
                state = 'placed';
                setStatusFcn('Drag to reposition.  Enter = zoom, Escape = cancel.');

            case 'placed'
                rp = hRect.Position;
                if mx >= rp(1) && mx <= rp(1)+rp(3) && ...
                   my >= rp(2) && my <= rp(2)+rp(4)
                    state = 'dragging';
                    dragOffset = [mx - (rp(1) + rp(3)/2), ...
                                  my - (rp(2) + rp(4)/2)];
                else
                    moveRect(mx, my);
                end
        end
    end

    function onUp(~, ~)
        if strcmp(state, 'dragging')
            state = 'placed';
        end
    end

    function onKey(~, evt)
        if strcmp(evt.Key, 'return')
            confirmed = true;
            if isvalid(fig), uiresume(fig); end
        elseif strcmp(evt.Key, 'escape')
            confirmed = false;
            setStatusFcn('Zoom cancelled.');
            if isvalid(fig), uiresume(fig); end
        end
    end

    function moveRect(cx_, cy_)
        pos = clampRect(cx_, cy_, wPx, hPx, imgW, imgH);
        if isvalid(hRect)
            hRect.Position = pos;
        end
        if isvalid(hLabel)
            hLabel.Position = [pos(1) + pos(3)/2, pos(2) - 3, 0];
        end
    end

end

% ════════════════════════════════════════════════════════════════════════
%  LOCAL FUNCTIONS
% ════════════════════════════════════════════════════════════════════════

function pos = clampRect(cx, cy, w, h, imgW, imgH)
%CLAMPRECT  Rectangle position [x y w h] centred at (cx,cy), clamped.
    x0 = cx - w/2;
    y0 = cy - h/2;
    x0 = max(0.5, min(imgW + 0.5 - w, x0));
    y0 = max(0.5, min(imgH + 0.5 - h, y0));
    pos = [x0, y0, w, h];
end

function [w, h, cancelled] = showDimDialog(parentFig, defaultW, defaultH, unitStr, isCalib)
%SHOWDIMDIALOG  Modal dialog for entering zoom dimensions.

    cancelled = true;
    w = defaultW;
    h = defaultH;

    dlgW = 280; dlgH = 180;
    parentPos = parentFig.Position;
    dlgX = parentPos(1) + (parentPos(3) - dlgW) / 2;
    dlgY = parentPos(2) + (parentPos(4) - dlgH) / 2;

    dlg = uifigure('Name', 'Zoom to Dimensions', ...
        'Position', [dlgX dlgY dlgW dlgH], ...
        'Resize', 'off', ...
        'WindowStyle', 'modal', ...
        'Color', [0.15 0.15 0.15], ...
        'CloseRequestFcn', @(~,~) onDlgCancel());

    gl = uigridlayout(dlg, [5 2], ...
        'RowHeight', {22, 28, 28, 8, 32}, ...
        'ColumnWidth', {'fit', '1x'}, ...
        'Padding', [12 10 12 10], ...
        'RowSpacing', 6);

    lblTitle = uilabel(gl, ...
        'Text', sprintf('Enter dimensions (%s):', unitStr), ...
        'FontColor', [0.85 0.85 0.85], 'FontSize', 11);
    lblTitle.Layout.Row = 1; lblTitle.Layout.Column = [1 2];

    lblW = uilabel(gl, 'Text', 'Width:', ...
        'FontColor', [0.75 0.75 0.75], 'FontSize', 11, ...
        'HorizontalAlignment', 'right');
    lblW.Layout.Row = 2; lblW.Layout.Column = 1;

    if isCalib
        efW = uieditfield(gl, 'numeric', 'Value', defaultW, ...
            'ValueDisplayFormat', '%.4g', 'Limits', [0.001 Inf], ...
            'BackgroundColor', [0.22 0.22 0.22], ...
            'FontColor', [0.95 0.95 0.95]);
    else
        efW = uieditfield(gl, 'numeric', 'Value', defaultW, ...
            'ValueDisplayFormat', '%.0f', ...
            'Limits', [1 Inf], 'RoundFractionalValues', 'on', ...
            'BackgroundColor', [0.22 0.22 0.22], ...
            'FontColor', [0.95 0.95 0.95]);
    end
    efW.Layout.Row = 2; efW.Layout.Column = 2;

    lblH = uilabel(gl, 'Text', 'Height:', ...
        'FontColor', [0.75 0.75 0.75], 'FontSize', 11, ...
        'HorizontalAlignment', 'right');
    lblH.Layout.Row = 3; lblH.Layout.Column = 1;

    if isCalib
        efH = uieditfield(gl, 'numeric', 'Value', defaultH, ...
            'ValueDisplayFormat', '%.4g', 'Limits', [0.001 Inf], ...
            'BackgroundColor', [0.22 0.22 0.22], ...
            'FontColor', [0.95 0.95 0.95]);
    else
        efH = uieditfield(gl, 'numeric', 'Value', defaultH, ...
            'ValueDisplayFormat', '%.0f', ...
            'Limits', [1 Inf], 'RoundFractionalValues', 'on', ...
            'BackgroundColor', [0.22 0.22 0.22], ...
            'FontColor', [0.95 0.95 0.95]);
    end
    efH.Layout.Row = 3; efH.Layout.Column = 2;

    btnGL = uigridlayout(gl, [1 2], ...
        'ColumnWidth', {'1x', '1x'}, ...
        'Padding', [0 0 0 0], ...
        'ColumnSpacing', 8);
    btnGL.Layout.Row = 5; btnGL.Layout.Column = [1 2];

    btnCancel = uibutton(btnGL, 'Text', 'Cancel', ...
        'FontSize', 11, 'BackgroundColor', [0.35 0.22 0.22], ...
        'FontColor', [1 1 1], ...
        'ButtonPushedFcn', @(~,~) onDlgCancel());
    btnCancel.Layout.Column = 1;

    btnOK = uibutton(btnGL, 'Text', 'OK', ...
        'FontSize', 11, 'BackgroundColor', [0.18 0.38 0.18], ...
        'FontColor', [1 1 1], ...
        'ButtonPushedFcn', @(~,~) onDlgOK());
    btnOK.Layout.Column = 2;

    dlg.WindowKeyPressFcn = @(~,evt) onDlgKey(evt);

    uiwait(dlg);

    function onDlgOK()
        w = efW.Value;
        h = efH.Value;
        cancelled = false;
        if isvalid(dlg), uiresume(dlg); delete(dlg); end
    end

    function onDlgCancel()
        if isvalid(dlg), uiresume(dlg); delete(dlg); end
    end

    function onDlgKey(evt)
        if strcmp(evt.Key, 'return'),    onDlgOK();     end
        if strcmp(evt.Key, 'escape'),    onDlgCancel(); end
    end

end
