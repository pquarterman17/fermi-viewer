function result = executeMontage(tiles, nCols, overlap)
%EXECUTEMONTAGE  Stitch tile images into a montage grid.
    arguments
        tiles   cell
        nCols   double
        overlap double
    end

    nImgs = numel(tiles);
    nRows = ceil(nImgs / nCols);

    maxH = 0; maxW = 0;
    for ti = 1:nImgs
        [h, w] = size(tiles{ti});
        maxH = max(maxH, h); maxW = max(maxW, w);
    end

    stepY = round(maxH * (1 - overlap));
    stepX = round(maxW * (1 - overlap));
    outH = (nRows - 1) * stepY + maxH;
    outW = (nCols - 1) * stepX + maxW;
    montage = zeros(outH, outW);
    weight  = zeros(outH, outW);

    for ti = 1:nImgs
        row = floor((ti - 1) / nCols);
        col = mod(ti - 1, nCols);
        y0 = row * stepY + 1;
        x0 = col * stepX + 1;
        [th, tw] = size(tiles{ti});
        yEnd = min(outH, y0 + th - 1);
        xEnd = min(outW, x0 + tw - 1);
        rh = yEnd - y0 + 1; rw = xEnd - x0 + 1;
        montage(y0:yEnd, x0:xEnd) = montage(y0:yEnd, x0:xEnd) + tiles{ti}(1:rh, 1:rw);
        weight(y0:yEnd, x0:xEnd)  = weight(y0:yEnd, x0:xEnd)  + 1;
    end

    weight(weight == 0) = 1;
    montage = montage ./ weight;

    mFig = figure('Name', 'Montage', 'NumberTitle', 'off');
    imagesc(montage); colormap(gray(256)); axis image;
    title(sprintf('%d images, %dx%d grid, %.0f%% overlap', ...
        nImgs, nRows, nCols, overlap*100), 'Interpreter', 'none');
    colorbar;

    result.fig = mFig;
    result.montage = montage;
    result.statusMsg = sprintf('Montage: %dx%d grid (%dx%d px)', nRows, nCols, outW, outH);
end
