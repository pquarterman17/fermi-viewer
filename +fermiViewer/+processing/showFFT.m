function showFFT(filteredPixels, titleStr)
%SHOWFFT  Compute FFT magnitude and display in a new figure.
    arguments
        filteredPixels  double
        titleStr        char = 'FFT'
    end

    magImg = imaging.computeFFT(filteredPixels);

    fftFig = figure('Name', titleStr, 'NumberTitle', 'off', ...
        'Units', 'pixels', 'Position', [220 180 600 520]);
    fftAx = axes(fftFig);
    imagesc(fftAx, magImg);
    colormap(fftFig, parula(256));
    colorbar(fftAx);
    axis(fftAx, 'image');
    fftAx.XTick = [];
    fftAx.YTick = [];
    title(fftAx, titleStr, 'Interpreter', 'none');
end
