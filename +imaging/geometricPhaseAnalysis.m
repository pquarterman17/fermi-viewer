function result = geometricPhaseAnalysis(img, g1, g2, opts)
%GEOMETRICPHASEANALYSIS  2-D strain tensor maps from HRTEM images via GPA.
%
%   Syntax:
%       result = imaging.geometricPhaseAnalysis(img, g1, g2)
%       result = imaging.geometricPhaseAnalysis(img, g1, g2, ...
%                    MaskRadius=12, MaskOrder=4, PixelSize=0.019)
%
%   Computes Geometric Phase Analysis (GPA) on a high-resolution TEM lattice
%   image.  Two reciprocal lattice vectors g1 and g2 are used to extract
%   phase maps via Butterworth-filtered inverse FFT, which are then converted
%   to displacement and strain fields.
%
%   Inputs:
%       img  — [H x W] numeric grayscale image (HRTEM lattice image)
%       g1   — [1 x 2] first  reciprocal vector [gx, gy] in FFT pixels
%       g2   — [1 x 2] second reciprocal vector [gx, gy] in FFT pixels
%
%   Optional Name-Value:
%       MaskRadius — radius of Butterworth mask in FFT pixels.
%                    Default: auto = min(|g1|, |g2|) / 3 (must be > 0)
%       MaskOrder  — Butterworth filter order (default: 2, must be >= 1)
%       PixelSize  — real-space pixel size used to scale displacement output.
%                    Default: 1 (output is in pixels)
%
%   Output:
%       result — struct with fields:
%           .exx           — [H x W] normal strain along x
%           .eyy           — [H x W] normal strain along y
%           .exy           — [H x W] shear strain (symmetric)
%           .rotation      — [H x W] rigid-body rotation map (radians)
%           .phase1        — [H x W] unwrapped phase for g1
%           .phase2        — [H x W] unwrapped phase for g2
%           .displacement_x — [H x W] x-displacement field (in PixelSize units)
%           .displacement_y — [H x W] y-displacement field (in PixelSize units)
%
%   Examples:
%       % Pick g-vectors from FFT spots (in pixel coords relative to centre)
%       g1 = [23, 0];   % e.g. (100) lattice planes
%       g2 = [0,  23];  % e.g. (010) lattice planes
%       result = imaging.geometricPhaseAnalysis(hrtemImg, g1, g2);
%
%       % Display exx strain map
%       imagesc(result.exx, [-0.05 0.05]); colormap jet; colorbar;
%       title('e_{xx} strain'); axis image;
%
%       % With known pixel calibration
%       result = imaging.geometricPhaseAnalysis(hrtemImg, g1, g2, PixelSize=0.019);
%
%   See also imaging.computeFFT, imaging.lineProfile

% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    img             (:,:) {mustBeNumeric}
    g1              (1,2) double
    g2              (1,2) double
    opts.MaskRadius (1,1) double = 0       % 0 = auto
    opts.MaskOrder  (1,1) double {mustBePositive} = 2
    opts.PixelSize  (1,1) double {mustBePositive} = 1
end

img = double(img);
[H, W] = size(img);

% ════════════════════════════════════════════════════════════════════════
%  Resolve mask radius
% ════════════════════════════════════════════════════════════════════════
if opts.MaskRadius == 0
    opts.MaskRadius = min(norm(g1), norm(g2)) / 3;
    if opts.MaskRadius < 1
        opts.MaskRadius = 1;
    end
end

% ════════════════════════════════════════════════════════════════════════
%  Forward FFT (shifted so DC is at centre)
% ════════════════════════════════════════════════════════════════════════
F = fftshift(fft2(img));

% Frequency axes in FFT pixels (centre = 0)
uAxis = (-floor(W/2) : ceil(W/2) - 1);   % column frequency index
vAxis = (-floor(H/2) : ceil(H/2) - 1);   % row    frequency index
[U, V] = meshgrid(uAxis, vAxis);          % [H x W]

% ════════════════════════════════════════════════════════════════════════
%  Extract phase for each g-vector
% ════════════════════════════════════════════════════════════════════════
phase1 = ExtractPhase(F, U, V, g1, opts.MaskRadius, opts.MaskOrder, H, W);
phase2 = ExtractPhase(F, U, V, g2, opts.MaskRadius, opts.MaskOrder, H, W);

