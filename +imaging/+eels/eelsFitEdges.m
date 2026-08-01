function result = eelsFitEdges(energyAxis, spectrum, edges, E0kV, betaMrad, opts)
%EELSFITEDGES  Model-based joint fit of background + multiple EELS edges.
%
%   Syntax:
%       result = imaging.eels.eelsFitEdges(energyAxis, spectrum, edges, ...
%                    E0kV, betaMrad)
%       result = imaging.eels.eelsFitEdges(..., FitWindow=[E1,E2])
%
%   Fits ONE model to the whole core-loss spectrum instead of the
%   sequential window-integration approach of imaging.eels.eelsQuantify:
%
%       spectrum(E) ~= A*E^(-r)  +  sum_X  a_X * dsigma_X/dE(E)
%
%   — a shared power-law background plus, per element, the hydrogenic
%   differential ionization cross-section shape
%   (imaging.eels.eelsEdgeShape) scaled by an amplitude a_X. Because each
%   shape already carries the cross-section magnitude (m^2/eV), the fitted
%   amplitudes are directly proportional to areal densities, so
%   at% = 100*a_X / sum(a). This resolves OVERLAPPING edges (e.g.
%   Mn-L23 / Fe-L23, rare-earth M edges) that window-integration
%   mis-assigns, and yields a per-amplitude 1-sigma error.
%
%   ALGORITHM (MATLAB built-ins only — no Optimization Toolbox):
%   For a FIXED background exponent r the model is LINEAR in
%   (A, a_1..a_n): one pinv-based least-squares solve on the design
%   matrix [E.^(-r), shape_1(E), ..., shape_n(E)] (pinv rather than
%   backslash so closely-spaced/OVERLAPPING edge shapes — the exact case
%   this fit targets — never trip a "rank deficient" warning). The outer 1-D search over r
%   (bounded to the physically-plausible EELS power-law range [0.5, 8])
%   uses fminbnd to minimise the residual sum of squares — a core-MATLAB
%   substitute for the Python port's joint nonlinear
%   scipy.optimize.least_squares fit. A log-log pre-edge polyfit (over
%   FitWindow) gives a seed estimate of r that is used only as a SANITY
%   CHECK (a warning is issued if the fitted r ends up far from it) — it
%   does not narrow fminbnd's search interval, so a bad seed can never
%   trap the bounded search in a spurious local result.
%
%   Negative amplitudes from the unconstrained pinv solve are
%   clamped to 0 and the affected columns are dropped for a single
%   re-solve — a simplified, ONE-PASS active-set approximation to
%   non-negative least squares (NOT iterated to full Lawson-Hanson KKT
%   convergence like MATLAB's lsqnonneg, and NOT the exact bound
%   enforcement scipy's trust-region fit gives the Python port). This is
%   the documented deviation the "MATLAB built-ins only" constraint
%   requires; it is adequate here because the edge shapes used in
%   practice are well-separated in energy and rarely need more than one
%   column dropped.
%
%   Per-amplitude 1-sigma errors come from the LINEAR sub-problem's
%   covariance at the optimal r: pinv(X'X)*reducedChi2, where X is the
%   same (M+1)-column design matrix used for the final solve. NOTE: r's
%   own uncertainty is NOT propagated into these errors — r is found by
%   an outer scalar search, not fitted jointly with the amplitudes — a
%   documented simplification relative to the Python port, which gets an
%   r uncertainty "for free" from one joint nonlinear covariance.
%
%   Inputs:
%       energyAxis — [N x 1] energy-loss axis (eV), strictly increasing
%       spectrum   — [N x 1] core-loss spectrum intensity (counts or cps)
%       edges      — struct array, one entry per edge to fit, fields:
%                       .element  char/string symbol (e.g. 'Fe')
%                       .shell    "K" or "L"
%                       .Z        atomic number
%                       .onsetEV  edge onset energy (eV)
%                     (same field contract as imaging.eels.eelsQuantify's
%                     `elements` input, minus the signal/background
%                     windows it needs but this joint model does not)
%       E0kV       — incident beam energy (kV)
%       betaMrad   — collection semi-angle (mrad)
%
%   Optional Name-Value:
%       FitWindow — [E1, E2] pre-edge window (eV) used ONLY to seed the
%                   sanity-check estimate of r via a log-log polyfit; the
%                   model fit itself always spans the full energyAxis.
%                   Default: [min(energyAxis), min(onset over edges)].
%
%   Outputs:
%       result — struct with fields:
%                  .element        [1 x M] string array of element symbols
%                  .atomicPercent  [1 x M] at%, sums to 100
%                  .amplitude      [1 x M] fitted areal-density proxies
%                  .amplitudeSigma [1 x M] 1-sigma errors (see ALGORITHM)
%                  .background     [N x 1] fitted power-law background
%                  .edgeCurves     [N x M] fitted per-edge contributions,
%                                  one COLUMN per edge (M trailing, as in
%                                  eelsQuantifyMap's [Ny,Nx,M] convention;
%                                  differs from the Python port's [M,N])
%                  .model          [N x 1] background + sum(edgeCurves,2)
%                  .r              fitted background power-law exponent
%                  .reducedChi2    reduced chi-squared of the fit
%                  .success        true if fminbnd's exit flag == 1
%
%   Examples:
%       el(1) = struct('element','O', 'shell',"K",'Z', 8,'onsetEV',532);
%       el(2) = struct('element','Fe','shell',"L",'Z',26,'onsetEV',708);
%       r = imaging.eels.eelsFitEdges(E, I, el, 200, 10);
%       fprintf('O: %.1f%%, Fe: %.1f%%\n', r.atomicPercent(1), r.atomicPercent(2));
%
%   See also imaging.eels.eelsEdgeShape, imaging.eels.eelsFitEdgesMap,
%            imaging.eels.eelsQuantify, imaging.eels.eelsCrossSection

% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    energyAxis (:,1) double {mustBeNonempty}
    spectrum   (:,1) double {mustBeNonempty}
    edges      (1,:) struct {mustBeNonempty}
    E0kV       (1,1) double {mustBePositive}
    betaMrad   (1,1) double {mustBePositive}
    opts.FitWindow (1,2) double = [NaN, NaN]
end

energyAxis = double(energyAxis(:));
spectrum   = double(spectrum(:));

if numel(energyAxis) ~= numel(spectrum)
    error('imaging:eels:eelsFitEdges:sizeMismatch', ...
        'energyAxis and spectrum must have the same number of elements.');
end

reqFields = {'element','shell','Z','onsetEV'};
for f = reqFields
    if ~isfield(edges, f{1})
        error('imaging:eels:eelsFitEdges:missingField', ...
            'edges struct is missing required field "%s".', f{1});
    end
end

M      = numel(edges);
nE     = numel(energyAxis);
epsVal = eps;

% ════════════════════════════════════════════════════════════════════════
%  Pre-compute the (unscaled) edge shapes on the data grid — independent
%  of r, so this happens ONCE outside the r-search below.
% ════════════════════════════════════════════════════════════════════════
symList = strings(1, M);
edgeRaw = zeros(nE, M);
onsets  = zeros(1, M);
for k = 1:M
    el = edges(k);
    fn = imaging.eels.eelsEdgeShape( ...
        double(el.Z), string(el.shell), E0kV, betaMrad, double(el.onsetEV));
    edgeRaw(:, k) = fn(energyAxis);
    symList(k)    = string(el.element);
    onsets(k)     = double(el.onsetEV);
end

peaks      = max(edgeRaw, [], 1);
validPeaks = peaks(peaks > 0);
if isempty(validPeaks)
    scale = 1;
else
    scale = 1 / max(validPeaks);
end
edgeCols = scale * edgeRaw;                 % [nE x M], fixed for every r

% ════════════════════════════════════════════════════════════════════════
%  Seed + sanity-check r from a log-log pre-edge polyfit (see ALGORITHM
%  above — deliberately NOT used to narrow fminbnd's search interval).
% ════════════════════════════════════════════════════════════════════════
firstOnset = min(onsets);
if any(isnan(opts.FitWindow))
    opts.FitWindow = [max(min(energyAxis), 0), firstOnset];
end
preMask = energyAxis > 0 & energyAxis >= opts.FitWindow(1) & ...
          energyAxis <= opts.FitWindow(2) & spectrum > 0;
if sum(preMask) >= 2
    seedCoeffs = polyfit(log(energyAxis(preMask)), log(spectrum(preMask)), 1);
    rSeed = -seedCoeffs(1);
else
    rSeed = 3.0;
end

% ════════════════════════════════════════════════════════════════════════
%  Outer 1-D search over r (fminbnd — core MATLAB, no Optimization
%  Toolbox). For each trial r the model is LINEAR; solve it and return
%  the residual sum of squares as the objective.
% ════════════════════════════════════════════════════════════════════════
Eguard = max(energyAxis, epsVal);
objFun = @(r) rssAtR(r, Eguard, edgeCols, spectrum);
[rHat, ~, exitFlag] = fminbnd(objFun, 0.5, 8);

if isfinite(rSeed) && abs(rHat - rSeed) > 3
    warning('imaging:eels:eelsFitEdges:rSeedMismatch', ...
        ['Fitted background exponent r=%.2f differs substantially from ' ...
         'the pre-edge seed estimate r0=%.2f; check FitWindow / the data.'], ...
        rHat, rSeed);
end

% ════════════════════════════════════════════════════════════════════════
%  Final linear solve at the optimal r
% ════════════════════════════════════════════════════════════════════════
design = [Eguard .^ (-rHat), edgeCols];      % [nE x (M+1)]
coeffs = solveNonNegativeLite(design, spectrum);

bgAmp  = coeffs(1);
ampVec = coeffs(2:end);                      % [M x 1]

background = bgAmp * Eguard .^ (-rHat);      % [nE x 1]
edgeCurves = edgeCols .* ampVec';            % [nE x M]
model      = background + sum(edgeCurves, 2);% [nE x 1] — exact decomposition

resid       = model - spectrum;
nParam      = M + 1;
dof         = max(nE - nParam, 1);
sse         = sum(resid .^ 2);
reducedChi2 = sse / dof;

covFull        = pinv(design' * design) * reducedChi2;
sigAll         = sqrt(max(diag(covFull), 0));
amplitudeSigma = sigAll(2:end)';             % [1 x M]

total = sum(ampVec);
if total > 0
    atomicPercent = 100 * ampVec' / total;
else
    atomicPercent = zeros(1, M);
end

result = struct( ...
    'element',        symList, ...
    'atomicPercent',  atomicPercent, ...
    'amplitude',      ampVec', ...
    'amplitudeSigma', amplitudeSigma, ...
    'background',     background, ...
    'edgeCurves',     edgeCurves, ...
    'model',          model, ...
    'r',              rHat, ...
    'reducedChi2',    reducedChi2, ...
    'success',        exitFlag == 1);

end


% ════════════════════════════════════════════════════════════════════════
%  Local functions
% ════════════════════════════════════════════════════════════════════════
function rss = rssAtR(r, Eguard, edgeCols, spectrum)
%RSSATR  Residual sum of squares of the linear (fixed-r) sub-problem.
%   Objective function for fminbnd's outer search over the background
%   exponent r (see imaging.eels.eelsFitEdges's ALGORITHM note).
    design = [Eguard .^ (-r), edgeCols];
    coeffs = solveNonNegativeLite(design, spectrum);
    model  = design * coeffs;
    rss    = sum((model - spectrum) .^ 2);
end

function coeffs = solveNonNegativeLite(design, y)
%SOLVENONNEGATIVELITE  pinv least-squares + a single active-set re-solve,
%   approximating a non-negative fit without the Optimization Toolbox (no
%   lsqnonneg/lsqlin dependency). Any negative coefficient from the
%   unconstrained solve is clamped to 0 and its column dropped; the
%   remaining columns are re-solved once. This is a ONE-PASS
%   approximation, not iterated to full Lawson-Hanson NNLS convergence —
%   see the ALGORITHM note in imaging.eels.eelsFitEdges.
%   pinv (not backslash) throughout: closely-spaced (OVERLAPPING) edge
%   shapes — the exact case this fit targets — routinely leave the
%   design matrix, or the reduced matrix after a column is dropped,
%   near-collinear at some trial r. pinv gives the stable minimum-norm
%   least-squares solution there instead of backslash's noisy "rank
%   deficient" warning, with an identical result whenever the matrix is
%   well-conditioned.
    coeffs = pinv(design) * y;
    neg = coeffs < 0;
    if any(neg)
        coeffs(neg) = 0;
        keepIdx = find(~neg);
        if ~isempty(keepIdx)
            sub = pinv(design(:, keepIdx)) * y;
            sub(sub < 0) = 0;
            coeffs(keepIdx) = sub;
        end
    end
end
