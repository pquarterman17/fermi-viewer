function result = eelsSVD(cube, energyAxis, opts)
%EELSSVD  SVD decomposition of an EELS spectrum image cube.
%
%   Syntax:
%       result = imaging.eelsSVD(cube, energyAxis)
%       result = imaging.eelsSVD(cube, energyAxis, NumComponents=5)
%       result = imaging.eelsSVD(cube, energyAxis, Denoise=true)
%
%   Performs Singular Value Decomposition on a spectrum image datacube
%   for multivariate statistical analysis (MSA).  The [Ny × Nx × nE]
%   cube is reshaped to [nPixels × nE], centred, and decomposed via
%   economy SVD.  Principal spectra (eigenspectra) and spatial score
%   maps (eigenimages) reveal the dominant spectral components without
%   requiring manual window selection.
%
%   Inputs:
%       cube       — [Ny × Nx × nE] spectrum image (any numeric type)
%       energyAxis — [nE × 1] energy-loss axis (eV)
%
%   Optional Name-Value:
%       NumComponents — number of components to keep (default: min(20, nE, nPixels))
%       Denoise       — logical; if true, reconstruct a denoised cube from
%                       the top-k components (default: false)
%       Center        — logical; subtract the mean spectrum before SVD
%                       (default: true — standard for MSA)
%
%   Outputs (struct):
%       .eigenspectra  — [nE × k] principal spectra (columns are spectral
%                        components, ordered by decreasing variance)
%       .scoreMaps     — [Ny × Nx × k] spatial weight maps (eigenimages)
%       .singularValues — [k × 1] singular values
%       .explained     — [k × 1] percent variance explained by each component
%       .cumulative    — [k × 1] cumulative percent variance
%       .meanSpectrum  — [nE × 1] mean spectrum subtracted (zeros if Center=false)
%       .Ny, .Nx, .nE  — original cube dimensions
%       .energyAxis    — copy of the energy axis
%       .denoisedCube  — [Ny × Nx × nE] reconstructed cube (only if Denoise=true)
%
%   Examples:
%       % Decompose a spectrum image
%       res = imaging.eelsSVD(cube, E, NumComponents=5);
%       % Scree plot
%       bar(res.explained); xlabel('Component'); ylabel('Variance (%)');
%       % First eigenimage
%       imagesc(res.scoreMaps(:,:,1)); axis image; colorbar;
%       % First eigenspectrum
%       plot(res.energyAxis, res.eigenspectra(:,1));
%       % Denoise and replace cube
%       res = imaging.eelsSVD(cube, E, NumComponents=3, Denoise=true);
%       cube = res.denoisedCube;
%
%   See also imaging.eelsExtractMap, imaging.eelsBackground,
%            utilities.pcaAnalysis

% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    cube         (:,:,:) {mustBeNumeric, mustBeNonempty}
    energyAxis   (:,1)   double {mustBeNonempty}
    opts.NumComponents (1,1) double {mustBeNonnegative, mustBeInteger} = 0
    opts.Denoise       (1,1) logical = false
    opts.Center        (1,1) logical = true
end

[Ny, Nx, nE] = size(cube);
nPixels = Ny * Nx;

if numel(energyAxis) ~= nE
    error('imaging:eelsSVD:sizeMismatch', ...
        'energyAxis length (%d) must match cube third dimension (%d).', ...
        numel(energyAxis), nE);
end

if nPixels < 2
    error('imaging:eelsSVD:tooFewPixels', ...
        'Need at least 2 spatial pixels, got %d.', nPixels);
end

% ════════════════════════════════════════════════════════════════════════
%  Reshape cube to 2D matrix [nPixels × nE]
% ════════════════════════════════════════════════════════════════════════
A = double(reshape(cube, nPixels, nE));

% ════════════════════════════════════════════════════════════════════════
%  Center (subtract mean spectrum)
% ════════════════════════════════════════════════════════════════════════
if opts.Center
    meanSpec = mean(A, 1);  % [1 × nE]
    Ac = A - meanSpec;
else
    meanSpec = zeros(1, nE);
    Ac = A;
end

% ════════════════════════════════════════════════════════════════════════
%  SVD — economy decomposition
% ════════════════════════════════════════════════════════════════════════
[U, S, V] = svd(Ac, 'econ');
sv = diag(S);

% Determine number of components to keep
kMax = min(nPixels, nE);
if opts.NumComponents > 0
    k = min(opts.NumComponents, kMax);
else
    k = min(20, kMax);  % default: up to 20
end

% Truncate
sv = sv(1:k);
U  = U(:, 1:k);
V  = V(:, 1:k);

% ════════════════════════════════════════════════════════════════════════
%  Sign convention — largest-magnitude element of each eigenspectrum
%  is positive (reproducible across platforms)
% ════════════════════════════════════════════════════════════════════════
for j = 1:k
    [~, maxIdx] = max(abs(V(:,j)));
    if V(maxIdx, j) < 0
        V(:,j) = -V(:,j);
        U(:,j) = -U(:,j);
    end
end

% ════════════════════════════════════════════════════════════════════════
%  Compute explained variance
% ════════════════════════════════════════════════════════════════════════
totalVar  = sum(diag(S).^2);
explained = 100 * sv.^2 / totalVar;
cumulative = cumsum(explained);

% ════════════════════════════════════════════════════════════════════════
%  Package results
% ════════════════════════════════════════════════════════════════════════
result.eigenspectra    = V;                           % [nE × k]
result.scoreMaps       = reshape(U .* sv', Ny, Nx, k); % [Ny × Nx × k]
result.singularValues  = sv;                           % [k × 1]
result.explained       = explained;                    % [k × 1]
result.cumulative      = cumulative;                   % [k × 1]
result.meanSpectrum    = meanSpec(:);                  % [nE × 1]
result.Ny              = Ny;
result.Nx              = Nx;
result.nE              = nE;
result.energyAxis      = energyAxis;

% ════════════════════════════════════════════════════════════════════════
%  Optional denoised cube reconstruction
% ════════════════════════════════════════════════════════════════════════
if opts.Denoise
    Arecon = (U .* sv') * V' + meanSpec;  % [nPixels × nE]
    result.denoisedCube = reshape(Arecon, Ny, Nx, nE);
else
    result.denoisedCube = [];
end

end
