function [appData, outHandles] = captureDispatch(action, appData, ctx, varargin)
%CAPTUREDISPATCH  Unified capture dispatcher extracted from FermiViewer.
%
% Syntax:
%   [appData, outHandles] = emViewer.captureDispatch(action, appData, ctx)
%   [appData, outHandles] = emViewer.captureDispatch(action, appData, ctx, arg1, ...)
%
% Actions:
%   'rectClick'    — onRectClick: accumulate rect corners, execute on 2nd click
%   'captureClick' — onCaptureClick: accumulate point clicks, dispatch by mode
%   'rectROI'      — executeRectROI(xMin, xMax, yMin, yMax)
%   'startCapture' — startTwoClickCapture(mode): arm capture mode for a given mode string
%   'boxZoomDrag'  — onBoxZoomDrag: rubber-band update during drag
%   'boxZoomRelease'— onBoxZoomRelease: apply box-zoom or marquee on drag end
%
% Inputs:
%   action   — char; one of the action strings above
%   appData  — FermiViewer appData struct (modified in-place via output)
%   ctx      — context struct with handles and callbacks (see buildCaptureCtx in FermiViewer.m)
%   varargin — action-specific extra args (e.g. xMin, xMax, yMin, yMax for rectROI;
%              mode string for startCapture)
%
% Outputs:
%   appData    — updated appData
%   outHandles — struct of any newly created graphics handles (may be empty)
%
% Examples:
%   ctx = buildCaptureCtx();
%   appData = emViewer.captureDispatch('rectClick', appData, ctx);
%   appData = emViewer.captureDispatch('startCapture', appData, ctx, 'distance');
%   appData = emViewer.captureDispatch('rectROI', appData, ctx, xMin, xMax, yMin, yMax);

    outHandles = struct();

    switch action
        case 'rectClick'
            appData = doRectClick(appData, ctx);
        case 'captureClick'
            appData = doCaptureClick(appData, ctx);
        case 'rectROI'
            xMin = varargin{1}; xMax = varargin{2};
            yMin = varargin{3}; yMax = varargin{4};
            appData = doExecuteRectROI(xMin, xMax, yMin, yMax, appData, ctx);
        case 'startCapture'
            mode = varargin{1};
            appData = doStartTwoClickCapture(mode, appData, ctx);
        case 'boxZoomDrag'
            appData = doBoxZoomDrag(appData, ctx);
        case 'boxZoomRelease'
            appData = doBoxZoomRelease(appData, ctx);
        otherwise
            error('emViewer:captureDispatch:unknownAction', ...
                'Unknown action: %s', action);
    end
end

