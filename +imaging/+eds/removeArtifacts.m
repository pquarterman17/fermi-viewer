function removal = removeArtifacts(energy, counts, elements, lineEnergiesKeV, options)
%REMOVEARTIFACTS  Predict, measure/model, and subtract Si-escape + sum peaks.
%
%   Syntax
%     removal = imaging.eds.removeArtifacts(energy, counts, elements, lineEnergiesKeV)
%     removal = imaging.eds.removeArtifacts(..., Name=Value)
%
%   The pre-pass for artifact-aware quantification. Artifacts predicted by
%   imaging.eds.predictArtifacts are treated according to its .blocked flag:
%
%     * FREE artifacts (clear of real lines -- most sum peaks, since the
%       high-energy region is usually empty) are MEASURED: free-amplitude
%       Gaussians at their fixed positions/Fano widths, fit jointly with a
%       linear background over a RESIDUAL spectrum (uniform weights, since a
%       residual can dip negative).
%     * BLOCKED escapes (the optimiser would steal real counts if fit
%       freely) are instead MODELED as EscapeFraction * parent net area
%       (needs ParentAreas); BLOCKED sums cannot be separated at all and are
%       SKIPPED and reported so the UI can flag them.
%
%   Inputs
%     energy, counts    numeric vectors, the raw summed spectrum (keV axis +
%                       counts)
%     elements          {1xM} cellstr, analysed element symbols
%     lineEnergiesKeV   numeric vector, parallel to ELEMENTS: their principal
%                       line energies (keV); NaN entries are ignored (matches
%                       imaging.eds.predictArtifacts)
%
%   Name-Value
%     Residual         numeric vector = []   COUNTS with the characteristic
%                      peak model already subtracted -- pass
%                      "counts - pf.fittedCurve" from imaging.eds.fitPeaks.
%                      Falls back to COUNTS when omitted.
%     ParentAreas      [1xM] double = []   element net areas, parallel to
%                      ELEMENTS (pass pf.netArea), needed to model blocked
%                      escapes. Omit (or NaN entries) to skip those escapes.
%     EscapeFraction   (1,1) double = 0.01   Si escape probability
%     ClearanceSigmas  (1,1) double = 2.0   see imaging.eds.predictArtifacts
%     IncludeEscape    (1,1) logical = true
%     IncludeSum       (1,1) logical = true
%
%   Output
%     removal  struct with fields:
%       .artifacts       the full struct array from imaging.eds.predictArtifacts
%       .measured        dictionary, artifact name -> freely-fitted net area
%       .measuredErrors  dictionary, artifact name -> 1-sigma error
%       .modeled         dictionary, artifact name -> modeled net area
%                        (blocked escapes with a known, positive parent area)
%       .skipped         string array of blocked artifact names left
%                        untouched (flag these in the UI)
%       .corrected       COUNTS minus every measured and modeled artifact
%                        curve (same length as COUNTS; backgrounds untouched)
%
%   Example
%     pf0 = imaging.eds.fitPeaks(e, counts, {'Fe','Cu'});
%     removal = imaging.eds.removeArtifacts(e, counts, {'Fe','Cu'}, ...
%         pf0.lineEnergyKeV, Residual=counts - pf0.fittedCurve, ...
%         ParentAreas=pf0.netArea);
%     pf1 = imaging.eds.fitPeaks(e, removal.corrected, {'Fe','Cu'});
%     % pf1.netArea recovers the true areas better than pf0.netArea did
%
%   See also IMAGING.EDS.PREDICTARTIFACTS, IMAGING.EDS.FITPEAKS
%
%   Reference: Goldstein et al., "Scanning Electron Microscopy and X-ray
%   Microanalysis", 4th ed., ch. 7; Statham, J. Res. NIST 107 (2002) 531.
%   Port of fermiviewer calc/eds_artifacts.py (measure_artifacts +
%   remove_artifacts).

    arguments
        energy  {mustBeNumeric, mustBeVector}
        counts  {mustBeNumeric, mustBeVector}
        elements (1,:) cell
        lineEnergiesKeV {mustBeNumeric, mustBeVector}
        options.Residual        {mustBeNumeric} = []
        options.ParentAreas     (1,:) double = []
        options.EscapeFraction  (1,1) double = 0.01
        options.ClearanceSigmas (1,1) double = 2.0
        options.IncludeEscape   (1,1) logical = true
        options.IncludeSum      (1,1) logical = true
    end

% ════════════════════════════════════════════════════════════════════════
%  Validate inputs
% ════════════════════════════════════════════════════════════════════════
energy = double(energy(:));
counts = double(counts(:));
if numel(energy) ~= numel(counts)
    error('removeArtifacts:sizeMismatch', 'energy and counts must have equal length.');
end
if options.EscapeFraction < 0 || options.EscapeFraction >= 1
    error('removeArtifacts:badEscapeFraction', 'EscapeFraction must be in [0, 1).');
end
if ~isempty(options.ParentAreas) && numel(options.ParentAreas) ~= numel(elements)
    error('removeArtifacts:parentAreasSizeMismatch', ...
        'ParentAreas must have the same length as elements.');
end
residual = double(options.Residual(:));
if ~isempty(residual) && numel(residual) ~= numel(energy)
    % Guards a real footgun: a caller building "counts - pf.fittedCurve"
    % with mismatched row/column orientation gets an implicitly-broadcast
    % N-by-N matrix (not an error) from plain subtraction; catch that here
    % rather than silently mis-sizing the downstream linear solve.
    error('removeArtifacts:residualSizeMismatch', ...
        'Residual must have the same number of elements as energy/counts.');
