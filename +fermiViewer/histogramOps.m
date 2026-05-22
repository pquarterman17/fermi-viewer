function histogramOps(action, histAx, appData, ui, cb, varargin)
%HISTOGRAMOPS  Histogram drawing and interactive-drag operations.
%
%   Syntax
%   ------
%   emViewer.histogramOps('update',   histAx, appData, ui, cb)
%   emViewer.histogramOps('click',    histAx, appData, ui, cb)
%   emViewer.histogramOps('startDrag',histAx, appData, ui, cb, which)
%   emViewer.histogramOps('markers',  histAx, appData, ui, cb)
%
%   Inputs
%   ------
%   action   - string: 'update' | 'click' | 'startDrag' | 'markers'
%   histAx   - axes handle for the histogram panel
%   appData  - FermiViewer appData struct (read-only here)
%   ui       - struct with widget handles: sldLow, sldHigh, sldGamma, fig
%   cb       - struct: onContrastChanged(src,~), onGammaChanged(~,~),
%              refreshHistogramMarkers()
%   varargin - optional arg for 'startDrag': which = 'lo'|'hi'|'bc'|'gamma'

    switch action

        % ── Redraw histogram bars ────────────────────────────────────────
        case 'update'
            if isempty(appData.rawPixels)
                cla(histAx);
                return;
            end

            [counts, edges] = histcounts(double(appData.rawPixels(:)), 256);
            binCenters = (edges(1:end-1) + edges(2:end)) / 2;

            displayCounts = counts;
            if appData.histLogScale
                displayCounts = log10(counts + 1);
            end

            cla(histAx);
            bar(histAx, binCenters, displayCounts, 1, ...
                'FaceColor', [0.5 0.5 0.5], ...
                'EdgeColor', 'none', ...
                'FaceAlpha', 0.8);

            if edges(end) > edges(1)
                histAx.XLim = [edges(1), edges(end)];
            end
            yMax = max(displayCounts);
            if yMax > 0
                histAx.YLim = [0, yMax * 1.05];
            end

            histAx.XTick = [];
            histAx.YTick = [];
            histAx.FontSize = 8;
            histAx.Box = 'on';
            histAx.Toolbar.Visible = 'off';

            if ~isempty(appData.filteredPixels)
                cb.refreshHistogramMarkers();
            end

        % ── Click on histogram axes: start drag (startDrag stays in FV) ──
        case 'click'
            if isempty(appData.filteredPixels), return; end
            cp  = histAx.CurrentPoint;
            px  = cp(1,1);
            lo  = ui.sldLow.Value;
            hi  = ui.sldHigh.Value;
            span = max(hi - lo, eps);

            xSpan   = diff(histAx.XLim);
            edgeTol = max(0.08 * span, 0.04 * xSpan);

            dLo = abs(px - lo);
            dHi = abs(px - hi);
            if hi > lo
                midX = lo + span * 0.5^(1/appData.gamma);
                dMid = abs(px - midX);
            else
                dMid = Inf;
            end

            if px > lo + edgeTol && px < hi - edgeTol && ...
                    dLo > edgeTol && dHi > edgeTol && dMid > edgeTol
                cb.startHistDrag('bc');
                return;
            end

            [~, closest] = min([dLo, dHi, dMid]);
            targets = {'lo', 'hi', 'gamma'};
            cb.startHistDrag(targets{closest});

        % ── Refresh contrast marker lines ────────────────────────────────
        case 'markers'
            if isempty(appData.filteredPixels), return; end
            if isempty(histAx) || ~isvalid(histAx), return; end

            delete(findobj(histAx, 'Tag', 'histMarker'));

            emViewer.drawHistogramOverlay( ...
                histAx, ...
                ui.sldLow.Value, ui.sldHigh.Value, ...
                appData.gamma, ...
                appData.contrastTransform, ...
                appData.contrastInvert, ...
                appData.rawPixels);

        otherwise
            warning('emViewer:histogramOps:unknownAction', ...
                'Unknown action "%s" — ignored.', action);
    end
end
