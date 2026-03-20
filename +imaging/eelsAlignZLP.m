function [alignedCube, shifts] = eelsAlignZLP(cube, energyAxis, opts)
%EELSALIGNZLP  Align zero-loss peaks across an EELS spectrum image.
%
%   Syntax:
%       [alignedCube, shifts] = imaging.eelsAlignZLP(cube, energyAxis)
%       [alignedCube, shifts] = imaging.eelsAlignZLP(cube, energyAxis, ...
%                                   Window=[-20, 20], Reference='mean')
%
%   Cross-correlates each pixel spectrum (restricted to the ZLP window) with
%   a reference spectrum, finds the integer channel shift at the
%   cross-correlation peak, then applies that shift via circshift along the
%   energy dimension.  Edge channels filled by the circular shift are
%   artifact-free for shifts much smaller than the window width.
%
%   Inputs:
%       cube       — [Ny x Nx x nE] spectrum image datacube (any numeric type)
%       energyAxis — [nE x 1] energy-loss values (eV)
%
%   Optional Name-Value:
%       Window    — [E1, E2] energy window used for cross-correlation (eV).
%                  Default: [-20, 20]
%       Reference — how to build the reference ZLP spectrum:
%                   'mean'  — mean over all spatial pixels (default)
%                   'max'   — pixel with the highest total ZLP counts
%                   [nE x 1] double — custom reference spectrum (full length)
%
%   Outputs:
%       alignedCube — [Ny x Nx x nE] shifted datacube (same class as cube)
%       shifts      — [Ny x Nx] integer channel shifts applied (positive =
%                    shifted to higher index, i.e. spectrum moved right)
%
%   Examples:
%       [aligned, sh] = imaging.eelsAlignZLP(cube, E);
%       imagesc(sh); colorbar; title('ZLP shift (channels)'); axis image;
%
%       % Use a narrow window and a custom reference
%       ref = squeeze(cube(64, 64, :));
%       [aligned, sh] = imaging.eelsAlignZLP(cube, E, ...
%                           Window=[-10, 10], Reference=ref);
%
%   See also imaging.eelsThicknessMap, imaging.eelsExtractMap

% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    cube       (:,:,:) {mustBeNumeric, mustBeNonempty}
    energyAxis (:,1)   double {mustBeNonempty}
    opts.Window    (1,2) double = [-20, 20]
    opts.Reference         = 'mean'   % 'mean' | 'max' | [nE x 1] double
end

[Ny, Nx, nE] = size(cube);

if numel(energyAxis) ~= nE
    error('imaging:eelsAlignZLP:sizeMismatch', ...
        'energyAxis length (%d) must match cube third dimension (%d).', ...
        numel(energyAxis), nE);
end

energyAxis = double(energyAxis(:));
cubeClass  = class(cube);
cubeD      = double(cube);

% ════════════════════════════════════════════════════════════════════════
%  ZLP window channel indices
% ════════════════════════════════════════════════════════════════════════
winMask = energyAxis >= opts.Window(1) & energyAxis <= opts.Window(2);
if sum(winMask) < 3
    error('imaging:eelsAlignZLP:tooNarrowWindow', ...
        'Window [%.1f, %.1f] eV spans fewer than 3 channels.', ...
        opts.Window(1), opts.Window(2));
end
winIdx = find(winMask);

% ════════════════════════════════════════════════════════════════════════
%  Build reference spectrum (ZLP window region only)
% ════════════════════════════════════════════════════════════════════════
cubeFlat = reshape(cubeD, Ny*Nx, nE)';    % [nE x NxNy]
zlpFlat  = cubeFlat(winIdx, :);            % [nWin x NxNy]

if ischar(opts.Reference) || isstring(opts.Reference)
    switch char(opts.Reference)
        case 'mean'
            refZLP = mean(zlpFlat, 2);     % [nWin x 1]
        case 'max'
            [~, bestPx] = max(sum(zlpFlat, 1));
            refZLP = zlpFlat(:, bestPx);
        otherwise
            error('imaging:eelsAlignZLP:badReference', ...
                'Reference must be ''mean'', ''max'', or an [nE x 1] vector.');
    end
else
    % Custom reference vector — extract its ZLP window
    ref = double(opts.Reference(:));
    if numel(ref) ~= nE
        error('imaging:eelsAlignZLP:refSizeMismatch', ...
            'Custom Reference must have %d elements (got %d).', nE, numel(ref));
    end
    refZLP = ref(winIdx);
end

% ════════════════════════════════════════════════════════════════════════
%  Cross-correlate each pixel and find integer shift
% ════════════════════════════════════════════════════════════════════════
nWin   = numel(winIdx);
shifts = zeros(Ny*Nx, 1, 'int32');

% Precompute FFT of reference for efficiency
refF = conj(fft(refZLP, 2*nWin - 1));

for p = 1:Ny*Nx
    pixZLP = zlpFlat(:, p);
    xc     = ifft(fft(pixZLP, 2*nWin - 1) .* refF, 'symmetric');
    [~, pk] = max(xc);
    lag    = pk - 1;                        % 0-based lag
    if lag > nWin - 1
        lag = lag - (2*nWin - 1);           % wrap negative lags
    end
    shifts(p) = int32(-lag);               % negative lag → shift right
end

shifts = reshape(shifts, Ny, Nx);

% ════════════════════════════════════════════════════════════════════════
%  Apply shifts via circshift along energy dimension
% ════════════════════════════════════════════════════════════════════════
alignedCube = cubeD;

for p = 1:Ny*Nx
    [row, col] = ind2sub([Ny, Nx], p);
    s = double(shifts(row, col));
    if s ~= 0
        alignedCube(row, col, :) = circshift(squeeze(cubeD(row,col,:)), s);
    end
end

% Restore original class if integer type (avoids unintended upcast)
if ~strcmp(cubeClass, 'double')
    try
        alignedCube = cast(alignedCube, cubeClass);
    catch
        % If cast fails (e.g. overflow), silently keep double
    end
end

end
