function outImg = clahe(img, options)
%CLAHE  Contrast-Limited Adaptive Histogram Equalization (no toolbox).
%
%   Syntax:
%       out = imaging.clahe(img)
%       out = imaging.clahe(img, TileSize=[8 8])
%       out = imaging.clahe(img, TileSize=[8 8], ClipLimit=0.01, NumBins=256)
%
%   Tile-based adaptive histogram equalization with clipping. The image
%   is divided into a grid of non-overlapping rectangular tiles; a
%   histogram is computed for each tile, clipped at ClipLimit (with the
%   excess redistributed uniformly), converted to a CDF-based mapping
%   LUT, and applied to pixels using bilinear interpolation between the
%   four nearest tile centers. This avoids the visible tile boundaries
%   that pure per-tile equalization produces.
%
%   No Image Processing Toolbox required.
%
%   Inputs:
%       img        — [H x W] numeric matrix (any integer or float type)
%
%   Optional Name-Value:
%       TileSize   — [rows cols] number of tiles (default: [8 8])
%       ClipLimit  — Fractional clip limit on normalized histogram counts
%                    (default: 0.01, typical 0.005–0.04). 0 disables
%                    clipping (pure AHE, which tends to amplify noise).
%       NumBins    — Number of histogram bins (default: 256)
%
%   Output:
%       out — [H x W] double image rescaled to [0, 1].
%
%   Examples:
%       eq = imaging.clahe(rawImg);
%       eq = imaging.clahe(rawImg, TileSize=[4 4], ClipLimit=0.02);
%
%   Notes:
%       - For low-contrast EM/STEM images a ClipLimit around 0.01 with
%         [8 8] tiles is a good starting point.
%       - The output is always double in [0, 1]. Rescale to your
%         preferred display range with `rescale` or a linear map.
%
%   See also imaging.adjustContrast, imaging.unsharpMask, imaging.multiOtsu

% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    img                   (:,:) {mustBeNumeric}
    options.TileSize      (1,2) double {mustBePositive, mustBeInteger} = [8 8]
    options.ClipLimit     (1,1) double {mustBeNonnegative} = 0.01
    options.NumBins       (1,1) double {mustBePositive, mustBeInteger} = 256
end

nTilesR = options.TileSize(1);
nTilesC = options.TileSize(2);
nBins   = options.NumBins;
clip    = options.ClipLimit;

[H, W] = size(img);
d = double(img);

% ════════════════════════════════════════════════════════════════════════
%  Normalize to [0, nBins-1] integer bin indices
% ════════════════════════════════════════════════════════════════════════
dMin = min(d(:));
dMax = max(d(:));
if dMax <= dMin
    % Constant image — nothing to equalize
    outImg = zeros(H, W);
    return;
end

% bin index in [0, nBins-1]
binImg = floor((d - dMin) / (dMax - dMin) * (nBins - 1) + 0.5);
binImg = max(0, min(nBins - 1, binImg));

% ════════════════════════════════════════════════════════════════════════
%  Tile grid: compute LUT per tile
% ════════════════════════════════════════════════════════════════════════
% Tile boundaries (integer row/col ranges). Use ceil so the last tile
% absorbs any remainder when H/W isn't divisible by the tile count.
rowEdges = round(linspace(0, H, nTilesR + 1));
colEdges = round(linspace(0, W, nTilesC + 1));

% LUTs(:, i, j) = mapping LUT for tile (i, j)
LUTs = zeros(nBins, nTilesR, nTilesC);

for i = 1:nTilesR
    rr = (rowEdges(i) + 1) : rowEdges(i + 1);
    for j = 1:nTilesC
        cc = (colEdges(j) + 1) : colEdges(j + 1);
        tileBins = binImg(rr, cc);
        nPx = numel(tileBins);
        if nPx == 0
            LUTs(:, i, j) = linspace(0, 1, nBins);
            continue;
        end

        % Histogram over bin indices [0, nBins-1]
        h = histcounts(tileBins(:), -0.5 : (nBins - 0.5));

        % Contrast clipping: clip counts above clipLimit*nPx and
        % redistribute the excess uniformly across all bins.
        if clip > 0
            clipCount = max(1, round(clip * nPx));
            excess = sum(max(0, h - clipCount));
            h = min(h, clipCount);
            h = h + excess / nBins;
        end

        % CDF → LUT in [0, 1]
        cdf = cumsum(h);
        if cdf(end) > 0
            cdf = cdf / cdf(end);
        end
        LUTs(:, i, j) = cdf(:);
    end
end

% ════════════════════════════════════════════════════════════════════════
%  Bilinear interpolation across tile centers
% ════════════════════════════════════════════════════════════════════════
% Tile center row/col (1-based floating coordinates)
tileCR = (rowEdges(1:end-1) + rowEdges(2:end) + 1) / 2;
tileCC = (colEdges(1:end-1) + colEdges(2:end) + 1) / 2;

% For each pixel, find the two bracketing tile centers in each axis.
rows = (1:H)';
cols = 1:W;

% Find bracketing indices (iLo, iHi) such that tileCR(iLo) <= r <= tileCR(iHi).
% Pixels outside the outer tile centers use the nearest center (no extrap).
iLo = zeros(H, 1);
iHi = zeros(H, 1);
for r = 1:H
    idx = find(tileCR <= rows(r), 1, 'last');
    if isempty(idx)
        iLo(r) = 1; iHi(r) = 1;
    elseif idx == nTilesR
        iLo(r) = nTilesR; iHi(r) = nTilesR;
    else
        iLo(r) = idx; iHi(r) = idx + 1;
    end
end

jLo = zeros(1, W);
jHi = zeros(1, W);
for c = 1:W
    idx = find(tileCC <= cols(c), 1, 'last');
    if isempty(idx)
        jLo(c) = 1; jHi(c) = 1;
    elseif idx == nTilesC
        jLo(c) = nTilesC; jHi(c) = nTilesC;
    else
        jLo(c) = idx; jHi(c) = idx + 1;
    end
end

% Fractional weights
wRow = zeros(H, 1);
for r = 1:H
    if iLo(r) == iHi(r)
        wRow(r) = 0;
    else
        wRow(r) = (rows(r) - tileCR(iLo(r))) / (tileCR(iHi(r)) - tileCR(iLo(r)));
    end
end

wCol = zeros(1, W);
for c = 1:W
    if jLo(c) == jHi(c)
        wCol(c) = 0;
    else
        wCol(c) = (cols(c) - tileCC(jLo(c))) / (tileCC(jHi(c)) - tileCC(jLo(c)));
    end
end

% Apply: outImg(r, c) =
%   (1-wR)(1-wC) * LUT[iLo,jLo](b) + wR(1-wC) * LUT[iHi,jLo](b)
% + (1-wR) wC    * LUT[iLo,jHi](b) + wR wC     * LUT[iHi,jHi](b)
outImg = zeros(H, W);
lutIdx = binImg + 1;   % 1-based index into LUT
for r = 1:H
    wr = wRow(r);
    for c = 1:W
        wc = wCol(c);
        b  = lutIdx(r, c);
        v00 = LUTs(b, iLo(r), jLo(c));
        v01 = LUTs(b, iLo(r), jHi(c));
        v10 = LUTs(b, iHi(r), jLo(c));
        v11 = LUTs(b, iHi(r), jHi(c));
        outImg(r, c) = (1 - wr) * ((1 - wc) * v00 + wc * v01) ...
                     +      wr  * ((1 - wc) * v10 + wc * v11);
    end
end
end
