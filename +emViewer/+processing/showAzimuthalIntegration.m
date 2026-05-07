function showAzimuthalIntegration(filteredPixels)
%SHOWAZIMUTHALINTEGRATION  Compute and display azimuthal integration from FFT.
    arguments
        filteredPixels  double
    end

    [mag, ~] = imaging.computeFFT(filteredPixels);
    [radii, intensity] = imaging.azimuthalIntegrate(mag);

    figure('Name', 'Azimuthal Integration', 'NumberTitle', 'off');
    plot(radii, intensity, 'k-', 'LineWidth', 1.2);
    xlabel('Spatial Frequency (px^{-1})'); ylabel('Integrated Intensity');
    title('Azimuthal Integration'); grid on;
end
