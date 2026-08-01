function [map, info] = elementMap(cube, energyAxis, eLo, eHi, options)
%ELEMENTMAP  Integrate an EDS hypercube over an energy window into a 2-D map.
%
%   map = imaging.eds.elementMap(cube, energyAxis, eLo, eHi) sums the counts
%   in each pixel's spectrum between energies eLo and eHi (keV), producing an
%   [H x W] intensity map suitable for displaying elemental distribution.
%
%   map = imaging.eds.elementMap(..., Background='linear') first subtracts a
%   per-pixel linear background interpolated from two side windows just below
%   and above the peak window, giving a net (background-corrected) map. This
%   removes the bremsstrahlung continuum so the map reflects characteristic
%   X-rays rather than overall count rate.
%
%   map = imaging.eds.elementMap(..., Background='bremsstrahlung', E0KeV=hv)
%   instead subtracts a PHYSICAL Kramers continuum: the continuum SHAPE is
%   fixed pure Kramers c(E) = max(E0-E,0)/max(E,eps) (zero at and above the
%   beam energy / Duane-Hunt cutoff E0), and only its per-pixel AMPLITUDE is
%   solved in closed form (a least-squares scale of that shape to the
%   flanking background windows) -- one dot product per pixel, vectorized
%   over the whole map, never a per-pixel curve fit. This tracks the true
%   convex continuum shape far better than the 'linear' chord, which
%   over-subtracts near a steep low-energy rise. E0KeV is REQUIRED for this
%   mode and must exceed the peak window's upper edge.
%
%   [map, info] = imaging.eds.elementMap(...) also returns a struct with the
%   channel ranges used (.peakChans, .bgLoChans, .bgHiChans) and .total.
%
%   Inputs
%   ------
%   cube        [H x W x C] numeric   EDS hypercube (counts per channel).
%   energyAxis  [C x 1] double        Energy (keV) of each channel.
%   eLo, eHi    (1,1) double          Peak window bounds (keV), eLo < eHi.
%
%   Name-Value
%   ----------
%   Background  'none' (default) | 'linear' | 'bremsstrahlung'
%   BgWidth     (1,1) double   Width of each side background window in keV
%                              (default: the peak-window width). Used by
%                              'linear' and 'bremsstrahlung'.
%   BgGap       (1,1) double   Gap (keV) between the peak window and each side
%                              window (default 0). Used by 'linear' and
%                              'bremsstrahlung'.
%   E0KeV       (1,1) double   Beam energy / Duane-Hunt cutoff (keV). REQUIRED
%                              when Background='bremsstrahlung' (default NaN).
%                              window (default 0).
%   Units       string  Energy-axis units ('' (default) | 'kev' | 'ev' |
%                        'mev', case-insensitive), passed through
%                        imaging.eds.toKeV before windowing. ELO/EHI are
%                        always keV; some spectrum-image formats (Gatan DM,
%                        FEI TIA/SER) calibrate their axis in eV, and
%                        comparing a keV window against an un-converted eV
%                        axis silently selects almost no channels and
%                        returns a blank map. Default '' leaves ENERGYAXIS
%                        unchanged (the common BCF/already-keV path
%                        allocates nothing).
%
%   Output is double; negative net values (over-subtraction) are clamped to 0.
%
%   Only the flanking background channels (and the peak window) are ever
%   read from cube, and always at cube's native class -- a small slice is
%   promoted to double, never the whole (possibly multi-GB) cube.
%
%   Example
%   -------
%     e   = imaging.eds.lineEnergy('Cu');           % 8.048 keV
%     map = imaging.eds.elementMap(cube, eax, e-0.10, e+0.10, Background='linear');
%     imagesc(map); axis image; colormap hot;
%
%     % physical Kramers continuum at a 20 kV beam energy
%     map = imaging.eds.elementMap(cube, eax, e-0.10, e+0.10, ...
%         Background='bremsstrahlung', E0KeV=20);
%
%   See also IMAGING.EDS.LINEENERGY, IMAGING.EDS.EXTRACTELEMENTMAPS,
%            IMAGING.EDS.FITCONTINUUM, IMPORTBCF
%     % Axis calibrated in eV (e.g. a DM spectrum image)
%     map = imaging.eds.elementMap(cube, eaxEV, e-0.10, e+0.10, Units='eV');
%
%   See also IMAGING.EDS.LINEENERGY, IMAGING.EDS.EXTRACTELEMENTMAPS,
%            IMAGING.EDS.TOKEV, IMPORTBCF

    arguments
        cube                       {mustBeNumeric}
        energyAxis      (:,1) double
        eLo             (1,1) double
        eHi             (1,1) double
        options.Background (1,1) string = "none"
        options.BgWidth    (1,1) double = NaN
        options.BgGap      (1,1) double = 0
        options.E0KeV      (1,1) double = NaN
        options.Units      (1,1) string = ""
    end

    energyAxis = imaging.eds.toKeV(energyAxis, options.Units);

    if eHi < eLo
        [eLo, eHi] = deal(eHi, eLo);
    end
    sz = size(cube);
    if numel(sz) < 3
        error('imaging:eds:elementMap:notACube', ...
            'cube must be [H x W x C]; got size [%s].', num2str(sz));
    end
    H = sz(1); W = sz(2); C = sz(3);
    if numel(energyAxis) ~= C
        error('imaging:eds:elementMap:axisMismatch', ...
            'energyAxis length (%d) must equal cube channel count (%d).', ...
            numel(energyAxis), C);
    end

    peakChans = find(energyAxis >= eLo & energyAxis <= eHi);
    info = struct('peakChans', peakChans, 'bgLoChans', [], 'bgHiChans', [], 'total', 0);
    if isempty(peakChans)
        map = zeros(H, W);
        return;
    end

    peakSum = windowSum(cube, peakChans);

    switch lower(char(options.Background))
        case 'bremsstrahlung'
            [map, loChans, hiChans] = kramersBgMap(cube, energyAxis, peakChans, peakSum, ...
                eLo, eHi, options.E0KeV, options.BgWidth, options.BgGap);
            info.bgLoChans = loChans;
            info.bgHiChans = hiChans;
        case 'linear'
            [loChans, hiChans] = sideWindows(energyAxis, eLo, eHi, options.BgWidth, options.BgGap);
            info.bgLoChans = loChans;
            info.bgHiChans = hiChans;

            nPeak = numel(peakChans);
            if ~isempty(loChans) && ~isempty(hiChans)
                % Mean count per channel on each side, interpolated under the peak.
                loRate = windowSum(cube, loChans) / numel(loChans);
                hiRate = windowSum(cube, hiChans) / numel(hiChans);
                bgPerChan = 0.5 * (loRate + hiRate);   % midpoint of the linear fit
                map = peakSum - bgPerChan * nPeak;
            elseif ~isempty(loChans)
                map = peakSum - (windowSum(cube, loChans) / numel(loChans)) * nPeak;
            elseif ~isempty(hiChans)
                map = peakSum - (windowSum(cube, hiChans) / numel(hiChans)) * nPeak;
            else
                map = peakSum;   % no side windows available
            end
            map = max(map, 0);
        otherwise
            map = peakSum;
    end

    info.total = sum(map(:));
