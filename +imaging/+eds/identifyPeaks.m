function peaks = identifyPeaks(sumSpectrum, energyAxis, options)
%IDENTIFYPEAKS  Detect EDS sum-spectrum peaks and match them to element lines.
%
%   peaks = imaging.eds.identifyPeaks(sumSpectrum, energyAxis) finds the most
%   prominent peaks in an EDS sum spectrum and assigns each to the nearest
%   known characteristic X-ray line (via imaging.eds.lineEnergy). It exists to
%   auto-populate element maps for BCF files whose header does not list
%   identified elements (edsData.elements == {}), so that "Enter EDS Mode" can
%   still show meaningful element distributions instead of a blank survey.
%
%   The detector is deliberately toolbox-free (no Signal Processing
%   findpeaks): it lightly smooths the spectrum, takes strict local maxima
%   above a height threshold, enforces a minimum energy separation so a single
%   element's Kα/Kβ pair is not double-counted, and keeps the tallest MaxPeaks.
%
%   Inputs
%   ──────
%   sumSpectrum  [C x 1] numeric   Integrated counts per channel.
%   energyAxis   [C x 1] double    Energy (keV) of each channel.
%
%   Name-Value
%   ──────────
%   MaxPeaks      (1,1) double = 8      Maximum number of peaks returned.
%   MinEnergy     (1,1) double = 0.2    Ignore peaks below this keV (the zero-
%                                       strobe peak and low-energy noise).
%   Tolerance     (1,1) double = 0.06   keV match window to a known line.
%   MinSeparation (1,1) double = 0.12   Minimum keV between accepted peaks.
%   HeightFrac    (1,1) double = 0.04   A peak must exceed this fraction of the
%                                       spectrum maximum to count.
%   BeamKV        (1,1) double = Inf    Accelerating voltage, for K/L/M line
%                                       auto-selection (heavy elements).
%
%   Output
%   ──────
%   peaks  Struct array sorted by descending height, one entry per peak:
%     .energy  Peak-centre energy (keV).
%     .height  Peak counts.
%     .symbol  Matched element symbol ('' if none within Tolerance).
%     .line    Matched line family 'K'/'L'/'M' ('' if none).
%     .label   Display label: 'Fe Kα' when matched, else '6.40 keV'.
%
%   Example
%   ───────
%     d   = parser.importBCF('map.bcf');
%     eds = d.metadata.parserSpecific.edsData;
%     pk  = imaging.eds.identifyPeaks(eds.sumSpectrum, eds.energyAxis);
%     {pk.label}      % -> {'Cu Kα','O Kα','C Kα', ...}
%
%   See also IMAGING.EDS.LINEENERGY, IMAGING.EDS.EXTRACTELEMENTMAPS

    arguments
        sumSpectrum                {mustBeNumeric}
        energyAxis      (:,1) double
        options.MaxPeaks      (1,1) double = 8
        options.MinEnergy     (1,1) double = 0.2
        options.Tolerance     (1,1) double = 0.06
        options.MinSeparation (1,1) double = 0.12
        options.HeightFrac    (1,1) double = 0.04
        options.BeamKV        (1,1) double = Inf
    end

    peaks = struct('energy', {}, 'height', {}, 'symbol', {}, 'line', {}, 'label', {});

    s = double(sumSpectrum(:));
    e = energyAxis(:);
    n = numel(s);
    if n < 3 || numel(e) ~= n || all(s == 0)
        return;
    end

    % Light 3-point moving average to suppress single-channel noise spikes
    % without shifting peak centres.
    sm = s;
    sm(2:end-1) = (s(1:end-2) + s(2:end-1) + s(3:end)) / 3;

    smax = max(sm);
    if smax <= 0, return; end
    heightThresh = options.HeightFrac * smax;

    % Strict interior local maxima above threshold and above MinEnergy.
    isMax = false(n, 1);
    isMax(2:end-1) = sm(2:end-1) > sm(1:end-2) & ...
                     sm(2:end-1) >= sm(3:end)  & ...
                     sm(2:end-1) >= heightThresh & ...
                     e(2:end-1)  >= options.MinEnergy;
    cand = find(isMax);
    if isempty(cand), return; end

    % Sort candidates tallest-first, then greedily accept while honouring the
    % minimum energy separation (drops Kβ next to a stronger Kα, etc.).
    [~, ord] = sort(sm(cand), 'descend');
    cand = cand(ord);
    acceptedE = [];
    acceptedI = [];
    for k = 1:numel(cand)
        ei = e(cand(k));
        if isempty(acceptedE) || all(abs(acceptedE - ei) >= options.MinSeparation)
            acceptedE(end+1) = ei;          %#ok<AGROW>
            acceptedI(end+1) = cand(k);     %#ok<AGROW>
        end
        if numel(acceptedI) >= options.MaxPeaks, break; end
    end

    % Reverse lookup table: known element -> principal line energy at BeamKV.
    [refSym, refE, refLine] = lineTable(options.BeamKV);

    for k = 1:numel(acceptedI)
        idx = acceptedI(k);
        pe  = e(idx);
        entry = struct('energy', pe, 'height', sm(idx), ...
                       'symbol', '', 'line', '', ...
                       'label', sprintf('%.2f keV', pe));
        [dmin, mi] = min(abs(refE - pe));
        if ~isempty(mi) && dmin <= options.Tolerance
            entry.symbol = refSym{mi};
            entry.line   = refLine{mi};
            entry.label  = sprintf('%s %s%s', refSym{mi}, refLine{mi}, alpha());
        end
        peaks(end+1) = entry; %#ok<AGROW>
    end
end


function a = alpha()
%ALPHA  The Greek alpha used in line labels ('Kα'); kept as a helper so the
%   literal is defined once and the file stays ASCII-clean above.
    a = char(945);   % α
end


function [syms, energies, lines] = lineTable(beamKV)
%LINETABLE  Principal-line energy for each common EDS element at BeamKV.
%   Built by querying imaging.eds.lineEnergy for a curated element list, so the
%   energies stay in lock-step with that single source of truth.
    syms = {'Be','B','C','N','O','F','Ne','Na','Mg','Al','Si','P','S','Cl', ...
            'Ar','K','Ca','Sc','Ti','V','Cr','Mn','Fe','Co','Ni','Cu','Zn', ...
            'Ga','Ge','As','Se','Br','Rb','Sr','Y','Zr','Nb','Mo','Ru','Rh', ...
            'Pd','Ag','Cd','In','Sn','Sb','Ba','La','Ce','Nd','Sm','Gd','Dy', ...
            'Er','Yb','Hf','Ta','W','Re','Os','Ir','Pt','Au','Hg','Tl','Pb', ...
            'Bi','Th','U'};
    energies = nan(numel(syms), 1);
    lines    = repmat({''}, numel(syms), 1);
    keep     = false(numel(syms), 1);
    for i = 1:numel(syms)
        [en, ln] = imaging.eds.lineEnergy(syms{i}, BeamKV=beamKV);
        if ~isnan(en)
            energies(i) = en;
            lines{i}    = ln;
            keep(i)     = true;
        end
    end
    syms     = syms(keep);
    energies = energies(keep);
    lines    = lines(keep);
end
