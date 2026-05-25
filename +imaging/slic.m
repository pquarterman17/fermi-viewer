function [labels, centers] = slic(img, options)
%SLIC  Simple Linear Iterative Clustering superpixels (grayscale, base MATLAB).
%
%   Syntax:
%       labels = imaging.slic(img)
%       [labels, centers] = imaging.slic(img, NumSuperpixels=300, Compactness=12)
%
%   Partitions a grayscale image into ~NumSuperpixels compact, boundary-
%   adhering regions by k-means in a combined (intensity, x, y) space
%   restricted to a local search window (the SLIC speed-up). Cluster centers
%   are seeded on a regular grid, so the result is DETERMINISTIC — no RNG.
%
%   Superpixels are a pre-segmentation: downstream clustering then operates
%   on a few hundred superpixels instead of millions of pixels (big speed-up
%   on large images) and respects superpixel borders, which tend to follow
%   real image edges. See imaging.grains.segmentAuto's Superpixels option.
%
%   No Image Processing Toolbox required.
%
%   Inputs:
%       img            — [H x W] numeric grayscale image.
%
%   Optional Name-Value:
%       NumSuperpixels — target number of superpixels (default 200). The
%                        actual count is close but not exact (grid rounding).
%       Compactness    — spatial-vs-intensity weight (default 10). Higher →
%                        more compact/square superpixels; lower → tighter
%                        adherence to intensity edges.
%       MaxIter        — Lloyd iterations (default 10).
%
%   Outputs:
%       labels         — [H x W] superpixel label map (1..M, no zeros).
%       centers        — [M x 3] final centers [row, col, intensity].
%
%   See also imaging.grains.segmentAuto, imaging.ml.kmeansLite

arguments
    img                   (:,:) {mustBeNumeric}
    options.NumSuperpixels(1,1) double {mustBePositive, mustBeInteger} = 200
    options.Compactness   (1,1) double {mustBePositive} = 10
    options.MaxIter       (1,1) double {mustBePositive, mustBeInteger} = 10
end

I = double(img);
lo = min(I(:)); hi = max(I(:));
if hi > lo
    I = (I - lo) / (hi - lo);     % normalize intensity to [0,1]
else
    I = zeros(size(I));
end
[H, W] = size(I);
N = H * W;

% ── Grid seeding ─────────────────────────────────────────────────────────
S = max(1, round(sqrt(N / options.NumSuperpixels)));   % grid step
gr = round(S/2):S:H;
gc = round(S/2):S:W;
if isempty(gr), gr = round(H/2); end
if isempty(gc), gc = round(W/2); end
[GC, GR] = meshgrid(gc, gr);
cr = GR(:); cc = GC(:);
ci = I(sub2ind([H, W], cr, cc));
K  = numel(cr);

m2 = (options.Compactness / S)^2;   % spatial weight in the distance metric

[XX, YY] = meshgrid(1:W, 1:H);      % per-pixel coordinates

labels = zeros(H, W);

% ── Lloyd iterations over local windows ─────────────────────────────────
for it = 1:options.MaxIter
    D = inf(H, W);
    labels(:) = 0;
    for k = 1:K
        r0 = max(1, cr(k)-S); r1 = min(H, cr(k)+S);
        c0 = max(1, cc(k)-S); c1 = min(W, cc(k)+S);
        rows = r0:r1; cols = c0:c1;

        patchI = I(rows, cols);
        patchX = XX(rows, cols);
        patchY = YY(rows, cols);

        dIntensity = (patchI - ci(k)).^2;
        dSpatial   = (patchX - cc(k)).^2 + (patchY - cr(k)).^2;
        dist = dIntensity + m2 * dSpatial;

        win = D(rows, cols);
        upd = dist < win;
        win(upd) = dist(upd);
        D(rows, cols) = win;

        lwin = labels(rows, cols);
        lwin(upd) = k;
        labels(rows, cols) = lwin;
    end

    % Any pixel never reached (sparse seeding) → nearest center fallback.
    miss = labels == 0;
    if any(miss(:))
        idx = find(miss);
        for j = idx'
            dd = (cr - YY(j)).^2 + (cc - XX(j)).^2;
            [~, kbest] = min(dd);
            labels(j) = kbest;
        end
    end

    % Update centers to the mean of their members.
    cnt = accumarray(labels(:), 1, [K 1]);
    cnt = max(cnt, 1);
    cr  = round(accumarray(labels(:), YY(:), [K 1]) ./ cnt);
    cc  = round(accumarray(labels(:), XX(:), [K 1]) ./ cnt);
    cr  = min(max(cr, 1), H);
    cc  = min(max(cc, 1), W);
    ci  = accumarray(labels(:), I(:), [K 1]) ./ cnt;
end

% ── Compact relabel (drop any empty centers) ────────────────────────────
present = unique(labels(:));
remap = zeros(max(present), 1);
remap(present) = 1:numel(present);
labels = remap(labels);

centers = [cr, cc, ci];
centers = centers(present, :);
end
