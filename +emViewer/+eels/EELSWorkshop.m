classdef EELSWorkshop < handle
%EELSWORKSHOP  Facade for the FermiViewer EELS subsystem.

    properties (SetAccess = protected)
        model   emViewer.eels.EELSWorkshopModel
        hook    struct = struct()
    end

    methods
        function obj = EELSWorkshop(hook)
            arguments
                hook struct = struct()
            end
            obj.hook  = hook;
            obj.model = emViewer.eels.EELSWorkshopModel();
        end

        function sync(obj, appData)
            obj.model.sync(appData);
        end

        function tf = isActive(obj)
            tf = obj.model.active;
        end

        function tf = hasSpectrum(obj)
            tf = obj.model.hasSpectrum();
        end

        function tf = hasCube(obj)
            tf = obj.model.hasCube;
        end

        function n = numChannels(obj)
            n = obj.model.numChannels();
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
