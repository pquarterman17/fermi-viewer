function hScaleBar = compareImage(targetAx, dataStruct, idx, cbScaleBarValue, scaleBarColor, scaleBarFontSize, clickCb, contrastParams)
%COMPAREIMAGE  Render one image into a compare-mode axes panel.
%
% Syntax:
%   hScaleBar = fermiViewer.compare.compareImage(targetAx, dataStruct, idx, ...
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
%   contrastParams   - (optional) struct with fields lo, hi, gamma,
%                      transform, invert. When present and valid, the image
%                      is rendered through fermiViewer.contrast.applyPipeline
%                      with this window instead of an auto-stretch. Pass []
%                      (or omit) for the default 0.35/99.65 auto-contrast.
%
% Outputs:
%   hScaleBar - graphics handle for the scale bar ([] if not added)
%               Caller is responsible for calling makeScaleBarDraggable(hScaleBar)
%               and storing it in appData.overlays.scalebarL/R.
%
% Examples:
%   hB = fermiViewer.compare.compareImage(axL, ds, 1, cbScaleBar.Value, ...
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

% Contrast: honour an explicit per-panel window (from the contrast
% controls in compare mode) when supplied; otherwise auto-stretch.
useCps = nargin >= 8 && isstruct(contrastParams) && ~isempty(contrastParams) ...
    && isfield(contrastParams, 'lo') && isfield(contrastParams, 'hi') ...
    && isfinite(contrastParams.lo) && isfinite(contrastParams.hi) ...
    && contrastParams.hi > contrastParams.lo;
if useCps
    tfm = 'linear';
    if isfield(contrastParams, 'transform'), tfm = contrastParams.transform; end
    g = 1.0;
    if isfield(contrastParams, 'gamma'), g = contrastParams.gamma; end
    inv = false;
    if isfield(contrastParams, 'invert'), inv = logical(contrastParams.invert); end
    dispImg = fermiViewer.contrast.applyPipeline(rawGray, ...
        contrastParams.lo, contrastParams.hi, tfm, g, inv);
else
    % Auto-contrast (0.35th/99.65th percentile — DM/ImageJ-matched)
    pLow  = imaging.percentile(rawGray(:), 0.35);
    pHigh = imaging.percentile(rawGray(:), 99.65);
    if pLow >= pHigh
        pLow  = min(rawGray(:));
        pHigh = max(rawGray(:));
    end
    if pHigh <= pLow, pHigh = pLow + 1; end
    dispImg = max(0, min(1, (rawGray - pLow) / (pHigh - pLow)));
end
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
