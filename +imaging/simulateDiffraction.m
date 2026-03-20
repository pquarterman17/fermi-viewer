function result = simulateDiffraction(phaseName, opts)
%SIMULATEDIFFRACTION  Simulate a kinematic electron diffraction pattern.
%
%   Syntax:
%       result = imaging.simulateDiffraction(phaseName)
%       result = imaging.simulateDiffraction(phaseName, ZoneAxis=[1 0 0], ...
%                    AccVoltage=200, CameraLength=200, PixelSize=0.05, ...
%                    ImageSize=[512 512], MaxHKL=5, MinIntensity=0.01, ...
%                    SpotSigma=3)
%
%   Generates a kinematic electron diffraction pattern for a named crystal
%   phase along a specified zone axis.  Spot positions are computed from
%   the reciprocal lattice projected onto the zone-axis plane and scaled
%   by the electron wavelength and camera geometry.  Intensities use
%   reflection multiplicity as a proxy for |F|^2.  Friedel pairs are
%   included automatically.  A Gaussian direct beam is added at the centre.
%
%   Inputs:
%       phaseName — string; matched case-insensitively (contains) against
%                   calc.crystal.phaseDatabase() .name field
%
%   Optional Name-Value:
%       ZoneAxis     — [1 x 3] zone-axis direction [u v w] (default [0 0 1])
%       AccVoltage   — accelerating voltage in kV (default 200)
%       CameraLength — effective camera length in mm (default 200)
%       PixelSize    — detector pixel size in mm/pixel (default 0.05)
%       ImageSize    — [H W] output image size in pixels (default [512 512])
%       MaxHKL       — maximum |h|, |k|, |l| to enumerate (default 5)
%       MinIntensity — minimum intensity fraction of max |F|^2 to include
%                      (default 0.01)
%       SpotSigma    — Gaussian spot radius in pixels (default 3)
%
%   Output:
%       result — struct with fields:
%           .spots     — struct array; one entry per spot (including Friedel
%                        pair and direct beam):
%               .hkl       — [1 x 3] Miller indices ([0 0 0] for direct beam)
%               .dSpacing  — d-spacing in Angstroms (NaN for direct beam)
%               .intensity — relative intensity (peak of Gaussian blob)
%               .pixelRow  — row position in output image (1-based)
%               .pixelCol  — column position in output image (1-based)
%           .image     — [H x W] double simulated diffraction pattern
%           .phaseName — matched phase name string
%           .formula   — chemical formula string
%           .zoneAxis  — [1 x 3] zone axis used
%           .lambda    — electron wavelength in Angstroms
%
%   Examples:
%       % Silicon [001] zone axis at 200 kV
%       r = imaging.simulateDiffraction('Silicon');
%       imagesc(r.image); colormap gray; axis equal tight; colorbar;
%       title(sprintf('%s  [%d %d %d]', r.phaseName, r.zoneAxis));
%
%       % SrTiO3 [110] at 300 kV
%       r = imaging.simulateDiffraction('SrTiO3', ZoneAxis=[1 1 0], ...
%               AccVoltage=300, CameraLength=300);
%
%   See also imaging.indexDiffraction, imaging.calcElectronWavelength,
%            calc.crystal.phaseDatabase, calc.crystal.planeSpacings

% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    phaseName        (1,:) char
    opts.ZoneAxis    (1,3) double = [0 0 1]
    opts.AccVoltage  (1,1) double {mustBePositive} = 200
    opts.CameraLength (1,1) double {mustBePositive} = 200
    opts.PixelSize   (1,1) double {mustBePositive} = 0.05
    opts.ImageSize   (1,2) double {mustBePositive, mustBeInteger} = [512 512]
    opts.MaxHKL      (1,1) double {mustBePositive, mustBeInteger} = 5
    opts.MinIntensity (1,1) double {mustBePositive} = 0.01
    opts.SpotSigma   (1,1) double {mustBePositive} = 3
end

