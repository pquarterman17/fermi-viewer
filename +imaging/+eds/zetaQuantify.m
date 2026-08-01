function result = zetaQuantify(intensityMaps, elements, zetaFactors, opts)
%ZETAQUANTIFY  Zeta-factor (Watanabe-Williams) EDS quantification.
%
%   Syntax:
%       result = imaging.eds.zetaQuantify(intensityMaps, elements, zetaFactors, ...
%                     DoseElectrons=dose)
%       result = imaging.eds.zetaQuantify(intensityMaps, elements, zetaFactors, ...
%                     BeamCurrentNA=1.0, LiveTimeS=100, ...)
%
%   Cliff-Lorimer (imaging.eds.cliffLorimer) works on intensity *ratios*, so
%   it yields composition but never thickness and cannot correct its own
%   absorption. The zeta-factor method instead relates each element's net
%   intensity *absolutely* to mass-thickness via the electron dose:
%
%       C_i * rho*t = zeta_i * I_i / D_e
%
%   Summing over elements (sum(C_i) = 1) gives the mass-thickness for free:
%
%       rho*t = sum_j(zeta_j * I_j) / D_e,      C_i = zeta_i*I_i / sum_j(zeta_j*I_j)
%
%   and the known rho*t then feeds a self-consistent thin-film absorption
%   correction (iterated): the measured intensity of element i is restored by
%
%       A_i = chi_i*rho*t / (1 - exp(-chi_i*rho*t)),   chi_i = csc(alpha) * sum_j (mu/rho)_i^j * w_j
%
%   Units: zeta carries kg/m^2 (per electron per photon) -- Watanabe's SI
%   convention -- so rho*t comes out in kg/m^2. The k<->zeta bridge
%   k_ij = zeta_i/zeta_j lets one absolute zeta (e.g. for Si) scale the
%   built-in 200 kV Cliff-Lorimer k-factor table into estimated zeta values
%   (imaging.eds.zetaFromKFactors); rigorous work supplies per-element zeta
%   from measured standards.
%
%   Inputs:
%       intensityMaps — per-element net intensities, either:
%                         * [1 x N] row vector — one scalar intensity per
%                           element (a single summed spectrum), or
%                         * [H x W x N] numeric cube — one [H x W] map per
%                           element, stacked along the 3rd dimension
%                       N must equal numel(elements).
%       elements      — {1 x N} cell array of element symbol strings
%       zetaFactors   — [1 x N] zeta-factor per element (kg/m^2); see
%                       imaging.eds.zetaFromKFactors to estimate these from
%                       one absolute standard plus the k-factor table.
%
%   Optional Name-Value:
%       DoseElectrons — total electron dose D_e = I*tau/e. Supply this OR
%                       both BeamCurrentNA and LiveTimeS (default: NaN).
%       BeamCurrentNA — probe current in nA, used with LiveTimeS to compute
%                       DoseElectrons via imaging.eds.doseElectrons
%                       (default: NaN).
%       LiveTimeS     — acquisition live time in seconds (default: NaN).
%       TakeoffDeg    — X-ray take-off angle alpha in degrees, (0,90)
%                       (default: 20).
%       Absorption    — iterate the self-consistent thin-film absorption
%                       correction (default: true). Cliff-Lorimer cannot do
%                       this at all; zeta-factor's known rho*t is what makes
%                       it possible.
%       NIter         — absorption-loop iteration count (default: 5).
%                       NIter=0 (or Absorption=false) skips the correction
%                       entirely and returns the closed-form, single-pass
%                       answer.
%       Density       — optional specimen density (g/cm^3) used to convert
%                       rho*t into a thickness map in nm (default: NaN ->
%                       thickness_nm is left empty).
%       MaskThreshold — pixels with summed intensity <= this are NaN
%                       (default: 0).
%
%   Output:
%       result — struct with fields:
%           .weightFrac        — [H x W x N] weight fraction (0-1); NaN off-mask
%           .atomicPct         — [H x W x N] atomic %  (0-100); NaN off-mask
%                                 (atomic-mass renormalisation, same
%                                 convention as imaging.eds.cliffLorimer)
%           .meanWeightFrac    — [1 x N] mean weight fraction over valid pixels
%           .meanAtomicPct     — [1 x N] mean atomic % over valid pixels
%           .rhoT_kg_m2        — [H x W] mass-thickness map (kg/m^2); NaN off-mask
%           .rhoT_ug_cm2       — [H x W] same, in µg/cm^2 (rhoT_kg_m2 * 1e5)
%           .meanRhoT_kg_m2    — scalar mean mass-thickness (kg/m^2)
%           .meanRhoT_ug_cm2   — scalar, µg/cm^2
%           .thickness_nm      — [H x W] thickness map (nm); [] unless Density given
%           .meanThickness_nm  — scalar; NaN unless Density given
%           .absorptionFactors — [1 x N] converged field-mean absorption
%                                 factors A_i (>= 1; all 1.0 when the
%                                 correction is off)
%           .iterations        — number of absorption iterations actually run
%           .mask              — [H x W] logical valid-pixel mask
%           .elements          — {1 x N} element symbols (echoed)
%           .zetaFactors       — [1 x N] zeta-factors used (echoed)
%           .dose              — electron dose D_e used
%
%   Examples:
%       % Two elements, no absorption -- exact hand check:
%       % sum(zeta.*I) = 500*2000 + 1000*1000 = 2e6 -> w = (0.5, 0.5),
%       % rho*t = 2e6/1e10 = 2e-4 kg/m^2
%       r = imaging.eds.zetaQuantify([2000 1000], {'Fe','O'}, [500 1000], ...
%               DoseElectrons=1e10, Absorption=false);
%       r.meanWeightFrac * 100      % -> [50 50]
%       r.meanRhoT_kg_m2            % -> 2e-4
%
%       % Estimate zeta from one absolute Si standard, then quantify a map
%       zeta = imaging.eds.zetaFromKFactors({'Fe','O'}, 1000.0);
%       r = imaging.eds.zetaQuantify(cat(3, feMap, oMap), {'Fe','O'}, zeta, ...
%               BeamCurrentNA=1.0, LiveTimeS=100, Density=5.2);
%
%   See also imaging.eds.zetaFromKFactors, imaging.eds.doseElectrons,
%            imaging.eds.cliffLorimer, imaging.eds.massAbsorptionCoeff

% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    intensityMaps double
    elements      (1,:) cell
    zetaFactors   (1,:) double
    opts.DoseElectrons (1,1) double = NaN
    opts.BeamCurrentNA (1,1) double = NaN
    opts.LiveTimeS     (1,1) double = NaN
    opts.TakeoffDeg    (1,1) double {mustBeGreaterThan(opts.TakeoffDeg,0), mustBeLessThan(opts.TakeoffDeg,90)} = 20
    opts.Absorption    (1,1) logical = true
    opts.NIter         (1,1) double {mustBeNonnegative} = 5
    opts.Density       (1,1) double = NaN
    opts.MaskThreshold (1,1) double = 0
end

% ════════════════════════════════════════════════════════════════════════
%  Validate inputs
% ════════════════════════════════════════════════════════════════════════
N = numel(elements);
if numel(zetaFactors) ~= N
    error('zetaQuantify:zetaLengthMismatch', ...
        'zetaFactors must have the same length as elements.');
end
if any(zetaFactors <= 0)
    error('zetaQuantify:zetaSign', 'zetaFactors must be positive.');
end

% ════════════════════════════════════════════════════════════════════════
%  Resolve electron dose: explicit DoseElectrons, or BeamCurrentNA+LiveTimeS
% ════════════════════════════════════════════════════════════════════════
if ~isnan(opts.DoseElectrons)
    dose = opts.DoseElectrons;
elseif ~isnan(opts.BeamCurrentNA) && ~isnan(opts.LiveTimeS)
    dose = imaging.eds.doseElectrons(opts.BeamCurrentNA, opts.LiveTimeS);
else
    error('zetaQuantify:doseRequired', ...
        'Supply DoseElectrons, or both BeamCurrentNA and LiveTimeS.');
end
if dose <= 0
    error('zetaQuantify:doseSign', 'dose must be positive.');
end
if ~isnan(opts.Density) && opts.Density <= 0
    error('zetaQuantify:densitySign', 'Density must be positive.');
end

% ════════════════════════════════════════════════════════════════════════
%  Resolve intensity cube: [1 x N] scalar spectrum, or [H x W x N] map cube
% ════════════════════════════════════════════════════════════════════════
cube = localResolveCube(intensityMaps, N);
[H, W, ~] = size(cube);

