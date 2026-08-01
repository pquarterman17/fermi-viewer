function api = openEELSQuantWorkshop(energyAxis, spectrum, ctx, cube)
%OPENEELSQUANTWORKSHOP  Interactive EELS composition (at%) window.
%
%   api = fermiViewer.eels.openEELSQuantWorkshop(energyAxis, spectrum, ctx)
%   api = fermiViewer.eels.openEELSQuantWorkshop(energyAxis, spectrum, ctx, cube)
%
%   Self-contained uifigure for quantitative EELS composition. The user
%   enters the beam energy, collection semi-angle, and one row per element
%   (symbol, shell, onset eV, integration width Δ); the window computes
%   at% via one of two Methods, selected from the Method dropdown:
%
%     Window integration (default) — imaging.eels.eelsQuantify (hydrogenic
%       partial cross-sections), showing the spectrum with per-element
%       signal/background windows.
%     Model fit — imaging.eels.eelsFitEdges, a joint power-law background
%       plus hydrogenic edge-shape fit that separates OVERLAPPING edges
%       (Mn-L/Fe-L class) window integration mis-assigns. Overlays the
%       fitted model, background, and per-edge components on the spectrum
%       plot, and reports the reduced chi-squared (status line + table).
%
%   The result table's "± at%" column shows the 1-sigma uncertainty on
%   at% — Poisson-propagated (imaging.eels.eelsAtomicSigma) for window
%   integration, or delta-method-propagated from the fit's amplitudeSigma
%   for model fit — and renders blank (never "NaN") when that uncertainty
%   is unavailable (older cached results, degenerate fits).
%
%   When a spectrum-image cube is supplied, a "Composition maps" button
%   computes per-pixel at% maps via imaging.eels.eelsQuantifyMap (window
%   integration) or imaging.eels.eelsFitEdgesMap (model fit), matching the
%   selected Method, and shows them in a tiled figure (one map per element).
%
%   Pre-edge background windows are auto-derived as [onset−54, onset−4] eV
%   (the standard ~50 eV pre-edge fit just below the edge); the signal
%   window is [onset, onset+Δ]. Returns an `api` struct so headless tests
%   can drive it without dialogs.
%
%   Inputs:
%       energyAxis — [N x 1] energy-loss axis (eV), increasing.
%       spectrum   — [N x 1] core-loss intensity.
%       ctx        — optional struct with .setStatus(msg) (graceful).
%       cube       — optional [Ny x Nx x N] spectrum image; enables
%                    per-pixel composition maps.
%
%   Output:
%       api — struct: .fig, .setBeam(E0,beta), .setEdges(cell Nx4),
%             .setMethod('Window integration'|'Model fit'), .compute(),
%             .getResult(), .computeMaps(), .getMapResult(),
%             .exportCSV(path), .close(), and the advanced/testing hook
%             .renderResult(r, method) — renders a precomputed result
%             struct without calling the analysis function, used to
%             exercise the sigma-fallback rendering path with a
%             synthetic/degenerate result.
%
%   See also imaging.eels.eelsQuantify, imaging.eels.eelsQuantifyMap,
%            imaging.eels.eelsCrossSection, imaging.eels.eelsFitEdges,
%            imaging.eels.eelsFitEdgesMap, imaging.eels.eelsAtomicSigma

    arguments
        energyAxis double = []
        spectrum   double = []
        ctx        struct = struct()
        cube       {mustBeNumeric} = []
    end

    E = energyAxis(:);
    I = spectrum(:);
    hasCube = ~isempty(cube) && ndims(cube) == 3;
    lastResult = struct('valid', false);
    lastMapResult = struct('valid', false);
    mapFig = [];

    fig = uifigure('Name', 'EELS Quantification', 'Position', [180 130 880 540]);
    gl  = uigridlayout(fig, [1 2], 'ColumnWidth', {'1x', 320}, 'Padding', [6 6 6 6]);

    axPanel = uipanel(gl); axPanel.Layout.Column = 1;
    ax = axes('Parent', axPanel);

    ctrl = uigridlayout(gl, [10 2], ...
        'RowHeight', {24, 24, 24, 18, '1x', 28, 16, '1x', 28, 28}, ...
        'ColumnWidth', {'1x','1x'}, 'RowSpacing', 6, 'Padding', [4 4 4 4]);
    ctrl.Layout.Column = 2;

    row = 1;
    lbl(ctrl, row, 'Beam E0 (kV):');
    spE0 = uispinner(ctrl, 'Limits', [20 400], 'Value', 200, 'Step', 20);
    spE0.Layout.Row = row; spE0.Layout.Column = 2;

    row = row + 1;
    lbl(ctrl, row, 'β (mrad):');
    spBeta = uispinner(ctrl, 'Limits', [0.5 200], 'Value', 10, 'Step', 1);
    spBeta.Layout.Row = row; spBeta.Layout.Column = 2;

    row = row + 1;
    lbl(ctrl, row, 'Method:');
    ddMethod = uidropdown(ctrl, 'Items', {'Window integration', 'Model fit'}, ...
        'Value', 'Window integration', 'ValueChangedFcn', @(~,~) onMethodChanged());
    ddMethod.Layout.Row = row; ddMethod.Layout.Column = 2;

    row = row + 1;
    lblE = uilabel(ctrl, 'Text', 'Edges (element, shell, onset eV, Δ eV):', 'FontSize', 11);
    lblE.Layout.Row = row; lblE.Layout.Column = [1 2];

    row = row + 1;
    tblEdges = uitable(ctrl, ...
        'ColumnName', {'Element','Shell','Onset','Δ'}, ...
        'ColumnEditable', [true true true true], ...
        'ColumnFormat', {'char', {'K','L'}, 'numeric', 'numeric'}, ...
        'Data', {'C','K',284,100; 'O','K',532,100; '','K',[],100; '','K',[],100});
    tblEdges.Layout.Row = row; tblEdges.Layout.Column = [1 2];

    row = row + 1;
    btnCompute = uibutton(ctrl, 'Text', 'Compute at%', 'ButtonPushedFcn', @(~,~) doCompute());
    btnCompute.Layout.Row = row; btnCompute.Layout.Column = [1 2];

    row = row + 1;
    lblR = uilabel(ctrl, 'Text', 'Composition:', 'FontSize', 11);
    lblR.Layout.Row = row; lblR.Layout.Column = [1 2];

    row = row + 1;
    tblResult = uitable(ctrl, ...
        'ColumnName', {'Element','at%','± at%','I','σ (m²)'}, ...
        'ColumnEditable', [false false false false false]);
    tblResult.Layout.Row = row; tblResult.Layout.Column = [1 2];

    row = row + 1;
    btnCSV = uibutton(ctrl, 'Text', 'Export CSV...', 'ButtonPushedFcn', @(~,~) doExportCSV());
    btnCSV.Layout.Row = row; btnCSV.Layout.Column = [1 2];

    row = row + 1;
    btnMaps = uibutton(ctrl, 'Text', 'Composition maps', ...
        'Enable', onOff(hasCube), ...
        'Tooltip', 'Per-pixel at% maps from the spectrum image', ...
        'ButtonPushedFcn', @(~,~) doComputeMaps());
    btnMaps.Layout.Row = row; btnMaps.Layout.Column = [1 2];

    plotSpectrum();
    status('EELS quantification ready — enter edges and Compute.');

    % ── API ──────────────────────────────────────────────────────────────
    api = struct();
    api.fig       = fig;
    api.setBeam   = @(e0, b) setBeam(e0, b);
    api.setEdges  = @(c) setEdges(c);
    api.setMethod = @(m) setMethod(m);
    api.compute   = @() doCompute();
    api.getResult = @getResult;   % NESTED fn (reads live lastResult); an
                                  % anonymous @() lastResult would capture the
                                  % initial value by value and never update.
    api.computeMaps  = @() doComputeMaps();
    api.getMapResult = @getMapResult;   % NESTED fn — same live-read reason.
    api.exportCSV = @(p) writeCSV(p);
    api.renderResult = @(r, method) renderResult(r, collectEdges(), method);
    api.close     = @() closeAll();

    % Clean up the maps figure if the main window is closed interactively
    fig.DeleteFcn = @(~,~) closeMapFig();

    % ── Callbacks (share parent workspace) ───────────────────────────────
    function r = getResult()
        r = lastResult;
    end

    function r = getMapResult()
        r = lastMapResult;
    end

    function closeMapFig()
        if ~isempty(mapFig) && isvalid(mapFig)
            close(mapFig);
        end
        mapFig = [];
    end

    function closeAll()
        closeMapFig();
        if isvalid(fig), close(fig); end
    end

    function doComputeMaps()
        if ~hasCube, status('No spectrum image available.'); return; end
        elements = collectEdges();
        if numel(elements) < 2
            status('Enter at least two complete edge rows (element + onset + Δ).');
            return;
        end
        method = ddMethod.Value;
        try
            if strcmp(method, 'Model fit')
                r = imaging.eels.eelsFitEdgesMap(cube, E, elements, ...
                    spE0.Value, spBeta.Value);
            else
                r = imaging.eels.eelsQuantifyMap(cube, E, elements, ...
                    spE0.Value, spBeta.Value);
            end
        catch ME
            status(['Map quantification failed: ' ME.message]); return;
        end
        r.valid = true;
        lastMapResult = r;

        % One tile per element, shared 0-100 at% colour scale
        closeMapFig();
        nEl = numel(r.element);
        mapFig = figure('Name', 'EELS composition maps', 'NumberTitle', 'off');
        tl = tiledlayout(mapFig, 'flow', 'TileSpacing', 'compact');
        for i = 1:nEl
            axi = nexttile(tl);
            imagesc(axi, r.atomicPercent(:, :, i));
            axis(axi, 'image');
            clim(axi, [0 100]);
            colorbar(axi);
            title(axi, sprintf('%s at%%', char(r.element(i))));
        end
        status(sprintf('Composition maps computed for %d elements (%s).', nEl, method));
    end

    function setBeam(e0, b)
        spE0.Value = e0; spBeta.Value = b;
    end

    function setEdges(c)
        % c: N x 4 cell {element, shell, onset, delta}
        tblEdges.Data = c;
    end

    function setMethod(m)
        ddMethod.Value = m;
        onMethodChanged();   % mirror the ValueChangedFcn a real user triggers
    end

    function onMethodChanged()
        % Switching Method mid-session must not leave a stale overlay (or
        % stale per-element windows) from the previous mode on the plot.
        plotSpectrum();
    end

    function elements = collectEdges()
        elements = struct('element', {}, 'shell', {}, 'Z', {}, ...
            'onsetEV', {}, 'signalWindow', {}, 'bgWindow', {});
        data = tblEdges.Data;
        for r = 1:size(data, 1)
            sym = strtrim(char(string(data{r,1})));
            onset = data{r,3};
            delta = data{r,4};
            if isempty(sym) || isempty(onset) || isnan(onset) || isempty(delta) || isnan(delta)
                continue;
            end
            k = numel(elements) + 1;
            elements(k).element      = sym;
            elements(k).shell        = string(data{r,2});
            elements(k).Z            = symbolToZ(sym);
            elements(k).onsetEV      = onset;
            elements(k).signalWindow = [onset, onset + delta];
            elements(k).bgWindow     = [max(min(E), onset - 54), onset - 4];
        end
    end

    function doCompute()
        if isempty(E) || isempty(I), status('No spectrum loaded.'); return; end
        elements = collectEdges();
        if numel(elements) < 2
            status('Enter at least two complete edge rows (element + onset + Δ).');
            return;
        end
        method = ddMethod.Value;
        try
            if strcmp(method, 'Model fit')
                r = imaging.eels.eelsFitEdges(E, I, elements, spE0.Value, spBeta.Value);
            else
                r = imaging.eels.eelsQuantify(E, I, elements, spE0.Value, spBeta.Value);
            end
        catch ME
            status(['Quantification failed: ' ME.message]); return;
        end
        renderResult(r, elements, method);
    end

    function renderResult(r, elements, method)
        % Shared table/plot/status rendering for BOTH Methods, and for the
        % advanced .renderResult() testing hook (a precomputed/synthetic r,
        % bypassing the analysis call — used to exercise the sigma-fallback
        % path without needing to contrive a degenerate physics input).
        isModelFit = strcmp(method, 'Model fit');
        r.valid  = true;
        r.method = method;
        nEl = numel(r.element);
        atPctSigma = resolveAtPctSigma(r, method, nEl);
        r.atPctSigmaDisplay = atPctSigma;
        lastResult = r;

        out = cell(nEl, 5);
        for i = 1:nEl
            out{i,1} = char(r.element(i));
            out{i,2} = sprintf('%.1f', r.atomicPercent(i));
            out{i,3} = formatOptional(atPctSigma(i), '%.1f');
            if isModelFit
                out{i,4} = sprintf('%.3g', r.amplitude(i));
                out{i,5} = sprintf('%.3g', r.reducedChi2);
            else
                out{i,4} = sprintf('%.3g', r.intensity(i));
                out{i,5} = sprintf('%.3g', r.sigma(i));
            end
        end
        if isModelFit
            tblResult.ColumnName = {'Element','at%','± at%','Amplitude','χ²_r'};
        else
            tblResult.ColumnName = {'Element','at%','± at%','I','σ (m²)'};
        end
        tblResult.Data = out;

        if isModelFit && isfield(r, 'model')
            plotSpectrum(elements, r);
        else
            plotSpectrum(elements);
        end

        comp = strjoin(arrayfun(@(k) sprintf('%s %.1f%%', char(r.element(k)), ...
            r.atomicPercent(k)), 1:nEl, 'UniformOutput', false), ', ');
        if isModelFit && isfield(r, 'reducedChi2')
            status(sprintf('Composition (model fit, chi2_r=%.3g): %s', r.reducedChi2, comp));
        else
            status(['Composition: ' comp]);
        end
    end

    function doExportCSV()
        if ~lastResult.valid, status('Compute a composition before exporting.'); return; end
        [f, p] = uiputfile('*.csv', 'Export EELS composition', 'eels_composition.csv');
        if isequal(f, 0), return; end
        writeCSV(fullfile(p, f));
        status(['Exported composition: ' f]);
    end

    function writeCSV(path)
        if ~lastResult.valid, return; end
        fid = fopen(path, 'w');
        if fid < 0, error('eels:csv', 'Cannot open %s', path); end
        isModelFit = isfield(lastResult, 'method') && strcmp(lastResult.method, 'Model fit');
        sigmaCol = lastResult.atPctSigmaDisplay;
        if isModelFit
            fprintf(fid, 'element,atomic_percent,atomic_percent_sigma,amplitude,reduced_chi2\n');
            for i = 1:numel(lastResult.element)
                fprintf(fid, '%s,%.4f,%s,%.6g,%.6g\n', char(lastResult.element(i)), ...
                    lastResult.atomicPercent(i), formatOptional(sigmaCol(i), '%.6g'), ...
                    lastResult.amplitude(i), lastResult.reducedChi2);
            end
        else
            fprintf(fid, 'element,atomic_percent,atomic_percent_sigma,intensity,sigma_m2\n');
            for i = 1:numel(lastResult.element)
                fprintf(fid, '%s,%.4f,%s,%.6g,%.6g\n', char(lastResult.element(i)), ...
                    lastResult.atomicPercent(i), formatOptional(sigmaCol(i), '%.6g'), ...
                    lastResult.intensity(i), lastResult.sigma(i));
            end
        end
        fclose(fid);
    end

    function plotSpectrum(elements, fitResult)
        cla(ax);
        if isempty(E)
            text(ax, 0.5, 0.5, 'No spectrum', 'Units', 'normalized', ...
                'HorizontalAlignment', 'center'); return;
        end
        plot(ax, E, I, 'k-', 'LineWidth', 0.6);
        xlabel(ax, 'Energy loss (eV)'); ylabel(ax, 'Intensity');
        grid(ax, 'on');
        hasElements = nargin >= 1 && ~isempty(elements);
        hasFit = nargin >= 2 && ~isempty(fitResult) && isfield(fitResult, 'model');
        if hasElements || hasFit
            hold(ax, 'on');
            if hasElements
                yl = ylim(ax);
                for k = 1:numel(elements)
                    sw = elements(k).signalWindow;
                    patch(ax, [sw(1) sw(2) sw(2) sw(1)], [yl(1) yl(1) yl(2) yl(2)], ...
                        [0.2 0.5 1], 'FaceAlpha', 0.12, 'EdgeColor', 'none');
                    xline(ax, elements(k).onsetEV, ':', elements(k).element);
                end
            end
            if hasFit
                % Dashed background + per-edge components, solid model —
                % all tagged so a re-run or a Method switch (onMethodChanged
                % calls plotSpectrum() with no overlay) clears them via the
                % cla(ax) above rather than stacking on top of the last fit.
                plot(ax, E, fitResult.background, 'b:', 'LineWidth', 1.0, ...
                    'Tag', 'eelsFitOverlay');
                nEdges = numel(fitResult.element);
                cmap = lines(max(nEdges, 1));
                for k = 1:nEdges
                    plot(ax, E, fitResult.edgeCurves(:, k), '--', 'Color', cmap(k,:), ...
                        'LineWidth', 1.0, 'Tag', 'eelsFitOverlay');
                end
                plot(ax, E, fitResult.model, 'r-', 'LineWidth', 1.4, ...
                    'Tag', 'eelsFitOverlay');
            end
            hold(ax, 'off');
        end
    end

    function status(msg)
        if isfield(ctx, 'setStatus')
            try
                ctx.setStatus(msg);
            catch
            end
        end
    end
