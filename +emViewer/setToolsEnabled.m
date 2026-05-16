function setToolsEnabled(state, ui, appData)
%SETTOOLSENABLED  Enable or disable all toolbar and panel widgets.
%
%   Syntax
%     emViewer.setToolsEnabled(state, ui, appData)
%
%   Inputs
%     state   - 'on' or 'off'
%     ui      - struct of UI widget handles from FermiViewer
%     appData - read-only; used for transformToolbarBtns and edsMode flag
%
%   Notes
%     Called from FermiViewer.m wrappers for displayImage() and
%     clearDisplay().  All mutations are to widget .Enable / .Value
%     properties, which are handle-object side effects — no return value
%     needed.

% ════════════════════════════════════════════════════════════════════════

% Icon transform toolbar above the image
if isfield(appData, 'transformToolbarBtns')
    for bk = 1:numel(appData.transformToolbarBtns)
        b = appData.transformToolbarBtns(bk);
        if ~isempty(b) && isgraphics(b) && isvalid(b)
            b.Enable = state;
        end
    end
end

ui.btnLineProfile.Enable   = state;
ui.btnBoxProfile.Enable    = state;
ui.btnDistance.Enable      = state;
ui.btnAngle.Enable         = state;
ui.btnExportProfile.Enable = state;
ui.btnClearOverlays.Enable = state;
ui.btnRemoveMeas.Enable    = state;
ui.btnRotCW.Enable         = state;
ui.btnRotCCW.Enable        = state;
ui.btnFlipH.Enable         = state;
ui.btnFlipV.Enable         = state;
ui.btnGaussian.Enable      = state;
ui.btnMedian.Enable        = state;
ui.btnShowFFT.Enable       = state;
ui.btnCLAHE.Enable         = state;
ui.btnUndoFilters.Enable   = state;
ui.btnZoomBox.Enable       = state;
ui.btnZoomDims.Enable      = state;
ui.btnResetZoom.Enable     = state;
ui.btnCropImage.Enable     = state;
ui.btnSaveCrop.Enable      = state;
ui.btnSaveImage.Enable     = state;
ui.btnSetPixelSize.Enable  = state;
ui.btnFFTMask.Enable       = state;
ui.btnParticles.Enable     = state;
ui.btnAlignStack.Enable    = state;
ui.btnColorOverlay.Enable  = state;
ui.btnExportOverlays.Enable = state;
ui.btnBatchExport.Enable   = state;
ui.btnCreateGIF.Enable     = state;
ui.btnCopyClipboard.Enable = state;
ui.cbMinimap.Enable        = state;
ui.cbPixelInspector.Enable = state;
ui.btnLiveThresh.Enable    = state;
ui.btnImgMath.Enable       = state;
ui.btnWatershed.Enable     = state;
ui.btnBatchCrop.Enable     = state;
ui.btnMontage.Enable       = state;
ui.btnSessionSave.Enable   = state;
ui.btnGrid.Enable          = state;
ui.btnExportMeasure.Enable = state;
ui.btnDiffRings.Enable     = state;
ui.btnROIManager.Enable    = state;
ui.btnCalibrateBar.Enable  = state;
ui.btnBatchRename.Enable   = state;
ui.btnRenameSelected.Enable = state;
ui.btnPlaceAnnot.Enable    = state;
ui.btnClearAnnot.Enable    = state;
ui.btnUndoAnnot.Enable     = state;
ui.ddAnnotColor.Enable     = state;
ui.cbColorbar.Enable       = state;

% Phase 3 buttons
ui.btnDSpacing.Enable      = state;
ui.spnProfileWidth.Enable  = state;
ui.ddROIShape.Enable       = state;
ui.btnDrawROI.Enable       = state;
ui.btnInvertImg.Enable     = state;
ui.btnSharpen.Enable       = state;
ui.btnBinImage.Enable      = state;
ui.btnMorphOp.Enable       = state;
ui.btnButterworth.Enable   = state;
ui.btnRadialProfile.Enable = state;
ui.btnAzIntegrate.Enable   = state;
ui.btnSurfacePlot.Enable   = state;
ui.btnBatchConvert.Enable  = state;
ui.btnCustomCmap.Enable    = state;
ui.btnPlaceArrow.Enable    = state;
ui.btnPlaceLine.Enable     = state;
ui.btnPlaceRect.Enable     = state;
ui.btnPlaceCircle.Enable   = state;

% Phase 4 buttons
ui.btnPlaneLevel.Enable    = state;
ui.btnRoughness.Enable     = state;
ui.btnInterfaceFit.Enable  = state;
ui.btnMultiOtsu.Enable     = state;
ui.btnLatticeMeasure.Enable = state;
ui.btnGPA.Enable           = state;
ui.btnCTF.Enable           = state;
ui.btnDefectCount.Enable   = state;
ui.btnBackProject.Enable   = state;
ui.btnFigureBuilder.Enable = state;
ui.btnJournalExport.Enable = state;
ui.btnCalibColorbar.Enable = state;
ui.btnMacroRecord.Enable   = state;
ui.btnFlickerCompare.Enable = state;

% New feature buttons
ui.btn3DSurface.Enable     = state;
ui.btnLiveFFT.Enable       = state;
ui.btnTemplateMatch.Enable = state;
ui.btnStitchImages.Enable  = state;
ui.btnNoiseEstimate.Enable = state;
ui.btnPubPresets.Enable    = state;
ui.btnColormapPreset.Enable = state;
ui.btnMeasStats.Enable     = state;
ui.btnBatchMeas.Enable     = state;
ui.btnExportToDP.Enable    = state;
ui.spnMeasLabelFont.Enable = state;
ui.ddMeasSymbol.Enable     = state;
ui.ddMeasColor.Enable      = state;

% EDS channel controls (only when not in EDS mode)
if ~appData.edsMode
    ui.btnAddChannel.Enable       = state;
    ui.btnRemoveChannel.Enable    = state;
    ui.ddChannelColor.Enable      = state;
    ui.cbChannelVisible.Enable    = state;
    ui.sldChannelIntensity.Enable = state;
    ui.efChannelLabel.Enable      = state;
    ui.btnExportComposite.Enable  = state;
end

% EDS quantification controls
ui.btnAssignElements.Enable     = state;
ui.btnQuantifyCL.Enable         = state;
ui.btnCompositionProfile.Enable = state;
ui.btnROIComposition.Enable     = state;

% EELS controls
ui.btnEnterEELS.Enable     = state;
ui.btnEELSFitBG.Enable     = state;
ui.ddEELSMethod.Enable     = state;
ui.chkShowEdges.Enable     = state;
ui.ddEdgeFilter.Enable     = state;
ui.btnEELSExtractMap.Enable = state;
ui.btnEELSThickness.Enable = state;
ui.btnEELSAlignZLP.Enable  = state;
ui.btnEELSDeconvolve.Enable = state;
ui.btnEELSELNES.Enable     = state;
ui.btnEELSKK.Enable        = state;
ui.btnEELSNavigate.Enable  = state;
ui.btnEELSSVD.Enable       = state;

% Diffraction controls
ui.btnAutoDetectSpots.Enable  = state;
ui.btnClickDiffSpot.Enable    = state;
ui.btnClearDiffSpots.Enable   = state;
ui.ddAccVoltage.Enable        = state;
ui.btnMatchDiffraction.Enable = state;
ui.btnOverlayDiffRings.Enable = state;
ui.btnSimDiffraction.Enable   = state;
ui.btnVDF.Enable              = state;

% ZAF quantification
ui.btnQuantifyZAF.Enable = state;
