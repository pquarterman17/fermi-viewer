function appData = dispatch(action, appData, ctx)
%DISPATCH  EDS subsystem dispatcher — all EDS callback bodies.
%
% Syntax:
%   appData = emViewer.eds.dispatch(action, appData, ctx)
%
% Inputs:
%   action  - string action key (see cases below)
%   appData - scalar struct with EDS/image state (modified and returned)
%   ctx     - struct with UI handles and callbacks:
%               ctx.ax, ctx.fig
%               ctx.btnEDSToolbar, ctx.btnEnterEDS
%               ctx.btnAddChannel, ctx.btnRemoveChannel
%               ctx.ddChannelColor, ctx.cbChannelVisible
%               ctx.sldChannelIntensity, ctx.efChannelLabel
%               ctx.btnExportComposite, ctx.lbEDSChannels
%               ctx.lblEDSIntensity, ctx.ddColormap
%               ctx.edtEDSThickness, ctx.edtEDSTakeOff   (ZAF only)
%               ctx.BTN_DANGER, ctx.BTN_PRIMARY, ctx.EDS_COLORS
%               ctx.cb.setStatus(msg)
%               ctx.cb.setToolsEnabled(state)
%               ctx.cb.displayImage()
%               ctx.cb.clearDisplay()
%               ctx.cb.exitCompareMode()
%               ctx.cb.attachImageContextMenu()
%               ctx.cb.onEnterEDS()   (for button callback restoration)
%               ctx.cb.onExitEDS()    (for button callback swap)
%               ctx.apiIdx, ctx.apiField, ctx.apiVal  (setChannelAPI only)
%
% Outputs:
%   appData - updated state struct

