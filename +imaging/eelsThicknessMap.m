function [tOverLambda, mask] = eelsThicknessMap(cube, energyAxis, opts)
%EELSTHICKNESSMAP  Log-ratio relative thickness from an EELS spectrum image.
%
%   Syntax:
%       [tOverLambda, mask] = imaging.eelsThicknessMap(cube, energyAxis)
%       [tOverLambda, mask] = imaging.eelsThicknessMap(cube, energyAxis, ...
%                                 ZLPWindow=[-5, 5], MinCounts=100)
%
%   Computes the Malis log-ratio estimator  t/lambda = ln(I_total / I_ZLP)
%   for every spatial pixel of a spectrum image.  I_ZLP is the integral of
%   the zero-loss peak (ZLP) in the specified energy window; I_total is the
%   integral of the entire spectrum.  Pixels with total counts below
%   MinCounts are flagged invalid and set to NaN in the output.
%
%   Inputs:
%       cube       — [Ny x Nx x nE] spectrum image datacube (any numeric type)
%       energyAxis — [nE x 1] energy-loss values (eV)
%
%   Optional Name-Value:
%       ZLPWindow  — [E1, E2] integration window for the zero-loss peak (eV).
%                   Default: [-5, 5]
%       MinCounts  — minimum total integrated counts for a pixel to be
%                   considered valid (default: 100)
%
%   Outputs:
%       tOverLambda — [Ny x Nx] double; relative thickness t/lambda.
%                    Invalid pixels (mask == false) are set to NaN.
%       mask        — [Ny x Nx] logical; true where pixel is valid
%
%   Examples:
%       [t, valid] = imaging.eelsThicknessMap(cube, E);
%       imagesc(t); colorbar; title('t / \lambda'); axis image;
%
%       % Tighter ZLP window for a well-aligned dataset
%       [t, valid] = imaging.eelsThicknessMap(cube, E, ZLPWindow=[-2, 2]);
%
%   See also imaging.eelsAlignZLP, imaging.eelsExtractMap,
%            imaging.eelsBackground

% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    cube       (:,:,:) {mustBeNumeric, mustBeNonempty}
    energyAxis (:,1)   double {mustBeNonempty}
    opts.ZLPWindow (1,2) double = [-5, 5]
    opts.MinCounts (1,1) double {mustBePositive} = 100
end

[Ny, Nx, nE] = size(cube);

if numel(energyAxis) ~= nE
    error('imaging:eelsThicknessMap:sizeMismatch', ...
        'energyAxis length (%d) must match the third dimension of cube (%d).', ...
        numel(energyAxis), nE);
end

energyAxis = double(energyAxis(:));

% ════════════════════════════════════════════════════════════════════════
%  Index masks for ZLP window and total spectrum
% ════════════════════════════════════════════════════════════════════════
zlpMask = energyAxis >= opts.ZLPWindow(1) & energyAxis <= opts.ZLPWindow(2);
if ~any(zlpMask)
    error('imaging:eelsThicknessMap:emptyZLPWindow', ...
        'ZLPWindow [%.1f, %.1f] eV contains no channels.', ...
        opts.ZLPWindow(1), opts.ZLPWindow(2));
end

% ════════════════════════════════════════════════════════════════════════
%  Integrate over spatial pixels
% ════════════════════════════════════════════════════════════════════════
% Reshape cube to [nE x (Ny*Nx)] for vectorised summation
cubeD   = double(reshape(cube, Ny*Nx, nE))';   % [nE x NxNy]

iTotal  = sum(cubeD, 1);                        % [1 x NxNy]
iZLP    = sum(cubeD(zlpMask, :), 1);            % [1 x NxNy]

% ════════════════════════════════════════════════════════════════════════
%  Validity mask and log-ratio
% ════════════════════════════════════════════════════════════════════════
validVec = iTotal >= opts.MinCounts & iZLP > 0 & iTotal > iZLP;

tLambdaVec          = nan(1, Ny*Nx);
tLambdaVec(validVec) = log(iTotal(validVec) ./ iZLP(validVec));

tOverLambda = reshape(tLambdaVec, Ny, Nx);
mask        = reshape(validVec,   Ny, Nx);

end
