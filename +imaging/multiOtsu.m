function result = multiOtsu(img, opts)
%MULTIOTSU  Multi-level Otsu threshold for N-class image segmentation.
%
%   Syntax:
%       result = imaging.multiOtsu(img)
%       result = imaging.multiOtsu(img, NumClasses=3, NumBins=256)
%
%   Maximises the between-class variance (Otsu criterion) over all
%   combinations of (NumClasses - 1) thresholds.  No toolbox required.
%   For NumClasses = 5 a coarse-to-fine strategy (64-bin first pass,
%   256-bin refinement) is used to keep run time tractable.
%
%   Inputs:
%       img        — [H x W] numeric matrix (grayscale)
%
%   Optional Name-Value:
%       NumClasses — number of intensity classes, 2..5 (default: 3)
%       NumBins    — histogram bins for 2..4 classes (default: 256)
%                    For NumClasses=5 the coarse pass uses 64 bins regardless.
%
%   Output:
%       result — struct with fields:
%           .thresholds    — [1 x (NumClasses-1)] threshold values in original
%                            image intensity units
%           .labelMap      — uint8 [H x W]; pixel labels 1..NumClasses
%           .classFractions — [1 x NumClasses] fractional area per class
%           .classRanges   — [NumClasses x 2] intensity range [min, max]
%                            per class in original image units
%
%   Examples:
%       r = imaging.multiOtsu(img);                  % 3-class segmentation
%       imagesc(r.labelMap); colormap(lines(3));
%       fprintf('Thresholds: %.0f  %.0f\n', r.thresholds);
%
%       r = imaging.multiOtsu(img, NumClasses=2);    % standard Otsu
%       mask = r.labelMap == 2;                       % foreground
%
%       r = imaging.multiOtsu(img, NumClasses=4, NumBins=128);
%
%   See also imaging.adjustContrast, imaging.applyGaussian

% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    img            (:,:) {mustBeNumeric}
    opts.NumClasses (1,1) double {mustBeInteger, mustBeInRange(opts.NumClasses,2,5)} = 3
    opts.NumBins    (1,1) double {mustBeInteger, mustBePositive}                     = 256
end

nClasses = opts.NumClasses;
nBins    = opts.NumBins;

imgDbl  = double(img);
imgMin  = min(imgDbl(:));
imgMax  = max(imgDbl(:));

% Degenerate case: all pixels identical
if imgMax == imgMin
    result.thresholds     = repmat(imgMin, 1, nClasses - 1);
    result.labelMap       = ones(size(img), 'uint8');
    result.classFractions = [1, zeros(1, nClasses - 1)];
    result.classRanges    = repmat([imgMin, imgMax], nClasses, 1);
    return
end

% ════════════════════════════════════════════════════════════════════════
%  Histogram and probability distribution
% ════════════════════════════════════════════════════════════════════════
    function [prob, binEdges, binCentres] = buildHist(image, nB)
        binEdges   = linspace(imgMin, imgMax, nB + 1);
        counts     = histc(image(:), binEdges);     %#ok<HISTC>
        counts(end-1) = counts(end-1) + counts(end); % absorb right-edge bin
        counts     = counts(1:nB);
        prob       = counts / sum(counts);
        binCentres = (binEdges(1:nB) + binEdges(2:nB+1)) / 2;
    end