switch action

    % ── Enter / Exit ──────────────────────────────────────────────────────
    case 'enter'
        if isempty(appData.images), return; end

        if appData.compareMode
            ctx.cb.exitCompareMode();
            appData.compareMode = false;
        end

        appData.edsMode = true;
        ctx.btnEDSToolbar.Value = true;
        ctx.btnEnterEDS.Text = 'Exit EDS Mode';
        ctx.btnEnterEDS.BackgroundColor = ctx.BTN_DANGER;
        ctx.btnEnterEDS.ButtonPushedFcn = @(~,~) ctx.cb.onExitEDS();

        if isempty(appData.edsChannels)
            defaultColors = ctx.EDS_COLORS;
            nImg = numel(appData.images);
            for ci = 1:nImg
                [~, fn, fe] = fileparts(appData.images{ci}.metadata.source);
                ch.imageIdx  = ci;
                ch.label     = [fn fe];
                ch.color     = defaultColors{mod(ci-1, numel(defaultColors)) + 1};
                ch.visible   = true;
                ch.intensity = 1.0;
                appData.edsChannels{ci} = ch;
            end
        end

        ctx.btnAddChannel.Enable       = 'on';
        ctx.btnRemoveChannel.Enable    = 'on';
        ctx.ddChannelColor.Enable      = 'on';
        ctx.cbChannelVisible.Enable    = 'on';
        ctx.sldChannelIntensity.Enable = 'on';
        ctx.efChannelLabel.Enable      = 'on';
        ctx.btnExportComposite.Enable  = 'on';

        ctx.cb.setToolsEnabled('off');
        ctx.btnEnterEDS.Enable = 'on';
        ctx.btnEDSToolbar.Enable = 'on';

        appData = emViewer.eds.dispatch('refreshList', appData, ctx);
        appData = emViewer.eds.dispatch('composite',   appData, ctx);
        ctx.cb.setStatus('EDS composite mode — adjust channels in Tools > EDS Channels');
        appData.edsWorkshop.sync(appData);

    case 'exit'
        appData.edsMode = false;
        appData.edsComposite = [];
        ctx.btnEDSToolbar.Value = false;
        ctx.btnEnterEDS.Text = 'Enter EDS Mode';
        ctx.btnEnterEDS.BackgroundColor = ctx.BTN_PRIMARY;
        ctx.btnEnterEDS.ButtonPushedFcn = @(~,~) ctx.cb.onEnterEDS();

        ctx.btnAddChannel.Enable       = 'off';
        ctx.btnRemoveChannel.Enable    = 'off';
        ctx.ddChannelColor.Enable      = 'off';
        ctx.cbChannelVisible.Enable    = 'off';
        ctx.sldChannelIntensity.Enable = 'off';
        ctx.efChannelLabel.Enable      = 'off';
        ctx.btnExportComposite.Enable  = 'off';

        ctx.cb.setToolsEnabled('on');

        if appData.activeIdx >= 1 && appData.activeIdx <= numel(appData.images)
            ctx.cb.displayImage();
        else
            ctx.cb.clearDisplay();
        end
        ctx.cb.setStatus('Exited EDS mode');
        appData.edsWorkshop.sync(appData);

    % ── Composite render ─────────────────────────────────────────────────
    case 'composite'
        if ~appData.edsMode || isempty(appData.edsChannels), return; end

        grays = cell(1, numel(appData.images));
        for ci = 1:numel(appData.edsChannels)
            ch = appData.edsChannels{ci};
            if ~ch.visible || ch.imageIdx < 1 || ch.imageIdx > numel(appData.images)
                continue;
            end
            if isempty(grays{ch.imageIdx})
                grays{ch.imageIdx} = emViewer.eds.getGrayscale( ...
                    appData.images{ch.imageIdx});
            end
        end
        composite = emViewer.eds.computeComposite(grays, appData.edsChannels);
        appData.edsComposite = composite;
        appData.displayImg   = composite;

        if ~isempty(ctx.ax) && isvalid(ctx.ax)
            delete(ctx.ax.Children); cla(ctx.ax);
            hImg = image(ctx.ax, composite);
            appData.imgHandle = hImg;
            ctx.cb.attachImageContextMenu();
            axis(ctx.ax, 'image');
            ctx.ax.XTick = []; ctx.ax.YTick = [];
            colormap(ctx.ax, feval(ctx.ddColormap.Value, 256));
        end

    % ── Channel list helpers ──────────────────────────────────────────────
    case 'refreshList'
        if isempty(appData.edsChannels)
            ctx.lbEDSChannels.Items = {'(no channels)'};
            ctx.lbEDSChannels.ItemsData = 0;
            return;
        end
        items = cell(1, numel(appData.edsChannels));
        idata = zeros(1, numel(appData.edsChannels));
        for ci = 1:numel(appData.edsChannels)
            ch = appData.edsChannels{ci};
            visStr = '';
            if ~ch.visible, visStr = ' [hidden]'; end
            items{ci} = sprintf('[%s] %s (img %d)%s', ...
                ch.color, ch.label, ch.imageIdx, visStr);
            idata(ci) = ci;
        end
        ctx.lbEDSChannels.Items = items;
        ctx.lbEDSChannels.ItemsData = idata;
        if ~isempty(idata)
            ctx.lbEDSChannels.Value = idata(1);
            appData = emViewer.eds.dispatch('populateControls', appData, ctx);
        end

    case 'populateControls'
        idx = ctx.lbEDSChannels.Value;
        if isempty(idx) || idx < 1 || idx > numel(appData.edsChannels), return; end
        ch = appData.edsChannels{idx};
        ctx.ddChannelColor.Value      = ch.color;
        ctx.cbChannelVisible.Value    = ch.visible;
        ctx.sldChannelIntensity.Value = ch.intensity;
        ctx.lblEDSIntensity.Text      = sprintf('Int: %.2f', ch.intensity);
        ctx.efChannelLabel.Value      = ch.label;

    case 'channelSelected'
        idx = ctx.lbEDSChannels.Value;
        if isempty(idx) || (isnumeric(idx) && idx == 0), return; end
        appData = emViewer.eds.dispatch('populateControls', appData, ctx);

    % ── Channel list add/remove ───────────────────────────────────────────
    case 'addChannel'
        if appData.activeIdx < 1 || appData.activeIdx > numel(appData.images), return; end
        for ci = 1:numel(appData.edsChannels)
            if appData.edsChannels{ci}.imageIdx == appData.activeIdx
                ctx.cb.setStatus(sprintf('Image %d is already an EDS channel', appData.activeIdx));
                return;
            end
        end
        [~, fn, fe] = fileparts(appData.images{appData.activeIdx}.metadata.source);
        ch.imageIdx  = appData.activeIdx;
        ch.label     = [fn fe];
        nCh = numel(appData.edsChannels);
        ch.color     = ctx.EDS_COLORS{mod(nCh, numel(ctx.EDS_COLORS)) + 1};
        ch.visible   = true;
        ch.intensity = 1.0;
        appData.edsChannels{end+1} = ch;
        appData = emViewer.eds.dispatch('refreshList', appData, ctx);
        if appData.edsMode
            appData = emViewer.eds.dispatch('composite', appData, ctx);
        end

    case 'removeChannel'
        idx = ctx.lbEDSChannels.Value;
        if isempty(idx) || (isnumeric(idx) && idx == 0), return; end
        if idx >= 1 && idx <= numel(appData.edsChannels)
            appData.edsChannels(idx) = [];
        end
        appData = emViewer.eds.dispatch('refreshList', appData, ctx);
        if appData.edsMode
            appData = emViewer.eds.dispatch('composite', appData, ctx);
        end

    % ── Channel property changes ──────────────────────────────────────────
    case 'propColor'
        idx = ctx.lbEDSChannels.Value;
        if isempty(idx) || idx < 1 || idx > numel(appData.edsChannels), return; end
        appData.edsChannels{idx}.color = ctx.ddChannelColor.Value;
        appData = emViewer.eds.dispatch('refreshList', appData, ctx);
        ctx.lbEDSChannels.Value = idx;
        if appData.edsMode, appData = emViewer.eds.dispatch('composite', appData, ctx); end

    case 'propVisible'
        idx = ctx.lbEDSChannels.Value;
        if isempty(idx) || idx < 1 || idx > numel(appData.edsChannels), return; end
        appData.edsChannels{idx}.visible = ctx.cbChannelVisible.Value;
        appData = emViewer.eds.dispatch('refreshList', appData, ctx);
        ctx.lbEDSChannels.Value = idx;
        if appData.edsMode, appData = emViewer.eds.dispatch('composite', appData, ctx); end

    case 'propIntensity'
        idx = ctx.lbEDSChannels.Value;
        if isempty(idx) || idx < 1 || idx > numel(appData.edsChannels), return; end
        appData.edsChannels{idx}.intensity = ctx.sldChannelIntensity.Value;
        ctx.lblEDSIntensity.Text = sprintf('Int: %.2f', ctx.sldChannelIntensity.Value);
        appData = emViewer.eds.dispatch('refreshList', appData, ctx);
        ctx.lbEDSChannels.Value = idx;
        if appData.edsMode, appData = emViewer.eds.dispatch('composite', appData, ctx); end

    case 'propLabel'
        idx = ctx.lbEDSChannels.Value;
        if isempty(idx) || idx < 1 || idx > numel(appData.edsChannels), return; end
        appData.edsChannels{idx}.label = ctx.efChannelLabel.Value;
        appData = emViewer.eds.dispatch('refreshList', appData, ctx);
        ctx.lbEDSChannels.Value = idx;

    % ── Export composite ──────────────────────────────────────────────────
    case 'exportComposite'
        if isempty(appData.edsComposite)
            uialert(ctx.fig, 'No EDS composite to export.', 'Export', 'Icon', 'warning');
            return;
        end
        startPath = appData.lastDir;
        if isempty(startPath) || ~isfolder(startPath), startPath = pwd; end
        [saveName, saveDir] = uiputfile( ...
            {'*.png', 'PNG (*.png)'; '*.tif;*.tiff', 'TIFF (*.tif)'}, ...
            'Export EDS Composite', fullfile(startPath, 'eds_composite.png'));
        if isequal(saveName, 0), return; end
        outPath = fullfile(saveDir, saveName);
        try
            imwrite(uint8(appData.edsComposite * 255), outPath);
            ctx.cb.setStatus(sprintf('EDS composite saved: %s', outPath));
        catch ME
            uialert(ctx.fig, sprintf('Export failed:\n%s', ME.message), ...
                'Error', 'Icon', 'error');
        end

    % ── Programmatic channel setter ───────────────────────────────────────
    case 'setChannelAPI'
        % ctx.apiIdx, ctx.apiField, ctx.apiVal must be set by caller
        idx   = ctx.apiIdx;
        field = ctx.apiField;
        val   = ctx.apiVal;
        if idx < 1 || idx > numel(appData.edsChannels)
            error('FermiViewer:invalidIdx', 'Channel index %d out of range', idx);
        end
        switch field
            case 'color'
                appData.edsChannels{idx}.color = val;
            case 'visible'
                appData.edsChannels{idx}.visible = val;
            case 'intensity'
                appData.edsChannels{idx}.intensity = max(0, min(1, val));
            case 'label'
                appData.edsChannels{idx}.label = val;
            otherwise
                error('FermiViewer:invalidField', 'Unknown field: %s', field);
        end
        appData = emViewer.eds.dispatch('refreshList', appData, ctx);
        if appData.edsMode, appData = emViewer.eds.dispatch('composite', appData, ctx); end

    otherwise
        error('emViewer:eds:dispatch:unknownAction', ...
            'Unknown EDS action: %s', action);
end
end
