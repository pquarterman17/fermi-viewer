function [alignedCube, shifts] = eelsAlignZLP(cube, energyAxis, opts)
%EELSALIGNZLP  Align zero-loss peaks across an EELS spectrum image.
%
%   Syntax:
%       [alignedCube, shifts] = imaging.eels.eelsAlignZLP(cube, energyAxis)
%       [alignedCube, shifts] = imaging.eels.eelsAlignZLP(cube, energyAxis, ...
%                                   Window=[-20, 20], Reference='mean')
%       [alignedCube, shifts] = imaging.eels.eelsAlignZLP(cube, energyAxis, ...
%                                   SubPixel=true)
%
%   Cross-correlates each pixel spectrum (restricted to the ZLP window) with
%   a reference spectrum, finds the integer channel shift at the
%   cross-correlation peak, then applies that shift via circshift along the
%   energy dimension.  Edge channels filled by the circular shift are
%   artifact-free for shifts much smaller than the window width.
%
%   With SubPixel=true, the cross-correlation peak is additionally refined
%   by a 3-point parabolic fit over its circular neighbours to recover a
%   fractional-channel offset, and the shift is applied via an FFT phase
%   ramp instead of circshift (so non-integer shifts are represented
%   exactly rather than rounded).  The default SubPixel=false path is
%   unchanged and remains byte-identical to prior releases.
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
%       SubPixel  — logical; refine the cross-correlation peak to
%                   sub-channel precision and apply the shift via an FFT
%                   phase ramp.  Default: false (integer-channel circshift).
%
%   Outputs:
%       alignedCube — [Ny x Nx x nE] shifted datacube (same class as cube)
%       shifts      — [Ny x Nx] channel shifts applied (positive = shifted
%                    to higher index, i.e. spectrum moved right).  int32
%                    when SubPixel=false (default); double (fractional)
%                    when SubPixel=true.
%
%   Examples:
%       [aligned, sh] = imaging.eels.eelsAlignZLP(cube, E);
%       imagesc(sh); colorbar; title('ZLP shift (channels)'); axis image;
%
%       % Use a narrow window and a custom reference
%       ref = squeeze(cube(64, 64, :));
%       [aligned, sh] = imaging.eels.eelsAlignZLP(cube, E, ...
%                           Window=[-10, 10], Reference=ref);
%
%       % Sub-pixel alignment for fine ZLP registration
%       [aligned, sh] = imaging.eels.eelsAlignZLP(cube, E, SubPixel=true);
%
%   See also imaging.eels.eelsThicknessMap, imaging.eels.eelsExtractMap

% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    cube       (:,:,:) {mustBeNumeric, mustBeNonempty}
    energyAxis (:,1)   double {mustBeNonempty}
    opts.Window    (1,2) double = [-20, 20]
    opts.Reference         = 'mean'   % 'mean' | 'max' | [nE x 1] double
    opts.SubPixel  (1,1) logical = false
end

[Ny, Nx, nE] = size(cube);

if numel(energyAxis) ~= nE
    error('imaging:eels:eelsAlignZLP:sizeMismatch', ...
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
    error('imaging:eels:eelsAlignZLP:tooNarrowWindow', ...
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
            error('imaging:eels:eelsAlignZLP:badReference', ...
                'Reference must be ''mean'', ''max'', or an [nE x 1] vector.');
    end
else
    % Custom reference vector — extract its ZLP window
    ref = double(opts.Reference(:));
    if numel(ref) ~= nE
        error('imaging:eels:eelsAlignZLP:refSizeMismatch', ...
            'Custom Reference must have %d elements (got %d).', nE, numel(ref));
    end
    refZLP = ref(winIdx);
end

% ════════════════════════════════════════════════════════════════════════
%  Cross-correlate each pixel and find integer shift
% ════════════════════════════════════════════════════════════════════════
nWin   = numel(winIdx);
nfft   = 2*nWin - 1;
shifts = zeros(Ny*Nx, 1, 'int32');
fracShift = zeros(Ny*Nx, 1);   % sub-channel offsets; only used if SubPixel

% Precompute FFT of reference for efficiency
refF = conj(fft(refZLP, nfft));

for p = 1:Ny*Nx
    pixZLP = zlpFlat(:, p);
    xc     = ifft(fft(pixZLP, nfft) .* refF, 'symmetric');
    [~, pk] = max(xc);
    lag    = pk - 1;                        % 0-based lag
    if lag > nWin - 1
        lag = lag - nfft;                   % wrap negative lags
    end
    shifts(p) = int32(-lag);               % negative lag → shift right

    if opts.SubPixel
        % Refine to sub-channel precision via a 3-point parabolic fit
        % around the (circular) cross-correlation peak.
        frac = parabolicOffset(xc, pk);
        fracShift(p) = double(shifts(p)) - frac;
    end
end

shifts = reshape(shifts, Ny, Nx);

% ════════════════════════════════════════════════════════════════════════
%  Apply shifts: integer circshift (default) or FFT phase-ramp (SubPixel)
% ════════════════════════════════════════════════════════════════════════
if opts.SubPixel
    shifts      = reshape(fracShift, Ny, Nx);      % double, sub-channel precision
    alignedCube = fractionalShift(cubeD, shifts);
else
    alignedCube = cubeD;

    for p = 1:Ny*Nx
        [row, col] = ind2sub([Ny, Nx], p);
        s = double(shifts(row, col));
        if s ~= 0
            alignedCube(row, col, :) = circshift(squeeze(cubeD(row,col,:)), s);
        end
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

% ────────────────────────────────────────────────────────────────────────
function frac = parabolicOffset(xc, pk)
%   Sub-sample peak offset in [-0.5, 0.5] from a 3-point parabolic fit
%   around the cross-correlation peak at 1-based index pk, using circular
%   neighbours (wraps at the ends of xc). xc is a single pixel's real
%   cross-correlation vector (length nfft).
nfft = numel(xc);
i0 = mod(pk - 2, nfft) + 1;   % pk-1, circular, 1-based
i2 = mod(pk,     nfft) + 1;   % pk+1, circular, 1-based
y0 = xc(i0);  y1 = xc(pk);  y2 = xc(i2);

denom = y0 - 2*y1 + y2;
if abs(denom) > eps
    frac = 0.5 * (y0 - y2) / denom;
else
    frac = 0;
end
frac = max(min(frac, 0.5), -0.5);
end

% ────────────────────────────────────────────────────────────────────────
function shiftedCube = fractionalShift(cubeD, shiftMap)
%   Shift each pixel's spectrum by a fractional channel count via an FFT
%   phase ramp. Sign matches circshift (positive shift moves the
%   spectrum toward higher channel index), so integer-valued shifts
%   reproduce the integer-alignment path exactly.
[Ny, Nx, nE] = size(cubeD);
flat = reshape(cubeD, Ny*Nx, nE);                    % [Np x nE]
s    = shiftMap(:);                                   % [Np x 1]

k = ifftshift(-floor(nE/2):ceil(nE/2)-1) / nE;        % [1 x nE], fftfreq order
spec  = fft(flat, [], 2);
phase = exp(-2i * pi * k .* s);                       % [Np x nE], broadcast
shiftedCube = reshape(real(ifft(spec .* phase, [], 2)), Ny, Nx, nE);
end
