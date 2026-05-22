function result = displayColorOverlay(imgA, imgB, cmapA, cmapB, alpha, nameA, nameB)
%DISPLAYCOLOROVERLAY  Blend two grayscale images with pseudo-color channels.
    arguments
        imgA    double
        imgB    double
        cmapA   char
        cmapB   char
        alpha   double
        nameA   char = ''
        nameB   char = ''
    end

    imgA = (imgA - min(imgA(:))) / max(1, max(imgA(:)) - min(imgA(:)));
    imgB = (imgB - min(imgB(:))) / max(1, max(imgB(:)) - min(imgB(:)));

    [Ha, Wa] = size(imgA);
    [Hb, Wb] = size(imgB);
    H2 = min(Ha, Hb); W2 = min(Wa, Wb);
    imgA = imgA(1:H2, 1:W2);
    imgB = imgB(1:H2, 1:W2);

    rgbA = emViewer.applyColorChannel(imgA, cmapA);
    rgbB = emViewer.applyColorChannel(imgB, cmapB);

    blended = max(0, min(1, rgbA * (1 - alpha) + rgbB * alpha));

    ovFig = figure('Name', 'Color Overlay', 'NumberTitle', 'off', ...
        'Units', 'pixels', 'Position', [250 180 650 550]);
    ovAx = axes(ovFig);
    image(ovAx, blended);
    axis(ovAx, 'image'); ovAx.XTick = []; ovAx.YTick = [];
    title(ovAx, sprintf('%s (%s) + %s (%s), alpha=%.1f', ...
        nameA, cmapA, nameB, cmapB, alpha), 'Interpreter', 'none');

    result.fig = ovFig;
    result.blended = blended;
    result.statusMsg = 'Color overlay displayed.';
end
