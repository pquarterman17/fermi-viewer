function profile = widthAveragedProfile(filteredPixels, x1, y1, x2, y2, width)
%WIDTHAVERAGEDPROFILE  Compute intensity profile averaged over parallel lines.
    arguments
        filteredPixels  double
        x1              double
        y1              double
        x2              double
        y2              double
        width           double
    end

    if width <= 1
        [profile.dist, profile.intensity] = imaging.lineProfile(...
            filteredPixels, x1, y1, x2, y2);
        return;
    end

    dx = x2 - x1;
    dy = y2 - y1;
    len = sqrt(dx^2 + dy^2);
    if len < 1
        profile.dist = 0;
        profile.intensity = 0;
        return;
    end
    px = -dy / len;
    py =  dx / len;

    halfW = (width - 1) / 2;
    offsets = linspace(-halfW, halfW, width);

    [d, refI] = imaging.lineProfile(filteredPixels, x1, y1, x2, y2);
    nProfPts = numel(refI);
    allI = NaN(numel(offsets), nProfPts);
    allI(1, :) = refI;
    for oi = 1:numel(offsets)
        off = offsets(oi);
        if off == 0, allI(oi, :) = refI; continue; end
        ox1 = x1 + off * px;
        oy1 = y1 + off * py;
        ox2 = x2 + off * px;
        oy2 = y2 + off * py;
        [~, intensity] = imaging.lineProfile(filteredPixels, ...
            ox1, oy1, ox2, oy2);
        nPts = min(nProfPts, numel(intensity));
        allI(oi, 1:nPts) = intensity(1:nPts);
    end

    profile.dist = d;
    profile.intensity = mean(allI, 1, 'omitnan');
end
