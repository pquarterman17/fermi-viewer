function maps = extractElementMaps(cube, energyAxis, elements, options)
%EXTRACTELEMENTMAPS  Build per-element EDS maps from a hypercube.
%
%   maps = imaging.eds.extractElementMaps(cube, energyAxis, elements) returns
%   a struct array with one entry per element symbol in the cell array
%   ELEMENTS, each holding the element's distribution map integrated over a
%   window around its principal characteristic line.
%
%   Fields of each maps(k):
%     .symbol   element symbol (e.g. 'Cu')
%     .line     line family used ('K'/'L'/'M')
%     .energy   line energy (keV)
%     .window   [eLo eHi] integration window (keV)
%     .map      [H x W] double intensity map
%     .total    total counts in the map
%   Elements whose line is unknown or falls outside the energy axis are
%   skipped (with a warning), so numel(maps) may be < numel(elements).
%
%   Name-Value
%   ──────────
%   HalfWindow  (1,1) double  Half-width of the integration window in keV
%                             (default 0.085, ≈ a typical EDS FWHM/2 near Mn).
%   Background  'linear' (default) | 'none' | 'bremsstrahlung'   Passed to
%                             elementMap.
%   BeamKV      (1,1) double  Accelerating voltage, for line auto-selection
%                             (default Inf).
%   E0KeV       (1,1) double  Beam energy / Duane-Hunt cutoff (keV), passed to
%                             elementMap. REQUIRED when Background=
%                             'bremsstrahlung' (default NaN).
%   Units       string  Energy-axis units ('' (default) | 'kev' | 'ev' |
%                        'mev', case-insensitive), passed through
%                        imaging.eds.toKeV before windowing. Line energies
%                        and HalfWindow are always keV; some spectrum-image
%                        formats (Gatan DM, FEI TIA/SER) calibrate their
%                        axis in eV, and comparing a keV window against an
%                        un-converted eV axis silently selects almost no
%                        channels and returns a blank map. Default '' leaves
%                        ENERGYAXIS unchanged (the common BCF/already-keV
%                        path allocates nothing).
%
%   Example
%   ───────
%     d   = parser.importBCF('map.bcf');
%     eds = d.metadata.parserSpecific.edsData;
%     m   = imaging.eds.extractElementMaps(eds.cube, eds.energyAxis, eds.elements);
%     imagesc(m(1).map); title(m(1).symbol); axis image;
%
%     % Axis calibrated in eV (e.g. a DM spectrum image)
%     m = imaging.eds.extractElementMaps(cube, eaxEV, {'Cu'}, Units='eV');
%
%   See also IMAGING.EDS.LINEENERGY, IMAGING.EDS.ELEMENTMAP, IMAGING.EDS.TOKEV,
%            IMPORTBCF

    arguments
        cube                    {mustBeNumeric}
        energyAxis   (:,1) double
        elements     cell
        options.HalfWindow (1,1) double = 0.085
        options.Background (1,1) string = "linear"
        options.BeamKV     (1,1) double = Inf
        options.E0KeV      (1,1) double = NaN
        options.Units      (1,1) string = ""
    end

    energyAxis = imaging.eds.toKeV(energyAxis, options.Units);

    maps = struct('symbol', {}, 'line', {}, 'energy', {}, ...
                  'window', {}, 'map', {}, 'total', {});
    if isempty(elements)
        return;
    end
    eMin = min(energyAxis); eMax = max(energyAxis);
    hw = options.HalfWindow;

    for k = 1:numel(elements)
        sym = elements{k};
        if ~(ischar(sym) || isstring(sym)) || strlength(string(sym)) == 0
            continue;
        end
        [e, line] = imaging.eds.lineEnergy(string(sym), BeamKV=options.BeamKV);
        if isnan(e)
            warning('imaging:eds:extractElementMaps:unknownElement', ...
                'No known line for "%s" — skipped.', char(sym));
            continue;
        end
        if e < eMin || e > eMax
            warning('imaging:eds:extractElementMaps:outOfRange', ...
                '%s %sα line (%.3f keV) is outside the energy axis — skipped.', ...
                char(sym), line, e);
            continue;
        end
        [m, ~] = imaging.eds.elementMap(cube, energyAxis, e-hw, e+hw, ...
            Background=options.Background, E0KeV=options.E0KeV);
        entry.symbol = char(sym);
        entry.line   = line;
        entry.energy = e;
        entry.window = [e-hw, e+hw];
        entry.map    = m;
        entry.total  = sum(m(:));
        maps(end+1) = entry; %#ok<AGROW>
    end
end
