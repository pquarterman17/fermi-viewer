function appData = displayStackFrame(idx, appData, ui, callbacks)
%DISPLAYSTACKFRAME  Render a specific frame from a multi-frame stack.
%
%   Syntax
%     appData = emViewer.displayStackFrame(idx, appData, ui, callbacks)
%
%   Inputs
%     idx       - frame index (1-based)
%     appData   - FermiViewer app state struct (modified; returned)
%     ui        - struct of UI widget handles; uses:
%                   .sldLow, .sldHigh  — contrast sliders (set and read)
%     callbacks - struct of function handles:
%                   .prepareDisplayBuffer() -> appData (returned)
%                   .applyContrastPipeline(pixels, lo, hi) -> dispImg
%                   .updateHistogram()
%
%   Outputs
%     appData - updated with rawPixels/filteredPixels/displayImg for the
%               requested frame.
%
%   Notes
%     Extracted from FermiViewer.m to reduce monolith line count.
%     Mirrors displayStackFrame() nested function exactly.

% ════════════════════════════════════════════════════════════════════════

if idx < 1 || idx > numel(appData.stackFrames)
    return;
end

frame = appData.stackFrames{idx};
appData.rawPixels      = frame;
appData.filteredPixels = frame;

% Update slider ranges for this frame
dMin = min(frame(:));
dMax = max(frame(:));
if dMax == dMin, dMax = dMin + 1; end
ui.sldLow.Limits  = [dMin, dMax];
ui.sldHigh.Limits = [dMin, dMax];

% Auto-contrast
pLow  = imaging.percentile(frame(:), 2);
pHigh = imaging.percentile(frame(:), 98);
if pLow >= pHigh
    pLow = dMin; pHigh = dMax;
end
ui.sldLow.Value  = pLow;
ui.sldHigh.Value = pHigh;

% Stack frame change — rebuild display buffer for the new frame
appData.displayPixels = [];
appData = callbacks.prepareDisplayBuffer();

dispImg = callbacks.applyContrastPipeline(appData.displayPixels, pLow, pHigh);
appData.displayImg = dispImg;

if ~isempty(appData.imgHandle) && isvalid(appData.imgHandle)
    appData.imgHandle.CData = dispImg;
end

callbacks.updateHistogram();
