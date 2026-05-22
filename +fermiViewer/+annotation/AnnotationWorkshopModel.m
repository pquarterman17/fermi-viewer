classdef AnnotationWorkshopModel < handle
%ANNOTATIONWORKSHOPMODEL  State container for FermiViewer text annotations.
%
%   Owns the annotation list (data only — no graphics handles), selection
%   state, and default styling. Each annotation record has fields:
%     x, y, str, fontSize, color
%
%   Graphics handles remain in FermiViewer's overlays struct. This model
%   mirrors the data for headless testing and future dialog extraction.

    properties (SetAccess = public)
        annotations     cell    = {}
        selectedIdx     (1,1) double = 0
        defaultColor    (1,3) double = [1 1 1]
        defaultFontSize (1,1) double = 12
    end

    methods
        function n = numAnnotations(obj)
            n = numel(obj.annotations);
        end

        function add(obj, x, y, str, fontSize, color)
            if nargin < 5, fontSize = obj.defaultFontSize; end
            if nargin < 6, color    = obj.defaultColor; end
            rec = struct('x', x, 'y', y, 'str', str, ...
                'fontSize', fontSize, 'color', color);
            obj.annotations{end+1} = rec;
        end

        function remove(obj, idx)
            if idx < 1 || idx > numel(obj.annotations), return; end
            obj.annotations(idx) = [];
            if obj.selectedIdx == idx
                obj.selectedIdx = 0;
            elseif obj.selectedIdx > idx
                obj.selectedIdx = obj.selectedIdx - 1;
            end
        end

        function select(obj, idx)
            if idx >= 0 && idx <= numel(obj.annotations)
                obj.selectedIdx = idx;
            end
        end

        function deselect(obj)
            obj.selectedIdx = 0;
        end

        function clearAll(obj)
            obj.annotations = {};
            obj.selectedIdx = 0;
        end

        function update(obj, idx, field, value)
            if idx < 1 || idx > numel(obj.annotations), return; end
            if isfield(obj.annotations{idx}, field)
                obj.annotations{idx}.(field) = value;
            end
        end

        function a = get(obj, idx)
            if idx >= 1 && idx <= numel(obj.annotations)
                a = obj.annotations{idx};
            else
                a = [];
            end
        end

        function sync(obj, annotCellArr)
        %SYNC  Rebuild model from the live overlays.textAnnotations cell array.
        %   Extracts data fields only (ignores hText handles). Swallows errors.
            try
                if isempty(annotCellArr)
                    obj.annotations = {};
                    obj.selectedIdx = 0;
                    return;
                end
                recs = {};
                for k = 1:numel(annotCellArr)
                    a = annotCellArr{k};
                    if ~isstruct(a), continue; end
                    rec.x = 0; rec.y = 0; rec.str = '';
                    rec.fontSize = 12; rec.color = [1 1 1];
                    if isfield(a, 'x'), rec.x = a.x; end
                    if isfield(a, 'y'), rec.y = a.y; end
                    if isfield(a, 'str'), rec.str = a.str; end
                    if isfield(a, 'fontSize'), rec.fontSize = a.fontSize; end
                    if isfield(a, 'color'), rec.color = a.color; end
                    recs{end+1} = rec; %#ok<AGROW>
                end
                obj.annotations = recs;
                if obj.selectedIdx > numel(recs)
                    obj.selectedIdx = 0;
                end
            catch
            end
        end

        function s = summarize(obj)
            n = obj.numAnnotations();
            if n == 0
                s = 'No annotations';
            else
                s = sprintf('%d annotation(s)', n);
            end
        end
    end
end
