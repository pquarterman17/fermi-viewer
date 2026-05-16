function appData = sessionOps(action, appData, ctx)
%SESSIONOPS  Dispatch table for session/file-management callbacks extracted
%   from FermiViewer.m.
%
%   Syntax
%     appData = emViewer.sessionOps('load',             appData, ctx)
%     appData = emViewer.sessionOps('renameBatch',      appData, ctx)
%     appData = emViewer.sessionOps('refreshImageList', appData, ctx)
%     appData = emViewer.sessionOps('fileDrop',         appData, ctx)
%
%   ctx fields (widgets)
%     ctx.fig, ctx.lbImages, ctx.sldGamma, ctx.efGamma, ctx.ddColormap,
%     ctx.efRenameBase, ctx.sldLow, ctx.sldHigh, ctx.inPath, ctx.idxs, ctx.evt
%
%   ctx.cb callbacks — see buildSessionCtx in FermiViewer.m

switch action

    % ────────────────────────────────────────────────────────────────────
    case 'load'
    %SESSIONLOADAPI  Load a session .mat file and restore state.
        inPath = ctx.inPath;
        fig = ctx.fig;

        fig.Pointer = 'watch'; drawnow;
        try
            tmp = load(inPath, 'session');
            if ~isfield(tmp, 'session')
                uialert(fig, 'Not a valid session file.', 'Error', 'Icon', 'error');
                fig.Pointer = 'arrow'; return;
            end
            s = tmp.session;
            appData.images        = s.images;
            appData.activeIdx     = s.activeIdx;
            appData.imageContrastState = cell(1, numel(appData.images));
            appData.lastDisplayedIdx   = 0;
            if isfield(s, 'gamma')
                appData.gamma = s.gamma;
                ctx.sldGamma.Value = s.gamma;
                ctx.efGamma.Value = s.gamma;
            end
            if isfield(s, 'roiList'), appData.roiList = s.roiList; end
            if isfield(s, 'measureLog'), appData.measurementLog = s.measureLog; end
            if isfield(s, 'edsChannels'), appData.edsChannels = s.edsChannels; end
            if isfield(s, 'colormap') && ismember(s.colormap, ctx.ddColormap.Items)
                ctx.ddColormap.Value = s.colormap;
            end
            if isfield(s, 'prefs')
                flds = fieldnames(s.prefs);
                for fi2 = 1:numel(flds)
                    appData.prefs.(flds{fi2}) = s.prefs.(flds{fi2});
                end
            end
            ctx.cb.rebuildImageList();
            if appData.activeIdx >= 1 && appData.activeIdx <= numel(appData.images)
                ctx.cb.displayImage();
                if isfield(s, 'contrastLow') && isfield(s, 'contrastHigh')
                    lo2 = max(ctx.sldLow.Limits(1), min(ctx.sldLow.Limits(2), s.contrastLow));
                    hi2 = max(ctx.sldHigh.Limits(1), min(ctx.sldHigh.Limits(2), s.contrastHigh));
                    if lo2 < hi2
                        ctx.sldLow.Value  = lo2;
                        ctx.sldHigh.Value = hi2;
                    end
                    ctx.cb.refreshDisplay();
                end
            end
            appData.sessionFile = inPath;
            ctx.cb.setStatus(sprintf('Session loaded: %d images from %s', numel(appData.images), inPath));
        catch ME
            uialert(fig, sprintf('Load failed:\n%s', ME.message), ...
                'Session Error', 'Icon', 'error');
        end
        fig.Pointer = 'arrow';

    % ────────────────────────────────────────────────────────────────────
    case 'renameBatch'
    %RENAMEBATCH  Rename files on disk with baseName_001, _002, ... pattern.
        fig  = ctx.fig;
        idxs = ctx.idxs;

        if isempty(appData.images)
            ctx.cb.setStatus('No images loaded.'); return;
        end

        baseName = strtrim(ctx.efRenameBase.Value);
        if isempty(baseName)
            ctx.cb.setStatus('Enter a base name before renaming.');
            return;
        end

        msg = sprintf('Rename %d file(s) on disk to %s_001, _002, ...?\nThis cannot be undone.', ...
            numel(idxs), baseName);
        answer = uiconfirm(fig, msg, 'Confirm Batch Rename', ...
            'Options', {'Rename', 'Cancel'}, 'DefaultOption', 2, 'CancelOption', 2);
        if ~strcmp(answer, 'Rename'), return; end

        fig.Pointer = 'watch'; drawnow;
        nRenamed = 0;
        for ri = 1:numel(idxs)
            ki = idxs(ri);
            try
                srcPath = appData.images{ki}.metadata.source;
                [srcDir, ~, srcExt] = fileparts(srcPath);
                newName = sprintf('%s_%03d%s', baseName, ri, srcExt);
                newPath = fullfile(srcDir, newName);

                if ~strcmp(srcPath, newPath)
                    if isfile(newPath)
                        warning('FermiViewer:rename', ...
                            'Skipped %s: target %s already exists.', srcPath, newName);
                        continue;
                    end
                    movefile(srcPath, newPath);
                    appData.images{ki}.metadata.source = newPath;
                    nRenamed = nRenamed + 1;
                end
            catch ME
                warning('FermiViewer:rename', 'Failed to rename %s: %s', ...
                    srcPath, ME.message);
            end
        end

        appData = emViewer.sessionOps('refreshImageList', appData, ctx);
        fig.Pointer = 'arrow';
        ctx.cb.setStatus(sprintf('Renamed %d / %d files with base "%s".', ...
            nRenamed, numel(idxs), baseName));

    % ────────────────────────────────────────────────────────────────────
    case 'refreshImageList'
    %REFRESHIMAGELIST  Rebuild listbox items from current appData.images.
        lbImages = ctx.lbImages;

        if isempty(appData.images)
            lbImages.Items = {'(no images loaded)'};
            lbImages.ItemsData = {0};
            return;
        end
        names = cell(1, numel(appData.images));
        data  = cell(1, numel(appData.images));
        for ri = 1:numel(appData.images)
            [~, nm, ex] = fileparts(appData.images{ri}.metadata.source);
            names{ri} = [nm ex];
            data{ri}  = ri;
        end
        lbImages.Items = names;
        lbImages.ItemsData = data;
        if appData.activeIdx >= 1 && appData.activeIdx <= numel(appData.images)
            lbImages.Value = {appData.activeIdx};
        end

    % ────────────────────────────────────────────────────────────────────
    case 'fileDrop'
    %ONFILEDROP  Handle drag-and-drop files onto the figure.
        evt = ctx.evt;

        if isempty(evt) || ~isprop(evt, 'Items')
            return;
        end

        items = evt.Items;
        fpaths = {};

        for ki = 1:numel(items)
            fp = items(ki);
            if ischar(fp) || isstring(fp)
                fp = char(fp);
            elseif isstruct(fp) && isfield(fp, 'Path')
                fp = char(fp.Path);
            else
                continue;
            end

            [~, ~, ext] = fileparts(fp);
            if ismember(lower(ext), {'.tif', '.tiff', '.raw', '.dm3', '.dm4'})
                fpaths{end+1} = fp; %#ok<AGROW>
            end
        end

        if ~isempty(fpaths)
            ctx.cb.loadImagesFromPaths(fpaths);
        end

    % ────────────────────────────────────────────────────────────────────
    otherwise
        error('emViewer:sessionOps:unknownAction', ...
            'Unknown action "%s".', action);

end
end
