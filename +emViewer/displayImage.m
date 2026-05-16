function appData = displayImage(appData, ui, callbacks)
%DISPLAYIMAGE  Core render pipeline — load active image and display on axes.
%
%   Syntax
%     appData = emViewer.displayImage(appData, ui, callbacks)
%
%   Inputs
%     appData   - FermiViewer app state struct (modified; returned)
%     ui        - struct of all UI widget handles used by the render pipeline;
%                 see "UI fields" section below for the full list.
%     callbacks - struct of function handles for intra-closure operations:
%                   .compositeEDS()
%                   .clearDisplay()         -> appData (returned)
%                   .deselectMeasurement()
%                   .cancelCapture()
%                   .clearAllOverlays()
%                   .prepareDisplayBuffer() -> appData (returned)
%                   .applyContrastPipeline(pixels, lo, hi) -> dispImg
%                   .attachImageContextMenu()
%                   .showStackControls(nFrames)
%                   .rebuildScaleBar()
%                   .updateMetadataPanel()
%                   .updateStatusBar()
%                   .updateHistogram()
%                   .setStatus(msg)
%                   .onOff(tf) -> 'on'|'off'
%
%   Outputs
%     appData - updated with new pixel arrays, contrast state, image handle,
%               stack frames, and lastDisplayedIdx.
%
%   Notes
%     Extracted from FermiViewer.m to reduce monolith line count.
%     The wrapper in FermiViewer.m is a ~30-line stub that builds ui_ and
%     callbacks_ structs and reassigns appData from the return value.
%
%   UI fields used (all fields of the ui struct)
%     ax, sldLow, sldHigh, sldGamma, efLow, efHigh, efGamma,
%     lblGamma, ddColormap, ddContrastTransform, cbInvert,
%     lblFilename, cbScaleBar, ddScaleBarColor, spnScaleBarFont,
%     efScaleBarLen, ddScaleBarUnit,
%     btnLineProfile, btnBoxProfile, btnDistance, btnAngle,
%     btnClearOverlays, btnRemoveMeas, spnMeasLabelFont, ddMeasSymbol,
%     ddMeasColor, spnTiltAngle, cbTiltCorrect, ddTiltGeometry,
%     btnRotCW, btnRotCCW, btnFlipH, btnFlipV, btnGaussian, btnMedian,
%     btnShowFFT, btnCLAHE, btnUndoFilters, ddROIShape, btnDrawROI,
%     btnZoomBox, btnZoomDims, btnResetZoom, btnCropImage, btnSaveCrop,
%     btnSaveImage, btnSetPixelSize, btnFFTMask, btnParticles,
%     btnAlignStack, btnColorOverlay, btnExportOverlays, btnBatchExport,
%     btnCreateGIF, btnCopyClipboard, cbColorbar, cbMinimap,
%     cbPixelInspector, btnLiveThresh, btnImgMath, btnWatershed,
%     btnBatchCrop, btnMontage, btnSessionSave, btnEnterEDS, btnGrid,
%     btnExportMeasure, btnDiffRings, btnROIManager, btnCalibrateBar,
%     btnBatchRename, btnRenameSelected, btnDSpacing, spnProfileWidth,
%     btnInvertImg, btnSharpen, btnBinImage, btnMorphOp, btnButterworth,
%     btnRadialProfile, btnAzIntegrate, btnSurfacePlot, btnBatchConvert,
%     btnCustomCmap, btnPlaneLevel, btnRoughness, btnInterfaceFit,
%     btnMultiOtsu, btnLatticeMeasure, btnGPA, btnCTF, btnDefectCount,
%     btnBackProject, btnFigureBuilder, btnJournalExport,
%     btnCalibColorbar, btnMacroRecord, btnFlickerCompare,
%     btn3DSurface, btnLiveFFT, btnTemplateMatch, btnStitchImages,
%     btnNoiseEstimate, btnPubPresets, btnColormapPreset, btnMeasStats,
%     btnBatchMeas, btnExportToDP,
%     btnPlaceAnnot, btnClearAnnot, btnUndoAnnot, ddAnnotColor,
%     btnPlaceArrow, btnPlaceLine, btnPlaceRect, btnPlaceCircle

% ════════════════════════════════════════════════════════════════════════

if appData.compareMode
    return;   % in compare mode, use displayCompareImage instead
