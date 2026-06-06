function annotateDSpacing(ax, appData, overlayColor, setStatus, x1, y1, x2, y2)
%ANNOTATEDSPACING  Compute d-spacing from two FFT spots and annotate them.
%   Reads appData (never mutates it) and draws spot circles + d-value
%   labels on ax. Safe to call from a closure wrapper without
%   accept-and-return: the only side effects are graphics + status.
%
%   See also fermiViewer.diffraction.computeDSpacing

    if appData.activeIdx < 1, return; end
    imgInfo = appData.images{appData.activeIdx}.metadata.parserSpecific.imageData;
    if ~imgInfo.calibrated || isnan(imgInfo.pixelSize)
        setStatus('d-spacing requires pixel size calibration.');
        return;
    end
    [H, W] = size(appData.filteredPixels);
    r = fermiViewer.diffraction.computeDSpacing( ...
        [H W], imgInfo.pixelSize, imgInfo.pixelUnit, x1, y1, x2, y2);
    hold(ax, 'on');
    th = linspace(0, 2*pi, 60);
    for si = 1:numel(r.spots)
        sp = r.spots(si);
        plot(ax, sp.x + sp.radius*cos(th), sp.y + sp.radius*sin(th), '-', ...
            'Color', overlayColor, 'LineWidth', 1.5, ...
            'HandleVisibility', 'off', 'HitTest', 'off');
        text(ax, sp.x + sp.radius + 3, sp.y, ...
            sprintf('d=%.3f %s', sp.dSpacing, imgInfo.pixelUnit), ...
            'Color', overlayColor, 'FontSize', 9, ...
            'HandleVisibility', 'off', 'HitTest', 'off');
    end
    hold(ax, 'off');
    setStatus(r.statusMsg);
end
