function [radii, avgProfile, maxProfile] = radialProfile(img, options)
%RADIALPROFILE  Compute a radial intensity profile from a 2-D image.
%
%   Syntax:
%       [radii, avgProfile, maxProfile] = imaging.radialProfile(img)
%       [radii, avgProfile, maxProfile] = imaging.radialProfile(img, ...
%                               Center=[cx cy], NumBins=128, Normalize=true)
%
%   Suitable for FFT magnitude images, diffraction patterns, and any image
%   with approximate rotational symmetry.  For each radial bin the function
%   returns both the mean and the maximum pixel value, making it easy to
%   detect narrow rings (max) as well as broad features (mean).
%
%   Inputs:
%       img          — [H x W] numeric matrix (any integer or float type)
%
%   Optional Name-Value:
%       Center    — [cx cy] centre of the radial coordinate system in pixel
%                   coordinates (column, row); default = image centre
%       NumBins   — number of equally-spaced radial bins;
%                   default = floor(min(size(img)) / 2)
%       Normalize — scale avgProfile and maxProfile to [0, 1] (default: false)
%
%   Outputs:
%       radii      — [NumBins x 1] bin-centre radii (pixels)
%       avgProfile — [NumBins x 1] mean intensity in each bin
%       maxProfile — [NumBins x 1] maximum intensity in each bin
%
%   Examples:
%       % Radial profile of an FFT magnitude image
%       mag = imaging.computeFFT(rawImg);
%       [r, avg, mx] = imaging.radialProfile(mag);
%       plot(r, avg); xlabel('Radius (px)'); ylabel('Mean magnitude');
%
%       % Custom centre and bin count, normalised
%       [r, avg, ~] = imaging.radialProfile(mag, ...
%                         Center=[256 256], NumBins=200, Normalize=true);
%
%   See also imaging.computeFFT, imaging.lineProfile

% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    img                    (:,:) {mustBeNumeric}
    options.Center         (1,2) double = [NaN NaN]
    options.NumBins        (1,1) double {mustBePositive, mustBeInteger} = 0
    options.Normalize      (1,1) logical = false
end

% ════════════════════════════════════════════════════════════════════════
%  Resolve defaults that depend on image size
% ════════════════════════════════════════════════════════════════════════
[H, W] = size(img);

if any(isnan(options.Center))
    cx = W / 2 + 0.5;   % column centre (pixel-centre convention)
    cy = H / 2 + 0.5;   % row centre
else
    cx = options.Center(1);
    cy = options.Center(2);
end

numBins = options.NumBins;
if numBins == 0
    numBins = floor(min(H, W) / 2);
end

% ════════════════════════════════════════════════════════════════════════
%  Compute per-pixel radial distance from centre
% ════════════════════════════════════════════════════════════════════════
[colGrid, rowGrid] = meshgrid(1:W, 1:H);
distMap = hypot(colGrid - cx, rowGrid - cy);   % [H x W]

% ════════════════════════════════════════════════════════════════════════
%  Define bin edges and centres
% ════════════════════════════════════════════════════════════════════════
maxRadius  = max(distMap(:));
edges      = linspace(0, maxRadius, numBins + 1);  % numBins+1 edges → numBins bins
binWidth   = edges(2) - edges(1);
radii      = (edges(1:end-1) + binWidth / 2)';     % [numBins x 1] bin centres

% ════════════════════════════════════════════════════════════════════════
%  Accumulate per-bin statistics
% ════════════════════════════════════════════════════════════════════════
imgDbl = double(img);

% Assign each pixel to a bin index (clamp last edge into final bin)
binIdx = floor(distMap / binWidth) + 1;
binIdx(binIdx > numBins) = numBins;

% Vectorised accumulation — same pattern as imaging.azimuthalIntegrate
avgProfile = accumarray(binIdx(:), imgDbl(:), [numBins 1], @mean, NaN);
maxProfile = accumarray(binIdx(:), imgDbl(:), [numBins 1], @max,  NaN);

% ════════════════════════════════════════════════════════════════════════
%  Optional normalisation
% ════════════════════════════════════════════════════════════════════════
if options.Normalize
    avgLo = min(avgProfile);  avgHi = max(avgProfile);
    maxLo = min(maxProfile);  maxHi = max(maxProfile);

    if avgHi > avgLo
        avgProfile = (avgProfile - avgLo) / (avgHi - avgLo);
    else
        avgProfile = zeros(numBins, 1);
    end

    if maxHi > maxLo
        maxProfile = (maxProfile - maxLo) / (maxHi - maxLo);
    else
        maxProfile = zeros(numBins, 1);
    end
end

end
