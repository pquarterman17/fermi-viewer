function autoDetectAndCalibrate(fig, ax, appData, applyCalibration, setStatus)
%AUTODETECTANDCALIBRATE  Run scale-bar detection, draw preview, prompt for length.
%
%   fermiViewer.calibration.autoDetectAndCalibrate(fig, ax, appData, applyCalibration, setStatus)
%
%   Calls fermiViewer.calibration.detectScaleBar on the current
%   filteredPixels. If a bar is found, overlays a temporary annotation
%   on the axes, prompts the user for the real-world distance via
%   fermiViewer.calibration.promptScaleBarDistance, then calls
%   applyCalibration with the resulting size/unit and writes status.

    fig.Pointer = 'watch'; drawnow;
    try
        det = fermiViewer.calibration.detectScaleBar(appData.filteredPixels);
        fig.Pointer = 'arrow';
        if ~det.found
            fermiViewer.chrome.quietAlert(fig, det.msg, 'Auto-Detect Failed', 'Icon', 'warning');
            return;
        end
        barColor = [0 1 1];
        hBarLine  = line(ax, [det.barX1 det.barX2], [det.barY det.barY], ...
            'Color', barColor, 'LineWidth', 3, 'HandleVisibility', 'off');
        hBarEnd1  = line(ax, [det.barX1 det.barX1], [det.barY-8 det.barY+8], ...
            'Color', barColor, 'LineWidth', 2, 'HandleVisibility', 'off');
        hBarEnd2  = line(ax, [det.barX2 det.barX2], [det.barY-8 det.barY+8], ...
            'Color', barColor, 'LineWidth', 2, 'HandleVisibility', 'off');
        hBarLabel = text(ax, (det.barX1+det.barX2)/2, det.barY-12, det.msg, ...
            'Color', barColor, 'FontSize', 11, 'FontWeight', 'bold', ...
            'HorizontalAlignment', 'center', 'BackgroundColor', [0.1 0.1 0.1], ...
            'HandleVisibility', 'off');
        drawnow;
        [realDist, realUnit, cancelled] = fermiViewer.calibration.promptScaleBarDistance(det.barLen);
        if isvalid(hBarLine),  delete(hBarLine);  end
        if isvalid(hBarEnd1),  delete(hBarEnd1);  end
        if isvalid(hBarEnd2),  delete(hBarEnd2);  end
        if isvalid(hBarLabel), delete(hBarLabel); end
        if cancelled, return; end
        newPixelSize = realDist / det.barLen;
        applyCalibration(newPixelSize, realUnit);
        setStatus(sprintf('Calibrated: %.4g %s/px (auto-detected %.0f px = %g %s)', ...
            newPixelSize, realUnit, det.barLen, realDist, realUnit));
    catch ME
        fig.Pointer = 'arrow';
        fermiViewer.chrome.quietAlert(fig, sprintf('Auto-detect failed:\n%s', ME.message), 'Error', 'Icon', 'error');
    end
end
