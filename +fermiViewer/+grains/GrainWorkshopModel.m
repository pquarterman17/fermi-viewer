classdef GrainWorkshopModel < handle
%GRAINWORKSHOPMODEL  State container for the FermiViewer grain-ID workshop.
%
%   Holds everything the grain workshop window needs that must persist
%   across callbacks: the source image and its calibration, the segmentation
%   parameters for both modes, the interactive training scribbles, the
%   trained classifier, the cached feature stack, and the latest result.
%
%   This is a `handle` class purely as a state container (per the project's
%   functional-with-handle-state-containers convention) — the segmentation
%   orchestration lives in the workshop's callbacks, not here. The few
%   methods are pure scribble-state mutations.
%
%   See also fermiViewer.grains.openGrainWorkshop, imaging.grains.segmentAuto,
%            imaging.grains.trainFromScribbles

    properties
        % ── Source ──────────────────────────────────────────────────────
        image      double = []      % [H x W] grayscale source (filtered pixels)
        pixelSize  double = NaN      % physical pixel size (NaN = uncalibrated)
        pixelUnit  string = "px"

        % ── Mode + parameters ────────────────────────────────────────────
        mode       (1,1) string {mustBeMember(mode, ["auto","trained"])} = "auto"
        K          (1,1) double = 4          % auto: number of feature clusters
        minArea    (1,1) double = 25         % min grain area (px)
        scales     (1,:) double = [2 4 8]    % feature scales
        superpixels    (1,1) logical = false % auto: cluster SLIC superpixels
        numSuperpixels (1,1) double = 300    % target superpixel count

        % ── Interactive training (trained mode) ──────────────────────────
        labelMask  double = []      % [H x W] scribble labels (0 = unlabelled)
        paintClass (1,1) double = 1 % class id currently being painted
        brushRadius(1,1) double = 4 % scribble brush radius (px)
        numClasses (1,1) double = 2 % how many scribble classes are offered
        boundaryClass double = []   % class id treated as boundary (excluded)
        classifierType (1,1) string {mustBeMember(classifierType, ["softmax","forest"])} = "softmax"
        model      struct = struct()% trained classifier (empty until trained)

        % ── Results ──────────────────────────────────────────────────────
        labels     double = []      % [H x W] grain label map (last run)
        result     struct = struct()% imaging.grains.grainStats result (last run)

        % ── Caches ────────────────────────────────────────────────────────
        featureCache double = []    % [H x W x F] feature cube (computed once)
        featureScales (1,:) double = []  % scales the cache was built with
    end

    methods
        function obj = GrainWorkshopModel(image, pixelSize, pixelUnit)
            %GRAINWORKSHOPMODEL  Construct from a source image + calibration.
            arguments
                image     double = []
                pixelSize double = NaN
                pixelUnit string = "px"
            end
            obj.image     = double(image);
            obj.pixelSize = pixelSize;
            obj.pixelUnit = pixelUnit;
            if ~isempty(image)
                obj.labelMask = zeros(size(image));
            end
        end

        function paintAt(obj, x, y)
            %PAINTAT  Paint a brush disk of paintClass at image coords (x,y).
            %   x = column, y = row (axes data coordinates, 1-based).
            if isempty(obj.labelMask), return; end
            [H, W] = size(obj.labelMask);
            r  = max(0, round(obj.brushRadius));
            cx = round(x); cy = round(y);
            rows = max(1, cy-r):min(H, cy+r);
            cols = max(1, cx-r):min(W, cx+r);
            if isempty(rows) || isempty(cols), return; end
            [CC, RR] = meshgrid(cols, rows);
            disk = (CC - cx).^2 + (RR - cy).^2 <= r^2;
            patch = obj.labelMask(rows, cols);
            patch(disk) = obj.paintClass;
            obj.labelMask(rows, cols) = patch;
        end

        function clearScribbles(obj)
            %CLEARSCRIBBLES  Erase all training labels and the trained model.
            if ~isempty(obj.image)
                obj.labelMask = zeros(size(obj.image));
            end
            obj.model = struct();
        end

        function tf = hasScribbles(obj)
            tf = ~isempty(obj.labelMask) && any(obj.labelMask(:) > 0);
        end

        function tf = isTrained(obj)
            tf = isfield(obj.model, 'W');
        end

        function [xy, classes] = scribblePoints(obj)
            %SCRIBBLEPOINTS  Labelled pixel coords + their class (for plotting).
            xy = zeros(0, 2); classes = zeros(0, 1);
            if ~obj.hasScribbles(), return; end
            idx = find(obj.labelMask > 0);
            [r, c] = ind2sub(size(obj.labelMask), idx);
            xy = [c, r];                 % [x y]
            classes = obj.labelMask(idx);
        end
    end
end
