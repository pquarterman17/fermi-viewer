function onAnnotationAction(action, appData, ui, cb, varargin)
%ONANNOTATIONACTION  Annotation dispatcher for FermiViewer.
%
% Syntax:
%   emViewer.onAnnotationAction(action, appData, ui, cb)
%   emViewer.onAnnotationAction(action, appData, ui, cb, arg1, ...)
%
% Inputs:
%   action   — string action key; see switch cases below
%   appData  — FermiViewer appData struct snapshot (value copy at call time);
%              mutations are committed back via cb.setAppData()
%   ui       — struct with fields:
%                .ax          uiaxes handle
%                .fig         uifigure handle
%                .efAnnotText uieditfield for annotation text
%                .spnAnnotFont uispinner for font size
%   cb       — struct with function-handle callbacks into the closure:
%                .setAppData(newAD)           — write modified appData back
%                .setStatus(msg)
%                .cancelCapture()             — aborts active capture
%                .placeAnnotationAt(x,y,...)  — creates annotation in closure
%                .finishCapture()             — clears capture state in closure
%                .deleteAnnotHandles(a)       — removes graphics handles
%                .highlightAnnotation(a, tf)  — toggles selection highlight
%                .deselectMeasurement()       — clears measurement selection
%                .dispatchSelf(action, ...)   — handle to wrapper onAnnotationAction
%   varargin — extra arguments forwarded from the wrapper (e.g. idx, color)
%
% Design notes:
%   appData is a value-type struct. Mutations are committed back to the
%   closure via cb.setAppData() rather than a return value.
%
%   For callbacks that both read appData fields (for visuals) AND write
%   appData fields (cancelCapture, deselectMeasurement), this function
%   pre-clears the fields the callback will write — before calling the
%   callback — so the subsequent cb.setAppData() carries the correct values
%   without needing to re-read the closure's appData after the callback runs.
%
%   For callbacks that only write appData and do not need our local snapshot
%   (placeAnnotationAt, finishCapture), those are called directly from the
%   closure wrapper (not here) after cb.setAppData() has already committed.
%
% Examples:
%   emViewer.onAnnotationAction('place', appData, ui, cb);
%   emViewer.onAnnotationAction('select', appData, ui, cb, 2);

