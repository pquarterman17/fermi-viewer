function varargout = measExecute(action, appData, ctx, varargin)
%MEASEXECUTE  Measurement drawing and execution helpers for FermiViewer.
%
% Syntax:
%   appData = emViewer.measExecute('profile',    appData, ctx, x1,y1,x2,y2)
%   appData = emViewer.measExecute('boxProfile', appData, ctx, x1,y1,x2,y2,width)
%   appData = emViewer.measExecute('distance',   appData, ctx, x1,y1,x2,y2)
%   [appData, hMark] = emViewer.measExecute('endpointMarker', appData, ctx, x,y,symType,symColor)
%   [appData, hTxt]  = emViewer.measExecute('distLabel',      appData, ctx, x1,y1,x2,y2)
%   appData = emViewer.measExecute('runProfile', appData, ctx, x1,y1,x2,y2)
%   [appData, angleDeg] = emViewer.measExecute('angleFromPoints', appData, ctx, pts)
%   [appData, totalDist] = emViewer.measExecute('polylineFromPoints', appData, ctx, pts)
%
% Inputs:
%   action   — string identifying the operation
%   appData  — FermiViewer appData struct (returned modified)
%   ctx      — context struct with fields:
%                .ax          — target axes handle
%                .fig         — figure handle
%                .ui          — struct of relevant widget handles:
%                    .ddMeasColor, .spnProfileWidth, .btnExportProfile,
%                    .ddMeasSymbol, .spnMeasLabelFont
%                .cb          — struct of callback function handles:
%                    .setStatus, .runWidthAveragedProfile, .getTiltState,
%                    .selectMeasurement, .deselectMeasurement, .finishCapture,
%                    .applyCalibration
%                .OVERLAY_COLOR — default colour for overlays
%   varargin — action-specific arguments (x1,y1,x2,y2, width, pts, ...)
%
% Outputs:
%   appData — modified appData
%   varargout — action-specific outputs (handles, scalar values)
%
% Examples:
%   ctx = buildMeasCtx();
%   appData = emViewer.measExecute('profile', appData, ctx, x1, y1, x2, y2);

% ════════════════════════════════════════════════════════════════════
switch lower(strtrim(action))
    case 'profile'
        [x1,y1,x2,y2] = deal(varargin{1:4});
        appData = doExecuteMeasureProfile(appData, ctx, x1, y1, x2, y2);
        varargout{1} = appData;

    case 'boxprofile'
        [x1,y1,x2,y2,width] = deal(varargin{1:5});
        appData = doExecuteBoxProfile(appData, ctx, x1, y1, x2, y2, width);
        varargout{1} = appData;

    case 'distance'
        [x1,y1,x2,y2] = deal(varargin{1:4});
        appData = doExecuteMeasureDistance(appData, ctx, x1, y1, x2, y2);
        varargout{1} = appData;

    case 'endpointmarker'
        x = varargin{1}; y = varargin{2};
        symType  = 'circle'; if numel(varargin) >= 3, symType  = varargin{3}; end
        symColor = ctx.OVERLAY_COLOR; if numel(varargin) >= 4, symColor = varargin{4}; end
        hMark = doCreateEndpointMarker(ctx.ax, x, y, symType, symColor);
        varargout{1} = appData;
        varargout{2} = hMark;

    case 'distlabel'
        [x1,y1,x2,y2] = deal(varargin{1:4});
        [appData, hTxt] = doCreateDistanceLabel(appData, ctx, x1, y1, x2, y2);
        varargout{1} = appData;
        varargout{2} = hTxt;

    case 'runprofile'
        [x1,y1,x2,y2] = deal(varargin{1:4});
        appData = doRunProfile(appData, ctx, x1, y1, x2, y2);
        varargout{1} = appData;

    case 'anglefrompoints'
        pts = varargin{1};
        [appData, angleDeg] = doExecuteAngleFromPoints(appData, ctx, pts);
        varargout{1} = appData;
        varargout{2} = angleDeg;

    case 'polylinefrompoints'
        pts = varargin{1};
        [appData, totalDist] = doExecutePolylineFromPoints(appData, ctx, pts);
        varargout{1} = appData;
        varargout{2} = totalDist;

    otherwise
        error('emViewer:measExecute:unknownAction', ...
            'Unknown action: ''%s''', action);
