function result = executeStitchImages(images, layout)
%EXECUTESTITCHIMAGES  Stitch multiple images into a mosaic and show result.
    arguments
        images  cell
        layout  char
    end

    imgs = cell(1, numel(images));
    for si = 1:numel(images)
        imgs{si} = imaging.getGrayscale(images{si});
    end
    r = imaging.stitchImages(imgs, Layout=layout);

    sFig = figure('Name', 'Stitched Mosaic', 'NumberTitle', 'off', ...
        'Tag', 'fermiViewerStitch');
    sAx = axes(sFig);
    imagesc(sAx, r.mosaic);
    axis(sAx, 'image');
    colormap(sAx, gray(256));
    sAx.XTick = [];
    sAx.YTick = [];
    title(sAx, sprintf('Mosaic: %d images (%s)', r.nImages, r.layout));

    result.nImages   = r.nImages;
    result.layout    = r.layout;
    result.statusMsg = sprintf('Stitched %d images (%s layout)', r.nImages, r.layout);
end