end

% ════════════════════════════════════════════════════════════════════════
%  Local helpers (file-scope)
% ════════════════════════════════════════════════════════════════════════
function h = lbl(parent, r, txt)
    h = uilabel(parent, 'Text', txt, 'FontSize', 11);
    h.Layout.Row = r; h.Layout.Column = 1;
end

function s = onOff(tf)
    if tf, s = 'on'; else, s = 'off'; end
end

function s = formatOptional(v, fmt)
%FORMATOPTIONAL  Render a numeric value with `fmt`, or '' if v is empty or
%   non-finite. Shared guard so an unavailable/degenerate uncertainty (a
%   missing atomicPercentSigma field, an older cached result predating it,
%   or a NaN/Inf entry) renders as a blank cell instead of erroring or
%   printing the literal text "NaN".
    if isempty(v) || ~isfinite(v)
        s = '';
    else
        s = sprintf(fmt, v);
    end
end

function sigmaPct = resolveAtPctSigma(r, method, nEl)
%RESOLVEATPCTSIGMA  Pick/derive the at%-uncertainty vector to render for
%   the current Method, defaulting to all-NaN (rendered blank by
%   formatOptional) when the source field is missing or empty.
    if strcmp(method, 'Model fit')
        if isfield(r, 'amplitude') && isfield(r, 'amplitudeSigma') && ~isempty(r.amplitudeSigma)
            sigmaPct = atPctSigmaFromAmplitude(r.amplitude, r.amplitudeSigma);
        else
            sigmaPct = nan(1, nEl);
        end
    else
        if isfield(r, 'atomicPercentSigma') && ~isempty(r.atomicPercentSigma)
            sigmaPct = r.atomicPercentSigma;
        else
            sigmaPct = nan(1, nEl);
        end
    end
