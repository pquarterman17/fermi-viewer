function result = dispatch(action, ctx, varargin)
%DISPATCH  Export pipeline for FermiViewer — extracted from main GUI closure.
%
% Syntax:
%   fermiViewer.export.dispatch(action, ctx, ...)
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
            fermiViewer.chrome.quietAlert(ctx.fig, 'No image to save.', 'No Image', 'Icon', 'warning');
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
            dispImg = fullResDisplayImg(ctx);
            if strcmpi(ext, '.png')
                imwrite(uint8(dispImg * 255), outPath);
            else
                imwrite(uint16(dispImg * 65535), outPath);
            end
            ctx.setStatus(sprintf('Saved: %s (%dx%d px)', saveName, ...
                size(dispImg,2), size(dispImg,1)));
        catch ME
            fermiViewer.chrome.quietAlert(ctx.fig, sprintf('Save failed:\n%s', ME.message), ...
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
                fermiViewer.chrome.quietAlert(ctx.fig, ...
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
            % Full contrast pipeline (transform/gamma/invert), not a bare
            % linear stretch — the crop must match the screen and Save Image.
            cropDisp = ctx.applyContrast(double(cropPx), ...
                ctx.sldLowValue, ctx.sldHighValue);

            if strcmpi(ext, '.png')
                imwrite(uint8(cropDisp * 255), outPath);
            else
                imwrite(uint16(cropDisp * 65535), outPath);
            end
            ctx.setStatus(sprintf('Crop saved: %s (%dx%d)', saveName, ...
                xMax - xMin + 1, yMax - yMin + 1));
        catch ME
            fermiViewer.chrome.quietAlert(ctx.fig, sprintf('Save crop failed:\n%s', ME.message), ...
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

        % The previous copyobj->getframe path captured at the temp
        % figure's on-screen size (PaperPosition is a no-op for
        % getframe), so output pixel counts never matched the image and
        % varied with screen/DPI scaling. Capture an offscreen 1:1
        % native copy instead: getframe of the exactly-sized offscreen
        % uifigure is pixel-exact; if a platform DPI-scales it, fall
        % back to exportgraphics and center-crop its fixed few-px pad.
        try
            [tmpFig, newAx, outW, outH] = makeNativeAxesCopy(ctx);
            tmpCleaner = onCleanup(@() delete(tmpFig));

            rgb = fermiViewer.export.captureAxesExact(tmpFig, newAx, outW, outH);
            if isempty(rgb)
                error('FermiViewer:captureFailed', ...
                    'Could not capture the image at native resolution.');
            end

            [~, ~, ext] = fileparts(outPath);
            if strcmpi(ext, '.tif') || strcmpi(ext, '.tiff')
                imwrite(rgb, outPath, 'Compression', 'none');
            else
                imwrite(rgb, outPath);
            end

            ctx.setStatus(sprintf('Exported with overlays: %s (%dx%d px, 1:1 native)', ...
                saveName, size(rgb,2), size(rgb,1)));
        catch ME
            ctx.fig.Pointer = 'arrow';
            fermiViewer.chrome.quietAlert(ctx.fig, sprintf('Export failed:\n%s', ME.message), ...
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

        nExported = 0; nSkipped = 0;
        for ki = 1:numel(ctx.appData.images)
            ps_ = ctx.appData.images{ki}.metadata.parserSpecific;
            if ~isfield(ps_, 'imageData')   % e.g. EDS-only BCF (no SEM image)
                nSkipped = nSkipped + 1;
                continue;
            end
            try
                imgInfo = ps_.imageData;
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
        msg = sprintf('Batch exported %d / %d images to %s', ...
            nExported, numel(ctx.appData.images), outDir);
        if nSkipped > 0
            msg = sprintf('%s (%d skipped — no image data)', msg, nSkipped);
        end
        ctx.setStatus(msg);

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
            fermiViewer.chrome.quietAlert(dlg, 'Select at least 2 images.', 'GIF Error');
            return;
        end
        if ~iscell(selIdx), selIdx = {selIdx}; end
        idxList = [selIdx{:}];
        if numel(idxList) < 2
            fermiViewer.chrome.quietAlert(dlg, 'Select at least 2 images.', 'GIF Error');
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
            fermiViewer.chrome.quietAlert(ctx.fig, sprintf('GIF creation failed:\n%s', ME.message), ...
                'Error', 'Icon', 'error');
        end

    % ── copyClipboard ─────────────────────────────────────────────
    % Copy a 1:1 native-resolution raster with all overlays burned in.
    % Copying the live UIAxes (raster OR vector) rasterizes the image
    % at the axes' physical on-screen size — window/monitor dependent
    % and nearest-neighbor resampled, which is the "weirdly pixelated
    % copy with mismatched pixel counts" bug (seen on R2022b, present
    % on every version). 'Resolution' is documented to be IGNORED for
    % ContentType='vector', so the old 300 DPI did nothing. Render an
    % offscreen copy at one canvas px per image px instead; the only
    % residue is a fixed ~2 px border copygraphics pads around content.
    case 'copyclipboard'
        if isempty(ctx.appData.displayImg) || isempty(ctx.ax) || ~isvalid(ctx.ax)
            return;
        end

        try
            [tmpFig, newAx, outW, outH] = makeNativeAxesCopy(ctx);
            tmpCleaner = onCleanup(@() delete(tmpFig));
            copygraphics(newAx, 'ContentType', 'image', ...
                'Resolution', 96, 'BackgroundColor', 'current');
            ctx.setStatus(sprintf( ...
                'Copied to clipboard (%dx%d px, 1:1 native, with overlays).', ...
                outW, outH));
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
            % Validate: NaN/0/negative width or dpi otherwise produce an
            % empty or 1-pixel "journal figure" written silently as success.
            if ~isfinite(widthMM) || widthMM <= 0 || ~isfinite(dpi) || dpi <= 0
                fermiViewer.chrome.quietAlert(ctx.fig, ...
                    'Width and DPI must be positive numbers.', ...
                    'Invalid Input', 'Icon', 'error');
                return;
            end
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
                % eps/pdf: render at the exact requested physical size so
                % the page is widthMM wide (the old default PaperPosition
                % ignored it). '-image' rasterizes the page at -r DPI —
                % vector mode embeds image objects at 96 DPI regardless of
                % -r, and '-deps' dithers to 1-bit black/white. For a pure
                % micrograph, a full-raster EPS/PDF at the requested DPI
                % is the journal-correct output.
                if strcmp(fmt, 'pdf'), drv = '-dpdf'; else, drv = '-depsc'; end
                if ndims(dispImg) == 3
                    rgbImg = dispImg;
                else
                    rgbImg = repmat(dispImg, 1, 1, 3);
                end
                tmpFig = figure('Visible', 'off', 'Color', 'w');
                tmpAx = axes(tmpFig, 'Position', [0 0 1 1], 'Visible', 'off');
                image(tmpAx, rgbImg);
                axis(tmpAx, 'image');
                set(tmpFig, 'PaperUnits', 'inches', 'PaperPositionMode', 'manual', ...
                    'PaperSize', [widthPx/dpi, newH/dpi], ...
                    'PaperPosition', [0 0 widthPx/dpi, newH/dpi]);
                print(tmpFig, outPath, drv, '-image', ['-r' num2str(dpi)]);
                close(tmpFig);
            end
            ctx.setStatus(sprintf('Exported %dx%d px @ %d dpi → %s', widthPx, newH, dpi, fname));
        catch ME
            ctx.setStatus(['Journal export error: ' ME.message]);
        end

    % ── exportProfile ─────────────────────────────────────────────
    case 'exportprofile'
        if isempty(ctx.appData.lastProfile.dist)
            fermiViewer.chrome.quietAlert(ctx.fig, 'No line profile available. Use "Line Profile" first.', ...
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
            fermiViewer.chrome.quietAlert(ctx.fig, sprintf('Export failed:\n%s', ME.message), ...
                'Export Error', 'Icon', 'error');
        end

    % ── exportMeasurements ────────────────────────────────────────
    case 'exportmeasurements'
        if isempty(ctx.appData.measurementLog)
            fermiViewer.chrome.quietAlert(ctx.fig, 'No measurements recorded yet.', 'Empty', 'Icon', 'info');
            return;
        end

        [fn, fp] = uiputfile('*.csv', 'Export Measurements');
        if isequal(fn, 0), return; end

        try
            writeMeasurementsCSV(fullfile(fp, fn), ctx.appData.measurementLog);
            ctx.setStatus(sprintf('Exported %d measurements to %s', ...
                numel(ctx.appData.measurementLog), fn));
        catch ME
            fermiViewer.chrome.quietAlert(ctx.fig, sprintf('Cannot write to:\n%s\n\n%s', fn, ME.message), ...
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
        dispImg = fullResDisplayImg(ctx);
        if strcmpi(ext, '.png')
            imwrite(uint8(dispImg * 255), outPath);
        else
            imwrite(uint16(dispImg * 65535), outPath);
        end

    % ── writeMeasurementsCSV (headless) ───────────────────────────
    case 'writemeasurementscsv'
        % NOTE: intentionally NOT guarded for an empty log. The headless
        % API contract is that exportMeasurements THROWS on an empty log so
        % scripts get a hard error (see test_fv_angle_polyline_export); the
        % GUI button path warns gently instead. Different contexts by design.
        writeMeasurementsCSV(varargin{1}, ctx.appData.measurementLog);

    otherwise
        warning('fermiViewer:export:dispatch:unknownAction', ...
            'Unknown export action "%s".', action);
end
end

% ════════════════════════════════════════════════════════════════════
%  LOCAL: makeNativeAxesCopy — offscreen 1:1 copy of the image axes
% ════════════════════════════════════════════════════════════════════
function [tmpFig, newAx, outW, outH] = makeNativeAxesCopy(ctx)
%MAKENATIVEAXESCOPY  Copy the live axes into an offscreen uifigure whose
%   plot box is exactly one canvas pixel per visible image pixel.
%
%   Two fidelity problems make the live axes unusable as a capture
%   source: (1) exportgraphics/copygraphics rasterize the image at the
%   axes' physical on-screen size (window and monitor dependent), and
%   (2) in HQ render mode the on-screen CData is an area-downsampled
%   buffer, not the data. The copy fixes both: the inner plot box is
%   sized to the visible region's native pixel count (96 DPI == 1 MATLAB
%   px per output px), and the copied image's CData is replaced with the
%   full-resolution contrast-processed pixels. Overlays — including
%   HandleVisibility='off' ones — ride along via copyobj.
%
%   Caller owns tmpFig and must delete it (use onCleanup).

    ax = ctx.ax;
    outW = max(2, round(diff(ax.XLim)));
    outH = max(2, round(diff(ax.YLim)));

    tmpFig = uifigure('Visible', 'off', 'Position', [100 100 outW outH]);
    newAx = copyobj(ax, tmpFig);
    newAx.Units = 'pixels';
    newAx.InnerPosition = [1 1 outW outH];

    % Decorations land inside the export's tight crop and would widen the
    % output past the image bounds — strip them from the copy.
    title(newAx, '');
    newAx.Box = 'off';
    newAx.XAxis.Visible = 'off';
    newAx.YAxis.Visible = 'off';

    % Swap the (possibly downsampled) display buffer for native pixels.
    % EDS/compare composites already live at image coordinates and are
    % not backed by filteredPixels (same guard as prepareDisplayBuffer).
    ad = ctx.appData;
    inComposite = (isfield(ad, 'edsMode') && ad.edsMode) || ...
        (isfield(ad, 'compareMode') && ad.compareMode);
    if ~inComposite && ~isempty(ad.filteredPixels)
        imgs = findall(newAx, 'Type', 'image');
        if isscalar(imgs)
            [imH, imW] = size(ad.filteredPixels);
            imgs.CData = ctx.applyContrast(double(ad.filteredPixels), ...
                ctx.sldLowValue, ctx.sldHighValue);
            imgs.XData = [1 imW];
            imgs.YData = [1 imH];
        end
    end
    drawnow;
end

% ════════════════════════════════════════════════════════════════════
%  LOCAL: fullResDisplayImg — contrast pipeline at native resolution
% ════════════════════════════════════════════════════════════════════
function dispImg = fullResDisplayImg(ctx)
%FULLRESDISPLAYIMG  Processed image at native pixel count for file output.
%   appData.displayImg is the on-screen buffer, which in HQ render mode
%   is area-downsampled to ~1.5x the axes size — writing it to disk gives
%   files whose pixel counts don't match the source. Rebuild from
%   filteredPixels instead. EDS/compare modes own displayImg directly
%   (RGB composites, no filteredPixels backing) and keep the buffer.
    ad = ctx.appData;
    if (isfield(ad, 'edsMode') && ad.edsMode) || ...
            (isfield(ad, 'compareMode') && ad.compareMode) || ...
            isempty(ad.filteredPixels)
        dispImg = ad.displayImg;
        return;
    end
    dispImg = ctx.applyContrast(double(ad.filteredPixels), ...
        ctx.sldLowValue, ctx.sldHighValue);
end

% ════════════════════════════════════════════════════════════════════
%  LOCAL: burnTextOnFrame — render text onto RGB image
% ════════════════════════════════════════════════════════════════════
function rgb = burnTextOnFrame(rgb, str, cx, topY, color)
%BURNTEXTONFRAME  Render a text label into an RGB frame, pixel-exact.
%   The previous legacy-figure getframe capture came back at the wrong
%   size on DPI-scaled setups (799x599 for an 800x600 frame on R2025b)
%   and the bilinear resize-back resampled the ENTIRE frame — every GIF
%   exported with a scale bar had degraded frames. Render offscreen in
%   an exactly-sized uifigure instead; if capture fails, return the
%   frame unmodified (no label) rather than resampling it.
    [fH, fW, ~] = size(rgb);
    tmpFig = uifigure('Visible', 'off', 'Position', [100 100 fW fH]);
    cleaner = onCleanup(@() delete(tmpFig));
    tmpAx = axes(tmpFig, 'Units', 'pixels', ...
        'XLim', [0.5 fW+0.5], 'YLim', [0.5 fH+0.5], 'YDir', 'reverse', ...
        'Visible', 'off', 'Color', 'none');
    tmpAx.InnerPosition = [1 1 fW fH];
    image(tmpAx, 'CData', rgb, 'XData', [1 fW], 'YData', [1 fH]);
    fontSize = max(8, round(fH * 0.025));
    text(tmpAx, cx, topY - round(fH*0.005), str, ...
        'Color', color, 'FontSize', fontSize, ...
        'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'bottom', ...
        'FontWeight', 'bold');
    drawnow;
    out = fermiViewer.export.captureAxesExact(tmpFig, tmpAx, fW, fH);
    if ~isempty(out)
        rgb = out;
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
