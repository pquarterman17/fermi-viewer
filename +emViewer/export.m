function result = export(action, ctx, varargin)
%EXPORT  Export pipeline for FermiViewer — extracted from main GUI closure.
%
% Syntax:
%   emViewer.export(action, ctx, ...)
%
% ctx struct fields:
%   .fig              — uifigure handle
%   .ax               — main image axes handle
%   .appData          — FermiViewer appData struct (snapshot)
%   .sldLowValue      — current low contrast slider value
%   .sldHighValue     — current high contrast slider value
%   .cmapName         — current colormap name string
%   .exportDPI        — export DPI value
%   .setStatus        — @setStatus function handle
%   .applyContrast    — @applyContrastPipeline function handle
%   .percentile       — @percentileNoToolbox function handle

result = [];

switch lower(action)

    % ── saveImage ─────────────────────────────────────────────────
    case 'saveimage'
        if isempty(ctx.appData.displayImg)
            uialert(ctx.fig, 'No image to save.', 'No Image', 'Icon', 'warning');
            return;
        end

        if ctx.appData.activeIdx >= 1
            [~, bname] = fileparts( ...
                ctx.appData.images{ctx.appData.activeIdx}.metadata.source);
            defName = [bname '_processed.tif'];
        else
            defName = 'em_image.tif';
        end

        startPath = ctx.appData.lastDir;
        if isempty(startPath) || ~isfolder(startPath)
            startPath = pwd;
        end

        [saveName, saveDir] = uiputfile( ...
            {'*.tif;*.tiff', 'TIFF (*.tif, *.tiff)'; ...
             '*.png',        'PNG (*.png)'}, ...
            'Save Processed Image As', ...
            fullfile(startPath, defName));

        if isequal(saveName, 0)
            return;
        end

        outPath = fullfile(saveDir, saveName);
        [~, ~, ext] = fileparts(outPath);

        ctx.fig.Pointer = 'watch';
        drawnow;

        try
            dispImg = ctx.appData.displayImg;
            if strcmpi(ext, '.png')
                imwrite(uint8(dispImg * 255), outPath);
            else
                imwrite(uint16(dispImg * 65535), outPath);
            end
            ctx.setStatus(sprintf('Saved: %s', saveName));
        catch ME
            uialert(ctx.fig, sprintf('Save failed:\n%s', ME.message), ...
                'Save Error', 'Icon', 'error');
        end

        ctx.fig.Pointer = 'arrow';

    % ── saveCroppedRegion ─────────────────────────────────────────
    case 'savecroppedregion'
        xMin = varargin{1}; xMax = varargin{2};
        yMin = varargin{3}; yMax = varargin{4};

        if ctx.appData.activeIdx >= 1
            srcPath = ctx.appData.images{ctx.appData.activeIdx}.metadata.source;
            [srcDir, bname] = fileparts(srcPath);
            defName = [bname '_crop.tif'];
        else
            srcPath = '';
            srcDir  = '';
            defName = 'crop.tif';
        end

        startPath = ctx.appData.lastDir;
        if isempty(startPath) || ~isfolder(startPath)
            if ~isempty(srcDir) && isfolder(srcDir)
                startPath = srcDir;
            else
                startPath = pwd;
            end
        end

        [saveName, saveDir] = uiputfile( ...
            {'*.tif;*.tiff', 'TIFF (*.tif, *.tiff)'; ...
             '*.png',        'PNG (*.png)'}, ...
            'Save Cropped Region As', ...
            fullfile(startPath, defName));

        if isequal(saveName, 0)
            ctx.setStatus('Save cancelled.');
            return;
        end

        outPath = fullfile(saveDir, saveName);

        if ~isempty(srcPath)
            srcResolved = fullfile(srcPath);
            outResolved = fullfile(outPath);
            if strcmpi(srcResolved, outResolved)
                uialert(ctx.fig, ...
                    'Cannot overwrite the original source file. Choose a different name.', ...
                    'Overwrite Blocked', 'Icon', 'warning');
                return;
            end
        end

        [~, ~, ext] = fileparts(outPath);

        ctx.fig.Pointer = 'watch';
        drawnow;

        try
            cropPx = ctx.appData.filteredPixels(yMin:yMax, xMin:xMax);
            lo = ctx.sldLowValue;
            hi = ctx.sldHighValue;
            if hi <= lo, hi = lo + 1; end
            cropDisp = (cropPx - lo) / (hi - lo);
            cropDisp = max(0, min(1, cropDisp));

            if strcmpi(ext, '.png')
                imwrite(uint8(cropDisp * 255), outPath);
            else
                imwrite(uint16(cropDisp * 65535), outPath);
            end
            ctx.setStatus(sprintf('Crop saved: %s (%dx%d)', saveName, ...
                xMax - xMin + 1, yMax - yMin + 1));
        catch ME
            uialert(ctx.fig, sprintf('Save crop failed:\n%s', ME.message), ...
                'Save Error', 'Icon', 'error');
        end

        ctx.fig.Pointer = 'arrow';

    % ── exportWithOverlays ────────────────────────────────────────
    case 'exportwithoverlays'
        if isempty(ctx.appData.displayImg) || isempty(ctx.ax) || ~isvalid(ctx.ax)
            return;
        end

        if ctx.appData.activeIdx >= 1
            [~, bname] = fileparts(ctx.appData.images{ctx.appData.activeIdx}.metadata.source);
            defName = [bname '_overlay.png'];
        else
            defName = 'overlay.png';
        end

        startPath = ctx.appData.lastDir;
        if isempty(startPath) || ~isfolder(startPath)
            startPath = pwd;
        end

        [saveName, saveDir] = uiputfile( ...
            {'*.png', 'PNG (*.png)'; '*.tif;*.tiff', 'TIFF (*.tif)'}, ...
            'Export with Overlays', fullfile(startPath, defName));
        if isequal(saveName, 0), return; end

        outPath = fullfile(saveDir, saveName);

        ctx.fig.Pointer = 'watch'; drawnow;

        try
            tmpFig = figure('Visible', 'off', 'Color', 'k');
            copyobj(ctx.ax, tmpFig);
            tmpAx = findobj(tmpFig, 'Type', 'axes');
            tmpAx.Units = 'normalized';
            tmpAx.Position = [0 0 1 1];

            colormap(tmpFig, feval(ctx.cmapName, 256));

            dpi = ctx.exportDPI;
            set(tmpFig, 'PaperUnits', 'inches', ...
                'PaperPosition', [0 0 size(ctx.appData.displayImg,2)/dpi size(ctx.appData.displayImg,1)/dpi]);
            frame = getframe(tmpAx);
            close(tmpFig);

            [~, ~, ext] = fileparts(outPath);
            if strcmpi(ext, '.tif') || strcmpi(ext, '.tiff')
                imwrite(frame.cdata, outPath, 'Compression', 'none');
            else
                imwrite(frame.cdata, outPath);
            end

            ctx.setStatus(sprintf('Exported with overlays: %s', saveName));
        catch ME
            ctx.fig.Pointer = 'arrow';
            uialert(ctx.fig, sprintf('Export failed:\n%s', ME.message), ...
                'Error', 'Icon', 'error');
            return;
        end

        ctx.fig.Pointer = 'arrow';

    % ── batchExport ───────────────────────────────────────────────
    case 'batchexport'
        if isempty(ctx.appData.images)
            return;
        end

        outDir = uigetdir(ctx.appData.lastDir, 'Select Output Folder for Batch Export');
        if isequal(outDir, 0), return; end

        ctx.fig.Pointer = 'watch'; drawnow;

        nExported = 0;
        for ki = 1:numel(ctx.appData.images)
            try
                imgInfo = ctx.appData.images{ki}.metadata.parserSpecific.imageData;
                px = double(imgInfo.pixels);
                if imgInfo.numChannels == 3
                    px = 0.299*px(:,:,1) + 0.587*px(:,:,2) + 0.114*px(:,:,3);
                end

                lo = ctx.percentile(px(:), 2);
                hi = ctx.percentile(px(:), 98);
                if lo >= hi
                    lo = min(px(:)); hi = max(px(:));
                end
                if hi <= lo, hi = lo + 1; end
                dispPx = (px - lo) / (hi - lo);
                dispPx = max(0, min(1, dispPx));

                [~, bname] = fileparts(ctx.appData.images{ki}.metadata.source);
                outPath = fullfile(outDir, [bname '_export.png']);
                imwrite(uint8(dispPx * 255), outPath);
                nExported = nExported + 1;
            catch
            end
        end

        ctx.fig.Pointer = 'arrow';
        ctx.setStatus(sprintf('Batch exported %d / %d images to %s', ...
            nExported, numel(ctx.appData.images), outDir));

    % ── doCreateGIF ───────────────────────────────────────────────
    case 'docreategif'
        dlg       = varargin{1};
        lbImages  = varargin{2};
        efDelay   = varargin{3};
        ddLoop    = varargin{4};
        cbBar     = varargin{5};
        ddBarColor = varargin{6};

        selIdx = lbImages.Value;
        if isempty(selIdx) || ~iscell(selIdx) && isscalar(selIdx) && selIdx < 1
            uialert(dlg, 'Select at least 2 images.', 'GIF Error');
            return;
        end
        if ~iscell(selIdx), selIdx = {selIdx}; end
        idxList = [selIdx{:}];
        if numel(idxList) < 2
            uialert(dlg, 'Select at least 2 images.', 'GIF Error');
            return;
        end

        delay     = efDelay.Value;
        loopCount = ddLoop.Value;
        addBar    = cbBar.Value;
        barColor  = [1 1 1];
        if strcmp(ddBarColor.Value, 'Black'), barColor = [0 0 0]; end

        if isinf(loopCount)
            gifLoop = 0;
        else
            gifLoop = max(0, loopCount - 1);
        end

        close(dlg);

        startPath = ctx.appData.lastDir;
        if isempty(startPath), startPath = pwd; end
        [saveName, saveDir] = uiputfile( ...
            {'*.gif', 'Animated GIF (*.gif)'}, ...
            'Save Animated GIF', fullfile(startPath, 'animation.gif'));
        if isequal(saveName, 0), return; end
        outPath = fullfile(saveDir, saveName);

        ctx.fig.Pointer = 'watch'; drawnow;
        ctx.setStatus('Creating GIF...');

        try
            maxH = 0; maxW = 0;
            for qi = 1:numel(idxList)
                imgInfo = ctx.appData.images{idxList(qi)}.metadata.parserSpecific.imageData;
                maxH = max(maxH, imgInfo.height);
                maxW = max(maxW, imgInfo.width);
            end

            barLenPx = 0;  barLenPhys = 0;  barUnit = '';
            if addBar
                for qi = 1:numel(idxList)
                    imgInfo = ctx.appData.images{idxList(qi)}.metadata.parserSpecific.imageData;
                    if imgInfo.calibrated
                        pxSz = imgInfo.pixelSize;
                        barUnit = imgInfo.pixelUnit;
                        targetPhys = maxW * pxSz / 5;
                        niceLens = [1 2 5 10 20 50 100 200 500 1000];
                        [~, bestIdx] = min(abs(niceLens - targetPhys));
                        barLenPhys = niceLens(bestIdx);
                        barLenPx   = barLenPhys / pxSz;
                        break;
                    end
                end
                if barLenPx == 0
                    addBar = false;
                end
            end

            cmap256 = getCmapByName(ctx.cmapName);

            for qi = 1:numel(idxList)
                imgInfo = ctx.appData.images{idxList(qi)}.metadata.parserSpecific.imageData;
                px = double(imgInfo.pixels);
                if imgInfo.numChannels == 3
                    px = 0.299*px(:,:,1) + 0.587*px(:,:,2) + 0.114*px(:,:,3);
                end

                lo = ctx.percentile(px(:), 2);
                hi = ctx.percentile(px(:), 98);
                if lo >= hi, lo = min(px(:)); hi = max(px(:)); end
                if hi <= lo, hi = lo + 1; end
                dispPx = (px - lo) / (hi - lo);
                dispPx = max(0, min(1, dispPx));

                [curH, curW] = size(dispPx);
                if curH ~= maxH || curW ~= maxW
                    padded = zeros(maxH, maxW);
                    offY = floor((maxH - curH) / 2) + 1;
                    offX = floor((maxW - curW) / 2) + 1;
                    padded(offY:offY+curH-1, offX:offX+curW-1) = dispPx;
                    dispPx = padded;
                end

                idxImg = max(1, min(256, round(dispPx * 255) + 1));
                rgbFrame = uint8(reshape(cmap256(idxImg(:), :), [maxH, maxW, 3]) * 255);

                if addBar
                    barH   = max(2, round(maxH * 0.02));
                    margin = round(barLenPx * 0.3);
                    bx1 = maxW - margin - round(barLenPx) + 1;
                    bx2 = maxW - margin;
                    by1 = maxH - margin - barH + 1;
                    by2 = maxH - margin;

                    bx1 = max(1, bx1); bx2 = min(maxW, bx2);
                    by1 = max(1, by1); by2 = min(maxH, by2);

                    barRGB = uint8(barColor * 255);
                    rgbFrame(by1:by2, bx1:bx2, 1) = barRGB(1);
                    rgbFrame(by1:by2, bx1:bx2, 2) = barRGB(2);
                    rgbFrame(by1:by2, bx1:bx2, 3) = barRGB(3);

                    if barLenPhys == round(barLenPhys)
                        lblStr = sprintf('%d %s', round(barLenPhys), barUnit);
                    else
                        lblStr = sprintf('%.2g %s', barLenPhys, barUnit);
                    end
                    rgbFrame = burnTextOnFrame(rgbFrame, lblStr, ...
                        round((bx1 + bx2) / 2), by1, barColor);
                end

                [idxFrame, cmap] = rgb2ind(rgbFrame, 256, 'nodither');

                if qi == 1
                    imwrite(idxFrame, cmap, outPath, 'gif', ...
                        'LoopCount', gifLoop, 'DelayTime', delay);
                else
                    imwrite(idxFrame, cmap, outPath, 'gif', ...
                        'WriteMode', 'append', 'DelayTime', delay);
                end

                ctx.setStatus(sprintf('Creating GIF... frame %d / %d', qi, numel(idxList)));
                drawnow;
            end

            ctx.fig.Pointer = 'arrow';
            ctx.setStatus(sprintf('GIF saved: %s (%d frames)', saveName, numel(idxList)));
        catch ME
            ctx.fig.Pointer = 'arrow';
            ctx.setStatus(sprintf('GIF export failed: %s', ME.message));
            uialert(ctx.fig, sprintf('GIF creation failed:\n%s', ME.message), ...
                'Error', 'Icon', 'error');
        end

    % ── copyClipboard ─────────────────────────────────────────────
    % Copy the live UIAxes directly so all overlays (measurements,
    % scale bar, annotations) are captured. The previous copyobj→
    % invisible-figure path silently dropped HandleVisibility='off'
    % overlays during the cross-figure-type translation.
    case 'copyclipboard'
        if isempty(ctx.appData.displayImg) || isempty(ctx.ax) || ~isvalid(ctx.ax)
            return;
        end

        try
            copygraphics(ctx.ax, 'Resolution', 300, ...
                'ContentType', 'vector', ...
                'BackgroundColor', 'current');
            ctx.setStatus('Copied to clipboard (vector, with overlays).');
        catch ME
            ctx.setStatus(sprintf('Clipboard copy failed: %s', ME.message));
        end

    % ── journalExport ─────────────────────────────────────────────
    case 'journalexport'
        if isempty(ctx.appData.rawPixels), return; end
        presets = { ...
            'Nature',      89,  300, 'tiff'; ...
            'Science',     85,  300, 'tiff'; ...
            'ACS',         84,  300, 'tiff'; ...
            'Elsevier',    90,  300, 'tiff'; ...
            'APS (PRL)',   86,  300, 'eps';  ...
            'Wiley',       85,  300, 'tiff'; ...
            'IUCr',        83,  600, 'tiff'; ...
            'Custom',      85,  300, 'tiff'};
        names = presets(:,1);
        [sel, ok] = listdlg('ListString', names, 'SelectionMode', 'single', ...
            'PromptString', 'Select journal preset:', 'ListSize', [250 200]);
        if ~ok, return; end
        widthMM = presets{sel, 2};
        dpi = presets{sel, 3};
        fmt = presets{sel, 4};
        if strcmp(names{sel}, 'Custom')
            ans2 = inputdlg({'Width (mm):', 'DPI:', 'Format (tiff/png/eps/pdf):'}, ...
                'Custom Export', [1 30; 1 30; 1 30], ...
                {num2str(widthMM), num2str(dpi), fmt});
            if isempty(ans2), return; end
            widthMM = str2double(ans2{1});
            dpi = str2double(ans2{2});
            fmt = strtrim(ans2{3});
        end
        widthPx = round(widthMM / 25.4 * dpi);
        try
            img = ctx.appData.filteredPixels;
            [H, W] = size(img, [1 2]);
            scale = widthPx / W;
            newH = round(H * scale);
            [Xq, Yq] = meshgrid(linspace(1, W, widthPx), linspace(1, H, newH));
            if ndims(img) == 3
                resized = zeros(newH, widthPx, 3, 'like', img);
                for ch = 1:3
                    resized(:,:,ch) = interp2(double(img(:,:,ch)), Xq, Yq, 'bilinear');
                end
            else
                resized = interp2(double(img), Xq, Yq, 'bilinear');
            end
            dispImg = ctx.applyContrast(resized, ctx.sldLowValue, ctx.sldHighValue);
            ext = ['.' fmt];
            [fname, fpath] = uiputfile({['*' ext], [upper(fmt) ' file']}, ...
                'Export for journal', ['figure' ext]);
            if isequal(fname, 0), return; end
            outPath = fullfile(fpath, fname);
            if ismember(fmt, {'tiff', 'tif'})
                imwrite(uint8(dispImg * 255), outPath, 'tiff', 'Compression', 'lzw', ...
                    'Resolution', dpi);
            elseif strcmp(fmt, 'png')
                imwrite(uint8(dispImg * 255), outPath, 'png');
            else
                tmpFig = figure('Visible', 'off');
                imshow(dispImg, 'Parent', axes(tmpFig));
                print(tmpFig, outPath, ['-d' fmt], ['-r' num2str(dpi)]);
                close(tmpFig);
            end
            ctx.setStatus(sprintf('Exported %dx%d px @ %d dpi → %s', widthPx, newH, dpi, fname));
        catch ME
            ctx.setStatus(['Journal export error: ' ME.message]);
        end

    % ── exportProfile ─────────────────────────────────────────────
    case 'exportprofile'
        if isempty(ctx.appData.lastProfile.dist)
            uialert(ctx.fig, 'No line profile available. Use "Line Profile" first.', ...
                'No Profile', 'Icon', 'warning');
            return;
        end

        if ctx.appData.activeIdx >= 1
            [~, bname] = fileparts(ctx.appData.images{ctx.appData.activeIdx}.metadata.source);
            defName = [bname '_profile.csv'];
        else
            defName = 'line_profile.csv';
        end

        startPath = ctx.appData.lastDir;
        if isempty(startPath) || ~isfolder(startPath)
            startPath = pwd;
        end

        [saveName, saveDir] = uiputfile('*.csv', 'Save Line Profile As', ...
            fullfile(startPath, defName));

        if isequal(saveName, 0)
            return;
        end

        outPath = fullfile(saveDir, saveName);

        distCol  = ctx.appData.lastProfile.dist(:);
        intCol   = ctx.appData.lastProfile.intensity(:);
        M = [distCol, intCol];

        unitStr = ctx.appData.lastProfile.unit;
        header  = sprintf('Distance (%s),Intensity', unitStr);

        try
            fid = fopen(outPath, 'w');
            if fid == -1
                error('FermiViewer:exportFailed', 'Cannot open file for writing: %s', outPath);
            end
            fprintf(fid, '%s\n', header);
            fclose(fid);
            writematrix(M, outPath, 'WriteMode', 'append');
            ctx.setStatus(sprintf('Profile saved: %s', saveName));
        catch ME
            uialert(ctx.fig, sprintf('Export failed:\n%s', ME.message), ...
                'Export Error', 'Icon', 'error');
        end

    % ── exportMeasurements ────────────────────────────────────────
    case 'exportmeasurements'
        if isempty(ctx.appData.measurementLog)
            uialert(ctx.fig, 'No measurements recorded yet.', 'Empty', 'Icon', 'info');
            return;
        end

        [fn, fp] = uiputfile('*.csv', 'Export Measurements');
        if isequal(fn, 0), return; end

        try
            writeMeasurementsCSV(fullfile(fp, fn), ctx.appData.measurementLog);
            ctx.setStatus(sprintf('Exported %d measurements to %s', ...
                numel(ctx.appData.measurementLog), fn));
        catch ME
            uialert(ctx.fig, sprintf('Cannot write to:\n%s\n\n%s', fn, ME.message), ...
                'Export Error', 'Icon', 'error');
        end

    % ── saveImageAPI (headless) ───────────────────────────────────
    case 'saveimageapi'
        outPath = varargin{1};
        if isempty(ctx.appData.displayImg)
            warning('FermiViewer:noImage', 'No image loaded.');
            return;
        end

        [~, ~, ext] = fileparts(outPath);
        dispImg = ctx.appData.displayImg;
        if strcmpi(ext, '.png')
            imwrite(uint8(dispImg * 255), outPath);
        else
            imwrite(uint16(dispImg * 65535), outPath);
        end

    % ── writeMeasurementsCSV (headless) ───────────────────────────
    case 'writemeasurementscsv'
        writeMeasurementsCSV(varargin{1}, ctx.appData.measurementLog);

    otherwise
        warning('emViewer:export:unknownAction', ...
            'Unknown export action "%s".', action);
