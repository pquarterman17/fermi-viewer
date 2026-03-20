function result = cliffLorimer(intensityMaps, elements, opts)
%CLIFFLORIMER  Cliff-Lorimer thin-film EDS quantification.
%
%   Syntax:
%       result = imaging.cliffLorimer(intensityMaps, elements)
%       result = imaging.cliffLorimer(intensityMaps, elements, KFactors=k, ...)
%
%   Computes atomic% and weight% maps from EDS intensity maps using the
%   Cliff-Lorimer relation:
%
%       C_A / C_B = k_AB * (I_A / I_B),   where k_AB = k_A / k_B
%
%   Weight fractions are computed as:
%
%       w_i = k_i * I_i / sum_j(k_j * I_j)
%
%   then normalised so sum(w_i) = 1 per pixel.  Atomic fractions follow from
%   w_i / M_i (M = atomic mass), renormalised to sum = 1.
%
%   Inputs:
%       intensityMaps — {1 x N} cell array of [H x W] double intensity maps
%       elements      — {1 x N} cell array of element symbol strings
%
%   Optional Name-Value:
%       KFactors      — [1 x N] double k-factors (relative to Si).
%                       Default: looked up from imaging.edsKFactorTable.
%       RefElement    — scalar index into elements used as Cliff-Lorimer
%                       reference (default: 1). Currently informational only;
%                       the normalised formulation makes the result
%                       reference-independent.
%       MaskThreshold — minimum summed intensity for a pixel to be considered
%                       valid (default: 0). Pixels below threshold → NaN.
%       Voltage       — accelerating voltage kV passed to edsKFactorTable
%                       when KFactors is not supplied (default: 200).
%
%   Output:
%       result — struct with fields:
%           .atomicPctMaps — {1 x N} cell of [H x W] atomic % maps
%           .weightPctMaps — {1 x N} cell of [H x W] weight % maps
%           .elements      — {1 x N} element symbols used
%           .kFactors      — [1 x N] k-factors used
%           .mask          — [H x W] logical valid-pixel mask
%           .meanAtomicPct — [1 x N] mean atomic % over valid pixels
%           .meanWeightPct — [1 x N] mean weight % over valid pixels
%
%   Examples:
%       % Quantify a three-element EDS map
%       maps = {femap, omap, simap};
%       els  = {'Fe', 'O', 'Si'};
%       res  = imaging.cliffLorimer(maps, els);
%       imagesc(res.atomicPctMaps{1});   % Fe atomic %
%       title(sprintf('Fe: %.1f at%%', res.meanAtomicPct(1)));
%
%       % Supply custom k-factors
%       res = imaging.cliffLorimer(maps, els, KFactors=[1.21 1.80 1.00]);
%
%   See also imaging.edsKFactorTable, imaging.edsCompositionProfile

% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    intensityMaps (1,:) cell
    elements      (1,:) cell
    opts.KFactors      (1,:) double = []
    opts.RefElement    (1,1) double = 1
    opts.MaskThreshold (1,1) double = 0
    opts.Voltage       (1,1) double = 200
end

% ════════════════════════════════════════════════════════════════════════
%  Validate inputs
% ════════════════════════════════════════════════════════════════════════
N = numel(elements);
if numel(intensityMaps) ~= N
    error('cliffLorimer:sizeMismatch', ...
        'intensityMaps and elements must have the same length.');
end

[H, W] = size(intensityMaps{1});
for i = 2:N
    if ~isequal(size(intensityMaps{i}), [H W])
        error('cliffLorimer:mapSizeMismatch', ...
            'All intensity maps must be the same size.');
    end
end

% ════════════════════════════════════════════════════════════════════════
%  Resolve k-factors
% ════════════════════════════════════════════════════════════════════════
if isempty(opts.KFactors)
    kTable = imaging.edsKFactorTable(Voltage=opts.Voltage);
    kVals  = zeros(1, N);
    for i = 1:N
        sym = elements{i};
        if isKey(kTable, sym)
            kVals(i) = kTable(sym);
        else
            warning('cliffLorimer:unknownElement', ...
                'No built-in k-factor for "%s". Using k = 1.00 (Si reference).', sym);
            kVals(i) = 1.00;
        end
    end
