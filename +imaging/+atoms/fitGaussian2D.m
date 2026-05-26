function result = fitGaussian2D(img, seeds, opts)
%FITGAUSSIAN2D  Sub-pixel atom-column refinement via 2D-Gaussian fitting.
%
%   Syntax:
%       result = imaging.atoms.fitGaussian2D(img, seeds)
%       result = imaging.atoms.fitGaussian2D(img, seeds, WinRadius=6, ...
%                    Polarity="bright", MaxIter=40)
%
%   Fits a rotated elliptical 2D Gaussian to a local window around each seed
%   position by hand-rolled Levenberg-Marquardt least squares (no
%   Optimization Toolbox). Returns sub-pixel column centers plus shape
%   parameters and a per-column fit quality (R^2).
%
%   Model (7 params): f(x,y) = bg + A*exp(-0.5*(xr^2/sx^2 + yr^2/sy^2))
%       where [xr;yr] = R(theta) * [x-x0; y-y0].
%
%   Inputs:
%       img   — [H x W] numeric image (same image passed to detectColumns).
%       seeds — [N x 2] (x,y) integer seed positions.
%
%   Optional Name-Value:
%       WinRadius — half-size of the fit window in px (default 6). Use
%                   ~0.4*lattice spacing so neighbours don't pollute the fit.
%       Polarity  — "bright" (default) or "dark"; dark fits on the negated
%                   image so columns are positive peaks.
%       MaxIter   — max LM iterations per column (default 40).
%
%   Output struct:
%       .positions — [N x 2] sub-pixel (x,y) centers (seed kept if fit fails).
%       .amplitude — [N x 1] fitted A.
%       .sigma     — [N x 2] fitted (sx, sy) in px.
%       .theta     — [N x 1] orientation (rad).
%       .background— [N x 1] fitted bg.
%       .rsquared  — [N x 1] coefficient of determination (fit quality).
%       .converged — [N x 1] logical, true if the fit stayed in-window.

% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    img                       (:,:) {mustBeNumeric}
    seeds                     (:,2) double
    opts.WinRadius (1,1) double {mustBePositive, mustBeInteger} = 6
    opts.Polarity  (1,1) string {mustBeMember(opts.Polarity, ["bright","dark"])} = "bright"
    opts.MaxIter   (1,1) double {mustBePositive, mustBeInteger} = 40
end

work = double(img);
if opts.Polarity == "dark"
    work = -work;
end
[H, W] = size(work);
N = size(seeds, 1);
R = opts.WinRadius;

positions = seeds;
amplitude = zeros(N, 1);
sigma     = zeros(N, 2);
theta     = zeros(N, 1);
background = zeros(N, 1);
rsquared  = zeros(N, 1);
converged = false(N, 1);