end
if appData.edsMode
    callbacks.compositeEDS();
    return;   % in EDS mode, show composite instead of single image
end
if appData.activeIdx < 1 || appData.activeIdx > numel(appData.images)
    appData = callbacks.clearDisplay();
    return;
end

% Persist the outgoing image's contrast/gamma state so it can be
% restored when the user navigates back to it in the same session.
outIdx = appData.lastDisplayedIdx;
if outIdx >= 1 && outIdx <= numel(appData.images) && ...
        ~appData.compareMode && ~appData.edsMode
    while numel(appData.imageContrastState) < outIdx
        appData.imageContrastState{end+1} = [];
    end
    appData.imageContrastState{outIdx} = struct( ...
        'lo',        ui.sldLow.Value, ...
        'hi',        ui.sldHigh.Value, ...
        'gamma',     appData.gamma, ...
        'transform', appData.contrastTransform, ...
        'invert',    appData.contrastInvert, ...
        'colormap',  ui.ddColormap.Value);
end

% Clear any measurement selection when switching images
callbacks.deselectMeasurement();

dataStruct = appData.images{appData.activeIdx};
ps = dataStruct.metadata.parserSpecific;

% Skip non-image data (e.g. 1D spectra from DM3/DM4)
if ~isfield(ps, 'imageData') || ~isfield(ps, 'isImage') || ~ps.isImage
    appData = callbacks.clearDisplay();
    if isfield(callbacks, 'setStatus')
        callbacks.setStatus('Selected file is a spectrum, not an image.');
    end
    return;
end

imgInfo = ps.imageData;
pixels  = imgInfo.pixels;

% Convert to grayscale double (raw, unprocessed)
if imgInfo.numChannels == 3
    pixDouble = double(pixels);
    rawGray = 0.299 * pixDouble(:,:,1) + ...
              0.587 * pixDouble(:,:,2) + ...
              0.114 * pixDouble(:,:,3);
else
    rawGray = double(pixels);
end

% Store the image pipeline state
appData.rawPixels      = rawGray;
appData.filteredPixels = rawGray;

% Clear undo stack on image switch
appData.undoStack = {};

% Detect multi-frame stacks (e.g. multi-page TIFFs)
if isfield(imgInfo, 'numFrames') && imgInfo.numFrames > 1 && ...
        isfield(imgInfo, 'frames') && ~isempty(imgInfo.frames)
    nF = numel(imgInfo.frames);
    appData.stackFrames = cell(1, nF);
    for fk = 1:nF
        frm = imgInfo.frames{fk};
        if size(frm, 3) == 3
            frm = double(frm);
            frm = 0.299*frm(:,:,1) + 0.587*frm(:,:,2) + 0.114*frm(:,:,3);
        else
            frm = double(frm);
        end
        appData.stackFrames{fk} = frm;
    end
    callbacks.showStackControls(nF);
else
    appData.stackFrames = {};
    appData.stackIdx    = 0;
    callbacks.showStackControls(0);
end

% Set slider ranges based on actual data range
dMin = min(rawGray(:));
dMax = max(rawGray(:));
if dMax == dMin
    dMax = dMin + 1;   % avoid degenerate range
end

ui.sldLow.Limits  = [dMin, dMax];
ui.sldHigh.Limits = [dMin, dMax];

% Priority order for initial contrast window:
%   1. In-session saved state (user was already here — restore it)
%   2. DM-saved display window from the parser (DigitalMicrograph
%      stored view — best match for microscopist intent)
%   3. Full pixel range (safe fallback; no aggressive auto-stretch)
pLow  = NaN;
pHigh = NaN;
savedState = [];
if appData.activeIdx <= numel(appData.imageContrastState)
    tmpState = appData.imageContrastState{appData.activeIdx};
    if isstruct(tmpState), savedState = tmpState; end
end

if ~isempty(savedState) && ...
        isfinite(savedState.lo) && isfinite(savedState.hi) && ...
        savedState.hi > savedState.lo
    pLow  = max(dMin, min(dMax, savedState.lo));
    pHigh = max(dMin, min(dMax, savedState.hi));
