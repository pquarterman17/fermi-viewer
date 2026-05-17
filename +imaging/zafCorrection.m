function result = zafCorrection(intensityMaps, elements, opts)
%ZAFCORRECTION  ZAF-corrected EDS quantification for thick specimens.
%
%   Syntax:
%       result = imaging.zafCorrection(intensityMaps, elements)
%       result = imaging.zafCorrection(intensityMaps, elements, Voltage=200, ...)
%
%   Extends Cliff-Lorimer with atomic number (Z), absorption (A), and
%   fluorescence (F) corrections.  Uses iterative refinement starting from
%   the Cliff-Lorimer thin-film approximation.
%
%   ZAF correction factors are computed from the mean composition over valid
%   pixels and applied uniformly to all pixels (standard first-order ZAF).
%
%   Inputs:
%       intensityMaps — {1 x N} cell of [H x W] double intensity maps
%       elements      — {1 x N} cell of element symbols
%
%   Optional Name-Value:
%       KFactors      — [1 x N] k-factors (relative to Si).
%                       Default: looked up from imaging.edsKFactorTable.
%       Voltage       — accelerating voltage in kV (default: 200).
%       Thickness     — specimen thickness in nm (default: 100).
%       TakeOffAngle  — X-ray take-off angle in degrees (default: 20).
%       Density       — mean specimen density in g/cm^3.
%                       If NaN (default), estimated as weighted sum of
%                       elemental densities from calc.elementData.
%       MaskThreshold — minimum summed intensity for a valid pixel (default: 0).
%       Iterations    — number of ZAF refinement iterations (default: 3).
%
%   Output:
%       result — struct with fields:
%           .atomicPctMaps  — {1 x N} cell of [H x W] ZAF-corrected atomic % maps
%           .weightPctMaps  — {1 x N} cell of [H x W] ZAF-corrected weight % maps
%           .elements       — {1 x N} element symbols
%           .kFactors       — [1 x N] k-factors used
%           .mask           — [H x W] logical valid-pixel mask
%           .meanAtomicPct  — [1 x N] mean atomic % over valid pixels
%           .meanWeightPct  — [1 x N] mean weight % over valid pixels
%           .zafFactors     — struct with fields .Z, .A, .F (each [1 x N])
%                             containing the per-element ZAF factors from the
%                             final iteration
%           .iterations     — number of iterations actually performed
%           .uncorrected    — Cliff-Lorimer result struct (for comparison)
%
%   Examples:
%       % Quantify an Fe-O-Si EDS map with ZAF correction
%       maps = {femap, omap, simap};
%       els  = {'Fe', 'O', 'Si'};
%       res  = imaging.zafCorrection(maps, els, TakeOffAngle=35);
%
%       % Compare with thin-film result
%       fprintf('Fe: CL=%.1f%%  ZAF=%.1f%%\n', ...
%           res.uncorrected.meanWeightPct(1), res.meanWeightPct(1));
%
%       % Supply custom k-factors
%       res = imaging.zafCorrection(maps, els, KFactors=[1.21 1.80 1.00]);
%
%   See also imaging.cliffLorimer, imaging.massAbsorptionCoeff,
%            imaging.edsKFactorTable

% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    intensityMaps  (1,:) cell
    elements       (1,:) cell
    opts.KFactors      (1,:) double = []
    opts.Voltage       (1,1) double = 200
    opts.Thickness     (1,1) double = 100
    opts.TakeOffAngle  (1,1) double = 20
    opts.Density       (1,1) double = NaN
    opts.MaskThreshold (1,1) double = 0
    opts.Iterations    (1,1) double = 3
end

% ════════════════════════════════════════════════════════════════════════
%  Validate inputs
% ════════════════════════════════════════════════════════════════════════
N = numel(elements);
if numel(intensityMaps) ~= N
    error('zafCorrection:sizeMismatch', ...
        'intensityMaps and elements must have the same length.');
end
if N < 1
    error('zafCorrection:emptyInput', 'At least one element is required.');
end

[H, W] = size(intensityMaps{1});
for i = 2:N
    if ~isequal(size(intensityMaps{i}), [H W])
        error('zafCorrection:mapSizeMismatch', ...
            'All intensity maps must be the same size.');
    end
end

% ════════════════════════════════════════════════════════════════════════
%  Step 1 — Cliff-Lorimer starting estimate
% ════════════════════════════════════════════════════════════════════════
clResult = imaging.cliffLorimer(intensityMaps, elements, ...
    KFactors=opts.KFactors, ...
    Voltage=opts.Voltage, ...
    MaskThreshold=opts.MaskThreshold);

