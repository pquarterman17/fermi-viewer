classdef DiffractionWorkshopModel < handle
%DIFFRACTIONWORKSHOPMODEL  State container for the FermiViewer diffraction subsystem.
%
%   Owns: spot list, indexing results, TEM geometry parameters, GPA
%   state, and d-spacing measurement cache. Replaces the flat
%   appData.diff* fields with a testable, self-contained model.
%
%   The model does NOT draw — all rendering goes through the hook
%   API in DiffractionWorkshop. This class is pure state + computation.
%
%   Canonical fields on each spot: [row, col] in pixel coordinates.
%   Results struct mirrors imaging.indexDiffraction output.

    properties (SetAccess = public)
        spots         (:,2) double  = zeros(0,2)
        results       struct        = struct()
        cameraLength  (1,1) double  = NaN
        accVoltage    (1,1) double  = 200
        zoneAxis      (1,3) double  = [0 0 1]
        pixelSize     (1,1) double  = 1
        pixelUnit     (1,:) char    = 'px'
        calibrated    (1,1) logical = false
        imageSize     (1,2) double  = [0 0]
    end

    properties (SetAccess = private)
        selectedCandidateIdx  (1,1) double = 0
    end

    methods
        function addSpots(obj, newSpots)
            if isempty(newSpots), return; end
            obj.spots = [obj.spots; newSpots];
        end

        function addSpot(obj, row, col)
            obj.spots(end+1, :) = [row, col];
        end

        function clearSpots(obj)
            obj.spots   = zeros(0, 2);
            obj.results = struct();
            obj.selectedCandidateIdx = 0;
        end

        function n = numSpots(obj)
            n = size(obj.spots, 1);
        end

        function setResults(obj, res)
            if nargin < 2 || isempty(res)
                obj.results = struct();
                obj.selectedCandidateIdx = 0;
                return;
            end
            obj.results = res;
            if isfield(res, 'candidates') && ~isempty(res.candidates)
                obj.selectedCandidateIdx = 1;
            else
                obj.selectedCandidateIdx = 0;
            end
        end

        function selectCandidate(obj, idx)
            if isfield(obj.results, 'candidates') && ...
                    idx >= 1 && idx <= numel(obj.results.candidates)
                obj.selectedCandidateIdx = idx;
            end
        end

        function c = getSelectedCandidate(obj)
            if obj.selectedCandidateIdx >= 1 && ...
                    isfield(obj.results, 'candidates') && ...
                    obj.selectedCandidateIdx <= numel(obj.results.candidates)
                c = obj.results.candidates(obj.selectedCandidateIdx);
            else
                c = [];
            end
        end

        function tf = hasResults(obj)
            tf = isfield(obj.results, 'candidates') && ...
                 ~isempty(obj.results.candidates);
        end

        function bindFromImage(obj, imgInfo)
            if nargin < 2 || isempty(imgInfo), return; end
            if isfield(imgInfo, 'pixelSize') && ~isnan(imgInfo.pixelSize)
                obj.pixelSize  = imgInfo.pixelSize;
            end
            if isfield(imgInfo, 'pixelUnit')
                obj.pixelUnit = imgInfo.pixelUnit;
            end
            if isfield(imgInfo, 'calibrated')
                obj.calibrated = imgInfo.calibrated;
            end
            if isfield(imgInfo, 'pixels')
                obj.imageSize = [size(imgInfo.pixels, 1), size(imgInfo.pixels, 2)];
            end
        end

        function sync(obj, appDataDiff)
        %SYNC  Re-sync model from appData diffraction fields.
        %   Swallows errors so a sync failure never blocks the UI.
            try
                if isfield(appDataDiff, 'diffSpots')
                    obj.spots = appDataDiff.diffSpots;
                    if isempty(obj.spots)
                        obj.spots = zeros(0, 2);
                    end
                end
                if isfield(appDataDiff, 'diffResults')
                    obj.setResults(appDataDiff.diffResults);
                end
                if isfield(appDataDiff, 'diffCameraLen')
                    obj.cameraLength = appDataDiff.diffCameraLen;
                end
                if isfield(appDataDiff, 'diffAccVoltage')
                    obj.accVoltage = appDataDiff.diffAccVoltage;
                end
            catch
            end
        end

        function s = summarize(obj)
        %SUMMARIZE  One-line status string for the current state.
            if obj.numSpots() == 0
                s = 'No spots detected';
                return;
            end
            s = sprintf('%d spots', obj.numSpots());
            if obj.hasResults()
                c = obj.getSelectedCandidate();
                if ~isempty(c)
                    s = sprintf('%s | %s (score=%.2f)', s, c.phaseName, c.score);
                end
            end
        end

        function tbl = spotsTable(obj)
        %SPOTSTABLE  Return spots as a table with SpotRow, SpotCol columns.
            if obj.numSpots() == 0
                tbl = table([], [], 'VariableNames', {'SpotRow', 'SpotCol'});
            else
                tbl = table(obj.spots(:,1), obj.spots(:,2), ...
                    'VariableNames', {'SpotRow', 'SpotCol'});
            end
        end

        function dVals = computeDSpacings(obj)
        %COMPUTEDSPACINGS  d-spacing for each spot from image center.
        %   d = N * pixelSize / r_px where N = sqrt(H*W).
            if obj.numSpots() == 0 || all(obj.imageSize == 0)
                dVals = [];
                return;
            end
            H = obj.imageSize(1);
            W = obj.imageSize(2);
            cx = W / 2;
            cy = H / 2;
            N  = sqrt(H * W);
            rPx = sqrt((obj.spots(:,2) - cx).^2 + (obj.spots(:,1) - cy).^2);
            dVals = N * obj.pixelSize ./ max(rPx, 1);
        end
    end
end
