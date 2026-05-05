function zoomToDimensions(fig, ax, imgH, imgW, pixelSize, pixelUnit, setStatusFcn)
%ZOOMTODIMENSIONS  Zoom to a fixed-size or fixed-ratio rectangular region.
%
%   emViewer.zoomToDimensions(fig, ax, imgH, imgW, pixelSize, pixelUnit, statusFcn)
%
%   Opens a dialog where the user picks Fixed Size (W×H) or Aspect Ratio
%   (e.g. 4:3).  A live preview rectangle is drawn on the image while the
%   dialog is open.  After OK the user clicks to place the rectangle, drags
%   to reposition, and presses Enter to zoom (Escape to cancel).  In Aspect
%   Ratio mode the scroll wheel resizes the box while keeping the ratio.

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
if isCalib
    unitStr = pixelUnit;
else
    unitStr = 'px';
end

% Default dimensions: half the current view
defaultWPx = diff(ax.XLim) / 2;
defaultHPx = diff(ax.YLim) / 2;

% ── Create preview rectangle (visible behind dialog) ────────────────
cx = mean(ax.XLim);
cy = mean(ax.YLim);

wPx = defaultWPx;
hPx = defaultHPx;

hRect = rectangle(ax, ...
    'Position', clampRect(cx, cy, wPx, hPx, imgW, imgH), ...
    'EdgeColor', [0 1 0.5], 'LineWidth', 1.5, 'LineStyle', '--', ...
    'HitTest', 'off', 'PickableParts', 'none');

hLabel = text(ax, cx, cy - hPx/2 - 5, '', ...
    'Color', [0 1 0.5], 'FontSize', 9, ...
    'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
    'HitTest', 'off', 'PickableParts', 'none');

updateLabel();

% ── Phase 1: Dimension / ratio dialog ───────────────────────────────
mode       = 'size';   % 'size' | 'ratio'
ratioW     = 4;
ratioH     = 3;
cancelled  = true;

showDimDialog();

if cancelled
    if isvalid(hRect), delete(hRect); end
    if isvalid(hLabel), delete(hLabel); end
    return;
end

if wPx < 1 || hPx < 1
    if isvalid(hRect), delete(hRect); end
    if isvalid(hLabel), delete(hLabel); end
    setStatusFcn('Zoom dimensions too small.');
    return;
end

% ── Phase 2: Interactive placement ──────────────────────────────────
savedBDF = fig.WindowButtonDownFcn;
savedBMF = fig.WindowButtonMotionFcn;
savedBUF = fig.WindowButtonUpFcn;
savedKPF = fig.WindowKeyPressFcn;
savedSWF = fig.WindowScrollWheelFcn;
savedPtr = fig.Pointer;

fig.Pointer = 'crosshair';
if strcmp(mode, 'ratio')
    setStatusFcn('Click to place.  Scroll to resize.  Enter = zoom, Escape = cancel.');
else
    setStatusFcn('Click to place, drag to reposition.  Enter = zoom, Escape = cancel.');
end

state = 'follow';
dragOffset = [0 0];
confirmed = false;

fig.WindowButtonMotionFcn = @onMotion;
fig.WindowButtonDownFcn   = @onDown;
fig.WindowButtonUpFcn     = @onUp;
fig.WindowKeyPressFcn     = @onKey;
fig.WindowScrollWheelFcn  = @onScroll;

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
    fig.WindowScrollWheelFcn  = savedSWF;
    fig.Pointer               = savedPtr;
end

if ~isempty(finalPos) && isvalid(ax)
    ax.XLim = [finalPos(1), finalPos(1) + finalPos(3)];
    ax.YLim = [finalPos(2), finalPos(2) + finalPos(4)];
    setStatusFcn(sprintf('Zoomed to %.0f %s %.0f px region.', ...
        finalPos(3), char(215), finalPos(4)));
end

