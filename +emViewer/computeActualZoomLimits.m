function [newXLim, newYLim] = computeActualZoomLimits(cx, cy, axW_px, axH_px, imgH, imgW)
%COMPUTEACTUALZOOMLIMITS  Compute 1:1 pixel-ratio axes limits, centred and clamped.
    halfW = axW_px / 2;
    halfH = axH_px / 2;
    newXLim = [cx - halfW, cx + halfW];
    newYLim = [cy - halfH, cy + halfH];
    if newXLim(1) < 0.5,        newXLim = [0.5, 0.5 + axW_px]; end
    if newXLim(2) > imgW + 0.5,  newXLim = [imgW + 0.5 - axW_px, imgW + 0.5]; end
    if newYLim(1) < 0.5,        newYLim = [0.5, 0.5 + axH_px]; end
    if newYLim(2) > imgH + 0.5,  newYLim = [imgH + 0.5 - axH_px, imgH + 0.5]; end
end
