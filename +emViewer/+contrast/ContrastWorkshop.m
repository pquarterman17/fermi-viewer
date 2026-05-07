classdef ContrastWorkshop < handle
%CONTRASTWORKSHOP  Facade for the FermiViewer contrast/histogram subsystem.
%
%   Owns a ContrastWorkshopModel. Mirrors the MeasurementWorkshop
%   and DiffractionWorkshop pattern.
%
%   Hook contract (subset):
%     hook.setStatus       @(msg)
%     hook.replot          @()
%     hook.refreshHist     @()

    properties (SetAccess = protected)
        model   emViewer.contrast.ContrastWorkshopModel
        hook    struct = struct()
    end

    methods
        function obj = ContrastWorkshop(hook)
            arguments
                hook struct = struct()
            end
            obj.hook  = hook;
            obj.model = emViewer.contrast.ContrastWorkshopModel();
        end

        function setLimits(obj, lo, hi)
            obj.model.setLimits(lo, hi);
        end

        function setTransform(obj, mode)
            obj.model.setTransform(mode);
        end

        function setGamma(obj, g)
            obj.model.setGamma(g);
        end

        function setInvert(obj, tf)
            obj.model.setInvert(tf);
        end

        function reset(obj)
            obj.model.reset();
        end

        function autoFromPixels(obj, pixels)
            obj.model.autoFromPixels(pixels);
        end

        function sync(obj, params)
            obj.model.sync(params);
        end

        function s = toStruct(obj)
            s = obj.model.toStruct();
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
