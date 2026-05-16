function varargout = scaleBarOps(action, appData, ctx, varargin)
%SCALEBAROPS  Scale bar operations for FermiViewer.
%
% Syntax:
%   appData = emViewer.scaleBarOps('rebuild',     appData, ctx)
%   appData = emViewer.scaleBarOps('startDrag',   appData, ctx, sb, dragAx)
%   appData = emViewer.scaleBarOps('calibrate',   appData, ctx, x1,y1,x2,y2)
%   appData = emViewer.scaleBarOps('autoDetect',  appData, ctx)
%
% Inputs:
%   action   — string identifying the operation
%   appData  — FermiViewer appData struct (returned modified)
%   ctx      — context struct with fields:
%                .ax          — primary axes handle
%                .axL, .axR   — compare-mode axes (may be empty)
%                .fig         — figure handle
%                .ui          — struct of widget handles:
%                    .spnScaleBarFont, .efScaleBarLen, .ddScaleBarUnit,
%                    .cbScaleBar
%                .cb          — struct of callback function handles:
%                    .deleteScaleBar, .makeScaleBarDraggable,
%                    .applyCalibration, .setStatus
%
% Examples:
%   ctx = buildMeasCtx();
%   appData = emViewer.scaleBarOps('rebuild', appData, ctx);
%   appData = emViewer.scaleBarOps('startDrag', appData, ctx, hBar, ax);
%   appData = emViewer.scaleBarOps('calibrate', appData, ctx, x1, y1, x2, y2);
%   appData = emViewer.scaleBarOps('autoDetect', appData, ctx);

% ════════════════════════════════════════════════════════════════════
switch lower(strtrim(action))
    case 'rebuild'
        appData = doRebuildScaleBar(appData, ctx);
        varargout{1} = appData;

    case 'startdrag'
        [sb, dragAx] = deal(varargin{1:2});
        doStartScaleBarDrag(ctx.fig, sb, dragAx);
        varargout{1} = appData;

    case 'calibrate'
        [x1, y1, x2, y2] = deal(varargin{1:4});
        appData = doExecuteScaleBarCalibration(appData, ctx, x1, y1, x2, y2);
        varargout{1} = appData;

    case 'autodetect'
        appData = doAutoDetectScaleBar(appData, ctx);
        varargout{1} = appData;

    otherwise
        error('emViewer:scaleBarOps:unknownAction', ...
            'Unknown action: ''%s''', action);
end
end

% ════════════════════════════════════════════════════════════════════
%  rebuildScaleBar — Delete and recreate with current settings
% ════════════════════════════════════════════════════════════════════
function appData = doRebuildScaleBar(appData, ctx)
    % Snapshot existing bar/label positions BEFORE delete so that user
    % drag offsets survive a property change (color, font, length, unit).
    snapSingle = emViewer.snapScaleBarPos(appData.overlays.scalebar);
    snapL      = emViewer.snapScaleBarPos(appData.overlays.scalebarL);
    snapR      = emViewer.snapScaleBarPos(appData.overlays.scalebarR);

    ctx.cb.deleteScaleBar();
    appData.overlays.scalebar  = [];
    appData.overlays.scalebarL = [];
    appData.overlays.scalebarR = [];

    % Read RGB directly from SSoT
    barColor = appData.scaleBarColor;
    fontSize = ctx.ui.spnScaleBarFont.Value;

    % Length override: editfield value > 0 with a non-auto unit
    lenVal  = ctx.ui.efScaleBarLen.Value;
    unitVal = ctx.ui.ddScaleBarUnit.Value;
    useLen  = lenVal > 0 && isfinite(lenVal) && ~strcmp(unitVal, 'auto');
    if useLen
        lenArgs = {'BarLength', lenVal, 'BarUnit', string(unitVal)};
    else
        lenArgs = {};
    end

    if appData.compareMode
        % Add scale bars to both compare axes
        for panelChar = ['L', 'R']
            if panelChar == 'L'
                tgtAx = ctx.axL;  idx = appData.compareIdxL;  prevSnap = snapL;
            else
                tgtAx = ctx.axR;  idx = appData.compareIdxR;  prevSnap = snapR;
            end
            if isempty(tgtAx) || ~isvalid(tgtAx), continue; end
            if idx < 1 || idx > numel(appData.images), continue; end
            imgI = appData.images{idx}.metadata.parserSpecific.imageData;
            if ~imgI.calibrated, continue; end
            hB = imaging.addScaleBar(tgtAx, imgI.pixelSize, imgI.pixelUnit, ...
                'Color', barColor, 'FontSize', fontSize, lenArgs{:});
            emViewer.applyScaleBarPos(hB, prevSnap);
            ctx.cb.makeScaleBarDraggable(hB);
            if panelChar == 'L'
                appData.overlays.scalebarL = hB;
            else
                appData.overlays.scalebarR = hB;
            end
        end
    else
        if appData.activeIdx < 1, return; end
        imgInfo = appData.images{appData.activeIdx}.metadata.parserSpecific.imageData;
        hBar = imaging.addScaleBar(ctx.ax, imgInfo.pixelSize, imgInfo.pixelUnit, ...
            'Color', barColor, 'FontSize', fontSize, lenArgs{:});
        emViewer.applyScaleBarPos(hBar, snapSingle);
        appData.overlays.scalebar = hBar;
        ctx.cb.makeScaleBarDraggable(hBar);
    end
end