end

% ════════════════════════════════════════════════════════════════════
%  executeMeasureProfile — Draw line and plot profile figure
% ════════════════════════════════════════════════════════════════════
function appData = doExecuteMeasureProfile(appData, ctx, x1, y1, x2, y2)
    ax = ctx.ax;
    measClr = ctx.ui.ddMeasColor.Value;
    if isempty(measClr), measClr = ctx.OVERLAY_COLOR; end
    hLine = line(ax, [x1 x2], [y1 y2], ...
        'Color',            measClr, ...
        'LineWidth',        1.5, ...
        'HandleVisibility', 'off');
    appData.overlays.lines{end+1} = hLine;

    % Delete temporary click markers -- we'll create draggable ones
    for ci = 1:numel(appData.overlays.clickMarkers)
        h = appData.overlays.clickMarkers{ci};
        if isvalid(h), delete(h); end
    end
    appData.overlays.clickMarkers = {};

    % Create draggable endpoint markers
    hP1 = doCreateEndpointMarker(ax, x1, y1, ctx.ui.ddMeasSymbol.Value, measClr);
    hP2 = doCreateEndpointMarker(ax, x2, y2, ctx.ui.ddMeasSymbol.Value, measClr);

    % Build measurement record
    meas.type      = 'profile';
    meas.hLine     = hLine;
    meas.hP1       = hP1;
    meas.hP2       = hP2;
    meas.hText     = [];   % profiles don't have a midpoint label
    meas.lineColor = measClr;
    meas.endSymbol = ctx.ui.ddMeasSymbol.Value;
    midx = numel(appData.overlays.measurements) + 1;
    appData.overlays.measurements{midx} = meas;
    appData.measWorkshop.sync(appData.overlays.measurements);

    % Attach drag + selection callbacks
    hP1.ButtonDownFcn   = @(~,~) ctx.cb.startEndpointDrag(midx, 1);
    hP2.ButtonDownFcn   = @(~,~) ctx.cb.startEndpointDrag(midx, 2);
    hLine.ButtonDownFcn = @(~,~) ctx.cb.selectMeasurement(midx);
    hLine.HitTest = 'on'; hLine.PickableParts = 'all';
    hLine.ContextMenu = ctx.cb.buildMeasLineMenu(hLine);

    % Run the profile computation
    appData = doRunProfile(appData, ctx, x1, y1, x2, y2);

