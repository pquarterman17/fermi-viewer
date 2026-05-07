function result = executeAlignStack(images)
%EXECUTEALIGNSTACK  FFT cross-correlation drift correction for an image stack.
    arguments
        images  cell
    end

    refPx = imaging.getGrayscale(images{1});
    shifts = zeros(numel(images), 2);

    for ki = 2:numel(images)
        movPx = imaging.getGrayscale(images{ki});

        [H2, W2] = size(refPx);
        [Hm, Wm] = size(movPx);
        padH = max(H2, Hm);
        padW = max(W2, Wm);

        refPad = zeros(padH, padW);
        refPad(1:H2, 1:W2) = refPx;
        movPad = zeros(padH, padW);
        movPad(1:Hm, 1:Wm) = movPx;

        cc = real(ifft2(fft2(refPad) .* conj(fft2(movPad))));
        [~, maxIdx] = max(cc(:));
        [peakR, peakC] = ind2sub(size(cc), maxIdx);

        dy = peakR - 1;
        dx = peakC - 1;
        if dy > padH/2, dy = dy - padH; end
        if dx > padW/2, dx = dx - padW; end
        shifts(ki, :) = [dy, dx];

        imgInfo = images{ki}.metadata.parserSpecific.imageData;
        shiftedPx = circshift(movPx, [dy, dx]);
        images{ki}.metadata.parserSpecific.imageData.pixels = ...
            cast(shiftedPx, class(imgInfo.pixels));
    end

    shiftStr = '';
    for ki = 2:numel(images)
        [~, fn, fe] = fileparts(images{ki}.metadata.source);
        shiftStr = [shiftStr sprintf('  %s%s: dy=%+d, dx=%+d\n', fn, fe, ...
            shifts(ki,1), shifts(ki,2))]; %#ok<AGROW>
    end

    result.images = images;
    result.shifts = shifts;
    result.shiftStr = shiftStr;
    result.statusMsg = sprintf('Aligned %d images to reference', numel(images) - 1);
end
