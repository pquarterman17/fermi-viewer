function result = executeGPA(filteredPixels, captureClicks, pixelSize)
%EXECUTEGPA  Geometric Phase Analysis from two Bragg spot selections.
    arguments
        filteredPixels  double
        captureClicks   double
        pixelSize       double = 1
    end

    [H, W] = size(filteredPixels);
    center = [H/2, W/2];
    g1 = [captureClicks(1,1) - center(2), captureClicks(1,2) - center(1)];
    g2 = [captureClicks(2,1) - center(2), captureClicks(2,2) - center(1)];

    res = imaging.geometricPhaseAnalysis(filteredPixels, g1, g2, PixelSize=pixelSize);

    gpaFig = figure('Name', 'GPA Strain Maps', 'NumberTitle', 'off');
    ax1 = subplot(2,2,1); imagesc(res.exx); axis equal tight;
    colorbar(ax1); title('exx'); colormap(ax1, jet(256)); clim(ax1, [-0.05 0.05]);
    ax2 = subplot(2,2,2); imagesc(res.eyy); axis equal tight;
    colorbar(ax2); title('eyy'); colormap(ax2, jet(256)); clim(ax2, [-0.05 0.05]);
    ax3 = subplot(2,2,3); imagesc(res.exy); axis equal tight;
    colorbar(ax3); title('exy'); colormap(ax3, jet(256)); clim(ax3, [-0.05 0.05]);
    ax4 = subplot(2,2,4); imagesc(rad2deg(res.rotation)); axis equal tight;
    colorbar(ax4); title('Rotation (deg)'); colormap(ax4, jet(256));

    result.gpaResult = res;
    result.gpaFig = gpaFig;
    result.statusMsg = 'GPA strain maps computed.';
end