% ════════════════════════════════════════════════════════════════════════
%  Locate phase in database (case-insensitive contains match)
% ════════════════════════════════════════════════════════════════════════
db = calc.crystal.phaseDatabase();
dbNames = {db.name};

matchIdx = find(contains(lower(dbNames), lower(phaseName)));

if isempty(matchIdx)
    error('imaging:simulateDiffraction:phaseNotFound', ...
        'No phase matching "%s" found in the database.', phaseName);
end

% Take the first match when multiple phases match.
phase = db(matchIdx(1));

% ════════════════════════════════════════════════════════════════════════
%  Electron wavelength (Angstroms)
% ════════════════════════════════════════════════════════════════════════
lambda = imaging.calcElectronWavelength(opts.AccVoltage);   % Å

% ════════════════════════════════════════════════════════════════════════
%  Build direct lattice vectors from a, b, c, alpha, beta, gamma
%
%  Convention:  a_vec along x; b_vec in xy-plane; c_vec completes the RH set.
%  Angles: alpha = angle(b,c), beta = angle(a,c), gamma = angle(a,b)  (deg)
% ════════════════════════════════════════════════════════════════════════
a = phase.a;
b = phase.b;
c = phase.c;
alphaR = deg2rad(phase.alpha);
betaR  = deg2rad(phase.beta);
gammaR = deg2rad(phase.gamma);

aVec = a * [1, 0, 0];
bVec = b * [cos(gammaR), sin(gammaR), 0];

cx = c * cos(betaR);
cy = c * (cos(alphaR) - cos(betaR) * cos(gammaR)) / sin(gammaR);
czSq = c^2 - cx^2 - cy^2;
% Guard against small negative values from floating-point rounding.
cz = sqrt(max(czSq, 0));
cVec = [cx, cy, cz];

% ════════════════════════════════════════════════════════════════════════
%  Reciprocal lattice vectors (Å⁻¹)
%  a* = (b x c) / V,  b* = (c x a) / V,  c* = (a x b) / V
% ════════════════════════════════════════════════════════════════════════
V = dot(aVec, cross(bVec, cVec));   % unit cell volume (Å³)

aStar = cross(bVec, cVec) / V;
bStar = cross(cVec, aVec) / V;
cStar = cross(aVec, bVec) / V;

% ════════════════════════════════════════════════════════════════════════
%  Zone-axis plane basis vectors (two orthonormal vectors perpendicular
%  to [uvw], used for projecting g-vectors onto the diffraction plane)
% ════════════════════════════════════════════════════════════════════════
uvw = opts.ZoneAxis;

% Choose a reference vector not parallel to uvw.
if abs(uvw(1)) <= abs(uvw(2)) && abs(uvw(1)) <= abs(uvw(3))
    ref = [1, 0, 0];
else
    ref = [0, 1, 0];
end

e1 = cross(uvw, ref);
e1 = e1 / norm(e1);
e2 = cross(uvw, e1);
e2 = e2 / norm(e2);

% ════════════════════════════════════════════════════════════════════════
%  Enumerate ALL (hkl) reflections with zone-axis filtering
%  planeSpacings returns only canonical representatives; we need all
%  symmetry-equivalent (hkl) to find those in the diffraction plane.
% ════════════════════════════════════════════════════════════════════════
u = uvw(1);
v = uvw(2);
w = uvw(3);

maxH = opts.MaxHKL;
spotList = [];  % will be [N x 5]: h, k, l, d, intensity

for h = -maxH:maxH
    for k = -maxH:maxH
        for l = -maxH:maxH
            if h == 0 && k == 0 && l == 0, continue; end

            % Zone axis condition
            if abs(h*u + k*v + l*w) > 0.5, continue; end

            % Check systematic absence (centering selection rules)
            if ~isAllowedReflection(h, k, l, phase.centering), continue; end

            % Compute d-spacing from reciprocal lattice
            gVec = h*aStar + k*bStar + l*cStar;
            gMag = norm(gVec);
            if gMag < eps, continue; end
            d = 1 / gMag;

            spotList = [spotList; h, k, l, d, 1]; %#ok<AGROW>
        end
    end