else
    if numel(opts.KFactors) ~= N
        error('cliffLorimer:kFactorLength', ...
            'KFactors must have the same length as elements.');
    end
    kVals = opts.KFactors;
end

% ════════════════════════════════════════════════════════════════════════
%  Fetch atomic masses from calc.elementData
% ════════════════════════════════════════════════════════════════════════
atomicMass = zeros(1, N);
for i = 1:N
    try
        el = calc.elementData('bySymbol', elements{i});
        atomicMass(i) = el.mass;
    catch
        warning('cliffLorimer:unknownMass', ...
            'Atomic mass not found for "%s". Using 1.0 amu.', elements{i});
        atomicMass(i) = 1.0;
    end
end

% ════════════════════════════════════════════════════════════════════════
%  Build stacked intensity cube [H x W x N]
% ════════════════════════════════════════════════════════════════════════
ICube = zeros(H, W, N);
for i = 1:N
    ICube(:,:,i) = double(intensityMaps{i});
end

% ════════════════════════════════════════════════════════════════════════
%  Valid-pixel mask
% ════════════════════════════════════════════════════════════════════════
totalIntensity = sum(ICube, 3);          % [H x W]
mask = totalIntensity > opts.MaskThreshold;

% ════════════════════════════════════════════════════════════════════════
%  Cliff-Lorimer weight fractions
%  w_i = k_i * I_i / sum_j(k_j * I_j)
% ════════════════════════════════════════════════════════════════════════
% Broadcast k-factors across the spatial dimensions
kBcast = reshape(kVals, 1, 1, N);       % [1 x 1 x N]
kI     = ICube .* kBcast;               % [H x W x N]
kIsum  = sum(kI, 3);                    % [H x W]  denominator

% Avoid divide-by-zero on masked pixels
kIsum(~mask) = 1;                       % temporary; will be set to NaN below

wFrac = kI ./ kIsum;                    % [H x W x N]  weight fractions (0–1)

% ════════════════════════════════════════════════════════════════════════
%  Convert weight% → atomic%
%  at_i = (w_i / M_i) / sum_j(w_j / M_j)
% ════════════════════════════════════════════════════════════════════════
MBcast   = reshape(atomicMass, 1, 1, N);
wOverM   = wFrac ./ MBcast;             % [H x W x N]
wOverMsum = sum(wOverM, 3);            % [H x W]
wOverMsum(~mask) = 1;

atFrac = wOverM ./ wOverMsum;           % [H x W x N]  atomic fractions (0–1)

% ════════════════════════════════════════════════════════════════════════
%  Apply mask: set invalid pixels to NaN
% ════════════════════════════════════════════════════════════════════════
maskNot = ~mask;
for i = 1:N
    wSlice         = wFrac(:,:,i);
    wSlice(maskNot) = NaN;
    wFrac(:,:,i)   = wSlice;

    atSlice         = atFrac(:,:,i);
    atSlice(maskNot) = NaN;
    atFrac(:,:,i)   = atSlice;
end

% ════════════════════════════════════════════════════════════════════════
%  Assemble output struct
% ════════════════════════════════════════════════════════════════════════
atomicPctMaps = cell(1, N);
weightPctMaps = cell(1, N);
meanAt        = zeros(1, N);
meanWt        = zeros(1, N);

validIdx = mask(:);                     % logical column vector

for i = 1:N
    atMap = atFrac(:,:,i) * 100;
    wMap  = wFrac(:,:,i)  * 100;
    atomicPctMaps{i} = atMap;
    weightPctMaps{i} = wMap;

    atVec    = atMap(:);
    wVec     = wMap(:);
    meanAt(i) = mean(atVec(validIdx), 'omitnan');
    meanWt(i) = mean(wVec(validIdx),  'omitnan');
end

result.atomicPctMaps = atomicPctMaps;
result.weightPctMaps = weightPctMaps;
result.elements      = elements;
result.kFactors      = kVals;
result.mask          = mask;
result.meanAtomicPct = meanAt;
result.meanWeightPct = meanWt;

end
