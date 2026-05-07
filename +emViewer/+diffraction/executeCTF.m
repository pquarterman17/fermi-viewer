function result = executeCTF(filteredPixels, kV, Cs_mm, pixelSize_A)
%EXECUTECTF  Estimate CTF from power spectrum and display results.
    arguments
        filteredPixels  double
        kV              double
        Cs_mm           double
        pixelSize_A     double
    end

    res = imaging.estimateCTF(filteredPixels, ...
        Voltage_kV=kV, Cs_mm=Cs_mm, PixelSize=pixelSize_A);

    ctfFig = figure('Name', 'CTF Estimation', 'NumberTitle', 'off');
    plot(res.radialProfile(:,1), log10(res.radialProfile(:,2) + 1), 'b');
    hold on;
    plot(res.radialProfile(:,1), res.ctfFit, 'r--', 'LineWidth', 1.5);
    xlabel('Spatial frequency (1/\AA)'); ylabel('log10(Power + 1)');
    title(sprintf('CTF Fit: Defocus = %.0f nm (R^2 = %.3f)', ...
        res.defocus_nm, res.rSquared));
    legend('Power spectrum', 'CTF^2 fit');

    result.ctfResult = res;
    result.ctfFig = ctfFig;
    result.statusMsg = sprintf('CTF: defocus = %.0f nm', res.defocus_nm);
end
