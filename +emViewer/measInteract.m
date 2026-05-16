function varargout = measInteract(action, appData, ctx, varargin)
%MEASINTERACT  Measurement interaction handlers for FermiViewer.
%
% Syntax:
%   appData = emViewer.measInteract('startEndpointDrag', appData, ctx, measIdx, whichEnd)
%   appData = emViewer.measInteract('applyMarqueeSelection', appData, ctx, xMin,xMax,yMin,yMax)
%   appData = emViewer.measInteract('onAngleAction', appData, ctx, action)
%   appData = emViewer.measInteract('onPolylineAction', appData, ctx, action)
%
% Inputs:
%   action   — string identifying the operation
%   appData  — FermiViewer appData struct (returned modified)
%   ctx      — context struct with fields:
%                .ax            — target axes handle
%                .fig           — figure handle
%                .OVERLAY_COLOR — default overlay colour
%                .ui            — struct of widget handles:
%                    .ddMeasColor, .ddMeasSymbol
%                .cb            — struct of callback function handles:
%                    .setStatus, .selectMeasurement, .deselectMeasurement,
%                    .getTiltState, .runProfile, .createDistanceLabel,
%                    .finishCapture, .cancelCapture, .highlightAnnotation,
%                    .applyMeasHighlight
%   varargin — action-specific arguments
%
% Examples:
%   ctx = buildMeasCtx();
%   appData = emViewer.measInteract('startEndpointDrag', appData, ctx, midx, 1);

% ════════════════════════════════════════════════════════════════════
switch lower(strtrim(action))
    case 'startendpointdrag'
        [measIdx, whichEnd] = deal(varargin{1:2});
        appData = doStartEndpointDrag(appData, ctx, measIdx, whichEnd);
        varargout{1} = appData;

    case 'applymarqueeselection'
        [xMin, xMax, yMin, yMax] = deal(varargin{1:4});
        appData = doApplyMarqueeSelection(appData, ctx, xMin, xMax, yMin, yMax);
        varargout{1} = appData;

    case 'onangleaction'
        act = varargin{1};
        appData = doOnAngleAction(appData, ctx, act);
        varargout{1} = appData;

    case 'onpolylineaction'
        act = varargin{1};
        appData = doOnPolylineAction(appData, ctx, act);
        varargout{1} = appData;

    otherwise
        error('emViewer:measInteract:unknownAction', ...
            'Unknown action: ''%s''', action);
end

