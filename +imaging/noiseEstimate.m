function result = noiseEstimate(img, options)
%NOISEESTIMATE  Estimate noise level and type in an image.
%
%   Uses multiple methods to characterize image noise:
%   - Median absolute deviation (MAD) of high-frequency components
%   - Local variance analysis
%   - Noise type classification (Gaussian vs Poisson)
%
%   Syntax:
%       result = imaging.noiseEstimate(img)
%       result = imaging.noiseEstimate(img, Method='mad')
%       result = imaging.noiseEstimate(img, Method='localvar')
%       result = imaging.noiseEstimate(img, Method='both')
%
%   Inputs:
%       img    — [H x W] grayscale image (double, or any numeric type)
%
%   Optional Name-Value:
%       Method — 'mad' (default) | 'localvar' | 'both'
%                'mad'      uses a Laplacian kernel + median absolute deviation
%                'localvar' divides the image into 16x16 blocks and estimates
%                           noise from the modal block variance
%                'both'     runs both and averages the two sigma estimates
%
%   Outputs:
%       result.sigma          — Estimated noise standard deviation (intensity units)
%       result.snr            — Signal-to-noise ratio in dB  (20*log10(S/N))
%       result.snrLinear      — Signal-to-noise ratio (linear, S/N)
%       result.noiseType      — 'gaussian' | 'poisson' | 'mixed' | 'unknown'
%       result.method         — Method string that was used
%       result.suggestedFilter — struct with recommended filter parameters:
%           .type   — 'gaussian' | 'median'
%           .sigma  — recommended sigma for Gaussian filter
%           .window — recommended window size for median filter
%
%   Examples:
%       % Basic noise estimate
%       result = imaging.noiseEstimate(img);
%       fprintf('sigma = %.2f, type = %s\n', result.sigma, result.noiseType);
%
%       % Use local-variance method
%       result = imaging.noiseEstimate(img, Method='localvar');
%
%       % Apply the suggested filter
%       if strcmp(result.suggestedFilter.type, 'gaussian')
%           clean = imaging.applyGaussian(img, Sigma=result.suggestedFilter.sigma);
%       else
%           clean = imaging.applyMedian(img, result.suggestedFilter.window);
%       end
%
%   See also imaging.applyGaussian, imaging.applyMedian, imaging.adjustContrast

% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    img            (:,:) {mustBeNumeric}
    options.Method (1,1) string {mustBeMember(options.Method, ...
                       {'mad','localvar','both'})} = 'mad'
end

img = double(img);
[H, W] = size(img);

% ════════════════════════════════════════════════════════════════════════
%  MAD-based sigma estimate (Laplacian kernel method)
% ════════════════════════════════════════════════════════════════════════
function s = estimateSigmaMAD(I)
    K = [1 -2 1; -2 4 -2; 1 -2 1];
    response = conv2(I, K, 'valid');
    % 0.6745 converts MAD to sigma for Gaussian noise;
    % 1/sqrt(20) corrects for the Laplacian kernel energy (sum of K.^2 = 20)
    s = median(abs(response(:))) / 0.6745 / sqrt(20);
end

% ════════════════════════════════════════════════════════════════════════
%  Local-variance sigma estimate (block-based mode method)
% ════════════════════════════════════════════════════════════════════════
function [s, blockMeans, blockVars] = estimateSigmaLocalVar(I)
    blockSize = 16;
    nRow = floor(H / blockSize);
    nCol = floor(W / blockSize);

    if nRow < 1 || nCol < 1
        % Image too small for 16x16 blocks; fall back to full-image variance
        s       = std(I(:));
        blockMeans = mean(I(:));
        blockVars  = var(I(:));
        return
    end

    nBlocks    = nRow * nCol;
    blockMeans = zeros(nBlocks, 1);
    blockVars  = zeros(nBlocks, 1);

    idx = 0;
    for r = 1:nRow
        rStart = (r - 1) * blockSize + 1;
        rEnd   = r * blockSize;
        for c = 1:nCol
            cStart = (c - 1) * blockSize + 1;
            cEnd   = c * blockSize;
            idx = idx + 1;
            blk = I(rStart:rEnd, cStart:cEnd);
            blockMeans(idx) = mean(blk(:));
            blockVars(idx)  = var(blk(:));
        end
    end

    % Mode of block variances: flat (low-detail) blocks dominate → noise floor
    % Approximate mode via histogram with ~50 bins
    nBins   = min(50, nBlocks);
    varMin  = min(blockVars);
    varMax  = max(blockVars);

    if varMax <= varMin
        % All blocks are identical (e.g. synthetic flat image)
        s = sqrt(max(varMin, 0));
        return
    end

    edges  = linspace(varMin, varMax, nBins + 1);
    counts = histc(blockVars, edges);   %#ok<HISTC>  (built-in; histcounts needs R2014b+)
    counts = counts(1:end-1);           % drop the trailing bin from histc
    [~, modeBin] = max(counts);
    noiseVar = (edges(modeBin) + edges(modeBin + 1)) / 2;
    s = sqrt(max(noiseVar, 0));
end

