function result = eelsFitEdgesMap(cube, energyAxis, edges, E0kV, betaMrad, opts)
%EELSFITEDGESMAP  Per-pixel model-based multi-edge EELS fit over an SI cube.
%
%   Syntax:
%       result = imaging.eels.eelsFitEdgesMap(cube, energyAxis, edges, ...
%                    E0kV, betaMrad)
%       result = imaging.eels.eelsFitEdgesMap(..., FitWindow=[E1,E2])
%
%   Spectrum-image (SI) companion to imaging.eels.eelsFitEdges. Fits the
%   SUMMED spectrum (over all Ny*Nx pixels) with the full nonlinear-in-r
%   joint model ONCE via imaging.eels.eelsFitEdges, then FIXES the
%   background exponent r from that fit. With r fixed, the per-pixel model
%
%       spectrum_px(E) ~= A_px*E^(-r)  +  sum_X a_X,px * dsigma_X/dE(E)
%
%   is LINEAR in (A_px, a_1,px .. a_n,px) for every pixel simultaneously,
%   so the whole cube is solved with ONE multi-right-hand-side backslash
%   ([nE x (1+M)] design against [nE x Ny*Nx] data) — no per-pixel loop,
%   mirroring the vectorisation budget of imaging.eels.eelsQuantifyMap.
%
%   Negative edge amplitudes are clamped to 0 (unlike
%   imaging.eels.eelsFitEdges' scalar path, there is NO active-set
%   re-solve here: with Ny*Nx independent right-hand sides, a per-pixel
%   active set would force a loop over pixels, defeating the point of the
%   vectorised solve. A plain clamp is the same simplification the Python
%   port's fit_edges_map uses). The background amplitude row is left
%   unclamped, also matching the Python port.
%
%   Inputs:
%       cube       — [Ny x Nx x nE] spectrum image (any numeric type)
%       energyAxis — [nE x 1] energy-loss axis (eV), strictly increasing
%       edges      — struct array, same field contract as
%                    imaging.eels.eelsFitEdges (.element, .shell, .Z,
%                    .onsetEV)
%       E0kV       — incident beam energy (kV)
%       betaMrad   — collection semi-angle (mrad)
%
%   Optional Name-Value:
%       FitWindow — forwarded to the one summed-spectrum
%                   imaging.eels.eelsFitEdges call (pre-edge window for
%                   its r sanity-check seed).
%
%   Outputs:
%       result — struct with fields:
%                  .element             [1 x M] element symbols
%                  .atomicPercent       [Ny x Nx x M] at% maps (each pixel
%                                       sums to 100, or all-zero if the
%                                       pixel has no positive edge signal)
%                  .amplitude           [Ny x Nx x M] fitted edge
%                                       amplitude maps (clamped >= 0)
%                  .backgroundAmplitude [Ny x Nx] fitted background
%                                       amplitude map (NOT clamped)
%                  .r                   background exponent, FIXED across
%                                       every pixel (from the summed fit)
%
%   Examples:
%       el(1) = struct('element','O', 'shell',"K",'Z', 8,'onsetEV',532);
%       el(2) = struct('element','Fe','shell',"L",'Z',26,'onsetEV',708);
%       r = imaging.eels.eelsFitEdgesMap(cube, E, el, 200, 10);
%       imagesc(r.atomicPercent(:,:,1)); colorbar;
%       title(sprintf('%s at%%', r.element(1)));
%
%   See also imaging.eels.eelsFitEdges, imaging.eels.eelsEdgeShape,
%            imaging.eels.eelsQuantifyMap

% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    cube       (:,:,:) {mustBeNumeric, mustBeNonempty}
    energyAxis (:,1) double {mustBeNonempty}
    edges      (1,:) struct {mustBeNonempty}
    E0kV       (1,1) double {mustBePositive}
    betaMrad   (1,1) double {mustBePositive}
    opts.FitWindow (1,2) double = [NaN, NaN]
end

[Ny, Nx, nE] = size(cube);
energyAxis = double(energyAxis(:));

if numel(energyAxis) ~= nE
    error('imaging:eels:eelsFitEdgesMap:sizeMismatch', ...
        'energyAxis length (%d) must match cube third dimension (%d).', ...
        numel(energyAxis), nE);
end

reqFields = {'element','shell','Z','onsetEV'};
for f = reqFields
    if ~isfield(edges, f{1})
        error('imaging:eels:eelsFitEdgesMap:missingField', ...
            'edges struct is missing required field "%s".', f{1});
    end
end

M  = numel(edges);
Np = Ny * Nx;

% ════════════════════════════════════════════════════════════════════════
%  1) Fix r from the summed spectrum — the one nonlinear-in-r fit.
% ════════════════════════════════════════════════════════════════════════
specMat = reshape(permute(double(cube), [3 1 2]), nE, Np);   % [nE x Np]
summed  = sum(specMat, 2);                                    % [nE x 1]

sumFit = imaging.eels.eelsFitEdges(energyAxis, summed, edges, E0kV, betaMrad, ...
    FitWindow=opts.FitWindow);
r = sumFit.r;

% ════════════════════════════════════════════════════════════════════════
%  2) Build the fixed-r LINEAR design matrix (same conditioning scale as
%     eelsFitEdges: divide by the largest raw shape peak so the fitted
%     amplitudes stay well scaled; this common factor cancels in at%).
% ════════════════════════════════════════════════════════════════════════
symList = strings(1, M);
edgeRaw = zeros(nE, M);
for k = 1:M
    el = edges(k);
    fn = imaging.eels.eelsEdgeShape( ...
        double(el.Z), string(el.shell), E0kV, betaMrad, double(el.onsetEV));
    edgeRaw(:, k) = fn(energyAxis);
    symList(k)    = string(el.element);
end
peaks      = max(edgeRaw, [], 1);
validPeaks = peaks(peaks > 0);
if isempty(validPeaks)
    scale = 1;
else
    scale = 1 / max(validPeaks);
end
edgeCols = scale * edgeRaw;                    % [nE x M]

Eguard = max(energyAxis, eps);
design = [Eguard .^ (-r), edgeCols];           % [nE x (M+1)]

% ════════════════════════════════════════════════════════════════════════
%  3) ONE multi-right-hand-side backslash solve for every pixel at once.
% ════════════════════════════════════════════════════════════════════════
coeffs   = design \ specMat;                   % [(M+1) x Np]
bgAmpMap = coeffs(1, :);                       % [1 x Np] — not clamped (matches the Python port)
ampMap   = max(coeffs(2:end, :), 0);           % [M x Np] — clamp negatives

total = sum(ampMap, 1);                        % [1 x Np]
atPct = zeros(M, Np);
has   = total > 0;
atPct(:, has) = 100 * ampMap(:, has) ./ total(has);

% Reshape [M x Np] -> [Ny x Nx x M] (columns of specMat follow the same
% column-major pixel order the cube was flattened in, so this reshape is
% the exact inverse — mirrors imaging.eels.eelsQuantifyMap's toMaps).
toMaps = @(m) reshape(m.', Ny, Nx, M);

result = struct( ...
    'element',             symList, ...
    'atomicPercent',       toMaps(atPct), ...
    'amplitude',           toMaps(ampMap), ...
    'backgroundAmplitude', reshape(bgAmpMap, Ny, Nx), ...
    'r',                   r);

end
