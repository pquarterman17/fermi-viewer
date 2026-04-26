classdef MeasurementWorkshopModel < handle
%MEASUREMENTWORKSHOPMODEL  State container for FermiViewer's measurement tools.
%
%   Owns the list of measurements (distance, angle, polyline, line
%   profile, box profile) accumulated by the user — independent of the
%   graphics handles the dialog draws on the image. The model can be
%   exercised in isolation against synthetic image arrays for batch
%   measurement analysis or scripted EM workflows.
%
%   Workshop pattern (MASTERPLAN W5 #28 / #65). The FermiViewer dialog
%   (FermiViewer.m, ~13,900 lines) currently owns measurement state in
%   `appData.overlays.measurements{:}`. This model extracts the
%   *data* part of each measurement (type, points, value, unit, label)
%   so the algorithmic core is testable + scriptable. Graphics handles
%   stay with the view.
%
%   Usage:
%       m = emViewer.measurement.MeasurementWorkshopModel();
%       m.pixelSize = 0.5;  m.pixelUnit = 'nm';
%       m.addDistance([10 10], [50 30]);
%       m.addAngle([20 20], [40 20], [20 40]);     % vertex, ray1, ray2
%       m.addPolyline([0 0; 5 0; 5 5; 10 5]);
%       stats = m.aggregateStats();                 % across distance metrics

    % ── Calibration ──────────────────────────────────────────────────
    properties
        pixelSize  double = NaN     % physical units per pixel
        pixelUnit  char   = 'px'    % 'nm', 'um', 'px', etc.
        tiltAngle  double = 0       % stage tilt in degrees
        tiltAxis   char   = 'Y'     % 'X' or 'Y' — which image axis is foreshortened
        tiltGeom   char   = 'CrossSection'   % 'CrossSection' | 'Surface'
    end

    % ── Measurement list (struct array; SetAccess protected) ─────────
    properties (SetAccess = protected)
        measurements = emViewer.measurement.MeasurementWorkshopModel.emptyMeas()
        selectedIdx  double = 0
    end

    methods
        function obj = MeasurementWorkshopModel()
        end

        function bindFromImage(obj, imgInfo)
        %BINDFROMIMAGE  Pull pixelSize / pixelUnit from an imgInfo struct.
        %   imgInfo: typically datasets{i}.metadata.parserSpecific.imageData
        %   with fields .pixelSize (numeric) and .pixelUnit (char).
            if isfield(imgInfo, 'pixelSize') && ~isnan(imgInfo.pixelSize)
                obj.pixelSize = imgInfo.pixelSize;
            end
            if isfield(imgInfo, 'pixelUnit') && ~isempty(imgInfo.pixelUnit)
                obj.pixelUnit = imgInfo.pixelUnit;
            end
        end

        % ── Measurement adders ───────────────────────────────────────
        function r = addDistance(obj, p1, p2, opts)
        %ADDDISTANCE  Append a 2-point distance measurement.
            arguments
                obj
                p1 (1,2) double
                p2 (1,2) double
                opts.label char = ''
            end
            if ~isnan(obj.pixelSize)
                [dv, du] = imaging.measureDistance(p1(1), p1(2), p2(1), p2(2), ...
                    PixelSize=obj.pixelSize, PixelUnit=obj.pixelUnit, ...
                    TiltAngle=obj.tiltAngle, TiltAxis=obj.tiltAxis, Geometry=obj.tiltGeom);
            else
                [dv, du] = imaging.measureDistance(p1(1), p1(2), p2(1), p2(2), ...
                    TiltAngle=obj.tiltAngle, TiltAxis=obj.tiltAxis, Geometry=obj.tiltGeom);
            end
            r = obj.makeMeas('distance', [p1; p2], dv, du, opts.label);
            obj.measurements(end+1) = r;
        end

        function r = addAngle(obj, vertex, p1, p2, opts)
        %ADDANGLE  Append a 3-point angle measurement (vertex, ray1, ray2).
            arguments
                obj
                vertex (1,2) double
                p1     (1,2) double
                p2     (1,2) double
                opts.label char = ''
            end
            v1 = p1 - vertex;  v2 = p2 - vertex;
            angDeg = emViewer.measurements('computeAngle', ...
                v1, v2, obj.tiltAngle, obj.tiltAxis, obj.tiltGeom);
            r = obj.makeMeas('angle', [vertex; p1; p2], angDeg, 'deg', opts.label);
            obj.measurements(end+1) = r;
        end

        function r = addPolyline(obj, pts, opts)
        %ADDPOLYLINE  Append a polyline path-length measurement (Nx2 points).
            arguments
                obj
                pts double
                opts.label char = ''
            end
            if size(pts, 2) ~= 2 || size(pts, 1) < 2
                error('MWM:badPts','Polyline needs Nx2 points (N>=2)');
            end
            distPx = emViewer.measurements('polylineLength', ...
                pts, obj.tiltAngle, obj.tiltAxis, obj.tiltGeom);
            if ~isnan(obj.pixelSize)
                dv = distPx * obj.pixelSize;  du = obj.pixelUnit;
            else
                dv = distPx;  du = 'px';
            end
            r = obj.makeMeas('polyline', pts, dv, du, opts.label);
            obj.measurements(end+1) = r;
        end

        function r = addLineProfile(obj, p1, p2, img, opts)
        %ADDLINEPROFILE  Sample image intensity along a line; return profile.
            arguments
                obj
                p1   (1,2) double
                p2   (1,2) double
                img  double
                opts.nSamples (1,1) double = 500
                opts.label    char         = ''
            end
            xs = linspace(p1(1), p2(1), opts.nSamples);
            ys = linspace(p1(2), p2(2), opts.nSamples);
            % Bilinear interpolation via interp2 (transpose-aware: img
            % is [rows, cols] so x → col, y → row)
            try
                profile_ = interp2(img, xs, ys, 'linear', NaN);
            catch
                profile_ = nan(size(xs));
            end
            distPx = sqrt(sum((p2 - p1).^2));
            if ~isnan(obj.pixelSize)
                dv = distPx * obj.pixelSize;  du = obj.pixelUnit;
            else
                dv = distPx;  du = 'px';
            end
            r = obj.makeMeas('lineprofile', [p1; p2], dv, du, opts.label);
            r.profile = profile_(:);
            r.profileX = linspace(0, dv, opts.nSamples)';
            obj.measurements(end+1) = r;
        end

        % ── List management ──────────────────────────────────────────
        function removeMeas(obj, idx)
            if idx < 1 || idx > numel(obj.measurements), return; end
            obj.measurements(idx) = [];
            if obj.selectedIdx == idx, obj.selectedIdx = 0;
            elseif obj.selectedIdx > idx, obj.selectedIdx = obj.selectedIdx - 1; end
        end

        function clearAll(obj)
            obj.measurements = emViewer.measurement.MeasurementWorkshopModel.emptyMeas();
            obj.selectedIdx  = 0;
        end

        function selectMeas(obj, idx)
            if idx >= 0 && idx <= numel(obj.measurements)
                obj.selectedIdx = idx;
            end
        end

        % ── Stats + export ───────────────────────────────────────────
        function s = aggregateStats(obj)
        %AGGREGATESTATS  Mean/std/min/max across distance-like measurements.
        %   Aggregates over types {'distance','polyline','lineprofile'}
        %   — anything where .value is a length. Uses
        %   emViewer.measurements('aggregateStats', ...).
            distLike = obj.measurements( ...
                ismember({obj.measurements.type}, {'distance','polyline','lineprofile'}));
            if isempty(distLike)
                s = struct('distances', [], 'count', 0, ...
                    'mean', NaN, 'std', NaN, 'min', NaN, 'max', NaN);
                return;
            end
            % Repackage into the cell-of-struct format expected by
            % emViewer.measurements; each entry needs a .distance field.
            cellList = arrayfun(@(m) struct('distance', m.value), distLike, ...
                'UniformOutput', false);
            s = emViewer.measurements('aggregateStats', cellList);
        end

        function exportCSV(obj, filename)
        %EXPORTCSV  Write measurements to a CSV file.
            fid = fopen(filename, 'w');
            cleanup = onCleanup(@() fclose(fid));
            fprintf(fid, 'Idx,Type,Value,Unit,Label,N_Points\n');
            for k = 1:numel(obj.measurements)
                m = obj.measurements(k);
                fprintf(fid, '%d,%s,%.6g,%s,%s,%d\n', ...
                    k, m.type, m.value, m.unit, m.label, size(m.points, 1));
            end
        end

        function tf = isEmpty(obj)
            tf = numel(obj.measurements) == 0;
        end
    end

    methods (Access = protected)
        function r = makeMeas(~, type, points, value, unit, label)
            r = emViewer.measurement.MeasurementWorkshopModel.emptyOnePeak();
            r.type   = type;
            r.points = points;
            r.value  = value;
            r.unit   = unit;
            r.label  = label;
        end
    end

    methods (Static, Access = public)
        function s = emptyMeas()
        %EMPTYMEAS  Canonical empty measurement struct array (0×0).
            s = struct('type', {}, 'points', {}, 'value', {}, 'unit', {}, ...
                       'label', {}, 'profile', {}, 'profileX', {});
        end

        function s = emptyOnePeak()
        %EMPTYONEPEAK  Canonical single measurement struct (1×1) with
        %   all 7 fields populated. Returned by makeMeas to feed
        %   measurements struct array.
            s = struct('type', '', 'points', [], 'value', NaN, 'unit', '', ...
                       'label', '', 'profile', [], 'profileX', []);
        end

        function s = normalizeMeasurements(input)
        %NORMALIZEMEASUREMENTS  Upgrade legacy measurement arrays to canonical
        %   7-field shape (workshop-pattern contract rule #1).
            if isempty(input)
                s = emViewer.measurement.MeasurementWorkshopModel.emptyMeas();
                return;
            end
            canonical = {'type','points','value','unit','label','profile','profileX'};
            defaults  = {'',  [],     NaN,    '',    '',    [],       []};
            s = input;
            for fi = 1:numel(canonical)
                f = canonical{fi};
                if ~isfield(s, f), [s.(f)] = deal(defaults{fi}); end
            end
        end

        function model = fromOverlayMeasurements(cellArr, calib)
        %FROMOVERLAYMEASUREMENTS  Build a populated model from FermiViewer's
        %   overlays.measurements cell array. Maps the dialog's heterogeneous
        %   per-type schema to the canonical 7-field shape, dropping graphics
        %   handles. Skips entries that lack a scalar aggregable value (e.g.
        %   profile-only and ROI records).
        %
        %   cellArr — cell array of measurement structs as stored in
        %             appData.overlays.measurements
        %   calib   — optional struct with fields .pixelSize, .pixelUnit,
        %             .tiltAngle, .tiltAxis, .tiltGeom (any subset honored)
            model = emViewer.measurement.MeasurementWorkshopModel();
            if nargin >= 2 && ~isempty(calib)
                fns = fieldnames(calib);
                for fi = 1:numel(fns)
                    if isprop(model, fns{fi}) && ~isempty(calib.(fns{fi}))
                        model.(fns{fi}) = calib.(fns{fi});
                    end
                end
            end
            if isempty(cellArr), return; end
            list = emViewer.measurement.MeasurementWorkshopModel.emptyMeas();
            for k = 1:numel(cellArr)
                src = cellArr{k};
                if ~isstruct(src) || ~isfield(src, 'type'), continue; end
                rec = emViewer.measurement.MeasurementWorkshopModel.emptyOnePeak();
                rec.type = src.type;
                if isfield(src, 'unit'),  rec.unit  = src.unit;  end
                if isfield(src, 'label'), rec.label = src.label; end
                switch lower(src.type)
                    case 'distance'
                        if isfield(src, 'distance'), rec.value = src.distance; end
                    case 'polyline'
                        if isfield(src, 'totalDist'), rec.value = src.totalDist; end
                        if isfield(src, 'vertices'),  rec.points = src.vertices; end
                    case 'lineprofile'
                        if isfield(src, 'value'), rec.value = src.value; end
                    otherwise
                        % rectROI / profile / others — skip from aggregable list
                        continue;
                end
                if ~isnan(rec.value)
                    list(end+1) = rec; %#ok<AGROW>
                end
            end
            % Direct internal assignment (SetAccess = protected only blocks
            % external writes; static methods on the same class can write).
            model.measurements = list;
        end
    end
end