elseif isfield(imgInfo, 'displayLow') && isfield(imgInfo, 'displayHigh') ...
        && isfinite(imgInfo.displayLow) && isfinite(imgInfo.displayHigh) ...
        && imgInfo.displayHigh > imgInfo.displayLow
    bScale  = 1;
    bOrigin = 0;
    if isfield(imgInfo, 'intensityScale') && isfinite(imgInfo.intensityScale) ...
            && imgInfo.intensityScale ~= 0
        bScale = imgInfo.intensityScale;
    end
    if isfield(imgInfo, 'intensityOrigin') && isfinite(imgInfo.intensityOrigin)
        bOrigin = imgInfo.intensityOrigin;
    end
    pLow  = (imgInfo.displayLow  - bOrigin) / bScale;
    pHigh = (imgInfo.displayHigh - bOrigin) / bScale;
    pLow  = max(dMin, min(dMax, pLow));
    pHigh = max(dMin, min(dMax, pHigh));
end

if ~(isfinite(pLow) && isfinite(pHigh) && pHigh > pLow)
    pLow  = dMin;
    pHigh = dMax;
end
ui.sldLow.Value  = pLow;
ui.sldHigh.Value = pHigh;
ui.efLow.Value   = pLow;
ui.efHigh.Value  = pHigh;

% Restore gamma / transform / invert / colormap from saved state,
% or reset to defaults on first-ever view of this image.
if ~isempty(savedState)
    if isfield(savedState, 'gamma') && isfinite(savedState.gamma)
        appData.gamma = savedState.gamma;
        ui.sldGamma.Value = max(ui.sldGamma.Limits(1), ...
                                min(ui.sldGamma.Limits(2), savedState.gamma));
        ui.efGamma.Value = appData.gamma;
    end
    if isfield(savedState, 'transform') && ...
            any(strcmp(savedState.transform, ui.ddContrastTransform.Items))
        appData.contrastTransform = savedState.transform;
        ui.ddContrastTransform.Value = savedState.transform;
    end
    if isfield(savedState, 'invert')
        appData.contrastInvert = logical(savedState.invert);
        ui.cbInvert.Value = appData.contrastInvert;
    end
    if isfield(savedState, 'colormap') && ...
            any(strcmp(savedState.colormap, ui.ddColormap.Items))
        ui.ddColormap.Value = savedState.colormap;
    end
else
    % Fresh view — reset to defaults so new image doesn't inherit
    % the previous image's adjustments.
    appData.gamma = 1.0;
    ui.sldGamma.Value = 1.0;
    ui.efGamma.Value = 1.0;
    appData.contrastTransform = 'linear';
    ui.ddContrastTransform.Value = 'linear';
    appData.contrastInvert = false;
    ui.cbInvert.Value = false;
end
ui.lblGamma.Text = 'Gamma';

[H, W] = size(rawGray);

% Cancel any in-progress capture before clearing
if ~isempty(appData.captureMode)
    callbacks.cancelCapture();
end

% Clear all overlays (switches image context — old overlays no longer valid)
callbacks.clearAllOverlays();

% Clear the axes and create fresh imagesc (resets zoom on image switch)
if isempty(ui.ax) || ~isvalid(ui.ax), return; end
delete(ui.ax.Children);
cla(ui.ax);

% Build the display buffer. Must happen AFTER filteredPixels is set
% because prepareDisplayBuffer reads from appData.filteredPixels.
appData = callbacks.prepareDisplayBuffer();

% Compute initial contrast-adjusted image via pipeline
dispImg = callbacks.applyContrastPipeline(appData.displayPixels, pLow, pHigh);
appData.displayImg = dispImg;

% Use the buffer's actual image-coordinate extent so MATLAB does NOT
% bilinearly stretch a downsampled buffer across the full native
% coordinate range.
dr = appData.displayRegion;
if isempty(dr), dr = [1, 1, W, H]; end
hImg = imagesc(ui.ax, 'XData', [dr(1) dr(3)], 'YData', [dr(2) dr(4)], 'CData', dispImg);
appData.imgHandle = hImg;
callbacks.attachImageContextMenu();

% Force nearest-neighbor sampling.
try
    hImg.Interpolation = 'nearest';
catch
end

% Apply selected colormap
cmapName = ui.ddColormap.Value;
colormap(ui.ax, feval(cmapName, 256));
ui.ax.CLim = [0 1];

