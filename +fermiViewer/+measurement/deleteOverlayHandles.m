function deleteOverlayHandles(overlays)
%DELETEOVERLAYHANDLES  Delete all graphics handles in an overlays struct.
%   Handles measurement records, loose lines, click markers, distance
%   labels, and text annotations. Does NOT clear the struct fields — the
%   caller should reset them to {} after this call.
    arguments
        overlays struct
    end

    for ci = 1:numel(overlays.measurements)
        m = overlays.measurements{ci};
        deleteIfValid(m, 'hLine');
        deleteIfValid(m, 'hP1');
        deleteIfValid(m, 'hP2');
        deleteIfValid(m, 'hRect');
        deleteIfValid(m, 'hText');
        deleteArrayField(m, 'hLines');
        deleteArrayField(m, 'hMarkers');
    end

    deleteHandleArray(overlays.lines);
    deleteHandleArray(overlays.clickMarkers);
    deleteHandleArray(overlays.distLabels);

    for ci = 1:numel(overlays.textAnnotations)
        emViewer.annotation.deleteAnnotHandles(overlays.textAnnotations{ci});
    end
end

function deleteIfValid(s, fld)
    if isfield(s, fld) && ~isempty(s.(fld)) && isvalid(s.(fld))
        delete(s.(fld));
    end
end

function deleteArrayField(s, fld)
    if isfield(s, fld) && ~isempty(s.(fld))
        for h = s.(fld)(:)'
            if isvalid(h), delete(h); end
        end
    end
end

function deleteHandleArray(arr)
    for ci = 1:numel(arr)
        h = arr{ci};
        if isvalid(h), delete(h); end
    end
end
