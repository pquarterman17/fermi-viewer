function result = templateMatch(img, template, opts)
%TEMPLATEMATCH  Find occurrences of a template pattern in an image.
%
%   Uses normalized cross-correlation (NCC) via FFT for speed.
%   Returns locations where NCC exceeds the threshold.
%
%   Syntax:
%       result = imaging.templateMatch(img, template)
%       result = imaging.templateMatch(img, template, Threshold=0.7)
%       result = imaging.templateMatch(img, template, MaxMatches=50)
%       result = imaging.templateMatch(img, template, MinDistance=32)
%
%   Inputs:
%       img      — [H x W] grayscale image (double or integer)
%       template — [h x w] template patch (double or integer), smaller than img
%
%   Name-Value:
%       Threshold   — NCC threshold in [0, 1], default 0.7
%       MaxMatches  — Maximum number of matches to return, default 100
%       MinDistance — Minimum pixel distance between match centers for
%                     non-maximum suppression; default max(h, w)
%
%   Outputs:
%       result.locations — [N x 2] matrix of [row, col] match centers
%       result.scores    — [N x 1] NCC scores at each location
%       result.nccMap    — [H x W] full NCC map (for visualization)
%       result.nMatches  — number of matches found
%       result.threshold — threshold used
%
%   Examples:
%       % Find a sub-region within a larger image
%       img = double(imread('sample.tif'));
%       tmpl = img(100:132, 200:232);   % 33x33 patch
%       result = imaging.templateMatch(img, tmpl, Threshold=0.85);
%       disp(result.locations)          % [row, col] of each match center
%
%       % Visualize the NCC map
%       result = imaging.templateMatch(img, tmpl);
%       imagesc(result.nccMap); colorbar; colormap hot;
%       hold on;
%       plot(result.locations(:,2), result.locations(:,1), 'b+', ...
%            'MarkerSize', 12, 'LineWidth', 2);
%
%   See also imaging.lineProfile, imaging.measureDistance

% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    img      (:,:) {mustBeNumeric}
    template (:,:) {mustBeNumeric}
    opts.Threshold   (1,1) double {mustBeInRange(opts.Threshold,   0, 1)} = 0.7
    opts.MaxMatches  (1,1) double {mustBePositive, mustBeInteger}         = 100
    opts.MinDistance (1,1) double {mustBeNonnegative}                     = 0
end

% ════════════════════════════════════════════════════════════════════════
%  Validate sizes
% ════════════════════════════════════════════════════════════════════════
[imgH, imgW]   = size(img);
[tmplH, tmplW] = size(template);

if tmplH >= imgH || tmplW >= imgW
    error('imaging:templateMatch:templateTooLarge', ...
        'Template (%dx%d) must be strictly smaller than image (%dx%d).', ...
        tmplH, tmplW, imgH, imgW);
end

% Resolve MinDistance default after we know template size
minDist = opts.MinDistance;
if minDist == 0
    minDist = max(tmplH, tmplW);
end

% ════════════════════════════════════════════════════════════════════════
%  Prepare images
% ════════════════════════════════════════════════════════════════════════
imgD  = double(img);
tmplD = double(template);

% Zero-mean template
tmplMean = mean(tmplD(:));
tmplZ    = tmplD - tmplMean;
tmplStd  = std(tmplZ(:), 0);   % std with N-1 denominator

if tmplStd < eps
    warning('imaging:templateMatch:constantTemplate', ...
        'Template has near-zero variance; NCC will be unreliable.');
    tmplStd = eps;
end

nTmpl = numel(tmplD);   % N = h*w

% ════════════════════════════════════════════════════════════════════════
%  Compute cross-correlation via FFT
%  Template is zero-padded to image size; flip template for true correlation
%  (fft2-based xcorr2 uses conjugate in frequency domain = flipping in space)
% ════════════════════════════════════════════════════════════════════════
tmplPadded = zeros(imgH, imgW);
tmplPadded(1:tmplH, 1:tmplW) = tmplZ;

% Use FFT: xcorr = ifft2( FFT(img) .* conj(FFT(tmpl_padded)) )
% This computes the un-normalized cross-correlation at each shift.
xcorrFull = real(ifft2( fft2(imgD) .* conj(fft2(tmplPadded)) ));

% The peak of the raw cross-correlation lives at shift (tmplH-1, tmplW-1)
% from the top-left, corresponding to the top-left corner of the template
% aligning with that pixel.  We will convert to center coordinates later.

% ════════════════════════════════════════════════════════════════════════
%  Sliding-window local statistics via integral images
%  local_sum(r,c)   = sum of img pixels in the tmplH x tmplW window
%                     whose TOP-LEFT corner is at (r, c)
%  local_sum_sq(r,c) = sum of img^2 pixels in the same window
% ════════════════════════════════════════════════════════════════════════
imgSq = imgD .^ 2;

% Cumulative-sum integral image (padded with zeros on top and left)
cumI   = cumsum(cumsum(imgD,  1), 2);
cumISq = cumsum(cumsum(imgSq, 1), 2);