% ════════════════════════════════════════════════════════════════════
%  startEndpointDrag — Drag a line endpoint to update measurement
% ════════════════════════════════════════════════════════════════════
function appData = doStartEndpointDrag(appData, ctx, measIdx, whichEnd)
    % whichEnd: 1 = start (P1), 2 = end (P2)
    if measIdx > numel(appData.overlays.measurements)
        return;
    end
    meas = appData.overlays.measurements{measIdx};
    if ~isvalid(meas.hLine)
        return;
    end

    % Select this measurement (highlight + enable Delete key)
    ctx.cb.selectMeasurement(measIdx);

    % Store original callbacks
    origMotionFcn  = ctx.fig.WindowButtonMotionFcn;
    origReleaseFcn = ctx.fig.WindowButtonUpFcn;

    ctx.fig.Pointer = 'crosshair';

    % Capture appData reference via handle trick: use a 1-element cell so
    % the anonymous callbacks can read and write appData by reference.
    adRef = {appData};

    ctx.fig.WindowButtonMotionFcn = @dragMotion;
    ctx.fig.WindowButtonUpFcn    = @dragRelease;

    function dragMotion(~, ~)
        cp = ctx.ax.CurrentPoint;
        nx = cp(1,1);
        ny = cp(1,2);

        % Clamp to image bounds
        if ~isempty(adRef{1}.displayImg)
            [H, W] = size(adRef{1}.filteredPixels);
            nx = max(0.5, min(W + 0.5, nx));
            ny = max(0.5, min(H + 0.5, ny));
        end

        % Update endpoint marker position. The marker is a 3-point
        % line (horizontal tick with a circle at index 2).
        if whichEnd == 1
            rTick = (meas.hP1.XData(end) - meas.hP1.XData(1)) / 2;
            meas.hP1.XData = [nx - rTick, nx, nx + rTick];
            meas.hP1.YData = [ny, ny, ny];
            meas.hLine.XData(1) = nx;
            meas.hLine.YData(1) = ny;
        else
            rTick = (meas.hP2.XData(end) - meas.hP2.XData(1)) / 2;
            meas.hP2.XData = [nx - rTick, nx, nx + rTick];
            meas.hP2.YData = [ny, ny, ny];
            meas.hLine.XData(2) = nx;
            meas.hLine.YData(2) = ny;
        end

        % Update distance label position (perpendicular offset) during drag.
        if ~isempty(meas.hText) && isvalid(meas.hText)
            x1d_ = meas.hLine.XData(1); y1d_ = meas.hLine.YData(1);
            x2d_ = meas.hLine.XData(2); y2d_ = meas.hLine.YData(2);
            mx_ = (x1d_ + x2d_) / 2;
            my_ = (y1d_ + y2d_) / 2;
            dx_ = x2d_ - x1d_;  dy_ = y2d_ - y1d_;
            len_ = hypot(dx_, dy_);
            if len_ < eps
                nx_ = 0;  ny_ = -1;
            else
                nx_ = -dy_ / len_;  ny_ = dx_ / len_;
                if ny_ > 0, nx_ = -nx_; ny_ = -ny_; end
            end
            lx_ = mx_ + 14 * nx_;
            ly_ = my_ + 14 * ny_;
            if ~isempty(adRef{1}.filteredPixels)
                [H_, W_] = size(adRef{1}.filteredPixels);
                if lx_ < 1 || lx_ > W_ || ly_ < 1 || ly_ > H_
                    lx_ = mx_ - 14 * nx_;
                    ly_ = my_ - 14 * ny_;
                end
            end
            meas.hText.Position = [lx_, ly_, 0];
        end
    end

    function dragRelease(~, ~)
        ctx.fig.WindowButtonMotionFcn = origMotionFcn;
        ctx.fig.WindowButtonUpFcn    = origReleaseFcn;
        ctx.fig.Pointer = 'arrow';

        % Read final positions
        x1 = meas.hLine.XData(1);
        y1 = meas.hLine.YData(1);
        x2 = meas.hLine.XData(2);
        y2 = meas.hLine.YData(2);

        % Update the stored record
        adRef{1}.overlays.measurements{measIdx} = meas;

        % Re-run the measurement
        switch meas.type
            case 'profile'
                adRef{1} = ctx.cb.runProfile(adRef{1}, x1, y1, x2, y2);
            case 'distance'
                % Update the distance label text
                if ~isempty(meas.hText) && isvalid(meas.hText)
                    delete(meas.hText);
                end
                [adRef{1}, newTxt] = ctx.cb.createDistanceLabel(adRef{1}, x1, y1, x2, y2);
                meas.hText = newTxt;
                adRef{1}.overlays.measurements{measIdx} = meas;
                ctx.cb.setStatus(sprintf('Distance: %s', newTxt.String));
                % Update distLabels reference
                adRef{1}.overlays.distLabels{end+1} = newTxt;
        end
        adRef{1}.measWorkshop.sync(adRef{1}.overlays.measurements);

        % Clear yellow selection highlight
        ctx.cb.deselectMeasurement();

        % Write appData back — caller must use the returned value
        appData = adRef{1};
    end

    % Note: appData is returned AFTER dragRelease fires (on mouse-up).
    % The caller assigns the return value; updates during drag are via
    % adRef{1} and graphics handles which are pass-by-reference.
    appData = adRef{1};

