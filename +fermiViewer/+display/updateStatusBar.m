function updateStatusBar(appData, ui)
%UPDATESTATUSBAR  Refresh the status-bar labels (dims/bits/pixel size).
%
%   fermiViewer.display.updateStatusBar(appData, ui)
%
%   ui fields: .lblStatusDims, .lblStatusBits, .lblStatusPixSize,
%              .lblStatusMouse, .lblStatusMode (optional)

    % Capture-mode readout + banner (independent of whether an image loaded).
    mode = '';
    if isfield(appData, 'captureMode'); mode = char(appData.captureMode); end
    modeLabel = ''; bannerTxt = '';
    if ~isempty(mode)
        tbl = fermiViewer.captureModeTable();
        if isfield(tbl, mode)
            modeLabel = tbl.(mode).label;
            bannerTxt = [modeLabel '   —   ' tbl.(mode).steps{1} '      (Esc to cancel)'];
        else
            modeLabel = mode;
            bannerTxt = [modeLabel '      (Esc to cancel)'];
        end
    end

    if isfield(ui, 'lblStatusMode') && isvalid(ui.lblStatusMode)
        if isempty(modeLabel)
            ui.lblStatusMode.Text = '';
        else
            ui.lblStatusMode.Text = ['● ' upper(modeLabel)];
        end
    end

    % Floating capture-mode banner over the axes.
    if isfield(ui, 'captureBanner') && isvalid(ui.captureBanner)
        if isempty(mode)
            ui.captureBanner.Visible = 'off';
        else
            if isfield(ui, 'captureBannerLabel') && isvalid(ui.captureBannerLabel)
                ui.captureBannerLabel.Text = ['●  ' bannerTxt];
            end
            % Re-centre at show time (SizeChangedFcn only fires on resize).
            try
                p = ui.captureBanner.Parent.InnerPosition;
                w = 480; h = 30;
                ui.captureBanner.Position = [max(1, round((p(3)-w)/2)), ...
                    max(1, round(p(4)-72)), w, h];
            catch
            end
            ui.captureBanner.Visible = 'on';
        end
    end

    if appData.activeIdx < 1 || appData.activeIdx > numel(appData.images)
        ui.lblStatusDims.Text    = '-- x -- px';
        ui.lblStatusBits.Text    = '--bit';
        ui.lblStatusPixSize.Text = 'uncalibrated';
        ui.lblStatusMouse.Text   = '';
        return;
    end

    imgInfo = appData.images{appData.activeIdx}.metadata.parserSpecific.imageData;

    ui.lblStatusDims.Text = sprintf('%d x %d px', imgInfo.width, imgInfo.height);
    ui.lblStatusBits.Text = sprintf('%d-bit', imgInfo.bitDepth);

    if imgInfo.calibrated && ~isnan(imgInfo.pixelSize)
        ui.lblStatusPixSize.Text = sprintf('%.4g %s/px', imgInfo.pixelSize, imgInfo.pixelUnit);
    else
        ui.lblStatusPixSize.Text = 'uncalibrated';
    end
end