% ════════════════════════════════════════════════════════════════════════
%  NESTED HELPERS — placement interaction
% ════════════════════════════════════════════════════════════════════════

    function onMotion(~, ~)
        if ~isvalid(ax), return; end
        cp = ax.CurrentPoint;
        mx = cp(1,1); my = cp(1,2);
        switch state
            case 'follow',   moveRect(mx, my);
            case 'dragging', moveRect(mx - dragOffset(1), my - dragOffset(2));
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
                if strcmp(mode, 'ratio')
                    setStatusFcn('Drag to reposition.  Scroll to resize.  Enter = zoom, Escape = cancel.');
                else
                    setStatusFcn('Drag to reposition.  Enter = zoom, Escape = cancel.');
                end
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
        if strcmp(state, 'dragging'), state = 'placed'; end
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

    function onScroll(~, evt)
        if strcmp(mode, 'size'), return; end
        factor = 1.15 ^ (-evt.VerticalScrollCount);
        newW = wPx * factor;
        newH = hPx * factor;
        newW = max(2, min(imgW, newW));
        newH = max(2, min(imgH, newH));
        % Re-derive from the ratio to avoid drift
        if newW / ratioW * ratioH > imgH
            newH = imgH;
            newW = newH * ratioW / ratioH;
        end
        if newH / ratioH * ratioW > imgW
            newW = imgW;
            newH = newW * ratioH / ratioW;
        end
        wPx = newW;
        hPx = newH;
        rp = hRect.Position;
        rcx = rp(1) + rp(3)/2;
        rcy = rp(2) + rp(4)/2;
        moveRect(rcx, rcy);
        updateLabel();
    end

    function moveRect(cx_, cy_)
        pos = clampRect(cx_, cy_, wPx, hPx, imgW, imgH);
        if isvalid(hRect), hRect.Position = pos; end
        if isvalid(hLabel)
            hLabel.Position = [pos(1) + pos(3)/2, pos(2) - 3, 0];
        end
    end

    function updateLabel()
        if isCalib
            wU = wPx * pixelSize;
            hU = hPx * pixelSize;
            str = sprintf('%.4g %s %.4g %s', wU, char(215), hU, unitStr);
        else
            str = sprintf('%d %s %d px', round(wPx), char(215), round(hPx));
        end
        if strcmp(mode, 'ratio')
            str = sprintf('%s  (%d:%d)', str, ratioW, ratioH);
        end
        if isvalid(hLabel), hLabel.String = str; end
    end

