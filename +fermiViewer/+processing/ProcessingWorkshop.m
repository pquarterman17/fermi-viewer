classdef ProcessingWorkshop < handle
%PROCESSINGWORKSHOP  Facade for FFT/Particle/Align processing tools.

    properties (SetAccess = protected)
        model   emViewer.processing.ProcessingWorkshopModel
        hook    struct = struct()
    end

    methods
        function obj = ProcessingWorkshop(hook)
            arguments
                hook struct = struct()
            end
            obj.hook  = hook;
            obj.model = emViewer.processing.ProcessingWorkshopModel();
        end

        function tf = isLiveFFTActive(obj)
            tf = obj.model.liveFFTActive;
        end

        function setLiveFFT(obj, tf)
            obj.model.setLiveFFT(tf);
        end

        function recordParticleResult(obj, count, threshold, minArea)
            obj.model.recordParticleResult(count, threshold, minArea);
        end

        function recordAlignment(obj, shifts)
            obj.model.recordAlignment(shifts);
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
