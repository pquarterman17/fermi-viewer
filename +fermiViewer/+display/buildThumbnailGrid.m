function gridFig = buildThumbnailGrid(images, jumpCallback)
%BUILDTHUMBNAILGRID  Show a thumbnail grid of all loaded images.
%   gridFig = buildThumbnailGrid(images, @(idx) jumpToImage(idx))
    arguments
        images       cell
        jumpCallback function_handle
    end

    nImgs = numel(images);
    nCols = ceil(sqrt(nImgs));
    nRows = ceil(nImgs / nCols);

    gridFig = figure('Name', 'Image Grid', 'NumberTitle', 'off', ...
        'Units', 'normalized', 'Position', [0.1 0.1 0.7 0.7]);

    for gi = 1:nImgs
        subplot(nRows, nCols, gi);
        imgInfo = images{gi}.metadata.parserSpecific.imageData;
        px = double(imgInfo.pixels);
        if imgInfo.numChannels == 3
            px = 0.299*px(:,:,1) + 0.587*px(:,:,2) + 0.114*px(:,:,3);
        end
        thumb = imaging.generateThumbnail(px, MaxSize=128);
        lo = imaging.percentile(thumb(:), 2);
        hi = imaging.percentile(thumb(:), 98);
        if hi <= lo, hi = lo + 1; end
        thumbDisp = max(0, min(1, (thumb - lo) / (hi - lo)));
        imagesc(thumbDisp); colormap(gray(256)); axis image off;
        [~, fn, fe] = fileparts(images{gi}.metadata.source);
        title([fn fe], 'Interpreter', 'none', 'FontSize', 8);

        ax_g = gca;
        ax_g.UserData = gi;
        ax_g.ButtonDownFcn = @(src, ~) jumpCallback(src.UserData);
    end
end