% ════════════════════════════════════════════════════════════════════════
%  Between-class variance for a given threshold index vector
% ════════════════════════════════════════════════════════════════════════
    function sigma2B = betweenClassVar(prob, muTotal, threshIdx, nB)
        % threshIdx: bin indices that define class boundaries (values are
        % last bin index belonging to class k).  Classes are:
        %   k=1: bins 1..threshIdx(1)
        %   k=2: bins threshIdx(1)+1..threshIdx(2)   etc.
        bounds = [0, threshIdx(:)', nB];
        K      = numel(bounds) - 1;
        sigma2B = 0;
        for k = 1:K
            binsK = bounds(k)+1 : bounds(k+1);
            wk    = sum(prob(binsK));
            if wk < eps
                continue
            end
            muk = dot(prob(binsK), binsK) / wk;  % weighted mean bin index
            sigma2B = sigma2B + wk * (muk - muTotal)^2;
        end
    end

% ════════════════════════════════════════════════════════════════════════
%  Find optimal thresholds
% ════════════════════════════════════════════════════════════════════════
    function threshIdx = findThresholds(prob, nB, K)
        % Returns (K-1) bin-index thresholds that maximise between-class variance
        muTotal = dot(prob, 1:nB);
        bestVar = -Inf;
        threshIdx = round(linspace(1, nB, K+1));
        threshIdx = threshIdx(2:K);   % safe default

        switch K
            case 2
                for t1 = 1:nB-1
                    v = betweenClassVar(prob, muTotal, t1, nB);
                    if v > bestVar
                        bestVar = v;
                        threshIdx = t1;
                    end
                end
            case 3
                for t1 = 1:nB-2
                    for t2 = t1+1:nB-1
                        v = betweenClassVar(prob, muTotal, [t1,t2], nB);
                        if v > bestVar
                            bestVar = v;
                            threshIdx = [t1, t2];
                        end
                    end
                end
            case 4
                for t1 = 1:nB-3
                    for t2 = t1+1:nB-2
                        for t3 = t2+1:nB-1
                            v = betweenClassVar(prob, muTotal, [t1,t2,t3], nB);
                            if v > bestVar
                                bestVar = v;
                                threshIdx = [t1, t2, t3];
                            end
                        end
                    end
                end
            case 5
                for t1 = 1:nB-4
                    for t2 = t1+1:nB-3
                        for t3 = t2+1:nB-2
                            for t4 = t3+1:nB-1
                                v = betweenClassVar(prob, muTotal, [t1,t2,t3,t4], nB);
                                if v > bestVar
                                    bestVar = v;
                                    threshIdx = [t1, t2, t3, t4];
                                end
                            end
                        end
                    end
                end
        end
    end

if nClasses == 5
    % ── Coarse-to-fine for 5-class (avoids O(256^4) = 4G iterations) ────
    nCoarse = 64;
    [probC, ~, centresC] = buildHist(imgDbl, nCoarse);
    idxC = findThresholds(probC, nCoarse, nClasses);

    % Map coarse bin indices back to intensity, then zoom in with full bins
    coarseVals = centresC(idxC);

    % Fine pass: restrict search to ±2 coarse bins around each coarse threshold
    binWidth  = (imgMax - imgMin) / nBins;
    coarseW   = (imgMax - imgMin) / nCoarse;
    [probF, edgesF, ~] = buildHist(imgDbl, nBins);

    % Convert coarse intensity thresholds to fine bin indices (clamped)
    fineCenter = round((coarseVals - imgMin) / binWidth) + 1;
    window     = max(2, round(coarseW / binWidth) * 2);

    % Build a search grid around the coarse solution
    t1Range = max(1, fineCenter(1)-window) : min(nBins-3, fineCenter(1)+window);
    t2Range = max(1, fineCenter(2)-window) : min(nBins-2, fineCenter(2)+window);
    t3Range = max(1, fineCenter(3)-window) : min(nBins-1, fineCenter(3)+window);
    t4Range = max(1, fineCenter(4)-window) : min(nBins,   fineCenter(4)+window);

    muTotal  = dot(probF, 1:nBins);
    bestVar  = -Inf;
    bestIdx  = fineCenter;
    for t1 = t1Range
        for t2 = t2Range(t2Range > t1)
            for t3 = t3Range(t3Range > t2)
                for t4 = t4Range(t4Range > t3)
                    v = betweenClassVar(probF, muTotal, [t1,t2,t3,t4], nBins);
                    if v > bestVar
                        bestVar = v;
                        bestIdx = [t1, t2, t3, t4];
                    end
                end
            end
        end
    end

    % Convert bin indices to intensity values
    threshVals = edgesF(bestIdx + 1);   % upper edge of each threshold bin

else
    [probF, edgesF, ~] = buildHist(imgDbl, nBins);
    bestIdx    = findThresholds(probF, nBins, nClasses);
    threshVals = edgesF(bestIdx + 1);
end

% ════════════════════════════════════════════════════════════════════════
%  Build label map
% ════════════════════════════════════════════════════════════════════════
labelMap = ones(size(img), 'uint8');   % class 1 = darkest
for k = 1:numel(threshVals)
    labelMap(imgDbl > threshVals(k)) = uint8(k + 1);
end

% ════════════════════════════════════════════════════════════════════════
%  Per-class statistics
% ════════════════════════════════════════════════════════════════════════
nPx           = numel(img);
classFractions = zeros(1, nClasses);
classRanges    = zeros(nClasses, 2);

for k = 1:nClasses
    mask = labelMap == uint8(k);
    classFractions(k) = sum(mask(:)) / nPx;
    vals = imgDbl(mask);
    if isempty(vals)
        classRanges(k,:) = [NaN, NaN];
    else
        classRanges(k,:) = [min(vals), max(vals)];
    end
end

% ════════════════════════════════════════════════════════════════════════
%  Assemble result
% ════════════════════════════════════════════════════════════════════════
result.thresholds     = threshVals(:)';
result.labelMap       = labelMap;
result.classFractions = classFractions;
result.classRanges    = classRanges;

end