end

% ════════════════════════════════════════════════════════════════════════
%  Predict + partition
% ════════════════════════════════════════════════════════════════════════
artifacts = imaging.eds.predictArtifacts(elements, lineEnergiesKeV, ...
    EMinKeV=energy(1), EMaxKeV=energy(end), ...
    IncludeEscape=options.IncludeEscape, IncludeSum=options.IncludeSum, ...
    ClearanceSigmas=options.ClearanceSigmas);

blockedMask = [artifacts.blocked];
free    = artifacts(~blockedMask);
blocked = artifacts(blockedMask);

corrected = counts;

% ════════════════════════════════════════════════════════════════════════
%  Free artifacts: measure on the residual (or raw counts), subtract
% ════════════════════════════════════════════════════════════════════════
measNames = strings(1, 0);
measAreas = zeros(1, 0);
measErrs  = zeros(1, 0);

if ~isempty(free)
    if isempty(residual)
        surface = counts;
    else
        surface = residual;
    end
    [areas, errs, curves] = measureFreeArtifacts(energy, surface, free);
    for k = 1:numel(free)
        measNames(end + 1) = string(free(k).name); %#ok<AGROW>
        measAreas(end + 1) = areas(k);              %#ok<AGROW>
        measErrs(end + 1)  = errs(k);                %#ok<AGROW>
        corrected = corrected - curves(:, k);
    end
end

% ════════════════════════════════════════════════════════════════════════
%  Blocked artifacts: model escapes from a known parent area, else skip
% ════════════════════════════════════════════════════════════════════════
modNames = strings(1, 0);
modAreas = zeros(1, 0);
skipped  = strings(1, 0);

for k = 1:numel(blocked)
    a = blocked(k);
    handled = false;
    if strcmp(a.kind, 'escape') && ~isempty(options.ParentAreas)
        parentIdx = find(strcmp(elements, a.parents{1}), 1);
        if ~isempty(parentIdx)
            parentArea = options.ParentAreas(parentIdx);
            if ~isnan(parentArea)
                area = options.EscapeFraction * max(parentArea, 0);
                if area > 0
                    modNames(end + 1) = string(a.name); %#ok<AGROW>
                    modAreas(end + 1) = area;             %#ok<AGROW>
                    corrected = corrected - areaGaussian(energy, area, a.energyKeV);
                    handled = true;
                end
            end
        end
    end
    if ~handled
        skipped(end + 1) = string(a.name); %#ok<AGROW>
    end
end

% ════════════════════════════════════════════════════════════════════════
%  Assemble output
% ════════════════════════════════════════════════════════════════════════
if isempty(measNames)
    removal.measured       = dictionary(string.empty(1, 0), double.empty(1, 0));
    removal.measuredErrors = dictionary(string.empty(1, 0), double.empty(1, 0));
else
    removal.measured       = dictionary(measNames, measAreas);
    removal.measuredErrors = dictionary(measNames, measErrs);
end
if isempty(modNames)
    removal.modeled = dictionary(string.empty(1, 0), double.empty(1, 0));
else
    removal.modeled = dictionary(modNames, modAreas);
end
removal.artifacts = artifacts;
removal.skipped   = skipped;
removal.corrected = corrected;

end


% ════════════════════════════════════════════════════════════════════════
%  Local helpers
% ════════════════════════════════════════════════════════════════════════

function [areas, errors, curves] = measureFreeArtifacts(energy, counts, artifacts)
%MEASUREFREEARTIFACTS  Free-amplitude Gaussians at fixed positions/Fano
%   widths, fit jointly with a linear background (uniform weights -- COUNTS
%   here may be a residual that dips negative). Amplitudes are clamped to
%   >= 0 after the (unconstrained) linear solve -- the same documented
%   simplification as imaging.eds.fitPeaks.
    n  = numel(artifacts);
    nE = numel(energy);
    sigmas = zeros(1, n);
    X = zeros(nE, n + 2);
    for k = 1:n
        [~, sig] = imaging.eds.fanoResolution(artifacts(k).energyKeV);
        sigmas(k) = max(sig, 1e-9);
        X(:, k) = exp(-0.5 * ((energy - artifacts(k).energyKeV) / sigmas(k)) .^ 2);
    end
    X(:, n + 1) = energy;
    X(:, n + 2) = 1;

    beta = X \ counts;
    beta(1:n) = max(beta(1:n), 0);

    nParam = n + 2;
    dof = max(nE - nParam, 1);
    resid = X * beta - counts;
    reducedChi2 = sum(resid .^ 2) / dof;

    XtX = X' * X;
    if rcond(XtX) > eps
        covBase = inv(XtX);
    else
        covBase = pinv(XtX);
    end
    cov = covBase * reducedChi2;

    areas  = zeros(1, n);
    errors = zeros(1, n);
    curves = zeros(nE, n);
    for k = 1:n
        scale = sigmas(k) * sqrt(2 * pi);
        areas(k)  = beta(k) * scale;
        errors(k) = sqrt(max(cov(k, k), 0)) * scale;
        curves(:, k) = X(:, k) * beta(k);
    end
end


function curve = areaGaussian(energy, area, centerKeV)
%AREAGAUSSIAN  Area-parametrised Gaussian at the detector (Fano) width.
    [~, sigma] = imaging.eds.fanoResolution(centerKeV);
    sigma = max(sigma, 1e-9);
    amp = area / (sigma * sqrt(2 * pi));
    curve = amp * exp(-0.5 * ((energy - centerKeV) / sigma) .^ 2);
end
