classdef EDSWorkshopModel < handle
%EDSWORKSHOPMODEL  State container for FermiViewer EDS subsystem.
%
%   Owns EDS mode state, channel list, quantification results. No graphics.

    properties (SetAccess = public)
        active          (1,1) logical  = false
        channels        cell           = {}
        hasComposite    (1,1) logical  = false
        compositeSize   (1,2) double   = [0 0]

        quantified      (1,1) logical  = false
        elements        cell           = {}
        numMaps         (1,1) double   = 0
    end

    methods
        function reset(obj)
            obj.active        = false;
            obj.channels      = {};
            obj.hasComposite  = false;
            obj.compositeSize = [0 0];
            obj.quantified    = false;
            obj.elements      = {};
            obj.numMaps       = 0;
        end

        function n = numChannels(obj)
            n = numel(obj.channels);
        end

        function n = numVisible(obj)
            n = 0;
            for k = 1:numel(obj.channels)
                if isstruct(obj.channels{k}) && isfield(obj.channels{k}, 'visible') ...
                        && obj.channels{k}.visible
                    n = n + 1;
                end
            end
        end

        function addChannel(obj, ch)
            if ~isstruct(ch), return; end
            ch = normalizeChannel(ch);
            obj.channels{end+1} = ch;
        end

        function removeChannel(obj, idx)
            if idx < 1 || idx > numel(obj.channels), return; end
            obj.channels(idx) = [];
        end

        function setChannelVisible(obj, idx, tf)
            if idx < 1 || idx > numel(obj.channels), return; end
            obj.channels{idx}.visible = logical(tf);
        end

        function setChannelIntensity(obj, idx, val)
            if idx < 1 || idx > numel(obj.channels), return; end
            obj.channels{idx}.intensity = max(0, min(2, val));
        end

        function setChannelColor(obj, idx, color)
            if idx < 1 || idx > numel(obj.channels), return; end
            obj.channels{idx}.color = color;
        end

        function setChannelLabel(obj, idx, lbl)
            if idx < 1 || idx > numel(obj.channels), return; end
            obj.channels{idx}.label = lbl;
        end

        function ch = getChannel(obj, idx)
            if idx >= 1 && idx <= numel(obj.channels)
                ch = obj.channels{idx};
            else
                ch = [];
            end
        end

        function sync(obj, appData)
        %SYNC  Mirror EDS-related appData fields into model.
            try
                obj.active = appData.edsMode;
                if ~isempty(appData.edsChannels)
                    obj.channels = appData.edsChannels;
                else
                    obj.channels = {};
                end
                obj.hasComposite = ~isempty(appData.edsComposite);
                if obj.hasComposite
                    sz = size(appData.edsComposite);
                    obj.compositeSize = sz(1:2);
                else
                    obj.compositeSize = [0 0];
                end
                obj.quantified = appData.edsQuantified;
                if ~isempty(appData.edsElements)
                    obj.elements = appData.edsElements;
                else
                    obj.elements = {};
                end
                obj.numMaps = numel(appData.edsAtomicPct);
            catch
            end
        end

        function s = summarize(obj)
            if ~obj.active
                s = 'EDS inactive';
            elseif obj.numChannels() == 0
                s = 'EDS active (no channels)';
            else
                parts = {sprintf('EDS: %d ch (%d visible)', ...
                    obj.numChannels(), obj.numVisible())};
                if obj.quantified
                    parts{end+1} = sprintf('quantified (%s)', strjoin(obj.elements, ','));
                end
                s = strjoin(parts, ', ');
            end
        end
    end
end

function ch = normalizeChannel(ch)
    if ~isfield(ch, 'imageIdx'),  ch.imageIdx  = 0; end
    if ~isfield(ch, 'label'),     ch.label     = ''; end
    if ~isfield(ch, 'color'),     ch.color     = [1 1 1]; end
    if ~isfield(ch, 'visible'),   ch.visible   = true; end
    if ~isfield(ch, 'intensity'), ch.intensity = 1.0; end
end