% ════════════════════════════════════════════════════════════════════════
%  Convert phases to displacement fields
%
%  Phase relation:  P_g(r) = -2*pi * g . u(r)
%  where g is in units of 1/pixel (normalised by image size).
%  Solve the 2x2 system:
%      [ g1x  g1y ] [ ux ]   [ -P1 / (2*pi) ]
%      [ g2x  g2y ] [ uy ] = [ -P2 / (2*pi) ]
% ════════════════════════════════════════════════════════════════════════

% Normalise g-vectors to 1/pixel (divide by image dimensions)
g1n = [g1(1)/W, g1(2)/H];
g2n = [g2(1)/W, g2(2)/H];

G = [g1n; g2n];    % [2 x 2]

detG = G(1,1)*G(2,2) - G(1,2)*G(2,1);
if abs(detG) < 1e-12
    error('imaging:geometricPhaseAnalysis:singularG', ...
        'g1 and g2 are linearly dependent — cannot invert G matrix.');
end

Ginv = [G(2,2), -G(1,2); -G(2,1), G(1,1)] / detG;  % 2x2 inverse

rhs1 = -phase1 / (2*pi);   % [H x W]
rhs2 = -phase2 / (2*pi);   % [H x W]

ux = Ginv(1,1) * rhs1 + Ginv(1,2) * rhs2;   % x-displacement [H x W]
uy = Ginv(2,1) * rhs1 + Ginv(2,2) * rhs2;   % y-displacement [H x W]

ux = ux * opts.PixelSize;
uy = uy * opts.PixelSize;

% ════════════════════════════════════════════════════════════════════════
%  Strain tensor from displacement gradients
% ════════════════════════════════════════════════════════════════════════
[dudx, dudy] = gradient(ux);   % gradient treats dim2 as x, dim1 as y
[dvdx, dvdy] = gradient(uy);

exx      =  dudx;
eyy      =  dvdy;
exy      =  0.5 * (dudy + dvdx);
rotation =  0.5 * (dvdx - dudy);

% ════════════════════════════════════════════════════════════════════════
%  Assemble output
% ════════════════════════════════════════════════════════════════════════
result.exx            = exx;
result.eyy            = eyy;
result.exy            = exy;
result.rotation       = rotation;
result.phase1         = phase1;
result.phase2         = phase2;
result.displacement_x = ux;
result.displacement_y = uy;

end % geometricPhaseAnalysis

% ════════════════════════════════════════════════════════════════════════
%  Local helper: extract and unwrap phase for one g-vector
% ════════════════════════════════════════════════════════════════════════
function phase = ExtractPhase(F, U, V, g, radius, order, H, W)
%EXTRACTPHASE  Apply Butterworth mask at g, shift to DC, IFFT, return unwrapped phase.

% Distance from g-vector centre (in FFT pixel coords, centre = 0)
r = sqrt((U - g(1)).^2 + (V - g(2)).^2);

% Butterworth low-pass mask centred on the spot
mask = 1 ./ (1 + (r / radius).^(2 * order));

% Mask the FFT (already fftshifted)
Fg = F .* mask;

% Translate the spot to the DC position by multiplying by a phase ramp.
% Shifting by -g in the frequency domain multiplies the spatial signal
% by exp(-j*2*pi*(g1*x/W + g2*y/H)), which moves the spot to centre.
[X, Y] = meshgrid(0:W-1, 0:H-1);
shiftRamp = exp(-1i * 2 * pi * (g(1) * X / W + g(2) * Y / H));

% IFFT of the shifted-to-DC masked spectrum
cg = ifft2(ifftshift(Fg)) .* shiftRamp;

% Extract phase and unwrap
rawPhase = angle(cg);

% 2-D unwrap: unwrap along rows then along columns
unwrapped = unwrap(rawPhase, [], 2);   % along columns (x direction)
unwrapped = unwrap(unwrapped, [], 1);  % along rows    (y direction)

phase = unwrapped;
end
