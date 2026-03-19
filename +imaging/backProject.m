function result = backProject(sinogram, opts)
%BACKPROJECT  Filtered back-projection tomographic reconstruction from a sinogram.
%
%   Syntax:
%       result = imaging.backProject(sinogram)
%       result = imaging.backProject(sinogram, Angles=angles, Filter='shepp-logan')
%       result = imaging.backProject(sinogram, OutputSize=256)
%
%   Reconstructs a 2-D slice from a [numAngles x width] sinogram using the
%   filtered back-projection (FBP) algorithm.  Each projection row is
%   filtered in the frequency domain before being smeared back across the
%   reconstruction grid via bilinear interpolation.
%
%   No Image Processing Toolbox or Signal Processing Toolbox is required.
%
%   Inputs:
%       sinogram — [numAngles x width] numeric matrix.
%                  Row k is the 1-D projection measured at angle Angles(k).
%
%   Optional Name-Value:
%       Angles     — [numAngles x 1] tilt angles in degrees.
%                    Default: linspace(-70, 70, numAngles)
%       Filter     — frequency-domain ramp filter variant:
%                      'ramp'        — |k| (Ram-Lak, default)
%                      'shepp-logan' — |k| * sinc(k / (2*kmax))
%                      'hamming'     — |k| * (0.54 + 0.46*cos(pi*k/kmax))
%                      'none'        — no filtering (pure back-projection)
%       OutputSize — side length (pixels) of the square output image.
%                    Default: width of sinogram
%
%   Output:
%       result — struct with fields:
%           .reconstruction — [OutputSize x OutputSize] double reconstructed slice
%           .sinogram       — input sinogram (echoed for display convenience)
%           .angles         — angles used (degrees)
%           .filter         — filter name used
%
%   Examples:
%       % Reconstruct from a 180-angle sinogram spanning -90..90 degrees
%       angles = linspace(-90, 90, 180);
%       result  = imaging.backProject(sino, Angles=angles, Filter='shepp-logan');
%       imagesc(result.reconstruction); colormap gray; axis image; colorbar;
%
%       % Quick preview with default angles (no filter)
%       result = imaging.backProject(sino, Filter='none');
%
%   See also imaging.computeFFT

% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    sinogram              (:,:) {mustBeNumeric}
    opts.Angles           (:,1) double = []          % resolved below
    opts.Filter           (1,1) string = 'ramp'
    opts.OutputSize       (1,1) double {mustBePositive} = 0   % 0 = auto
end

sinogram = double(sinogram);
[numAngles, W] = size(sinogram);

% ════════════════════════════════════════════════════════════════════════
%  Resolve defaults
% ════════════════════════════════════════════════════════════════════════
if isempty(opts.Angles)
    angles = linspace(-70, 70, numAngles)';
else
    angles = opts.Angles(:);
    if numel(angles) ~= numAngles
        error('imaging:backProject:anglesMismatch', ...
            'Angles length (%d) must match sinogram rows (%d).', ...
            numel(angles), numAngles);
    end
end

outSize = opts.OutputSize;
if outSize == 0
    outSize = W;
end

filterName = lower(char(opts.Filter));
validFilters = {'ramp', 'shepp-logan', 'hamming', 'none'};
if ~any(strcmp(filterName, validFilters))
    error('imaging:backProject:unknownFilter', ...
        'Filter must be one of: ramp, shepp-logan, hamming, none.');
end

% ════════════════════════════════════════════════════════════════════════
%  Build frequency-domain filter for one projection width
% ════════════════════════════════════════════════════════════════════════
% Pad to next power of 2 for efficient FFT
Npad = 2^nextpow2(2 * W - 1);

H = BuildFilter(W, Npad, filterName);   % [1 x Npad] real filter

% ════════════════════════════════════════════════════════════════════════
%  Filter each projection row
% ════════════════════════════════════════════════════════════════════════
filtSino = zeros(numAngles, W);

for k = 1 : numAngles
    proj = sinogram(k, :);                        % [1 x W]

    if strcmp(filterName, 'none')
        filtSino(k, :) = proj;
    else
        projPad = [proj, zeros(1, Npad - W)];     % zero-pad
        fProj   = fft(projPad) .* H;              % apply filter
        iProj   = real(ifft(fProj));              % back to spatial
        filtSino(k, :) = iProj(1:W);             % trim
    end
end

% ════════════════════════════════════════════════════════════════════════
%  Back-project each filtered projection onto the output grid
% ════════════════════════════════════════════════════════════════════════
% Output pixel coordinates centred at (0,0)
halfOut = (outSize - 1) / 2;
xOut    = linspace(-halfOut, halfOut, outSize);   % [1 x outSize]
[Xg, Yg] = meshgrid(xOut, xOut);                  % [outSize x outSize], both

% Projection coordinate axis (centred at W/2)
halfW  = (W - 1) / 2;
tAxis  = linspace(-halfW, halfW, W);              % [1 x W]

recon = zeros(outSize, outSize);
anglesRad = angles * (pi / 180);

for k = 1 : numAngles
    theta = anglesRad(k);

    % For each output pixel, find the radon coordinate t = x*cos + y*sin
    % Note: MATLAB meshgrid: Xg varies along columns (x), Yg along rows (y)
    T = Xg * cos(theta) + Yg * sin(theta);       % [outSize x outSize]

    % Clamp to valid projection range
    T = max(T, tAxis(1));
    T = min(T, tAxis(end));

    % Interpolate filtered projection at each t value
    projSlice = interp1(tAxis, filtSino(k, :), T(:), 'linear', 0);
    recon = recon + reshape(projSlice, outSize, outSize);
end

% Normalise by number of angles
recon = recon * (pi / (2 * numAngles));

% ════════════════════════════════════════════════════════════════════════
%  Assemble output
% ════════════════════════════════════════════════════════════════════════
result.reconstruction = recon;
result.sinogram        = sinogram;
result.angles          = angles;
result.filter          = filterName;

end % backProject

% ════════════════════════════════════════════════════════════════════════
%  Local helper: build 1-D frequency-domain ramp filter (length Npad)
% ════════════════════════════════════════════════════════════════════════
function H = BuildFilter(W, Npad, filterName)
%BUILDFILTER  Construct a ramp-based frequency filter of length Npad.

% Normalised frequency axis [0, 1) — matches MATLAB fft ordering
freqAxis = (0 : Npad - 1) / Npad;               % [1 x Npad]

% Map to symmetric [-0.5, 0.5) for ramp magnitude |k|
kSym = freqAxis;
kSym(freqAxis > 0.5) = freqAxis(freqAxis > 0.5) - 1;
absK = abs(kSym);                                % ramp magnitude
kmax = 0.5;                                      % Nyquist

switch filterName
    case 'ramp'
        H = absK;

    case 'shepp-logan'
        % sinc window: sinc(k / (2*kmax)) = sin(pi*k/(2*kmax)) / (pi*k/(2*kmax))
        arg = pi * absK / (2 * kmax);
        sincWin = ones(size(arg));
        nonzero = arg > 0;
        sincWin(nonzero) = sin(arg(nonzero)) ./ arg(nonzero);
        H = absK .* sincWin;

    case 'hamming'
        % Hamming window in frequency domain
        hammWin = 0.54 + 0.46 * cos(pi * absK / kmax);
        H = absK .* hammWin;

    otherwise
        H = ones(1, Npad);   % 'none' — identity (handled upstream, but safe fallback)
end

% Scale so the filter area is consistent with the projection width
H = H * (1 / W);

end
