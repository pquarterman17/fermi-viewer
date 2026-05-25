function updateStatusBar(appData, ui)
%UPDATESTATUSBAR  Refresh the status-bar labels (dims/bits/pixel size).
%
%   fermiViewer.display.updateStatusBar(appData, ui)
%
%   ui fields: .lblStatusDims, .lblStatusBits, .lblStatusPixSize,
%              .lblStatusMouse, .lblStatusMode (optional)

    % Capture-mode readout (independent of whether an image is loaded).
    if isfield(ui, 'lblStatusMode') && isvalid(ui.lblStatusMode)
        modeTxt = '';
        mode = '';
        if isfield(appData, 'captureMode'); mode = char(appData.captureMode); end
        if ~isempty(mode)
            tbl = fermiViewer.captureModeTable();
            if isfield(tbl, mode)
                modeTxt = ['● ' upper(tbl.(mode).label)];
            else
                modeTxt = ['● ' upper(mode)];
            end
        end
        ui.lblStatusMode.Text = modeTxt;
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
