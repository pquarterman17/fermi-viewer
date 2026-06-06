function [appData, annot, idx] = placeShape(appData, ax, setStatus, shapeKey, a, b, c, d)
%PLACESHAPE  Draw a shape annotation and append it to the overlay list.
%   Accept-and-return. Returns the annot struct and its overlay index so
%   the CALLER can attach the (closure-built) context menu AFTER the
%   `appData =` assignment; annot is [] when the shape was degenerate.

    annot = [];
    idx   = 0;

    if strcmp(shapeKey, 'circle')
        coords = struct('cx',a,'cy',b,'ex',c,'ey',d);
    else
        coords = struct('x1',a,'y1',b,'x2',c,'y2',d);
    end
    drawn = fermiViewer.annotation.drawShape(ax, shapeKey, coords, appData.annotationColor);
    if strcmp(shapeKey, 'circle') && (isempty(fieldnames(drawn)) || drawn.radius < 1)
        return
    end
    appData.overlays.textAnnotations{end+1} = drawn;
    annot = drawn;
    idx   = numel(appData.overlays.textAnnotations);

    switch shapeKey
        case 'arrow'
            setStatus(sprintf('Arrow placed (%.0f,%.0f) → (%.0f,%.0f)', a, b, c, d));
        case 'line'
            setStatus('Line annotation placed.');
        case 'rectangle'
            setStatus('Rectangle annotation placed.');
        case 'circle'
            setStatus(sprintf('Circle annotation placed (r=%.0f px).', drawn.radius));
    end
end
