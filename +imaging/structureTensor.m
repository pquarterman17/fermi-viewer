function st = structureTensor(img, options)
%STRUCTURETENSOR  Local orientation and coherence from the structure tensor.
%
%   Syntax:
%       st = imaging.structureTensor(img)
%       st = imaging.structureTensor(img, Sigma=3.0)
%       st = imaging.structureTensor(img, Sigma=3.0, GradientSigma=1.0)
%
%   Computes the per-pixel 2-D structure (second-moment) tensor
%
%       J = G_sigma * [ Ix.^2   Ix.*Iy ;
%                       Ix.*Iy  Iy.^2  ]
%
%   where Ix, Iy are image gradients and G_sigma is Gaussian smoothing over
%   an integration window of scale Sigma. The closed-form 2x2 eigen-analysis
%   yields the dominant local orientation and an anisotropy (coherence)
%   measure. This is the orientation feature that separates grains of
%   similar BRIGHTNESS but different lattice ORIENTATION — the case plain
%   intensity thresholding cannot handle.
%
%   No Image Processing Toolbox required (gradients via base `gradient`,
%   smoothing via imaging.applyGaussian).
%
%   Inputs:
%       img            — [H x W] numeric matrix (grayscale).
%
%   Optional Name-Value:
%       Sigma          — integration-window scale in pixels for smoothing
%                        the tensor components (default 3.0, must be > 0).
%                        Larger = orientation averaged over a bigger
%                        neighbourhood (smoother, less local).
%       GradientSigma  — optional pre-smoothing of the image before taking
%                        gradients, in pixels (default 0 = none). Use a
%                        small value (~1) on noisy data.
%
%   Output: st — struct with [H x W] fields:
%       .orientation — dominant gradient orientation in radians, in
%                      (-pi/2, pi/2]. For an intensity wave varying along
%                      direction phi, .orientation == phi.
%       .coherence   — anisotropy in [0,1]: ((l1-l2)/(l1+l2))^2. 1 = strongly
%                      oriented (clear edge/lattice), 0 = isotropic (no
%                      preferred direction). Robust to overall contrast.
%       .lambda1     — larger eigenvalue (energy across the dominant direction).
%       .lambda2     — smaller eigenvalue (energy along it).
%       .energy      — lambda1 + lambda2 = local gradient energy (trace).
%
%   Example:
%       st = imaging.structureTensor(hrtemImg, Sigma=4);
%       grainBoundaries = st.coherence < 0.2;   % disordered / boundary
%
%   See also imaging.geometricPhaseAnalysis, imaging.applyGaussian,
%            imaging.grains.extractGrainFeatures

% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    img                   (:,:) {mustBeNumeric}
    options.Sigma         (1,1) double {mustBePositive}    = 3.0
    options.GradientSigma (1,1) double {mustBeNonnegative} = 0
end

d = double(img);
if options.GradientSigma > 0
    d = imaging.applyGaussian(d, Sigma=options.GradientSigma);
end

% ── Gradients (base MATLAB) ─────────────────────────────────────────────
% gradient returns [d/dx (cols), d/dy (rows)].
[Ix, Iy] = gradient(d);

% ── Tensor components, smoothed over the integration window ─────────────
Jxx = imaging.applyGaussian(Ix.^2,   Sigma=options.Sigma);
Jxy = imaging.applyGaussian(Ix .* Iy, Sigma=options.Sigma);
Jyy = imaging.applyGaussian(Iy.^2,   Sigma=options.Sigma);

% ── Closed-form 2x2 symmetric eigenvalues ───────────────────────────────
%   l1,2 = (Jxx+Jyy)/2 ± sqrt( ((Jxx-Jyy)/2)^2 + Jxy^2 )
trace2  = (Jxx + Jyy) / 2;
diff2   = (Jxx - Jyy) / 2;
rad     = sqrt(diff2.^2 + Jxy.^2);
lambda1 = trace2 + rad;     % larger eigenvalue
lambda2 = trace2 - rad;     % smaller eigenvalue

% ── Orientation and coherence ───────────────────────────────────────────
%   For I varying along direction phi: atan2(2*Jxy, Jxx-Jyy) = 2*phi.
orientation = 0.5 * atan2(2 * Jxy, Jxx - Jyy);
energy      = lambda1 + lambda2;
coherence   = ((lambda1 - lambda2) ./ (energy + eps)).^2;

st = struct( ...
    'orientation', orientation, ...
    'coherence',   coherence, ...
    'lambda1',     lambda1, ...
    'lambda2',     lambda2, ...
    'energy',      energy);
end