end

if isempty(spotList)
    % Return empty result
    result.spots = struct('hkl',{},'dSpacing',{},'intensity',{},'pixelRow',{},'pixelCol',{});
    result.image = zeros(opts.ImageSize);
    result.phaseName = phase.name;
    result.formula = phase.formula;
    result.zoneAxis = opts.ZoneAxis;
    result.lambda = lambda;
    return;
end

hklZone  = spotList(:, 1:3);
dZone    = spotList(:, 4);
multZone = spotList(:, 5);
nZone    = size(hklZone, 1);

% ════════════════════════════════════════════════════════════════════════
%  Compute pixel offsets for each reflection
%
%  Camera equation (small-angle, TEM):
%    R = lambda * L / d        [Å * mm / Å = mm on detector]
%    pixel_offset = R / PixelSize   [pixels]
%  where L = CameraLength (mm), d = d-spacing (Å), lambda (Å).
%
%  Direction: project g = h*a* + k*b* + l*c* onto e1, e2.
% ════════════════════════════════════════════════════════════════════════
centerRow = opts.ImageSize(1) / 2 + 0.5;
centerCol = opts.ImageSize(2) / 2 + 0.5;

% Conversion: lambda (Å) * CameraLength (mm) / PixelSize (mm/px) / d (Å)
% = pixel offset.  We fold the 1/d into the g-vector magnitude projection.
% For a spot at g-vector magnitude |g| = 1/d:
%   pixel_offset = lambda (Å) * CameraLength (mm) / PixelSize (mm/px) * |g_proj| (Å⁻¹)
%   where |g_proj| has units Å⁻¹ and the g-vector length in the projection
%   plane equals the fraction of 1/d projected.

scale = lambda * opts.CameraLength / opts.PixelSize;   % pixels * Å

spotRow   = zeros(nZone, 1);
spotCol   = zeros(nZone, 1);
intensRaw = zeros(nZone, 1);

for ii = 1:nZone
    h = hklZone(ii, 1);
    k = hklZone(ii, 2);
    l = hklZone(ii, 3);

    gVec = h * aStar + k * bStar + l * cStar;   % [1 x 3] Å⁻¹

    % Project onto zone-axis plane basis.
    gx = dot(gVec, e1);   % Å⁻¹, along e1
    gy = dot(gVec, e2);   % Å⁻¹, along e2

    % Pixel offsets.
    dCol = gx * scale;    % e1 mapped to column direction
    dRow = gy * scale;    % e2 mapped to row direction

    spotCol(ii) = centerCol + dCol;
    spotRow(ii) = centerRow + dRow;

    % Intensity proxy: multiplicity (stand-in for |F|^2).
    intensRaw(ii) = multZone(ii);
end

% ════════════════════════════════════════════════════════════════════════
%  Normalise intensities and apply MinIntensity threshold
% ════════════════════════════════════════════════════════════════════════
if max(intensRaw) > 0
    intensNorm = intensRaw / max(intensRaw);
else
    intensNorm = intensRaw;
end

keepMask = intensNorm >= opts.MinIntensity;

hklZone   = hklZone(keepMask, :);
dZone     = dZone(keepMask);
intensNorm = intensNorm(keepMask);
spotRow   = spotRow(keepMask);
spotCol   = spotCol(keepMask);

nSpots = size(hklZone, 1);

% ════════════════════════════════════════════════════════════════════════
%  Render image: add Gaussian blobs at each spot position
% ════════════════════════════════════════════════════════════════════════
H = opts.ImageSize(1);
W = opts.ImageSize(2);

img = zeros(H, W);

sigma = opts.SpotSigma;
kHalf = ceil(4 * sigma);   % kernel half-width (4-sigma truncation)

