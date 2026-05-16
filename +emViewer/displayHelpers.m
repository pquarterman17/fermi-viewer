function [appData, varargout] = displayHelpers(action, appData, ctx, varargin)
%DISPLAYHELPERS  Dispatch table for display/undo/rebuild helpers extracted
%   from FermiViewer.m.
%
%   Syntax
%     appData = emViewer.displayHelpers('refresh',        appData, ctx)
%     appData = emViewer.displayHelpers('undoPop',        appData, ctx)
%     appData = emViewer.displayHelpers('rebuildAxes',    appData, ctx)
%     [appData, result] = emViewer.displayHelpers('lineProfile', appData, ctx, x1, y1, x2, y2)
%     appData = emViewer.displayHelpers('pixelInspector', appData, ctx, px, py)
%     appData = emViewer.displayHelpers('flickerTick',    appData, ctx)
%
%   Inputs
%     action   — one of 'refresh', 'undoPop', 'rebuildAxes', 'lineProfile',
%                'pixelInspector', 'flickerTick'
%     appData  — FermiViewer application state struct
%     ctx      — context struct (see fields below)
%     varargin — action-specific extra arguments
%
%   ctx fields (widgets — handle objects, pass-by-reference)
%     ctx.ax          — image axes
%     ctx.sldLow      — contrast low slider
%     ctx.sldHigh     — contrast high slider
%     ctx.sldGamma    — gamma slider (for completeness)
%     ctx.ddColormap  — colormap dropdown
%     ctx.cbScaleBar  — scale bar checkbox
%     ctx.cbColorbar  — colorbar checkbox
%     ctx.cbMinimap   — minimap checkbox
%     ctx.hColorbar   — current colorbar handle (may be empty)
%     ctx.hMinimap    — current minimap handle (may be empty)
%     ctx.hPixelInspector — pixel inspector axes handle (may be empty)
%     ctx.ui.btnExportProfile — profile export button (lineProfile only)
%
%   ctx callback fields
%     ctx.cb.applyContrastPipeline — @applyContrastPipeline
%     ctx.cb.refreshHistogramMarkers — @refreshHistogramMarkers
%     ctx.cb.updateMinimapRect     — @updateMinimapRect
%     ctx.cb.updateLiveFFT         — @updateLiveFFT
%     ctx.cb.rebuildScaleBar       — @rebuildScaleBar
%     ctx.cb.attachImageContextMenu — @attachImageContextMenu
%     ctx.cb.updateStatusBar       — @updateStatusBar
%     ctx.cb.updateHistogram       — @updateHistogram
%     ctx.cb.setStatus             — @setStatus
%     ctx.cb.displayImage          — @displayImage
%
%   Outputs
%     appData   — updated application state struct
%     varargout — action-specific extra outputs (lineProfile: result struct)
%
%   Examples
%     appData = emViewer.displayHelpers('refresh', appData, ctx);
%     [appData, r] = emViewer.displayHelpers('lineProfile', appData, ctx, 10, 20, 100, 80);

varargout = {};

