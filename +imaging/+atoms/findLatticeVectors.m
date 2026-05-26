function result = findLatticeVectors(positions, opts)
%FINDLATTICEVECTORS  Estimate the two primitive lattice vectors of a column set.
%
%   Syntax:
%       result = imaging.atoms.findLatticeVectors(positions)
%       result = imaging.atoms.findLatticeVectors(positions, Neighbors=6, ...
%                    MinAngleDeg=15)
%
%   From the cloud of column positions, collects nearest-neighbour
%   displacement vectors, folds them into a half-plane (so antiparallel
%   pairs merge), and picks the two shortest dominant non-collinear
%   directions as the primitive lattice vectors a1, a2. Pure base MATLAB
%   (no Statistics Toolbox); pairwise distances via the (a-b)^2 expansion.
%
%   Inputs:
%       positions — [N x 2] (x,y) column centers (>= 4 points).
%
%   Optional Name-Value:
%       Neighbors   — nearest neighbours sampled per point (default 6).
%       MinAngleDeg — minimum angle between a1 and a2 to count as
%                     non-collinear (default 15 deg).
%       MaxSample   — cap on query points for speed (default 400).
%
%   Output struct:
%       .a1, .a2   — [1 x 2] primitive lattice vectors (px).
%       .origin    — [1 x 2] lattice origin (centroid-nearest column).
%       .spacing   — median nearest-neighbour distance (px).
%       .valid     — logical; false if a lattice could not be resolved.

arguments
    positions               (:,2) double
    opts.Neighbors  (1,1) double {mustBePositive, mustBeInteger} = 6
    opts.MinAngleDeg (1,1) double {mustBePositive}               = 15
    opts.MaxSample  (1,1) double {mustBePositive, mustBeInteger} = 400
end

N = size(positions, 1);
result = struct('a1', [NaN NaN], 'a2', [NaN NaN], ...
    'origin', [NaN NaN], 'spacing', NaN, 'valid', false);
if N < 4, return; end

% ── Origin: the column nearest the centroid ──────────────────────────────
ctr = mean(positions, 1);
[~, iC] = min(sum((positions - ctr).^2, 2));
result.origin = positions(iC, :);

% ── Nearest-neighbour displacement vectors ───────────────────────────────
m = min(N, opts.MaxSample);
Q = positions(1:m, :);
P = positions;
D2 = sum(Q.^2, 2) - 2 * (Q * P') + sum(P.^2, 2)';
D2(D2 < 0) = 0;

vecs = zeros(m * opts.Neighbors, 2);
nnDist = zeros(m, 1);
cnt = 0;
for i = 1:m
    [ds, ord] = sort(D2(i, :), 'ascend');
    ord = ord(2:end); ds = ds(2:end);          % drop self
    kk = min(opts.Neighbors, numel(ord));
    if kk < 1, continue; end
    nnDist(i) = sqrt(ds(1));
    for j = 1:kk
        cnt = cnt + 1;
        vecs(cnt, :) = P(ord(j), :) - Q(i, :);
    end
end
vecs = vecs(1:cnt, :);
if cnt < 3, return; end

spacing = median(nnDist(nnDist > 0));
result.spacing = spacing;

% ── Keep short vectors, fold into the right half-plane ───────────────────
len = sqrt(sum(vecs.^2, 2));
keep = len > 0.3 * spacing & len < 1.8 * spacing;
vecs = vecs(keep, :);
if size(vecs, 1) < 3, return; end
flip = vecs(:,1) < 0 | (abs(vecs(:,1)) < 1e-9 & vecs(:,2) < 0);
vecs(flip, :) = -vecs(flip, :);
ang = atan2(vecs(:,2), vecs(:,1));               % in (-pi/2, pi/2]

% ── Dominant direction (histogram peak) -> a1 ────────────────────────────
nb = 36;
edges = linspace(-pi/2, pi/2, nb + 1);
h = histcounts(ang, edges);
[~, b1] = max(h);
c1 = (edges(b1) + edges(b1+1)) / 2;
tol = deg2rad(12);
sel1 = abs(angDiff(ang, c1)) <= tol;
if nnz(sel1) < 2, return; end
a1 = mean(vecs(sel1, :), 1);

% ── Next dominant direction non-collinear with a1 -> a2 ──────────────────
minSep = deg2rad(opts.MinAngleDeg);
far = abs(angDiff(ang, c1)) > minSep;
if nnz(far) < 2, return; end
h2 = histcounts(ang(far), edges);
[~, b2] = max(h2);
c2 = (edges(b2) + edges(b2+1)) / 2;
sel2 = far & (abs(angDiff(ang, c2)) <= tol);
if nnz(sel2) < 2, return; end
a2 = mean(vecs(sel2, :), 1);

% ── Sanity: non-degenerate basis ─────────────────────────────────────────
if abs(det([a1; a2])) < 1e-6 * spacing^2, return; end

result.a1 = a1;
result.a2 = a2;
result.valid = true;
end

% ────────────────────────────────────────────────────────────────────────
function d = angDiff(a, b)
%   Smallest signed difference between angles (mod pi, since vectors fold
%   into a half-plane and direction is defined mod 180 deg).
d = mod(a - b + pi/2, pi) - pi/2;
end
