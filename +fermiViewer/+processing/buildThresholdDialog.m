function buildThresholdDialog(pixels, btnColors, hook)
%BUILDTHRESHOLDDIALOG  Live threshold preview with Otsu auto-detect.
    arguments
        pixels    double
        btnColors struct
        hook      struct
    end

    dMin = min(pixels(:));
    dMax = max(pixels(:));
    otsuThresh = emViewer.processing.otsuThreshold(pixels);

    tFig = uifigure('Name', 'Live Threshold Preview', ...
        'Position', [250 200 500 400]);
    tGL = uigridlayout(tFig, [3 1], ...
        'RowHeight', {'1x', 30, 30}, 'Padding', [6 6 6 6]);

    tAx = uiaxes(tGL);
    tAx.Layout.Row = 1;
    imagesc(tAx, pixels); colormap(tAx, gray(256));
    axis(tAx, 'image'); tAx.XTick = []; tAx.YTick = [];
    tAx.Toolbar.Visible = 'off';

    sldRow = uigridlayout(tGL, [1 3], ...
        'ColumnWidth', {60, '1x', 60}, 'Padding', [0 0 0 0]);
    sldRow.Layout.Row = 2;
    uilabel(sldRow, 'Text', 'Threshold:', 'HorizontalAlignment', 'right');
    sldThresh = uislider(sldRow, 'Limits', [dMin dMax], 'Value', otsuThresh);
    sldThresh.Layout.Column = 2;
    sldThresh.MajorTicks = []; sldThresh.MinorTicks = [];
    lblThVal = uilabel(sldRow, 'Text', sprintf('%.0f', otsuThresh));
    lblThVal.Layout.Column = 3;

    btnRowT = uigridlayout(tGL, [1 3], ...
        'ColumnWidth', {'1x', 80, 80}, 'Padding', [0 0 0 0]);
    btnRowT.Layout.Row = 3;
    uilabel(btnRowT, 'Text', sprintf('Otsu: %.0f', otsuThresh), ...
        'FontColor', [0.4 0.7 0.4]);
    uibutton(btnRowT, 'Text', 'Apply', ...
        'BackgroundColor', btnColors.primary, 'FontColor', btnColors.fg, ...
        'ButtonPushedFcn', @(~,~) applyThreshold());
    uibutton(btnRowT, 'Text', 'Cancel', ...
        'ButtonPushedFcn', @(~,~) close(tFig));

    hOverlay = [];
    sldThresh.ValueChangedFcn = @(~,~) updateThreshPreview();
    updateThreshPreview();

    function updateThreshPreview()
        tv = sldThresh.Value;
        lblThVal.Text = sprintf('%.0f', tv);
        bw = pixels > tv;
        if ~isempty(hOverlay) && isvalid(hOverlay)
            delete(hOverlay);
        end
        hold(tAx, 'on');
        alphaMap = double(bw) * 0.35;
        redImg = zeros([size(bw) 3]);
        redImg(:,:,1) = 1;
        hOverlay = image(tAx, 'CData', redImg, 'AlphaData', alphaMap);
        hOverlay.HitTest = 'off';
        hold(tAx, 'off');
    end

    function applyThreshold()
        tv = sldThresh.Value;
        threshResult = double(pixels > tv) .* pixels;
        close(tFig);
        hook.applyResult(threshResult, sprintf('Threshold applied at %.0f', tv));
    end
end
