function showRadialProfile(filteredPixels)
%SHOWRADIALPROFILE  Compute and display radial profile from FFT.
    arguments
        filteredPixels  double
    end

    [mag, ~] = imaging.computeFFT(filteredPixels);
    [radii, avgProf, maxProf] = imaging.radialProfile(mag);

    figure('Name', 'Radial Profile', 'NumberTitle', 'off');
    subplot(1, 2, 1);
    plot(radii, avgProf, 'b-', 'LineWidth', 1.2);
    xlabel('Spatial Frequency (px^{-1})'); ylabel('Mean Intensity');
    title('Radial Average'); grid on;

    subplot(1, 2, 2);
    plot(radii, maxProf, 'r-', 'LineWidth', 1.2);
    xlabel('Spatial Frequency (px^{-1})'); ylabel('Max Intensity');
    title('Radial Maximum'); grid on;
end
