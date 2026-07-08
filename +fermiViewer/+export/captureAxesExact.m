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
        cleaner = onCleanup(@() deleteIfFile(tmpPng));
        exportgraphics(ax, tmpPng, 'ContentType', 'image', ...
            'Resolution', 96, 'BackgroundColor', 'current');
        out = imread(tmpPng);

        % Constrained environments (e.g. headless R2022b under Xvfb) clamp
        % the offscreen window, so the 96-DPI export can come back SMALLER
        % than the target. Re-export with a compensating resolution — the
        % renderer samples CData at the output resolution, so the result
        % stays ~1:1 with the data rather than an upscale of the clamped
        % render.
        if size(out, 1) < outH || size(out, 2) < outW
            scale = max(outW / max(size(out, 2), 1), ...
                        outH / max(size(out, 1), 1));
            dpi2 = min(2000, ceil(96 * scale) + 2);
            exportgraphics(ax, tmpPng, 'ContentType', 'image', ...
                'Resolution', dpi2, 'BackgroundColor', 'current');
            out = imread(tmpPng);
        end

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


function deleteIfFile(p)
    if isfile(p)
        try, delete(p); catch, end
    end
end
