function appData = rotateFlip(mode, appData, ui, cb)
%ROTATEFLIP  Rotate or flip the active image and rebuild the display.
%
%   Syntax
%   ------
%   appData = emViewer.rotateFlip(mode, appData, ui, cb)
%
%   Inputs
%   ------
%   mode    - string: 'cw90' | 'ccw90' | 'flipH' | 'flipV' | '180'
%   appData - FermiViewer appData struct
%   ui      - struct: ax, sldLow, sldHigh, ddColormap, cbColorbar, hColorbar,
%             cbScaleBar
%   cb      - struct: undoPush, applyContrastPipeline, prepareDisplayBuffer,
%             attachImageContextMenu, clearAllOverlays, rebuildScaleBar, setStatus
%
%   Outputs
%   -------
%   appData - updated appData (rawPixels, filteredPixels, displayPixels,
%             displayImg, imgHandle updated)

    if isempty(appData.rawPixels), return; end

    cb.undoPush();
    r = emViewer.processing.executeRotateFlip( ...
        appData.rawPixels, appData.filteredPixels, mode);
    if ~r.applied, return; end

    appData.rawPixels      = r.rawPixels;
    appData.filteredPixels = r.filteredPixels;

    [H, W] = size(appData.filteredPixels);
    lo = ui.sldLow.Value;
    hi = ui.sldHigh.Value;
    appData.displayPixels = [];
    cb.prepareDisplayBuffer();
    dispImg = cb.applyContrastPipeline(appData.displayPixels, lo, hi);
    appData.displayImg = dispImg;

    delete(ui.ax.Children);
    cla(ui.ax);
    dr = appData.displayRegion;
    if isempty(dr), dr = [1, 1, W, H]; end
    hImg = imagesc(ui.ax, 'XData', [dr(1) dr(3)], 'YData', [dr(2) dr(4)], 'CData', dispImg);
    try, hImg.Interpolation = 'nearest'; catch; end
    appData.imgHandle = hImg;
    cb.attachImageContextMenu();
    cmapName = ui.ddColormap.Value;
    colormap(ui.ax, feval(cmapName, 256));
    ui.ax.CLim = [0 1];
    ui.ax.YDir = 'reverse';
    axis(ui.ax, 'equal');
    ui.ax.XLim = [0.5, W + 0.5];
    ui.ax.YLim = [0.5, H + 0.5];
    ui.ax.XTick = [];
    ui.ax.YTick = [];
    ui.ax.Toolbar.Visible = 'off';

    % Colorbar: deletion and recreation handled by caller (hColorbar is a
    % closure variable — FermiViewer's onRotateFlip wrapper deals with it).

    cb.clearAllOverlays();
    if ~isempty(ui.cbScaleBar) && isvalid(ui.cbScaleBar) && ...
            strcmp(ui.cbScaleBar.Enable, 'on') && ui.cbScaleBar.Value
        appData = cb.rebuildScaleBar(appData);
    end
    cb.setStatus(r.msg);
end
