function result = eelsQuantifyMap(cube, energyAxis, elements, E0kV, betaMrad, opts)
%EELSQUANTIFYMAP  Per-pixel atomic composition maps from an EELS spectrum image.
%
%   Syntax:
%       result = imaging.eels.eelsQuantifyMap(cube, energyAxis, elements, ...
%                    E0kV, betaMrad)
%       result = imaging.eels.eelsQuantifyMap(..., BackgroundMethod='powerlaw')
%
%   Spectrum-image (SI) companion to imaging.eels.eelsQuantify: applies the
%   same Egerton quantification relation (Egerton 2011, Eq. 4.65)
%
%       N_A / N_B = [ I_A(beta,Delta) / sigma_A(beta,Delta) ]
%                 / [ I_B(beta,Delta) / sigma_B(beta,Delta) ]
%
%   at every spatial pixel of an [Ny x Nx x nE] cube, producing relative
%   composition (at%) maps. The per-channel arithmetic is identical to the
%   scalar routine — a cube whose pixels all hold the same spectrum yields
%   maps that match eelsQuantify on that spectrum to floating-point
%   round-off — but the background fit is vectorised across all Ny*Nx
%   pixels at once (one least-squares solve per element instead of Np
%   polyfit calls), the same approach used by imaging.eels.eelsExtractMap.
%
%   Per element the routine:
%     1. Fits the background model in the pre-edge bgWindow simultaneously
%        for all pixels (powerlaw: linear fit in log-log space;
%        exponential: log-linear), mirroring imaging.eels.eelsBackground.
%     2. Subtracts the extrapolated background over signalWindow and clamps
%        negatives to 0, then integrates per pixel (trapz) to get I_X maps.
%     3. Computes the partial cross-section sigma_X ONCE (it depends only on
%        the edge and optics, not the pixel) via imaging.eels.eelsCrossSection.
%     4. Forms r_X = I_X / sigma_X per pixel and normalises:
%            at%_X = 100 * r_X / sum_j r_j   (0 where the pixel total is 0).
%
%   Inputs:
%       cube       — [Ny x Nx x nE] spectrum image (any numeric type)
%       energyAxis — [nE x 1] energy-loss axis (eV), strictly increasing
%       elements   — struct array, one entry per element to quantify, fields:
%                       .element      char/string symbol (e.g. 'C')
%                       .shell        "K" or "L"
%                       .Z            atomic number
%                       .onsetEV      edge onset energy (eV)
%                       .signalWindow [E1 E2] integration window above onset
%                       .bgWindow     [E1 E2] pre-edge background fit window
%       E0kV       — incident beam energy (kV)
%       betaMrad   — collection semi-angle (mrad)
%
%   Optional Name-Value:
%       BackgroundMethod — 'powerlaw' (default) | 'exponential'
%
%   Outputs:
%       result — struct with fields (M = numel(elements)):
%                  .element       [1 x M] string array of element symbols
%                  .atomicPercent [Ny x Nx x M] at% maps; each pixel sums to
%                                 100 across M (or all-zero where no signal)
%                  .intensity     [Ny x Nx x M] integrated bg-subtracted I_X
%                  .sigma         [1 x M] partial cross-sections (m^2)
%                  .arealRatio    [Ny x Nx x M] r_X = I_X / sigma_X
%
%   Examples:
%       el(1) = struct('element','C','shell',"K",'Z',6,'onsetEV',284, ...
%                      'signalWindow',[284 384],'bgWindow',[230 280]);
%       el(2) = struct('element','O','shell',"K",'Z',8,'onsetEV',532, ...
%                      'signalWindow',[532 632],'bgWindow',[470 525]);
%       r = imaging.eels.eelsQuantifyMap(cube, E, el, 200, 10);
%       imagesc(r.atomicPercent(:,:,1)); colorbar;
%       title(sprintf('%s at%%', r.element(1)));
%
%   See also imaging.eels.eelsQuantify, imaging.eels.eelsCrossSection,
%            imaging.eels.eelsExtractMap, imaging.eels.eelsBackground

% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    cube       (:,:,:) {mustBeNumeric, mustBeNonempty}
    energyAxis (:,1) double {mustBeNonempty}
    elements   (1,:) struct {mustBeNonempty}
    E0kV       (1,1) double {mustBePositive}
    betaMrad   (1,1) double {mustBePositive}
    opts.BackgroundMethod (1,1) string ...
        {mustBeMember(opts.BackgroundMethod, {'powerlaw','exponential'})} = 'powerlaw'
end

[Ny, Nx, nE] = size(cube);
energyAxis = double(energyAxis(:));

if numel(energyAxis) ~= nE
    error('imaging:eels:eelsQuantifyMap:sizeMismatch', ...
        'energyAxis length (%d) must match cube third dimension (%d).', ...
        numel(energyAxis), nE);
end

reqFields = {'element','shell','Z','onsetEV','signalWindow','bgWindow'};
for f = reqFields
    if ~isfield(elements, f{1})
        error('imaging:eels:eelsQuantifyMap:missingField', ...
            'elements struct is missing required field "%s".', f{1});
    end
