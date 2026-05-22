function [newXLim, newYLim] = computePanLimits(panStartXY, curXY, startLims, imgH, imgW)
%COMPUTEPANLIMITS  Compute clamped axes limits for a pan drag.
%   Pure function: no GUI state, no handles — just coordinate math.
    dx = panStartXY(1) - curXY(1);
    dy = panStartXY(2) - curXY(2);
    newXLim = startLims.XLim + dx;
    newYLim = startLims.YLim + dy;
    viewW = diff(startLims.XLim);
    viewH = diff(startLims.YLim);
    if newXLim(1) < 0.5,       newXLim = [0.5, 0.5 + viewW]; end
    if newXLim(2) > imgW + 0.5, newXLim = [imgW + 0.5 - viewW, imgW + 0.5]; end
    if newYLim(1) < 0.5,       newYLim = [0.5, 0.5 + viewH]; end
    if newYLim(2) > imgH + 0.5, newYLim = [imgH + 0.5 - viewH, imgH + 0.5]; end
end
