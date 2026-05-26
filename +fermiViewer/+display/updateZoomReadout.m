function updateZoomReadout(ax, lblZoom)
%UPDATEZOOMREADOUT  Refresh the status-bar zoom label from the axes view.
%
%   fermiViewer.display.updateZoomReadout(ax, lblZoom)
%
%   Wired as an XLim 'PostSet' listener on the main axes so it fires on
%   every view change (zoom, pan, fit, reset) without hooking each
%   callback. Zoom is image-fraction based — 100% means the full image
%   width fills the view; 200% means half the width is visible (2x). This
%   definition is resize-independent (depends only on XLim vs image width),
%   so an XLim listener is sufficient and never goes stale on window resize.
%
%   Inputs
%     ax       main image uiaxes
%     lblZoom  the status-bar zoom uilabel (s.lblStatusZoom)

    if isempty(lblZoom) || ~isgraphics(lblZoom) || ~isvalid(lblZoom)
        return;
    end
    if isempty(ax) || ~isgraphics(ax) || ~isvalid(ax)
        return;
    end

    imObj = findobj(ax, 'Type', 'image');
    if isempty(imObj)
        lblZoom.Text = '';
        return;
    end

    W = size(imObj(1).CData, 2);
    span = diff(ax.XLim);
    if ~isfinite(span) || span <= 0 || W <= 0
        lblZoom.Text = '';
        return;
    end

    lblZoom.Text = sprintf('%d%%', round(W / span * 100));
end
