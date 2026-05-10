function r = computeDSpacing(imgSize, pixelSize, pixelUnit, x1, y1, x2, y2)
%COMPUTEDSPACING  Compute d-spacing from two FFT spot positions.
%   r = computeDSpacing(imgSize, pixelSize, pixelUnit, x1, y1, x2, y2)
%   imgSize:   [H, W] of the image
%   pixelSize: calibrated pixel size
%   pixelUnit: unit string (e.g. 'nm')
%   x1,y1,x2,y2: coordinates of two FFT spots
%   Returns r with .values (cell of formatted strings), .spots (struct array),
%   .statusMsg
    arguments
        imgSize   (1,2) double
        pixelSize double
        pixelUnit char
        x1        double
        y1        double
        x2        double
        y2        double
    end

    H = imgSize(1); W = imgSize(2);
    cx = W / 2;
    cy = H / 2;
    N = sqrt(H * W);

    r.values = {};
    r.spots  = struct('x', {}, 'y', {}, 'radius', {}, 'dSpacing', {});

    coords = [x1 y1; x2 y2];
    for si = 1:2
        sx = coords(si, 1);
        sy = coords(si, 2);
        rPx = sqrt((sx - cx)^2 + (sy - cy)^2);
        if rPx < 1, continue; end
        dSpace = N * pixelSize / rPx;
        r.values{end+1} = sprintf('%.3f %s', dSpace, pixelUnit);
        spotR = max(5, min(15, rPx * 0.05));
        r.spots(end+1) = struct('x', sx, 'y', sy, 'radius', spotR, 'dSpacing', dSpace);
    end

    if ~isempty(r.values)
        r.statusMsg = ['d-spacing: ' strjoin(r.values, ', ')];
    else
        r.statusMsg = 'd-spacing: no valid spots';
    end
end