ui.ax.YDir = 'reverse';
axis(ui.ax, 'equal');
ui.ax.XLim = [0.5, W + 0.5];
ui.ax.YLim = [0.5, H + 0.5];
ui.ax.XTick = [];
ui.ax.YTick = [];
title(ui.ax, '');
xlabel(ui.ax, '');
ylabel(ui.ax, '');
ui.ax.Toolbar.Visible = 'off';

% Update filename label in toolbar
[~, fname, fext] = fileparts(dataStruct.metadata.source);
ui.lblFilename.Text = [fname, fext];

% Update metadata panel, status bar, and histogram
callbacks.updateMetadataPanel();
callbacks.updateStatusBar();
callbacks.updateHistogram();

% Enable measurement controls; scale bar only when calibrated
imgInfo2 = dataStruct.metadata.parserSpecific.imageData;
isCalib  = imgInfo2.calibrated && ~isnan(imgInfo2.pixelSize);
ui.cbScaleBar.Enable       = callbacks.onOff(isCalib);
ui.cbScaleBar.Value        = isCalib;   % on by default when calibrated
ui.ddScaleBarColor.Enable  = callbacks.onOff(isCalib);
ui.spnScaleBarFont.Enable  = callbacks.onOff(isCalib);
ui.efScaleBarLen.Enable    = callbacks.onOff(isCalib);
ui.ddScaleBarUnit.Enable   = callbacks.onOff(isCalib);
if isCalib
    callbacks.rebuildScaleBar();
end
ui.btnLineProfile.Enable   = 'on';
ui.btnBoxProfile.Enable    = 'on';
ui.btnDistance.Enable      = 'on';
ui.btnAngle.Enable         = 'on';
ui.btnClearOverlays.Enable = 'on';
ui.btnRemoveMeas.Enable    = 'on';
ui.spnMeasLabelFont.Enable = 'on';
ui.ddMeasSymbol.Enable     = 'on';
ui.ddMeasColor.Enable      = 'on';

% Auto-populate tilt UI from image metadata
ui.spnTiltAngle.Enable    = 'on';
ui.cbTiltCorrect.Enable   = 'on';
ui.ddTiltGeometry.Enable  = 'on';
try
    tiltMetaDeg = imaging.getStageTilt(imgInfo2);
catch
    tiltMetaDeg = NaN;
end
if ~isnan(tiltMetaDeg) && abs(tiltMetaDeg) > 1e-3
    tiltMetaDeg = max(-89.9, min(89.9, tiltMetaDeg));
    ui.spnTiltAngle.Value = tiltMetaDeg;
    ui.cbTiltCorrect.Value = true;
elseif ~ui.cbTiltCorrect.Value
    ui.spnTiltAngle.Value = 0;
end

% Enable processing controls
if isfield(appData, 'transformToolbarBtns')
    for toolbarK = 1:numel(appData.transformToolbarBtns)
        toolbarBtn = appData.transformToolbarBtns(toolbarK);
        if ~isempty(toolbarBtn) && isgraphics(toolbarBtn) && isvalid(toolbarBtn)
            toolbarBtn.Enable = 'on';
        end
    end
