function appData = loadImages(fpaths, appData, ui, callbacks)
%LOADIMAGES  Load image files and append to appData.images.
%
%   Syntax
%     appData = emViewer.loadImages(fpaths, appData, ui, callbacks)
%
%   Inputs
%     fpaths    - char path, string, or cell array of paths; each element
%                 may also be a struct with fields: .path, .Width, .Height,
%                 .BitDepth (for RAW files in API mode).
%     appData   - FermiViewer app state struct (modified; returned)
%     ui        - struct of UI widget handles; uses:
%                   .fig  — for uialert dialogs
%     callbacks - struct of function handles:
%                   .showLoading(msg)
%                   .updateLoading(k, n, name)
%                   .hideLoading()
%                   .appendImage(data)       % mutates appData via closure
%                   .addToRecentFiles(fp)
%                   .promptAndLoadRaw(fp)    % returns data or []
%                   .rebuildImageList()
%                   .displayImage()          % wrapper that sets appData
%
%   Outputs
%     appData - updated with new images appended (via callbacks.appendImage
%               which mutates the closure; appData returned from this
%               function reflects any fields the caller tracks locally).
%
%   Notes
%     Extracted from FermiViewer.m to reduce monolith line count.
%     Mirrors loadImagesFromPaths() nested function exactly.
%     For API (no-UI) use, pass a ui struct with .fig = [] and no-op
%     showLoading/updateLoading/hideLoading callbacks.

% ════════════════════════════════════════════════════════════════════════

if ischar(fpaths) || isstring(fpaths)
    fpaths = {char(fpaths)};
end

nFiles = numel(fpaths);
if nFiles > 0
    callbacks.showLoading(sprintf('Loading %d file(s)...', nFiles));
end
loadedAny = false;

for k = 1:nFiles
    entry = fpaths{k};

    if isstruct(entry)
        % RAW file with explicit dimensions (API mode)
        try
            data = parser.importRawImage(entry.path, ...
                Width=entry.Width, Height=entry.Height, ...
                BitDepth=entry.BitDepth);
            callbacks.appendImage(data);
            loadedAny = true;
        catch ME
            warning('FermiViewer:loadFailed', ...
                'Failed to load entry %d: %s', k, ME.message);
        end
        continue;
    end

    fp = char(entry);
    [~, fn, fext] = fileparts(fp);
    callbacks.updateLoading(k, nFiles, [fn fext]);

    [~, ~, ext] = fileparts(fp);
    ext = lower(ext);

    try
        switch ext
            case {'.tif', '.tiff'}
                data = parser.importTIFF(fp);
                callbacks.appendImage(data);
                callbacks.addToRecentFiles(fp);
                loadedAny = true;

            case {'.jpg', '.jpeg', '.png', '.bmp', '.gif'}
                data = parser.importImage(fp);
                callbacks.appendImage(data);
                callbacks.addToRecentFiles(fp);
                loadedAny = true;

            case '.bcf'
                data = parser.importBCF(fp);
                callbacks.appendImage(data);
                callbacks.addToRecentFiles(fp);
                loadedAny = true;

            case {'.spm', '.000', '.001', '.002', '.003'}
                data = parser.importAFM(fp);
                callbacks.appendImage(data);
                callbacks.addToRecentFiles(fp);
                loadedAny = true;

            case '.raw'
                % RAW files need dimensions from user
                data = callbacks.promptAndLoadRaw(fp);
                if ~isempty(data)
                    callbacks.appendImage(data);
                    callbacks.addToRecentFiles(fp);
                    loadedAny = true;
                end

            case '.dm3'
                data = parser.importDM3(fp);
                callbacks.appendImage(data);
                callbacks.addToRecentFiles(fp);
                loadedAny = true;

            case '.dm4'
                data = parser.importDM4(fp);
                callbacks.appendImage(data);
                callbacks.addToRecentFiles(fp);
                loadedAny = true;

            case '.ser'
                data = parser.importSER(fp);
                callbacks.appendImage(data);
                callbacks.addToRecentFiles(fp);
                loadedAny = true;

            case {'.mrc', '.mrcs'}
                data = parser.importMRC(fp);
                callbacks.appendImage(data);
                callbacks.addToRecentFiles(fp);
                loadedAny = true;

            otherwise
                if ~isempty(ui.fig) && isvalid(ui.fig)
                    uialert(ui.fig, ...
                        sprintf('Unsupported file format: "%s"\n\nSupported: .tif, .tiff, .jpg, .png, .bcf, .raw, .dm3, .dm4, .ser, .mrc, .spm, .000', ext), ...
                        'Unsupported Format', 'Icon', 'warning');
                else
                    warning('FermiViewer:unsupported', ...
                        'Unsupported format: %s', ext);
                end
        end
    catch ME
        fprintf(2, '\n[FermiViewer] Load error (%s): %s\n', fp, ME.message);
        for si = 1:numel(ME.stack)
            fprintf(2, '  at %s (line %d)\n', ME.stack(si).name, ME.stack(si).line);
        end
        if ~isempty(ui.fig) && isvalid(ui.fig)
            uialert(ui.fig, ...
                sprintf('Failed to load "%s":\n\n%s', fp, ME.message), ...
                'Load Error', 'Icon', 'error');
        else
            warning('FermiViewer:loadFailed', ...
                'Failed to load "%s": %s', fp, ME.message);
        end
    end
end

callbacks.hideLoading();
if loadedAny
    callbacks.rebuildImageList();
    callbacks.displayImage();
end
