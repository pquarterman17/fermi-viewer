function thresh = otsuThreshold(img)
%OTSUTHRESHOLD  Compute Otsu's optimal threshold (no toolbox).
    arguments
        img  double
    end

    img = double(img(:));
    nBins = 256;
    [counts, edges] = histcounts(img, nBins);
    binCenters = (edges(1:end-1) + edges(2:end)) / 2;
    totalPx = numel(img);
    sumTotal = sum(binCenters .* counts);
    sumB = 0; wB = 0;
    maxVar = 0; thresh = binCenters(1);
    for bi = 1:nBins
        wB = wB + counts(bi);
        if wB == 0, continue; end
        wF = totalPx - wB;
        if wF == 0, break; end
        sumB = sumB + binCenters(bi) * counts(bi);
        mB = sumB / wB;
        mF = (sumTotal - sumB) / wF;
        varBetween = wB * wF * (mB - mF)^2;
        if varBetween > maxVar
            maxVar = varBetween;
            thresh = binCenters(bi);
        end
    end
end
