function api = openGrainWorkshop(image, ctx)
%OPENGRAINWORKSHOP  Open the interactive grain-identification window.
%
%   api = fermiViewer.grains.openGrainWorkshop(image, ctx)
%
%   Self-contained uifigure (like the FFT mask editor) for counting grains
%   and grain boundaries on the current image. Two modes:
%     • Automatic — unsupervised feature clustering (imaging.grains.segmentAuto).
%     • Trained   — paint a few class strokes, train a softmax pixel
%                   classifier (imaging.grains.trainFromScribbles) and
%                   segment (imaging.grains.segmentTrained).
%
%   All mouse/painting wiring lives here on this window's OWN axes, so it
%   never touches FermiViewer's capture-mode system. Returns an `api` struct
%   exposing the callbacks programmatically so headless tests can drive the
%   workshop without real mouse events.
%
%   Inputs:
%       image — [H x W] grayscale image to analyse (FermiViewer's filtered
%               pixels). If empty, the window opens with a notice.
%       ctx   — optional struct with .setStatus(msg), .guiPixelSize(),
%               .guiPixelUnit() (FermiViewer process context). Missing
%               fields degrade gracefully.
%
%   Output:
%       api   — struct: .fig, .model, and function handles .setMode,
%               .run, .paint, .clearScribbles, .getResult, .exportCSV, .close.
%
%   See also fermiViewer.grains.GrainWorkshopModel, imaging.grains.segmentAuto,
%            imaging.grains.trainFromScribbles, imaging.grains.segmentTrained

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

    model = fermiViewer.grains.GrainWorkshopModel(image, ps, pu);

    % Scribble class palette (HSV-ish fixed colours for up to 5 classes).
    classColors = [0.20 0.60 1.00;   % 1 blue
                   1.00 0.40 0.20;   % 2 orange
                   0.30 0.85 0.40;   % 3 green
                   0.90 0.30 0.80;   % 4 magenta
                   0.95 0.85 0.20];  % 5 yellow

    % ════════════════════════════════════════════════════════════════════
    %  Window + layout
    % ════════════════════════════════════════════════════════════════════
    fig = uifigure('Name', 'Grain Identification', 'Position', [180 120 920 600]);
    gl  = uigridlayout(fig, [1 2], 'ColumnWidth', {'1x', 290}, 'Padding', [6 6 6 6]);

    axPanel = uipanel(gl);
    axPanel.Layout.Column = 1;
    ax = axes('Parent', axPanel);
    ax.XTick = []; ax.YTick = [];
    paintOn = false;   % closure flag, toggled by the Paint button

    % ── Control column ───────────────────────────────────────────────────
    ctrl = uigridlayout(gl, [15 2], ...
        'RowHeight', {24,24,24,24,24,24,28,24,24,24,'1x',28,28,24,24}, ...
        'ColumnWidth', {'1x','1x'}, 'RowSpacing', 6, 'Padding', [4 4 4 4]);
    ctrl.Layout.Column = 2;

    row = 1;
    lbl(ctrl, row, 'Mode:');
    ddMode = uidropdown(ctrl, 'Items', {'Automatic','Trained'}, ...
        'ValueChangedFcn', @(~,~) onModeChanged());
    ddMode.Layout.Row = row; ddMode.Layout.Column = 2;

    row = row + 1;
    lbl(ctrl, row, 'Scales (px):');
    efScales = uieditfield(ctrl, 'text', 'Value', num2str(model.scales), ...
        'ValueChangedFcn', @(~,~) onParamsChanged());
    efScales.Layout.Row = row; efScales.Layout.Column = 2;

    row = row + 1;
    lbl(ctrl, row, 'Min area (px):');
    spMinArea = uispinner(ctrl, 'Limits', [1 Inf], 'Value', model.minArea, ...
        'ValueChangedFcn', @(~,~) onParamsChanged());
    spMinArea.Layout.Row = row; spMinArea.Layout.Column = 2;

    % ── Automatic-only ────────────────────────────────────────────────
    row = row + 1;
    lblK = lbl(ctrl, row, 'Clusters (K):');
    spK = uispinner(ctrl, 'Limits', [2 12], 'Value', model.K, ...
        'ValueChangedFcn', @(~,~) onParamsChanged());
    spK.Layout.Row = row; spK.Layout.Column = 2;

    row = row + 1;
    cbSuper = uicheckbox(ctrl, 'Text', 'Superpixels', 'Value', model.superpixels, ...
        'ValueChangedFcn', @(~,~) onParamsChanged());
    cbSuper.Layout.Row = row; cbSuper.Layout.Column = 1;
    spNumSP = uispinner(ctrl, 'Limits', [20 5000], 'Value', model.numSuperpixels, ...
        'Step', 50, 'ValueChangedFcn', @(~,~) onParamsChanged());
    spNumSP.Layout.Row = row; spNumSP.Layout.Column = 2;

    % ── Trained-only ───────────────────────────────────────────────────
    row = row + 1;
    lblClass = lbl(ctrl, row, 'Paint class:');
    spClass = uispinner(ctrl, 'Limits', [1 5], 'Value', model.paintClass, ...
        'ValueChangedFcn', @(~,~) onParamsChanged());
    spClass.Layout.Row = row; spClass.Layout.Column = 2;

    row = row + 1;
    btnPaint = uibutton(ctrl, 'state', 'Text', 'Paint scribbles', ...
        'ValueChangedFcn', @(s,~) onPaintToggle(s));
    btnPaint.Layout.Row = row; btnPaint.Layout.Column = [1 2];

    row = row + 1;
    lblBrush = lbl(ctrl, row, 'Brush (px):');
    spBrush = uispinner(ctrl, 'Limits', [0 50], 'Value', model.brushRadius, ...
        'ValueChangedFcn', @(~,~) onParamsChanged());
    spBrush.Layout.Row = row; spBrush.Layout.Column = 2;

    row = row + 1;
    btnClear = uibutton(ctrl, 'Text', 'Clear scribbles', ...
        'ButtonPushedFcn', @(~,~) doClearScribbles());
    btnClear.Layout.Row = row; btnClear.Layout.Column = [1 2];

    row = row + 1;
    lblClf = lbl(ctrl, row, 'Classifier:');
    ddClf = uidropdown(ctrl, 'Items', {'Softmax','Forest'}, ...
        'ValueChangedFcn', @(~,~) onParamsChanged());
    ddClf.Layout.Row = row; ddClf.Layout.Column = 2;

    % ── Results readout ──────────────────────────────────────────────────
    row = row + 1;
    taResults = uitextarea(ctrl, 'Editable', 'off', 'Value', {'No analysis yet.'});
    taResults.Layout.Row = row; taResults.Layout.Column = [1 2];

    % ── Run + export ───────────────────────────────────────────────────
    row = row + 1;
    btnRun = uibutton(ctrl, 'Text', 'Run', 'ButtonPushedFcn', @(~,~) doRun());
    btnRun.Layout.Row = row; btnRun.Layout.Column = [1 2];

    row = row + 1;
    btnCSV = uibutton(ctrl, 'Text', 'Export CSV...', 'ButtonPushedFcn', @(~,~) doExportCSV());
    btnCSV.Layout.Row = row; btnCSV.Layout.Column = [1 2];

    row = row + 1;
    btnPNG = uibutton(ctrl, 'Text', 'Save overlay...', 'ButtonPushedFcn', @(~,~) doSaveOverlay());
    btnPNG.Layout.Row = row; btnPNG.Layout.Column = [1 2];

    % ── Mouse wiring on this window's own axes ──────────────────────────
    ax.ButtonDownFcn = @(~,~) onAxesDown();

    drawBase();
    onModeChanged();      % set initial control visibility
    status('Grain workshop ready.');

    % ════════════════════════════════════════════════════════════════════
    %  Headless / programmatic API
    % ════════════════════════════════════════════════════════════════════
    api = struct();
    api.fig            = fig;
    api.model          = model;
    api.setMode        = @(m) setMode(m);
    api.setClassifier  = @(t) setClassifier(t);
    api.setSuperpixels = @(tf) setSuperpixels(tf);
    api.run            = @() doRun();
    api.paint          = @(x,y) apiPaint(x, y);
    api.clearScribbles = @() doClearScribbles();
    api.getResult      = @() model.result;
    api.exportCSV      = @(p) imaging.grains.exportGrainCSV(model.result, Filename=p);
    api.close          = @() close(fig);

    % ════════════════════════════════════════════════════════════════════
    %  Callbacks (closures over model + UI handles)
    % ════════════════════════════════════════════════════════════════════
    function onModeChanged()
        if string(ddMode.Value) == "Trained"
            model.mode = "trained";
        else
            model.mode = "auto";
        end
        isAuto = model.mode == "auto";
        setRowEnable([lblK, spK, cbSuper, spNumSP], isAuto);
        setRowEnable([lblClass, spClass, btnPaint, lblBrush, spBrush, btnClear, lblClf, ddClf], ~isAuto);
        if isAuto && ~isempty(btnPaint.Value) && btnPaint.Value
            btnPaint.Value = false; paintOn = false;
        end
    end

    function onParamsChanged()
        sc = str2num(efScales.Value); %#ok<ST2NM>  intentional vector parse
        if ~isempty(sc) && all(sc > 0)
            model.scales = sc;
        else
            efScales.Value = num2str(model.scales);   % reject bad input
        end
        model.minArea     = spMinArea.Value;
        model.K           = spK.Value;
        model.superpixels    = logical(cbSuper.Value);
        model.numSuperpixels = spNumSP.Value;
        model.paintClass  = spClass.Value;
        model.brushRadius = spBrush.Value;
        model.classifierType = lower(string(ddClf.Value));
    end

    function onPaintToggle(src)
        paintOn = logical(src.Value);
    end

    function onAxesDown()
        if ~paintOn || model.mode ~= "trained", return; end
        paintCurrent();
        fig.WindowButtonMotionFcn = @(~,~) paintCurrent();
        fig.WindowButtonUpFcn     = @(~,~) endPaint();
    end

    function endPaint()
        fig.WindowButtonMotionFcn = '';
        fig.WindowButtonUpFcn     = '';
    end

    function paintCurrent()
        cp = ax.CurrentPoint;
        model.paintAt(cp(1,1), cp(1,2));
        drawScribbles();
    end

    function apiPaint(x, y)
        model.paintAt(x, y);
        drawScribbles();
    end

    function doClearScribbles()
        model.clearScribbles();
        drawBase();
        status('Scribbles cleared.');
    end

    function doRun()
        if isempty(model.image)
            status('No image to analyse.'); return;
        end
        onParamsChanged();
        try
            if model.mode == "auto"
                lab = imaging.grains.segmentAuto(model.image, ...
                    K=model.K, Scales=model.scales, MinArea=model.minArea, ...
                    Superpixels=model.superpixels, NumSuperpixels=model.numSuperpixels);
            else
                if ~model.hasScribbles() || numel(unique(model.labelMask(model.labelMask>0))) < 2
                    status('Paint at least 2 classes before running Trained mode.');
                    return;
                end
                model.model = imaging.grains.trainFromScribbles(model.image, ...
                    model.labelMask, Scales=model.scales, Classifier=model.classifierType);
                lab = imaging.grains.segmentTrained(model.image, model.model, ...
                    BoundaryClass=model.boundaryClass, MinArea=model.minArea);
            end
            model.labels = lab;
            model.result = imaging.grains.grainStats(lab, model.image, ...
                PixelSize=model.pixelSize, PixelUnit=model.pixelUnit, MinArea=model.minArea);
            drawResult();
            updateResultsText();
            status(sprintf('Found %d grains, %d boundary segments.', ...
                model.result.numGrains, model.result.numBoundarySegments));
        catch ME
            status(['Grain run failed: ' ME.message]);
        end
    end

    function doExportCSV()
        if ~isfield(model.result, 'numGrains')
            status('Run an analysis before exporting.'); return;
        end
        [f, p] = uiputfile('*.csv', 'Export grain measurements', 'grains.csv');
        if isequal(f, 0), return; end
        imaging.grains.exportGrainCSV(model.result, Filename=fullfile(p, f));
        status(sprintf('Exported %d grains to %s', model.result.numGrains, f));
    end

    function doSaveOverlay()
        if isempty(model.labels)
            status('Run an analysis before saving the overlay.'); return;
        end
        [f, p] = uiputfile({'*.png';'*.tif'}, 'Save grain overlay', 'grains_overlay.png');
        if isequal(f, 0), return; end
        bnd = [];
        if isfield(model.result, 'boundaryMask'), bnd = model.result.boundaryMask; end
        rgb = imaging.grains.labelOverlay(model.labels, BaseImage=model.image, Boundary=bnd);
        imwrite(rgb, fullfile(p, f));
        status(['Overlay saved: ' f]);
    end

    % ── Drawing helpers ──────────────────────────────────────────────────
    function drawBase()
        cla(ax);
        if isempty(model.image)
            text(ax, 0.5, 0.5, 'No image', 'Units', 'normalized', ...
                'HorizontalAlignment', 'center');
            return;
        end
        imagesc(ax, model.image);
        colormap(ax, gray(256));
        axis(ax, 'image'); ax.XTick = []; ax.YTick = [];
        drawScribbles();
    end

    function drawScribbles()
        delete(findobj(ax, 'Tag', 'grainScribble'));
        [xy, cls] = model.scribblePoints();
        hold(ax, 'on');
        for c = unique(cls)'
            m = cls == c;
            col = classColors(min(c, size(classColors,1)), :);
            scatter(ax, xy(m,1), xy(m,2), 8, col, 'filled', ...
                'MarkerEdgeColor', 'none', 'Tag', 'grainScribble');
        end
        hold(ax, 'off');
    end

    function drawResult()
        if isempty(model.labels), return; end
        bnd = [];
        if isfield(model.result, 'boundaryMask'), bnd = model.result.boundaryMask; end
        rgb = imaging.grains.labelOverlay(model.labels, BaseImage=model.image, ...
            Boundary=bnd, Alpha=0.45);
        cla(ax);
        image(ax, rgb);
        axis(ax, 'image'); ax.XTick = []; ax.YTick = [];
        drawScribbles();
    end

    function updateResultsText()
        r = model.result;
        lines = { ...
            sprintf('Grains:            %d', r.numGrains), ...
            sprintf('Boundary segs:     %d', r.numBoundarySegments), ...
            sprintf('Boundary length:   %g px', r.boundaryLengthPx) };
        if ~isnan(model.pixelSize) && model.pixelSize > 0 && r.numGrains > 0
            lines{end+1} = sprintf('Mean diameter:     %.3g %s', ...
                mean(r.diameterCalibrated), model.pixelUnit);
            lines{end+1} = sprintf('Boundary length:   %.4g %s', ...
                r.boundaryLengthCalibrated, model.pixelUnit);
        elseif r.numGrains > 0
            lines{end+1} = sprintf('Mean diameter:     %.3g px', mean(r.equivDiameterPx));
        end
        taResults.Value = lines;
    end

    function setMode(m)
        m = lower(string(m));
        if m == "trained"
            ddMode.Value = 'Trained';
        else
            ddMode.Value = 'Automatic';
        end
        onModeChanged();
    end

    function setClassifier(t)
        if lower(string(t)) == "forest"
            ddClf.Value = 'Forest';
        else
            ddClf.Value = 'Softmax';
        end
        onParamsChanged();
    end

    function setSuperpixels(tf)
        cbSuper.Value = logical(tf);
        onParamsChanged();
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

function setRowEnable(handles, tf)
    state = matlab.lang.OnOffSwitchState(tf);
    for h = handles
        h.Enable = state;
    end
end
