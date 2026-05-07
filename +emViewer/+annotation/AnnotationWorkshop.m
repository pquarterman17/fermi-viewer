classdef AnnotationWorkshop < handle
%ANNOTATIONWORKSHOP  Facade for the FermiViewer annotation subsystem.

    properties (SetAccess = protected)
        model   emViewer.annotation.AnnotationWorkshopModel
        hook    struct = struct()
    end

    methods
        function obj = AnnotationWorkshop(hook)
            arguments
                hook struct = struct()
            end
            obj.hook  = hook;
            obj.model = emViewer.annotation.AnnotationWorkshopModel();
        end

        function sync(obj, annotCellArr)
            obj.model.sync(annotCellArr);
        end

        function n = numAnnotations(obj)
            n = obj.model.numAnnotations();
        end

        function clearAll(obj)
            obj.model.clearAll();
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
