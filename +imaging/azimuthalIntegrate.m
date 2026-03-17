function [radii, intensity] = azimuthalIntegrate(img, options)
%AZIMUTHALINTEGRATE  Azimuthal (powder) integration of a 2-D diffraction pattern.
%
%   Syntax:
%       [radii, intensity] = imaging.azimuthalIntegrate(img)
%       [radii, intensity] = imaging.azimuthalIntegrate(img, ...
%                               Center=[cx cy], NumBins=512, ...
%                               SectorMin=0, SectorMax=360, ...
%                               PixelSize=0.01, PixelUnit='nm^-1')
%
%   Bins each pixel into a radial ring and returns the mean intensity per
%   ring.  An optional azimuthal sector mask restricts the integration to
%   a wedge of the diffraction pattern (e.g. to avoid a beamstop shadow or
%   select a particular texture component).
%
%   Inputs:
%       img         — [H x W] numeric matrix (any integer or float type).
%                     NaN pixels are silently excluded from bin averages.
%
%   Optional Name-Value:
%       Center      — [1x2] double [cx cy]; beam centre in pixel coordinates
%                     (column, row).  Default: centre of the image.
%       NumBins     — number of radial bins (default: floor(min(size(img))/2))
%       SectorMin   — minimum azimuthal angle in degrees, 0-360 (default: 0)
%       SectorMax   — maximum azimuthal angle in degrees, 0-360 (default: 360)
%       PixelSize   — physical size of one pixel for calibrated radii
%                     (default: 1, i.e. radii in pixels)
%       PixelUnit   — unit string attached to the radii axis (default: 'px')
%
%   Outputs:
%       radii     — [NumBins x 1] double; bin-centre radii in PixelUnit.
%                   Bins with no contributing pixels have NaN intensity but
%                   still carry a valid radius value.
%       intensity — [NumBins x 1] double; mean pixel intensity per bin.
%                   Empty bins are NaN.
%
%   Examples:
%       % Full-circle integration, result in pixels
%       [r, I] = imaging.azimuthalIntegrate(diffPattern);
%       plot(r, I); xlabel('Radius (px)'); ylabel('Mean intensity');
%
%       % Sector integration (top half, 90° wedge), calibrated axis
%       [r, I] = imaging.azimuthalIntegrate(diffPattern, ...
%                    Center=[256 256], NumBins=300, ...
%                    SectorMin=45, SectorMax=135, ...
%                    PixelSize=0.012, PixelUnit='nm^{-1}');
%
%   See also imaging.computeFFT, imaging.lineProfile

% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    img                    (:,:) {mustBeNumeric}
    options.Center         (1,2) double = [NaN NaN]   % resolved below
    options.NumBins        (1,1) double = 0            % resolved below
    options.SectorMin      (1,1) double = 0
    options.SectorMax      (1,1) double = 360
    options.PixelSize      (1,1) double = 1
    options.PixelUnit      (1,1) string = 'px'
end

% ════════════════════════════════════════════════════════════════════════
%  Resolve defaults that depend on image size
% ════════════════════════════════════════════════════════════════════════
[H, W] = size(img);

if any(isnan(options.Center))
    cx = (W + 1) / 2;
    cy = (H + 1) / 2;
else
    cx = options.Center(1);
    cy = options.Center(2);
end

if options.NumBins == 0
    nBins = floor(min(H, W) / 2);
else
    nBins = options.NumBins;
end

% ════════════════════════════════════════════════════════════════════════
%  Build coordinate grids relative to centre
%  MATLAB image convention: X (column) increases right, Y (row) increases
%  downward.  atan2d(dy, dx) therefore measures angles from the positive
%  X axis going clockwise — consistent with crystallography convention.
% ════════════════════════════════════════════════════════════════════════
colVec = (1:W) - cx;          % [1 x W]
rowVec = (1:H) - cy;          % [H x 1]

[dx, dy] = meshgrid(colVec, rowVec);   % both [H x W]

R   = hypot(dx, dy);                   % radial distance in pixels [H x W]
phi = atan2d(dy, dx);                  % [-180, 180]

% Convert to [0, 360)
phi(phi < 0) = phi(phi < 0) + 360;

% ════════════════════════════════════════════════════════════════════════
%  Sector mask
% ════════════════════════════════════════════════════════════════════════
sMin = options.SectorMin;
sMax = options.SectorMax;

fullCircle = (sMin == 0) && (sMax == 360);

if ~fullCircle
    if sMin < sMax
        % Simple contiguous wedge
        sectorMask = (phi >= sMin) & (phi < sMax);
    else
        % Wrapping wedge (e.g. 300 → 60)
        sectorMask = (phi >= sMin) | (phi < sMax);
    end
else
    sectorMask = true(H, W);
end

% ════════════════════════════════════════════════════════════════════════
%  Radial binning
% ════════════════════════════════════════════════════════════════════════
% Determine bin edges: 0 to rMax in nBins equal-width bins.
% rMax is the largest radius that falls within the image (hypotenuse to
% nearest edge from centre, capped by the diagonal to avoid empty bins
% at the periphery).
rMax = min([cx, cy, W - cx, H - cy]);   % stay inside the image
rMax = max(rMax, 1);                    % guard against pathological centres

edges      = linspace(0, rMax, nBins + 1);   % [1 x nBins+1]
binWidth   = edges(2) - edges(1);
binCentres = edges(1:nBins) + binWidth / 2;  % [1 x nBins]

% Flatten arrays; apply NaN and sector masks together
d   = double(img);
R_v   = R(:);
phi_v = phi(:);     %#ok<NASGU>  kept for future use
I_v   = d(:);
mask  = sectorMask(:) & ~isnan(I_v) & (R_v >= 0) & (R_v < rMax);

R_v = R_v(mask);
I_v = I_v(mask);

% Assign each pixel to a bin (1-based)
binIdx = floor(R_v / binWidth) + 1;
binIdx = min(binIdx, nBins);   % clamp the rare pixel exactly at rMax

% Accumulate sum and count per bin using sparse (fast, no toolbox needed)
binSum   = accumarray(binIdx, I_v,   [nBins 1], @sum,   0);
binCount = accumarray(binIdx, ones(size(I_v)), [nBins 1], @sum, 0);

% Mean per bin; mark empty bins as NaN
intensity = binSum ./ binCount;
intensity(binCount == 0) = NaN;

% ════════════════════════════════════════════════════════════════════════
%  Apply pixel calibration
% ════════════════════════════════════════════════════════════════════════
radii = (binCentres * options.PixelSize)';   % column vector

end
