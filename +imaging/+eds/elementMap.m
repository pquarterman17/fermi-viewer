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
%   [map, info] = imaging.eds.elementMap(...) also returns a struct with the
%   channel ranges used (.peakChans, .bgLoChans, .bgHiChans) and .total.
%
%   Inputs
%   ──────
%   cube        [H x W x C] numeric   EDS hypercube (counts per channel).
%   energyAxis  [C x 1] double        Energy (keV) of each channel.
%   eLo, eHi    (1,1) double          Peak window bounds (keV), eLo < eHi.
%
%   Name-Value
%   ──────────
%   Background  'none' (default) | 'linear'
%   BgWidth     (1,1) double   Width of each side background window in keV
%                              (default: the peak-window width). Only used
%                              when Background='linear'.
%   BgGap       (1,1) double   Gap (keV) between the peak window and each side
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
%   Example
%   ───────
%     e   = imaging.eds.lineEnergy('Cu');           % 8.048 keV
%     map = imaging.eds.elementMap(cube, eax, e-0.10, e+0.10, Background='linear');
%     imagesc(map); axis image; colormap hot;
%
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

    cubeD = double(cube);
    peakSum = sum(cubeD(:, :, peakChans), 3);

    if strcmpi(options.Background, 'linear')
        pw = eHi - eLo;
        bw = options.BgWidth;
        if isnan(bw) || bw <= 0, bw = pw; end
        gap = max(options.BgGap, 0);

        loChans = find(energyAxis >= eLo - gap - bw & energyAxis < eLo - gap);
        hiChans = find(energyAxis >  eHi + gap      & energyAxis <= eHi + gap + bw);
        info.bgLoChans = loChans;
        info.bgHiChans = hiChans;

        nPeak = numel(peakChans);
        if ~isempty(loChans) && ~isempty(hiChans)
            % Mean count per channel on each side, interpolated under the peak.
            loRate = sum(cubeD(:, :, loChans), 3) / numel(loChans);
            hiRate = sum(cubeD(:, :, hiChans), 3) / numel(hiChans);
            bgPerChan = 0.5 * (loRate + hiRate);   % midpoint of the linear fit
            map = peakSum - bgPerChan * nPeak;
        elseif ~isempty(loChans)
            map = peakSum - (sum(cubeD(:, :, loChans), 3) / numel(loChans)) * nPeak;
        elseif ~isempty(hiChans)
            map = peakSum - (sum(cubeD(:, :, hiChans), 3) / numel(hiChans)) * nPeak;
        else
            map = peakSum;   % no side windows available
        end
        map = max(map, 0);
    else
        map = peakSum;
    end

    info.total = sum(map(:));
end
