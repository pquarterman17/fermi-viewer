function promptSetPixelSize(fig, appData, applyCalibration, setStatus)
%PROMPTSETPIXELSIZE  Manual pixel-size entry dialog.
%
%   fermiViewer.calibration.promptSetPixelSize(fig, appData, applyCalibration, setStatus)
%
%   Reads the current image's pixelSize/pixelUnit as defaults, prompts
%   for new values, validates, and applies. The applyCalibration callback
%   is what actually updates the image metadata + UI; this function only
%   handles the dialog flow.

    if appData.activeIdx < 1
        return;
    end

    imgInfo = appData.images{appData.activeIdx}.metadata.parserSpecific.imageData;
    if imgInfo.calibrated && ~isnan(imgInfo.pixelSize)
        defSize = num2str(imgInfo.pixelSize);
        defUnit = imgInfo.pixelUnit;
    else
        defSize = '1.0';
        defUnit = 'nm';
    end

    answer = inputdlg( ...
        {'Pixel size:', 'Unit (nm, µm, Å, mm, etc.):'}, ...
        'Set Pixel Calibration', [1 36], {defSize, defUnit});
    if isempty(answer)
        return;
    end

    newSize = str2double(answer{1});
    newUnit = strtrim(answer{2});
    if isnan(newSize) || newSize <= 0
        fermiViewer.chrome.quietAlert(fig, 'Pixel size must be a positive number.', ...
            'Invalid Input', 'Icon', 'error');
        return;
    end
    if isempty(newUnit)
        newUnit = 'px';
    end

    applyCalibration(newSize, newUnit);
    setStatus(sprintf('Pixel size set to %.4g %s/px', newSize, newUnit));
end
