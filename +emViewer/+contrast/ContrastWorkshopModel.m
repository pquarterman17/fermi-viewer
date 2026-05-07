classdef ContrastWorkshopModel < handle
%CONTRASTWORKSHOPMODEL  State container for FermiViewer contrast/histogram.
%
%   Owns the display pipeline parameters: contrast limits (lo/hi),
%   transform mode, gamma, invert flag, and histogram preferences.
%   The actual pixel transformation lives in FermiViewer's
%   applyContrastPipeline — this model owns the parameters, not
%   the computation.
%
%   Transform modes: 'linear' | 'log' | 'sqrt' | 'power'

    properties (SetAccess = public)
        lo              (1,1) double  = 0
        hi              (1,1) double  = 1
        transform       (1,:) char    = 'linear'
        gamma           (1,1) double  = 1.0
        invert          (1,1) logical = false
        histLogScale    (1,1) logical = false
        autoContrast    (1,1) logical = true
    end

    properties (Dependent)
        range
    end

    methods
        function r = get.range(obj)
            r = obj.hi - obj.lo;
        end

        function setLimits(obj, newLo, newHi)
            if newLo >= newHi, return; end
            obj.lo = newLo;
            obj.hi = newHi;
            obj.autoContrast = false;
        end

        function setTransform(obj, mode)
            valid = {'linear', 'log', 'sqrt', 'power'};
            if any(strcmp(mode, valid))
                obj.transform = mode;
            end
        end

        function setGamma(obj, g)
            if g > 0 && g <= 10
                obj.gamma = g;
            end
        end

        function setInvert(obj, tf)
            obj.invert = logical(tf);
        end

        function reset(obj)
            obj.lo           = 0;
            obj.hi           = 1;
            obj.transform    = 'linear';
            obj.gamma        = 1.0;
            obj.invert       = false;
            obj.autoContrast = true;
        end

        function autoFromPixels(obj, pixels)
        %AUTOFROMPIXELS  Compute percentile-based auto contrast.
            if isempty(pixels), return; end
            vals = double(pixels(:));
            vals = vals(isfinite(vals));
            if isempty(vals), return; end
            sorted = sort(vals);
            n = numel(sorted);
            obj.lo = sorted(max(1, round(0.01 * n)));
            obj.hi = sorted(min(n, round(0.99 * n)));
            if obj.lo >= obj.hi
                obj.lo = sorted(1);
                obj.hi = sorted(end);
            end
            obj.autoContrast = true;
        end

        function sync(obj, params)
        %SYNC  Re-sync from a struct of parameters. Error-swallowing.
            try
                if isfield(params, 'lo'),        obj.lo = params.lo; end
                if isfield(params, 'hi'),        obj.hi = params.hi; end
                if isfield(params, 'transform'), obj.setTransform(params.transform); end
                if isfield(params, 'gamma'),     obj.gamma = params.gamma; end
                if isfield(params, 'invert'),    obj.invert = logical(params.invert); end
                if isfield(params, 'histLogScale'), obj.histLogScale = logical(params.histLogScale); end
            catch
            end
        end

        function s = toStruct(obj)
        %TOSTRUCT  Export state as a plain struct (for session save).
            s.lo           = obj.lo;
            s.hi           = obj.hi;
            s.transform    = obj.transform;
            s.gamma        = obj.gamma;
            s.invert       = obj.invert;
            s.histLogScale = obj.histLogScale;
        end
    end
end
