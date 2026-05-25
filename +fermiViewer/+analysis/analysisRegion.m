function [pixels, info] = analysisRegion(appData)
%ANALYSISREGION  Pixels that analysis ops (FFT, diffraction, CTF, ...) act on.
%
%   [pixels, info] = fermiViewer.analysis.analysisRegion(appData)
%
%   Returns the active "Analysis ROI" sub-image when appData.analysisROI is
%   set, otherwise the full appData.filteredPixels. This is the single hook
%   every region-scoped analysis calls instead of reading filteredPixels
%   directly, so a user-drawn rectangle/circle ROI transparently restricts
%   FFT / diffraction / CTF / GPA / defect-count to that region.
%
%   appData.analysisROI is [] (full image) or a struct:
%     .type = 'rect'   with .x1 .x2 .y1 .y2   (inclusive pixel bounds)
%     .type = 'circle' with .cx .cy .r        (center + radius, pixels)
%
%   For a circle, the bounding box is cropped and pixels OUTSIDE the radius
%   are set to the in-circle mean — a soft aperture that avoids the hard
%   zero-edge ringing that would corrupt an FFT/diffractogram.
%
%   info: struct with .roi (logical), .type, and .label (human-readable,
%   e.g. 'rect 64x64 px' or 'full image') for status/titles.

    full = double(appData.filteredPixels);
    pixels = full;
    info = struct('roi', false, 'type', 'full', 'label', 'full image');

    if ~isfield(appData, 'analysisROI') || isempty(appData.analysisROI)
        return;
    end
    roi = appData.analysisROI;
    [H, W] = size(full);

    switch roi.type
        case 'rect'
            x1 = max(1, min(W, round(min(roi.x1, roi.x2))));
            x2 = max(1, min(W, round(max(roi.x1, roi.x2))));
            y1 = max(1, min(H, round(min(roi.y1, roi.y2))));
            y2 = max(1, min(H, round(max(roi.y1, roi.y2))));
            if x2 - x1 < 1 || y2 - y1 < 1, return; end   % degenerate -> full
            pixels = full(y1:y2, x1:x2);
            info = struct('roi', true, 'type', 'rect', ...
                'label', sprintf('rect %dx%d px', x2-x1+1, y2-y1+1));

        case 'circle'
            r  = round(roi.r);
            cx = round(roi.cx); cy = round(roi.cy);
            if r < 1, return; end
            x1 = max(1, cx - r); x2 = min(W, cx + r);
            y1 = max(1, cy - r); y2 = min(H, cy + r);
            if x2 - x1 < 1 || y2 - y1 < 1, return; end
            sub = full(y1:y2, x1:x2);
            [XX, YY] = meshgrid(x1:x2, y1:y2);
            inside = (XX - cx).^2 + (YY - cy).^2 <= r^2;
            if ~any(inside(:)), return; end
            % Soft aperture: outside-circle -> in-circle mean (no zero edge).
            sub(~inside) = mean(sub(inside));
            pixels = sub;
            info = struct('roi', true, 'type', 'circle', ...
                'label', sprintf('circle r=%d px', r));
    end
end
