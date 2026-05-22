function annot = drawShape(targetAx, shapeType, coords, color)
%DRAWSHAPE  Draw an annotation shape on an axes and return the record.
%   annot = drawShape(ax, 'arrow', struct(x1,y1,x2,y2), [1 0 0])
%   annot = drawShape(ax, 'line',  struct(x1,y1,x2,y2), [0 1 1])
%   annot = drawShape(ax, 'rectangle', struct(x1,y1,x2,y2), [1 1 0])
%   annot = drawShape(ax, 'circle', struct(cx,cy,ex,ey), [0 1 0])
    arguments
        targetAx  matlab.graphics.axis.Axes
        shapeType char
        coords    struct
        color     (1,3) double
    end

    hold(targetAx, 'on');

    switch shapeType
        case 'arrow'
            annot = drawArrow(targetAx, coords, color);
        case 'line'
            annot = drawLine(targetAx, coords, color);
        case 'rectangle'
            annot = drawRect(targetAx, coords, color);
        case 'circle'
            annot = drawCircle(targetAx, coords, color);
        otherwise
            hold(targetAx, 'off');
            error('emViewer:annotation:unknownShape', ...
                'Unknown shape type: %s', shapeType);
    end

    hold(targetAx, 'off');
end

function annot = drawArrow(targetAx, c, color)
    hLine = plot(targetAx, [c.x1 c.x2], [c.y1 c.y2], '-', ...
        'Color', color, 'LineWidth', 2, ...
        'HandleVisibility', 'off', 'HitTest', 'off');

    dx = c.x2 - c.x1;
    dy = c.y2 - c.y1;
    len = sqrt(dx^2 + dy^2);
    if len < 1
        annot = struct('type', 'arrow', 'hLine', hLine, 'hHead', gobjects(0), ...
            'x1', c.x1, 'y1', c.y1, 'x2', c.x2, 'y2', c.y2, 'color', color);
        return;
    end
    ux = dx / len;
    uy = dy / len;
    headLen = min(15, len * 0.2);
    headW   = headLen * 0.5;

    tipX   = c.x2;
    tipY   = c.y2;
    leftX  = c.x2 - headLen * ux + headW * uy;
    leftY  = c.y2 - headLen * uy - headW * ux;
    rightX = c.x2 - headLen * ux - headW * uy;
    rightY = c.y2 - headLen * uy + headW * ux;

    hHead = patch(targetAx, [tipX leftX rightX], [tipY leftY rightY], color, ...
        'EdgeColor', color, 'FaceColor', color, ...
        'HandleVisibility', 'off', 'HitTest', 'off');

    annot = struct('type', 'arrow', 'hLine', hLine, 'hHead', hHead, ...
        'x1', c.x1, 'y1', c.y1, 'x2', c.x2, 'y2', c.y2, 'color', color);
end

function annot = drawLine(targetAx, c, color)
    hL = plot(targetAx, [c.x1 c.x2], [c.y1 c.y2], '-', 'Color', color, ...
        'LineWidth', 2, 'HandleVisibility', 'off', 'HitTest', 'off');
    annot = struct('type', 'line', 'hLine', hL, ...
        'x1', c.x1, 'y1', c.y1, 'x2', c.x2, 'y2', c.y2, 'color', color);
end

function annot = drawRect(targetAx, c, color)
    xMin = min(c.x1, c.x2);
    yMin = min(c.y1, c.y2);
    w = abs(c.x2 - c.x1);
    h = abs(c.y2 - c.y1);
    hR = rectangle(targetAx, 'Position', [xMin yMin w h], ...
        'EdgeColor', color, 'LineWidth', 2, ...
        'FaceColor', 'none', 'HitTest', 'off');
    annot = struct('type', 'rectangle', 'hRect', hR, ...
        'x1', c.x1, 'y1', c.y1, 'x2', c.x2, 'y2', c.y2, 'color', color);
end

function annot = drawCircle(targetAx, c, color)
    r = sqrt((c.ex - c.cx)^2 + (c.ey - c.cy)^2);
    if r < 1
        annot = struct('type', 'circle', 'hCircle', gobjects(0), ...
            'cx', c.cx, 'cy', c.cy, 'radius', r, 'color', color);
        return;
    end
    th = linspace(0, 2*pi, 120);
    hC = plot(targetAx, c.cx + r*cos(th), c.cy + r*sin(th), '-', ...
        'Color', color, 'LineWidth', 2, ...
        'HandleVisibility', 'off', 'HitTest', 'off');
    annot = struct('type', 'circle', 'hCircle', hC, ...
        'cx', c.cx, 'cy', c.cy, 'radius', r, 'color', color);
end
