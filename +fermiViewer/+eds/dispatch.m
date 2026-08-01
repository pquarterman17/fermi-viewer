function appData = dispatch(action, appData, ctx)
%DISPATCH  EDS subsystem dispatcher — all EDS callback bodies.
%
% Syntax:
%   appData = fermiViewer.eds.dispatch(action, appData, ctx)
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
            % Prefer cube-derived element channels when the active image is a
            % BCF carrying a decoded EDS hypercube — this makes EDS mode show
            % real element maps instead of the (often blank) SEM survey image.
            cubeCh = {};
            ai = appData.activeIdx;
            if ai >= 1 && ai <= numel(appData.images)
                [bgSel, e0Sel] = resolveEDSMapOptions(ctx);
                cubeCh = fermiViewer.eds.buildCubeChannels( ...
                    appData.images{ai}, defaultColors, Background=bgSel, E0KeV=e0Sel);
            end
            if ~isempty(cubeCh)
                appData.edsChannels = cubeCh;
            else
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
        end

        % Note ordering: setToolsEnabled('off') runs BEFORE the explicit
        % enables below, otherwise it would re-disable EDS-mode-only
        % buttons that setToolsEnabled now correctly guards with
        % `if ~appData.edsMode`. With edsMode already true at this point
        % (set above), setToolsEnabled skips EDS-mode buttons, leaving
        % our explicit enables below in charge.
        ctx.cb.setToolsEnabled('off');
        ctx.btnEnterEDS.Enable = 'on';
        ctx.btnEDSToolbar.Enable = 'on';

        % Channel controls
        ctx.btnAddChannel.Enable        = 'on';
        ctx.btnRemoveChannel.Enable     = 'on';
        ctx.ddChannelColor.Enable       = 'on';
        ctx.cbChannelVisible.Enable     = 'on';
        ctx.sldChannelIntensity.Enable  = 'on';
        ctx.efChannelLabel.Enable       = 'on';
        ctx.btnExportComposite.Enable   = 'on';

        % Quantification controls — must be enabled here because
        % setToolsEnabled skips them in EDS mode (avoid the
        % enable-then-disable race that previously left them off).
        ctx.btnAssignElements.Enable    = 'on';
        ctx.btnQuantifyCL.Enable        = 'on';
        ctx.btnCompositionProfile.Enable = 'on';
        ctx.btnROIComposition.Enable    = 'on';
        ctx.btnQuantifyZAF.Enable       = 'on';
        setExtraEDSControlsEnable(ctx, 'on');

        appData = fermiViewer.eds.dispatch('refreshList', appData, ctx);
        appData = fermiViewer.eds.dispatch('composite',   appData, ctx);
        cubeDerived = ~isempty(appData.edsChannels) && any(cellfun( ...
            @(c) isfield(c, 'map') && ~isempty(c.map), appData.edsChannels));
        if cubeDerived
            ctx.cb.setStatus(sprintf(['EDS mode — %d element map(s) from cube. ' ...
                'Toggle/recolor in Tools > EDS Channels'], numel(appData.edsChannels)));
        else
            ctx.cb.setStatus('EDS composite mode — adjust channels in Tools > EDS Channels');
        end
        appData.edsWorkshop.sync(appData);

    case 'exit'
        appData.edsMode = false;
        appData.edsComposite = [];
        ctx.btnEDSToolbar.Value = false;
        ctx.btnEnterEDS.Text = 'Enter EDS Mode';
        ctx.btnEnterEDS.BackgroundColor = ctx.BTN_PRIMARY;
        ctx.btnEnterEDS.ButtonPushedFcn = @(~,~) ctx.cb.onEnterEDS();

        % Disable EDS-only buttons BEFORE setToolsEnabled('on') would
        % skip them (edsMode is now false above, so they're back under
        % setToolsEnabled's control — but for cleanliness we set them
        % to 'off' here so exit leaves a clean baseline state).
        ctx.btnAddChannel.Enable        = 'off';
        ctx.btnRemoveChannel.Enable     = 'off';
        ctx.ddChannelColor.Enable       = 'off';
        ctx.cbChannelVisible.Enable     = 'off';
        ctx.sldChannelIntensity.Enable  = 'off';
        ctx.efChannelLabel.Enable       = 'off';
        ctx.btnExportComposite.Enable   = 'off';
        ctx.btnAssignElements.Enable    = 'off';
        ctx.btnQuantifyCL.Enable        = 'off';
        ctx.btnCompositionProfile.Enable = 'off';
        ctx.btnROIComposition.Enable    = 'off';
        ctx.btnQuantifyZAF.Enable       = 'off';
        setExtraEDSControlsEnable(ctx, 'off');

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
            if ~ch.visible, continue; end
            % Cube-derived channels carry their own .map — no grayscale lookup.
            if isfield(ch, 'map') && ~isempty(ch.map), continue; end
            if ch.imageIdx < 1 || ch.imageIdx > numel(appData.images)
                continue;
            end
            if isempty(grays{ch.imageIdx})
                grays{ch.imageIdx} = fermiViewer.eds.getGrayscale( ...
                    appData.images{ch.imageIdx});
            end
        end
        composite = fermiViewer.eds.computeComposite(grays, appData.edsChannels);
        appData.edsComposite = composite;
        appData.displayImg   = composite;

        if ~isempty(ctx.ax) && isvalid(ctx.ax)
            delete(ctx.ax.Children); cla(ctx.ax);
            hImg = image(ctx.ax, composite);
            appData.imgHandle = hImg;
            ctx.cb.attachImageContextMenu(hImg);   % pass directly (closure ordering)
            axis(ctx.ax, 'image');
            ctx.ax.XTick = []; ctx.ax.YTick = [];
            colormap(ctx.ax, feval(ctx.ddColormap.Value, 256));
            % Don't leave a silent black panel: if nothing rendered, say why.
            if max(composite(:)) <= 0
                text(ctx.ax, 0.5, 0.5, ...
                    {'No EDS signal to display', ...
                     'No element maps (EDS cube skipped?) or images are blank.'}, ...
                    'Units', 'normalized', 'HorizontalAlignment', 'center', ...
                    'Color', [0.85 0.85 0.85], 'FontSize', 12, 'FontWeight', 'bold');
            end
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
            % Cube-derived channels (from a BCF EDS hypercube) carry a .map
            % and have no source image — show "(cube)" rather than the
            % meaningless "(img 0)" they used to display.
            if isfield(ch, 'map') && ~isempty(ch.map)
                srcStr = '(cube)';
            else
                srcStr = sprintf('(img %d)', ch.imageIdx);
            end
            items{ci} = sprintf('[%s] %s %s%s', ...
                ch.color, ch.label, srcStr, visStr);
            idata(ci) = ci;
        end
        ctx.lbEDSChannels.Items = items;
        ctx.lbEDSChannels.ItemsData = idata;
        if ~isempty(idata)
            ctx.lbEDSChannels.Value = idata(1);
            appData = fermiViewer.eds.dispatch('populateControls', appData, ctx);
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
        appData = fermiViewer.eds.dispatch('populateControls', appData, ctx);

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
        appData = fermiViewer.eds.dispatch('refreshList', appData, ctx);
        if appData.edsMode
            appData = fermiViewer.eds.dispatch('composite', appData, ctx);
        end

    case 'removeChannel'
        idx = ctx.lbEDSChannels.Value;
        if isempty(idx) || (isnumeric(idx) && idx == 0), return; end
        if idx >= 1 && idx <= numel(appData.edsChannels)
            appData.edsChannels(idx) = [];
        end
        appData = fermiViewer.eds.dispatch('refreshList', appData, ctx);
        if appData.edsMode
            appData = fermiViewer.eds.dispatch('composite', appData, ctx);
        end

    % ── Channel property changes ──────────────────────────────────────────
    case 'propColor'
        idx = ctx.lbEDSChannels.Value;
        if isempty(idx) || idx < 1 || idx > numel(appData.edsChannels), return; end
        appData.edsChannels{idx}.color = ctx.ddChannelColor.Value;
        appData = fermiViewer.eds.dispatch('refreshList', appData, ctx);
        ctx.lbEDSChannels.Value = idx;
        if appData.edsMode, appData = fermiViewer.eds.dispatch('composite', appData, ctx); end

    case 'propVisible'
        idx = ctx.lbEDSChannels.Value;
        if isempty(idx) || idx < 1 || idx > numel(appData.edsChannels), return; end
        appData.edsChannels{idx}.visible = ctx.cbChannelVisible.Value;
        appData = fermiViewer.eds.dispatch('refreshList', appData, ctx);
        ctx.lbEDSChannels.Value = idx;
        if appData.edsMode, appData = fermiViewer.eds.dispatch('composite', appData, ctx); end

    case 'propIntensity'
        idx = ctx.lbEDSChannels.Value;
        if isempty(idx) || idx < 1 || idx > numel(appData.edsChannels), return; end
        appData.edsChannels{idx}.intensity = ctx.sldChannelIntensity.Value;
        ctx.lblEDSIntensity.Text = sprintf('Int: %.2f', ctx.sldChannelIntensity.Value);
        appData = fermiViewer.eds.dispatch('refreshList', appData, ctx);
        ctx.lbEDSChannels.Value = idx;
        if appData.edsMode, appData = fermiViewer.eds.dispatch('composite', appData, ctx); end

    case 'propLabel'
        idx = ctx.lbEDSChannels.Value;
        if isempty(idx) || idx < 1 || idx > numel(appData.edsChannels), return; end
        appData.edsChannels{idx}.label = ctx.efChannelLabel.Value;
        appData = fermiViewer.eds.dispatch('refreshList', appData, ctx);
        ctx.lbEDSChannels.Value = idx;

    % ── Export composite ──────────────────────────────────────────────────
    case 'exportComposite'
        if isempty(appData.edsComposite)
            fermiViewer.chrome.quietAlert(ctx.fig, 'No EDS composite to export.', 'Export', 'Icon', 'warning');
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
            fermiViewer.chrome.quietAlert(ctx.fig, sprintf('Export failed:\n%s', ME.message), ...
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
        appData = fermiViewer.eds.dispatch('refreshList', appData, ctx);
        if appData.edsMode, appData = fermiViewer.eds.dispatch('composite', appData, ctx); end

    otherwise
        error('fermiViewer:eds:dispatch:unknownAction', ...
            'Unknown EDS action: %s', action);
end
end


% ════════════════════════════════════════════════════════════════════════
%  Local helpers — Method/Artifact/Background/Dose controls postdate
%  buildEDSCtx() in FermiViewer.m (a ZERO-nested-function-headroom, tightly
%  line-budgeted file — see matlab-gui-complexity.md), so ctx does not carry
%  dedicated fields for them. They are located instead via the EDS grid that
%  ctx.btnQuantifyCL (an existing ctx field) already lives in, using Tag +
%  findobj. See +fermiViewer/+eds/buildEDSPanel.m for the Tag values and
%  +fermiViewer/+eds/runQuantifyCL.m for the read side used by Quantify.
% ════════════════════════════════════════════════════════════════════════

function setExtraEDSControlsEnable(ctx, state)
%SETEXTRAEDSCONTROLSENABLE  Enable/disable the Method/Artifact/Background/
%   Dose controls alongside the rest of the EDS quantification section.
    edsGL = edsGridOf(ctx);
    if isempty(edsGL), return; end
    tags = {'ddEDSMethod', 'cbEDSRemoveArtifacts', 'ddEDSMapBackground', ...
        'edtEDSE0KeV', 'edtEDSDoseCurrentNA', 'edtEDSDoseLiveTimeS', 'edtEDSZetaSi'};
    for k = 1:numel(tags)
        h = findobj(edsGL, 'Tag', tags{k});
        if ~isempty(h), set(h, 'Enable', state); end
    end
end


function [bg, e0] = resolveEDSMapOptions(ctx)
%RESOLVEEDSMAPOPTIONS  Read the Map BG / E0 (keV) controls that drive the
%   background model fermiViewer.eds.buildCubeChannels uses when building
%   cube-derived element maps on Enter EDS Mode. Defaults ('linear', NaN)
%   match buildCubeChannels' own defaults, so a ctx with no usable handle
%   (e.g. a headless caller that doesn't build a real panel) reproduces
%   today's unchanged behaviour.
    bg = 'linear';
    e0 = NaN;
    edsGL = edsGridOf(ctx);
    if isempty(edsGL), return; end
    h = findobj(edsGL, 'Tag', 'ddEDSMapBackground');
    if ~isempty(h), bg = h(1).Value; end
    h = findobj(edsGL, 'Tag', 'edtEDSE0KeV');
    if ~isempty(h), e0 = str2double(h(1).Value); end
end


function edsGL = edsGridOf(ctx)
%EDSGRIDOF  The edsInnerGL grid that hosts every EDS panel widget, reached
%   via ctx.btnQuantifyCL.Parent (btnQuantifyCL is an existing ctx field
%   set directly inside that grid — see buildEDSPanel.m). Returns [] when
%   ctx carries no usable handle.
    edsGL = [];
    if ~isstruct(ctx) || ~isfield(ctx, 'btnQuantifyCL') || isempty(ctx.btnQuantifyCL) ...
            || ~isgraphics(ctx.btnQuantifyCL)
        return;
    end
    edsGL = ctx.btnQuantifyCL.Parent;
end
