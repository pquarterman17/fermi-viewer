function showSurfacePlot(filteredPixels)
%SHOWSURFACEPLOT  Open 3D surface plot of image intensity.
    arguments
        filteredPixels  double
    end

    img = filteredPixels;
    [H, W] = size(img);
    maxDim = 512;
    if H > maxDim || W > maxDim
        scaleFactor = maxDim / max(H, W);
        newH = round(H * scaleFactor);
        newW = round(W * scaleFactor);
        [Xq, Yq] = meshgrid(linspace(1, W, newW), linspace(1, H, newH));
        [Xo, Yo] = meshgrid(1:W, 1:H);
        img = interp2(Xo, Yo, img, Xq, Yq, 'linear');
    end

    figure('Name', 'Surface Plot', 'NumberTitle', 'off');
    surf(img, 'EdgeColor', 'none');
    colormap(parula); colorbar;
    xlabel('X (px)'); ylabel('Y (px)'); zlabel('Intensity');
    title('Image Intensity Surface');
    view(45, 30);
end
