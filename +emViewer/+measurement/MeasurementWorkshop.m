classdef MeasurementWorkshop < handle
%MEASUREMENTWORKSHOP  Facade for the FermiViewer measurement subsystem.
%
%   Owns a MeasurementWorkshopModel and the hook struct FermiViewer
%   passes in. Mirrors bosonPlotter.peak.PeakWorkshop — same pattern,
%   same lifecycle (constructor in 1b, real cutover in 1c).
%
%   Hook contract (the 8-field struct FermiViewer.m must build before
%   constructing the workshop). Each field is a function handle:
%
%     hook.getActiveImage    @() struct(pixels=..., calibrated=...,
%                                       pixelSize=..., pixelUnit=...,
%                                       metadata=...)
%     hook.setStatus         @(msg)               bottom-bar status
%     hook.drawOverlay       @(type, args) handle measurement line, ROI rect, text label
%     hook.clearOverlays     @(filter)            'measurements'|'roi'|'all'|tag
%     hook.enableClickMode   @(name, callback)    start a two-click capture
%     hook.disableClickMode  @()
%     hook.replot            @()                  refreshDisplay
%     hook.logError          @(ME)
%
%   The workshop NEVER reaches into FermiViewer's appData / fig / ax
%   directly. Cross-workshop communication goes through hook calls
%   mediated by the parent.
%
%   Usage from FermiViewer.m (target shape, lands in 1c):
%       hook = emViewer.measurement.buildHook(fig, ax, appData);
%       ws   = emViewer.measurement.MeasurementWorkshop(hook);
%       ws.bind(appData.overlays.measurements);
%       ws.bindCalibration(imgInfo);
%       ws.selectMeas(idx);
%
%   Today (1b) the facade is operational for the model side: bind /
%   bindCalibration / selectMeas / getMeasurements all work without
%   needing the hook. show() / hide() error out until the dialog
%   cutover lands in 1c.

    properties (SetAccess = protected)
        model    emViewer.measurement.MeasurementWorkshopModel
        hook     struct  = struct()
        widgets  struct  = struct()
        measFig                                  % uifigure handle (1c)
    end

    methods
        function obj = MeasurementWorkshop(hook)
        %MEASUREMENTWORKSHOP  Construct with a hook struct.
        %   hook may be empty (struct()) for headless / model-only use;
        %   the workshop will still bind + aggregate + export, but any
        %   call that requires drawing will error.
            arguments
                hook struct = struct()
            end
            obj.hook  = hook;
            obj.model = emViewer.measurement.MeasurementWorkshopModel();
        end

        function bind(obj, overlayCellArr)
        %BIND  Replace the model's measurement list from
        %   appData.overlays.measurements (cell array of structs).
        %   Normalizes legacy-shaped input via
        %   MeasurementWorkshopModel.normalizeMeasurements.
            if nargin < 2, overlayCellArr = {}; end
            obj.model.bindFromOverlays(overlayCellArr);
        end

        function bindCalibration(obj, imgInfo)
        %BINDCALIBRATION  Pull pixelSize / pixelUnit from an imgInfo
        %   struct (typically datasets{i}.metadata.parserSpecific.imageData).
            if nargin < 2 || isempty(imgInfo), return; end
            obj.model.bindFromImage(imgInfo);
        end

        function selectMeas(obj, idx)
            obj.model.selectMeas(idx);
        end

        function removeMeas(obj, idx)
            obj.model.removeMeas(idx);
        end

        function clearAll(obj)
            obj.model.clearAll();
        end

        function s = getMeasurements(obj)
            s = obj.model.measurements;
        end

        function n = numMeasurements(obj)
            n = numel(obj.model.measurements);
        end

        function show(~)
            error('MeasurementWorkshop:notImplemented', ...
                'show() arrives in 1c with the dialog cutover.');
        end

        function hide(~)
            error('MeasurementWorkshop:notImplemented', ...
                'hide() arrives in 1c with the dialog cutover.');
        end

        function close(obj)
            if ~isempty(obj.measFig) && isvalid(obj.measFig)
                delete(obj.measFig);
            end
        end

        function tf = hasHook(obj, fieldName)
        %HASHOOK  True if the hook struct carries `fieldName` and it is
        %   a function handle. Use this in 1c cutover code to guard
        %   any draw/replot call so the workshop stays usable in
        %   headless contexts.
            tf = isfield(obj.hook, fieldName) && ...
                 isa(obj.hook.(fieldName), 'function_handle');
        end
    end
end
