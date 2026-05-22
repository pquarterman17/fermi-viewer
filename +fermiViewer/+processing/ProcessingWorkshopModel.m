classdef ProcessingWorkshopModel < handle
%PROCESSINGWORKSHOPMODEL  State container for FermiViewer FFT/Particle/Align tools.
%
%   Lightweight model for the processing subsystem. These tools are mostly
%   fire-and-forget (stateless per-invocation), but the workshop tracks:
%   - Live FFT toggle state
%   - Last particle detection results (count, threshold, minArea)
%   - Last alignment shifts

    properties (SetAccess = public)
        liveFFTActive       (1,1) logical = false

        lastParticleCount   (1,1) double  = 0
        lastThreshold       (1,1) double  = NaN
        lastMinArea         (1,1) double  = 10
        lastAlignShifts     (:,2) double  = zeros(0,2)
        numAligned          (1,1) double  = 0
    end

    methods
        function reset(obj)
            obj.liveFFTActive     = false;
            obj.lastParticleCount = 0;
            obj.lastThreshold     = NaN;
            obj.lastMinArea       = 10;
            obj.lastAlignShifts   = zeros(0,2);
            obj.numAligned        = 0;
        end

        function setLiveFFT(obj, tf)
            obj.liveFFTActive = logical(tf);
        end

        function recordParticleResult(obj, count, threshold, minArea)
            obj.lastParticleCount = count;
            obj.lastThreshold     = threshold;
            obj.lastMinArea       = minArea;
        end

        function recordAlignment(obj, shifts)
            obj.lastAlignShifts = shifts;
            obj.numAligned = size(shifts, 1);
        end

        function s = summarize(obj)
            parts = {};
            if obj.liveFFTActive
                parts{end+1} = 'Live FFT on';
            end
            if obj.lastParticleCount > 0
                parts{end+1} = sprintf('%d particles', obj.lastParticleCount);
            end
            if obj.numAligned > 0
                parts{end+1} = sprintf('%d aligned', obj.numAligned);
            end
            if isempty(parts)
                s = 'Processing: idle';
            else
                s = ['Processing: ' strjoin(parts, ', ')];
            end
        end
    end
end
