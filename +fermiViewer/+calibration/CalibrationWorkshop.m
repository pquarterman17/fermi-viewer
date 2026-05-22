classdef CalibrationWorkshop < handle
%CALIBRATIONWORKSHOP  Facade for FermiViewer calibration/scale-bar subsystem.

    properties (SetAccess = protected)
        model   emViewer.calibration.CalibrationWorkshopModel
        hook    struct = struct()
    end

    methods
        function obj = CalibrationWorkshop(hook)
            arguments
                hook struct = struct()
            end
            obj.hook  = hook;
            obj.model = emViewer.calibration.CalibrationWorkshopModel();
        end

        function sync(obj, appData)
            obj.model.sync(appData);
        end

        function tf = isCalibrated(obj)
            tf = obj.model.calibrated;
        end

        function [sz, unit] = getPixelSize(obj)
            sz   = obj.model.pixelSize;
            unit = obj.model.pixelUnit;
        end

        function s = summarize(obj)
            s = obj.model.summarize();
        end

        function reset(obj)
            obj.model.reset();
        end

        function show(~)
        end

        function hide(~)
        end

        function close(~)
        end

        function tf = hasHook(obj, fieldName)
            tf = isfield(obj.hook, fieldName) && ...
                 isa(obj.hook.(fieldName), 'function_handle');
        end
    end
end
