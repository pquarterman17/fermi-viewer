function promptCalibrateBar(fig, appData, onDraw, onAutoDetect)
%PROMPTCALIBRATEBAR  Offer draw-bar vs auto-detect choice for scale bar calibration.
%
%   Returns nothing; calls onDraw() or onAutoDetect() depending on choice.

    if appData.activeIdx < 1 || isempty(appData.displayImg)
        return;
    end

    sel = fermiViewer.chrome.quietConfirm(fig, ...
        ['Choose calibration method:' newline newline ...
         'DRAW — Click both ends of the scale bar, then enter the distance.' newline ...
         'AUTO-DETECT — Scan the image for a scale bar and suggest calibration.'], ...
        'Calibrate from Scale Bar', ...
        'Options', {'Draw on Bar', 'Auto-Detect', 'Cancel'}, ...
        'DefaultOption', 1, 'CancelOption', 3, ...
        'Icon', 'question');

    switch sel
        case 'Draw on Bar'
            onDraw();
        case 'Auto-Detect'
            onAutoDetect();
    end
end
