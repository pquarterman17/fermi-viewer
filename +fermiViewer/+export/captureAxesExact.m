function rgb = captureAxesExact(tmpFig, ax, outW, outH)
%CAPTUREAXESEXACT  Capture an offscreen uifigure axes at exactly outW x outH.
%
%   rgb = fermiViewer.export.captureAxesExact(tmpFig, ax, outW, outH)
%
%   tmpFig must be an offscreen uifigure sized [outW outH] whose axes'
%   inner plot box fills it exactly — one canvas pixel per data pixel.
%   getframe of such a figure is pixel-exact (verified R2023b/R2025b,
%   Windows); if a platform DPI-scales the capture, fall back to
%   exportgraphics at 96 DPI (1 MATLAB px per output px) and center-crop
%   the fixed few-px padding it always adds.
%
%   Returns [] if both paths fail. Callers must then keep their
%   unrendered source rather than resampling a wrong-size capture —
%   resampling is the bug class this helper exists to prevent.

    rgb = [];
    try
        fr = getframe(tmpFig);
        if size(fr.cdata, 1) == outH && size(fr.cdata, 2) == outW
            rgb = fr.cdata;
            return;
        end
    catch
    end

    try
        tmpPng = [tempname '.png'];
        exportgraphics(ax, tmpPng, 'ContentType', 'image', ...
            'Resolution', 96, 'BackgroundColor', 'current');
        out = imread(tmpPng);
        delete(tmpPng);
        padH = size(out, 1) - outH;
        padW = size(out, 2) - outW;
        if padH >= 0 && padW >= 0
            r0 = floor(padH / 2);
            c0 = floor(padW / 2);
            rgb = out(r0+1:r0+outH, c0+1:c0+outW, :);
        end
    catch
    end
end
