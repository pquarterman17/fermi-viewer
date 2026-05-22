function out = applyCLAHE(img, tileSize, clipLimit)
%APPLYCLAHE  No-toolbox Contrast-Limited Adaptive Histogram Equalization.
%   Tiles the image, computes clipped local histograms, bilinear-
%   interpolates the mappings across tile boundaries.
    arguments
        img       double
        tileSize  (1,1) double {mustBePositive}
        clipLimit (1,1) double {mustBePositive}
    end

    [H, W] = size(img);

    dMin = min(img(:));
    dMax = max(img(:));
    if dMax == dMin, dMax = dMin + 1; end
    imgNorm = (img - dMin) / (dMax - dMin);

    nBins = 256;
    nTilesR = max(1, round(H / tileSize));
    nTilesC = max(1, round(W / tileSize));
    tileH = H / nTilesR;
    tileW = W / nTilesC;

    mappings = cell(nTilesR, nTilesC);
    for tr = 1:nTilesR
        r1 = round((tr-1) * tileH) + 1;
        r2 = min(H, round(tr * tileH));
        for tc = 1:nTilesC
            c1 = round((tc-1) * tileW) + 1;
            c2 = min(W, round(tc * tileW));
            tile = imgNorm(r1:r2, c1:c2);

            counts = histcounts(tile(:), linspace(0, 1, nBins+1));

            nPix = numel(tile);
            clipCount = clipLimit * (nPix / nBins);
            excess = sum(max(0, counts - clipCount));
            counts = min(counts, clipCount);
            counts = counts + excess / nBins;

            cdf = cumsum(counts);
            if cdf(end) == 0
                cdf = linspace(0, 1, nBins);
            else
                cdf = cdf / cdf(end);
            end
            mappings{tr, tc} = cdf;
        end
    end

    out = zeros(H, W);
    for r = 1:H
        ty = (r - 0.5) / tileH - 0.5;
        tr1 = max(1, floor(ty) + 1);
        tr2 = min(nTilesR, tr1 + 1);
        fy = ty - (tr1 - 1);
        fy = max(0, min(1, fy));

        for c = 1:W
            tx = (c - 0.5) / tileW - 0.5;
            tc1 = max(1, floor(tx) + 1);
            tc2 = min(nTilesC, tc1 + 1);
            fx = tx - (tc1 - 1);
            fx = max(0, min(1, fx));

            val = imgNorm(r, c);
            bin = max(1, min(nBins, round(val * (nBins-1)) + 1));

            v11 = mappings{tr1, tc1}(bin);
            v12 = mappings{tr1, tc2}(bin);
            v21 = mappings{tr2, tc1}(bin);
            v22 = mappings{tr2, tc2}(bin);

            mapped = (1-fy) * ((1-fx)*v11 + fx*v12) + ...
                      fy    * ((1-fx)*v21 + fx*v22);
            out(r, c) = mapped;
        end
    end

    out = out * (dMax - dMin) + dMin;
end
