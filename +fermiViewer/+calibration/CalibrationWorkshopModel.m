classdef CalibrationWorkshopModel < handle
%CALIBRATIONWORKSHOPMODEL  State container for FermiViewer calibration/scale-bar.
%
%   Mirrors the active image's calibration state plus scale-bar display
%   preferences. No graphics handles.

    properties (SetAccess = public)
        calibrated      (1,1) logical  = false
        pixelSize       (1,1) double   = NaN
        pixelUnit       (1,:) char     = 'px'

        scaleBarVisible (1,1) logical  = false
        scaleBarColor   (1,3) double   = [1 1 1]
        scaleBarFontSize (1,1) double  = 10
        scaleBarLength  (1,1) double   = 0
        scaleBarUnit    (1,:) char     = 'nm'
    end

    methods
        function reset(obj)
            obj.calibrated       = false;
            obj.pixelSize        = NaN;
            obj.pixelUnit        = 'px';
            obj.scaleBarVisible  = false;
            obj.scaleBarColor    = [1 1 1];
            obj.scaleBarFontSize = 10;
            obj.scaleBarLength   = 0;
            obj.scaleBarUnit     = 'nm';
        end

        function applyCalibration(obj, pxSize, unit)
            obj.calibrated = true;
            obj.pixelSize  = pxSize;
            obj.pixelUnit  = unit;
        end

        function clearCalibration(obj)
            obj.calibrated = false;
            obj.pixelSize  = NaN;
            obj.pixelUnit  = 'px';
        end

        function setScaleBarColor(obj, rgb)
            obj.scaleBarColor = rgb;
        end

        function setScaleBarVisible(obj, tf)
            obj.scaleBarVisible = logical(tf);
        end

        function setScaleBarFontSize(obj, sz)
            obj.scaleBarFontSize = max(6, min(24, sz));
        end

        function sync(obj, appData)
        %SYNC  Mirror calibration state from active image.
            try
                obj.scaleBarColor = appData.scaleBarColor;
                idx = appData.activeIdx;
                if idx >= 1 && idx <= numel(appData.images)
                    imgData = appData.images{idx}.metadata.parserSpecific.imageData;
                    obj.calibrated = imgData.calibrated;
                    if obj.calibrated
                        obj.pixelSize = imgData.pixelSize;
                        obj.pixelUnit = imgData.pixelUnit;
                    else
                        obj.pixelSize = NaN;
                        obj.pixelUnit = 'px';
                    end
                else
                    obj.calibrated = false;
                    obj.pixelSize  = NaN;
                    obj.pixelUnit  = 'px';
                end
            catch
            end
        end

        function bindFromImageData(obj, imgData)
        %BINDFROMIMAGEDATA  Sync from an imageData struct directly.
            try
                if isstruct(imgData)
                    if isfield(imgData, 'calibrated') && imgData.calibrated
                        obj.calibrated = true;
                        obj.pixelSize = imgData.pixelSize;
                        obj.pixelUnit = imgData.pixelUnit;
                    else
                        obj.calibrated = false;
                        obj.pixelSize  = NaN;
                        obj.pixelUnit  = 'px';
                    end
                end
            catch
            end
        end

        function s = summarize(obj)
            if ~obj.calibrated
                s = 'Uncalibrated';
            else
                s = sprintf('Calibrated: %.4g %s/px', obj.pixelSize, obj.pixelUnit);
                if obj.scaleBarVisible
                    s = [s ', scale bar on'];
                end
            end
        end
    end
end