% ════════════════════════════════════════════════════════════════════════
%  NESTED HELPER — dialog
% ════════════════════════════════════════════════════════════════════════

    function showDimDialog()

        if isCalib
            defW = defaultWPx * pixelSize;
            defH = defaultHPx * pixelSize;
        else
            defW = round(defaultWPx);
            defH = round(defaultHPx);
        end

        dlgW = 300; dlgH = 220;
        parentPos = fig.Position;
        dlgX = parentPos(1) + (parentPos(3) - dlgW) / 2;
        dlgY = parentPos(2) + (parentPos(4) - dlgH) / 2;

        dlg = uifigure('Name', 'Zoom to Dimensions', ...
            'Position', [dlgX dlgY dlgW dlgH], ...
            'Resize', 'off', ...
            'WindowStyle', 'modal', ...
            'Color', [0.15 0.15 0.15], ...
            'CloseRequestFcn', @(~,~) onDlgCancel());

        gl = uigridlayout(dlg, [6 2], ...
            'RowHeight', {28, 22, 28, 28, 8, 32}, ...
            'ColumnWidth', {'fit', '1x'}, ...
            'Padding', [12 10 12 10], ...
            'RowSpacing', 6);

        % ── Row 1: Mode dropdown ─────────────────────────────────────
        lblMode = uilabel(gl, 'Text', 'Mode:', ...
            'FontColor', [0.75 0.75 0.75], 'FontSize', 11, ...
            'HorizontalAlignment', 'right');
        lblMode.Layout.Row = 1; lblMode.Layout.Column = 1;

        ddMode = uidropdown(gl, ...
            'Items', {'Fixed Size', 'Aspect Ratio'}, ...
            'Value', 'Fixed Size', ...
            'BackgroundColor', [0.22 0.22 0.22], ...
            'FontColor', [0.95 0.95 0.95], ...
            'ValueChangedFcn', @(~,~) onModeChange());
        ddMode.Layout.Row = 1; ddMode.Layout.Column = 2;

        % ── Row 2: Unit label ────────────────────────────────────────
        lblUnit = uilabel(gl, ...
            'Text', sprintf('Dimensions (%s):', unitStr), ...
            'FontColor', [0.65 0.65 0.65], 'FontSize', 10);
        lblUnit.Layout.Row = 2; lblUnit.Layout.Column = [1 2];

        % ── Row 3: Width / Ratio W ───────────────────────────────────
        lblW = uilabel(gl, 'Text', 'Width:', ...
            'FontColor', [0.75 0.75 0.75], 'FontSize', 11, ...
            'HorizontalAlignment', 'right');
        lblW.Layout.Row = 3; lblW.Layout.Column = 1;

        if isCalib
            efW = uieditfield(gl, 'numeric', 'Value', defW, ...
                'ValueDisplayFormat', '%.4g', 'Limits', [0.001 Inf], ...
                'BackgroundColor', [0.22 0.22 0.22], ...
                'FontColor', [0.95 0.95 0.95], ...
                'ValueChangedFcn', @(~,~) onValueChange());
        else
            efW = uieditfield(gl, 'numeric', 'Value', defW, ...
                'ValueDisplayFormat', '%.0f', ...
                'Limits', [1 Inf], 'RoundFractionalValues', 'on', ...
                'BackgroundColor', [0.22 0.22 0.22], ...
                'FontColor', [0.95 0.95 0.95], ...
                'ValueChangedFcn', @(~,~) onValueChange());
        end
        efW.Layout.Row = 3; efW.Layout.Column = 2;

        % ── Row 4: Height / Ratio H ──────────────────────────────────
        lblH = uilabel(gl, 'Text', 'Height:', ...
            'FontColor', [0.75 0.75 0.75], 'FontSize', 11, ...
            'HorizontalAlignment', 'right');
        lblH.Layout.Row = 4; lblH.Layout.Column = 1;

        if isCalib
            efH = uieditfield(gl, 'numeric', 'Value', defH, ...
                'ValueDisplayFormat', '%.4g', 'Limits', [0.001 Inf], ...
                'BackgroundColor', [0.22 0.22 0.22], ...
                'FontColor', [0.95 0.95 0.95], ...
                'ValueChangedFcn', @(~,~) onValueChange());
        else
            efH = uieditfield(gl, 'numeric', 'Value', defH, ...
                'ValueDisplayFormat', '%.0f', ...
                'Limits', [1 Inf], 'RoundFractionalValues', 'on', ...
                'BackgroundColor', [0.22 0.22 0.22], ...
                'FontColor', [0.95 0.95 0.95], ...
                'ValueChangedFcn', @(~,~) onValueChange());
        end
        efH.Layout.Row = 4; efH.Layout.Column = 2;

        % ── Row 6: Buttons ───────────────────────────────────────────
        btnGL = uigridlayout(gl, [1 2], ...
            'ColumnWidth', {'1x', '1x'}, ...
            'Padding', [0 0 0 0], ...
            'ColumnSpacing', 8);
        btnGL.Layout.Row = 6; btnGL.Layout.Column = [1 2];

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

        % ── Dialog callbacks ─────────────────────────────────────────

        function onModeChange()
            if strcmp(ddMode.Value, 'Fixed Size')
                mode = 'size';
                lblW.Text = 'Width:';
                lblH.Text = 'Height:';
                lblUnit.Text = sprintf('Dimensions (%s):', unitStr);
                if isCalib
                    efW.Value = wPx * pixelSize;
                    efH.Value = hPx * pixelSize;
                    efW.Limits = [0.001 Inf];
                    efH.Limits = [0.001 Inf];
                    efW.RoundFractionalValues = 'off';
                    efH.RoundFractionalValues = 'off';
                    efW.ValueDisplayFormat = '%.4g';
                    efH.ValueDisplayFormat = '%.4g';
                else
                    efW.Value = round(wPx);
                    efH.Value = round(hPx);
                    efW.Limits = [1 Inf];
                    efH.Limits = [1 Inf];
                    efW.RoundFractionalValues = 'on';
                    efH.RoundFractionalValues = 'on';
                end
            else
                mode = 'ratio';
                lblW.Text = 'W Ratio:';
                lblH.Text = 'H Ratio:';
                lblUnit.Text = 'Aspect ratio (scroll to resize after placing):';
                efW.Value = ratioW;
                efH.Value = ratioH;
                efW.Limits = [1 Inf];
                efH.Limits = [1 Inf];
                efW.RoundFractionalValues = 'on';
                efH.RoundFractionalValues = 'on';
                efW.ValueDisplayFormat = '%.0f';
                efH.ValueDisplayFormat = '%.0f';
            end
            onValueChange();
        end

        function onValueChange()
            if strcmp(mode, 'size')
                if isCalib
                    wPx = max(1, min(imgW, efW.Value / pixelSize));
                    hPx = max(1, min(imgH, efH.Value / pixelSize));
                else
                    wPx = max(1, min(imgW, efW.Value));
                    hPx = max(1, min(imgH, efH.Value));
                end
            else
                ratioW = max(1, round(efW.Value));
                ratioH = max(1, round(efH.Value));
                viewW = diff(ax.XLim) * 0.6;
                viewH = diff(ax.YLim) * 0.6;
                if viewW / ratioW * ratioH <= viewH
                    wPx = viewW;
                    hPx = viewW * ratioH / ratioW;
                else
                    hPx = viewH;
                    wPx = viewH * ratioW / ratioH;
                end
                wPx = max(2, min(imgW, wPx));
                hPx = max(2, min(imgH, hPx));
            end
            % Update preview rectangle
            rp = hRect.Position;
            rcx = rp(1) + rp(3)/2;
            rcy = rp(2) + rp(4)/2;
            moveRect(rcx, rcy);
            updateLabel();
        end

        function onDlgOK()
            if strcmp(mode, 'size')
                if isCalib
                    wPx = max(1, min(imgW, efW.Value / pixelSize));
                    hPx = max(1, min(imgH, efH.Value / pixelSize));
                else
                    wPx = max(1, min(imgW, efW.Value));
                    hPx = max(1, min(imgH, efH.Value));
                end
            else
                ratioW = max(1, round(efW.Value));
                ratioH = max(1, round(efH.Value));
            end
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

end

% ════════════════════════════════════════════════════════════════════════
%  LOCAL FUNCTION
% ════════════════════════════════════════════════════════════════════════

function pos = clampRect(cx, cy, w, h, imgW, imgH)
    x0 = cx - w/2;
    y0 = cy - h/2;
    x0 = max(0.5, min(imgW + 0.5 - w, x0));
    y0 = max(0.5, min(imgH + 0.5 - h, y0));
    pos = [x0, y0, w, h];
end
