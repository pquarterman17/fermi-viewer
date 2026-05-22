function appData = dispatch(action, appData, ctx)
%DISPATCH  EELS subsystem dispatcher — all EELS callback bodies.
%
% Syntax:
%   appData = emViewer.eels.dispatch(action, appData, ctx)
%
% Inputs:
%   action  - string action key (see cases below)
%   appData - scalar struct with EELS/image state (modified and returned)
%   ctx     - struct with UI handles and callbacks:
%               ctx.ax, ctx.fig
%               ctx.btnEnterEELS
%               ctx.edtEELSPreEdgeStart, ctx.edtEELSPreEdgeEnd
%               ctx.edtEELSSignalStart, ctx.edtEELSSignalEnd
%               ctx.edtEELSEdgeOnset
%               ctx.ddEELSMethod, ctx.chkShowEdges, ctx.ddEdgeFilter
%               ctx.BTN_DANGER, ctx.BTN_PRIMARY
%               ctx.cb.setStatus(msg)
%               ctx.cb.setToolsEnabled(state)
%               ctx.cb.displayImage()
%               ctx.cb.exitCompareMode()
%
% Outputs:
%   appData - updated state struct

switch action

    % ── Enter / Exit ──────────────────────────────────────────────────────
    case 'enter'
        if isempty(appData.images), return; end

        if appData.edsMode
            % Exit EDS mode — clear state in our local appData copy.
            % ctx.cb.onExitEDS is NOT called here to avoid double-write;
            % the EDS-exit UI side-effects are handled via ctx.cb.setToolsEnabled.
            appData.edsMode = false;
            appData.edsComposite = [];
            ctx.cb.setToolsEnabled('on');
        end
        if appData.compareMode
            ctx.cb.exitCompareMode();
            appData.compareMode = false;
        end

        if ~appData.eelsMode
            appData.eelsMode = true;
            ctx.btnEnterEELS.Text = 'Exit EELS';
            ctx.btnEnterEELS.BackgroundColor = ctx.BTN_DANGER;

            idx = appData.activeIdx;
            if idx > 0 && idx <= numel(appData.images)
                ps = appData.images{idx}.metadata.parserSpecific;
                if isfield(ps, 'spectrumData')
                    appData.eelsData = ps.spectrumData;
                    appData.eelsEnergyAxis = ps.spectrumData.energyAxis;
                    if isfield(ps, 'spectrumImage')
                        appData.eelsCube = ps.spectrumImage.cube;
                    end
                end
            end

            if ~isempty(appData.eelsData)
                appData.eelsFig = emViewer.eels.showSpectrum( ...
                    appData.eelsData.energyAxis, double(appData.eelsData.counts), ...
                    appData.eelsFig);
            end

            ctx.cb.setStatus('EELS mode active');
            appData.eelsWorkshop.sync(appData);
        else
            appData = emViewer.eels.dispatch('exit', appData, ctx);
        end

    case 'exit'
        appData.eelsMode       = false;
        appData.eelsData       = [];
        appData.eelsCube       = [];
        appData.eelsEnergyAxis = [];
        ctx.btnEnterEELS.Text = 'Enter EELS';
        ctx.btnEnterEELS.BackgroundColor = ctx.BTN_PRIMARY;

        if ~isempty(appData.eelsFig) && isvalid(appData.eelsFig)
            close(appData.eelsFig);
        end
        appData.eelsFig = [];

        ctx.cb.displayImage();
        ctx.cb.setStatus('');
        appData.eelsWorkshop.sync(appData);

    % ── Main action dispatcher ─────────────────────────────────────────────
    case 'bgFit'
        if isempty(appData.eelsData), return; end
        E = appData.eelsData.energyAxis;
        I = double(appData.eelsData.counts);
        E1 = str2double(ctx.edtEELSPreEdgeStart.Value);
        E2 = str2double(ctx.edtEELSPreEdgeEnd.Value);
        if isnan(E1) || isnan(E2) || E1 >= E2
            ctx.cb.setStatus('Invalid pre-edge window'); return;
        end
        method = ctx.ddEELSMethod.Value;
        try
            r = emViewer.eels.executeBackgroundFit(E, I, [E1 E2], method);
        catch ME
            ctx.cb.setStatus(['EELS background error: ' ME.message]); return;
        end
        if ~isempty(appData.eelsFig) && isvalid(appData.eelsFig)
            eelsAx = findobj(appData.eelsFig, 'Type', 'axes');
            if ~isempty(eelsAx)
                eelsAx = eelsAx(1);
                cla(eelsAx); hold(eelsAx, 'on');
                plot(eelsAx, E, I, 'k-', 'LineWidth', 0.5, 'DisplayName', 'Raw');
                plot(eelsAx, E, r.bg, 'r--', 'LineWidth', 1, 'DisplayName', 'Background');
                plot(eelsAx, E, max(r.signal, 0), 'b-', 'LineWidth', 1, 'DisplayName', 'Signal');
                hold(eelsAx, 'off'); legend(eelsAx, 'show');
                if ~isempty(r.titleStr), title(eelsAx, r.titleStr); end
            end
        end
        ctx.cb.setStatus(r.statusMsg);
        appData.eelsWorkshop.sync(appData);

    case 'showEdges'
        if isempty(appData.eelsFig) || ~isvalid(appData.eelsFig), return; end
        eelsAx = findobj(appData.eelsFig, 'Type', 'axes');
        if isempty(eelsAx), return; end
        eelsAx = eelsAx(1);
        if ~ctx.chkShowEdges.Value
            delete(findobj(eelsAx, 'Tag', 'eels_edge'));
            return;
        end
        emViewer.eels.overlayEdges(eelsAx, ctx.ddEdgeFilter.Value);

    case 'extractMap'
        if isempty(appData.eelsCube), ctx.cb.setStatus('No spectrum image loaded'); return; end
        E1 = str2double(ctx.edtEELSSignalStart.Value);
        E2 = str2double(ctx.edtEELSSignalEnd.Value);
        if isnan(E1) || isnan(E2), ctx.cb.setStatus('Invalid signal window'); return; end
        bgE1 = str2double(ctx.edtEELSPreEdgeStart.Value);
        bgE2 = str2double(ctx.edtEELSPreEdgeEnd.Value);
        bgWin = [];
        if ~isnan(bgE1) && ~isnan(bgE2) && bgE1 < bgE2, bgWin = [bgE1 bgE2]; end
        try
            map = imaging.eelsExtractMap(appData.eelsCube, appData.eelsEnergyAxis, ...
                [E1 E2], 'BackgroundWindow', bgWin);
        catch ME
            ctx.cb.setStatus(['EELS extract error: ' ME.message]); return;
        end
        cla(ctx.ax); imagesc(ctx.ax, map); colorbar(ctx.ax); colormap(ctx.ax, 'hot');
        title(ctx.ax, sprintf('EELS Map: %.0f-%.0f eV', E1, E2)); axis(ctx.ax, 'image');
        ctx.cb.setStatus(sprintf('Extracted map: %.0f-%.0f eV', E1, E2));

    case 'thicknessMap'
        if isempty(appData.eelsCube), ctx.cb.setStatus('No spectrum image loaded'); return; end
        try
            [tMap, mask] = imaging.eelsThicknessMap(appData.eelsCube, appData.eelsEnergyAxis);
        catch ME
            ctx.cb.setStatus(['Thickness map error: ' ME.message]); return;
        end
        cla(ctx.ax); imagesc(ctx.ax, tMap); colorbar(ctx.ax); colormap(ctx.ax, 'parula');
        title(ctx.ax, 't/\lambda thickness map'); axis(ctx.ax, 'image');
        ctx.cb.setStatus(sprintf('Thickness map: mean t/lambda=%.2f', mean(tMap(mask))));

    case 'alignZLP'
        if isempty(appData.eelsCube), ctx.cb.setStatus('No spectrum image loaded'); return; end
        try
            [appData.eelsCube, shifts] = imaging.eelsAlignZLP( ...
                appData.eelsCube, appData.eelsEnergyAxis);
        catch ME
            ctx.cb.setStatus(['ZLP alignment error: ' ME.message]); return;
        end
        appData.eelsData.counts = squeeze(sum(sum(double(appData.eelsCube), 1), 2));
        appData.eelsFig = emViewer.eels.showSpectrum( ...
            appData.eelsData.energyAxis, double(appData.eelsData.counts), ...
            appData.eelsFig);
        ctx.cb.setStatus(sprintf('ZLP aligned: max shift=%.0f channels', max(abs(shifts(:)))));
        appData.eelsWorkshop.sync(appData);

    % ── Navigate toggle ────────────────────────────────────────────────────
    case 'navigateOn'
        if isempty(appData.eelsCube)
            ctx.cb.setStatus('No spectrum image loaded');
            ctx.btnNavToggle.Value = false;
            return;
        end
        appData.captureMode = 'specnav';
        ctx.fig.WindowButtonDownFcn = ctx.cb.onCaptureClick;
        ctx.fig.Pointer = 'crosshair';
        ctx.cb.setStatus('Click on image to show pixel spectrum');

    case 'navigateOff'
        appData.captureMode = '';
        ctx.fig.WindowButtonDownFcn = ctx.cb.onIdleMouseDown;
        ctx.fig.Pointer = 'arrow';
        delete(findobj(ctx.ax, 'Tag', 'specnav_marker'));
        ctx.cb.setStatus('');

    % ── Advanced actions (deconvolve / ELNES / KK / SVD) ─────────────────
    case 'deconvolve'
        if isempty(appData.eelsData), return; end
        E = appData.eelsData.energyAxis;
        I = double(appData.eelsData.counts);
        try
            [ssd, tl] = imaging.eelsFourierLog(E, I);
            appData.eelsSSD = ssd;
            if ~isempty(appData.eelsFig) && isvalid(appData.eelsFig)
                ax2 = findobj(appData.eelsFig, 'Type', 'axes');
                if ~isempty(ax2)
                    hold(ax2(1), 'on');
                    plot(ax2(1), E, ssd, 'm-', 'LineWidth', 1.2, 'DisplayName', 'SSD');
                    hold(ax2(1), 'off');
                    legend(ax2(1), 'show');
                end
            end
            ctx.cb.setStatus(sprintf('Deconvolved: t/lambda=%.2f', tl));
            appData.eelsWorkshop.sync(appData);
        catch ME
            ctx.cb.setStatus(sprintf('Deconvolution failed: %s', ME.message));
        end

    case 'elnes'
        if isempty(appData.eelsData), return; end
        onset = str2double(ctx.edtEELSEdgeOnset.Value);
        if isnan(onset), ctx.cb.setStatus('Invalid edge onset'); return; end
        E = appData.eelsData.energyAxis;
        I = double(appData.eelsData.counts);
        if ~isempty(appData.eelsSSD), I = appData.eelsSSD; end
        E1 = str2double(ctx.edtEELSPreEdgeStart.Value);
        E2 = str2double(ctx.edtEELSPreEdgeEnd.Value);
        if isnan(E1) || isnan(E2), ctx.cb.setStatus('Set pre-edge window first'); return; end
        try
            if ishandle(appData.eelsELNESFig), close(appData.eelsELNESFig); end
            elnesOut = emViewer.eels.executeELNES(E, I, onset, [E1 E2]);
            appData.eelsELNESFig = elnesOut.elnesFig;
            ctx.cb.setStatus(elnesOut.statusMsg);
        catch ME
            ctx.cb.setStatus(sprintf('ELNES failed: %s', ME.message));
        end

    case 'kramersKronig'
        if isempty(appData.eelsData), return; end
        if ishandle(appData.eelsKKFig), close(appData.eelsKKFig); end
        try
            kkOut = emViewer.eels.executeKramersKronig( ...
                appData.eelsData.energyAxis, double(appData.eelsData.counts));
            appData.eelsKKResult = kkOut.kkResult;
            appData.eelsKKFig = kkOut.kkFig;
            ctx.cb.setStatus(kkOut.statusMsg);
            appData.eelsWorkshop.sync(appData);
        catch ME
            ctx.cb.setStatus(sprintf('KK failed: %s', ME.message));
        end

    case 'svd'
        if isempty(appData.eelsCube)
            ctx.cb.setStatus('No spectrum image loaded'); return;
        end
        if ishandle(appData.eelsSVDFig), close(appData.eelsSVDFig); end
        ctx.cb.setStatus('Running SVD decomposition...');
        ctx.fig.Pointer = 'watch'; drawnow;
        try
            svdOut = emViewer.eels.executeSVD(appData.eelsCube, appData.eelsEnergyAxis, ctx.fig);
        catch ME
            ctx.fig.Pointer = 'arrow';
            ctx.cb.setStatus(sprintf('SVD failed: %s', ME.message)); return;
        end
        ctx.fig.Pointer = 'arrow';
        appData.eelsSVDResult = svdOut.svdResult;
        appData.eelsSVDFig = svdOut.svdFig;
        if svdOut.denoised
            appData.eelsCube = svdOut.denoisedCube;
            appData.eelsData.counts = svdOut.sumSpectrum;
            appData.eelsFig = emViewer.eels.showSpectrum( ...
                appData.eelsData.energyAxis, double(appData.eelsData.counts), ...
                appData.eelsFig);
        end
        ctx.cb.setStatus(svdOut.statusMsg);
        appData.eelsWorkshop.sync(appData);

    % ── Programmatic navigate API ──────────────────────────────────────────
    case 'navigateAPI'
        % ctx.apiRow, ctx.apiCol must be set by caller
        if isempty(appData.eelsCube), return; end
        row = ctx.apiRow;
        col = ctx.apiCol;
        [Ny, Nx, ~] = size(appData.eelsCube);
        if row >= 1 && row <= Ny && col >= 1 && col <= Nx
            spec = squeeze(double(appData.eelsCube(row, col, :)));
            appData.eelsFig = emViewer.eels.showSpectrum( ...
                appData.eelsData.energyAxis, double(appData.eelsData.counts), ...
                appData.eelsFig);
            ax2 = findobj(appData.eelsFig, 'Type', 'axes');
            if ~isempty(ax2)
                cla(ax2(1));
                plot(ax2(1), appData.eelsEnergyAxis, spec, 'k-', 'LineWidth', 1);
                title(ax2(1), sprintf('Pixel [%d, %d]', row, col));
            end
        end

    otherwise
        error('emViewer:eels:dispatch:unknownAction', ...
            'Unknown EELS action: %s', action);
end
end
