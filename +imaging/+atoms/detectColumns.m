function result = detectColumns(img, opts)
%DETECTCOLUMNS  Detect atomic-column seed positions in an HR(S)TEM image.
%
%   Syntax:
%       result = imaging.atoms.detectColumns(img)
%       result = imaging.atoms.detectColumns(img, Sigma=2, Threshold=0.2, ...
%                    MinSeparation=8, Polarity="bright", MaxColumns=20000)
%
%   Gaussian pre-smooth -> 8-connected local-maximum detection -> intensity
%   threshold -> greedy non-maximum suppression. Returns integer-pixel seed
%   positions; refine to sub-pixel with imaging.atoms.fitGaussian2D. Same
%   pure-MATLAB detection technique as findDiffractionSpots, minus the
%   center-exclusion (atom columns fill the field of view).
%
%   No Image Processing Toolbox required.
%
%   Inputs:
%       img — [H x W] numeric image (real space, atomic resolution).
%
%   Optional Name-Value:
%       Sigma         — Gaussian pre-smooth sigma in px (default 2).
%       Threshold     — accept maxima >= Threshold*max(smoothed), in [0,1]
%                       (default 0.2).
%       MinSeparation — minimum px distance between accepted columns; the NMS
%                       radius. Set near the lattice spacing (default 8).
%       Polarity      — "bright" (default) for bright columns (HAADF-STEM),
%                       "dark" for dark columns (some HRTEM defocus).
%       MaxColumns    — cap on returned columns, strongest first (default 20000).
%
%   Output struct:
%       .positions    — [N x 2] (x,y) integer pixel coords (col,row).
%       .intensities  — [N x 1] smoothed intensity at each seed.
%       .polarity     — the polarity used (for the fitter / overlays).

% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    img                          (:,:) {mustBeNumeric}
    opts.Sigma         (1,1) double {mustBePositive}                 = 2
    opts.Threshold     (1,1) double {mustBeInRange(opts.Threshold,0,1)} = 0.2
    opts.MinSeparation (1,1) double {mustBePositive}                 = 8
    opts.Polarity      (1,1) string {mustBeMember(opts.Polarity, ["bright","dark"])} = "bright"
    opts.MaxColumns    (1,1) double {mustBePositive, mustBeInteger}  = 20000
end

work = double(img);
if opts.Polarity == "dark"
    work = -work;     % detect minima as maxima
end

% ── Gaussian pre-smooth (manual kernel) ─────────────────────────────────
% Use REPLICATE padding (not conv2's zero-pad 'same'): a dark-polarity image
% has a large DC offset, and zero-padding attenuates it near the borders,
% creating artificial bright rims that become spurious local maxima after
% negation. Replicate-pad + 'valid' eliminates that edge bias for both
% polarities.
hw = ceil(3 * opts.Sigma);
ax = -hw:hw;
[X, Y] = meshgrid(ax, ax);
kernel = exp(-0.5 * (X.^2 + Y.^2) / opts.Sigma^2);
kernel = kernel / sum(kernel(:));
[Hh, Ww] = size(work);
rows = [ones(1, hw), 1:Hh, Hh * ones(1, hw)];
cols = [ones(1, hw), 1:Ww, Ww * ones(1, hw)];
smoothed = conv2(work(rows, cols), kernel, 'valid');

% ── 8-connected local maxima ────────────────────────────────────────────
[nRows, nCols] = size(smoothed);
pad = -Inf(nRows + 2, nCols + 2);
pad(2:end-1, 2:end-1) = smoothed;
center = pad(2:end-1, 2:end-1);
isMax = true(nRows, nCols);
for dr = -1:1
    for dc = -1:1
        if dr == 0 && dc == 0, continue; end
        neighbour = pad((2+dr):(end-1+dr), (2+dc):(end-1+dc));
        isMax = isMax & (center >= neighbour);
    end
end

% ── Intensity threshold (relative to the smoothed dynamic range) ─────────
lo = min(smoothed(:));
hi = max(smoothed(:));
if hi <= lo
    result = emptyResult(opts.Polarity);
    return;
end
cut = lo + opts.Threshold * (hi - lo);
isMax = isMax & (smoothed >= cut);

[rowIdx, colIdx] = find(isMax);
if isempty(rowIdx)
    result = emptyResult(opts.Polarity);
    return;
end

% ── Greedy non-maximum suppression by MinSeparation ─────────────────────
intens = smoothed(sub2ind([nRows, nCols], rowIdx, colIdx));
[intens, ord] = sort(intens, 'descend');
rowIdx = rowIdx(ord);
colIdx = colIdx(ord);

minSep2 = opts.MinSeparation^2;
keep = false(numel(rowIdx), 1);
accR = zeros(numel(rowIdx), 1);
accC = zeros(numel(rowIdx), 1);
nAcc = 0;
for i = 1:numel(rowIdx)
    if nAcc == 0
        ok = true;
    else
        d2 = (accR(1:nAcc) - rowIdx(i)).^2 + (accC(1:nAcc) - colIdx(i)).^2;
        ok = all(d2 >= minSep2);
    end
    if ok
        nAcc = nAcc + 1;
        accR(nAcc) = rowIdx(i);
        accC(nAcc) = colIdx(i);
        keep(i) = true;
    end
    if nAcc >= opts.MaxColumns, break; end
end

rowIdx = rowIdx(keep);
colIdx = colIdx(keep);
intens = intens(keep);

result = struct( ...
    'positions',   [colIdx, rowIdx], ...   % (x, y)
    'intensities', intens, ...
    'polarity',    opts.Polarity);
end

% ────────────────────────────────────────────────────────────────────────
function r = emptyResult(polarity)
r = struct('positions', zeros(0,2), 'intensities', zeros(0,1), 'polarity', polarity);
end
