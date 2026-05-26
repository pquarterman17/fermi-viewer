function api = openAtomColumnWorkshop(image, ctx)
%OPENATOMCOLUMNWORKSHOP  Open the interactive atom-column analysis window.
%
%   api = fermiViewer.atomcolumns.openAtomColumnWorkshop(image, ctx)
%
%   Self-contained uifigure (like the grain workshop) for HR(S)TEM
%   atomic-column analysis:
%     1. Detect + sub-pixel fit columns (imaging.atoms.detectColumns +
%        fitGaussian2D).
%     2. Group into sublattices by intensity (imaging.atoms.assignSublattice).
%     3. Peak-pair-analysis strain vs the average lattice
%        (imaging.atoms.findLatticeVectors + peakPairStrain).
%
%   All mouse wiring lives on this window's OWN axes, so it never touches
%   FermiViewer's capture-mode system. Returns an `api` struct exposing the
%   callbacks so headless tests can drive it without real mouse events.
%
%   Inputs:
%       image — [H x W] grayscale image (FermiViewer's filtered pixels). If
%               empty the window opens with a notice.
%       ctx   — optional struct with .setStatus(msg), .guiPixelSize(),
%               .guiPixelUnit(); missing fields degrade gracefully.
%
%   Output:
%       api   — struct: .fig, .model, and handles .detect, .computeStrain,
%               .setOverlay, .setPolarity, .getResult, .exportCSV, .close.
%
%   See also fermiViewer.atomcolumns.AtomColumnWorkshopModel,
%            imaging.atoms.peakPairStrain

    arguments
        image double = []
        ctx   struct = struct()
    end

    % ── Calibration from ctx (graceful) ─────────────────────────────────
    ps = NaN; pu = "px";
    if isfield(ctx, 'guiPixelSize')
        v = ctx.guiPixelSize();
        if ~isempty(v) && v > 0, ps = v; end
    end
    if isfield(ctx, 'guiPixelUnit')
        u = ctx.guiPixelUnit();
        if ~isempty(u) && strlength(string(u)) > 0, pu = string(u); end
    end

    model = fermiViewer.atomcolumns.AtomColumnWorkshopModel(image, ps, pu);

    subColors = [0.20 0.60 1.00; 1.00 0.55 0.15; 0.30 0.85 0.40; 0.90 0.30 0.80];

    % ════════════════════════════════════════════════════════════════════
    %  Window + layout
    % ════════════════════════════════════════════════════════════════════
    fig = uifigure('Name', 'Atom Columns', 'Position', [170 110 940 620]);
    gl  = uigridlayout(fig, [1 2], 'ColumnWidth', {'1x', 280}, 'Padding', [6 6 6 6]);

    axPanel = uipanel(gl); axPanel.Layout.Column = 1;
    ax = axes('Parent', axPanel);
    ax.XTick = []; ax.YTick = [];

    ctrl = uigridlayout(gl, [12 2], ...
        'RowHeight', {24,24,24,24,24,28,24,28,24,'1x',28,28}, ...
        'ColumnWidth', {'1x','1x'}, 'RowSpacing', 6, 'Padding', [4 4 4 4]);
    ctrl.Layout.Column = 2;

    row = 1;
    lbl(ctrl, row, 'Polarity:');
    ddPol = uidropdown(ctrl, 'Items', {'Bright','Dark'}, ...
        'ValueChangedFcn', @(~,~) onParamsChanged());
    ddPol.Layout.Row = row; ddPol.Layout.Column = 2;

    row = row + 1;
    lbl(ctrl, row, 'Pre-smooth σ:');
    spSigma = uispinner(ctrl, 'Limits', [0.5 10], 'Value', model.sigma, ...
        'Step', 0.5, 'ValueChangedFcn', @(~,~) onParamsChanged());
    spSigma.Layout.Row = row; spSigma.Layout.Column = 2;

    row = row + 1;
    lbl(ctrl, row, 'Threshold:');
    spThr = uispinner(ctrl, 'Limits', [0 1], 'Value', model.threshold, ...
        'Step', 0.05, 'ValueChangedFcn', @(~,~) onParamsChanged());
    spThr.Layout.Row = row; spThr.Layout.Column = 2;

    row = row + 1;
    lbl(ctrl, row, 'Min spacing (px):');
    spSep = uispinner(ctrl, 'Limits', [2 200], 'Value', model.minSep, ...
        'ValueChangedFcn', @(~,~) onParamsChanged());
    spSep.Layout.Row = row; spSep.Layout.Column = 2;

    row = row + 1;
    lbl(ctrl, row, 'Fit window (px):');
    spWin = uispinner(ctrl, 'Limits', [3 30], 'Value', model.winRadius, ...
        'ValueChangedFcn', @(~,~) onParamsChanged());
    spWin.Layout.Row = row; spWin.Layout.Column = 2;

    row = row + 1;
    btnDetect = uibutton(ctrl, 'Text', 'Detect + Fit', 'ButtonPushedFcn', @(~,~) doDetect());
    btnDetect.Layout.Row = row; btnDetect.Layout.Column = [1 2];

    row = row + 1;
    lbl(ctrl, row, 'Sublattices:');
    spSub = uispinner(ctrl, 'Limits', [1 4], 'Value', model.numSublattices, ...
        'ValueChangedFcn', @(~,~) onParamsChanged());
    spSub.Layout.Row = row; spSub.Layout.Column = 2;

    row = row + 1;
    btnStrain = uibutton(ctrl, 'Text', 'Strain (PPA)', 'ButtonPushedFcn', @(~,~) doStrain());
    btnStrain.Layout.Row = row; btnStrain.Layout.Column = [1 2];

    row = row + 1;
    lbl(ctrl, row, 'Overlay:');
    ddOverlay = uidropdown(ctrl, ...
        'Items', {'Markers','Sublattice','εxx','εyy','εxy','Rotation'}, ...
        'ValueChangedFcn', @(~,~) onOverlayChanged());
    ddOverlay.Layout.Row = row; ddOverlay.Layout.Column = 2;

    row = row + 1;
    taResults = uitextarea(ctrl, 'Editable', 'off', 'Value', {'No analysis yet.'});
    taResults.Layout.Row = row; taResults.Layout.Column = [1 2];

    row = row + 1;
    btnCSV = uibutton(ctrl, 'Text', 'Export CSV...', 'ButtonPushedFcn', @(~,~) doExportCSV());
    btnCSV.Layout.Row = row; btnCSV.Layout.Column = [1 2];

    row = row + 1;
    btnPNG = uibutton(ctrl, 'Text', 'Save overlay...', 'ButtonPushedFcn', @(~,~) doSaveOverlay());
    btnPNG.Layout.Row = row; btnPNG.Layout.Column = [1 2];

    drawBase();
    status('Atom-column workshop ready.');

    % ════════════════════════════════════════════════════════════════════
    %  Headless / programmatic API
    % ════════════════════════════════════════════════════════════════════
    api = struct();
    api.fig           = fig;
    api.model         = model;
    api.detect        = @() doDetect();
    api.computeStrain = @() doStrain();
    api.setOverlay    = @(o) setOverlay(o);
    api.setPolarity   = @(p) setPolarity(p);
    api.getResult     = @() packResult();
    api.exportCSV     = @(p) writeCSV(p);
    api.close         = @() close(fig);

    % ════════════════════════════════════════════════════════════════════
    %  Callbacks (closures over model + UI handles)
    % ════════════════════════════════════════════════════════════════════
    function onParamsChanged()
        model.polarity   = lower(string(ddPol.Value));
        model.sigma      = spSigma.Value;
        model.threshold  = spThr.Value;
        model.minSep     = spSep.Value;
        model.winRadius  = spWin.Value;
        model.numSublattices = spSub.Value;
    end

    function onOverlayChanged()
        model.overlay = overlayKey(ddOverlay.Value);
        updateOverlay();
    end

    function doDetect()
        if isempty(model.image), status('No image to analyse.'); return; end
        onParamsChanged();
        try
            det = imaging.atoms.detectColumns(model.image, Sigma=model.sigma, ...
                Threshold=model.threshold, MinSeparation=model.minSep, ...
                Polarity=model.polarity);
            if isempty(det.positions)
                status('No columns detected — lower the threshold or adjust σ.');
                return;
            end
            fit = imaging.atoms.fitGaussian2D(model.image, det.positions, ...
                WinRadius=model.winRadius, Polarity=model.polarity);
            model.positions  = fit.positions;
            model.amplitude  = fit.amplitude;
            model.meanRsq    = mean(fit.rsquared, 'omitnan');
            model.sublattice = imaging.atoms.assignSublattice(fit.amplitude, model.numSublattices);
            model.lattice    = imaging.atoms.findLatticeVectors(fit.positions);
            model.strain     = struct('valid', false);
            if model.overlay ~= "markers" && model.overlay ~= "sublattice"
                model.overlay = "markers"; ddOverlay.Value = 'Markers';
            end
            updateOverlay();
            updateResultsText();
            status(sprintf('Detected %d columns (median R²=%.3f).', ...
                size(model.positions,1), model.meanRsq));
        catch ME
            status(['Detect failed: ' ME.message]);
        end
    end

    function doStrain()
        if ~model.hasColumns(), status('Detect columns first.'); return; end
        try
            if ~isfield(model.lattice, 'valid') || ~model.lattice.valid
                model.lattice = imaging.atoms.findLatticeVectors(model.positions);
            end
            if ~model.lattice.valid
                status('Could not resolve a lattice — need a cleaner column set.');
                return;
            end
            model.strain = imaging.atoms.peakPairStrain(model.positions, ...
                RefVectors=[model.lattice.a1; model.lattice.a2], ...
                Origin=model.lattice.origin);
            if ~model.strain.valid, status('PPA strain failed.'); return; end
            model.overlay = "exx"; ddOverlay.Value = 'εxx';
            updateOverlay();
            updateResultsText();
            status(sprintf('Strain vs average lattice — median εxx=%.3f%%, εyy=%.3f%%.', ...
                100*median(model.strain.exx,'omitnan'), 100*median(model.strain.eyy,'omitnan')));
        catch ME
            status(['Strain failed: ' ME.message]);
        end
    end

    function doExportCSV()
        if ~model.hasColumns(), status('Detect columns before exporting.'); return; end
        [f, p] = uiputfile('*.csv', 'Export atom columns', 'atom_columns.csv');
        if isequal(f, 0), return; end
        writeCSV(fullfile(p, f));
        status(sprintf('Exported %d columns to %s', size(model.positions,1), f));
    end

    function doSaveOverlay()
        if ~model.hasColumns(), status('Detect columns before saving.'); return; end
        [f, p] = uiputfile({'*.png';'*.tif'}, 'Save overlay', 'atom_columns.png');
        if isequal(f, 0), return; end
        exportgraphics(ax, fullfile(p, f));
        status(['Overlay saved: ' f]);
    end

    % ── Drawing ──────────────────────────────────────────────────────────
    function drawBase()
        cla(ax);
        if isempty(model.image)
            text(ax, 0.5, 0.5, 'No image', 'Units', 'normalized', ...
                'HorizontalAlignment', 'center');
            return;
        end
        imagesc(ax, model.image); colormap(ax, gray(256));
        axis(ax, 'image'); ax.XTick = []; ax.YTick = [];
    end

    function updateOverlay()
        drawBase();
        if ~model.hasColumns(), return; end
        hold(ax, 'on');
        switch model.overlay
            case "markers"
                scatter(ax, model.positions(:,1), model.positions(:,2), 18, ...
                    [1 0.2 0.2], 'o', 'LineWidth', 1, 'Tag', 'atomOverlay');
            case "sublattice"
                for c = 1:max(model.sublattice)
                    m = model.sublattice == c;
                    col = subColors(min(c, size(subColors,1)), :);
                    scatter(ax, model.positions(m,1), model.positions(m,2), 22, ...
                        col, 'filled', 'MarkerEdgeColor', 'none', 'Tag', 'atomOverlay');
                end
            otherwise   % a strain component
                vals = strainValues(model.overlay);
                if isempty(vals), hold(ax, 'off'); return; end
                good = ~isnan(vals);
                scatter(ax, model.positions(good,1), model.positions(good,2), 26, ...
                    vals(good), 'filled', 'Tag', 'atomOverlay');
                colormap(ax, divergingMap(256));
                cmax = pct95(abs(vals(good)));   % base-MATLAB percentile (no Stats Toolbox)
                if ~(cmax > 0), cmax = 1; end
                clim(ax, [-cmax cmax]);
                cb = colorbar(ax); cb.Color = [0.85 0.85 0.85];
        end
        hold(ax, 'off');
    end

    function vals = strainValues(key)
        vals = [];
        if ~model.hasStrain(), return; end
        switch key
            case "exx",      vals = model.strain.exx;
            case "eyy",      vals = model.strain.eyy;
            case "exy",      vals = model.strain.exy;
            case "rotation", vals = model.strain.rotation;
        end
    end

    function updateResultsText()
        n = size(model.positions, 1);
        lines = {sprintf('Columns:        %d', n)};
        if isfield(model.lattice, 'spacing') && ~isnan(model.lattice.spacing)
            sp = model.lattice.spacing;
            if ~isnan(model.pixelSize) && model.pixelSize > 0
                lines{end+1} = sprintf('NN spacing:     %.3g %s', sp*model.pixelSize, model.pixelUnit);
            else
                lines{end+1} = sprintf('NN spacing:     %.3g px', sp);
            end
        end
        if ~isnan(model.meanRsq)
            lines{end+1} = sprintf('Median fit R²:   %.3f', model.meanRsq);
        end
        if model.hasStrain()
            lines{end+1} = sprintf('εxx (median):    %.3f %%', 100*median(model.strain.exx,'omitnan'));
            lines{end+1} = sprintf('εyy (median):    %.3f %%', 100*median(model.strain.eyy,'omitnan'));
            lines{end+1} = sprintf('εxy (median):    %.3f %%', 100*median(model.strain.exy,'omitnan'));
        end
        taResults.Value = lines;
    end

    % ── API setters ──────────────────────────────────────────────────────
    function setOverlay(o)
        key = lower(string(o));
        map = ["markers","Markers";"sublattice","Sublattice";"exx","εxx"; ...
               "eyy","εyy";"exy","εxy";"rotation","Rotation"];
        i = find(map(:,1) == key, 1);
        if isempty(i), return; end
        ddOverlay.Value = char(map(i,2));
        onOverlayChanged();
    end

    function setPolarity(p)
        if lower(string(p)) == "dark", ddPol.Value = 'Dark'; else, ddPol.Value = 'Bright'; end
        onParamsChanged();
    end

    function r = packResult()
        r = struct('positions', model.positions, 'amplitude', model.amplitude, ...
            'sublattice', model.sublattice, 'lattice', model.lattice, ...
            'strain', model.strain, 'meanRsq', model.meanRsq);
    end

    function writeCSV(path)
        n = size(model.positions, 1);
        if n == 0, return; end
        hasS = model.hasStrain();
        fid = fopen(path, 'w');
        if fid < 0, error('atomcolumns:csv', 'Cannot open %s for writing.', path); end
        fprintf(fid, 'x_px,y_px,amplitude,sublattice,exx,eyy,exy,rotation_rad\n');
        for i = 1:n
            if hasS
                fprintf(fid, '%.4f,%.4f,%.6g,%d,%.6g,%.6g,%.6g,%.6g\n', ...
                    model.positions(i,1), model.positions(i,2), model.amplitude(i), ...
                    model.sublattice(i), model.strain.exx(i), model.strain.eyy(i), ...
                    model.strain.exy(i), model.strain.rotation(i));
            else
                fprintf(fid, '%.4f,%.4f,%.6g,%d,,,,\n', ...
                    model.positions(i,1), model.positions(i,2), model.amplitude(i), ...
                    model.sublattice(i));
            end
        end
        fclose(fid);
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
%  Local helpers (file-scope, no closure)
% ════════════════════════════════════════════════════════════════════════
function h = lbl(parent, r, txt)
    h = uilabel(parent, 'Text', txt);
    h.Layout.Row = r; h.Layout.Column = 1;
end

function key = overlayKey(displayValue)
    switch string(displayValue)
        case "Markers",    key = "markers";
        case "Sublattice", key = "sublattice";
        case "εxx",        key = "exx";
        case "εyy",        key = "eyy";
        case "εxy",        key = "exy";
        case "Rotation",   key = "rotation";
        otherwise,         key = "markers";
    end
end

function v = pct95(x)
%   95th percentile via sorting (no Statistics Toolbox).
    x = x(~isnan(x));
    if isempty(x), v = 0; return; end
    xs = sort(x(:));
    v = xs(max(1, ceil(0.95 * numel(xs))));
end

function cmap = divergingMap(n)
%   Blue-white-red diverging colormap (for signed strain), pure base MATLAB.
    if nargin < 1, n = 256; end
    h = floor(n/2);
    up = linspace(0, 1, h)';
    lower = [up, up, ones(h,1)];           % blue -> white
    dn = linspace(1, 0, n-h)';
    upper = [ones(n-h,1), dn, dn];          % white -> red
    cmap = [lower; upper];
end
