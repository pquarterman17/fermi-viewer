function api = openEELSQuantWorkshop(energyAxis, spectrum, ctx)
%OPENEELSQUANTWORKSHOP  Interactive EELS composition (at%) window.
%
%   api = fermiViewer.eels.openEELSQuantWorkshop(energyAxis, spectrum, ctx)
%
%   Self-contained uifigure for quantitative EELS composition. The user
%   enters the beam energy, collection semi-angle, and one row per element
%   (symbol, shell, onset eV, integration width Δ); the window computes
%   at% via imaging.eels.eelsQuantify (hydrogenic cross-sections) and shows
%   the spectrum with per-element signal/background windows.
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
%
%   Output:
%       api — struct: .fig, .setBeam(E0,beta), .setEdges(cell Nx4),
%             .compute(), .getResult(), .exportCSV(path), .close().
%
%   See also imaging.eels.eelsQuantify, imaging.eels.eelsCrossSection

    arguments
        energyAxis double = []
        spectrum   double = []
        ctx        struct = struct()
    end

    E = energyAxis(:);
    I = spectrum(:);
    lastResult = struct('valid', false);

    fig = uifigure('Name', 'EELS Quantification', 'Position', [180 130 880 540]);
    gl  = uigridlayout(fig, [1 2], 'ColumnWidth', {'1x', 320}, 'Padding', [6 6 6 6]);

    axPanel = uipanel(gl); axPanel.Layout.Column = 1;
    ax = axes('Parent', axPanel);

    ctrl = uigridlayout(gl, [9 2], ...
        'RowHeight', {24, 24, 18, '1x', 28, 16, '1x', 28, 28}, ...
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
    tblResult = uitable(ctrl, 'ColumnName', {'Element','at%','I','σ (m²)'}, ...
        'ColumnEditable', [false false false false]);
    tblResult.Layout.Row = row; tblResult.Layout.Column = [1 2];

    row = row + 1;
    btnCSV = uibutton(ctrl, 'Text', 'Export CSV...', 'ButtonPushedFcn', @(~,~) doExportCSV());
    btnCSV.Layout.Row = row; btnCSV.Layout.Column = [1 2];

    plotSpectrum();
    status('EELS quantification ready — enter edges and Compute.');

    % ── API ──────────────────────────────────────────────────────────────
    api = struct();
    api.fig       = fig;
    api.setBeam   = @(e0, b) setBeam(e0, b);
    api.setEdges  = @(c) setEdges(c);
    api.compute   = @() doCompute();
    api.getResult = @getResult;   % NESTED fn (reads live lastResult); an
                                  % anonymous @() lastResult would capture the
                                  % initial value by value and never update.
    api.exportCSV = @(p) writeCSV(p);
    api.close     = @() close(fig);

    % ── Callbacks (share parent workspace) ───────────────────────────────
    function r = getResult()
        r = lastResult;
    end

    function setBeam(e0, b)
        spE0.Value = e0; spBeta.Value = b;
    end

    function setEdges(c)
        % c: N x 4 cell {element, shell, onset, delta}
        tblEdges.Data = c;
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
        try
            r = imaging.eels.eelsQuantify(E, I, elements, spE0.Value, spBeta.Value);
        catch ME
            status(['Quantification failed: ' ME.message]); return;
        end
        r.valid = true;
        lastResult = r;
        nEl = numel(r.element);
        out = cell(nEl, 4);
        for i = 1:nEl
            out{i,1} = char(r.element(i));
            out{i,2} = sprintf('%.1f', r.atomicPercent(i));
            out{i,3} = sprintf('%.3g', r.intensity(i));
            out{i,4} = sprintf('%.3g', r.sigma(i));
        end
        tblResult.Data = out;
        plotSpectrum(elements);
        comp = strjoin(arrayfun(@(k) sprintf('%s %.1f%%', char(r.element(k)), ...
            r.atomicPercent(k)), 1:nEl, 'UniformOutput', false), ', ');
        status(['Composition: ' comp]);
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
        fprintf(fid, 'element,atomic_percent,intensity,sigma_m2\n');
        for i = 1:numel(lastResult.element)
            fprintf(fid, '%s,%.4f,%.6g,%.6g\n', char(lastResult.element(i)), ...
                lastResult.atomicPercent(i), lastResult.intensity(i), lastResult.sigma(i));
        end
        fclose(fid);
    end

    function plotSpectrum(elements)
        cla(ax);
        if isempty(E)
            text(ax, 0.5, 0.5, 'No spectrum', 'Units', 'normalized', ...
                'HorizontalAlignment', 'center'); return;
        end
        plot(ax, E, I, 'k-', 'LineWidth', 0.6);
        xlabel(ax, 'Energy loss (eV)'); ylabel(ax, 'Intensity');
        grid(ax, 'on');
        if nargin >= 1 && ~isempty(elements)
            hold(ax, 'on');
            yl = ylim(ax);
            for k = 1:numel(elements)
                sw = elements(k).signalWindow;
                patch(ax, [sw(1) sw(2) sw(2) sw(1)], [yl(1) yl(1) yl(2) yl(2)], ...
                    [0.2 0.5 1], 'FaceAlpha', 0.12, 'EdgeColor', 'none');
                xline(ax, elements(k).onsetEV, ':', elements(k).element);
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
