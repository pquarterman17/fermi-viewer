function pu = activePixelUnit(appData)
%ACTIVEPIXELUNIT  Pixel unit string of the active image ('px' fallback).
    pu = 'px';
    if isempty(appData.images) || appData.activeIdx < 1, return; end
    try
        imgInfo = appData.images{appData.activeIdx}.metadata.parserSpecific.imageData;
        if imgInfo.calibrated && ~isnan(imgInfo.pixelSize)
            pu = imgInfo.pixelUnit;
        end
    catch
    end
end
