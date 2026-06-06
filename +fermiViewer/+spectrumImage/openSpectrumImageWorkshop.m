function api = openSpectrumImageWorkshop(eds, survey, ctx)
%OPENSPECTRUMIMAGEWORKSHOP  Interactive EDS spectrum-image explorer.
%
%   api = fermiViewer.spectrumImage.openSpectrumImageWorkshop(eds, survey, ctx)
%
%   Self-contained uifigure for exploring a decoded EDS hypercube:
%     • LEFT  — the spatial element map. Click a pixel (or click-drag a
%               rectangular ROI) to set the spectrum source.
%     • RIGHT — the spectrum of the selected pixel/ROI (or the sum spectrum).
%               Click-drag horizontally to define an energy window; the map
%               recomputes live for that window.
%   An element drop-down snaps the window to a chosen element's principal
%   X-ray line; a background drop-down toggles linear two-window subtraction.
%
%   Inputs
%   ──────
%   eds    struct  edsData from parser.importBCF; uses .cube [HxWxN],
%                  .energyAxis [Nx1], .elements {symbols}, .elementZ.
%   survey         optional [HxW] SEM reference image (currently informational).
%   ctx    struct  optional, with .setStatus(msg) (used gracefully).
%
%   Output
%   ──────
%   api    struct of handles so headless tests can drive the window without
%          mouse events: .fig, .setWindow(lo,hi), .selectElement(sym),
%          .selectPixel(r,c), .selectROI(r0,c0,r1,c1), .showSum(),
%          .setBackground('none'|'linear'), .getMap(), .getSpectrum(),
%          .getWindow(), .exportMapCSV(path), .exportSpectrumCSV(path),
%          .close().
%
%   See also IMAGING.EDS.ELEMENTMAP, IMAGING.EDS.PIXELSPECTRUM,
%            IMAGING.EDS.LINEENERGY, FERMIVIEWER.SPECTRUMIMAGE.LAUNCH

    arguments
        eds    struct
        survey = []
        ctx    struct = struct()
    end

    cube = eds.cube;
    eax  = eds.energyAxis(:);
    sz   = size(cube);
    if numel(sz) < 3 || isempty(cube)
        error('fermiViewer:spectrumImage:noCube', ...
            'edsData has no spectral cube to explore.');
    end
    H = sz(1); W = sz(2);

    elements = {};
    if isfield(eds, 'elements'), elements = eds.elements; end
    halfWin = 0.085;                 % keV, default ½-window
    beamKV  = Inf;

    % ── State (shared with nested callbacks) ──────────────────────────────
    curWin   = defaultWindow();      % [eLo eHi] keV
    curMap   = [];
    curSpec  = sumSpectrum();        % start on the sum spectrum
    specLabel = 'Sum spectrum';
    bgMode   = 'linear';
    dragX0   = [];
    dragPatch = [];

    % ── Figure / layout ───────────────────────────────────────────────────
    fig = uifigure('Name', 'EDS Spectrum Image', 'Position', [140 110 940 560]);
    gl  = uigridlayout(fig, [1 2], 'ColumnWidth', {'1.2x', '1x'}, 'Padding', [6 6 6 6]);

    mapPanel = uipanel(gl, 'Title', 'Element map'); mapPanel.Layout.Column = 1;
    axMap = axes('Parent', mapPanel);

    right = uigridlayout(gl, [7 2], ...
        'RowHeight', {24, 24, 24, '1x', 26, 26, 18}, ...
        'ColumnWidth', {'1x','1x'}, 'RowSpacing', 6, 'Padding', [4 4 4 4]);
    right.Layout.Column = 2;

    r = 1;
    lbl(right, r, 'Element:');
    ddItems = [{'(custom)'}, elements(:).'];
    ddElem = uidropdown(right, 'Items', ddItems, 'Value', ddItems{1}, ...
        'ValueChangedFcn', @(s,~) onElementChanged(s.Value));
    ddElem.Layout.Row = r; ddElem.Layout.Column = 2;

    r = r + 1;
    lbl(right, r, 'Window lo / hi (keV):');
    r = r + 1;
    spLo = uispinner(right, 'Limits', [min(eax) max(eax)], 'Value', curWin(1), ...
        'Step', 0.05, 'ValueDisplayFormat', '%.3f', ...
        'ValueChangedFcn', @(s,~) onSpinWindow());
    spLo.Layout.Row = r; spLo.Layout.Column = 1;
    spHi = uispinner(right, 'Limits', [min(eax) max(eax)], 'Value', curWin(2), ...
        'Step', 0.05, 'ValueDisplayFormat', '%.3f', ...
        'ValueChangedFcn', @(s,~) onSpinWindow());
    spHi.Layout.Row = r; spHi.Layout.Column = 2;

    r = r + 1;
    specPanel = uipanel(right, 'Title', 'Spectrum (drag to set window)');
    specPanel.Layout.Row = r; specPanel.Layout.Column = [1 2];
    axSpec = axes('Parent', specPanel);

    r = r + 1;
    ddBg = uidropdown(right, 'Items', {'Background: linear', 'Background: none'}, ...
        'Value', 'Background: linear', ...
        'ValueChangedFcn', @(s,~) onBgChanged(s.Value));
    ddBg.Layout.Row = r; ddBg.Layout.Column = 1;
    btnSum = uibutton(right, 'Text', 'Show sum spectrum', ...
        'ButtonPushedFcn', @(~,~) showSumSpectrum());
    btnSum.Layout.Row = r; btnSum.Layout.Column = 2;

    r = r + 1;
    btnMapCSV = uibutton(right, 'Text', 'Export map CSV...', ...
        'ButtonPushedFcn', @(~,~) doExportMapCSV());
    btnMapCSV.Layout.Row = r; btnMapCSV.Layout.Column = 1;
    btnSpecCSV = uibutton(right, 'Text', 'Export spectrum CSV...', ...
        'ButtonPushedFcn', @(~,~) doExportSpecCSV());
    btnSpecCSV.Layout.Row = r; btnSpecCSV.Layout.Column = 2;

    % ── Initial render ─────────────────────────────────────────────────────
    if ~isempty(elements)
        ddElem.Value = elements{1};
        onElementChanged(elements{1});     % sets window + map
    else
        recomputeMap();
    end
    drawSpectrum();
    status(sprintf('Spectrum image %dx%dx%d ready.', H, W, sz(3)));

    % ── API ─────────────────────────────────────────────────────────────────
    api = struct();
    api.fig                = fig;
    api.setWindow          = @(lo, hi) setWindow(lo, hi);
    api.getWindow          = @getWindow;     % NESTED (live curWin), not @() curWin
    api.selectElement      = @(s) onElementChanged(s);
    api.selectPixel        = @(rr, cc) selectPixel(rr, cc);
    api.selectROI          = @(r0, c0, r1, c1) selectROI(r0, c0, r1, c1);
    api.showSum            = @() showSumSpectrum();
    api.setBackground      = @(m) setBackground(m);
    api.getMap             = @getMap;        % NESTED getters: read live state
    api.getSpectrum        = @getSpectrum;
    api.exportMapCSV       = @(p) writeMapCSV(p);
    api.exportSpectrumCSV  = @(p) writeSpecCSV(p);
    api.close              = @() close(fig);

    % ════════════════════════════════════════════════════════════════════════
    %  Nested callbacks / helpers (share this workspace)
    % ════════════════════════════════════════════════════════════════════════
    function m = getMap(),      m = curMap;  end
    function s = getSpectrum(), s = curSpec; end
    function w = getWindow(),   w = curWin;  end

    function w = defaultWindow()
        if isfield(eds, 'elements') && ~isempty(eds.elements)
            e = imaging.eds.lineEnergy(string(eds.elements{1}), BeamKV=beamKV);
            if ~isnan(e), w = [e-halfWin, e+halfWin]; return; end
        end
        lo = max(min(eax), 0.5*(min(eax)+max(eax)) - 0.5);
        w  = [lo, lo + 1.0];
    end

    function s = sumSpectrum()
        s = squeeze(sum(sum(double(cube), 1), 2));
    end

    function setBackground(m)
        m = char(string(m));
        if any(strcmpi(m, {'none','linear'}))
            bgMode = lower(m);
            if strcmpi(bgMode,'linear'), ddBg.Value = 'Background: linear';
            else, ddBg.Value = 'Background: none'; end
            recomputeMap();
        end
    end

    function onBgChanged(val)
        if contains(val, 'none'), bgMode = 'none'; else, bgMode = 'linear'; end
        recomputeMap();
    end

    function setWindow(lo, hi)
        lo = max(min(eax), min(lo, hi));
        hi = min(max(eax), max(lo, hi));
        curWin = [lo hi];
        spLo.Value = lo; spHi.Value = hi;
        recomputeMap();
        drawSpectrum();   % refresh the window patch
    end

    function onSpinWindow()
        setWindow(spLo.Value, spHi.Value);
        ddElem.Value = '(custom)';
    end

    function onElementChanged(sym)
        sym = char(string(sym));
        if strcmp(sym, '(custom)'), return; end
        [e, ~] = imaging.eds.lineEnergy(string(sym), BeamKV=beamKV);
        if isnan(e)
            status(sprintf('No known line for %s.', sym)); return;
        end
        ddElem.Value = sym;
        setWindow(e-halfWin, e+halfWin);
        status(sprintf('%s line at %.3f keV.', sym, e));
    end

    function recomputeMap()
        [curMap, ~] = imaging.eds.elementMap(cube, eax, curWin(1), curWin(2), ...
            Background=bgMode);
        drawMap();
    end

    function drawMap()
        him = imagesc(axMap, curMap);
        axis(axMap, 'image'); colormap(axMap, hot(256));
        cb = colorbar(axMap); cb.Color = [0 0 0]; %#ok<NASGU>
        title(axMap, sprintf('%.3f–%.3f keV (%s bg)', curWin(1), curWin(2), bgMode));
        % Unconditional pixel-pick handler (HitTest on) — see image-click contract.
        him.HitTest = 'on';
        him.PickableParts = 'all';
        him.ButtonDownFcn = @(~,~) onMapClick();
        axMap.ButtonDownFcn = @(~,~) onMapClick();
    end

    function onMapClick()
        cp = axMap.CurrentPoint;
        c = round(cp(1,1)); rr = round(cp(1,2));
        if rr >= 1 && rr <= H && c >= 1 && c <= W
            selectPixel(rr, c);
        end
    end

    function selectPixel(rr, cc)
        rr = round(rr); cc = round(cc);
        if rr < 1 || rr > H || cc < 1 || cc > W, return; end
        curSpec = imaging.eds.pixelSpectrum(cube, rr, cc);
        specLabel = sprintf('Pixel (%d, %d)', rr, cc);
        drawSpectrum();
        status(sprintf('%s: %g total counts.', specLabel, sum(curSpec)));
    end

    function selectROI(r0, c0, r1, c1)
        r0 = max(1,round(min(r0,r1))); r1 = min(H,round(max(r0,r1)));
        c0 = max(1,round(min(c0,c1))); c1 = min(W,round(max(c0,c1)));
        mask = false(H, W); mask(r0:r1, c0:c1) = true;
        curSpec = imaging.eds.pixelSpectrum(cube, mask);
        specLabel = sprintf('ROI [%d:%d, %d:%d]', r0, r1, c0, c1);
        drawSpectrum();
        status(sprintf('%s: %g total counts.', specLabel, sum(curSpec)));
    end

    function showSumSpectrum()
        curSpec = sumSpectrum();
        specLabel = 'Sum spectrum';
        drawSpectrum();
    end

    function drawSpectrum()
        cla(axSpec);
        plot(axSpec, eax, curSpec, 'k-', 'LineWidth', 0.6);
        xlabel(axSpec, 'Energy (keV)'); ylabel(axSpec, 'Counts');
        grid(axSpec, 'on'); title(axSpec, specLabel);
        yl = ylim(axSpec);
        dragPatch = patch(axSpec, ...
            [curWin(1) curWin(2) curWin(2) curWin(1)], ...
            [yl(1) yl(1) yl(2) yl(2)], [0.2 0.5 1], ...
            'FaceAlpha', 0.15, 'EdgeColor', [0.2 0.4 0.9], 'HitTest', 'off');
        axSpec.ButtonDownFcn = @(~,~) onSpecDown();
    end

    function onSpecDown()
        cp = axSpec.CurrentPoint; dragX0 = cp(1,1);
        fig.WindowButtonMotionFcn = @(~,~) onSpecMove();
        fig.WindowButtonUpFcn     = @(~,~) onSpecUp();
    end

    function onSpecMove()
        cp = axSpec.CurrentPoint; x1 = cp(1,1);
        lo = min(dragX0, x1); hi = max(dragX0, x1);
        if isgraphics(dragPatch)
            yl = ylim(axSpec);
            set(dragPatch, 'XData', [lo hi hi lo], 'YData', [yl(1) yl(1) yl(2) yl(2)]);
        end
    end

    function onSpecUp()
        fig.WindowButtonMotionFcn = '';
        fig.WindowButtonUpFcn     = '';
        cp = axSpec.CurrentPoint; x1 = cp(1,1);
        if ~isempty(dragX0) && abs(x1 - dragX0) > 1e-6
            setWindow(dragX0, x1);
            ddElem.Value = '(custom)';
        end
        dragX0 = [];
    end

    function doExportMapCSV()
        [f, p] = uiputfile('*.csv', 'Export element map', 'eds_map.csv');
        if isequal(f, 0), return; end
        writeMapCSV(fullfile(p, f)); status(['Exported map: ' f]);
    end

    function writeMapCSV(path)
        writematrix(curMap, path);
    end

    function doExportSpecCSV()
        [f, p] = uiputfile('*.csv', 'Export spectrum', 'eds_spectrum.csv');
        if isequal(f, 0), return; end
        writeSpecCSV(fullfile(p, f)); status(['Exported spectrum: ' f]);
    end

    function writeSpecCSV(path)
        fid = fopen(path, 'w');
        if fid < 0, error('fermiViewer:spectrumImage:csv', 'Cannot open %s', path); end
        fprintf(fid, 'energy_keV,counts\n');
        n = min(numel(eax), numel(curSpec));
        for i = 1:n
            fprintf(fid, '%.6f,%.6f\n', eax(i), curSpec(i));
        end
        fclose(fid);
    end

    function status(msg)
        if isfield(ctx, 'setStatus')
            try, ctx.setStatus(msg); catch, end
        end
    end
end

% ════════════════════════════════════════════════════════════════════════
function h = lbl(parent, rr, txt)
    h = uilabel(parent, 'Text', txt, 'FontSize', 11);
    h.Layout.Row = rr; h.Layout.Column = 1;
end
