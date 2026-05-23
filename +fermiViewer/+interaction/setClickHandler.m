function setClickHandler(imgHandle, ax, fcn)
%SETCLICKHANDLER  Point the image + axes ButtonDownFcn at fcn.
%
%   fermiViewer.interaction.setClickHandler(imgHandle, ax, fcn)
%
%   In a MATLAB uifigure, a left-click on the displayed image fires the
%   IMAGE object's ButtonDownFcn, NOT the figure's WindowButtonDownFcn.
%   The two-click capture system (Distance/Profile/Angle/ROI/annotations)
%   and the rect-capture system (box zoom / crop) install their handlers
%   on fig.WindowButtonDownFcn, which therefore never fires for image
%   clicks — capture is silently dead.
%
%   This helper points BOTH the image object and its parent axes (for
%   clicks on padding outside the image) at the supplied handler:
%     - capture-start passes the capture click handler
%     - finishCapture passes the idle axesDown handler (box-zoom/pan/
%       double-click-reset)
%
%   No return value: it only sets handle ButtonDownFcn properties.
%   Both targets are guarded for validity so it is safe to call before an
%   image exists.

    if ~isempty(imgHandle) && isvalid(imgHandle)
        imgHandle.ButtonDownFcn = fcn;
    end
    if ~isempty(ax) && isvalid(ax)
        ax.ButtonDownFcn = fcn;
    end
end