end
ui.btnRotCW.Enable       = 'on';
ui.btnRotCCW.Enable      = 'on';
ui.btnFlipH.Enable       = 'on';
ui.btnFlipV.Enable       = 'on';
ui.btnGaussian.Enable    = 'on';
ui.btnMedian.Enable      = 'on';
ui.btnShowFFT.Enable     = 'on';
ui.btnCLAHE.Enable       = 'on';
ui.btnUndoFilters.Enable = 'on';
ui.ddROIShape.Enable     = 'on';
ui.btnDrawROI.Enable     = 'on';
ui.btnZoomBox.Enable     = 'on';
ui.btnZoomDims.Enable    = 'on';
ui.btnResetZoom.Enable   = 'on';
ui.btnCropImage.Enable   = 'on';
ui.btnSaveCrop.Enable    = 'on';
ui.btnSaveImage.Enable   = 'on';
ui.btnSetPixelSize.Enable  = 'on';
ui.btnFFTMask.Enable       = 'on';
ui.btnParticles.Enable     = 'on';
ui.btnAlignStack.Enable    = callbacks.onOff(numel(appData.images) >= 2);
ui.btnColorOverlay.Enable  = callbacks.onOff(numel(appData.images) >= 2);
ui.btnExportOverlays.Enable = 'on';
ui.btnBatchExport.Enable   = callbacks.onOff(numel(appData.images) >= 1);
ui.btnCreateGIF.Enable     = callbacks.onOff(numel(appData.images) >= 2);
ui.btnCopyClipboard.Enable = 'on';
ui.cbColorbar.Enable       = 'on';
ui.cbMinimap.Enable        = 'on';
ui.cbPixelInspector.Enable = 'on';
ui.btnLiveThresh.Enable    = 'on';
ui.btnImgMath.Enable       = callbacks.onOff(numel(appData.images) >= 2);
ui.btnWatershed.Enable     = 'on';
ui.btnBatchCrop.Enable     = callbacks.onOff(numel(appData.images) >= 2);
ui.btnMontage.Enable       = callbacks.onOff(numel(appData.images) >= 2);
ui.btnSessionSave.Enable   = 'on';
ui.btnEnterEDS.Enable      = 'on';
ui.btnGrid.Enable          = callbacks.onOff(numel(appData.images) >= 2);
ui.btnExportMeasure.Enable = 'on';
ui.btnDiffRings.Enable     = 'on';
ui.btnROIManager.Enable    = 'on';
ui.btnCalibrateBar.Enable  = 'on';
ui.btnBatchRename.Enable   = callbacks.onOff(numel(appData.images) >= 1);
ui.btnRenameSelected.Enable = 'on';

% Enable Phase 3 measurement controls
ui.btnDSpacing.Enable     = callbacks.onOff(isCalib);
ui.spnProfileWidth.Enable = 'on';
ui.btnInvertImg.Enable    = 'on';

% Enable Phase 3 processing controls
ui.btnSharpen.Enable      = 'on';
ui.btnBinImage.Enable     = 'on';
ui.btnMorphOp.Enable      = 'on';
ui.btnButterworth.Enable  = 'on';
ui.btnRadialProfile.Enable = 'on';
ui.btnAzIntegrate.Enable  = 'on';
ui.btnSurfacePlot.Enable  = 'on';
ui.btnBatchConvert.Enable = callbacks.onOff(numel(appData.images) >= 1);
ui.btnCustomCmap.Enable   = 'on';

% Enable Phase 4 processing controls
ui.btnPlaneLevel.Enable    = 'on';
ui.btnRoughness.Enable     = 'on';
ui.btnInterfaceFit.Enable  = 'on';
ui.btnMultiOtsu.Enable     = 'on';
ui.btnLatticeMeasure.Enable = 'on';
ui.btnGPA.Enable           = 'on';
ui.btnCTF.Enable           = 'on';
ui.btnDefectCount.Enable   = 'on';
ui.btnBackProject.Enable   = 'on';
ui.btnFigureBuilder.Enable = callbacks.onOff(numel(appData.images) >= 1);
ui.btnJournalExport.Enable = 'on';
ui.btnCalibColorbar.Enable = 'on';
ui.btnMacroRecord.Enable   = 'on';
ui.btnFlickerCompare.Enable = callbacks.onOff(numel(appData.images) >= 2);
ui.btn3DSurface.Enable     = 'on';
ui.btnLiveFFT.Enable       = 'on';
ui.btnTemplateMatch.Enable = 'on';
ui.btnStitchImages.Enable  = callbacks.onOff(numel(appData.images) >= 2);
ui.btnNoiseEstimate.Enable = 'on';
ui.btnPubPresets.Enable    = 'on';
ui.btnColormapPreset.Enable = 'on';
ui.btnMeasStats.Enable     = 'on';
ui.btnBatchMeas.Enable     = callbacks.onOff(numel(appData.images) >= 2);
ui.btnExportToDP.Enable    = 'on';

% Enable annotation controls
ui.btnPlaceAnnot.Enable  = 'on';
ui.btnClearAnnot.Enable  = 'on';
ui.btnUndoAnnot.Enable   = 'on';
ui.ddAnnotColor.Enable   = 'on';
ui.btnPlaceArrow.Enable  = 'on';
ui.btnPlaceLine.Enable   = 'on';
ui.btnPlaceRect.Enable   = 'on';
ui.btnPlaceCircle.Enable = 'on';

% Remember which image we just displayed so the next displayImage()
% call can save its state before switching away.
appData.lastDisplayedIdx = appData.activeIdx;