end

M  = numel(elements);
Np = Ny * Nx;

% Reshape cube once to [nE x Np] for matrix ops (shared by every element)
specMat = reshape(permute(double(cube), [3 1 2]), nE, Np);

% ════════════════════════════════════════════════════════════════════════
%  Per-element intensity maps and cross-sections
% ════════════════════════════════════════════════════════════════════════
symList    = strings(1, M);
sigma      = zeros(1, M);
intensity  = zeros(M, Np);          % [M x Np], reshaped at the end
arealRatio = zeros(M, Np);

for k = 1:M
    el = elements(k);

    sigWin = double(el.signalWindow(:)');
    bgWin  = double(el.bgWindow(:)');
    if numel(sigWin) ~= 2 || numel(bgWin) ~= 2
        error('imaging:eels:eelsQuantifyMap:badWindow', ...
            'Element %d: signalWindow and bgWindow must each be [E1 E2].', k);
    end

    fitMask = energyAxis >= bgWin(1) & energyAxis <= bgWin(2);
    if sum(fitMask) < 2
        error('imaging:eels:eelsQuantifyMap:tooFewBgPoints', ...
            'Element %d: bgWindow [%.1f %.1f] has < 2 channels.', ...
            k, bgWin(1), bgWin(2));
    end

    sigMask = energyAxis >= sigWin(1) & energyAxis <= sigWin(2);
    if sum(sigMask) < 2
        error('imaging:eels:eelsQuantifyMap:tooFewPoints', ...
            'Element %d: signalWindow [%.1f %.1f] has < 2 channels.', ...
            k, sigWin(1), sigWin(2));
    end

    Efit = energyAxis(fitMask);                          % [K  x 1]
    Esig = energyAxis(sigMask);                          % [Ks x 1]
    K    = numel(Efit);

    Ifit = specMat(fitMask, :);                          % [K  x Np]
    Isig = specMat(sigMask, :);                          % [Ks x Np]

    % Clamp non-positive pre-edge intensities before the log transform
    % (matches the scalar eelsBackground's `Ifit = max(Ifit, eps)`).
    IfitClamped = max(Ifit, eps);

    % ── Vectorised background fit + reconstruction over the signal window.
    %    Two-step exp(A)*... formulation matches eelsBackground exactly so
    %    degenerate pixels overflow/underflow identically (see the parity
    %    notes in imaging.eels.eelsExtractMap).
    switch opts.BackgroundMethod
        case 'powerlaw'
            X = [log(Efit), ones(K, 1)];                 % [K x 2] (slope, intercept)
            coeffs = X \ log(IfitClamped);               % [2 x Np]
            A = exp(coeffs(2, :));                       % [1 x Np]
            r = -coeffs(1, :);                           % [1 x Np]
            Eguard = max(Esig, eps);
            bgSig  = (Eguard .^ (-r)) .* A;              % [Ks x Np]

        case 'exponential'
            X = [Efit, ones(K, 1)];
            coeffs = X \ log(IfitClamped);
            A = exp(coeffs(2, :));
            b = coeffs(1, :);
            bgSig = exp(Esig * b) .* A;                  % [Ks x Np]
    end

    % Background-subtract, clamp negatives (per channel, BEFORE integration —
    % same order as the scalar path: eelsBackground clamps signal, then
    % eelsQuantify integrates). NaN-safe for pathological pixels.
    sigSubtr = max(Isig - bgSig, 0);                     % [Ks x Np]
    sigSubtr(isnan(sigSubtr)) = 0;

    % Trapezoidal integration per pixel over the signal window
    I_X = trapz(Esig, sigSubtr);                         % [1 x Np]
    I_X = max(I_X, 0);

    % ── Partial cross-section: pixel-independent, computed once ──────────
    deltaEV = sigWin(2) - sigWin(1);
    s_X = imaging.eels.eelsCrossSection( ...
        double(el.Z), string(el.shell), E0kV, betaMrad, deltaEV, double(el.onsetEV));

    symList(k)   = string(el.element);
    sigma(k)     = s_X;
    intensity(k, :) = I_X;
    if s_X > 0
        arealRatio(k, :) = I_X / s_X;
    end
end

% ════════════════════════════════════════════════════════════════════════
%  Normalise to atomic percent per pixel
% ════════════════════════════════════════════════════════════════════════
total = sum(arealRatio, 1);                              % [1 x Np]
atomicPercent = zeros(M, Np);
hasSignal = total > 0;
atomicPercent(:, hasSignal) = 100 * arealRatio(:, hasSignal) ./ total(hasSignal);

% Reshape [M x Np] → [Ny x Nx x M] (columns of specMat are column-major
% pixel order, so reshape restores the spatial layout directly)
toMaps = @(m) reshape(m.', Ny, Nx, M);

result = struct( ...
    'element',       symList, ...
    'atomicPercent', toMaps(atomicPercent), ...
    'intensity',     toMaps(intensity), ...
    'sigma',         sigma, ...
    'arealRatio',    toMaps(arealRatio));

end
