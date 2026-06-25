function channels = buildCubeChannels(img, edsColors, options)
%BUILDCUBECHANNELS  Build colored EDS composite channels from a BCF cube.
%
%   channels = fermiViewer.eds.buildCubeChannels(img, edsColors) inspects an
%   image data struct for a decoded EDS hypercube
%   (img.metadata.parserSpecific.edsData.cube, populated by parser.importBCF)
%   and returns a cell array of composite-channel structs — one per element —
%   each carrying its own element-distribution map. This is what lets
%   "Enter EDS Mode" show real element maps for a freshly-opened BCF instead
%   of just the (often blank) SEM survey image.
%
%   Returns {} when img carries no cube, so the caller can fall back to the
%   legacy image-file channel behaviour.
%
%   Element selection:
%     1. If edsData.elements is non-empty (Bruker listed them), use those.
%     2. Otherwise auto-detect peaks in the sum spectrum
%        (imaging.eds.identifyPeaks) and use the matched element symbols,
%        falling back to energy-window maps for unmatched peaks.
%
%   Each returned channel is a struct compatible with the EDS composite path
%   (see fermiViewer.eds.computeComposite) with fields:
%     .imageIdx   0      (cube-derived, not an entry in appData.images)
%     .label      e.g. 'Cu Kα' or '6.40 keV'
%     .color      name from edsColors, cycled
%     .visible    true
%     .intensity  1.0
%     .map        [H x W] double element/energy-window map
%     .symbol     element symbol ('' for unmatched energy windows)
%
%   Name-Value
%   ──────────
%   MaxChannels (1,1) double = 6   Cap on channels (too many overlaid colour
%                                  maps make a muddy composite).
%   HalfWindow  (1,1) double = 0.085  Integration half-window (keV).
%
%   See also FERMIVIEWER.EDS.COMPUTECOMPOSITE, IMAGING.EDS.EXTRACTELEMENTMAPS,
%   IMAGING.EDS.IDENTIFYPEAKS, PARSER.IMPORTBCF

    arguments
        img
        edsColors   cell
        options.MaxChannels (1,1) double = 6
        options.HalfWindow  (1,1) double = 0.085
    end

    channels = {};

    eds = getEDS(img);
    if isempty(eds) || ~isfield(eds, 'cube') || isempty(eds.cube)
        return;
    end

    cube = eds.cube;
    if isfield(eds, 'cubeEnergyAxis') && ~isempty(eds.cubeEnergyAxis)
        eax = eds.cubeEnergyAxis(:);
    elseif isfield(eds, 'energyAxis') && ~isempty(eds.energyAxis)
        eax = eds.energyAxis(:);
    else
        return;
    end
    if size(cube, 3) ~= numel(eax)
        return;   % axis/cube mismatch — refuse rather than mislabel
    end

    beamKV = getBeamKV(img);
    hw = options.HalfWindow;

    % ── Decide which (label, map) pairs to build ─────────────────────────────
    specs = struct('label', {}, 'symbol', {}, 'map', {});

    elements = {};
    if isfield(eds, 'elements'), elements = eds.elements; end

    if ~isempty(elements)
        maps = imaging.eds.extractElementMaps(cube, eax, elements, ...
            BeamKV=beamKV, HalfWindow=hw);
        for k = 1:numel(maps)
            specs(end+1) = struct('label', maps(k).symbol, ...
                'symbol', maps(k).symbol, 'map', maps(k).map); %#ok<AGROW>
        end
    else
        sumSpec = [];
        if isfield(eds, 'sumSpectrum'), sumSpec = eds.sumSpectrum; end
        if isempty(sumSpec)
            sumSpec = squeeze(sum(sum(double(cube), 1), 2));
        end
        pk = imaging.eds.identifyPeaks(sumSpec, eax, ...
            BeamKV=beamKV, MaxPeaks=options.MaxChannels);
        for k = 1:numel(pk)
            m = imaging.eds.elementMap(cube, eax, ...
                pk(k).energy - hw, pk(k).energy + hw, Background='linear');
            specs(end+1) = struct('label', pk(k).label, ...
                'symbol', pk(k).symbol, 'map', m); %#ok<AGROW>
        end
    end

    if isempty(specs)
        return;
    end

    % ── Assemble channel structs (cap count, cycle colours) ──────────────────
    nMax = min(numel(specs), options.MaxChannels);
    for k = 1:nMax
        ch.imageIdx  = 0;
        ch.label     = specs(k).label;
        ch.color     = edsColors{mod(k-1, numel(edsColors)) + 1};
        ch.visible   = true;
        ch.intensity = 1.0;
        ch.map       = specs(k).map;
        ch.symbol    = specs(k).symbol;
        channels{end+1} = ch; %#ok<AGROW>
    end
end


function eds = getEDS(img)
    eds = [];
    if isstruct(img) && isfield(img, 'metadata') ...
            && isfield(img.metadata, 'parserSpecific') ...
            && isfield(img.metadata.parserSpecific, 'edsData')
        eds = img.metadata.parserSpecific.edsData;
    end
end


function kv = getBeamKV(img)
    kv = Inf;   % no overvoltage limit when unknown
    try
        sp = img.metadata.parserSpecific.semParams;
        if isfield(sp, 'voltage_kV') && ~isnan(sp.voltage_kV) && sp.voltage_kV > 0
            kv = sp.voltage_kV;
        end
    catch
    end
end
