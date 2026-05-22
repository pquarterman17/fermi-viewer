function result = executeImageMath(pxA, pxB, op, nameA)
%EXECUTEIMAGEMATHD  Arithmetic operation on two images.
    arguments
        pxA     double
        pxB     double
        op      char
        nameA   char = ''
    end

    [hA, wA] = size(pxA); [hB, wB] = size(pxB);
    mh = min(hA, hB); mw = min(wA, wB);
    pxA = pxA(1:mh, 1:mw); pxB = pxB(1:mh, 1:mw);

    switch op
        case 'subtract', res = pxA - pxB;
        case 'divide',   res = pxA ./ max(pxB, 1);
        case 'ratio',    res = pxA ./ max(pxA + pxB, 1);
        case 'add',      res = pxA + pxB;
        otherwise
            error('executeImageMath:badOp', 'Unknown operation: %s', op);
    end

    mathFig = figure('Name', sprintf('Image Math: %s', op), 'NumberTitle', 'off');
    imagesc(res); colormap(gray(256)); axis image; colorbar;
    title(sprintf('%s — %s', nameA, op), 'Interpreter', 'none');

    result.fig = mathFig;
    result.pixels = res;
    result.statusMsg = sprintf('Image math: %s', op);
end