% ════════════════════════════════════════════════════════════════════
switch action

    case 'place'
        if appData.activeIdx < 1 || isempty(appData.displayImg), return; end
        if appData.compareMode, return; end
        if ~isempty(appData.captureMode)
            % Pre-clear the fields cancelCapture will set, so setAppData
            % below carries the correct values without re-reading the closure.
            appData.overlays.clickMarkers = {};
            appData.captureMode           = '';
            appData.captureClicks         = [];
            cb.cancelCapture();   % handles graphics deletes + fig property resets
        end
        appData.captureMode   = 'annotation';
        appData.captureClicks = [];
        cb.setAppData(appData);
        ui.fig.Pointer = 'crosshair';
        ui.fig.WindowButtonDownFcn = @(~,~) cb.dispatchSelf('click');
        cb.setStatus('Click on image to place text annotation... (Esc to cancel)');

    case 'click'
        if ~strcmp(appData.captureMode, 'annotation'), return; end
        cp = ui.ax.CurrentPoint;
        x  = cp(1, 1);
        y  = cp(1, 2);
        if isempty(appData.displayImg), return; end
        [H, W] = size(appData.filteredPixels);
        if x < 0.5 || x > W + 0.5 || y < 0.5 || y > H + 0.5, return; end
        annotStr   = ui.efAnnotText.Value;
        annotSize  = ui.spnAnnotFont.Value;
        annotColor = appData.annotationColor;
        if isempty(strtrim(annotStr))
            cb.setStatus('Annotation text is empty — enter text first.');
            return;
        end
        cb.placeAnnotationAt(x, y, annotStr, annotSize, annotColor);
        cb.finishCapture();
        cb.setStatus(sprintf('Annotation placed at (%.0f, %.0f).', x, y));

    case 'clear'
        appData.selectedAnnotIdx     = 0;
        appData.selectedAnnotIndices = [];
        for ci = 1:numel(appData.overlays.textAnnotations)
            cb.deleteAnnotHandles(appData.overlays.textAnnotations{ci});
        end
        appData.overlays.textAnnotations = {};
        cb.setAppData(appData);
        appData.annotWorkshop.clearAll();
        cb.setStatus('All annotations cleared.');

    case 'undoLast'
        if isempty(appData.overlays.textAnnotations), return; end
        if appData.selectedAnnotIdx == numel(appData.overlays.textAnnotations)
            appData.selectedAnnotIdx = 0;
        end
        cb.deleteAnnotHandles(appData.overlays.textAnnotations{end});
        appData.overlays.textAnnotations(end) = [];
        cb.setAppData(appData);
        appData.annotWorkshop.sync(appData.overlays.textAnnotations);
        cb.setStatus('Last annotation removed.');

    case 'select'
        idx = varargin{1};
        if idx < 1 || idx > numel(appData.overlays.textAnnotations), return; end
        appData = localDeselect(appData, cb);
        % Clicking a single annotation also drops any existing
        % measurement marquee so the visible selection is coherent.
        if ~isempty(appData.selectedMeasIndices) || appData.selectedMeasIdx > 0
            % deselectMeasurement reads selectedMeasIndices for visuals then
            % clears them. Pre-clear in our copy so setAppData below is correct.
            appData.selectedMeasIdx     = 0;
            appData.selectedMeasIndices = [];
            cb.deselectMeasurement();   % visual-only: restores highlight colors
        end
        appData.selectedAnnotIdx     = idx;
        appData.selectedAnnotIndices = idx;
        a = appData.overlays.textAnnotations{idx};
        cb.highlightAnnotation(a, true);
        cb.setAppData(appData);
        cb.setStatus(sprintf('Annotation %d selected.', idx));

    case 'deselect'
        appData = localDeselect(appData, cb);
        cb.setAppData(appData);

    case 'deleteOne'
        idx = varargin{1};
        if idx < 1 || idx > numel(appData.overlays.textAnnotations), return; end
        cb.deleteAnnotHandles(appData.overlays.textAnnotations{idx});
        appData.overlays.textAnnotations(idx) = [];
        if appData.selectedAnnotIdx == idx
            appData.selectedAnnotIdx = 0;
        elseif appData.selectedAnnotIdx > idx
            appData.selectedAnnotIdx = appData.selectedAnnotIdx - 1;
        end
        % Maintain selectedAnnotIndices under the shift: remove
        % the deleted index, decrement any larger ones.
        if ~isempty(appData.selectedAnnotIndices)
            keep = appData.selectedAnnotIndices ~= idx;
            appData.selectedAnnotIndices = appData.selectedAnnotIndices(keep);
            shift = appData.selectedAnnotIndices > idx;
            appData.selectedAnnotIndices(shift) = ...
                appData.selectedAnnotIndices(shift) - 1;
        end
        cb.setAppData(appData);
        appData.annotWorkshop.sync(appData.overlays.textAnnotations);
        cb.setStatus(sprintf('Annotation %d deleted.', idx));

    case 'setColor'
        idx = varargin{1};
        newColor = varargin{2};
        if idx < 1 || idx > numel(appData.overlays.textAnnotations), return; end
        a = appData.overlays.textAnnotations{idx};
        a.color = newColor;
        for fk = {'hText','hLine','hCircle'}
            fn = fk{1};
            if isfield(a, fn) && ~isempty(a.(fn)) && isvalid(a.(fn))
                a.(fn).Color = newColor;
            end
        end
        if isfield(a, 'hHead') && ~isempty(a.hHead) && isvalid(a.hHead)
            a.hHead.FaceColor = newColor;
            a.hHead.EdgeColor = newColor;
        end
        if isfield(a, 'hRect') && ~isempty(a.hRect) && isvalid(a.hRect)
            a.hRect.EdgeColor = newColor;
        end
        appData.overlays.textAnnotations{idx} = a;
        cb.setAppData(appData);

    case 'setFontSize'
        idx = varargin{1};
        if idx < 1 || idx > numel(appData.overlays.textAnnotations), return; end
        a = appData.overlays.textAnnotations{idx};
        if ~isfield(a, 'hText') || isempty(a.hText) || ~isvalid(a.hText)
            cb.setStatus('Font size only applies to text annotations.'); return;
        end
        answer = inputdlg('Font size:', 'Annotation Font', 1, {num2str(a.fontSize)});
        if isempty(answer), return; end
        newSz = round(str2double(answer{1}));
        if isnan(newSz) || newSz < 4 || newSz > 120, return; end
        a.hText.FontSize = newSz;
        a.fontSize = newSz;
        appData.overlays.textAnnotations{idx} = a;
        cb.setAppData(appData);

    case 'editText'
        idx = varargin{1};
        if idx < 1 || idx > numel(appData.overlays.textAnnotations), return; end
        a = appData.overlays.textAnnotations{idx};
        if ~isfield(a, 'hText') || isempty(a.hText) || ~isvalid(a.hText)
            cb.setStatus('Only text annotations have editable text.'); return;
        end
        answer = inputdlg('Annotation text:', 'Edit Annotation', 1, {a.str});
        if isempty(answer), return; end
        a.hText.String = answer{1};
        a.str = answer{1};
        appData.overlays.textAnnotations{idx} = a;
        cb.setAppData(appData);

    case 'startDrag'
        idx = varargin{1};
        if strcmp(ui.fig.SelectionType, 'alt'), return; end
        if idx < 1 || idx > numel(appData.overlays.textAnnotations), return; end
        % Inline 'select' logic to avoid recursive dispatch.
        appData = localDeselect(appData, cb);
        if ~isempty(appData.selectedMeasIndices) || appData.selectedMeasIdx > 0
            % Pre-clear so setAppData below carries correct values.
            appData.selectedMeasIdx     = 0;
            appData.selectedMeasIndices = [];
            cb.deselectMeasurement();   % visual-only: restores highlight colors
        end
        appData.selectedAnnotIdx     = idx;
        appData.selectedAnnotIndices = idx;
        cb.highlightAnnotation(appData.overlays.textAnnotations{idx}, true);
        cb.setStatus(sprintf('Annotation %d selected.', idx));
        cp = ui.ax.CurrentPoint;
        appData.dragAnnotIdx   = idx;
        appData.dragLastPt     = [cp(1,1), cp(1,2)];
        appData.savedMotionFcn = ui.fig.WindowButtonMotionFcn;
        appData.savedUpFcn     = ui.fig.WindowButtonUpFcn;
        cb.setAppData(appData);
        ui.fig.WindowButtonMotionFcn = @(~,~) cb.dispatchSelf('drag');
        ui.fig.WindowButtonUpFcn     = @(~,~) cb.dispatchSelf('endDrag');

    case 'drag'
        if appData.dragAnnotIdx < 1, return; end
        cp = ui.ax.CurrentPoint;
        dx = cp(1,1) - appData.dragLastPt(1);
        dy = cp(1,2) - appData.dragLastPt(2);
        appData.dragLastPt = [cp(1,1), cp(1,2)];
        idx = appData.dragAnnotIdx;
        a = appData.overlays.textAnnotations{idx};
        if isfield(a, 'hText') && ~isempty(a.hText) && isvalid(a.hText)
            pos = a.hText.Position;
            a.hText.Position = [pos(1)+dx, pos(2)+dy, 0];
            a.x = a.x + dx; a.y = a.y + dy;
        end
        if isfield(a, 'hLine') && ~isempty(a.hLine) && isvalid(a.hLine)
            a.hLine.XData = a.hLine.XData + dx;
            a.hLine.YData = a.hLine.YData + dy;
        end
        if isfield(a, 'hHead') && ~isempty(a.hHead) && isvalid(a.hHead)
            a.hHead.Vertices(:,1) = a.hHead.Vertices(:,1) + dx;
            a.hHead.Vertices(:,2) = a.hHead.Vertices(:,2) + dy;
        end
        if isfield(a, 'hRect') && ~isempty(a.hRect) && isvalid(a.hRect)
            p = a.hRect.Position;
            a.hRect.Position = [p(1)+dx, p(2)+dy, p(3), p(4)];
        end
        if isfield(a, 'hCircle') && ~isempty(a.hCircle) && isvalid(a.hCircle)
            a.hCircle.XData = a.hCircle.XData + dx;
            a.hCircle.YData = a.hCircle.YData + dy;
        end
        for fld = {'x1','y1','x2','y2','cx','cy'}
            f = fld{1};
            if isfield(a, f)
                if contains(f, 'x') || strcmp(f, 'cx')
                    a.(f) = a.(f) + dx;
                else
                    a.(f) = a.(f) + dy;
                end
            end
        end
        appData.overlays.textAnnotations{idx} = a;
        cb.setAppData(appData);

    case 'endDrag'
        ui.fig.WindowButtonMotionFcn = appData.savedMotionFcn;
        ui.fig.WindowButtonUpFcn     = appData.savedUpFcn;
        if appData.dragAnnotIdx > 0
            cb.setStatus(sprintf('Annotation %d repositioned.', appData.dragAnnotIdx));
        end
        appData.dragAnnotIdx = 0;
        cb.setAppData(appData);
end % switch

end % onAnnotationAction

% ════════════════════════════════════════════════════════════════════

function appData = localDeselect(appData, cb)
%LOCALDESELECT  Clear the current annotation selection (visual + state).
    if appData.selectedAnnotIdx > 0 && ...
       appData.selectedAnnotIdx <= numel(appData.overlays.textAnnotations)
        a = appData.overlays.textAnnotations{appData.selectedAnnotIdx};
        cb.highlightAnnotation(a, false);
    end
    for dai = appData.selectedAnnotIndices(:)'
        if dai >= 1 && dai <= numel(appData.overlays.textAnnotations)
            cb.highlightAnnotation( ...
                appData.overlays.textAnnotations{dai}, false);
        end
    end
    appData.selectedAnnotIdx     = 0;
    appData.selectedAnnotIndices = [];
end