end
end

% ════════════════════════════════════════════════════════════════════
%  LOCAL: burnTextOnFrame — render text onto RGB image
% ════════════════════════════════════════════════════════════════════
function rgb = burnTextOnFrame(rgb, str, cx, topY, color)
    [fH, fW, ~] = size(rgb);
    tmpFig = figure('Visible', 'off', 'Color', 'k', ...
        'Units', 'pixels', 'Position', [0 0 fW fH], ...
        'MenuBar', 'none', 'ToolBar', 'none');
    tmpAx = axes(tmpFig, 'Units', 'pixels', 'Position', [0 0 fW fH], ...
        'XLim', [0.5 fW+0.5], 'YLim', [0.5 fH+0.5], 'YDir', 'reverse', ...
        'Visible', 'off', 'Color', 'none');
    image(tmpAx, 'CData', rgb, 'XData', [1 fW], 'YData', [1 fH]);
    fontSize = max(8, round(fH * 0.025));
    text(tmpAx, cx, topY - round(fH*0.005), str, ...
        'Color', color, 'FontSize', fontSize, ...
        'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'bottom', ...
        'FontWeight', 'bold');
    drawnow;
    frame = getframe(tmpAx);
    close(tmpFig);
    rgb = frame.cdata;
    if size(rgb,1) ~= fH || size(rgb,2) ~= fW
        rgb = imresize(rgb, [fH fW]);
    end
end

% ════════════════════════════════════════════════════════════════════
%  LOCAL: getCmapByName — return 256×3 colormap matrix
% ════════════════════════════════════════════════════════════════════
function cmap = getCmapByName(name)
    try
        cmap = feval(name, 256);
    catch
        cmap = parula(256);
    end
end

% ════════════════════════════════════════════════════════════════════
%  LOCAL: writeMeasurementsCSV — write measurement log to CSV
% ════════════════════════════════════════════════════════════════════
function writeMeasurementsCSV(fullpath, measurementLog)
    if isempty(measurementLog)
        error('FermiViewer:noMeasurements', 'No measurements to export.');
    end
    fid = fopen(fullpath, 'w');
    if fid == -1
        error('FermiViewer:cannotWrite', 'Cannot open file for writing: %s', fullpath);
    end
    cleaner = onCleanup(@() fclose(fid));
    fprintf(fid, 'Type,Value,Unit,Details\n');
    for mi = 1:numel(measurementLog)
        m = measurementLog{mi};
        details = strrep(m.details, '"', '""');
        fprintf(fid, '%s,%.6g,%s,"%s"\n', m.type, m.value, m.unit, details);
    end
end