% Helper: integral image box sum for windows of size (tmplH x tmplW)
% top-left corners at rows 1..imgH-tmplH+1, cols 1..imgW-tmplW+1
r2 = tmplH : imgH;          % bottom row of window
c2 = tmplW : imgW;          % right  col of window
r1 = r2 - tmplH;            % row above top of window (0-indexed into cumI)
c1 = c2 - tmplW;

% Box sum using the 4-corner formula:
%   S(r2,c2) - S(r1,c2) - S(r2,c1) + S(r1,c1)
% where S(0,*) = S(*,0) = 0, handled by the cumsum padding trick below.
% We prepend a row/col of zeros to cumI for the r1=0 / c1=0 cases.
cumIPad   = [zeros(1, imgW+1); [zeros(imgH,1), cumI]];
cumISqPad = [zeros(1, imgW+1); [zeros(imgH,1), cumISq]];

localSum   = cumIPad(r2+1, c2+1) - cumIPad(r1+1, c2+1) ...
           - cumIPad(r2+1, c1+1) + cumIPad(r1+1, c1+1);

localSumSq = cumISqPad(r2+1, c2+1) - cumISqPad(r1+1, c2+1) ...
           - cumISqPad(r2+1, c1+1) + cumISqPad(r1+1, c1+1);

% Local variance: E[x^2] - E[x]^2;  clamp negatives from floating-point noise
localVar = localSumSq ./ nTmpl - (localSum ./ nTmpl) .^ 2;
localVar  = max(localVar, 0);
localStd  = sqrt(localVar);

% ════════════════════════════════════════════════════════════════════════
%  Build the valid NCC map
%  FFT xcorr at (r, c) (1-based) corresponds to the template top-left at
%  row (r - tmplH + 1), col (c - tmplW + 1) via the circular-shift property.
%  The valid region (no wrap-around) is rows 1..imgH-tmplH+1, cols 1..imgW-tmplW+1
%  which maps to xcorrFull rows tmplH..imgH, cols tmplW..imgW.
% ════════════════════════════════════════════════════════════════════════
xcorrValid = xcorrFull(tmplH:imgH, tmplW:imgW);

% Normalise
denom = localStd * (tmplStd * nTmpl);
denom(denom < eps) = eps;  % avoid divide-by-zero in flat regions

nccValid = xcorrValid ./ denom;
nccValid = max(-1, min(1, nccValid));  % clamp to [-1, 1] for numerical safety

% Embed the valid NCC map in a full-size map (edges = 0)
nccMap = zeros(imgH, imgW);
halfR  = floor(tmplH / 2);
halfC  = floor(tmplW / 2);
% Top-left corner of the valid region maps to the template center pixel.
% Shift the valid map so output nccMap(r,c) = NCC when template is centred at (r,c).
rowStart = 1 + halfR;
rowEnd   = rowStart + size(nccValid, 1) - 1;
colStart = 1 + halfC;
colEnd   = colStart + size(nccValid, 2) - 1;

% Clip to image bounds (safety)
rowEnd = min(rowEnd, imgH);
colEnd = min(colEnd, imgW);
nRows  = rowEnd - rowStart + 1;
nCols  = colEnd - colStart + 1;

nccMap(rowStart:rowEnd, colStart:colEnd) = nccValid(1:nRows, 1:nCols);

% ════════════════════════════════════════════════════════════════════════
%  Threshold
% ════════════════════════════════════════════════════════════════════════
aboveThresh = nccMap >= opts.Threshold;

if ~any(aboveThresh(:))
    result.locations  = zeros(0, 2);
    result.scores     = zeros(0, 1);
    result.nccMap     = nccMap;
    result.nMatches   = 0;
    result.threshold  = opts.Threshold;
    return
end

% Candidate pixel indices
[candRows, candCols] = find(aboveThresh);
candScores = nccMap(aboveThresh);

% Sort descending by score
[candScores, sortIdx] = sort(candScores, 'descend');
candRows = candRows(sortIdx);
candCols = candCols(sortIdx);

% ════════════════════════════════════════════════════════════════════════
%  Non-maximum suppression (greedy, descending score order)
% ════════════════════════════════════════════════════════════════════════
nCand   = numel(candScores);
kept    = false(nCand, 1);
minDist2 = minDist ^ 2;

for k = 1 : nCand
    if numel(find(kept)) >= opts.MaxMatches
        break
    end
    % Check distance to all already-kept peaks
    if any(kept)
        dr2 = (candRows(k) - candRows(kept)) .^ 2 + ...
              (candCols(k) - candCols(kept)) .^ 2;
        if any(dr2 < minDist2)
            continue  % too close to an existing match
        end
    end
    kept(k) = true;
end

% ════════════════════════════════════════════════════════════════════════
%  Assemble result
% ════════════════════════════════════════════════════════════════════════
result.locations  = [candRows(kept), candCols(kept)];
result.scores     = candScores(kept);
result.nccMap     = nccMap;
result.nMatches   = sum(kept);
result.threshold  = opts.Threshold;

end
