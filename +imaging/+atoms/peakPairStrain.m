function result = peakPairStrain(positions, opts)
%PEAKPAIRSTRAIN  Real-space peak-pair-analysis strain from atom-column positions.
%
%   Syntax:
%       result = imaging.atoms.peakPairStrain(positions, RefVectors=[a1;a2], ...
%                    Origin=[x0 y0])
%       result = imaging.atoms.peakPairStrain(positions, RefRegion=[x y w h])
%
%   Indexes every column to its ideal site on a reference lattice, measures
%   the displacement from that site, then fits a local displacement gradient
%   per column to obtain the 2D strain tensor (exx, eyy, exy) and rigid
%   rotation. This is the real-space complement to FFT-based GPA — it works
%   directly from fitted column centers and resolves strain per column.
%
%   The reference (unstrained) lattice is either supplied (RefVectors +
%   Origin) or estimated from a sub-region of the columns (RefRegion); if
%   neither is given it is estimated from all columns (i.e. average lattice).
%
%   Inputs:
%       positions — [N x 2] (x,y) sub-pixel column centers.
%
%   Optional Name-Value:
%       RefVectors — [2 x 2] reference primitive vectors [a1; a2] (px).
%       Origin     — [1 x 2] lattice origin (px).
%       RefRegion  — [x y w h] rectangle; columns inside define the
%                    reference lattice (used when RefVectors not given).
%       Neighbors  — neighbours used for the local gradient fit (default 8).
%
%   Output struct:
%       .exx,.eyy,.exy — [N x 1] strain-tensor components (dimensionless).
%       .rotation      — [N x 1] rigid rotation (rad).
%       .displacement  — [N x 2] (ux,uy) displacement from the ideal site (px).
%       .indices       — [N x 2] integer (m,n) lattice indices.
%       .refVectors    — [2 x 2] reference vectors actually used.
%       .origin        — [1 x 2] origin actually used.
%       .valid         — logical; false if no reference lattice could be built.

arguments
    positions               (:,2) double
    opts.RefVectors (:,:) double = []
    opts.Origin     (:,:) double = []
    opts.RefRegion  (:,:) double = []
    opts.Neighbors  (1,1) double {mustBePositive, mustBeInteger} = 8
end

N = size(positions, 1);
nanv = nan(N, 1);
result = struct('exx', nanv, 'eyy', nanv, 'exy', nanv, 'rotation', nanv, ...
    'displacement', nan(N,2), 'indices', nan(N,2), ...
    'refVectors', nan(2,2), 'origin', [NaN NaN], 'valid', false);
if N < 4, return; end

% ── Establish the reference lattice ──────────────────────────────────────
if ~isempty(opts.RefVectors) && ~isempty(opts.Origin)
    B = [opts.RefVectors(1,:)', opts.RefVectors(2,:)'];   % columns a1,a2
    origin = opts.Origin(:)';
    refV = opts.RefVectors;
else
    refSrc = positions;
    if ~isempty(opts.RefRegion)
        r = opts.RefRegion;
        in = positions(:,1) >= r(1) & positions(:,1) <= r(1)+r(3) & ...
             positions(:,2) >= r(2) & positions(:,2) <= r(2)+r(4);
        if nnz(in) >= 4, refSrc = positions(in, :); end
    end
    lv = imaging.atoms.findLatticeVectors(refSrc);
    if ~lv.valid, return; end
    B = [lv.a1', lv.a2'];
    origin = lv.origin;
    refV = [lv.a1; lv.a2];
end
if abs(det(B)) < 1e-9, return; end

% ── Index each column and measure displacement from the ideal site ───────
frac = B \ (positions - origin)';     % 2 x N real lattice coords
idx  = round(frac);
ideal = origin + (B * idx)';          % N x 2 ideal positions
u = positions - ideal;                % N x 2 displacement

% ── Local displacement-gradient -> strain tensor per column ──────────────
D2 = sum(ideal.^2, 2) - 2 * (ideal * ideal') + sum(ideal.^2, 2)';
D2(D2 < 0) = 0;
K = opts.Neighbors;
exx = nanv; eyy = nanv; exy = nanv; rot = nanv;
for i = 1:N
    [~, ord] = sort(D2(i, :), 'ascend');
    kk = min(K + 1, numel(ord));          % include self
    nb = ord(1:kk);
    if kk < 4, continue; end
    dx = ideal(nb,1) - ideal(i,1);
    dy = ideal(nb,2) - ideal(i,2);
    A = [ones(kk,1), dx, dy];
    % Solve for the in-plane gradient of ux and uy.
    gx = A \ u(nb,1);    % [ux0; dux/dx; dux/dy]
    gy = A \ u(nb,2);    % [uy0; duy/dx; duy/dy]
    gxx = gx(2); gxy = gx(3);
    gyx = gy(2); gyy = gy(3);
    exx(i) = gxx;
    eyy(i) = gyy;
    exy(i) = 0.5 * (gxy + gyx);
    rot(i) = 0.5 * (gyx - gxy);
end

result.exx = exx;  result.eyy = eyy;  result.exy = exy;
result.rotation = rot;
result.displacement = u;
result.indices = idx';
result.refVectors = refV;
result.origin = origin;
result.valid = true;
end
