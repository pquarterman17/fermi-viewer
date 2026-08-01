function appData = imageOps(action, appData, ctx)
%IMAGEOPS  Dispatch table for image open/remove callbacks extracted from
%   FermiViewer.m.
%
%   Syntax
%     appData = fermiViewer.processing.imageOps('open',   appData, ctx)
%     appData = fermiViewer.processing.imageOps('remove', appData, ctx)
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
            '*.tif;*.tiff;*.jpg;*.jpeg;*.png;*.bmp;*.raw;*.dm3;*.dm4;*.bcf;*.ser;*.mrc;*.mrcs', 'All Supported Images'; ...
            '*.tif;*.tiff',                   'TIFF Files (*.tif, *.tiff)'; ...
            '*.jpg;*.jpeg;*.png;*.bmp',       'Common Images (*.jpg, *.png, *.bmp)'; ...
            '*.dm3;*.dm4',                    'Gatan Files (*.dm3, *.dm4)'; ...
            '*.bcf',                          'Bruker EDS Files (*.bcf)'; ...
            '*.ser',                          'FEI SER Files (*.ser)'; ...
            '*.mrc;*.mrcs',                   'MRC Files (*.mrc, *.mrcs)'; ...
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
            fermiViewer.chrome.quietAlert(fig, sprintf('Error loading files:\n%s', ME.message), ...
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

        selIdx = fermiViewer.display.imageListSelection(lbImages);
        selIdx = selIdx(selIdx > 0 & selIdx <= numel(appData.images));
        if isempty(selIdx)
            return;
        end

        if numel(selIdx) > 1
            answer = fermiViewer.chrome.quietConfirm(fig, ...
                sprintf('Remove %d selected images?', numel(selIdx)), ...
                'Confirm Remove', 'Options', {'Remove', 'Cancel'}, ...
                'DefaultOption', 'Remove', 'CancelOption', 'Cancel');
            if strcmp(answer, 'Cancel'), return; end
        end

        appData.images(selIdx) = [];
        if numel(appData.imageContrastState) >= max(selIdx)
            appData.imageContrastState(selIdx) = [];
        end

        % Keep EDS channel source-image indices valid after the removal:
        % a channel whose source image was removed is hidden; the rest
        % shift down by the number of removed images that preceded them.
        % Cube-derived channels (imageIdx < 1, backed by .map) are untouched.
        if isfield(appData, 'edsChannels') && ~isempty(appData.edsChannels)
            for ci = 1:numel(appData.edsChannels)
                ch = appData.edsChannels{ci};
                if ~isfield(ch, 'imageIdx') || ch.imageIdx < 1, continue; end
                if any(selIdx == ch.imageIdx)
                    ch.visible  = false;
                    ch.imageIdx = 0;
                else
                    ch.imageIdx = ch.imageIdx - sum(selIdx < ch.imageIdx);
                end
                appData.edsChannels{ci} = ch;
            end
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
        % Widget-enable side effects read the freshly-pruned LOCAL appData
        % and mutate handles directly — safe regardless of closure timing.
        ctx.btnCompare.Enable = ctx.cb.onOff(numel(appData.images) >= 2);
        ctx.btnEDSToolbar.Enable = ctx.cb.onOff(numel(appData.images) >= 1);

        % NOTE: the list refresh + display are deliberately NOT run here.
        % rebuildImageList()/displayImage()/clearDisplay() are closure
        % callbacks that read the CALLER'S appData, which still holds the
        % removed image until the caller reassigns it from our return value.
        % Running them here rebuilt the listbox from stale state, so the
        % file never disappeared ("can't remove"). The caller
        % (onRemoveImage) runs them after `appData = imageOps(...)`.
        % See the closure-mutation-ordering hazard.

    % ────────────────────────────────────────────────────────────────────
    otherwise
        error('fermiViewer:processing:imageOps:unknownAction', ...
            'Unknown action "%s".', action);

end
end
