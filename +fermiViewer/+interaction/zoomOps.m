function [xl, yl] = zoomOps(action, appData, ax)
%ZOOMOPS  Compute axes limits for the toolbar zoom controls.
%
%   [xl, yl] = fermiViewer.interaction.zoomOps(action, appData, ax)
%
%   action - 'fit' | 'reset' (fit axes to the whole raster)
%          | 'actual'        (1:1 native-pixel zoom, centred on view)
%          | 'out'           (zoom out 2x, centred on view)
%
%   Returns the new [xMin xMax], [yMin yMax] limits, or [] for both when
%   there is nothing to display (the caller then leaves the axes alone).
%
%   EDS-mode dimension source
%   -------------------------
%   In EDS mode the object on screen is the false-colour composite, whose
%   pixel grid is the EDS *cube* size (e.g. 256x256) — typically much
%   smaller than the survey image held in appData.rawPixels /
%   appData.filteredPixels (e.g. 1024x1024 or larger). The zoom controls
%   used to read the survey dimensions unconditionally, which blew the axes
%   up to the survey extent and shrank the composite into a corner ("tiny
%   image in a huge black box"), and broke zoom because every fit re-applied
%   the wrong extent. Here EDS mode sources the dimensions from
%   appData.edsComposite so fit/zoom track the composite that is actually
%   drawn.

    xl = [];
    yl = [];

    isEDS = isfield(appData, 'edsMode') && appData.edsMode;

    if isEDS
        if ~isfield(appData, 'edsComposite') || isempty(appData.edsComposite)
            return;
        end
        [H, W, ~] = size(appData.edsComposite);
    else
        if strcmp(action, 'reset')
            if isempty(appData.displayImg), return; end
            base = appData.filteredPixels;
        else
            if appData.activeIdx < 1 || isempty(appData.rawPixels), return; end
            base = appData.rawPixels;
        end
        [H, W] = size(base);
    end

    switch action
        case {'fit', 'reset'}
            xl = [0.5, W + 0.5];
            yl = [0.5, H + 0.5];

        case 'actual'
            axPos = getpixelposition(ax, true);
            [xl, yl] = fermiViewer.interaction.computeActualZoomLimits( ...
                mean(ax.XLim), mean(ax.YLim), axPos(3), axPos(4), H, W);

        case 'out'
            cx = mean(ax.XLim); cy = mean(ax.YLim);
            hw = diff(ax.XLim);  hh = diff(ax.YLim);
            xl = [max(cx - hw, 0.5), min(cx + hw, W + 0.5)];
            yl = [max(cy - hh, 0.5), min(cy + hh, H + 0.5)];
            if diff(xl) >= W && diff(yl) >= H
                xl = [0.5, W + 0.5];
                yl = [0.5, H + 0.5];
            end
    end
end
