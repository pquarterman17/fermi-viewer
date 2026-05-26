function result = eelsQuantify(energyAxis, spectrum, elements, E0kV, betaMrad, opts)
%EELSQUANTIFY  Quantitative atomic composition from EELS core-loss edges.
%
%   Syntax:
%       result = imaging.eels.eelsQuantify(energyAxis, spectrum, elements, ...
%                    E0kV, betaMrad)
%       result = imaging.eels.eelsQuantify(..., BackgroundMethod='powerlaw')
%
%   Converts background-subtracted inner-shell edge intensities into relative
%   atomic composition (at%) using the standard EELS quantification relation
%   (Egerton 2011, Eq. 4.65):
%
%       N_A / N_B = [ I_A(beta,Delta) / sigma_A(beta,Delta) ]
%                 / [ I_B(beta,Delta) / sigma_B(beta,Delta) ]
%
%   where I_X is the background-subtracted edge intensity integrated over a
%   signal window of width Delta_X, and sigma_X is the partial ionization
%   cross-section for the same beta and Delta_X.  Because every element is
%   measured under the same incident beam, the low-loss intensity I_0 and the
%   single-scattering normalisation cancel in the *ratio*, so absolute I_0 is
%   not required for relative composition (at%).
%
%   For each element the routine:
%     1. Fits and subtracts the background with imaging.eels.eelsBackground
%        using the element's bgWindow (pre-edge fit window).
%     2. Integrates the background-subtracted signal over signalWindow (trapz)
%        to obtain I_X.
%     3. Computes sigma_X via imaging.eels.eelsCrossSection with
%        Delta = width(signalWindow) and the element's onset.
%     4. Forms the areal ratio  r_X = I_X / sigma_X  and normalises:
%            at%_X = 100 * r_X / sum_j r_j .
%
%   Inputs:
%       energyAxis — [N x 1] energy-loss axis (eV), strictly increasing
%       spectrum   — [N x 1] core-loss spectrum intensity (counts or cps)
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
%       BackgroundMethod — 'powerlaw' (default) | 'exponential', forwarded to
%                          imaging.eels.eelsBackground.
%
%   Outputs:
%       result — struct with fields (each [1 x M], M = numel(elements)):
%                  .element       string array of element symbols
%                  .atomicPercent at% vector summing to 100
%                  .intensity     integrated background-subtracted I_X
%                  .sigma         partial cross-section sigma_X (m^2)
%                  .arealRatio    r_X = I_X / sigma_X (proportional to N_X)
%
%   NOTE: This v1 handles a single 1-D spectrum.  Spectrum-image (3-D cube)
%   composition maps are a TODO — loop this routine per pixel once SI speed
%   is addressed.
%
%   Examples:
%       el(1) = struct('element','C','shell',"K",'Z',6,'onsetEV',284, ...
%                      'signalWindow',[284 384],'bgWindow',[230 280]);
%       el(2) = struct('element','O','shell',"K",'Z',8,'onsetEV',532, ...
%                      'signalWindow',[532 632],'bgWindow',[470 525]);
%       r = imaging.eels.eelsQuantify(E, I, el, 200, 10);
%       disp([r.element(:), string(r.atomicPercent(:))]);
%
%   See also imaging.eels.eelsCrossSection, imaging.eels.eelsBackground,
%            imaging.eels.eelsEdgeTable

% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    energyAxis (:,1) double {mustBeNonempty}
    spectrum   (:,1) double {mustBeNonempty}
    elements   (1,:) struct {mustBeNonempty}
    E0kV       (1,1) double {mustBePositive}
    betaMrad   (1,1) double {mustBePositive}
    opts.BackgroundMethod (1,1) string ...
        {mustBeMember(opts.BackgroundMethod, {'powerlaw','exponential'})} = 'powerlaw'
end

energyAxis = double(energyAxis(:));
spectrum   = double(spectrum(:));

if numel(energyAxis) ~= numel(spectrum)
    error('imaging:eels:eelsQuantify:sizeMismatch', ...
        'energyAxis and spectrum must have the same number of elements.');
end

reqFields = {'element','shell','Z','onsetEV','signalWindow','bgWindow'};
for f = reqFields
    if ~isfield(elements, f{1})
        error('imaging:eels:eelsQuantify:missingField', ...
            'elements struct is missing required field "%s".', f{1});
    end
end

M = numel(elements);

% ════════════════════════════════════════════════════════════════════════
%  Per-element intensity and cross-section
% ════════════════════════════════════════════════════════════════════════
symList    = strings(1, M);
intensity  = zeros(1, M);
sigma      = zeros(1, M);
arealRatio = zeros(1, M);

for k = 1:M
    el = elements(k);

    sigWin = double(el.signalWindow(:)');
    bgWin  = double(el.bgWindow(:)');
    if numel(sigWin) ~= 2 || numel(bgWin) ~= 2
        error('imaging:eels:eelsQuantify:badWindow', ...
            'Element %d: signalWindow and bgWindow must each be [E1 E2].', k);
    end

    % --- background subtraction over the full axis using the pre-edge window
    sig = imaging.eels.eelsBackground(energyAxis, spectrum, ...
        FitWindow=bgWin, Method=opts.BackgroundMethod);

    % --- integrate background-subtracted signal over signal window ----------
    sigMask = energyAxis >= sigWin(1) & energyAxis <= sigWin(2);
    if sum(sigMask) < 2
        error('imaging:eels:eelsQuantify:tooFewPoints', ...
            'Element %d: signalWindow [%.1f %.1f] has < 2 channels.', ...
            k, sigWin(1), sigWin(2));
    end
    I_X = trapz(energyAxis(sigMask), sig(sigMask));
    I_X = max(I_X, 0);

    % --- partial cross-section for the same Delta and beta ------------------
    deltaEV = sigWin(2) - sigWin(1);
    s_X = imaging.eels.eelsCrossSection( ...
        double(el.Z), string(el.shell), E0kV, betaMrad, deltaEV, double(el.onsetEV));

    symList(k)    = string(el.element);
    intensity(k)  = I_X;
    sigma(k)      = s_X;
    if s_X > 0
        arealRatio(k) = I_X / s_X;            % proportional to areal density N_X
    else
        arealRatio(k) = 0;
    end
end

% ════════════════════════════════════════════════════════════════════════
%  Normalise to atomic percent
% ════════════════════════════════════════════════════════════════════════
total = sum(arealRatio);
if total > 0
    atomicPercent = 100 * arealRatio / total;
else
    atomicPercent = zeros(1, M);
end

result = struct( ...
    'element',       symList, ...
    'atomicPercent', atomicPercent, ...
    'intensity',     intensity, ...
    'sigma',         sigma, ...
    'arealRatio',    arealRatio);

end
