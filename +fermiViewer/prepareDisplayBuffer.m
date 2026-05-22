function appData = prepareDisplayBuffer(appData, ui, pushToImage, callbacks)
%PREPAREDISPLAYBUFFER  Build display buffer from filtered pixels.
%
%   Syntax
%     appData = emViewer.prepareDisplayBuffer(appData, ui)
%     appData = emViewer.prepareDisplayBuffer(appData, ui, pushToImage)
%     appData = emViewer.prepareDisplayBuffer(appData, ui, pushToImage, callbacks)
%
%   Inputs
%     appData     - FermiViewer app state struct (modified; returned)
%     ui          - struct of UI widget handles; uses:
%                     .ax           — main image axes (for XLim/YLim/InnerPosition)
%                     .sldLow       — contrast low slider (read when pushToImage=true)
%                     .sldHigh      — contrast high slider (read when pushToImage=true)
%     pushToImage - (optional, default false) when true, update imgHandle CData
%     callbacks   - (optional) struct of function handles:
%                     .applyContrastPipeline(pixels, lo, hi) -> dispImg
%                   Required only when pushToImage is true.
%
%   Outputs
%     appData - updated with .displayPixels and .displayRegion set;
%               also .displayImg and .imgHandle CData updated when
%               pushToImage is true.
%
%   Notes
%     Extracted from FermiViewer.m to reduce monolith line count.
%     Mirrors prepareDisplayBuffer() nested function exactly.

% ════════════════════════════════════════════════════════════════════════

if nargin < 3, pushToImage = false; end

if isempty(appData.filteredPixels)
    appData.displayPixels = [];
    return;
end

% Listener path: skip if no image drawn yet or Fast mode renders at
% native resolution (no rebuild needed on zoom).
if pushToImage && (isempty(appData.imgHandle) || ...
        ~isvalid(appData.imgHandle) || ...
        ~strcmp(appData.renderMode, 'hq'))
    return;
end

[H, W] = size(appData.filteredPixels);
x0 = 1; x1 = W; y0 = 1; y1 = H;    % default region = full image

if strcmp(appData.renderMode, 'fast')
    % Fast mode — no preprocessing, CData spans full native pixels.
    appData.displayPixels = double(appData.filteredPixels);
else
    % HQ mode — area-average the VISIBLE region to roughly 1.5x
    % axes pixel size (a little oversampling so minor zoom-in
    % doesn't immediately reveal downsample blocks).
    xLim = ui.ax.XLim; yLim = ui.ax.YLim;
    x0 = max(1, floor(xLim(1))); x1 = min(W, ceil(xLim(2)));
    y0 = max(1, floor(yLim(1))); y1 = min(H, ceil(yLim(2)));
    if x1 <= x0 || y1 <= y0
        x0 = 1; x1 = W; y0 = 1; y1 = H;
    end

    region = appData.filteredPixels(y0:y1, x0:x1);
    regH = y1 - y0 + 1;
    regW = x1 - x0 + 1;

    axPos = ui.ax.InnerPosition;
    axW   = round(axPos(3));
    axH   = round(axPos(4));

    % Guard: InnerPosition returns [0 0 0 0] (or near-zero) before
    % the uifigure Chromium renderer completes its first layout pass.
    % Downsampling to a tiny buffer at this point would produce
    % catastrophic blur. Skip downsampling and let the zoom-listener
    % rebuild correctly after the first render pass.
    if axW < 100 || axH < 100
        appData.displayPixels = double(region);
    else
        targetW = round(axW * 1.5);
        targetH = round(axH * 1.5);

        if regH > targetH || regW > targetW
            appData.displayPixels = imaging.areaDownsample(region, ...
                min(regH, targetH), min(regW, targetW));
        else
            appData.displayPixels = double(region);
        end
    end
end

% Always record the image-coordinate bounds of the display buffer.
appData.displayRegion = [x0, y0, x1, y1];

if pushToImage && ~isempty(appData.imgHandle) && isvalid(appData.imgHandle)
    lo = ui.sldLow.Value; hi = ui.sldHigh.Value;
    dispImg = callbacks.applyContrastPipeline(appData.displayPixels, lo, hi);
    appData.displayImg = dispImg;
    appData.imgHandle.XData = [x0, x1];
    appData.imgHandle.YData = [y0, y1];
    appData.imgHandle.CData = dispImg;
end
