function [measurements, selectedIdx, selectedIndices] = selection(action, measurements, varargin)
%SELECTION  Measurement highlight, deselect, and delete helpers.
%
% Syntax:
%   emViewer.meas.selection('highlight', measurements, idx)
%   [m,si,sis] = emViewer.meas.selection('deselect',  measurements, selectedIdx, selectedIndices, overlayColor)
%   [m,si,sis] = emViewer.meas.selection('delete',    measurements, idx, overlayColor, rebindFn)
%
% All mutating functions return the updated measurements cell array plus
% the new selectedIdx (scalar) and selectedIndices (row vector) values.
%
% Inputs:
%   measurements      — cell array of measurement structs
%   idx               — scalar measurement index (1-based)
%   selectedIdx       — current appData.selectedMeasIdx
%   selectedIndices   — current appData.selectedMeasIndices
%   overlayColor      — [1x3] default overlay RGB (OVERLAY_COLOR)
%   rebindFn          — @(mi, m) rebind drag callbacks after deletion
%
% Examples:
%   emViewer.meas.selection('highlight', meas, 3);
%   [meas, si, sis] = emViewer.meas.selection('deselect', meas, 2, [2 4], [0 1 1]);

% ════════════════════════════════════════════════════════════════════
selectedIdx     = 0;
selectedIndices = [];

switch lower(action)
    case 'highlight'
        idx = varargin{1};
        applyMeasHighlight(measurements, idx);

    case 'deselect'
        [selIdx, selInd, overlayColor] = varargin{:};
        [measurements, selectedIdx, selectedIndices] = ...
            doDeselect(measurements, selIdx, selInd, overlayColor);

    case 'delete'
        [idx, overlayColor, rebindFn] = varargin{:};
        [measurements, selectedIdx, selectedIndices] = ...
            doDelete(measurements, idx, overlayColor, rebindFn);

    otherwise
        error('emViewer:meas:selection:unknownAction', ...
            'Unknown action "%s". Valid: highlight, deselect, delete', action);
end

% ════════════════════════════════════════════════════════════════════
function applyMeasHighlight(measurements, idx)
    if idx < 1 || idx > numel(measurements), return; end
    meas = measurements{idx};
    hlClr = [1 1 0];

    if isfield(meas, 'type') && strcmp(meas.type, 'rectROI') ...
            && isfield(meas, 'hRect') && isvalid(meas.hRect)
        meas.hRect.LineWidth = 3;
        meas.hRect.EdgeColor = hlClr;
        return;
    end

    if isfield(meas, 'type') && strcmp(meas.type, 'polyline')
        if isfield(meas, 'hLines')
            for h = meas.hLines(:)'
                if isvalid(h), h.LineWidth = 3; h.Color = hlClr; end
            end
        end
        if isfield(meas, 'hMarkers')
            for h = meas.hMarkers(:)'
                if isvalid(h)
                    h.Color = hlClr;
                    h.MarkerEdgeColor = hlClr;
                    h.MarkerFaceColor = hlClr;
                end
            end
        end
        return;
    end

    if ~isfield(meas, 'hLine') || ~isvalid(meas.hLine), return; end
    meas.hLine.LineWidth = 3;
    meas.hLine.Color = hlClr;
    if isfield(meas, 'hP1') && ~isempty(meas.hP1) && isvalid(meas.hP1)
        meas.hP1.Color           = hlClr;
        meas.hP1.MarkerEdgeColor = hlClr;
    end
    if isfield(meas, 'hP2') && ~isempty(meas.hP2) && isvalid(meas.hP2)
        meas.hP2.Color           = hlClr;
        meas.hP2.MarkerEdgeColor = hlClr;
    end

% ════════════════════════════════════════════════════════════════════
function [measurements, selectedIdx, selectedIndices] = ...
        doDeselect(measurements, selIdx, selInd, overlayColor)
    ids = selInd;
    if isempty(ids) && selIdx > 0
        ids = selIdx;
    end
    for idx = ids(:)'
        if idx < 1 || idx > numel(measurements), continue; end
        meas = measurements{idx};
        restoreClr = overlayColor;
        if isfield(meas, 'lineColor'), restoreClr = meas.lineColor; end

        if isfield(meas, 'type') && strcmp(meas.type, 'rectROI') ...
                && isfield(meas, 'hRect') && isvalid(meas.hRect)
            meas.hRect.LineWidth = 1.5;
            meas.hRect.EdgeColor = restoreClr;
            continue;
        end

        if isfield(meas, 'type') && strcmp(meas.type, 'polyline')
            if isfield(meas, 'hLines')
                for h = meas.hLines(:)'
                    if isvalid(h), h.LineWidth = 1.5; h.Color = restoreClr; end
                end
            end
            if isfield(meas, 'hMarkers')
                for h = meas.hMarkers(:)'
                    if isvalid(h)
                        h.Color = restoreClr;
                        h.MarkerEdgeColor = restoreClr;
                        h.MarkerFaceColor = restoreClr;
                    end
                end
            end
            continue;
        end

        if isfield(meas, 'hLine') && isvalid(meas.hLine)
            meas.hLine.LineWidth = 1.5;
            meas.hLine.Color = restoreClr;
        end
        if isfield(meas, 'hP1') && ~isempty(meas.hP1) && isvalid(meas.hP1)
            meas.hP1.Color           = restoreClr;
            meas.hP1.MarkerEdgeColor = restoreClr;
            meas.hP1.MarkerFaceColor = 'none';
        end
        if isfield(meas, 'hP2') && ~isempty(meas.hP2) && isvalid(meas.hP2)
            meas.hP2.Color           = restoreClr;
            meas.hP2.MarkerEdgeColor = restoreClr;
            meas.hP2.MarkerFaceColor = 'none';
        end
    end
    selectedIdx     = 0;
    selectedIndices = [];

% ════════════════════════════════════════════════════════════════════
function [measurements, selectedIdx, selectedIndices] = ...
        doDelete(measurements, idx, overlayColor, rebindFn)
    selectedIdx     = 0;
    selectedIndices = [];

    if idx < 1 || idx > numel(measurements), return; end

    meas = measurements{idx};

    if isfield(meas, 'type') && strcmp(meas.type, 'rectROI')
        if isfield(meas, 'hRect') && isvalid(meas.hRect), delete(meas.hRect); end
    elseif isfield(meas, 'type') && strcmp(meas.type, 'polyline')
        if isfield(meas, 'hLines')
            for h = meas.hLines(:)'
                if isvalid(h), delete(h); end
            end
        end
        if isfield(meas, 'hMarkers')
            for h = meas.hMarkers(:)'
                if isvalid(h), delete(h); end
            end
        end
        if isfield(meas, 'hText') && ~isempty(meas.hText) && isvalid(meas.hText)
            delete(meas.hText);
        end
    else
        if isfield(meas, 'hLine')  && isvalid(meas.hLine),                 delete(meas.hLine);  end
        if isfield(meas, 'hP1')    && ~isempty(meas.hP1)   && isvalid(meas.hP1),   delete(meas.hP1);   end
        if isfield(meas, 'hP2')    && ~isempty(meas.hP2)   && isvalid(meas.hP2),   delete(meas.hP2);   end
        if isfield(meas, 'hText')  && ~isempty(meas.hText) && isvalid(meas.hText), delete(meas.hText); end
    end

    measurements(idx) = [];

    % Re-bind drag + selection callbacks via caller-supplied function
    if ~isempty(rebindFn)
        for mi = 1:numel(measurements)
            m = measurements{mi};
            rebindFn(mi, m);
        end
    end