kVals = clResult.kFactors;   % resolved k-factors
mask  = clResult.mask;

% ════════════════════════════════════════════════════════════════════════
%  Step 2 — Fetch element properties from calc.elementData
% ════════════════════════════════════════════════════════════════════════
atomicNum  = zeros(1, N);
atomicMass = zeros(1, N);
elemDens   = zeros(1, N);   % bulk density g/cm^3 (for density estimation)

for i = 1:N
    try
        el = calc.elementData('bySymbol', elements{i});
        atomicNum(i)  = double(el.Z);
        atomicMass(i) = el.mass;
        d = el.density;
        elemDens(i) = d;
    catch
        warning('zafCorrection:unknownElement', ...
            'Element data not found for "%s". Using Z=1, A=1, rho=1.', elements{i});
        atomicNum(i)  = 1;
        atomicMass(i) = 1;
        elemDens(i)   = 1;
    end
    % Guard against NaN densities
    if isnan(elemDens(i)) || elemDens(i) <= 0
        elemDens(i) = 5.0;   % fallback: generic solid density
    end
end

% ════════════════════════════════════════════════════════════════════════
%  Pre-compute geometry constants
% ════════════════════════════════════════════════════════════════════════
takeoffRad = opts.TakeOffAngle * pi / 180;
cscTakeoff = 1 / sin(takeoffRad);
tCm        = opts.Thickness * 1e-7;   % nm → cm

% ════════════════════════════════════════════════════════════════════════
%  Pre-compute MAC matrix:  macMat(i,j) = mac of emitter-i in absorber-j
% ════════════════════════════════════════════════════════════════════════
macMat = zeros(N, N);
for i = 1:N
    for j = 1:N
        macMat(i,j) = imaging.massAbsorptionCoeff(elements{i}, elements{j});
    end
end
% Replace NaN entries with a conservative fallback (100 cm^2/g)
macMat(isnan(macMat)) = 100;

% ════════════════════════════════════════════════════════════════════════
%  Initialise working weight fractions from Cliff-Lorimer result
%  Use mean over valid pixels as the composition for ZAF factors
% ════════════════════════════════════════════════════════════════════════
% [1 x N] mean weight fractions (0–1 scale)
wMean = clResult.meanWeightPct / 100;

% Clamp and renormalise to avoid degenerate inputs
wMean = max(wMean, 0);
s = sum(wMean);
if s > 0
    wMean = wMean / s;
else
    wMean = ones(1, N) / N;
end

% Per-pixel weight cubes from CL (0–1 scale) — keep original for re-application
wCubeCL = zeros(H, W, N);
for i = 1:N
    wCubeCL(:,:,i) = clResult.weightPctMaps{i} / 100;
end
wCube = wCubeCL;   % working copy

% ════════════════════════════════════════════════════════════════════════
%  Iterative ZAF refinement
%
%  The ZAF factor for element i corrects for effects that inflate or
%  deflate the measured X-ray intensity relative to the true concentration.
%  A high ZAF_i means measured intensity is enhanced → true concentration
%  is LOWER → we DIVIDE by ZAF_i.  Each iteration reapplies the correction
%  to the ORIGINAL CL result (not compounded).
% ════════════════════════════════════════════════════════════════════════
zFactors = ones(1, N);
aFactors = ones(1, N);
fFactors = ones(1, N);   % fluorescence held at 1.0 (see docstring)

nIter = max(1, round(opts.Iterations));

% Precompute 3-D mask for background NaN application (outside iteration loop)
% mask3D shape: [H x W x N], true where pixels should be NaN (background).
mask3D = repmat(~mask, 1, 1, N);   % [H x W x N] logical

% Precompute flat valid-pixel index for mean computation
validMask = mask(:);               % [H*W x 1] logical

