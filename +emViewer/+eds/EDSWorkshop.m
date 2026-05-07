classdef EDSWorkshop < handle
%EDSWORKSHOP  Facade for the FermiViewer EDS subsystem.

    properties (SetAccess = protected)
        model   emViewer.eds.EDSWorkshopModel
        hook    struct = struct()
    end

    methods
        function obj = EDSWorkshop(hook)
            arguments
                hook struct = struct()
            end
            obj.hook  = hook;
            obj.model = emViewer.eds.EDSWorkshopModel();
        end

        function sync(obj, appData)
            obj.model.sync(appData);
        end

        function tf = isActive(obj)
            tf = obj.model.active;
        end

        function n = numChannels(obj)
            n = obj.model.numChannels();
        end

        function n = numVisible(obj)
            n = obj.model.numVisible();
        end

        function tf = isQuantified(obj)
            tf = obj.model.quantified;
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
