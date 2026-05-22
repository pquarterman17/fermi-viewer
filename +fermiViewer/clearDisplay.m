function appData = clearDisplay(appData, ui, callbacks)
%CLEARDISPLAY  Clear axes and reset all UI state when no image is loaded.
%
%   Syntax
%     appData = emViewer.clearDisplay(appData, ui, callbacks)
%
%   Inputs
%     appData   - FermiViewer app state struct (modified; returned)
%     ui        - struct of all UI widget handles
%     callbacks - struct of function handles:
%                   .showStackControls(nFrames)
%
%   Outputs
%     appData   - updated app state (pixel arrays cleared, stack reset)
%
%   Notes
%     Extracted from FermiViewer.m to reduce monolith line count.
%     Mirrors clearDisplay() nested function exactly.

% ════════════════════════════════════════════════════════════════════════

appData.rawPixels      = [];
appData.filteredPixels = [];
appData.preCropPixels  = [];
appData.displayImg     = [];
appData.imgHandle      = [];
appData.edsComposite   = [];

if ~isempty(ui.ax) && isvalid(ui.ax)
    delete(ui.ax.Children);
    cla(ui.ax);
end
if ~isempty(ui.ax) && isvalid(ui.ax)
    ui.ax.XTick = [];
    ui.ax.YTick = [];
    title(ui.ax, 'Open an image file to begin', 'Interpreter', 'none');
    colormap(ui.ax, gray(256));
    ui.ax.Toolbar.Visible = 'off';
end

ui.lblFilename.Text      = '(no image loaded)';
ui.lblStatusDims.Text    = '-- x -- px';
ui.lblStatusBits.Text    = '--bit';
ui.lblStatusPixSize.Text = 'uncalibrated';
ui.lblStatusMouse.Text   = '';
ui.taMetadata.Value      = {'(no image loaded)'};

% Disable measurement controls
ui.btnLineProfile.Enable   = 'off';
ui.btnBoxProfile.Enable    = 'off';
ui.btnDistance.Enable      = 'off';
ui.btnExportProfile.Enable = 'off';
ui.btnAngle.Enable         = 'off';
ui.btnClearOverlays.Enable = 'off';
ui.btnRemoveMeas.Enable    = 'off';
ui.cbScaleBar.Enable       = 'off';
ui.ddScaleBarColor.Enable  = 'off';
ui.spnScaleBarFont.Enable  = 'off';
ui.efScaleBarLen.Enable    = 'off';
ui.ddScaleBarUnit.Enable   = 'off';

% Disable processing controls
if isfield(appData, 'transformToolbarBtns')
    for toolbarK = 1:numel(appData.transformToolbarBtns)
        toolbarBtn = appData.transformToolbarBtns(toolbarK);
        if ~isempty(toolbarBtn) && isgraphics(toolbarBtn) && isvalid(toolbarBtn)
            toolbarBtn.Enable = 'off';
        end
    end
end
ui.btnRotCW.Enable       = 'off';
ui.btnRotCCW.Enable      = 'off';
ui.btnFlipH.Enable       = 'off';
ui.btnFlipV.Enable       = 'off';
ui.btnGaussian.Enable    = 'off';
ui.btnMedian.Enable      = 'off';
ui.btnShowFFT.Enable     = 'off';
ui.btnCLAHE.Enable       = 'off';
ui.btnUndoFilters.Enable = 'off';
ui.ddROIShape.Enable     = 'off';
ui.btnDrawROI.Enable     = 'off';
ui.btnZoomBox.Enable     = 'off';
ui.btnZoomDims.Enable    = 'off';
ui.btnResetZoom.Enable   = 'off';
ui.btnCropImage.Enable   = 'off';
ui.btnSaveCrop.Enable    = 'off';
ui.btnSaveImage.Enable   = 'off';
ui.btnSetPixelSize.Enable   = 'off';
ui.btnFFTMask.Enable        = 'off';
ui.btnParticles.Enable      = 'off';
ui.btnAlignStack.Enable     = 'off';
ui.btnColorOverlay.Enable   = 'off';
ui.btnExportOverlays.Enable = 'off';
ui.btnBatchExport.Enable    = 'off';
ui.btnCreateGIF.Enable      = 'off';
ui.btnCopyClipboard.Enable  = 'off';
ui.cbColorbar.Enable        = 'off';
ui.cbColorbar.Value         = false;
ui.cbMinimap.Enable         = 'off';
ui.cbMinimap.Value          = false;
ui.cbPixelInspector.Enable  = 'off';
ui.cbPixelInspector.Value   = false;
ui.btnLiveThresh.Enable     = 'off';
ui.btnImgMath.Enable        = 'off';
ui.btnWatershed.Enable      = 'off';
ui.btnBatchCrop.Enable      = 'off';
ui.btnMontage.Enable        = 'off';
ui.btnSessionSave.Enable    = 'off';
ui.btnEnterEDS.Enable       = 'off';
ui.btnEDSToolbar.Enable     = 'off';
ui.btnAddChannel.Enable     = 'off';
ui.btnRemoveChannel.Enable  = 'off';
ui.btnExportComposite.Enable = 'off';
ui.btnGrid.Enable           = 'off';
ui.btnExportMeasure.Enable  = 'off';
ui.btnDiffRings.Enable      = 'off';
ui.btnROIManager.Enable     = 'off';
ui.btnCalibrateBar.Enable   = 'off';
ui.btnBatchRename.Enable    = 'off';
ui.btnRenameSelected.Enable = 'off';

% Clean up floating panels
if ~isempty(ui.hColorbar) && isvalid(ui.hColorbar)
    delete(ui.hColorbar);
    ui.hColorbar = [];
end
if ~isempty(ui.hMinimap) && isvalid(ui.hMinimap)
    delete(ui.hMinimap);
    ui.hMinimap = [];
end
if ~isempty(ui.hPixelInspector) && isvalid(ui.hPixelInspector)
    delete(ui.hPixelInspector);
    ui.hPixelInspector = [];
end

% Disable Phase 4 buttons
ui.btnPlaneLevel.Enable    = 'off';
ui.btnRoughness.Enable     = 'off';
ui.btnInterfaceFit.Enable  = 'off';
ui.btnMultiOtsu.Enable     = 'off';
ui.btnLatticeMeasure.Enable = 'off';
ui.btnGPA.Enable           = 'off';
ui.btnCTF.Enable           = 'off';
ui.btnDefectCount.Enable   = 'off';
ui.btnBackProject.Enable   = 'off';
ui.btnFigureBuilder.Enable = 'off';
ui.btnJournalExport.Enable = 'off';
ui.btnCalibColorbar.Enable = 'off';
ui.btnMacroRecord.Enable   = 'off';
ui.btnFlickerCompare.Enable = 'off';

% Disable annotation controls
ui.btnPlaceAnnot.Enable = 'off';
ui.btnClearAnnot.Enable = 'off';
ui.btnUndoAnnot.Enable  = 'off';
ui.ddAnnotColor.Enable  = 'off';

% Hide stack navigator and reset stack state
appData.stackFrames = {};
appData.stackIdx    = 0;
appData.undoStack   = {};
callbacks.showStackControls(0);

% Clear histogram
cla(ui.histAx);
ui.histAx.XLim = [0 1];
ui.histAx.YLim = [0 1];