for ii = 1:nSpots
    img = addGaussianBlob(img, spotRow(ii), spotCol(ii), intensNorm(ii), sigma, kHalf);
end

% Direct beam at centre with intensity = 1.0 (max).
img = addGaussianBlob(img, centerRow, centerCol, 1.0, sigma, kHalf);

% Clip to [0, 1] in case of overlapping Gaussian additions.
img = min(img, 1);

% ════════════════════════════════════════════════════════════════════════
%  Build spots struct array
% ════════════════════════════════════════════════════════════════════════
nTotal = nSpots + 1;   % +1 for direct beam

% Initialise with the direct beam.
spots = struct( ...
    'hkl',       {[0, 0, 0]}, ...
    'dSpacing',  {NaN}, ...
    'intensity', {1.0}, ...
    'pixelRow',  {centerRow}, ...
    'pixelCol',  {centerCol});

spots(nTotal) = spots(1);   % pre-allocate

spots(1).hkl       = [0, 0, 0];
spots(1).dSpacing  = NaN;
spots(1).intensity = 1.0;
spots(1).pixelRow  = centerRow;
spots(1).pixelCol  = centerCol;

for ii = 1:nSpots
    spots(ii + 1).hkl       = hklZone(ii, :);
    spots(ii + 1).dSpacing  = dZone(ii);
    spots(ii + 1).intensity = intensNorm(ii);
    spots(ii + 1).pixelRow  = spotRow(ii);
    spots(ii + 1).pixelCol  = spotCol(ii);
end

% ════════════════════════════════════════════════════════════════════════
%  Pack result
% ════════════════════════════════════════════════════════════════════════
result.spots     = spots;
result.image     = img;
result.phaseName = phase.name;
result.formula   = phase.formula;
result.zoneAxis  = uvw;
result.lambda    = lambda;

end   % main function

% ════════════════════════════════════════════════════════════════════════
%  Local helper: Bravais centering selection rules
% ════════════════════════════════════════════════════════════════════════
function ok = isAllowedReflection(h, k, l, centering)
%ISALLOWEDREFLECTION  Check if (hkl) satisfies Bravais centering selection rules.
    switch upper(centering)
        case 'P'
            ok = true;
        case 'F'
            % FCC: h,k,l all odd or all even
            ok = (mod(h+k,2)==0) && (mod(h+l,2)==0) && (mod(k+l,2)==0);
        case 'I'
            % BCC: h+k+l even
            ok = mod(h+k+l, 2) == 0;
        case 'C'
            % C-centered: h+k even
            ok = mod(h+k, 2) == 0;
        case 'A'
            ok = mod(k+l, 2) == 0;
        case 'B'
            ok = mod(h+l, 2) == 0;
        case 'R'
            % Rhombohedral: -h+k+l = 3n
            ok = mod(-h+k+l, 3) == 0;
        otherwise
            ok = true;
    end
end

% ════════════════════════════════════════════════════════════════════════
%  Local helper: render a Gaussian blob into an image
% ════════════════════════════════════════════════════════════════════════
function img = addGaussianBlob(img, rowC, colC, amplitude, sigma, kHalf)
%ADDGAUSSIANBLOB  Add a 2-D Gaussian blob to img at sub-pixel position.
%   rowC, colC — centre (may be non-integer); kHalf — kernel half-width.

[H, W] = size(img);

% Integer bounding box.
r0 = round(rowC);
c0 = round(colC);

rMin = max(1,   r0 - kHalf);
rMax = min(H,   r0 + kHalf);
cMin = max(1,   c0 - kHalf);
cMax = min(W,   c0 + kHalf);

if rMin > rMax || cMin > cMax
    return;   % spot outside image
end

[CC, RR] = meshgrid(cMin:cMax, rMin:rMax);

blob = amplitude * exp(-((RR - rowC).^2 + (CC - colC).^2) / (2 * sigma^2));

img(rMin:rMax, cMin:cMax) = img(rMin:rMax, cMin:cMax) + blob;

end   % addGaussianBlob