% ════════════════════════════════════════════════════════════════════
%  applyMarqueeSelection — Select items inside a drag box
% ════════════════════════════════════════════════════════════════════
function appData = doApplyMarqueeSelection(appData, ctx, xMin, xMax, yMin, yMax)
    % Drop existing selection first
    ctx.cb.deselectMeasurement();
    % Clear annotation highlights too
    for ai = appData.selectedAnnotIndices(:)'
        if ai >= 1 && ai <= numel(appData.overlays.textAnnotations)
            ctx.cb.highlightAnnotation(appData.overlays.textAnnotations{ai}, false);
        end
    end
    appData.selectedAnnotIndices = [];
    if appData.selectedAnnotIdx > 0 && ...
            appData.selectedAnnotIdx <= numel(appData.overlays.textAnnotations)
        ctx.cb.highlightAnnotation( ...
            appData.overlays.textAnnotations{appData.selectedAnnotIdx}, false);
    end
    appData.selectedAnnotIdx = 0;

    % Measurements: both endpoints inside the box.
    measPick = [];
    for mi = 1:numel(appData.overlays.measurements)
        m = appData.overlays.measurements{mi};

        % rectROI: include when the rectangle's bounds lie inside the box
        if isfield(m, 'type') && strcmp(m.type, 'rectROI')
            if m.xMin >= xMin && m.xMax <= xMax && ...
                    m.yMin >= yMin && m.yMax <= yMax
                measPick(end+1) = mi; %#ok<AGROW>
            end
            continue;
        end

        % polyline: include when every vertex lies inside the box
        if isfield(m, 'type') && strcmp(m.type, 'polyline') ...
                && isfield(m, 'vertices') && ~isempty(m.vertices)
            vx = m.vertices(:, 1); vy = m.vertices(:, 2);
            if all(vx >= xMin) && all(vx <= xMax) && ...
                    all(vy >= yMin) && all(vy <= yMax)
                measPick(end+1) = mi; %#ok<AGROW>
            end
            continue;
        end

        % Legacy distance/profile/angle measurement: both endpoints inside.
        if ~isfield(m, 'hP1') || ~isfield(m, 'hP2'), continue; end
        if isempty(m.hP1) || isempty(m.hP2), continue; end
        if ~isvalid(m.hP1) || ~isvalid(m.hP2), continue; end
        xd1 = m.hP1.XData; yd1 = m.hP1.YData;
        xd2 = m.hP2.XData; yd2 = m.hP2.YData;
        mIdx = 2;
        if numel(xd1) < mIdx, mIdx = 1; end
        x1 = xd1(mIdx); y1 = yd1(mIdx);
        x2 = xd2(min(mIdx, numel(xd2))); y2 = yd2(min(mIdx, numel(yd2)));
        in1 = x1 >= xMin && x1 <= xMax && y1 >= yMin && y1 <= yMax;
        in2 = x2 >= xMin && x2 <= xMax && y2 >= yMin && y2 <= yMax;
        if in1 && in2
            measPick(end+1) = mi; %#ok<AGROW>
        end
    end

    % Annotations: text anchor inside the box
    annPick = [];
    for ai = 1:numel(appData.overlays.textAnnotations)
        a = appData.overlays.textAnnotations{ai};
        if ~isfield(a, 'x') || ~isfield(a, 'y'), continue; end
        if a.x >= xMin && a.x <= xMax && a.y >= yMin && a.y <= yMax
            annPick(end+1) = ai; %#ok<AGROW>
        end
    end

    % Apply highlights
    for mi = measPick
        ctx.cb.applyMeasHighlight(mi);
    end
    for ai = annPick
        ctx.cb.highlightAnnotation(appData.overlays.textAnnotations{ai}, true);
    end

    % Update state
    appData.selectedMeasIndices = measPick;
    appData.selectedAnnotIndices = annPick;
    if ~isempty(measPick),  appData.selectedMeasIdx  = measPick(end);  end
    if ~isempty(annPick),   appData.selectedAnnotIdx = annPick(end);   end

    nTot = numel(measPick) + numel(annPick);
    if nTot == 0
        ctx.cb.setStatus('Marquee: no items inside the box.');
    elseif nTot == 1
        ctx.cb.setStatus('Marquee: 1 item selected (Delete to remove).');
    else
        ctx.cb.setStatus(sprintf('Marquee: %d items selected (Delete to remove all).', nTot));
    end

