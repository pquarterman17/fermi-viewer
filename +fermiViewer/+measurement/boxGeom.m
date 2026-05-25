function varargout = boxGeom(action, x1, y1, x2, y2, width)
%BOXGEOM  Geometry helpers for the rotated box-profile rectangle.
%
%   corners      = fermiViewer.measurement.boxGeom('corners', x1,y1,x2,y2,width)
%   [w1, w2]     = fermiViewer.measurement.boxGeom('widthHandles', x1,y1,x2,y2,width)
%   [ux, uy]     = fermiViewer.measurement.boxGeom('perpUnit', x1,y1,x2,y2)
%
%   'corners'      → 4x2 [x y] matrix of the rectangle corners (CCW).
%   'widthHandles' → midpoints of the two long edges (each 1x2 [x y]).
%   'perpUnit'     → unit vector perpendicular to the (x1,y1)->(x2,y2) line.
%
%   The perpendicular offset uses width/2; identical math to the original
%   doExecuteBoxProfile so geometry stays consistent across draw and drag.

    switch lower(action)
        case 'perpunit'
            [ux, uy] = perpUnit(x1, y1, x2, y2);
            varargout = {ux, uy};
        case 'corners'
            [ux, uy] = perpUnit(x1, y1, x2, y2);
            h = width / 2;
            varargout{1} = [
                x1 + h*ux, y1 + h*uy;
                x2 + h*ux, y2 + h*uy;
                x2 - h*ux, y2 - h*uy;
                x1 - h*ux, y1 - h*uy
            ];
        case 'widthhandles'
            [ux, uy] = perpUnit(x1, y1, x2, y2);
            h  = width / 2;
            mx = (x1 + x2) / 2; my = (y1 + y2) / 2;
            varargout{1} = [mx + h*ux, my + h*uy];
            varargout{2} = [mx - h*ux, my - h*uy];
        otherwise
            error('fermiViewer:measurement:boxGeom:unknownAction', ...
                'Unknown action "%s".', action);
    end
end

function [ux, uy] = perpUnit(x1, y1, x2, y2)
    dx = x2 - x1; dy = y2 - y1;
    L = hypot(dx, dy);
    if L < eps
        ux = 0; uy = 0;
    else
        ux = -dy / L; uy = dx / L;
    end
end
