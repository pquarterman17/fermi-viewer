function appData = imageOps(action, appData, ctx)
%IMAGEOPS  Dispatch table for image open/remove callbacks extracted from
%   FermiViewer.m.
%
%   Syntax
%     appData = emViewer.imageOps('open',   appData, ctx)
%     appData = emViewer.imageOps('remove', appData, ctx)
%
%   ctx fields (widgets)
%     ctx.fig, ctx.lbImages, ctx.btnCompare, ctx.btnEDSToolbar
%
%   ctx.cb callbacks — see buildImageCtx in FermiViewer.m

switch action

    % ────────────────────────────────────────────────────────────────────
    case 'open'
    %ONOPENFILES  Browse for image files via uigetfile.
        fig = ctx.fig;

        filterSpec = { ...
            '*.tif;*.tiff;*.jpg;*.jpeg;*.png;*.bmp;*.raw;*.dm3;*.dm4;*.bcf;*.ser;*.mrc;*.mrcs;*.spm;*.000;*.001;*.002;*.003', 'All Supported Images'; ...
            '*.tif;*.tiff',                   'TIFF Files (*.tif, *.tiff)'; ...
            '*.jpg;*.jpeg;*.png;*.bmp',       'Common Images (*.jpg, *.png, *.bmp)'; ...
            '*.dm3;*.dm4',                    'Gatan Files (*.dm3, *.dm4)'; ...
            '*.bcf',                          'Bruker EDS Files (*.bcf)'; ...
            '*.ser',                          'FEI SER Files (*.ser)'; ...
            '*.mrc;*.mrcs',                   'MRC Files (*.mrc, *.mrcs)'; ...
            '*.spm;*.000;*.001;*.002;*.003',  'AFM Files (*.spm, *.000)'; ...
            '*.raw',                          'RAW Binary Files (*.raw)'; ...
            '*.*',                            'All Files (*.*)'};

        startDir = appData.lastDir;
        if isempty(startDir) || ~isfolder(startDir)
            startDir = pwd;
        end

        try
            [files, folder] = uigetfile(filterSpec, 'Select Image File(s)', ...
                startDir, 'MultiSelect', 'on');
        catch
            fig.Pointer = 'arrow';
            ctx.cb.setStatus('File browser cancelled or failed.');
            return;
        end

        if isequal(files, 0)
            return;
        end

        appData.lastDir = folder;

        if ischar(files)
            files = {files};
        end

        fpaths = cellfun(@(f) fullfile(folder, f), files, 'UniformOutput', false);

        try
            ctx.cb.loadImagesFromPaths(fpaths);
        catch ME
            ctx.cb.hideLoading();
            fprintf(2, '\n[FermiViewer] Error loading files: %s\n', ME.message);
            for si = 1:numel(ME.stack)
                fprintf(2, '  at %s (line %d)\n', ME.stack(si).name, ME.stack(si).line);
            end
            bosonPlotter.quietAlert(fig, sprintf('Error loading files:\n%s', ME.message), ...
                'Load Error', 'Icon', 'error');
        end

    % ────────────────────────────────────────────────────────────────────
    case 'remove'
    %ONREMOVEIMAGE  Remove selected image(s) from the list.
        fig      = ctx.fig;
        lbImages = ctx.lbImages;

        if isempty(appData.images)
            return;
        end

        selVals = lbImages.Value;
        if iscell(selVals)
            selIdx = [selVals{:}];
        else
            selIdx = selVals;
        end

        selIdx = selIdx(selIdx > 0 & selIdx <= numel(appData.images));
        if isempty(selIdx)
            return;
        end

        if numel(selIdx) > 1
            answer = bosonPlotter.quietConfirm(fig, ...
                sprintf('Remove %d selected images?', numel(selIdx)), ...
                'Confirm Remove', 'Options', {'Remove', 'Cancel'}, ...
                'DefaultOption', 'Remove', 'CancelOption', 'Cancel');
            if strcmp(answer, 'Cancel'), return; end
        end

        appData.images(selIdx) = [];
        if numel(appData.imageContrastState) >= max(selIdx)
            appData.imageContrastState(selIdx) = [];
        end
        if appData.lastDisplayedIdx > 0 && any(selIdx == appData.lastDisplayedIdx)
            appData.lastDisplayedIdx = 0;
        end

        if isempty(appData.images)
            appData.activeIdx = 0;
        elseif appData.activeIdx > numel(appData.images)
            appData.activeIdx = numel(appData.images);
        elseif any(selIdx == appData.activeIdx)
            appData.activeIdx = min(appData.activeIdx, numel(appData.images));
            if appData.activeIdx == 0 && ~isempty(appData.images)
                appData.activeIdx = 1;
            end
        end

        if numel(appData.images) < 2 && appData.compareMode
            ctx.btnCompare.Value = false;
            ctx.cb.exitCompareMode();
        end
        ctx.btnCompare.Enable = ctx.cb.onOff(numel(appData.images) >= 2);
        ctx.btnEDSToolbar.Enable = ctx.cb.onOff(numel(appData.images) >= 1);

        ctx.cb.rebuildImageList();

        if appData.activeIdx > 0
            ctx.cb.displayImage();
        else
            ctx.cb.clearDisplay();
        end

    % ────────────────────────────────────────────────────────────────────
    otherwise
        error('emViewer:imageOps:unknownAction', ...
            'Unknown action "%s".', action);

end
end