% ════════════════════════════════════════════════════════════════════════════
%  onRectClick — rectangular selection handler
% ════════════════════════════════════════════════════════════════════════════
function appData = doRectClick(appData, ctx)
    if ~ismember(appData.captureMode, {'zoom', 'crop', 'savecrop', 'rectROI', 'batchcrop'})
        return;
    end

    cp = ctx.ax.CurrentPoint;
    x  = cp(1, 1);
    y  = cp(1, 2);

    % Clamp to image bounds
    [H, W] = size(appData.filteredPixels);
    x = max(0.5, min(W + 0.5, x));
    y = max(0.5, min(H + 0.5, y));

    appData.captureClicks(end+1, :) = [x, y];

    if size(appData.captureClicks, 1) == 1
        % First click — draw live preview rectangle
        hRect = rectangle(ctx.ax, 'Position', [x y 1 1], ...
            'EdgeColor', ctx.OVERLAY_COLOR, ...
            'LineWidth', 1.5, ...
            'LineStyle', '--', ...
            'HandleVisibility', 'off');
        appData.overlays.clickMarkers{end+1} = hRect;

        % Attach motion callback for live rubber-band
        ctx.fig.WindowButtonMotionFcn = @(~,~) updateRectPreview(hRect, ctx.ax, ...
            appData.captureClicks(1,1), appData.captureClicks(1,2));

        switch appData.captureMode
            case 'zoom'
                ctx.cb.setStatus('Click second corner to zoom... (Esc to cancel)');
            case 'crop'
                ctx.cb.setStatus('Click second corner to crop... (Esc to cancel)');
            case 'savecrop'
                ctx.cb.setStatus('Click second corner to save... (Esc to cancel)');
            case 'rectROI'
                ctx.cb.setStatus('Click second corner for Rect ROI... (Esc to cancel)');
        end

    elseif size(appData.captureClicks, 1) >= 2
        % Both corners collected
        x1 = appData.captureClicks(1, 1);
        y1 = appData.captureClicks(1, 2);
        x2 = appData.captureClicks(2, 1);
        y2 = appData.captureClicks(2, 2);

        mode = appData.captureMode;

        % Clean up preview rectangle and restore callbacks
        ctx.fig.WindowButtonMotionFcn = ctx.cb.onMouseMotion;
        for ci = 1:numel(appData.overlays.clickMarkers)
            h = appData.overlays.clickMarkers{ci};
            if isvalid(h), delete(h); end
        end
        appData.overlays.clickMarkers = {};
        ctx.cb.finishCapture();
        appData.captureMode   = '';
        appData.captureClicks = [];

        % Normalize to [xMin xMax yMin yMax]
        xMin = max(1, floor(min(x1, x2)));
        xMax = min(size(appData.displayImg, 2), ceil(max(x1, x2)));
        yMin = max(1, floor(min(y1, y2)));
        yMax = min(size(appData.displayImg, 1), ceil(max(y1, y2)));

        if xMax - xMin < 2 || yMax - yMin < 2
            ctx.cb.setStatus('Selection too small — cancelled.');
            return;
        end

        switch mode
            case 'zoom'
                ctx.ax.XLim = [xMin - 0.5, xMax + 0.5];
                ctx.ax.YLim = [yMin - 0.5, yMax + 0.5];
                ctx.cb.setStatus(sprintf('Zoomed to [%d:%d, %d:%d]', ...
                    xMin, xMax, yMin, yMax));

            case 'crop'
                ctx.cb.undoPush();
                appData.rawPixels      = appData.rawPixels(yMin:yMax, xMin:xMax);
                appData.filteredPixels = appData.filteredPixels(yMin:yMax, xMin:xMax);
                ctx.cb.refreshDisplay();
                ctx.cb.setStatus(sprintf('Cropped to %dx%d px', ...
                    xMax - xMin + 1, yMax - yMin + 1));

            case 'savecrop'
                ctx.cb.onExportAction('saveCroppedRegion', xMin, xMax, yMin, yMax);

            case 'rectROI'
                appData = doExecuteRectROI(xMin, xMax, yMin, yMax, appData, ctx);

            case 'batchcrop'
                ctx.cb.applyBatchCrop(xMin, xMax, yMin, yMax);
        end
    end
end

