classdef DiffractionWorkshop < handle
%DIFFRACTIONWORKSHOP  Facade for the FermiViewer diffraction subsystem.
%
%   Owns a DiffractionWorkshopModel and the hook struct FermiViewer
%   passes in. Mirrors emViewer.measurement.MeasurementWorkshop.
%
%   Hook contract (subset of the 8-field struct):
%     hook.setStatus         @(msg)
%     hook.drawOverlay       @(type, args)
%     hook.clearOverlays     @(filter)   filter='diff_spot'|'diff_ring'
%     hook.replot            @()
%     hook.logError          @(ME)
%
%   Usage from FermiViewer.m:
%       ws = emViewer.diffraction.DiffractionWorkshop();
%       ws.bindCalibration(imgInfo);
%       ws.sync(struct('diffSpots', appData.diffSpots, ...));

    properties (SetAccess = protected)
        model    emViewer.diffraction.DiffractionWorkshopModel
        hook     struct = struct()
    end

    methods
        function obj = DiffractionWorkshop(hook)
            arguments
                hook struct = struct()
            end
            obj.hook  = hook;
            obj.model = emViewer.diffraction.DiffractionWorkshopModel();
        end

        function bindCalibration(obj, imgInfo)
            if nargin < 2 || isempty(imgInfo), return; end
            obj.model.bindFromImage(imgInfo);
        end

        function sync(obj, appDataDiff)
            obj.model.sync(appDataDiff);
        end

        function clearSpots(obj)
            obj.model.clearSpots();
        end

        function n = numSpots(obj)
            n = obj.model.numSpots();
        end

        function tf = hasResults(obj)
            tf = obj.model.hasResults();
        end

        function s = summarize(obj)
            s = obj.model.summarize();
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
