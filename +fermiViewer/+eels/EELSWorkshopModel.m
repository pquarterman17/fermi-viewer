classdef EELSWorkshopModel < handle
%EELSWORKSHOPMODEL  State container for FermiViewer EELS subsystem.
%
%   Owns EELS mode state, spectrum data, cube reference, analysis results,
%   and UI-parameter snapshots. No graphics handles or figure references.

    properties (SetAccess = public)
        active          (1,1) logical  = false
        energyAxis      (:,1) double   = []
        counts          (:,1) double   = []
        hasCube         (1,1) logical  = false
        cubeSize        (1,3) double   = [0 0 0]

        bgMethod        (1,:) char     = 'powerlaw'
        preEdgeWindow   (1,2) double   = [0 0]
        signalWindow    (1,2) double   = [0 0]
        edgeOnset       (1,1) double   = NaN

        showEdges       (1,1) logical  = false
        edgeFilter      (1,:) char     = 'All'
        navigateMode    (1,1) logical  = false

        hasSSD          (1,1) logical  = false
        hasKKResult     (1,1) logical  = false
        hasSVDResult    (1,1) logical  = false
        hasELNESResult  (1,1) logical  = false

        lastTLambda     (1,1) double   = NaN
        lastSVDExplained (:,1) double  = []
    end

    methods
        function reset(obj)
            obj.active          = false;
            obj.energyAxis      = [];
            obj.counts          = [];
            obj.hasCube         = false;
            obj.cubeSize        = [0 0 0];
            obj.bgMethod        = 'powerlaw';
            obj.preEdgeWindow   = [0 0];
            obj.signalWindow    = [0 0];
            obj.edgeOnset       = NaN;
            obj.showEdges       = false;
            obj.edgeFilter      = 'All';
            obj.navigateMode    = false;
            obj.hasSSD          = false;
            obj.hasKKResult     = false;
            obj.hasSVDResult    = false;
            obj.hasELNESResult  = false;
            obj.lastTLambda     = NaN;
            obj.lastSVDExplained = [];
        end

        function bindFromAppData(obj, eelsData, eelsCube, eelsEnergyAxis)
        %BINDFROMAPPDATA  Sync model from FermiViewer's appData fields.
            try
                if ~isempty(eelsData) && isstruct(eelsData)
                    if isfield(eelsData, 'energyAxis')
                        obj.energyAxis = eelsData.energyAxis(:);
                    end
                    if isfield(eelsData, 'counts')
                        obj.counts = double(eelsData.counts(:));
                    end
                end
                if nargin >= 3 && ~isempty(eelsCube)
                    obj.hasCube = true;
                    obj.cubeSize = size(eelsCube);
                else
                    obj.hasCube = false;
                    obj.cubeSize = [0 0 0];
                end
                if nargin >= 4 && ~isempty(eelsEnergyAxis)
                    obj.energyAxis = eelsEnergyAxis(:);
                end
            catch
            end
        end

        function sync(obj, appData)
        %SYNC  Mirror EELS-related appData fields into model.
            try
                obj.active = appData.eelsMode;
                if ~isempty(appData.eelsData) && isstruct(appData.eelsData)
                    if isfield(appData.eelsData, 'energyAxis')
                        obj.energyAxis = appData.eelsData.energyAxis(:);
                    end
                    if isfield(appData.eelsData, 'counts')
                        obj.counts = double(appData.eelsData.counts(:));
                    end
                else
                    obj.energyAxis = [];
                    obj.counts = [];
                end
                obj.hasCube = ~isempty(appData.eelsCube);
                if obj.hasCube
                    obj.cubeSize = size(appData.eelsCube);
                else
                    obj.cubeSize = [0 0 0];
                end
                if ~isempty(appData.eelsEnergyAxis)
                    obj.energyAxis = appData.eelsEnergyAxis(:);
                end
                obj.hasSSD         = ~isempty(appData.eelsSSD);
                obj.hasKKResult    = ~isempty(appData.eelsKKResult);
                obj.hasSVDResult   = ~isempty(appData.eelsSVDResult);
            catch
            end
        end

        function n = numChannels(obj)
            n = numel(obj.energyAxis);
        end

        function tf = hasSpectrum(obj)
            tf = ~isempty(obj.counts) && numel(obj.counts) > 0;
        end

        function setPreEdgeWindow(obj, e1, e2)
            if e1 < e2
                obj.preEdgeWindow = [e1 e2];
            end
        end

        function setSignalWindow(obj, e1, e2)
            if e1 < e2
                obj.signalWindow = [e1 e2];
            end
        end

        function setEdgeOnset(obj, val)
            obj.edgeOnset = val;
        end

        function setBgMethod(obj, method)
            obj.bgMethod = method;
        end

        function setNavigateMode(obj, tf)
            obj.navigateMode = tf;
        end

        function s = summarize(obj)
            if ~obj.active
                s = 'EELS inactive';
            elseif ~obj.hasSpectrum()
                s = 'EELS active (no spectrum)';
            else
                parts = {sprintf('EELS: %d channels', obj.numChannels())};
                if obj.hasCube
                    parts{end+1} = sprintf('cube %dx%dx%d', ...
                        obj.cubeSize(1), obj.cubeSize(2), obj.cubeSize(3));
                end
                if obj.hasSSD, parts{end+1} = 'SSD'; end
                if obj.hasKKResult, parts{end+1} = 'KK'; end
                if obj.hasSVDResult, parts{end+1} = 'SVD'; end
                s = strjoin(parts, ', ');
            end
        end
    end
end