% ════════════════════════════════════════════════════════════════════════════
%  onCaptureClick — two-point click accumulator
% ════════════════════════════════════════════════════════════════════════════
function appData = doCaptureClick(appData, ctx)
    if isempty(appData.captureMode)
        return;
    end

    % Get click position in data (image pixel) coordinates
    cp = ctx.ax.CurrentPoint;
    x  = cp(1, 1);
    y  = cp(1, 2);

    % Validate within image bounds
    if isempty(appData.displayImg)
        return;
    end
    [H, W] = size(appData.filteredPixels);
    x = max(0.5, min(W + 0.5, x));
    y = max(0.5, min(H + 0.5, y));

    % Draw click marker
    hMark = line(ctx.ax, x, y, ...
        'Marker',           'o', ...
        'MarkerSize',       6, ...
        'Color',            ctx.OVERLAY_COLOR, ...
        'MarkerFaceColor',  ctx.OVERLAY_COLOR, ...
        'LineStyle',        'none', ...
        'HandleVisibility', 'off');
    appData.overlays.clickMarkers{end+1} = hMark;

    % Handle single-click modes that accumulate without a fixed endpoint
    if strcmp(appData.captureMode, 'diffspot')
        newSpot = [y, x];  % [row, col]
        appData.diffSpots = [appData.diffSpots; newSpot];
        appData.diffWorkshop.model.spots = appData.diffSpots;
        ctx.cb.onDiffractionAction('drawSpots');
        ctx.ui.lblSpotCount.Text = sprintf('%d spots', size(appData.diffSpots, 1));
        return;
    end

    if strcmp(appData.captureMode, 'specnav')
        % Navigate spectrum image pixel — single click, stays active
        col = round(x); row = round(y);
        [Ny, Nx, ~] = size(appData.eelsCube);
        if row >= 1 && row <= Ny && col >= 1 && col <= Nx
            spec = squeeze(double(appData.eelsCube(row, col, :)));
            delete(findobj(ctx.ax, 'Tag', 'specnav_marker'));
            hold(ctx.ax, 'on');
            plot(ctx.ax, col, row, 'r+', 'MarkerSize', 15, 'LineWidth', 2, ...
                'Tag', 'specnav_marker', 'HandleVisibility', 'off');
            hold(ctx.ax, 'off');
            if ~isempty(appData.eelsFig) && isvalid(appData.eelsFig)
                ax2 = findobj(appData.eelsFig, 'Type', 'axes');
                if ~isempty(ax2)
                    cla(ax2(1));
                    plot(ax2(1), appData.eelsEnergyAxis, spec, 'k-', 'LineWidth', 1);
                    xlabel(ax2(1), 'Energy Loss (eV)'); ylabel(ax2(1), 'Counts');
                    title(ax2(1), sprintf('Pixel [%d, %d]', row, col));
                    grid(ax2(1), 'on');
                end
            end
            ctx.cb.setStatus(sprintf('Pixel [%d,%d]: max=%.0f', row, col, max(spec)));
        end
        return;
    end

    if strcmp(appData.captureMode, 'vdf_select')
        % Virtual dark-field — single click selects the FFT spot
        col = round(x); row = round(y);
        idx = appData.activeIdx;
        if idx > 0 && idx <= numel(appData.images)
            pixels = double(appData.images{idx}.metadata.parserSpecific.imageData.pixels);
            try
                vdf = imaging.virtualDarkField(pixels, 'MaskCenter', [row col], 'MaskRadius', 10);
                imagesc(ctx.ax, vdf); colormap(ctx.ax, 'gray'); axis(ctx.ax, 'image');
                title(ctx.ax, sprintf('VDF at [%d,%d]', row, col));
            catch ME
                ctx.cb.setStatus(sprintf('VDF failed: %s', ME.message));
            end
        end
        appData.captureMode = '';
        ctx.fig.WindowButtonDownFcn = ctx.cb.onIdleMouseDown;
        ctx.fig.Pointer = 'arrow';
        return;
    end

    % Accumulate clicks
    appData.captureClicks(end+1, :) = [x, y];

    if size(appData.captureClicks, 1) == 1
        % First click recorded — wait for second
        if strcmp(appData.captureMode, 'scalebar')
            ctx.cb.setStatus('Click other end of scale bar... (Escape to cancel)');
        else
            ctx.cb.setStatus('Click second point on the image... (Escape to cancel)');
        end

    elseif size(appData.captureClicks, 1) >= 2
        % Both clicks collected — execute the measurement
        x1 = appData.captureClicks(1, 1);
        y1 = appData.captureClicks(1, 2);
        x2 = appData.captureClicks(2, 1);
        y2 = appData.captureClicks(2, 2);

        mode = appData.captureMode;

        % Restore normal interaction
        ctx.cb.finishCapture();
        appData.captureMode   = '';
        appData.captureClicks = [];

        switch mode
            case 'profile'
                ctx.cb.executeMeasureProfile(x1, y1, x2, y2);
            case 'boxprofile'
                ctx.cb.executeBoxProfile(x1, y1, x2, y2, appData.boxProfileWidth);
            case 'distance'
                ctx.cb.executeMeasureDistance(x1, y1, x2, y2);
            case 'scalebar'
                ctx.cb.executeScaleBarCalibration(x1, y1, x2, y2);
            case 'dspacing'
                ctx.cb.executeDSpacing(x1, y1, x2, y2);
            case 'roiellipse'
                ctx.cb.executeEllipseROI(x1, y1, x2, y2);
            case 'arrow'
                ctx.cb.executeArrow(x1, y1, x2, y2);
            case 'annotline'
                ctx.cb.executeAnnotLine(x1, y1, x2, y2);
            case 'annotrect'
                ctx.cb.executeAnnotRect(x1, y1, x2, y2);
            case 'annotcircle'
                ctx.cb.executeAnnotCircle(x1, y1, x2, y2);
            case 'lattice'
                appData.captureClicks = [appData.captureClicks; x1, y1; x2, y2];
                ctx.cb.onDiffractionAction('latticeExecute');
            case 'gpa'
                appData.captureClicks = [appData.captureClicks; x1, y1; x2, y2];
                ctx.cb.executeGPA();
            case 'edsprofile'
                p1 = [x1, y1];
                p2 = [x2, y2];
                profile = imaging.edsCompositionProfile(appData.edsAtomicPct, ...
                    appData.edsElements, p1(1), p1(2), p2(1), p2(2));
                profFig = figure('Name', 'Composition Profile');
                ax2 = axes(profFig);
                plot(ax2, profile.distance, profile.atomicPct, 'LineWidth', 1.5);
                xlabel(ax2, sprintf('Distance (%s)', profile.unit));
                ylabel(ax2, 'Atomic %%');
                legend(ax2, appData.edsElements);
                title(ax2, 'EDS Composition Profile');
                grid(ax2, 'on');
                ctx.cb.setStatus('Profile extracted');
            case 'edsroi'
                c1 = max(1, min(round(x1), round(x2)));
                c2 = min(size(appData.edsAtomicPct{1},2), max(round(x1), round(x2)));
                r1 = max(1, min(round(y1), round(y2)));
                r2 = min(size(appData.edsAtomicPct{1},1), max(round(y1), round(y2)));
                msg = 'ROI Composition: ';
                for kq = 1:numel(appData.edsElements)
                    roi = appData.edsAtomicPct{kq}(r1:r2, c1:c2);
                    msg = [msg sprintf('%s=%.1f%% ', appData.edsElements{kq}, mean(roi(:), 'omitnan'))]; %#ok<AGROW>
                end
                ctx.cb.setStatus(msg);
        end
    end
