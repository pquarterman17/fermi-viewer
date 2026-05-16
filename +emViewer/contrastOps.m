function [appData, varargout] = contrastOps(action, appData, ui, cb, varargin)
%CONTRASTOPS  Dispatcher for contrast/histogram/colormap operations.
%
%   Syntax
%   ------
%   appData = emViewer.contrastOps(action, appData, ui, cb)
%   appData = emViewer.contrastOps(action, appData, ui, cb, src)
%
%   Inputs
%   ------
%   action   - string: 'changed' | 'editChanged' | 'auto' | 'reset' |
%              'colormapChanged' | 'colormapPreset' | 'cycleColormap' |
%              'setColormap' | 'setContrast' | 'setTransform' |
%              'transformChanged' | 'invertToggle' | 'toggleHistLog' |
%              'setHistLog' | 'scrollWheelContrast' | 'customColormap'
%   appData  - FermiViewer appData struct (returned, possibly modified)
%   ui       - struct with widget handles: sldLow, sldHigh, sldGamma,
%              efLow, efHigh, efGamma, lblGamma, ddColormap,
%              ddContrastTransform, ddRenderMode, cbInvert, histAx, ax,
%              fig, btnLogHist
%   cb       - struct with callback handles: onContrastChanged,
%              prepareDisplayBuffer, onGammaChanged, setStatus,
%              refreshHistogramMarkers, refreshDisplay,
%              updateHistogram, onInvertToggle, onContrastTransformChanged
%   varargin - optional: src (event source widget)
%
%   Outputs
%   -------
%   appData     - updated appData
%   varargout{1} - result struct (for 'computeFFT', 'getContrastTransform')
%
%   Examples
%   --------
%   appData = emViewer.contrastOps('changed', appData, ui, cb, sldLow);
%   appData = emViewer.contrastOps('auto', appData, ui, cb);

    varargout = {};

    switch action

        % ── Slider moved ────────────────────────────────────────────────
        case 'changed'
            src = [];
            if ~isempty(varargin), src = varargin{1}; end

            if isempty(appData.filteredPixels) || ...
                    isempty(appData.imgHandle) || ~isvalid(appData.imgHandle)
                return;
            end

            lo = ui.sldLow.Value;
            hi = ui.sldHigh.Value;

            if lo >= hi
                span = ui.sldLow.Limits(2) - ui.sldLow.Limits(1);
                eps_ = span * 0.001;
                if ~isempty(src) && isequal(src, ui.sldLow)
                    lo = max(ui.sldLow.Limits(1), hi - eps_);
                    ui.sldLow.Value = lo;
                else
                    hi = min(ui.sldHigh.Limits(2), lo + eps_);
                    ui.sldHigh.Value = hi;
                end
            end

            ui.efLow.Value  = lo;
            ui.efHigh.Value = hi;

            if isempty(appData.displayPixels)
                cb.prepareDisplayBuffer();
            end
            dispImg = emViewer.contrast.applyPipeline( ...
                appData.displayPixels, lo, hi, ...
                appData.contrastTransform, appData.gamma, appData.contrastInvert);
            appData.displayImg = dispImg;
            appData.imgHandle.CData = dispImg;
            appData.contrastWS.setLimits(lo, hi);
            cb.refreshHistogramMarkers();

        % ── Typed edit field changed ─────────────────────────────────────
        %   Returns updated appData. Caller must call onContrastChanged()
        %   AFTER storing the returned appData.
        case 'editChanged'
            src = [];
            if ~isempty(varargin), src = varargin{1}; end

            if isequal(src, ui.efLow)
                v = max(ui.sldLow.Limits(1), min(ui.sldLow.Limits(2), ui.efLow.Value));
                ui.sldLow.Value = v;
                cb.onContrastChanged(ui.sldLow, []);
            elseif isequal(src, ui.efHigh)
                v = max(ui.sldHigh.Limits(1), min(ui.sldHigh.Limits(2), ui.efHigh.Value));
                ui.sldHigh.Value = v;
                cb.onContrastChanged(ui.sldHigh, []);
            elseif isequal(src, ui.efGamma)
                v = max(ui.sldGamma.Limits(1), min(ui.sldGamma.Limits(2), ui.efGamma.Value));
                ui.sldGamma.Value = v;
                ui.lblGamma.Text = 'Gamma';
                % Store new gamma; caller's wrapper applies it then calls refresh
                appData.gamma = v;
            elseif isequal(src, ui.ddRenderMode)
                appData.renderMode = ui.ddRenderMode.Value;
                appData.displayPixels = [];
                if strcmp(appData.renderMode, 'hq')
                    cb.setStatus('Render mode: HQ (DM-style area-averaged downsample).');
                else
                    cb.setStatus('Render mode: Fast (full-res nearest-neighbor).');
                end
            end

        % ── Auto contrast: 2nd/98th percentile ──────────────────────────
        case 'auto'
            if isempty(appData.filteredPixels), return; end

            pLow  = imaging.percentile(appData.filteredPixels(:), 2);
            pHigh = imaging.percentile(appData.filteredPixels(:), 98);

            if pLow >= pHigh
                pLow  = ui.sldLow.Limits(1);
                pHigh = ui.sldHigh.Limits(2);
            end

            ui.sldLow.Value  = pLow;
            ui.sldHigh.Value = pHigh;
            cb.onContrastChanged([], []);
            cb.setStatus(sprintf('Auto contrast: [%.4g, %.4g]', pLow, pHigh));

        % ── Reset contrast to full data range ───────────────────────────
        %   Caller must call onContrastChanged() after storing returned appData.
        case 'reset'
            if isempty(appData.filteredPixels), return; end

            ui.sldLow.Value  = ui.sldLow.Limits(1);
            ui.sldHigh.Value = ui.sldHigh.Limits(2);

            appData.gamma = 1.0;
            ui.sldGamma.Value = 1.0;
            ui.efGamma.Value  = 1.0;
            ui.lblGamma.Text  = 'Gamma';
            appData.contrastWS.setGamma(1.0);
            cb.setStatus('Contrast reset to full range; gamma reset to 1.00.');

        % ── Colormap dropdown changed ────────────────────────────────────
        case 'colormapChanged'
            if appData.activeIdx < 1, return; end
            cmapName = ui.ddColormap.Value;
            colormap(ui.ax, feval(cmapName, 256));

        % ── Colormap preset picker ───────────────────────────────────────
        case 'colormapPreset'
            r = emViewer.display.selectColormapPreset();
            if ~r.selected, return; end
            ui.ddColormap.Value = r.cmapName;
            if ~isempty(ui.ax) && isvalid(ui.ax)
                colormap(ui.ax, feval(r.cmapName, 256));
            end
            cb.setStatus(r.statusMsg);

        % ── Cycle colormap ───────────────────────────────────────────────
        case 'cycleColormap'
            items = ui.ddColormap.Items;
            cur   = ui.ddColormap.Value;
            idx   = find(strcmp(items, cur), 1);
            if isempty(idx), idx = 0; end
            ui.ddColormap.Value = items{mod(idx, numel(items)) + 1};
            cb.onContrastChanged([], []);

        % ── API: set colormap by name ────────────────────────────────────
        case 'setColormap'
            name = varargin{1};
            if ~any(strcmp(name, ui.ddColormap.Items))
                error('FermiViewer:setColormap:unknown', ...
                    'Unknown colormap "%s". Valid: %s', name, strjoin(ui.ddColormap.Items, ', '));
            end
            ui.ddColormap.Value = name;
            cb.onContrastChanged([], []);

        % ── API: set contrast window ─────────────────────────────────────
        case 'setContrast'
            lo = varargin{1};
            hi = varargin{2};
            if isempty(appData.filteredPixels)
                warning('FermiViewer:noImage', 'No image loaded.');
                return;
            end
            if ~isfinite(lo) || ~isfinite(hi) || lo >= hi
                warning('FermiViewer:invalidContrast', ...
                    'Low must be finite and less than High. Values unchanged.');
                return;
            end
            dMin = ui.sldLow.Limits(1);
            dMax = ui.sldHigh.Limits(2);
            loC  = max(dMin, min(dMax, lo));
            hiC  = max(dMin, min(dMax, hi));
            if loC >= hiC
                span = max(eps(dMax), (dMax - dMin) * 1e-6);
                if hi <= dMin
                    loC = dMin; hiC = min(dMax, dMin + span);
                elseif lo >= dMax
                    hiC = dMax; loC = max(dMin, dMax - span);
                else
                    loC = dMin; hiC = dMax;
                end
            end
            ui.sldLow.Value  = loC;
            ui.sldHigh.Value = hiC;
            cb.onContrastChanged([], []);

        % ── API: set contrast transform mode ────────────────────────────
        case 'setTransform'
            mode = varargin{1};
            if ~any(strcmp(mode, ui.ddContrastTransform.Items))
                error('FermiViewer:setContrastTransform:unknown', ...
                    'Unknown transform "%s". Valid: %s', mode, ...
                    strjoin(ui.ddContrastTransform.Items, ', '));
            end
            ui.ddContrastTransform.Value = mode;
            cb.onContrastTransformChanged([], []);

        % ── Transform dropdown changed ───────────────────────────────────
        %   Caller must call onContrastChanged() after storing returned appData.
        case 'transformChanged'
            appData.contrastTransform = ui.ddContrastTransform.Value;
            appData.contrastWS.setTransform(appData.contrastTransform);

        % ── Invert toggle ────────────────────────────────────────────────
        %   Caller must call onContrastChanged() after storing returned appData.
        case 'invertToggle'
            appData.contrastInvert = ui.cbInvert.Value;
            appData.contrastWS.setInvert(appData.contrastInvert);

        % ── Toggle histogram log scale ───────────────────────────────────
        case 'toggleHistLog'
            src = varargin{1};
            appData.histLogScale = src.Value;
            cb.updateHistogram();

        % ── API: set histogram log scale ─────────────────────────────────
        case 'setHistLog'
            tf = varargin{1};
            appData.histLogScale = tf;
            ui.btnLogHist.Value  = tf;
            cb.updateHistogram();

        % ── Scroll wheel over histogram: zoom contrast window ────────────
        case 'scrollWheelContrast'
            evt = varargin{1};
            if isempty(appData.filteredPixels), return; end
            if ~isvalid(ui.histAx), return; end
            figPos = ui.fig.CurrentPoint;
            axPos  = getpixelposition(ui.histAx, true);
            if figPos(1) < axPos(1) || figPos(1) > axPos(1)+axPos(3) || ...
               figPos(2) < axPos(2) || figPos(2) > axPos(2)+axPos(4)
                return;
            end
            lo   = ui.sldLow.Value;
            hi   = ui.sldHigh.Value;
            span = hi - lo;
            step = span * 0.04 * evt.VerticalScrollCount;
            lims = ui.sldLow.Limits;
            gap  = (lims(2) - lims(1)) * 0.001;
            newLo = max(lims(1), lo + step);
            newHi = min(lims(2), hi - step);
            if newHi - newLo < gap, return; end
            ui.sldLow.Value  = newLo;
            ui.sldHigh.Value = newHi;
            cb.onContrastChanged([], []);

        % ── Custom colormap ──────────────────────────────────────────────
        case 'customColormap'
            answer = inputdlg( ...
                {'Color stops (e.g. "0 0 0; 1 0 0; 1 1 1" for black→red→white):'}, ...
                'Custom Colormap', [3 60], {'0 0 0; 1 0 0; 1 1 1'});
            if isempty(answer), return; end
            try
                cmap = emViewer.processing.parseColormap(answer{1});
                if ~isempty(ui.ax) && isvalid(ui.ax)
                    colormap(ui.ax, cmap);
                end
                cb.setStatus('Custom colormap applied.');
            catch ME
                cb.setStatus(['Custom colormap failed: ' ME.message]);
            end

        otherwise
            warning('emViewer:contrastOps:unknownAction', ...
                'Unknown action "%s" — ignored.', action);
    end
end
