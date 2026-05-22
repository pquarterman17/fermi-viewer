function hScaleBar = compareImage(targetAx, dataStruct, idx, cbScaleBarValue, scaleBarColor, scaleBarFontSize, clickCb)
%COMPAREIMAGE  Render one image into a compare-mode axes panel.
%
% Syntax:
%   hScaleBar = emViewer.compareImage(targetAx, dataStruct, idx, ...
%       cbScaleBarValue, scaleBarColor, scaleBarFontSize, clickCb)
%
% Inputs:
%   targetAx         - uiaxes to render into (axL or axR)
%   dataStruct       - image data struct (.metadata.parserSpecific.imageData)
%   idx              - image list index (for title label)
%   cbScaleBarValue  - logical; true to add scale bar if calibrated
%   scaleBarColor    - [1x3] RGB for scale bar
%   scaleBarFontSize - scalar font size for scale bar label
%   clickCb          - function handle for panel click ButtonDownFcn
%
% Outputs:
%   hScaleBar - graphics handle for the scale bar ([] if not added)
%               Caller is responsible for calling makeScaleBarDraggable(hScaleBar)
%               and storing it in appData.overlays.scalebarL/R.
%
% Examples:
%   hB = emViewer.compareImage(axL, ds, 1, cbScaleBar.Value, ...
%       appData.scaleBarColor, spnScaleBarFont.Value, @(~,~) switchPanel());
%   if ~isempty(hB), makeScaleBarDraggable(hB); end

% ════════════════════════════════════════════════════════════════════

hScaleBar = [];
if isempty(targetAx) || ~isvalid(targetAx)
    return;
end

imgInfo = dataStruct.metadata.parserSpecific.imageData;
pixels  = imgInfo.pixels;

% Convert to grayscale double
if imgInfo.numChannels == 3
    pixDouble = double(pixels);
    rawGray = 0.299*pixDouble(:,:,1) + 0.587*pixDouble(:,:,2) + 0.114*pixDouble(:,:,3);
else
    rawGray = double(pixels);
end

% Auto-contrast (2nd/98th percentile)
pLow  = imaging.percentile(rawGray(:), 2);
pHigh = imaging.percentile(rawGray(:), 98);
if pLow >= pHigh
    pLow  = min(rawGray(:));
    pHigh = max(rawGray(:));
end
if pHigh <= pLow, pHigh = pLow + 1; end

dispImg = max(0, min(1, (rawGray - pLow) / (pHigh - pLow)));
[H, W] = size(rawGray);

delete(targetAx.Children);
cla(targetAx);
imagesc(targetAx, 'XData', [1 W], 'YData', [1 H], 'CData', dispImg);
targetAx.CLim = [0 1];
targetAx.YDir = 'reverse';
axis(targetAx, 'equal');
targetAx.XLim = [0.5, W + 0.5];
targetAx.YLim = [0.5, H + 0.5];
targetAx.XTick = [];
targetAx.YTick = [];

[~, fname, fext] = fileparts(dataStruct.metadata.source);
title(targetAx, sprintf('[%d] %s%s', idx, fname, fext), ...
    'Interpreter', 'none', 'FontSize', 11);

% Attach click callback to axes and image object
targetAx.ButtonDownFcn = clickCb;
imgObj = findobj(targetAx, 'Type', 'image');
if ~isempty(imgObj)
    imgObj(1).ButtonDownFcn = clickCb;
end

% Scale bar (caller must makeScaleBarDraggable on returned handle)
if cbScaleBarValue && imgInfo.calibrated && ~isnan(imgInfo.pixelSize)
    hScaleBar = imaging.addScaleBar(targetAx, imgInfo.pixelSize, imgInfo.pixelUnit, ...
        'Color', scaleBarColor, 'FontSize', scaleBarFontSize);
end

end