end

function sigmaPct = atPctSigmaFromAmplitude(amplitude, amplitudeSigma)
%ATPCTSIGMAFROMAMPLITUDE  Derive an at%-uncertainty display value from the
%   model fit's per-edge amplitude and amplitudeSigma
%   (imaging.eels.eelsFitEdges), using the SAME delta-method Jacobian as
%   imaging.eels.eelsAtomicSigma: at%_i = 100*a_i/sum(a), so
%       var(at%_i) = 100^2 * sum_j J_ij^2 * var(a_j),
%       J_ij = (delta_ij - a_i/S)/S,  S = sum(a).
%   Amplitudes are treated as independent (eelsFitEdges does not return
%   their covariance) — the same simplification the function documents for
%   its own r-exponent uncertainty. This is presentation-only derived math
%   for the workshop's table/CSV rendering; it does not modify
%   imaging.eels.eelsFitEdges itself.
    a  = double(amplitude(:));
    sA = double(amplitudeSigma(:));
    M  = numel(a);
    S  = sum(a);
    if isempty(a) || ~isfinite(S) || S <= 0 || numel(sA) ~= M || any(~isfinite(sA))
        sigmaPct = nan(1, M);
        return;
    end
    frac   = a / S;
    jacMat = (eye(M) - frac) / S;
    varAt  = sum((jacMat .^ 2) .* (sA(:)' .^ 2), 2);
    varAt(varAt < 0) = 0;
    sigmaPct = 100 * sqrt(varAt)';
end

function Z = symbolToZ(sym)
%   Atomic number from element symbol (1..92), base MATLAB. Z is used only
%   for forward-compatibility in eelsCrossSection (reserved); a miss returns 1.
    syms = ["H","He","Li","Be","B","C","N","O","F","Ne","Na","Mg","Al","Si", ...
        "P","S","Cl","Ar","K","Ca","Sc","Ti","V","Cr","Mn","Fe","Co","Ni","Cu", ...
        "Zn","Ga","Ge","As","Se","Br","Kr","Rb","Sr","Y","Zr","Nb","Mo","Tc","Ru", ...
        "Rh","Pd","Ag","Cd","In","Sn","Sb","Te","I","Xe","Cs","Ba","La","Ce","Pr", ...
        "Nd","Pm","Sm","Eu","Gd","Tb","Dy","Ho","Er","Tm","Yb","Lu","Hf","Ta","W", ...
        "Re","Os","Ir","Pt","Au","Hg","Tl","Pb","Bi","Po","At","Rn","Fr","Ra","Ac", ...
        "Th","Pa","U"];
    idx = find(strcmpi(syms, sym), 1);
    if isempty(idx), Z = 1; else, Z = idx; end
end