% ════════════════════════════════════════════════════════════════════
%  executeBoxProfile — Rotated-rectangle integrated profile
% ════════════════════════════════════════════════════════════════════
function appData = doExecuteBoxProfile(appData, ctx, x1, y1, x2, y2, width)
    ax = ctx.ax;
    dx = x2 - x1; dy = y2 - y1;
    L = hypot(dx, dy);
    if L < 1
        ctx.cb.setStatus('Box profile: endpoints too close.');
        return;
    end
    ux = -dy / L; uy = dx / L;    % perpendicular unit vector
    h = width / 2;
    corners = [
        x1 + h*ux, y1 + h*uy;
        x2 + h*ux, y2 + h*uy;
        x2 - h*ux, y2 - h*uy;
        x1 - h*ux, y1 - h*uy
    ];

    % Clear temporary click markers before drawing the box
    for ci = 1:numel(appData.overlays.clickMarkers)
        hh = appData.overlays.clickMarkers{ci};
        if isvalid(hh), delete(hh); end
    end
    appData.overlays.clickMarkers = {};

    measClr = ctx.ui.ddMeasColor.Value;
    if isempty(measClr), measClr = ctx.OVERLAY_COLOR; end

    % Filled rotated rectangle (translucent) + dashed center line
    patch(ax, corners(:,1), corners(:,2), measClr, ...
        'FaceAlpha',        0.12, ...
        'EdgeColor',        measClr, ...
        'LineWidth',        1.2, ...
        'Tag',              'box_profile', ...
        'HandleVisibility', 'off', ...
        'HitTest',          'off');
    line(ax, [x1 x2], [y1 y2], ...
        'Color',            measClr, ...
        'LineWidth',        1.2, ...
        'LineStyle',        '--', ...
        'Tag',              'box_profile', ...
        'HandleVisibility', 'off', ...
        'HitTest',          'off');

    % Compute the averaged profile using the existing engine
    try
        prof = ctx.cb.runWidthAveragedProfile(x1, y1, x2, y2, width);
    catch ME
        uialert(ctx.fig, sprintf('Box profile failed:\n%s', ME.message), ...
            'Error', 'Icon', 'error');
        return;
    end

    dist      = prof.dist;
    intensity = prof.intensity;

    % Pixel-size calibration for the distance axis
    pu = 'px';
    if appData.activeIdx >= 1
        imgInfo = appData.images{appData.activeIdx}.metadata.parserSpecific.imageData;
        if imgInfo.calibrated && ~isnan(imgInfo.pixelSize)
            dist = dist * imgInfo.pixelSize;
            pu   = char(imgInfo.pixelUnit);
            if isempty(pu), pu = 'px'; end
        end
    end

    % Stash for CSV export (reuses the Line Profile export button)
    appData.lastProfile = struct('dist', dist, 'intensity', intensity, 'unit', pu);
    ctx.ui.btnExportProfile.Enable = 'on';

    if ~strcmp(pu, 'px') && ~isempty(dist)
        ctx.cb.setStatus(sprintf('Box profile: length %.4g %s, width %d px (averaged across %d lines)', ...
            dist(end), pu, width, width));
    else
        ctx.cb.setStatus(sprintf('Box profile: length %.1f px, width %d px', L, width));
    end

    emViewer.measurement.plotProfileFigure(dist, intensity, pu, ...
        sprintf('Box Profile (width = %d px)', width), ...
        YLabel='Mean intensity');

% ════════════════════════════════════════════════════════════════════
%  executeMeasureDistance — Draw line and annotate distance
% ════════════════════════════════════════════════════════════════════
function appData = doExecuteMeasureDistance(appData, ctx, x1, y1, x2, y2)
    ax = ctx.ax;
    measClr = ctx.ui.ddMeasColor.Value;
    if isempty(measClr), measClr = ctx.OVERLAY_COLOR; end
    hLine = line(ax, [x1 x2], [y1 y2], ...
        'Color',            measClr, ...
        'LineWidth',        1.5, ...
        'HandleVisibility', 'off');
    appData.overlays.lines{end+1} = hLine;

    % Delete temporary click markers -- we'll create draggable ones
    for ci = 1:numel(appData.overlays.clickMarkers)
        h = appData.overlays.clickMarkers{ci};
        if isvalid(h), delete(h); end
    end
    appData.overlays.clickMarkers = {};

    % Create draggable endpoint markers
    hP1 = doCreateEndpointMarker(ax, x1, y1, ctx.ui.ddMeasSymbol.Value, measClr);
    hP2 = doCreateEndpointMarker(ax, x2, y2, ctx.ui.ddMeasSymbol.Value, measClr);

    % Create midpoint distance label
    [appData, hTxt] = doCreateDistanceLabel(appData, ctx, x1, y1, x2, y2);

    % Build measurement record
    meas.type      = 'distance';
    meas.hLine     = hLine;
    meas.hP1       = hP1;
    meas.hP2       = hP2;
    meas.hText     = hTxt;
    meas.lineColor = measClr;
    meas.endSymbol = ctx.ui.ddMeasSymbol.Value;
    % Store distance value in calibrated units (or px if uncalibrated)
    try
        imgInfo = appData.images{appData.activeIdx}.metadata.parserSpecific.imageData;
        [tiltDeg, tiltAxis, ~, tiltGeom] = ctx.cb.getTiltState();
        if imgInfo.calibrated && ~isnan(imgInfo.pixelSize)
            [dv, du] = imaging.measureDistance(x1, y1, x2, y2, ...
                PixelSize=imgInfo.pixelSize, PixelUnit=imgInfo.pixelUnit, ...
                TiltAngle=tiltDeg, TiltAxis=tiltAxis, Geometry=tiltGeom);
        else
            [dv, du] = imaging.measureDistance(x1, y1, x2, y2, ...
                TiltAngle=tiltDeg, TiltAxis=tiltAxis, Geometry=tiltGeom);
        end
        meas.distance = dv;
        meas.unit     = du;
    catch
        meas.distance = sqrt((x2-x1)^2 + (y2-y1)^2);
        meas.unit     = 'px';
    end
    midx = numel(appData.overlays.measurements) + 1;
    appData.overlays.measurements{midx} = meas;
    appData.measWorkshop.sync(appData.overlays.measurements);

    % Attach drag + selection callbacks
    hP1.ButtonDownFcn   = @(~,~) ctx.cb.startEndpointDrag(midx, 1);
    hP2.ButtonDownFcn   = @(~,~) ctx.cb.startEndpointDrag(midx, 2);
    hLine.ButtonDownFcn = @(~,~) ctx.cb.selectMeasurement(midx);
    hLine.HitTest = 'on'; hLine.PickableParts = 'all';

    % Right-click menu on the line handle
    hLine.ContextMenu = ctx.cb.buildMeasLineMenu(hLine);

    appData.overlays.distLabels{end+1} = hTxt;
    ctx.cb.setStatus(sprintf('Distance: %s', hTxt.String));