% Clamp stray negative counts (e.g. background-subtraction artifacts) to
% zero without disturbing NaN (NaN < 0 is false, so NaN pixels pass through).
cube(cube < 0) = 0;

% ════════════════════════════════════════════════════════════════════════
%  Valid-pixel mask
% ════════════════════════════════════════════════════════════════════════
totalIntensity = sum(cube, 3);
mask = totalIntensity > opts.MaskThreshold;

% ════════════════════════════════════════════════════════════════════════
%  Absorption setup. NIter=0 behaves exactly like Absorption=false: a
%  single closed-form pass with no self-consistent correction.
% ════════════════════════════════════════════════════════════════════════
doAbsorption = opts.Absorption && opts.NIter > 0;
if doAbsorption
    mac = localMacMatrix(elements);                        % [N x N] m^2/kg
    takeoffRad = opts.TakeoffDeg * pi / 180;
    cscTakeoff = 1 / sin(takeoffRad);
    nIterMax   = max(1, round(opts.NIter));
else
    mac = [];
    cscTakeoff = NaN;
    nIterMax   = 1;
end

% ════════════════════════════════════════════════════════════════════════
%  Fixed-point loop: (w, rho*t) -> absorption A -> restored intensities
%  q = gen.*zeta;  rho*t = sum(q,3)/dose;  w = q./sum(q,3)
%  chi_i(px) = csc(alpha) * sum_j mac(i,j)*w_j(px);  x = chi.*rho*t
%  A = x./(1-exp(-x)), A=1 where |x|<1e-6;  gen = measured .* A
% ════════════════════════════════════════════════════════════════════════
zetaBcast = reshape(zetaFactors, 1, 1, N);
gen       = cube;
w         = zeros(H, W, N);
rhoT      = zeros(H, W);
absFac    = ones(1, N);
iterUsed  = 0;

