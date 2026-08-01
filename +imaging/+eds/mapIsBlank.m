function tf = mapIsBlank(map, options)
%MAPISBLANK  True for an EDS at%/intensity map with no coherent signal.
%
%   tf = imaging.eds.mapIsBlank(map) returns true when MAP looks like an
%   element that isn't really present rather than a genuine distribution, so
%   callers (quantification results, the composite channel list, any map
%   display) can skip it instead of cluttering the UI with noise.
%
%   Coverage, not peak value, is the discriminator. Because Cliff-Lorimer /
%   ZAF normalize atomic-% per pixel, an ABSENT element still spikes to
%   ~100 at% in stray noise/vacuum pixels (validated on real Bruker SEM
%   data: an absent element hit 100 at% yet covered <1% of the field, while
%   present elements covered several percent or more). A map is therefore
%   judged blank when fewer than CoverageThreshold of its pixels exceed
%   ValueThreshold. This also catches the all-zero / all-NaN cases — NaN
%   never satisfies `> ValueThreshold`, so NaN pixels never count as a hit —
%   while a present-everywhere element (a single-element quant sits at
%   ~100 at% across the whole field -> 100% coverage) is correctly kept.
%
%   Inputs
%   ──────
%   map   [H x W] numeric   Per-pixel map, typically a Cliff-Lorimer/ZAF
%                            atomic-% (or weight-%) output.
%
%   Name-Value
%   ──────────
%   ValueThreshold     (1,1) double = 1.0    Pixel value above which a pixel
%                                            counts as a "hit" (at% units by
%                                            convention, matching the
%                                            quantification output).
%   CoverageThreshold  (1,1) double = 0.01   Minimum fraction of pixels that
%                                            must be hits for the map to be
%                                            considered non-blank.
%
%   Outputs
%   ───────
%   tf   (1,1) logical   true when MAP is blank (element judged absent).
%
%   Examples
%   ────────
%     tf = imaging.eds.mapIsBlank(atMap);                       % defaults
%     tf = imaging.eds.mapIsBlank(atMap, CoverageThreshold=0.02);
%
%   See also IMAGING.EDS.CLIFFLORIMER, IMAGING.EDS.ZAFCORRECTION

    arguments
        map                        {mustBeNumeric}
        options.ValueThreshold    (1,1) double = 1.0
        options.CoverageThreshold (1,1) double = 0.01
    end

    a = double(map);
    if isempty(a)
        tf = true;
        return;
    end
    hits = a > options.ValueThreshold;   % NaN > threshold is false in MATLAB
    tf = (nnz(hits) / numel(a)) < options.CoverageThreshold;
end
