function rebindCallbacks(measurements, cb)
%REBINDCALLBACKS  Re-attach drag + selection callbacks after a deletion.
%
%   fermiViewer.measurement.rebindCallbacks(measurements, cb)
%
%   After a measurement is removed from the overlays cell array, every
%   remaining measurement's index shifts. The drag/selection callbacks
%   capture the (now stale) index by value, so they must be rebound to
%   the new index. This helper performs that rebind for all measurement
%   types, including the interactive box profile.
%
%   Inputs:
%       measurements — cell array of measurement structs (post-deletion)
%       cb           — struct of callback function handles:
%           .startEndpointDrag(measIdx, whichEnd)
%           .selectMeasurement(measIdx)
%
%   whichEnd convention (shared with startEndpointDrag):
%       1,2 = endpoints; 3 = body move; 4,5 = box width side handles.

    for mi = 1:numel(measurements)
        m = measurements{mi};

        if isfield(m, 'hP1') && ~isempty(m.hP1) && isvalid(m.hP1)
            m.hP1.ButtonDownFcn = @(~,~) cb.startEndpointDrag(mi, 1);
        end
        if isfield(m, 'hP2') && ~isempty(m.hP2) && isvalid(m.hP2)
            m.hP2.ButtonDownFcn = @(~,~) cb.startEndpointDrag(mi, 2);
        end
        if isfield(m, 'hLine') && ~isempty(m.hLine) && isvalid(m.hLine)
            m.hLine.ButtonDownFcn = @(~,~) cb.selectMeasurement(mi);
        end

        if isfield(m, 'type') && strcmp(m.type, 'polyline') && isfield(m, 'hLines')
            for hh = m.hLines(:)'
                if isvalid(hh), hh.ButtonDownFcn = @(~,~) cb.selectMeasurement(mi); end
            end
        end

        if isfield(m, 'type') && strcmp(m.type, 'boxprofile')
            if isfield(m, 'hPatch') && isvalid(m.hPatch)
                m.hPatch.ButtonDownFcn = @(~,~) cb.startEndpointDrag(mi, 3);
            end
            if isfield(m, 'hW1') && ~isempty(m.hW1) && isvalid(m.hW1)
                m.hW1.ButtonDownFcn = @(~,~) cb.startEndpointDrag(mi, 4);
            end
            if isfield(m, 'hW2') && ~isempty(m.hW2) && isvalid(m.hW2)
                m.hW2.ButtonDownFcn = @(~,~) cb.startEndpointDrag(mi, 5);
            end
        end
    end
end