% ════════════════════════════════════════════════════════════════════════
%  Dispatch to method(s)
% ════════════════════════════════════════════════════════════════════════
switch options.Method
    case 'mad'
        sigma = estimateSigmaMAD(img);
        % blockMeans/blockVars still needed for noise classification
        [~, blockMeans, blockVars] = estimateSigmaLocalVar(img);
        usedMethod = 'mad';

    case 'localvar'
        [sigma, blockMeans, blockVars] = estimateSigmaLocalVar(img);
        usedMethod = 'localvar';

    case 'both'
        sigmaMad = estimateSigmaMAD(img);
        [sigmaLV, blockMeans, blockVars] = estimateSigmaLocalVar(img);
        sigma = (sigmaMad + sigmaLV) / 2;
        usedMethod = 'both';
end

% Guard: sigma must be non-negative and finite
if ~isfinite(sigma) || sigma < 0
    sigma = 0;
end

% ════════════════════════════════════════════════════════════════════════
%  SNR
% ════════════════════════════════════════════════════════════════════════
signalLevel = mean(img(:));

if sigma > 0 && signalLevel > 0
    snrLinear = signalLevel / sigma;
    snrDb     = 20 * log10(snrLinear);
elseif sigma == 0
    snrLinear = Inf;
    snrDb     = Inf;
else
    % signalLevel <= 0 (e.g. mean-subtracted data)
    snrLinear = NaN;
    snrDb     = NaN;
end

% ════════════════════════════════════════════════════════════════════════
%  Noise type classification (variance vs mean across blocks)
% ════════════════════════════════════════════════════════════════════════
noiseType = classifyNoiseType(blockMeans, blockVars);

% ════════════════════════════════════════════════════════════════════════
%  Filter suggestion
% ════════════════════════════════════════════════════════════════════════
suggestedFilter = suggestFilter(sigma, noiseType);

% ════════════════════════════════════════════════════════════════════════
%  Assemble output
% ════════════════════════════════════════════════════════════════════════
result.sigma           = sigma;
result.snr             = snrDb;
result.snrLinear       = snrLinear;
result.noiseType       = noiseType;
result.method          = usedMethod;
result.suggestedFilter = suggestedFilter;

end

% ════════════════════════════════════════════════════════════════════════
%  Local helper: noise type classification
% ════════════════════════════════════════════════════════════════════════
function noiseType = classifyNoiseType(blockMeans, blockVars)
%CLASSIFYNOISETYPE  Classify noise as Gaussian or Poisson via var-vs-mean regression.
%
%   Gaussian noise: variance is independent of mean (flat relationship).
%   Poisson  noise: variance scales linearly with mean (slope ≈ 1 in photon units).
%   We use the R² of a linear fit of var vs mean to judge confidence.

    if numel(blockMeans) < 4
        noiseType = 'unknown';
        return
    end

    x = blockMeans(:);
    y = blockVars(:);

    % Remove blocks where the mean is non-positive (avoids Poisson confusion
    % when the image has a dark background with near-zero signal)
    valid = x > 0;
    if sum(valid) < 4
        noiseType = 'unknown';
        return
    end
    x = x(valid);
    y = y(valid);

    % Linear regression: y = a*x + b
    n  = numel(x);
    sx = sum(x);  sy = sum(y);
    sxx = sum(x .* x);  sxy = sum(x .* y);
    denom = n * sxx - sx^2;

    if abs(denom) < eps
        noiseType = 'unknown';
        return
    end

    slope     = (n * sxy - sx * sy) / denom;
    intercept = (sy - slope * sx) / n;

    yFit   = slope * x + intercept;
    ssTot  = sum((y - mean(y)).^2);
    ssRes  = sum((y - yFit).^2);

    if ssTot < eps
        % All variances identical — could be a synthetic/flat image
        noiseType = 'gaussian';
        return
    end

    rSquared = 1 - ssRes / ssTot;

    % Classification rules:
    %   slope near 0, R² < 0.4  → Gaussian (variance unrelated to mean)
    %   slope > 0,    R² > 0.6  → Poisson  (variance grows with mean)
    %   R² in [0.4, 0.6]        → mixed
    %   otherwise               → unknown
    if rSquared > 0.6 && slope > 0
        noiseType = 'poisson';
    elseif rSquared < 0.4
        noiseType = 'gaussian';
    elseif rSquared >= 0.4 && rSquared <= 0.6
        noiseType = 'mixed';
    else
        noiseType = 'unknown';
    end
end

% ════════════════════════════════════════════════════════════════════════
%  Local helper: filter suggestion
% ════════════════════════════════════════════════════════════════════════
function sf = suggestFilter(sigma, noiseType)
%SUGGESTFILTER  Return recommended filter type and parameters for given noise.

    % Poisson noise responds better to median filtering
    preferMedian = strcmp(noiseType, 'poisson');

    if sigma < 5
        sf.type   = 'gaussian';
        sf.sigma  = 1;
        sf.window = 3;
    elseif sigma <= 15
        if preferMedian
            sf.type   = 'median';
            sf.sigma  = 2;
            sf.window = 3;
        else
            sf.type   = 'gaussian';
            sf.sigma  = 2;
            sf.window = 3;
        end
    else
        % sigma > 15: heavy noise
        if preferMedian
            sf.type   = 'median';
            sf.sigma  = 3;
            sf.window = 5;
        else
            sf.type   = 'gaussian';
            sf.sigma  = 3;
            sf.window = 5;
        end
    end
end