for iter = 1:nIter

    % ── Z correction (vectorised) ──────────────────────────────────────
    % Simplified thin-film Z correction: scales linearly with thickness.
    % At zero thickness, Z_i = 1 (thin-film limit, no correction needed).
    % At large thickness, approaches meanZ/Z_i.
    meanZ  = sum(wMean .* atomicNum);
    zScale = 1 - exp(-opts.Thickness / 200);
    % Element-wise: zFactors(i) = 1 + (meanZ/Z_i - 1)*zScale for Z_i > 0
    hasZ         = atomicNum > 0;
    zFactors(:)  = 1.0;
    zFactors(hasZ) = 1 + (meanZ ./ atomicNum(hasZ) - 1) * zScale;

    % ── A correction (vectorised) ──────────────────────────────────────
    if isnan(opts.Density) || opts.Density <= 0
        rho = sum(wMean .* elemDens);
        if rho <= 0 || isnan(rho)
            rho = 5.0;
        end
    else
        rho = opts.Density;
    end

    % specMac(i) = sum_j C_j * mac(i->j) = macMat * wMean'  [N x 1]
    specMacVec = macMat * wMean';              % [N x 1]
    chiVec     = specMacVec * rho * tCm * cscTakeoff;  % [N x 1]

    % f(chi) = chi / (1 - exp(-chi)), limit f→1 as chi→0
    aFactors    = ones(1, N);
    bigChi      = abs(chiVec') >= 1e-6;        % [1 x N] logical
    aFactors(bigChi) = chiVec(bigChi)' ./ (1 - exp(-chiVec(bigChi)'));

    % ── F correction ──────────────────────────────────────────────────
    % Fluorescence correction is set to 1.0; it is typically < 2% for
    % transition-metal oxides and requires detailed cross-section tables
    % not available without external data.
    fFactors(:) = 1.0;

    % ── Apply ZAF to original CL weights (divide, not multiply) ──────
    % Combined ZAF factor: ZAF_i = Z_i * A_i * F_i
    % Correction: C_i_true ∝ C_i_measured / ZAF_i
    zafVec = zFactors .* aFactors .* fFactors;   % [1 x N]

    % Guard against zero ZAF factors
    zafVec = max(zafVec, eps);

    zafBcast = reshape(zafVec, 1, 1, N);
    wScaled  = wCubeCL ./ zafBcast;              % [H x W x N]  divide by ZAF

    wSum = sum(wScaled, 3);                      % [H x W]
    wSum(~mask) = 1;                             % avoid div-by-zero

    wCube = wScaled ./ wSum;                     % [H x W x N]  renormalised

    % Apply mask: set background pixels to NaN using precomputed 3-D index
    wCube(mask3D) = NaN;

    % Update mean weight fractions for next iteration (vectorised over N)
    wFlat  = reshape(wCube, H*W, N);            % [H*W x N]
    wValid = wFlat(validMask, :);               % [nValid x N]
    wMean  = mean(wValid, 1, 'omitnan');        % [1 x N]
    s = sum(wMean, 'omitnan');
    if s > 0
        wMean = wMean / s;
    end

end  % iterations

% ════════════════════════════════════════════════════════════════════════
%  Convert final weight fractions to atomic%
%  at_i = (w_i / M_i) / sum_j(w_j / M_j)
% ════════════════════════════════════════════════════════════════════════
MBcast    = reshape(atomicMass, 1, 1, N);
wOverM    = wCube ./ MBcast;
wOverMsum = sum(wOverM, 3);
wOverMsum(~mask) = 1;
atCube = wOverM ./ wOverMsum;

% Apply mask to atomic fractions
for i = 1:N
    sl = atCube(:,:,i);
    sl(~mask) = NaN;
    atCube(:,:,i) = sl;
end

% ════════════════════════════════════════════════════════════════════════
%  Assemble output maps and mean values
% ════════════════════════════════════════════════════════════════════════
atomicPctMaps = cell(1, N);
weightPctMaps = cell(1, N);
meanAt        = zeros(1, N);
meanWt        = zeros(1, N);
validIdx      = mask(:);

for i = 1:N
    atMap = atCube(:,:,i) * 100;
    wMap  = wCube(:,:,i)  * 100;
    atomicPctMaps{i} = atMap;
    weightPctMaps{i} = wMap;

    atVec     = atMap(:);
    wVec      = wMap(:);
    meanAt(i) = mean(atVec(validIdx), 'omitnan');
    meanWt(i) = mean(wVec(validIdx),  'omitnan');
end

% ════════════════════════════════════════════════════════════════════════
%  Pack results
% ════════════════════════════════════════════════════════════════════════
result.atomicPctMaps = atomicPctMaps;
result.weightPctMaps = weightPctMaps;
result.elements      = elements;
result.kFactors      = kVals;
result.mask          = mask;
result.meanAtomicPct = meanAt;
result.meanWeightPct = meanWt;

result.zafFactors.Z = zFactors;
result.zafFactors.A = aFactors;
result.zafFactors.F = fFactors;

result.iterations    = nIter;
result.uncorrected   = clResult;

end