% ════════════════════════════════════════════════════════════════════
%  onAngleAction — Three-click angle measurement dispatcher
%  action='start' : begin capture; action='click' : handle each click
% ════════════════════════════════════════════════════════════════════
function appData = doOnAngleAction(appData, ctx, action)
    if strcmp(action, 'start')
        if appData.activeIdx < 1 || isempty(appData.displayImg), return; end
        if appData.compareMode, return; end
        if ~isempty(appData.captureMode), ctx.cb.cancelCapture(); end
        appData.captureMode = 'angle';
        appData.captureClicks = [];
        ctx.fig.Pointer = 'crosshair';
        ctx.fig.WindowButtonDownFcn = @(s,e) ctx.cb.onAngleAction('click', s, e);
        ctx.cb.setStatus('Click vertex point (1 of 3)... (Esc to cancel)');
        return;
    end

    % --- action == 'click' ---
    if ~strcmp(appData.captureMode, 'angle'), return; end
    cp = ctx.ax.CurrentPoint;
    x = cp(1,1);
    y = cp(1,2);
    if isempty(appData.displayImg), return; end
    [H, W] = size(appData.filteredPixels);
    if x < 0.5 || x > W + 0.5 || y < 0.5 || y > H + 0.5, return; end

    appData.captureClicks(end+1, :) = [x, y];
    nClicks = size(appData.captureClicks, 1);

    % Draw marker
    hM = line(ctx.ax, x, y, ...
        'Marker', 'o', 'MarkerSize', 8, ...
        'MarkerFaceColor', ctx.OVERLAY_COLOR, ...
        'MarkerEdgeColor', 'none', ...
        'LineStyle', 'none', ...
        'HandleVisibility', 'off');
    appData.overlays.clickMarkers{end+1} = hM;

    if nClicks == 1
        ctx.cb.setStatus('Click first ray endpoint (2 of 3)... (Esc to cancel)');
    elseif nClicks == 2
        pts = appData.captureClicks;
        hL = line(ctx.ax, [pts(1,1) pts(2,1)], [pts(1,2) pts(2,2)], ...
            'Color', ctx.OVERLAY_COLOR, 'LineWidth', 1.5, 'HandleVisibility', 'off');
        appData.overlays.lines{end+1} = hL;
        ctx.cb.setStatus('Click second ray endpoint (3 of 3)... (Esc to cancel)');
    elseif nClicks >= 3
        pts = appData.captureClicks;
        hL2 = line(ctx.ax, [pts(1,1) pts(3,1)], [pts(1,2) pts(3,2)], ...
            'Color', ctx.OVERLAY_COLOR, 'LineWidth', 1.5, 'HandleVisibility', 'off');
        appData.overlays.lines{end+1} = hL2;

        % Compute tilt-corrected angle (pure math delegated to package)
        v1 = pts(2,:) - pts(1,:);
        v2 = pts(3,:) - pts(1,:);
        [tiltDeg, tiltAxis, tiltActive, tiltGeom] = ctx.cb.getTiltState();
        angleDeg = emViewer.measurements('computeAngle', v1, v2, tiltDeg, tiltAxis, tiltGeom);

        % Arc annotation geometry
        arc = emViewer.measurements('arcGeometry', pts, v1, v2);
        hArc = line(ctx.ax, arc.arcX, arc.arcY, ...
            'Color', ctx.OVERLAY_COLOR, 'LineWidth', 1, ...
            'LineStyle', '--', 'HandleVisibility', 'off');
        appData.overlays.lines{end+1} = hArc;

        % Label at midpoint of arc
        labelX = pts(1,1) + arc.arcRadius * 1.4 * cosd(arc.midAngle);
        labelY = pts(1,2) + arc.arcRadius * 1.4 * sind(arc.midAngle);
        angleStr = sprintf('%.1f deg', angleDeg);
        if tiltActive, angleStr = [angleStr, '*']; end
        hLabel = text(ctx.ax, labelX, labelY, angleStr, ...
            'Color', ctx.OVERLAY_COLOR, 'FontSize', 12, ...
            'FontWeight', 'bold', ...
            'HorizontalAlignment', 'center', ...
            'HandleVisibility', 'off');
        appData.overlays.distLabels{end+1} = hLabel;

        % Clean up temporary click markers (keep lines and labels)
        for ci = 1:numel(appData.overlays.clickMarkers)
            h = appData.overlays.clickMarkers{ci};
            if isvalid(h), delete(h); end
        end
        appData.overlays.clickMarkers = {};

        ctx.cb.finishCapture();
        tiltTag = '';
        if tiltActive, tiltTag = sprintf(' [tilt %.1f deg]', tiltDeg); end
        ctx.cb.setStatus(sprintf('Angle: %.1f deg%s', angleDeg, tiltTag));

        detailStr = sprintf('vertex=(%.0f,%.0f)', pts(1,1), pts(1,2));
        if tiltActive
            detailStr = sprintf('%s tilt=%.2f deg axis=%s', detailStr, tiltDeg, tiltAxis);
        end
        appData.measurementLog{end+1} = struct( ...
            'type', 'angle', 'value', angleDeg, 'unit', 'deg', ...
            'details', detailStr, ...
            'timestamp', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')));
    end

% ════════════════════════════════════════════════════════════════════
%  onPolylineAction — Multi-point distance measurement dispatcher
%  action='start' : begin capture; action='click' : handle each click
% ════════════════════════════════════════════════════════════════════
function appData = doOnPolylineAction(appData, ctx, action)
    if strcmp(action, 'start')
        if appData.activeIdx < 1 || isempty(appData.displayImg), return; end
        if appData.compareMode, return; end
        if ~isempty(appData.captureMode), ctx.cb.cancelCapture(); end
        appData.captureMode = 'polyline';
        appData.captureClicks = [];
        ctx.fig.Pointer = 'crosshair';
        ctx.fig.WindowButtonDownFcn = @(s,e) ctx.cb.onPolylineAction('click', s, e);
        ctx.cb.setStatus('Click points to measure path length; double-click to finish (Esc to cancel)');
        return;
    end

    % --- action == 'click' ---
    if ~strcmp(appData.captureMode, 'polyline'), return; end
    cp = ctx.ax.CurrentPoint;
    x = cp(1,1);
    y = cp(1,2);
    if isempty(appData.displayImg), return; end
    [H, W] = size(appData.filteredPixels);
    if x < 0.5 || x > W + 0.5 || y < 0.5 || y > H + 0.5, return; end

    % Check for double-click BEFORE adding the point (avoids duplicate)
    isDoubleClick = isprop(ctx.fig, 'SelectionType') && strcmp(ctx.fig.SelectionType, 'open');

    if isDoubleClick && size(appData.captureClicks, 1) >= 2
        % Double-click finishes -- delegate length computation to package
        pts = appData.captureClicks;
        [tiltDeg, tiltAxis, tiltActive, tiltGeom] = ctx.cb.getTiltState();
        totalDist = emViewer.measurements('polylineLength', pts, tiltDeg, tiltAxis, tiltGeom);

        % Convert to calibrated units if available
        unitStr = 'px';
        if appData.activeIdx >= 1
            imgInfo = appData.images{appData.activeIdx}.metadata.parserSpecific.imageData;
            if imgInfo.calibrated && ~isnan(imgInfo.pixelSize)
                totalDist = totalDist * imgInfo.pixelSize;
                unitStr = imgInfo.pixelUnit;
            end
        end

        nSegs = size(pts, 1) - 1;
        midIdx = max(1, round(size(pts, 1) / 2));
        labelStr = sprintf('%.2f %s', totalDist, unitStr);
        if tiltActive, labelStr = [labelStr, '*']; end
        measClr = ctx.ui.ddMeasColor.Value;
        if isempty(measClr), measClr = ctx.OVERLAY_COLOR; end
        hLabel = text(ctx.ax, pts(midIdx, 1), pts(midIdx, 2), labelStr, ...
            'Color', measClr, 'FontSize', 11, ...
            'FontWeight', 'bold', ...
            'HorizontalAlignment', 'center', ...
            'VerticalAlignment', 'bottom', ...
            'HandleVisibility', 'off');

        % Promote the polyline graphics to a proper measurement
        nLines = nSegs;
        nMarkers = size(pts, 1);
        hLines = gobjects(0, 1);
        if nLines > 0 && numel(appData.overlays.lines) >= nLines
            hLines = [appData.overlays.lines{end-nLines+1:end}];
            appData.overlays.lines(end-nLines+1:end) = [];
        end
        hMarkers = gobjects(0, 1);
        if nMarkers > 0 && numel(appData.overlays.clickMarkers) >= nMarkers
            hMarkers = [appData.overlays.clickMarkers{end-nMarkers+1:end}];
            appData.overlays.clickMarkers(end-nMarkers+1:end) = [];
        end

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

        % Attach click-to-select on every segment and vertex marker.
        for hh = hLines(:)'
            if isvalid(hh)
                hh.HitTest = 'on';
                hh.PickableParts = 'all';
                hh.ButtonDownFcn = @(~,~) ctx.cb.selectMeasurement(midx);
            end
        end
        for hh = hMarkers(:)'
            if isvalid(hh)
                hh.HitTest = 'on';
                hh.PickableParts = 'all';
                hh.ButtonDownFcn = @(~,~) ctx.cb.selectMeasurement(midx);
            end
        end
        if isvalid(hLabel)
            hLabel.HitTest = 'on';
            hLabel.PickableParts = 'all';
            hLabel.ButtonDownFcn = @(~,~) ctx.cb.selectMeasurement(midx);
        end

        ctx.cb.finishCapture();
        tiltTag = '';
        if tiltActive, tiltTag = sprintf(' [tilt %.1f deg]', tiltDeg); end
        ctx.cb.setStatus(sprintf('Polyline: %.2f %s (%d segments)%s -- click to select, Delete to remove', ...
            totalDist, unitStr, nSegs, tiltTag));

        detailStr = sprintf('%d segments', nSegs);
        if tiltActive
            detailStr = sprintf('%s tilt=%.2f deg axis=%s', detailStr, tiltDeg, tiltAxis);
        end
        appData.measurementLog{end+1} = struct( ...
            'type', 'polyline', 'value', totalDist, 'unit', unitStr, ...
            'details', detailStr, ...
            'timestamp', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')));
        return;
    end

    % Single click -- add point
    appData.captureClicks(end+1, :) = [x, y];
    nPts = size(appData.captureClicks, 1);

    hM = line(ctx.ax, x, y, ...
        'Marker', 'o', 'MarkerSize', 6, ...
        'MarkerFaceColor', ctx.OVERLAY_COLOR, ...
        'MarkerEdgeColor', 'none', ...
        'LineStyle', 'none', ...
        'HandleVisibility', 'off');
    appData.overlays.clickMarkers{end+1} = hM;

    if nPts >= 2
        px = appData.captureClicks(nPts-1, 1);
        py = appData.captureClicks(nPts-1, 2);
        hL = line(ctx.ax, [px x], [py y], ...
            'Color', ctx.OVERLAY_COLOR, 'LineWidth', 1.5, 'HandleVisibility', 'off');
        appData.overlays.lines{end+1} = hL;
    end

    ctx.cb.setStatus(sprintf('Point %d placed -- click next or double-click to finish', nPts));