end

% ════════════════════════════════════════════════════════════════════════════
%  executeRectROI — draw persistent rectangle ROI + stats
% ════════════════════════════════════════════════════════════════════════════
function appData = doExecuteRectROI(xMin, xMax, yMin, yMax, appData, ctx)
    % Compute stats and show histogram figure via package helper
    imgInfoROI = [];
    if appData.activeIdx >= 1
        imgInfoROI = appData.images{appData.activeIdx}.metadata.parserSpecific.imageData;
    end
    r = emViewer.rectROI(appData.filteredPixels, xMin, xMax, yMin, yMax, imgInfoROI);

    % Draw persistent rectangle overlay on main image
    measClr = ctx.ui.ddMeasColor.Value;
    if isempty(measClr), measClr = ctx.OVERLAY_COLOR; end
    hRect = rectangle(ctx.ax, 'Position', [xMin yMin xMax-xMin yMax-yMin], ...
        'EdgeColor', measClr, 'LineWidth', 1.5, 'LineStyle', '-', ...
        'HandleVisibility', 'off');

    % Register as a measurement (Delete / marquee / selection support)
    meas.type      = 'rectROI';
    meas.hRect     = hRect;
    meas.hLine     = hRect;
    meas.hP1       = [];
    meas.hP2       = [];
    meas.hText     = [];
    meas.lineColor = measClr;
    meas.xMin      = xMin;  meas.xMax = xMax;
    meas.yMin      = yMin;  meas.yMax = yMax;
    meas.stats     = struct('mean', r.mean, 'std', r.std, ...
                            'min', r.min, 'max', r.max, 'area', r.area);
    midx = numel(appData.overlays.measurements) + 1;
    appData.overlays.measurements{midx} = meas;
    appData.measWorkshop.sync(appData.overlays.measurements);

    hRect.HitTest = 'on';
    hRect.PickableParts = 'visible';
    hRect.ButtonDownFcn = @(~,~) ctx.cb.selectMeasurement(midx);

    appData.measurementLog{end+1} = struct( ...
        'type', 'ROI', 'value', r.mean, 'unit', 'intensity', ...
        'details', sprintf('[%d:%d, %d:%d] mean=%.4g std=%.4g min=%.4g max=%.4g area=%s', ...
            xMin, xMax, yMin, yMax, r.mean, r.std, r.min, r.max, r.areaStr), ...
        'timestamp', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')));

    roiEntry = struct('name', sprintf('ROI_%d', numel(appData.roiList)+1), ...
        'xMin', xMin, 'xMax', xMax, 'yMin', yMin, 'yMax', yMax, ...
        'stats', struct('mean', r.mean, 'std', r.std, 'min', r.min, ...
                        'max', r.max, 'area', r.area), ...
        'areaStr', r.areaStr, 'hRect', hRect);
    appData.roiList{end+1} = roiEntry;

    ctx.cb.setStatus(sprintf('Rect ROI: mean=%.1f std=%.1f min=%.0f max=%.0f area=%s', ...
        r.mean, r.std, r.min, r.max, r.areaStr));
end

% ════════════════════════════════════════════════════════════════════════════
%  startTwoClickCapture — arm capture mode
% ════════════════════════════════════════════════════════════════════════════
function appData = doStartTwoClickCapture(mode, appData, ctx)
    % Cancel any existing capture first
    if ~isempty(appData.captureMode)
        ctx.cb.cancelCapture();
        appData.captureMode   = '';
        appData.captureClicks = [];
    end

    appData.captureMode   = mode;
    appData.captureClicks = [];

    ctx.fig.Pointer = 'crosshair';
    ctx.fig.WindowButtonDownFcn = ctx.cb.onCaptureClick;

    switch mode
        case 'profile'
            ctx.cb.setStatus('Click first point for line profile... (Escape to cancel)');
        case 'boxprofile'
            ctx.cb.setStatus(sprintf('Box profile (width %d px): click first point... (Escape to cancel)', ...
                appData.boxProfileWidth));
        case 'distance'
            ctx.cb.setStatus('Click first point for distance... (Escape to cancel)');
        case 'scalebar'
            ctx.cb.setStatus('Click one end of the scale bar... (Escape to cancel)');
        case 'dspacing'
            ctx.cb.setStatus('Click first FFT spot for d-spacing measurement... (Escape to cancel)');
        case 'roiellipse'
            ctx.cb.setStatus('Click center of ellipse... (Escape to cancel)');
        case 'arrow'
            ctx.cb.setStatus('Click arrow start point... (Escape to cancel)');
        case 'annotline'
            ctx.cb.setStatus('Click line start point... (Escape to cancel)');
        case 'annotrect'
            ctx.cb.setStatus('Click first corner of rectangle... (Escape to cancel)');
        case 'annotcircle'
            ctx.cb.setStatus('Click center of circle... (Escape to cancel)');
    end
end

% ════════════════════════════════════════════════════════════════════════════
%  onBoxZoomDrag — motion handler for drag interactions
% ════════════════════════════════════════════════════════════════════════════
function appData = doBoxZoomDrag(appData, ctx)
    if strcmp(appData.dragAction, 'pan')
        if isempty(appData.panStartXY), return; end
        cp = ctx.ax.CurrentPoint;
        [H, W] = size(appData.rawPixels);
        [newXLim, newYLim] = emViewer.computePanLimits( ...
            appData.panStartXY, cp(1,1:2), appData.panStartLims, H, W);
        ctx.ax.XLim = newXLim;
        ctx.ax.YLim = newYLim;
        return;
    end

    % Zoom / marquee: rubber-band rectangle
    p0 = appData.zoomStartXY;
    if isempty(p0), return; end
    cp = ctx.ax.CurrentPoint;
    x0 = min(p0(1), cp(1,1));  x1 = max(p0(1), cp(1,1));
    y0 = min(p0(2), cp(1,2));  y1 = max(p0(2), cp(1,2));
    w = max(1e-6, x1 - x0);    h = max(1e-6, y1 - y0);
    if isempty(appData.zoomRect) || ~isvalid(appData.zoomRect)
        if w < 10 && h < 10, return; end
        appData.zoomRect = rectangle(ctx.ax, ...
            'Position',        [x0, y0, w, h], ...
            'EdgeColor',       [1 1 0], ...
            'LineStyle',       '--', ...
            'LineWidth',       1, ...
            'FaceColor',       'none', ...
            'PickableParts',   'none', ...
            'HandleVisibility','off');
        return;
    end
    appData.zoomRect.Position = [x0, y0, w, h];
end

% ════════════════════════════════════════════════════════════════════════════
%  onBoxZoomRelease — end of drag; apply box-zoom or marquee selection
% ════════════════════════════════════════════════════════════════════════════
function appData = doBoxZoomRelease(appData, ctx)
    wasPan = strcmp(appData.dragAction, 'pan');
    appData.dragAction = '';

    if wasPan
        appData.panStartXY   = [];
        appData.panStartLims = [];
        ctx.fig.WindowButtonMotionFcn = appData.prevMotionFcn;
        ctx.fig.WindowButtonUpFcn     = appData.prevUpFcn;
        appData.prevMotionFcn = '';
        appData.prevUpFcn     = '';
        if appData.panMode
            ctx.fig.Pointer = 'hand';
        else
            ctx.fig.Pointer = 'arrow';
        end
        return;
    end

    pos = [];
    if ~isempty(appData.zoomRect) && isvalid(appData.zoomRect)
        pos = appData.zoomRect.Position;
        delete(appData.zoomRect);
    end
    appData.zoomRect = [];
    appData.zoomStartXY = [];
    ctx.fig.WindowButtonMotionFcn = appData.prevMotionFcn;
    ctx.fig.WindowButtonUpFcn     = appData.prevUpFcn;
    appData.prevMotionFcn = '';
    appData.prevUpFcn     = '';

    % Apply only if drag covers > 15 data units in both dims
    if isempty(pos) || pos(3) < 15 || pos(4) < 15
        return;
    end
    xMin = pos(1); xMax = pos(1) + pos(3);
    yMin = pos(2); yMax = pos(2) + pos(4);
    if appData.zoomMode
        ctx.ax.XLim = [xMin, xMax];
        ctx.ax.YLim = [yMin, yMax];
    else
        ctx.cb.applyMarqueeSelection(xMin, xMax, yMin, yMax);
    end
end

% ════════════════════════════════════════════════════════════════════════════
%  updateRectPreview — rubber-band rectangle motion helper (local)
% ════════════════════════════════════════════════════════════════════════════
function updateRectPreview(hRect, ax, x0, y0)
    if ~isvalid(hRect), return; end
    cp = ax.CurrentPoint;
    cx = cp(1,1);
    cy = cp(1,2);
    rx = min(x0, cx);
    ry = min(y0, cy);
    rw = abs(cx - x0);
    rh = abs(cy - y0);
    if rw < 0.5, rw = 0.5; end
    if rh < 0.5, rh = 0.5; end
    hRect.Position = [rx ry rw rh];
end
