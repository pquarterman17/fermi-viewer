function varargout = scaleBarOps(action, appData, ctx, varargin)
%SCALEBAROPS  Scale bar operations for FermiViewer.
%
% Syntax:
%   appData = fermiViewer.export.scaleBarOps('rebuild', appData, ctx)
%
% Inputs:
%   action   — string identifying the operation (only 'rebuild')
%   appData  — FermiViewer appData struct (returned modified)
%   ctx      — context struct with fields:
%                .ax          — primary axes handle
%                .axL, .axR   — compare-mode axes (may be empty)
%                .fig         — figure handle
%                .ui          — struct of widget handles:
%                    .spnScaleBarFont, .efScaleBarLen, .ddScaleBarUnit,
%                    .cbScaleBar
%                .cb          — struct of callback function handles:
%                    .deleteScaleBar, .makeScaleBarDraggable, .setStatus
%
% Examples:
%   ctx = buildScaleBarCtx();
%   appData = fermiViewer.export.scaleBarOps('rebuild', appData, ctx);
%
% NOTE: 'startDrag', 'calibrate', and 'autoDetect' actions were removed
% (2026-05-24) — they were dead duplicates of FermiViewer's inline
% startScaleBarDrag / executeScaleBarCalibration / autoDetectScaleBar, and
% the calibrate/autoDetect paths referenced a ctx.cb.applyCalibration that
% buildScaleBarCtx never provided (a latent crash if ever revived).

% ════════════════════════════════════════════════════════════════════
switch lower(strtrim(action))
    case 'rebuild'
        appData = doRebuildScaleBar(appData, ctx);
        varargout{1} = appData;

    otherwise
        error('fermiViewer:export:scaleBarOps:unknownAction', ...
            'Unknown action: ''%s''', action);
end
end

% ════════════════════════════════════════════════════════════════════
%  rebuildScaleBar — Delete and recreate with current settings
% ════════════════════════════════════════════════════════════════════
function appData = doRebuildScaleBar(appData, ctx)
    % Snapshot existing bar/label positions BEFORE delete so that user
    % drag offsets survive a property change (color, font, length, unit).
    snapSingle = fermiViewer.export.snapScaleBarPos(appData.overlays.scalebar);
    snapL      = fermiViewer.export.snapScaleBarPos(appData.overlays.scalebarL);
    snapR      = fermiViewer.export.snapScaleBarPos(appData.overlays.scalebarR);

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
            fermiViewer.export.applyScaleBarPos(hB, prevSnap);
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
        fermiViewer.export.applyScaleBarPos(hBar, snapSingle);
        appData.overlays.scalebar = hBar;
        ctx.cb.makeScaleBarDraggable(hBar);
    end
end