switch action

    % ────────────────────────────────────────────────────────────────────
    case 'refresh'
    %REFRESH  Re-apply contrast to filteredPixels; update histogram and
    %  CData without resetting zoom.  Called after filter/crop/rotate/undo.
        if isempty(appData.filteredPixels) || isempty(appData.imgHandle) || ...
                ~isvalid(appData.imgHandle)
            return;
        end

        lo = ctx.sldLow.Value;
        hi = ctx.sldHigh.Value;

        % Always rebuild displayPixels — can't cheaply detect value changes
        % at same size (CLAHE, blur, morph, etc.).
        appData.displayPixels = [];
        ui_ = struct('ax', ctx.ax, 'sldLow', ctx.sldLow, 'sldHigh', ctx.sldHigh);
        appData = emViewer.prepareDisplayBuffer(appData, ui_);
        dispImg = ctx.cb.applyContrastPipeline(appData.displayPixels, lo, hi);

        appData.displayImg        = dispImg;
        appData.imgHandle.CData   = dispImg;

        ctx.cb.refreshHistogramMarkers();

        % Update minimap if active
        if ctx.cbMinimap.Value && ~isempty(ctx.hMinimap) && isvalid(ctx.hMinimap)
            ctx.cb.updateMinimapRect();
        end

        % Update live FFT if active
        if ~isempty(appData.liveFFTFig) && isvalid(appData.liveFFTFig)
            ctx.cb.updateLiveFFT();
        end

        % Restore scale bar — position is in image-pixel coords so it must
        % be rebuilt any time filteredPixels changes.
        if ~isempty(ctx.cbScaleBar) && isvalid(ctx.cbScaleBar) && ...
                strcmp(ctx.cbScaleBar.Enable, 'on') && ctx.cbScaleBar.Value
            ctx.cb.rebuildScaleBar();
        end

    % ────────────────────────────────────────────────────────────────────
    case 'undoPop'
    %UNDOPOP  Pop the most recent snapshot and restore it.
        if isempty(appData.undoStack)
            ctx.cb.setStatus('Nothing to undo.');
            return;
        end

        snapshot = appData.undoStack{end};
        appData.undoStack(end)     = [];
        appData.rawPixels          = snapshot{1};
        appData.filteredPixels     = snapshot{2};

        % If dimensions changed (e.g. undoing a rotation), do a full rebuild
        [H2, W2] = size(appData.filteredPixels);
        appData.displayPixels = [];   % always invalidate on undo

        if ~isempty(appData.imgHandle) && isvalid(appData.imgHandle) && ...
                ~isequal(size(appData.imgHandle.CData), [H2 W2])

            lo = ctx.sldLow.Value;
            hi = ctx.sldHigh.Value;
            ui_ = struct('ax', ctx.ax, 'sldLow', ctx.sldLow, 'sldHigh', ctx.sldHigh);
            appData = emViewer.prepareDisplayBuffer(appData, ui_);
            dispImg = ctx.cb.applyContrastPipeline(appData.displayPixels, lo, hi);
            appData.displayImg = dispImg;

            ax = ctx.ax;
            delete(ax.Children);
            cla(ax);
            hImg = imagesc(ax, 'XData', [1 W2], 'YData', [1 H2], 'CData', dispImg);
            appData.imgHandle = hImg;

            ctx.cb.attachImageContextMenu();
            colormap(ax, feval(ctx.ddColormap.Value, 256));
            ax.CLim = [0 1];  ax.YDir = 'reverse';
            axis(ax, 'equal');
            ax.XLim = [0.5, W2+0.5];  ax.YLim = [0.5, H2+0.5];
            ax.XTick = [];  ax.YTick = [];  ax.Toolbar.Visible = 'off';

            if ctx.cbColorbar.Value
                if ~isempty(ctx.hColorbar) && isvalid(ctx.hColorbar)
                    delete(ctx.hColorbar);
                end
                appData.undoPop_hColorbar = colorbar(ax);  % returned for caller
            end

            if ~isempty(ctx.cbScaleBar) && isvalid(ctx.cbScaleBar) && ...
                    strcmp(ctx.cbScaleBar.Enable, 'on') && ctx.cbScaleBar.Value
                ctx.cb.rebuildScaleBar();
            end

        else
            % Same size — cheap path, just reapply contrast
            appData = emViewer.displayHelpers('refresh', appData, ctx);
        end

        ctx.cb.setStatus(sprintf('Undo — %d states remaining', numel(appData.undoStack)));

    % ────────────────────────────────────────────────────────────────────
    case 'rebuildAxes'
    %REBUILDAXES  Rebuild image display after dimension-changing operations
    %  (binning, crop).
        [H, W] = size(appData.filteredPixels);
        lo = ctx.sldLow.Value;
        hi = ctx.sldHigh.Value;

        % Clamp slider limits to new data range
        dMin = min(appData.filteredPixels(:));
        dMax = max(appData.filteredPixels(:));
        if dMax == dMin, dMax = dMin + 1; end
        ctx.sldLow.Limits  = [dMin dMax];
        ctx.sldHigh.Limits = [dMin dMax];
        ctx.sldLow.Value   = max(dMin, min(lo,  dMax));
        ctx.sldHigh.Value  = max(dMin, min(hi,  dMax));

        appData.displayPixels = [];
        ui_ = struct('ax', ctx.ax, 'sldLow', ctx.sldLow, 'sldHigh', ctx.sldHigh);
        appData = emViewer.prepareDisplayBuffer(appData, ui_);
        dispImg = ctx.cb.applyContrastPipeline( ...
            appData.displayPixels, ctx.sldLow.Value, ctx.sldHigh.Value);
        appData.displayImg = dispImg;

        ax = ctx.ax;
        if ~isempty(ax) && isvalid(ax)
            delete(ax.Children);
            cla(ax);
            dr = appData.displayRegion;
            if isempty(dr), dr = [1, 1, W, H]; end
            hImg = imagesc(ax, 'XData', [dr(1) dr(3)], 'YData', [dr(2) dr(4)], ...
                'CData', dispImg);
            try
                hImg.Interpolation = 'nearest';
            catch
            end
            appData.imgHandle = hImg;
            ctx.cb.attachImageContextMenu();
            colormap(ax, feval(ctx.ddColormap.Value, 256));
            ax.CLim = [0 1];  ax.YDir = 'reverse';
            axis(ax, 'equal');
            ax.XLim = [0.5, W+0.5];  ax.YLim = [0.5, H+0.5];
            ax.XTick = [];  ax.YTick = [];  ax.Toolbar.Visible = 'off';
        end

        ctx.cb.updateStatusBar();
        ctx.cb.updateHistogram();
        if ~isempty(ctx.cbScaleBar) && isvalid(ctx.cbScaleBar) && ...
                strcmp(ctx.cbScaleBar.Enable, 'on') && ctx.cbScaleBar.Value
            ctx.cb.rebuildScaleBar();
        end

    % ────────────────────────────────────────────────────────────────────
    case 'lineProfile'
    %LINEPROFILEAPI  Extract a line profile from the active image.
    %   [appData, result] = emViewer.displayHelpers('lineProfile', appData, ctx, x1, y1, x2, y2)
    %   result.dist      — [Nx1] distance vector
    %   result.intensity — [Nx1] interpolated intensity (raw pixel counts)
    %   result.unit      — unit string ('px' when uncalibrated)
        result = struct('dist', [], 'intensity', [], 'unit', 'px');

        if appData.activeIdx < 1 || isempty(appData.filteredPixels)
            warning('FermiViewer:noImage', 'No image loaded.');
            varargout{1} = result;
            return;
        end

        x1 = varargin{1};  y1 = varargin{2};
        x2 = varargin{3};  y2 = varargin{4};

        imgInfo = appData.images{appData.activeIdx}.metadata.parserSpecific.imageData;
        ps = NaN;
        pu = 'px';
        if imgInfo.calibrated && ~isnan(imgInfo.pixelSize)
            ps = imgInfo.pixelSize;
            pu = imgInfo.pixelUnit;
        end

        if ~isnan(ps)
            [dist, intensity] = imaging.lineProfile(appData.filteredPixels, ...
                x1, y1, x2, y2, PixelSize=ps, PixelUnit=pu);
        else
            [dist, intensity] = imaging.lineProfile(appData.filteredPixels, ...
                x1, y1, x2, y2);
        end

        result.dist      = dist;
        result.intensity = intensity;
        result.unit      = pu;

        % Cache so Export CSV becomes available
        appData.lastProfile = result;
        ctx.ui.btnExportProfile.Enable = 'on';

        varargout{1} = result;

    % ────────────────────────────────────────────────────────────────────
    case 'pixelInspector'
    %PIXELINSPECTOR  Update pixel inspector overlay with NxN neighborhood.
        if isempty(ctx.hPixelInspector) || ~isvalid(ctx.hPixelInspector), return; end
        if isempty(appData.filteredPixels), return; end

        px = varargin{1};
        py = varargin{2};

        N     = appData.prefs.pixelInspectorSize;
        halfN = floor(N / 2);
        [H, W] = size(appData.filteredPixels);
        px = round(px);  py = round(py);
        if px < 1 || py < 1 || px > W || py > H, return; end

        % Extract neighborhood with boundary clamping
        rows = max(1, py-halfN):min(H, py+halfN);
        cols = max(1, px-halfN):min(W, px+halfN);
        neighborhood = appData.filteredPixels(rows, cols);

        hpi = ctx.hPixelInspector;
        cla(hpi);
        imagesc(hpi, neighborhood);
        colormap(hpi, gray(256));
        hpi.XTick = [];  hpi.YTick = [];
        axis(hpi, 'image');

        % Overlay text values
        [nR, nC] = size(neighborhood);
        meanVal  = mean(appData.filteredPixels(:));
        for ri = 1:nR
            for ci = 1:nC
                v = neighborhood(ri, ci);
                if v > meanVal
                    tc = [0 0 0];
                else
                    tc = [1 1 1];
                end
                text(hpi, ci, ri, sprintf('%.0f', v), ...
                    'HorizontalAlignment', 'center', 'FontSize', 6, ...
                    'Color', tc, 'HitTest', 'off');
            end
        end

    % ────────────────────────────────────────────────────────────────────
    case 'flickerTick'
    %FLICKERTICK  Swap between flickerState.imgA and .imgB, then redisplay.
        if ~isfield(appData, 'flickerState'), return; end
        try
            fs = appData.flickerState;
            if fs.showA
                appData.filteredPixels = fs.imgA;
            else
                appData.filteredPixels = fs.imgB;
            end
            appData.flickerState.showA = ~fs.showA;
            ctx.cb.displayImage();
        catch
            % Timer may fire after GUI closes — silently swallow
        end

    % ────────────────────────────────────────────────────────────────────
    otherwise
        error('emViewer:displayHelpers:unknownAction', ...
            'Unknown action "%s".', action);

end
end