end


function s = windowSum(cube, chans)
%WINDOWSUM  Sum the requested channel slice in double, without ever casting
%   the whole (possibly multi-GB) cube. cube(:,:,chans) stays at its native
%   class until this point, so the double() promotion touches only the
%   channels actually needed. Port of eds_maps.py's window_sum.
    s = sum(double(cube(:, :, chans)), 3);
end


function [loChans, hiChans] = sideWindows(energyAxis, eLo, eHi, bgWidth, bgGap)
%SIDEWINDOWS  Flanking background channel indices shared by the linear and
%   bremsstrahlung background estimators. Port of eds_maps.py's
%   _side_windows.
    pw = eHi - eLo;
    if isnan(bgWidth) || bgWidth <= 0
        bw = pw;
    else
        bw = bgWidth;
    end
    gap = max(bgGap, 0);
    loChans = find(energyAxis >= eLo - gap - bw & energyAxis < eLo - gap);
    hiChans = find(energyAxis >  eHi + gap      & energyAxis <= eHi + gap + bw);
end


function [map, loChans, hiChans] = kramersBgMap(cube, energyAxis, peakChans, peakSum, ...
        eLo, eHi, e0KeV, bgWidth, bgGap)
%KRAMERSBGMAP  Per-pixel net map under a fixed-shape Kramers continuum.
%
%   The continuum SHAPE is fixed pure Kramers (E0-E)/E (zero above the
%   Duane-Hunt cutoff E0); only its per-pixel AMPLITUDE is solved, as the
%   closed-form least-squares scale of that shape to the flanking background
%   channels:
%
%       amp(y,x) = sum_side( cube(y,x,side) .* c(side) ) / sum_side( c(side)^2 )
%       net      = peakSum - amp .* sum_peak( c(peak) )
%
%   Vectorized over all pixels -- an O(pixels) linear solve, never a
%   per-pixel curve fit. Port of eds_maps.py's _kramers_bg_map.
%
%   Only the flanking background channels are read, so cube is sliced at its
%   native class and promoted to double only for that small slice.

    if ~isfinite(e0KeV)
        error('imaging:eds:elementMap:missingE0KeV', ...
            'Background="bremsstrahlung" requires a finite E0KeV (beam energy, keV).');
    end
    if e0KeV <= eHi
        error('imaging:eds:elementMap:e0KeVBelowWindow', ...
            'E0KeV (beam energy, %.4g keV) must exceed the peak window upper edge (%.4g keV).', ...
            e0KeV, eHi);
    end

    [loChans, hiChans] = sideWindows(energyAxis, eLo, eHi, bgWidth, bgGap);
    sideChans = [loChans(:); hiChans(:)];
    if isempty(sideChans)
        map = peakSum;
        return;
    end

    c = zeros(size(energyAxis));
    below = energyAxis < e0KeV;
    c(below) = max(e0KeV - energyAxis(below), 0) ./ max(energyAxis(below), 1e-9);

    cSide = c(sideChans);
    denom = sum(cSide .^ 2);
    if denom <= 0
        map = peakSum;
        return;
    end

    sideSlice = double(cube(:, :, sideChans));                      % small slice only
    amp = sum(sideSlice .* reshape(cSide, 1, 1, []), 3) / denom;     % [H x W]

    map = peakSum - amp * sum(c(peakChans));
    map = max(map, 0);
end
