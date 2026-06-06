function appData = runCircleROI(appData, ax, overlayColor, setStatus, cx, cy, ex, ey)
%RUNCIRCLEROI  Compute circle-ROI statistics, draw the circle, log it.
%   Accept-and-return: appends to appData.measurementLog on the local
%   copy. setStatus is UI-pure (status bar text), safe to call here.

    if isempty(appData.filteredPixels), return; end
    r = sqrt((ex - cx)^2 + (ey - cy)^2);
    if r < 1, setStatus('Circle ROI too small.'); return; end

    s = fermiViewer.measurement.computeCircleROI(appData.filteredPixels, cx, cy, r);
    if s.empty, setStatus('No pixels in circle ROI.'); return; end

    hold(ax, 'on');
    th = linspace(0, 2*pi, 120);
    plot(ax, cx + r*cos(th), cy + r*sin(th), '-', ...
        'Color', overlayColor, 'LineWidth', 1.5, ...
        'HandleVisibility', 'off', 'HitTest', 'off');
    hold(ax, 'off');

    appData.measurementLog{end+1} = struct('type', 'circleROI', ...
        'cx', cx, 'cy', cy, 'radius', r, ...
        'mean', s.mean, 'std', s.std, 'min', s.min, 'max', s.max, 'area', s.area);
    setStatus(s.statusMsg);
end
