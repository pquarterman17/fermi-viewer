function dispImg = applyPipeline(pixels, lo, hi, transform, gamma, invert)
%APPLYPIPELINE  Apply contrast transform → window → gamma → invert.
    arguments
        pixels    double
        lo        (1,1) double
        hi        (1,1) double
        transform char   = 'linear'
        gamma     (1,1) double = 1.0
        invert    (1,1) logical = false
    end

    img = double(pixels);

    switch transform
        case 'log'
            img = log1p(max(img, -1));
            lo  = log1p(max(lo,  -1));
            hi  = log1p(max(hi,  -1));
        case 'sqrt'
            img = sqrt(max(img, 0));
            lo = sqrt(max(lo, 0));
            hi = sqrt(max(hi, 0));
        case 'power'
            img = max(img, 0) .^ 0.3;
            lo  = max(lo,  0) ^ 0.3;
            hi  = max(hi,  0) ^ 0.3;
    end

    if hi <= lo
        hi = lo + 1;
    end
    dispImg = (img - lo) / (hi - lo);
    dispImg = max(0, min(1, dispImg));

    if gamma ~= 1.0
        dispImg = dispImg .^ gamma;
    end

    if invert
        dispImg = 1 - dispImg;
    end
end
