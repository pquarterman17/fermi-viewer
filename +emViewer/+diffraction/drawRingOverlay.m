function nDrawn = drawRingOverlay(ax, dSpacings, camLength, wavelength, imgSize, pixelSize)
%DRAWRINGOVERLAY  Overlay diffraction ring circles on axes.
    arguments
        ax
        dSpacings   double
        camLength   double
        wavelength  double
        imgSize     (1,2) double
        pixelSize   double = 1
    end

    H = imgSize(1); W = imgSize(2);
    cx = W / 2; cy = H / 2;
    colors = lines(numel(dSpacings));
    nDrawn = 0;

    hold(ax, 'on');
    for di = 1:numel(dSpacings)
        sinTheta = wavelength / (2 * dSpacings(di));
        if sinTheta > 1, continue; end
        radius = camLength * tan(2 * asin(sinTheta)) / pixelSize;
        th = linspace(0, 2*pi, 120);
        plot(ax, cx + radius*cos(th), cy + radius*sin(th), '-', ...
            'Color', colors(di,:), 'LineWidth', 1.2, ...
            'Tag', 'diff_ring', ...
            'HandleVisibility', 'off', 'HitTest', 'off');
        text(ax, cx + radius*0.72, cy - radius*0.72, ...
            sprintf('%.3f A', dSpacings(di)), 'Color', colors(di,:), ...
            'FontSize', 8, 'Tag', 'diff_ring', ...
            'HandleVisibility', 'off', 'HitTest', 'off');
        nDrawn = nDrawn + 1;
    end
    hold(ax, 'off');
end