for iter = 1:nIterMax
    iterUsed = iter;

    q      = gen .* zetaBcast;              % zeta_i*I_i per pixel
    qSum   = sum(q, 3);                     % [H x W]
    rhoT   = qSum / dose;                   % kg/m^2
    safe   = qSum;
    safe(safe <= 0) = 1;                    % avoid divide-by-zero
    w      = q ./ safe;                     % [H x W x N] broadcast over dim 3

    if ~doAbsorption
        break
    end

    wFlat   = reshape(w, H*W, N);           % [HW x N]
    chiFlat = (wFlat * mac') * cscTakeoff;  % chi_i = csc * sum_j mac(i,j)*w_j
    chi     = reshape(chiFlat, H, W, N);
    x       = chi .* rhoT;                  % broadcast [H x W] over dim 3

    aMap = ones(H, W, N);
    big  = abs(x) >= 1e-6;
    aMap(big) = x(big) ./ (1 - exp(-x(big)));

    gen = cube .* aMap;

    aFlat = reshape(aMap, H*W, N);
    valid = mask(:);
    if any(valid)
        absFac = mean(aFlat(valid, :), 1);
    else
        absFac = ones(1, N);
    end
end

% ════════════════════════════════════════════════════════════════════════
%  Weight% -> atomic%: at_i = (w_i/M_i) / sum_j(w_j/M_j)  (same convention
%  as imaging.eds.cliffLorimer)
% ════════════════════════════════════════════════════════════════════════
masses = zeros(1, N);
for i = 1:N
    try
        el = calc.elementData('bySymbol', elements{i});
        masses(i) = el.mass;
    catch
        warning('zetaQuantify:unknownMass', ...
            'Atomic mass not found for "%s". Using 1.0 amu.', elements{i});
        masses(i) = 1.0;
    end
end

wOverM  = w ./ reshape(masses, 1, 1, N);
mSum    = sum(wOverM, 3);
mSafe   = mSum;
mSafe(mSafe <= 0) = 1;
atFrac  = wOverM ./ mSafe;

% ════════════════════════════════════════════════════════════════════════
%  Apply mask (NaN off-mask) and assemble per-pixel outputs
% ════════════════════════════════════════════════════════════════════════
maskNot     = ~mask;
weightFrac  = w;
atomicPct   = atFrac * 100;
for i = 1:N
    wSlice = weightFrac(:,:,i);
    wSlice(maskNot) = NaN;
    weightFrac(:,:,i) = wSlice;

    aSlice = atomicPct(:,:,i);
    aSlice(maskNot) = NaN;
    atomicPct(:,:,i) = aSlice;
end

rhoT_kg_m2 = rhoT;
rhoT_kg_m2(maskNot) = NaN;
rhoT_ug_cm2 = rhoT_kg_m2 * 1e5;    % kg/m^2 -> µg/cm^2

% ════════════════════════════════════════════════════════════════════════
%  Field means over valid pixels
% ════════════════════════════════════════════════════════════════════════
validIdx = mask(:);
if any(validIdx)
    meanWeightFrac = zeros(1, N);
    meanAtomicPct  = zeros(1, N);
    for i = 1:N
        wVec = reshape(weightFrac(:,:,i), [], 1);
        aVec = reshape(atomicPct(:,:,i),  [], 1);
        meanWeightFrac(i) = mean(wVec(validIdx), 'omitnan');
        meanAtomicPct(i)  = mean(aVec(validIdx),  'omitnan');
    end
    rtVec = reshape(rhoT_kg_m2, [], 1);
    meanRhoT_kg_m2 = mean(rtVec(validIdx), 'omitnan');
else
    meanWeightFrac = nan(1, N);
    meanAtomicPct  = nan(1, N);
    meanRhoT_kg_m2 = NaN;
end
meanRhoT_ug_cm2 = meanRhoT_kg_m2 * 1e5;

% ════════════════════════════════════════════════════════════════════════
%  Optional thickness from density: t = rho*t / rho
% ════════════════════════════════════════════════════════════════════════
thickness_nm     = [];
meanThickness_nm = NaN;
if ~isnan(opts.Density)
    rhoSI = opts.Density * 1000;              % g/cm^3 -> kg/m^3
    thickness_nm     = rhoT_kg_m2 / rhoSI * 1e9;   % m -> nm
    meanThickness_nm = meanRhoT_kg_m2 / rhoSI * 1e9;
end

% ════════════════════════════════════════════════════════════════════════
%  Assemble output struct
% ════════════════════════════════════════════════════════════════════════
result.weightFrac        = weightFrac;
result.atomicPct         = atomicPct;
result.meanWeightFrac    = meanWeightFrac;
result.meanAtomicPct     = meanAtomicPct;
result.rhoT_kg_m2        = rhoT_kg_m2;
result.rhoT_ug_cm2       = rhoT_ug_cm2;
result.meanRhoT_kg_m2    = meanRhoT_kg_m2;
result.meanRhoT_ug_cm2   = meanRhoT_ug_cm2;
result.thickness_nm      = thickness_nm;
result.meanThickness_nm  = meanThickness_nm;
result.absorptionFactors = absFac;
result.iterations        = iterUsed;
result.mask              = mask;
result.elements          = elements;
result.zetaFactors       = zetaFactors;
result.dose              = dose;

end

% ════════════════════════════════════════════════════════════════════════
%  Local helpers
% ════════════════════════════════════════════════════════════════════════
function cube = localResolveCube(raw, nEl)
%LOCALRESOLVECUBE  Accept either a [1 x nEl] scalar spectrum or an
%[H x W x nEl] map cube and normalise to [H x W x nEl].
raw = double(raw);
if isvector(raw) && numel(raw) == nEl
    cube = reshape(raw, 1, 1, nEl);
elseif ndims(raw) == 3 && size(raw, 3) == nEl
    cube = raw;
elseif ismatrix(raw) && nEl == 1
    cube = reshape(raw, size(raw,1), size(raw,2), 1);
else
    error('zetaQuantify:intensityShapeMismatch', ...
        ['intensityMaps must be a 1x%d vector (scalar intensity per ' ...
         'element) or an HxWx%d cube (one map per element).'], nEl, nEl);
end
end

function mac = localMacMatrix(elements)
%LOCALMACMATRIX  (emitter,absorber) mass-absorption-coefficient matrix in
%m^2/kg. Unknown/non-finite pairs fall back to a bland 100 cm^2/g before
%unit conversion (10 m^2/kg), matching the reference zeta-factor model.
n   = numel(elements);
mac = zeros(n, n);
for i = 1:n
    for j = 1:n
        mac(i,j) = imaging.eds.massAbsorptionCoeff(elements{i}, elements{j});
    end
end
mac(~isfinite(mac)) = 100.0;    % cm^2/g bland fallback
mac = mac * 0.1;                % cm^2/g -> m^2/kg
end