% ════════════════════════════════════════════════════════════════════
%  createEndpointMarker — Draggable marker for line endpoints
% ════════════════════════════════════════════════════════════════════
function hMark = doCreateEndpointMarker(ax, x, y, symType, symColor)
    mrk   = emViewer.meas.symToMarker(symType);
    mrkSz = 6; if strcmp(symType, 'none'), mrkSz = 0.1; end
    tickHalf = 4;
    hMark = line(ax, [x - tickHalf, x, x + tickHalf], [y, y, y], ...
        'Marker',           mrk, ...
        'MarkerIndices',    2, ...
        'MarkerSize',       mrkSz, ...
        'MarkerEdgeColor',  symColor, ...
        'MarkerFaceColor',  'none', ...
        'LineStyle',        '-', ...
        'LineWidth',        1.0, ...
        'Color',            symColor, ...
        'HandleVisibility', 'off');

% ════════════════════════════════════════════════════════════════════
%  createDistanceLabel — Offset annotation with distance text
% ════════════════════════════════════════════════════════════════════
function [appData, hTxt] = doCreateDistanceLabel(appData, ctx, x1, y1, x2, y2)
    ax = ctx.ax;
    % Retrieve calibration
    imgInfo = appData.images{appData.activeIdx}.metadata.parserSpecific.imageData;
    ps = NaN;
    pu = 'px';
    if imgInfo.calibrated && ~isnan(imgInfo.pixelSize)
        ps = imgInfo.pixelSize;
        pu = imgInfo.pixelUnit;
    end

    [tiltDeg, tiltAxis, tiltActive, tiltGeom] = ctx.cb.getTiltState();

    if ~isnan(ps)
        [dVal, dUnit] = imaging.measureDistance(x1, y1, x2, y2, ...
            PixelSize=ps, PixelUnit=pu, ...
            TiltAngle=tiltDeg, TiltAxis=tiltAxis, Geometry=tiltGeom);
        distStr = sprintf('%.4g %s', dVal, dUnit);
    else
        [dVal, dUnit] = imaging.measureDistance(x1, y1, x2, y2, ...
            TiltAngle=tiltDeg, TiltAxis=tiltAxis, Geometry=tiltGeom);
        distStr = sprintf('%.1f %s', dVal, dUnit);
    end
    if tiltActive
        distStr = [distStr, '*'];
    end

    % Offset the label perpendicular to the measurement line
    mx_ = (x1 + x2) / 2;
    my_ = (y1 + y2) / 2;
    dx_ = x2 - x1;  dy_ = y2 - y1;
    len_ = hypot(dx_, dy_);
    if len_ < eps
        nx_ = 0;  ny_ = -1;
    else
        nx_ = -dy_ / len_;  ny_ = dx_ / len_;
        if ny_ > 0, nx_ = -nx_; ny_ = -ny_; end   % prefer up-on-screen
    end
    lx_ = mx_ + 14 * nx_;
    ly_ = my_ + 14 * ny_;
    if ~isempty(appData.filteredPixels)
        [H_, W_] = size(appData.filteredPixels);
        if lx_ < 1 || lx_ > W_ || ly_ < 1 || ly_ > H_
            lx_ = mx_ - 14 * nx_;
            ly_ = my_ - 14 * ny_;
        end
    end

    hTxt = text(ax, lx_, ly_, distStr, ...
        'Color',               [1 1 1], ...
        'FontSize',            ctx.ui.spnMeasLabelFont.Value, ...
        'FontWeight',          'bold', ...
        'HorizontalAlignment', 'center', ...
        'VerticalAlignment',   'middle', ...
        'BackgroundColor',     'none', ...
        'EdgeColor',           'none', ...
        'Margin',              1, ...
        'HandleVisibility',    'off');

    % Drag to reposition the label without affecting the measurement.
    hTxt.ButtonDownFcn = @(~,~) ctx.cb.startLabelDrag(hTxt);

    % Context menu: always includes "Font size..."
    cm = uicontextmenu(ctx.fig);
    if tiltActive
        if strcmpi(tiltGeom, 'Surface')
            factorName = 'cos';
        else
            factorName = 'sin';
        end
        tipStr = sprintf( ...
            'Tilt-corrected: 1/%s(%.1f degrees) applied on %s-axis (%s geometry)', ...
            factorName, tiltDeg, upper(char(tiltAxis)), tiltGeom);
        hTxt.UserData = struct('tooltip', tipStr);
        uimenu(cm, 'Text', tipStr, 'Enable', 'off');
    end
    uimenu(cm, 'Text', 'Font size', ...
        'MenuSelectedFcn', @(~,~) ctx.cb.panelApplyLabelFont());
    hTxt.ContextMenu = cm;

    % Log measurement
    detailStr = sprintf('(%.0f,%.0f)-(%.0f,%.0f)', x1, y1, x2, y2);
    if tiltActive
        detailStr = sprintf('%s tilt=%.2f deg axis=%s geom=%s', ...
            detailStr, tiltDeg, tiltAxis, tiltGeom);
    end
    appData.measurementLog{end+1} = struct( ...
        'type', 'distance', 'value', dVal, 'unit', dUnit, ...
        'details', detailStr, ...
        'timestamp', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')));

% ════════════════════════════════════════════════════════════════════
%  runProfile — Extract and display line profile
% ════════════════════════════════════════════════════════════════════
function appData = doRunProfile(appData, ctx, x1, y1, x2, y2)
    if isempty(appData.filteredPixels) || ~isnumeric(appData.filteredPixels)
        uialert(ctx.fig, 'Load an image before running a line profile.', ...
            'No image', 'Icon', 'warning');
        return;
    end
    imgInfo = appData.images{appData.activeIdx}.metadata.parserSpecific.imageData;
    ps = NaN;
    pu = 'px';
    if imgInfo.calibrated && ~isnan(imgInfo.pixelSize)
        ps = imgInfo.pixelSize;
        pu = char(imgInfo.pixelUnit);
        if isempty(pu), pu = 'px'; end
    end

    [tiltDeg, tiltAxis, tiltActive, tiltGeom] = ctx.cb.getTiltState();

    try
        profileWidth = ctx.ui.spnProfileWidth.Value;
        if profileWidth > 1
            % Width-averaged profile
            profResult = ctx.cb.runWidthAveragedProfile(x1, y1, x2, y2, profileWidth);
            dist = profResult.dist;
            intensity = profResult.intensity;
            if tiltActive && ~isempty(dist)
                dxp = x2 - x1; dyp = y2 - y1;
                if strcmpi(tiltGeom, 'Surface')
                    scl = 1 / cosd(tiltDeg);
                else
                    scl = 1 / sind(tiltDeg);
                end
                if strcmpi(tiltAxis, 'Y'), dyp = dyp * scl; else, dxp = dxp * scl; end
                correctedPx = sqrt(dxp^2 + dyp^2);
                origPx = sqrt((x2-x1)^2 + (y2-y1)^2);
                if origPx > 0
                    dist = dist * (correctedPx / origPx);
                end
            end
            if ~isnan(ps)
                dist = dist * ps;
            end
        else
            if ~isnan(ps)
                [dist, intensity] = imaging.lineProfile(appData.filteredPixels, ...
                    x1, y1, x2, y2, PixelSize=ps, PixelUnit=pu, ...
                    TiltAngle=tiltDeg, TiltAxis=tiltAxis, Geometry=tiltGeom);
            else
                [dist, intensity] = imaging.lineProfile(appData.filteredPixels, ...
                    x1, y1, x2, y2, TiltAngle=tiltDeg, TiltAxis=tiltAxis, ...
                    Geometry=tiltGeom);
            end
        end
    catch ME
        uialert(ctx.fig, sprintf('Line profile failed:\n%s', ME.message), ...
            'Error', 'Icon', 'error');
        return;
    end

    % Store for CSV export
    appData.lastProfile = struct('dist', dist, 'intensity', intensity, 'unit', pu);
    ctx.ui.btnExportProfile.Enable = 'on';

    % Status bar
    [dVal, dUnit] = imaging.measureDistance(x1, y1, x2, y2, ...
        PixelSize=ps, PixelUnit=pu, ...
        TiltAngle=tiltDeg, TiltAxis=tiltAxis, Geometry=tiltGeom);
    tiltTag = '';
    if tiltActive, tiltTag = sprintf(' (tilt %.1f deg)', tiltDeg); end
    if ~isnan(ps)
        ctx.cb.setStatus(sprintf('Line profile: %.4g %s%s', dVal, dUnit, tiltTag));
    else
        ctx.cb.setStatus(sprintf('Line profile: %.1f px%s', dVal, tiltTag));
    end

    emViewer.measurement.plotProfileFigure(dist, intensity, pu, 'Line Profile');

% ════════════════════════════════════════════════════════════════════
%  executeAngleFromPoints — Headless angle measurement
% ════════════════════════════════════════════════════════════════════
function [appData, angleDeg] = doExecuteAngleFromPoints(appData, ctx, pts)
%DOEXECUTEANGLEFROMPOINTS  Measure/draw/log angle from 3 points.
%   pts is a 3x2 matrix: [vertex; ray1; ray2].
    ax = ctx.ax;
    if appData.activeIdx < 1 || isempty(appData.displayImg)
        angleDeg = NaN; return;
    end
    if ~isequal(size(pts), [3 2])
        error('FermiViewer:badInput', 'executeAngleFromPoints: pts must be 3x2');
    end

    v1 = pts(2,:) - pts(1,:);
    v2 = pts(3,:) - pts(1,:);
    % No tilt correction in headless path (caller supplies pre-corrected pts)
    angleDeg = emViewer.measurements('computeAngle', v1, v2, 0, 'Y', 'CrossSection');
    if isnan(angleDeg), return; end

    % Draw the two rays
    hL1 = line(ax, [pts(1,1) pts(2,1)], [pts(1,2) pts(2,2)], ...
        'Color', ctx.OVERLAY_COLOR, 'LineWidth', 1.5, 'HandleVisibility', 'off');
    appData.overlays.lines{end+1} = hL1;
    hL2 = line(ax, [pts(1,1) pts(3,1)], [pts(1,2) pts(3,2)], ...
        'Color', ctx.OVERLAY_COLOR, 'LineWidth', 1.5, 'HandleVisibility', 'off');
    appData.overlays.lines{end+1} = hL2;

    % Arc annotation
    arc = emViewer.measurements('arcGeometry', pts, v1, v2);
    hArc = line(ax, arc.arcX, arc.arcY, ...
        'Color', ctx.OVERLAY_COLOR, 'LineWidth', 1, 'LineStyle', '--', ...
        'HandleVisibility', 'off');
    appData.overlays.lines{end+1} = hArc;

    labelX = pts(1,1) + arc.arcRadius * 1.4 * cosd(arc.midAngle);
    labelY = pts(1,2) + arc.arcRadius * 1.4 * sind(arc.midAngle);
    hLabel = text(ax, labelX, labelY, sprintf('%.1f deg', angleDeg), ...
        'Color', ctx.OVERLAY_COLOR, 'FontSize', 12, 'FontWeight', 'bold', ...
        'HorizontalAlignment', 'center', 'HandleVisibility', 'off');
    appData.overlays.distLabels{end+1} = hLabel;

    appData.measurementLog{end+1} = struct( ...
        'type', 'angle', 'value', angleDeg, 'unit', 'deg', ...
        'details', sprintf('vertex=(%.0f,%.0f)', pts(1,1), pts(1,2)), ...
        'timestamp', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')));

% ════════════════════════════════════════════════════════════════════
%  executePolylineFromPoints — Headless polyline length
% ════════════════════════════════════════════════════════════════════
function [appData, totalDist] = doExecutePolylineFromPoints(appData, ctx, pts)
%DOEXECUTEPOLYLINEFROMPOINTS  Measure/draw/log polyline path length.
%   pts is an Nx2 matrix of (x,y) vertices (N >= 2).
    ax = ctx.ax;
    if appData.activeIdx < 1 || isempty(appData.displayImg)
        totalDist = NaN; return;
    end
    if size(pts, 2) ~= 2 || size(pts, 1) < 2
        error('FermiViewer:badInput', ...
            'executePolylineFromPoints: pts must be Nx2 with N>=2');
    end

    measClr = ctx.OVERLAY_COLOR;

    % Draw vertex markers and segments
    nPts = size(pts, 1);
    hMarkers = gobjects(nPts, 1);
    hLines   = gobjects(max(0, nPts-1), 1);
    for pi = 1:nPts
        hMarkers(pi) = line(ax, pts(pi,1), pts(pi,2), ...
            'Marker', 'o', 'MarkerSize', 6, ...
            'MarkerFaceColor', measClr, ...
            'MarkerEdgeColor', 'none', ...
            'LineStyle', 'none', 'HandleVisibility', 'off');
        if pi >= 2
            hLines(pi-1) = line(ax, [pts(pi-1,1) pts(pi,1)], ...
                          [pts(pi-1,2) pts(pi,2)], ...
                'Color', measClr, 'LineWidth', 1.5, ...
                'HandleVisibility', 'off');
        end
    end

    % Total length (no tilt correction in headless path)
    totalDist = emViewer.measurements('polylineLength', pts, 0, 'Y', 'CrossSection');

    % Calibration
    unitStr = 'px';
    imgInfo = appData.images{appData.activeIdx}.metadata.parserSpecific.imageData;
    if imgInfo.calibrated && ~isnan(imgInfo.pixelSize)
        totalDist = totalDist * imgInfo.pixelSize;
        unitStr = imgInfo.pixelUnit;
    end

    % Label at midpoint
    midIdx = max(1, round(size(pts, 1) / 2));
    hLabel = text(ax, pts(midIdx, 1), pts(midIdx, 2), ...
        sprintf('%.2f %s', totalDist, unitStr), ...
        'Color', measClr, 'FontSize', 11, 'FontWeight', 'bold', ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
        'HandleVisibility', 'off');

    nSegs = nPts - 1;

    % Register as a measurement record
    meas = struct();
    meas.type      = 'polyline';
    meas.hLines    = hLines;
    meas.hMarkers  = hMarkers;
    meas.hText     = hLabel;
    meas.hLine     = [];
    meas.hP1       = [];
    meas.hP2       = [];
    meas.vertices  = pts;
    meas.totalDist = totalDist;
    meas.unit      = unitStr;
    meas.lineColor = measClr;
    midx = numel(appData.overlays.measurements) + 1;
    appData.overlays.measurements{midx} = meas;
    appData.measWorkshop.sync(appData.overlays.measurements);

    for hh = [hLines(:); hMarkers(:); hLabel]'
        if isvalid(hh)
            hh.HitTest = 'on';
            hh.PickableParts = 'all';
            hh.ButtonDownFcn = @(~,~) ctx.cb.selectMeasurement(midx);
        end
    end

    appData.measurementLog{end+1} = struct( ...
        'type', 'polyline', 'value', totalDist, 'unit', unitStr, ...
        'details', sprintf('%d segments', nSegs), ...
        'timestamp', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')));