% ════════════════════════════════════════════════════════════════════
%  startScaleBarDrag — Handle scale bar dragging
% ════════════════════════════════════════════════════════════════════
function doStartScaleBarDrag(fig, sb, dragAx)
    if isempty(sb) || ~isstruct(sb), return; end
    if isempty(dragAx) || ~isvalid(dragAx), return; end

    % Current bar position: [x y w h]
    barPos  = sb.bar.Position;
    labelPt = [sb.label.Position(1), sb.label.Position(2)];

    % Get click location in data coords
    cp = dragAx.CurrentPoint;
    startX = cp(1,1);
    startY = cp(1,2);

    % Store original callbacks to restore on release
    origMotionFcn  = fig.WindowButtonMotionFcn;
    origReleaseFcn = fig.WindowButtonUpFcn;

    fig.WindowButtonMotionFcn = @dragMotion;
    fig.WindowButtonUpFcn    = @dragRelease;

    function dragMotion(~, ~)
        cp2 = dragAx.CurrentPoint;
        dx = cp2(1,1) - startX;
        dy = cp2(1,2) - startY;

        % Move rectangle
        sb.bar.Position(1) = barPos(1) + dx;
        sb.bar.Position(2) = barPos(2) + dy;

        % Move label
        sb.label.Position = [labelPt(1) + dx, labelPt(2) + dy, 0];
    end

    function dragRelease(~, ~)
        fig.WindowButtonMotionFcn = origMotionFcn;
        fig.WindowButtonUpFcn    = origReleaseFcn;
    end
end

% ════════════════════════════════════════════════════════════════════
%  executeScaleBarCalibration — Calibrate from known distance
% ════════════════════════════════════════════════════════════════════
function appData = doExecuteScaleBarCalibration(appData, ctx, x1, y1, x2, y2)
    % Draw overlay line where user clicked
    hLine = line(ctx.ax, [x1 x2], [y1 y2], ...
        'Color', [0 1 1], 'LineWidth', 2, 'LineStyle', '--', ...
        'HandleVisibility', 'off');

    % Compute pixel distance
    pxDist = sqrt((x2 - x1)^2 + (y2 - y1)^2);

    % Clean up click markers
    for ci = 1:numel(appData.overlays.clickMarkers)
        h = appData.overlays.clickMarkers{ci};
        if isvalid(h), delete(h); end
    end
    appData.overlays.clickMarkers = {};

    % Prompt for real distance with unit dropdown
    [realDist, realUnit, cancelled] = emViewer.calibration.promptScaleBarDistance(pxDist);

    % Remove overlay line
    if isvalid(hLine), delete(hLine); end

    if cancelled, return; end

    % Compute pixel size = realDist / pxDist
    newPixelSize = realDist / pxDist;

    appData = ctx.cb.applyCalibration(appData, newPixelSize, realUnit);
    ctx.cb.setStatus(sprintf('Calibrated: %.4g %s/px (from %.1f px = %g %s)', ...
        newPixelSize, realUnit, pxDist, realDist, realUnit));
end

% ════════════════════════════════════════════════════════════════════
%  autoDetectScaleBar — Find scale bar in image automatically
% ════════════════════════════════════════════════════════════════════
function appData = doAutoDetectScaleBar(appData, ctx)
    ctx.fig.Pointer = 'watch'; drawnow;
    try
        det = emViewer.calibration.detectScaleBar(appData.filteredPixels);
        ctx.fig.Pointer = 'arrow';
        if ~det.found
            uialert(ctx.fig, det.msg, 'Auto-Detect Failed', 'Icon', 'warning');
            return;
        end

        barColor = [0 1 1];
        hBarLine = line(ctx.ax, [det.barX1 det.barX2], [det.barY det.barY], ...
            'Color', barColor, 'LineWidth', 3, 'HandleVisibility', 'off');
        hBarEnd1 = line(ctx.ax, [det.barX1 det.barX1], [det.barY-8 det.barY+8], ...
            'Color', barColor, 'LineWidth', 2, 'HandleVisibility', 'off');
        hBarEnd2 = line(ctx.ax, [det.barX2 det.barX2], [det.barY-8 det.barY+8], ...
            'Color', barColor, 'LineWidth', 2, 'HandleVisibility', 'off');
        hBarLabel = text(ctx.ax, (det.barX1 + det.barX2)/2, det.barY - 12, ...
            det.msg, 'Color', barColor, 'FontSize', 11, 'FontWeight', 'bold', ...
            'HorizontalAlignment', 'center', 'BackgroundColor', [0.1 0.1 0.1], ...
            'HandleVisibility', 'off');
        drawnow;

        [realDist, realUnit, cancelled] = emViewer.calibration.promptScaleBarDistance(det.barLen);

        if isvalid(hBarLine),  delete(hBarLine);  end
        if isvalid(hBarEnd1),  delete(hBarEnd1);  end
        if isvalid(hBarEnd2),  delete(hBarEnd2);  end
        if isvalid(hBarLabel), delete(hBarLabel); end
        if cancelled, return; end

        newPixelSize = realDist / det.barLen;
        appData = ctx.cb.applyCalibration(appData, newPixelSize, realUnit);
        ctx.cb.setStatus(sprintf('Calibrated: %.4g %s/px (auto-detected %.0f px = %g %s)', ...
            newPixelSize, realUnit, det.barLen, realDist, realUnit));
    catch ME
        ctx.fig.Pointer = 'arrow';
        uialert(ctx.fig, sprintf('Auto-detect failed:\n%s', ME.message), 'Error', 'Icon', 'error');
    end
end
