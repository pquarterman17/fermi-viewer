function result = countDefectLines(img, opts)
%COUNTDEFECTLINES  Semi-automated counting of linear defects for dislocation
%                  density estimation (Ham's interception method).
%
%   Syntax:
%       result = imaging.countDefectLines(img)
%       result = imaging.countDefectLines(img, ROI=[1,1,512,512], ...
%                    Direction=90, GridSpacing=40, FoilThickness=100, ...
%                    PixelSize=0.5, PixelUnit='nm')
%
%   Applies an oriented derivative filter to enhance linear features, then
%   thresholds using an inline Otsu method (no toolboxes required), and
%   counts intersections between defect lines and a grid of test lines to
%   estimate dislocation density via Ham's method.
%
%   Inputs:
%       img — [H x W] numeric grayscale image (TEM micrograph)
%
%   Optional Name-Value:
%       ROI           — [r1, c1, r2, c2] bounding box rows/cols, 1-based
%                       (default: full image)
%       Direction     — preferred defect orientation in degrees measured
%                       from horizontal; NaN = use all 4 orientations
%                       0/45/90/135 deg and take max response (default NaN)
%       KernelLength  — length of the oriented derivative kernel in pixels;
%                       must be odd (default 15)
%       GridSpacing   — spacing between parallel test lines in pixels
%                       (default 50)
%       FoilThickness — TEM foil thickness in the same unit as PixelUnit for
%                       3-D density; NaN = return 2-D surface density
%                       (default NaN)
%       PixelSize     — physical size of one pixel (default 1)
%       PixelUnit     — unit string associated with PixelSize (default 'px')
%
%   Outputs:
%       result — struct with fields:
%           .intersectionCount — total intersection count across all test lines
%           .numTestLines      — number of test lines cast (H + V combined)
%           .totalLineLength   — total calibrated test-line length
%           .density           — estimated dislocation density
%           .densityUnit       — unit string for density (e.g. 'lines/nm^2')
%           .enhancedImg       — [H x W] double; filter response (absolute value)
%           .binaryMask        — [H x W] logical; thresholded defect mask
%           .testLinePositions — struct with fields:
%               .horizontal — row indices of horizontal test lines
%               .vertical   — column indices of vertical test lines
%
%   Examples:
%       % Basic usage — auto-detect all directions
%       result = imaging.countDefectLines(temImg);
%       imagesc(result.enhancedImg); colormap gray;
%
%       % Calibrated with known geometry
%       result = imaging.countDefectLines(temImg, ...
%           Direction=90, KernelLength=21, GridSpacing=40, ...
%           FoilThickness=120, PixelSize=0.25, PixelUnit='nm');
%       fprintf('Dislocation density: %.3g %s\n', result.density, result.densityUnit);
%
%       % Restrict to a sub-region
%       result = imaging.countDefectLines(temImg, ROI=[50,50,450,450]);
%
%   See also imaging.lineProfile, imaging.computeFFT, imaging.applyGaussian

% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    img                   (:,:) {mustBeNumeric}
    opts.ROI              (1,4) double = [NaN NaN NaN NaN]
    opts.Direction        (1,1) double = NaN
    opts.KernelLength     (1,1) double {mustBePositive, mustBeInteger} = 15
    opts.GridSpacing      (1,1) double {mustBePositive, mustBeInteger} = 50
    opts.FoilThickness    (1,1) double = NaN
    opts.PixelSize        (1,1) double {mustBePositive} = 1
    opts.PixelUnit        (1,1) string = 'px'
end

% ════════════════════════════════════════════════════════════════════════
%  Extract ROI
% ════════════════════════════════════════════════════════════════════════
[imgH, imgW] = size(img);

if any(isnan(opts.ROI))
    r1 = 1; c1 = 1; r2 = imgH; c2 = imgW;
else
    r1 = max(1,    round(opts.ROI(1)));
    c1 = max(1,    round(opts.ROI(2)));
    r2 = min(imgH, round(opts.ROI(3)));
    c2 = min(imgW, round(opts.ROI(4)));
    if r2 <= r1 || c2 <= c1
        error('imaging:countDefectLines:badROI', ...
            'ROI [%d %d %d %d] is invalid — r2 must be > r1 and c2 > c1.', ...
            r1, c1, r2, c2);
    end
end

roi = double(img(r1:r2, c1:c2));
[roiH, roiW] = size(roi);

% ════════════════════════════════════════════════════════════════════════
%  Ensure kernel length is odd
% ════════════════════════════════════════════════════════════════════════
kLen = opts.KernelLength;
if mod(kLen, 2) == 0
    kLen = kLen + 1;
end

% ════════════════════════════════════════════════════════════════════════
%  Oriented derivative filtering
%
%  For each angle theta the kernel is a 2-D separable approximation:
%    - Along the defect direction (axis parallel):  Gaussian smoothing
%    - Perpendicular to defect:                     1st derivative of Gaussian
%
%  We build the kernel in the un-rotated frame (vertical features = theta=0
%  degrees from vertical = horizontal derivative) and then rotate the
%  coordinate frame for each target angle.
% ════════════════════════════════════════════════════════════════════════
if isnan(opts.Direction)
    angles = [0, 45, 90, 135];
else
    angles = opts.Direction;
end

% Sigma for smoothing: scale with kernel length
sigma      = kLen / 6;          % covers ~3-sigma within half-kernel
sigmaPerp  = sigma;             % perpendicular smoothing
sigmaParal = sigma * 2;         % parallel smoothing (more elongated)

% Build a response image that is the max across all requested angles
response = zeros(roiH, roiW);

for ai = 1:numel(angles)
    theta   = angles(ai);
    k       = buildOrientedKernel(kLen, theta, sigmaParal, sigmaPerp);
    filtered = conv2(roi, k, 'same');
    response = max(response, abs(filtered));
end

% ════════════════════════════════════════════════════════════════════════
%  Inline Otsu threshold (no toolbox)
%  Maximise inter-class variance over 256-bin histogram.
% ════════════════════════════════════════════════════════════════════════
nBins   = 256;
respMin = min(response(:));
respMax = max(response(:));

if respMax <= respMin
    % Flat image — no features detectable
    binaryMask = false(roiH, roiW);
else
    range      = respMax - respMin;
    binEdges   = linspace(respMin, respMax, nBins + 1);
    binCentres = (binEdges(1:end-1) + binEdges(2:end)) / 2;

    % Histogram counts (avoid histc — use manual binning)
    normResp   = (response(:) - respMin) / range;   % map to [0,1]
    binIdx     = min(nBins, floor(normResp * nBins) + 1);
    counts     = accumarray(binIdx, 1, [nBins, 1]);

    prob       = counts / sum(counts);

    % Cumulative sums for Otsu
    omega      = cumsum(prob);                        % cumulative weight
    mu         = cumsum(prob .* binCentres(:));       % cumulative weighted mean
    muTotal    = mu(end);

    % Between-class variance (avoid division by zero at boundaries)
    with1      = omega;
    with2      = 1 - omega;
    safeIdx    = with1 > 1e-10 & with2 > 1e-10;
    varBetween = zeros(nBins, 1);
    varBetween(safeIdx) = ...
        (muTotal * with1(safeIdx) - mu(safeIdx)).^2 ./ ...
        (with1(safeIdx) .* with2(safeIdx));

    [~, bestBin] = max(varBetween);
    otsuThresh   = binCentres(bestBin);
    binaryMask   = response >= otsuThresh;
end

% ════════════════════════════════════════════════════════════════════════
%  Place test line grid
% ════════════════════════════════════════════════════════════════════════
gap = opts.GridSpacing;

% Horizontal test lines: evenly spaced rows within ROI
hRows = (gap : gap : roiH - 1);    % keep away from edges by 1 px
if isempty(hRows)
    hRows = round(roiH / 2);       % fallback: single line through centre
end

% Vertical test lines: evenly spaced cols within ROI
vCols = (gap : gap : roiW - 1);
if isempty(vCols)
    vCols = round(roiW / 2);
end

% ════════════════════════════════════════════════════════════════════════
%  Count intersections
%  An intersection is a 0→1 transition along a test line in binaryMask.
% ════════════════════════════════════════════════════════════════════════
totalIntersections = 0;

% Horizontal lines (scan across columns)
for r = hRows
    lineVec = binaryMask(r, :);
    transitions = sum(diff(lineVec) == 1);
    totalIntersections = totalIntersections + transitions;
end

% Vertical lines (scan across rows)
for c = vCols
    lineVec = binaryMask(:, c)';
    transitions = sum(diff(lineVec) == 1);
    totalIntersections = totalIntersections + transitions;
end

numTestLines = numel(hRows) + numel(vCols);

% ════════════════════════════════════════════════════════════════════════
%  Total calibrated line length
% ════════════════════════════════════════════════════════════════════════
pixelSize = opts.PixelSize;
unit      = opts.PixelUnit;

totalHLineLength = numel(hRows) * roiW * pixelSize;   % calibrated
totalVLineLength = numel(vCols) * roiH * pixelSize;
totalLineLength  = totalHLineLength + totalVLineLength;

% ════════════════════════════════════════════════════════════════════════
%  Dislocation density (Ham 1961)
%
%  2-D (no foil thickness):  rho2D = 2 * N / L_total
%  3-D (with foil thickness): rho3D = 2 * N / (L_total * t)
%
%  The factor of 2 accounts for the statistical correction that a random
%  line distribution gives an average interception probability of 0.5 per
%  unit length.
% ════════════════════════════════════════════════════════════════════════
N = totalIntersections;
L = totalLineLength;

if L > 0
    rho2D = 2 * N / L;
else
    rho2D = 0;
end

foilT = opts.FoilThickness;

if ~isnan(foilT) && foilT > 0
    density     = 2 * N / (L * foilT);
    densityUnit = sprintf('lines/%s^3', unit);
else
    density     = rho2D;
    densityUnit = sprintf('lines/%s^2', unit);
end

% ════════════════════════════════════════════════════════════════════════
%  Pack result
% ════════════════════════════════════════════════════════════════════════
result.intersectionCount   = totalIntersections;
result.numTestLines        = numTestLines;
result.totalLineLength     = totalLineLength;
result.density             = density;
result.densityUnit         = densityUnit;
result.enhancedImg         = response;
result.binaryMask          = binaryMask;
result.testLinePositions.horizontal = hRows;
result.testLinePositions.vertical   = vCols;

end

% ════════════════════════════════════════════════════════════════════════
%  Local helper: build an oriented derivative kernel
%
%  theta — angle of the *defect lines* in degrees from horizontal.
%          E.g. theta=90 → vertical lines → horizontal derivative.
%  The kernel detects edges perpendicular to the defect orientation.
% ════════════════════════════════════════════════════════════════════════
function k = buildOrientedKernel(kLen, theta, sigmaParal, sigmaPerp)
    hw     = floor(kLen / 2);
    coords = -hw : hw;
    [X, Y] = meshgrid(coords, coords);   % X=col offset, Y=row offset

    % Rotate coordinate frame so that u is along defect, v is perpendicular
    thetaRad = theta * pi / 180;
    U =  X * cos(thetaRad) + Y * sin(thetaRad);   % along defect direction
    V = -X * sin(thetaRad) + Y * cos(thetaRad);   % perpendicular

    % Gaussian smoothing along defect (U axis)
    gParal = exp(-0.5 * (U / sigmaParal).^2);

    % First derivative of Gaussian perpendicular to defect (V axis)
    gPerpDeriv = -(V / sigmaPerp^2) .* exp(-0.5 * (V / sigmaPerp).^2);

    % Combined kernel
    k = gParal .* gPerpDeriv;

    % Zero-mean normalisation (derivative kernels should sum to ~0)
    posSum = sum(k(k > 0));
    negSum = sum(k(k < 0));
    if posSum > 0 && abs(negSum) > 0
        k(k > 0) = k(k > 0) / posSum;
        k(k < 0) = k(k < 0) / abs(negSum);
    end
end
