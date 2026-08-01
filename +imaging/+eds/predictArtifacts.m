function artifacts = predictArtifacts(elements, lineEnergiesKeV, options)
%PREDICTARTIFACTS  Predict Si-escape + sum/pile-up peaks; flag which are blocked.
%
%   Syntax
%     artifacts = imaging.eds.predictArtifacts(elements, lineEnergiesKeV)
%     artifacts = imaging.eds.predictArtifacts(..., Name=Value)
%
%   Detector artifacts masquerade as element lines: a Si ESCAPE PEAK appears
%   1.740 keV below any sufficiently hard parent line (the detector loses one
%   Si-Ka photon), and SUM/PILE-UP PEAKS appear at E_i + E_j when two photons
%   arrive within one pulse-shaping window (including self-sums, 2*E_i --
%   the classic false-ID trap is Cu-Ka escape at 6.308 keV sitting on
%   Fe-Ka at 6.404 keV).
%
%   Each predicted artifact is also PARTITIONED by proximity to a real,
%   analysed line: an artifact is BLOCKED when it lies within
%   ClearanceSigmas*(sigma_artifact + sigma_line) of any of the input lines
%   (sigmas from imaging.eds.fanoResolution) -- too close for a
%   free-amplitude fit to separate. This single .blocked flag is enough to
%   drive spectrum markers and to route imaging.eds.removeArtifacts.
%
%   Inputs
%     elements         {1xN} cellstr of analysed element symbols
%     lineEnergiesKeV  numeric vector, parallel to ELEMENTS: each element's
%                      principal line energy (keV). NaN entries are ignored
%                      (e.g. an element imaging.eds.fitPeaks could not
%                      resolve a line for).
%
%   Name-Value
%     EMinKeV         (1,1) double = 0.2   drop artifacts below this energy
%     EMaxKeV         (1,1) double = Inf   drop artifacts above this energy
%                     (pass the spectrum's axis limits to drop off-range sums)
%     IncludeEscape   (1,1) logical = true
%     IncludeSum      (1,1) logical = true
%     ClearanceSigmas (1,1) double = 2.0   see partition rule above
%
%   Output
%     artifacts  struct array, one entry per predicted artifact, sorted by
%     ascending energy (empty 0x0 struct if none predicted):
%       .name       component-safe id, e.g. 'esc_Cu', 'sum_Fe_Cu'
%       .label      display form, e.g. 'Cu esc', 'Fe+Cu'
%       .kind       'escape' | 'sum'
%       .energyKeV  predicted peak position (keV)
%       .parents    cellstr of the generating element symbol(s) (1 for an
%                   escape, 1 or 2 for a sum -- 1 for a self-sum)
%       .blocked    true when too close to an analysed element's own line
%                   for a free-amplitude fit to separate
%
%   Examples
%     [eFe, ~] = imaging.eds.lineEnergy('Fe', BeamKV=20);
%     [eCu, ~] = imaging.eds.lineEnergy('Cu', BeamKV=20);
%     arts = imaging.eds.predictArtifacts({'Fe','Cu'}, [eFe eCu]);
%     % 5 artifacts: esc_Fe (4.664, free), esc_Cu (6.308, BLOCKED -- sits on
%     % Fe-Ka 6.404), sum_Fe_Fe (12.808), sum_Fe_Cu (14.452), sum_Cu_Cu (16.096)
%
%   See also IMAGING.EDS.REMOVEARTIFACTS, IMAGING.EDS.FANORESOLUTION
%
%   Reference: Goldstein et al., "Scanning Electron Microscopy and X-ray
%   Microanalysis", 4th ed., ch. 7 (escape and sum peaks); Statham,
%   J. Res. NIST 107 (2002) 531 (pile-up correction).
%   Port of fermiviewer calc/eds_artifacts.py (predict_artifacts +
%   partition_artifacts, merged into one call here).

    arguments
        elements         (1,:) cell
        lineEnergiesKeV  {mustBeNumeric, mustBeVector}
        options.EMinKeV         (1,1) double = 0.2
        options.EMaxKeV         (1,1) double = Inf
        options.IncludeEscape   (1,1) logical = true
        options.IncludeSum      (1,1) logical = true
        options.ClearanceSigmas (1,1) double = 2.0
    end

SI_ESCAPE_KEV = 1.740;   % Si-Ka carried away by the escaping photon
SI_K_EDGE_KEV = 1.839;   % parent must ionise Si-K for escape to occur

lineEnergiesKeV = double(lineEnergiesKeV(:).');
elements = elements(:).';
if numel(elements) ~= numel(lineEnergiesKeV)
    error('predictArtifacts:sizeMismatch', ...
        'elements and lineEnergiesKeV must have the same length.');
end

keep = ~isnan(lineEnergiesKeV);
syms  = elements(keep);
lines = lineEnergiesKeV(keep);
n = numel(syms);

artifacts = struct('name', {}, 'label', {}, 'kind', {}, 'energyKeV', {}, ...
    'parents', {}, 'blocked', {});

% ════════════════════════════════════════════════════════════════════════
%  Escape peaks: one per parent above the Si K edge
% ════════════════════════════════════════════════════════════════════════
if options.IncludeEscape
    for i = 1:n
        if lines(i) <= SI_K_EDGE_KEV, continue; end
        parentSym = {syms{i}}; %#ok<CCAT1>
        newArt = struct('name', sprintf('esc_%s', syms{i}), ...
            'label', sprintf('%s esc', syms{i}), 'kind', 'escape', ...
            'energyKeV', lines(i) - SI_ESCAPE_KEV, 'parents', {parentSym}, ...
            'blocked', false);
        artifacts(end + 1) = newArt; %#ok<AGROW>
    end
end

% ════════════════════════════════════════════════════════════════════════
%  Sum peaks: all unordered pairs, including self-sums (2*E_i)
% ════════════════════════════════════════════════════════════════════════
if options.IncludeSum
    for i = 1:n
        for j = i:n
            parentSyms = {syms{i}, syms{j}};
            newArt = struct('name', sprintf('sum_%s_%s', syms{i}, syms{j}), ...
                'label', sprintf('%s+%s', syms{i}, syms{j}), 'kind', 'sum', ...
                'energyKeV', lines(i) + lines(j), 'parents', {parentSyms}, ...
                'blocked', false);
            artifacts(end + 1) = newArt; %#ok<AGROW>
        end
    end
end

if isempty(artifacts)
    return
end

% ════════════════════════════════════════════════════════════════════════
%  Range filter + energy sort
% ════════════════════════════════════════════════════════════════════════
e = [artifacts.energyKeV];
inRange = e >= options.EMinKeV & e <= options.EMaxKeV;
artifacts = artifacts(inRange);
if isempty(artifacts), return; end

[~, ord] = sort([artifacts.energyKeV]);
artifacts = artifacts(ord);

% ════════════════════════════════════════════════════════════════════════
%  Partition: blocked when within ClearanceSigmas*(sigma_a + sigma_line)
%  of any analysed element's line
% ════════════════════════════════════════════════════════════════════════
for k = 1:numel(artifacts)
    [~, sigA] = imaging.eds.fanoResolution(artifacts(k).energyKeV);
    near = false;
    for i = 1:n
        [~, sigL] = imaging.eds.fanoResolution(lines(i));
        if abs(artifacts(k).energyKeV - lines(i)) < options.ClearanceSigmas * (sigA + sigL)
            near = true;
            break
        end
    end
    artifacts(k).blocked = near;
end

end
