function appData = processActions(action, appData, ctx)
%PROCESSACTIONS  Dispatcher for FermiViewer process/analysis callbacks.
%
% Syntax
%   appData = emViewer.processActions(action, appData, ctx)
%
% Inputs
%   action  — string key identifying the operation
%   appData — viewer state struct (may be modified and returned)
%   ctx     — struct of UI handles and callback function handles:
%               ctx.fig, ctx.ax, ctx.sldLow, ctx.sldHigh,
%               ctx.ddColormap, ctx.cbScaleBar, ctx.cbColorbar,
%               ctx.btnMacroRecord, ctx.BTN_TOOL, ctx.OVERLAY_COLOR,
%               ctx.undoPush, ctx.refreshDisplay, ctx.displayImage,
%               ctx.rebuildAxesForNewSize, ctx.setStatus,
%               ctx.guiPixelSize, ctx.guiPixelUnit,
%               ctx.rebuildScaleBar, ctx.updateHistogram,
%               ctx.updateStatusBar, ctx.prepareDisplayBuffer,
%               ctx.applyContrastPipeline
%
% Outputs
%   appData — updated viewer state struct

switch action

    % ── Invert Image ─────────────────────────────────────────────────────
    case 'invert'
        if isempty(appData.filteredPixels), return; end
        try
            ctx.undoPush();
            appData.filteredPixels = max(appData.filteredPixels(:)) - appData.filteredPixels;
            ctx.refreshDisplay();
            ctx.setStatus('Image inverted.');
        catch ME
            ctx.setStatus(['Invert failed: ' ME.message]);
        end

    % ── Unsharp Mask / Sharpen ───────────────────────────────────────────
    case 'sharpen'
        if isempty(appData.filteredPixels), return; end
        answer = inputdlg({'Sigma:', 'Amount:'}, 'Unsharp Mask', [1 30], {'2', '1.0'});
        if isempty(answer), return; end
        sigma  = str2double(answer{1});
        amount = str2double(answer{2});
        if isnan(sigma) || isnan(amount), return; end
        try
            ctx.undoPush();
            appData.filteredPixels = imaging.unsharpMask(appData.filteredPixels, ...
                Sigma=sigma, Amount=amount);
            ctx.refreshDisplay();
            ctx.setStatus(sprintf('Sharpened (sigma=%.1f, amount=%.1f)', sigma, amount));
        catch ME
            ctx.setStatus(['Sharpen failed: ' ME.message]);
        end

    % ── Image Binning ─────────────────────────────────────────────────────
    case 'binImage'
        if isempty(appData.filteredPixels), return; end
        answer = inputdlg({'Bin size (2, 4, or 8):', 'Mode (average or sum):'}, ...
            'Bin Image', [1 30], {'2', 'average'});
        if isempty(answer), return; end
        binSz = round(str2double(answer{1}));
        mode  = strtrim(answer{2});
        if isnan(binSz) || ~any(binSz == [2 4 8]), binSz = 2; end
        if ~any(strcmp(mode, {'average', 'sum'})), mode = 'average'; end
        try
            ctx.undoPush();
            appData.filteredPixels = imaging.binImage(appData.filteredPixels, ...
                BinSize=binSz, Mode=mode);
            appData.rawPixels = appData.filteredPixels;
            ctx.rebuildAxesForNewSize();
            ctx.setStatus(sprintf('Binned %dx%d (%s)', binSz, binSz, mode));
        catch ME
            ctx.setStatus(['Bin failed: ' ME.message]);
        end

    % ── Morphological Operations ─────────────────────────────────────────
    case 'morphOp'
        if isempty(appData.filteredPixels), return; end
        answer = inputdlg({'Operation (erode/dilate/open/close):', 'Radius (1-10):'}, ...
            'Morphological Operation', [1 40], {'open', '2'});
        if isempty(answer), return; end
        op = strtrim(answer{1});
        radius = round(str2double(answer{2}));
        if isnan(radius) || radius < 1, radius = 2; end
        try
            ctx.undoPush();
            appData.filteredPixels = imaging.morphOp(appData.filteredPixels, op, ...
                Radius=radius);
            ctx.refreshDisplay();
            ctx.setStatus(sprintf('Morphological %s (radius=%d)', op, radius));
        catch ME
            ctx.setStatus(['Morph op failed: ' ME.message]);
        end

    % ── Butterworth Bandpass Filter ───────────────────────────────────────
    case 'butterworth'
        if isempty(appData.filteredPixels), return; end
        answer = inputdlg({'Low cutoff (0-1, 0=no highpass):', ...
                           'High cutoff (0-1, 1=no lowpass):', ...
                           'Order (1-10):'}, ...
            'Butterworth Filter', [1 40], {'0', '0.5', '2'});
        if isempty(answer), return; end
        lowC  = str2double(answer{1});
        highC = str2double(answer{2});
        order = round(str2double(answer{3}));
        if isnan(lowC),  lowC  = 0; end
        if isnan(highC), highC = 0.5; end
        if isnan(order), order = 2; end
        try
            ctx.undoPush();
            appData.filteredPixels = imaging.butterworthFilter(appData.filteredPixels, ...
                LowCutoff=lowC, HighCutoff=highC, Order=order);
            ctx.refreshDisplay();
            ctx.setStatus(sprintf('Butterworth filter (low=%.2f, high=%.2f, order=%d)', ...
                lowC, highC, order));
        catch ME
            ctx.setStatus(['Butterworth failed: ' ME.message]);
        end

    % ── Batch Format Conversion ───────────────────────────────────────────
    case 'batchConvert'
        if isempty(appData.images), return; end
        answer = inputdlg({'Output format (png/tiff/jpeg):', 'Output directory (blank = same as source):'}, ...
            'Batch Convert', [1 50], {'png', ''});
        if isempty(answer), return; end
        fmt = lower(strtrim(answer{1}));
        outDir = strtrim(answer{2});
        if ~any(strcmp(fmt, {'png', 'tiff', 'jpeg', 'jpg'}))
            ctx.setStatus('Unsupported format. Use png, tiff, or jpeg.'); return;
        end
        if strcmp(fmt, 'jpg'), fmt = 'jpeg'; end
        ctx.fig.Pointer = 'watch'; drawnow;
        r = emViewer.processing.batchConvertImages(appData.images, fmt, outDir);
        ctx.fig.Pointer = 'arrow';
        ctx.setStatus(r.statusMsg);

    % ── Plane Leveling ────────────────────────────────────────────────────
    case 'planeLevel'
        if isempty(appData.rawPixels), return; end
        answer = inputdlg('Polynomial order (1=plane, 2=quadratic, 3=cubic):', ...
            'Plane Level', [1 40], {'1'});
        if isempty(answer), return; end
        order = str2double(answer{1});
        if isnan(order) || ~ismember(order, [1 2 3])
            uialert(ctx.fig, 'Order must be 1, 2, or 3.', 'Invalid'); return;
        end
        try
            ctx.undoPush();
            result = imaging.planeLevel(double(appData.filteredPixels), Order=order);
            appData.filteredPixels = result.leveled;
            ctx.displayImage();
            ctx.setStatus(sprintf('Plane leveled (order %d).', order));
        catch ME
            ctx.setStatus(['Plane level error: ' ME.message]);
        end

    % ── Surface Roughness ─────────────────────────────────────────────────
    case 'roughness'
        if isempty(appData.rawPixels), return; end
        try
            px = ctx.guiPixelSize();
            pu = ctx.guiPixelUnit();
            result = imaging.surfaceRoughness(double(appData.filteredPixels), ...
                PixelSize=px, PixelUnit=pu, Level='plane');
            uialert(ctx.fig, emViewer.display.formatRoughnessResult(result, pu), ...
                'Roughness Statistics', 'Icon', 'info');
            ctx.setStatus(sprintf('Roughness: Ra=%.3g, Rq=%.3g %s', result.Ra, result.Rq, pu));
        catch ME
            ctx.setStatus(['Roughness error: ' ME.message]);
        end

    % ── Interface Width Fit ───────────────────────────────────────────────
    case 'interfaceFit'
        if isempty(appData.rawPixels), return; end
        if ~isfield(appData, 'lastProfile') || isempty(appData.lastProfile)
            uialert(ctx.fig, 'Draw a line profile first, then click Interface Fit.', 'No profile');
            return;
        end
        try
            lp = appData.lastProfile;
            result = imaging.fitInterfaceWidth(lp.dist, lp.intensity);
            msg = sprintf(['Interface Width Fit\n\n' ...
                'Center: %.2f\nSigma: %.3f\n' ...
                '10-90%% width: %.3f\nR^2: %.4f\nModel: %s'], ...
                result.center, result.sigma, result.width1090, ...
                result.rSquared, result.model);
            uialert(ctx.fig, msg, 'Interface Fit', 'Icon', 'info');
            ctx.setStatus(sprintf('Interface width: %.3f (10-90%%)', result.width1090));
        catch ME
            ctx.setStatus(['Interface fit error: ' ME.message]);
        end

    % ── Multi-class Threshold ─────────────────────────────────────────────
    case 'multiOtsu'
        if isempty(appData.rawPixels), return; end
        answer = inputdlg('Number of classes (2-5):', 'Multi-Otsu', [1 30], {'3'});
        if isempty(answer), return; end
        nClass = str2double(answer{1});
        if isnan(nClass) || nClass < 2 || nClass > 5
            uialert(ctx.fig, 'Classes must be 2-5.', 'Invalid'); return;
        end
        try
            r = emViewer.processing.visualizeMultiOtsu(appData.filteredPixels, nClass);
            ctx.setStatus(r.statusMsg);
        catch ME
            ctx.setStatus(['Multi-Otsu error: ' ME.message]);
        end

    % ── GPA Strain Mapping Setup ──────────────────────────────────────────
    case 'gpa'
        if isempty(appData.rawPixels), return; end
        px = ctx.guiPixelSize();
        if px <= 0
            uialert(ctx.fig, 'Set pixel calibration first for meaningful strain values.', 'No calibration');
        end
        appData.captureMode = 'gpa';
        appData.captureClicks = [];
        ctx.setStatus('GPA: click two Bragg spots in the FFT. Esc to cancel.');

    % ── GPA Execution ─────────────────────────────────────────────────────
    case 'executeGPA'
        pts = appData.captureClicks;
        if size(pts, 1) < 2, return; end
        try
            gpaOut = emViewer.diffraction.executeGPA( ...
                double(appData.filteredPixels), pts, max(ctx.guiPixelSize(), 1));
            ctx.setStatus(gpaOut.statusMsg);
        catch ME
            ctx.setStatus(['GPA error: ' ME.message]);
        end

    % ── CTF Estimation ────────────────────────────────────────────────────
    case 'ctfEstimate'
        if isempty(appData.rawPixels), return; end
        answer = inputdlg({'Voltage (kV):', 'Cs (mm):', 'Pixel size (Å):'}, ...
            'CTF Parameters', [1 40; 1 40; 1 40], {'200', '1.2', '1'});
        if isempty(answer), return; end
        kV  = str2double(answer{1});
        Cs  = str2double(answer{2});
        pxA = str2double(answer{3});
        if any(isnan([kV, Cs, pxA]))
            uialert(ctx.fig, 'Invalid numeric input.', 'Error'); return;
        end
        try
            ctfOut = emViewer.diffraction.executeCTF( ...
                double(appData.filteredPixels), kV, Cs, pxA);
            ctx.setStatus(ctfOut.statusMsg);
        catch ME
            ctx.setStatus(['CTF error: ' ME.message]);
        end

    % ── Defect Counter ────────────────────────────────────────────────────
    case 'defectCount'
        if isempty(appData.rawPixels), return; end
        answer = inputdlg({'Grid spacing (px):', 'Foil thickness (nm, 0=unknown):', ...
                           'Defect direction (deg, NaN=all):'}, ...
            'Defect Counter', [1 40; 1 40; 1 40], {'50', '0', 'NaN'});
        if isempty(answer), return; end
        gridSp = str2double(answer{1});
        if isnan(gridSp), gridSp = 50; end
        try
            dcOut = emViewer.diffraction.executeDefectCount( ...
                double(appData.filteredPixels), gridSp, ...
                max(ctx.guiPixelSize(), 1), ctx.guiPixelUnit());
            uialert(ctx.fig, dcOut.dialogMsg, 'Defect Count', 'Icon', 'info');
            ctx.setStatus(dcOut.statusMsg);
        catch ME
            ctx.setStatus(['Defect count error: ' ME.message]);
        end

    % ── Back-Projection Preview ───────────────────────────────────────────
    case 'backProject'
        if isempty(appData.rawPixels), return; end
        if ~isfield(appData, 'images') || numel(appData.images) < 2
            uialert(ctx.fig, 'Load a tilt series (multi-frame) first.', 'Need stack'); return;
        end
        answer = inputdlg({'Tilt angles (comma-separated, deg):', 'Row index for sinogram:'}, ...
            'Back-Projection', [1 60; 1 40], ...
            {sprintf('%.0f,', linspace(-70, 70, numel(appData.images))), ...
             num2str(round(size(appData.images{1}, 1) / 2))});
        if isempty(answer), return; end
        try
            rowIdx = str2double(answer{2});
            bpOut = emViewer.processing.executeBackProject( ...
                appData.images, answer{1}, rowIdx);
            ctx.setStatus(bpOut.statusMsg);
        catch ME
            ctx.setStatus(['Back-projection error: ' ME.message]);
        end

    % ── Figure Panel Builder ──────────────────────────────────────────────
    case 'figureBuilder'
        if isempty(appData.rawPixels), return; end
        nImg = numel(appData.images);
        if nImg < 1
            uialert(ctx.fig, 'Load at least one image.', 'No images'); return;
        end
        answer = inputdlg({'Rows:', 'Columns:', 'Gap (px):'}, ...
            'Figure Builder', [1 30; 1 30; 1 30], ...
            {num2str(ceil(sqrt(nImg))), num2str(ceil(nImg / ceil(sqrt(nImg)))), '2'});
        if isempty(answer), return; end
        try
            nRows = str2double(answer{1});
            nCols = str2double(answer{2});
            gap   = str2double(answer{3});
            imgs = appData.images(1:min(nImg, nRows*nCols));
            emViewer.processing.buildFigurePanel(imgs, nRows, nCols, gap);
            ctx.setStatus('Figure panel built.');
        catch ME
            ctx.setStatus(['Figure builder error: ' ME.message]);
        end

    % ── Calibrated Colorbar ───────────────────────────────────────────────
    case 'calibratedColorbar'
        if isempty(appData.rawPixels), return; end
        answer = inputdlg({'Min value:', 'Max value:', 'Unit label:'}, ...
            'Calibrated Colorbar', [1 30; 1 30; 1 30], ...
            {num2str(min(appData.filteredPixels(:))), ...
             num2str(max(appData.filteredPixels(:))), 'counts'});
        if isempty(answer), return; end
        try
            minVal    = str2double(answer{1});
            maxVal    = str2double(answer{2});
            unitLabel = answer{3};
            cmap = feval(ctx.ddColormap.Value, 256);
            [H, W] = size(appData.filteredPixels);
            result = imaging.addColorbar([H, W], Colormap=cmap, ...
                Range=[minVal, maxVal], Unit=unitLabel);
            if ~isempty(ctx.ax) && isvalid(ctx.ax)
                ctx.ax.CLim = [0 1];
                cb = colorbar(ctx.ax, 'Location', 'eastoutside');
                nTicks = numel(result.labelStrings);
                cb.Ticks = linspace(0, 1, nTicks);
                cb.TickLabels = result.labelStrings;
                cb.Label.String = unitLabel;
                appData.calibColorbar = cb;
            end
            ctx.setStatus(sprintf('Colorbar: %.3g to %.3g %s', minVal, maxVal, unitLabel));
        catch ME
            ctx.setStatus(['Colorbar error: ' ME.message]);
        end

    % ── Macro Recorder Toggle ─────────────────────────────────────────────
    case 'macroToggle'
        if ~isfield(appData, 'isRecording'), appData.isRecording = false; end
        if ~appData.isRecording
            appData.isRecording = true;
            appData.macroRecording = {};
            ctx.btnMacroRecord.Text = 'Stop Recording';
            ctx.btnMacroRecord.BackgroundColor = [0.7 0.15 0.15];
            ctx.setStatus('Macro recording started. Perform measurements, then click Stop.');
        else
            appData.isRecording = false;
            ctx.btnMacroRecord.Text = 'Record Macro';
            ctx.btnMacroRecord.BackgroundColor = ctx.BTN_TOOL;
            nCmds = numel(appData.macroRecording);
            if nCmds == 0
                ctx.setStatus('Macro: no commands recorded.');
                return;
            end
            [fname, fpath] = uiputfile({'*.mat', 'MATLAB macro (*.mat)'}, ...
                'Save Macro', 'macro.mat');
            if ~isequal(fname, 0)
                macroData = appData.macroRecording; %#ok<NASGU>
                save(fullfile(fpath, fname), 'macroData');
                ctx.setStatus(sprintf('Macro saved: %d commands → %s', nCmds, fname));
            else
                ctx.setStatus(sprintf('Macro: %d commands recorded (not saved).', nCmds));
            end
        end

end
end
