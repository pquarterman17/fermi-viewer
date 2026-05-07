function buildFigurePanel(images, nRows, nCols, gap)
%BUILDFIGUREPANEL  Create a composite figure panel from loaded images.
    arguments
        images  cell
        nRows   double
        nCols   double
        gap     double = 2
    end

    result = imaging.buildFigurePanel(images, Rows=nRows, Cols=nCols, Gap=gap);
    figure('Name', 'Figure Panel', 'NumberTitle', 'off');
    image(result.composite); axis equal tight off;
    title(sprintf('%dx%d panel (%d images)', nRows, nCols, numel(images)));
end