for k = 1:N
    sx0 = seeds(k, 1);  sy0 = seeds(k, 2);
    c0 = round(sx0);    r0 = round(sy0);

    cLo = max(1, c0 - R);  cHi = min(W, c0 + R);
    rLo = max(1, r0 - R);  rHi = min(H, r0 + R);
    if (cHi - cLo) < 2 || (rHi - rLo) < 2
        continue;   % too close to the edge to fit; keep seed
    end

    [XX, YY] = meshgrid(cLo:cHi, rLo:rHi);
    Z = work(rLo:rHi, cLo:cHi);
    xv = XX(:);  yv = YY(:);  zv = Z(:);

    % ── Initial guess ──────────────────────────────────────────────────
    bg0  = min(zv);
    amp0 = max(zv) - bg0;
    if amp0 <= 0, continue; end
    p = [amp0, sx0, sy0, max(1.0, R/3), max(1.0, R/3), 0, bg0];

    % ── Levenberg-Marquardt (numerical Jacobian, ridge-regularised) ──────
    lambda = 1e-2;
    [fModel, ok] = gaussModel(p, xv, yv);
    if ~ok, continue; end
    err = zv - fModel;
    cost = err' * err;

    for it = 1:opts.MaxIter
        J = numJacobian(p, xv, yv);
        if isempty(J), break; end
        JtJ = J' * J;
        Jte = J' * err;
        % Ridge keeps the normal-equation matrix non-singular when a
        % parameter is locally unidentifiable (e.g. theta on a near-circular
        % column, where its Jacobian column is ~0) — avoids spurious
        % "matrix close to singular" warnings without perturbing the fit.
        ridge = 1e-9 * max([diag(JtJ); 1]);
        stepTaken = false; smallStep = false;   % NB: not 'converged' — that
        for tries = 1:6                          % name is the output array.
            H_ = JtJ + lambda * diag(diag(JtJ)) + ridge * eye(numel(p));
            dp = (H_ \ Jte)';
            pNew = clampParams(p + dp);
            [fNew, okNew] = gaussModel(pNew, xv, yv);
            if okNew
                errNew = zv - fNew;
                costNew = errNew' * errNew;
                if costNew < cost
                    smallStep = (cost - costNew) < 1e-6 * cost;
                    p = pNew; err = errNew; cost = costNew;
                    lambda = max(lambda / 3, 1e-9);
                    stepTaken = true;
                    break;
                end
            end
            lambda = min(lambda * 4, 1e9);
        end
        if ~stepTaken || smallStep, break; end
    end

    % ── Accept only if the center stayed inside the window ───────────────
    inWin = p(2) >= cLo - 0.5 && p(2) <= cHi + 0.5 && ...
            p(3) >= rLo - 0.5 && p(3) <= rHi + 0.5;
    ssTot = sum((zv - mean(zv)).^2);
    r2 = 1; if ssTot > 0, r2 = 1 - (err' * err) / ssTot; end

    if inWin && isfinite(p(2)) && isfinite(p(3))
        positions(k, :) = [p(2), p(3)];
        converged(k) = true;
    end
    amplitude(k) = p(1);
    sigma(k, :)  = abs(p(4:5));
    theta(k)     = p(6);
    background(k)= p(7);
    rsquared(k)  = r2;
end

result = struct( ...
    'positions',  positions, ...
    'amplitude',  amplitude, ...
    'sigma',      sigma, ...
    'theta',      theta, ...
    'background', background, ...
    'rsquared',   rsquared, ...
    'converged',  converged);
end

% ────────────────────────────────────────────────────────────────────────
function [f, ok] = gaussModel(p, x, y)
%   p = [A x0 y0 sx sy theta bg]
A = p(1); x0 = p(2); y0 = p(3); sx = p(4); sy = p(5); th = p(6); bg = p(7);
ok = sx > 0 && sy > 0 && isfinite(A) && isfinite(x0) && isfinite(y0);
if ~ok, f = []; return; end
ct = cos(th); st = sin(th);
dx = x - x0;  dy = y - y0;
xr =  ct .* dx + st .* dy;
yr = -st .* dx + ct .* dy;
f = bg + A .* exp(-0.5 * (xr.^2 ./ sx^2 + yr.^2 ./ sy^2));
end

% ────────────────────────────────────────────────────────────────────────
function J = numJacobian(p, x, y)
%   Forward-difference Jacobian of the model wrt each parameter.
[f0, ok] = gaussModel(p, x, y);
if ~ok, J = []; return; end
np = numel(p);
J = zeros(numel(x), np);
step = max(abs(p) * 1e-4, 1e-6);
for j = 1:np
    pp = p; pp(j) = pp(j) + step(j);
    [fj, okj] = gaussModel(pp, x, y);
    if ~okj, J = []; return; end
    J(:, j) = (fj - f0) / step(j);
end
end

% ────────────────────────────────────────────────────────────────────────
function p = clampParams(p)
%   Keep widths positive and finite; wrap theta to a sane range.
p(4) = max(abs(p(4)), 0.3);
p(5) = max(abs(p(5)), 0.3);
if ~isfinite(p(6)), p(6) = 0; end
end
