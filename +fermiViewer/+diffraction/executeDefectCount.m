function result = executeDefectCount(filteredPixels, gridSpacing, pixelSize, pixelUnit)
%EXECUTEDEFECTCOUNT  Count defect line intersections and compute density.
    arguments
        filteredPixels  double
        gridSpacing     double
        pixelSize       double
        pixelUnit       char
    end

    res = imaging.countDefectLines(filteredPixels, ...
        GridSpacing=gridSpacing, PixelSize=pixelSize, PixelUnit=pixelUnit);

    result.defectResult = res;
    result.statusMsg = sprintf('Defect density: %.3g %s', res.density, res.densityUnit);
    result.dialogMsg = sprintf(['Defect Line Count\n\n' ...
        'Intersections: %d\nTest lines: %d\n' ...
        'Density: %.3g %s'], ...
        res.intersectionCount, res.numTestLines, ...
        res.density, res.densityUnit);
end
