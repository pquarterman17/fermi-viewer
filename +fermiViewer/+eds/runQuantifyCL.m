function appData = runQuantifyCL(appData, setStatus, ctx)
%RUNQUANTIFYCL  Cliff-Lorimer-family EDS quantification across assigned
%   EDS channels — window integration (default), peak-fit, or ζ-factor.
%
%   appData = fermiViewer.eds.runQuantifyCL(appData, setStatus)
%   appData = fermiViewer.eds.runQuantifyCL(appData, setStatus, ctx)
%
%   Reads appData.edsChannels (must be populated) and appData.edsElements
%   (must be assigned), pulls the underlying pixel maps from
%   appData.images, and quantifies using one of three methods selected via
%   the EDS panel's Method dropdown (fermiViewer.eds.buildEDSPanel's
%   ddEDSMethod, Tag-located through ctx — see resolveEDSOptions below):
%
%     'Window integration' (default, unchanged from the pre-Method-dropdown
%        behaviour) — imaging.eds.cliffLorimer directly on the per-pixel
%        window-integrated maps already carried by appData.edsChannels.
%     'Peak fit' — constrained multi-Gaussian deconvolution
%        (imaging.eds.fitPeaks / imaging.eds.quantifyPeaks) of the ACTIVE
%        image's summed EDS-cube spectrum. Resolves overlapping lines
%        (S-Ka/Mo-La/Pb-Ma class) that window integration mis-assigns; a
%        bulk (whole-field) composition, broadcast to uniform per-pixel
%        maps so downstream tools (ROI/profile, blank suppression) keep
%        working. Needs a decoded EDS cube.
%     'ζ-factor' — imaging.eds.zetaQuantify on the SAME per-pixel maps as
%        window integration, reporting composition AND mass-thickness
%        (Cliff-Lorimer cannot report thickness at all). ζ-factors are
%        bootstrapped from the built-in 200 kV k-factor table via one
%        absolute ζ_Si standard (imaging.eds.zetaFromKFactors); dose comes
%        from the panel's probe current (nA) + live time (s)
%        (imaging.eds.doseElectrons).
%
%   Optional artifact pre-pass (fermiViewer.eds.buildEDSPanel's
%   cbEDSRemoveArtifacts, default off): before quantifying, measures the
%   ACTIVE image's summed spectrum against imaging.eds.predictArtifacts /
%   imaging.eds.removeArtifacts (the canonical Cu-Ka escape at 6.308 keV
%   inflating Fe-Ka at 6.404 keV) and rescales each element's per-pixel map
%   by the ratio of its artifact-corrected to raw net area — a spatially
%   uniform correction applied to every pixel at once. Needs a decoded EDS
%   cube; no-ops (with a status note) otherwise.
%
%   ctx (optional) is the struct built by FermiViewer.m's buildEDSCtx();
%   omitting it (or passing one with no usable ctx.btnQuantifyCL handle)
%   reproduces exactly today's window-integration-only behaviour, which is
%   what keeps the default call path byte-identical for existing callers.
%
%   Blank at%-map suppression (imaging.eds.mapIsBlank): Cliff-Lorimer-style
%   normalization can spike an absent element to ~100 at% in stray
%   noise/vacuum pixels — coverage, not peak value, tells present from
%   absent. Elements judged blank are dropped from
%   appData.edsElements/edsAtomicPct/edsWeightPct (the three stay
%   index-aligned) so they don't clutter downstream tools (ROI/profile,
%   the EDS workshop panel) with noise; the status message names them.
%   Syncs the EDS workshop. Accept-and-return.
%
%   See also FERMIVIEWER.EDS.BUILDEDSPANEL, FERMIVIEWER.EDS.DISPATCH,
%   IMAGING.EDS.CLIFFLORIMER, IMAGING.EDS.QUANTIFYPEAKS,
%   IMAGING.EDS.ZETAQUANTIFY, IMAGING.EDS.REMOVEARTIFACTS

    arguments
        appData
        setStatus
        ctx = struct()
    end

    if ~appData.edsMode || isempty(appData.edsChannels)
        return;
    end
    if isempty(appData.edsElements)
        setStatus('Assign elements first');
        return;
    end

    opts = resolveEDSOptions(ctx);
    elements = appData.edsElements;
    nCh  = numel(appData.edsChannels);

    maps = cell(1, nCh);
    for k = 1:nCh
        ch = appData.edsChannels{k};
        if isfield(ch, 'map') && ~isempty(ch.map)
            % Cube-derived element channel: its map IS the intensity map.
            maps{k} = double(ch.map);
        else
            chIdx  = ch.imageIdx;
            maps{k} = double(appData.images{chIdx}.metadata.parserSpecific.imageData.pixels);
        end
    end

    artifactNote = '';
    if opts.removeArtifacts
        [maps, artifactNote] = applyArtifactPrepass(appData, elements, maps);
    end

    extra = struct();
    switch methodKey(opts.method)
        case 'peakfit'
            [result, methodLabel, extra, errMsg] = runPeakFit(appData, elements, opts);
        case 'zeta'
            [result, methodLabel, extra, errMsg] = runZeta(maps, elements, opts);
        otherwise
            methodLabel = 'Window integration';
            errMsg = '';
            try
                result = imaging.eds.cliffLorimer(maps, elements);
            catch ME
                result = [];
                errMsg = ['Cliff-Lorimer error: ' ME.message];
            end
    end

    if ~isempty(errMsg)
        setStatus(errMsg);
        return;
    end

    msg = sprintf('Composition (%s, at%%): ', methodLabel);
    for k = 1:numel(elements)
        msg = [msg sprintf('%s=%.1f%% ', elements{k}, result.meanAtomicPct(k))]; %#ok<AGROW>
    end

    blank = false(1, numel(elements));
    for k = 1:numel(elements)
        blank(k) = imaging.eds.mapIsBlank(result.atomicPctMaps{k});
    end
    keep = ~blank;

    appData.edsAtomicPct      = result.atomicPctMaps(keep);
    appData.edsWeightPct      = result.weightPctMaps(keep);
    suppressed                = elements(blank);
    appData.edsElements       = elements(keep);
    appData.edsQuantified     = true;
    appData.edsQuantifyMethod = methodLabel;

    if isfield(extra, 'meanRhoT_kg_m2')
        appData.edsMeanMassThicknessKgM2 = extra.meanRhoT_kg_m2;
        appData.edsMassThicknessMapKgM2  = extra.rhoT_kg_m2;
        appData.edsMeanThicknessNm       = extra.meanThickness_nm;
        msg = [msg sprintf('| mass-thickness=%.4g kg/m^2', extra.meanRhoT_kg_m2)];
        if isfinite(extra.meanThickness_nm)
            msg = [msg sprintf(' (%.1f nm)', extra.meanThickness_nm)];
        end
        msg = [msg ' '];
    end

    if any(blank)
        n = nnz(blank);
        suffix = ''; if n ~= 1, suffix = 's'; end
        msg = [msg sprintf('| %d element%s suppressed as blank: %s', ...
            n, suffix, strjoin(suppressed, ', '))];
    end
    if ~isempty(artifactNote)
        msg = [msg ' | ' artifactNote];
    end
    setStatus(msg);
    appData.edsWorkshop.sync(appData);
end


% ════════════════════════════════════════════════════════════════════════
%  Local helpers
% ════════════════════════════════════════════════════════════════════════

function opts = resolveEDSOptions(ctx)
%RESOLVEEDSOPTIONS  Read Method/Artifact/Dose panel values via the EDS grid
%   that ctx.btnQuantifyCL (an existing buildEDSCtx() field) lives in. The
%   new Method/Artifact/Dose controls postdate buildEDSCtx() and aren't in
%   ctx directly (see matlab-gui-complexity.md — FermiViewer.m has ZERO
%   nested-function headroom, so ctx-building itself cannot be extended
%   there); this locates sibling widgets by Tag instead. Falls back to
%   today's defaults when ctx carries no usable handle (legacy 2-argument
%   call, or a test that omits ctx) — this is what keeps the default call
%   path byte-identical to pre-Method-dropdown behaviour.
    opts = struct('method', 'Window integration', 'removeArtifacts', false, ...
        'beamCurrentNA', NaN, 'liveTimeS', NaN, 'zetaSi', NaN);
    if ~isstruct(ctx) || ~isfield(ctx, 'btnQuantifyCL') || isempty(ctx.btnQuantifyCL) ...
            || ~isgraphics(ctx.btnQuantifyCL)
        return;
    end
    root = ctx.btnQuantifyCL.Parent;
    opts.method          = widgetValue(root, 'ddEDSMethod', opts.method);
    opts.removeArtifacts = widgetValue(root, 'cbEDSRemoveArtifacts', opts.removeArtifacts);
    opts.beamCurrentNA   = str2double(widgetValue(root, 'edtEDSDoseCurrentNA', 'NaN'));
    opts.liveTimeS       = str2double(widgetValue(root, 'edtEDSDoseLiveTimeS', 'NaN'));
    opts.zetaSi          = str2double(widgetValue(root, 'edtEDSZetaSi', 'NaN'));
end


function val = widgetValue(root, tag, default)
%WIDGETVALUE  .Value of the first graphics object under ROOT tagged TAG,
%   or DEFAULT when none is found.
    val = default;
    if isempty(root) || ~isgraphics(root), return; end
    h = findobj(root, 'Tag', tag);
    if isempty(h), return; end
    val = h(1).Value;
end


function key = methodKey(methodStr)
%METHODKEY  Normalize a Method dropdown string to a short lowercase key.
%   char(950) is Greek small letter zeta (ζ), matched independent of case
%   or the exact "ζ-factor" spelling.
    s = lower(strtrim(string(methodStr)));
    if contains(s, 'peak')
        key = 'peakfit';
    elseif contains(s, 'zeta') || contains(s, char(950))
        key = 'zeta';
    else
        key = 'window';
    end
end


function [cube, eax, beamKV, sz, ok] = activeCube(appData)
%ACTIVECUBE  Locate the decoded EDS hypercube + energy axis for the active
%   image, if any. Needed by the bulk spectral operations (peak fit,
%   artifact pre-pass) that window-integration/ζ-factor's per-pixel maps
%   don't require. Mirrors buildCubeChannels.m's getEDS/getBeamKV helpers.
    cube = []; eax = []; beamKV = 200; sz = [0 0]; ok = false;
    ai = appData.activeIdx;
    if ai < 1 || ai > numel(appData.images), return; end
    img = appData.images{ai};
    if ~isstruct(img) || ~isfield(img, 'metadata') ...
            || ~isfield(img.metadata, 'parserSpecific') ...
            || ~isfield(img.metadata.parserSpecific, 'edsData')
        return;
    end
    eds = img.metadata.parserSpecific.edsData;
    if ~isfield(eds, 'cube') || isempty(eds.cube)
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
        return;
    end
    sz = [size(cube, 1), size(cube, 2)];
    try
        sp = img.metadata.parserSpecific.semParams;
        if isfield(sp, 'voltage_kV') && ~isnan(sp.voltage_kV) && sp.voltage_kV > 0
            beamKV = sp.voltage_kV;
        end
    catch
    end
    ok = true;
end


function [result, methodLabel, extra, errMsg] = runPeakFit(appData, elements, opts) %#ok<INUSD>
%RUNPEAKFIT  Bulk (summed-spectrum) peak-fit quantification, broadcast to
%   uniform per-pixel maps sized like the other channels so downstream
%   consumers (ROI/profile tools, mapIsBlank suppression) keep working.
    methodLabel = 'Peak fit';
    extra = struct();
    result = [];

    [cube, eax, beamKV, sz, ok] = activeCube(appData);
    if ~ok
        errMsg = 'Peak fit needs a decoded EDS cube (open a BCF/SER spectrum image).';
        return;
    end
    errMsg = '';

    spec = squeeze(sum(sum(double(cube), 1), 2));
    try
        [~, cl] = imaging.eds.quantifyPeaks(eax, spec, elements, BeamKV=beamKV);
    catch ME
        errMsg = ['Peak fit error: ' ME.message];
        return;
    end

    N = numel(elements);
    atomicPctMaps = cell(1, N);
    weightPctMaps = cell(1, N);
    for i = 1:N
        atomicPctMaps{i} = ones(sz) * cl.meanAtomicPct(i);
        weightPctMaps{i} = ones(sz) * cl.meanWeightPct(i);
    end
    result.atomicPctMaps = atomicPctMaps;
    result.weightPctMaps = weightPctMaps;
    result.meanAtomicPct = cl.meanAtomicPct;
    result.meanWeightPct = cl.meanWeightPct;
end


function [result, methodLabel, extra, errMsg] = runZeta(maps, elements, opts)
%RUNZETA  ζ-factor quantification off the same per-pixel maps as
%   window-integration/Cliff-Lorimer, adding mass-thickness for free.
    methodLabel = [char(950) '-factor'];
    extra = struct();
    result = [];

    if isnan(opts.zetaSi) || opts.zetaSi <= 0
        errMsg = [methodLabel ' needs a positive ' char(950) '_Si standard value.'];
        return;
    end
    if isnan(opts.beamCurrentNA) || isnan(opts.liveTimeS) ...
            || opts.beamCurrentNA <= 0 || opts.liveTimeS <= 0
        errMsg = [methodLabel ' needs a positive probe current (nA) and live time (s).'];
        return;
    end
    errMsg = '';

    dose = imaging.eds.doseElectrons(opts.beamCurrentNA, opts.liveTimeS);
    zetaFactors = imaging.eds.zetaFromKFactors(elements, opts.zetaSi);
    mapCube = cat(3, maps{:});

    % Absorption=false: the closed-form pass, matching window-integration/
    % Cliff-Lorimer's own thin-specimen assumption (neither corrects for
    % self-absorption either -- that is what the separate, pre-existing
    % "Quantify ZAF" button is for). This is also what keeps composition
    % exactly dose-independent (imaging.eds.zetaQuantify's self-consistent
    % absorption iteration ties the correction factor to rho*t, which is
    % itself dose-dependent, so composition would otherwise vary with dose).
    try
        z = imaging.eds.zetaQuantify(mapCube, elements, zetaFactors, ...
            DoseElectrons=dose, Absorption=false);
    catch ME
        errMsg = [methodLabel ' error: ' ME.message];
        return;
    end

    N = numel(elements);
    atomicPctMaps = cell(1, N);
    weightPctMaps = cell(1, N);
    for i = 1:N
        atomicPctMaps{i} = z.atomicPct(:, :, i);
        weightPctMaps{i} = z.weightFrac(:, :, i) * 100;
    end
    result.atomicPctMaps = atomicPctMaps;
    result.weightPctMaps = weightPctMaps;
    result.meanAtomicPct = z.meanAtomicPct;
    result.meanWeightPct = z.meanWeightFrac * 100;

    extra.meanRhoT_kg_m2   = z.meanRhoT_kg_m2;
    extra.rhoT_kg_m2       = z.rhoT_kg_m2;
    extra.meanThickness_nm = z.meanThickness_nm;
end


function [maps, note] = applyArtifactPrepass(appData, elements, maps)
%APPLYARTIFACTPREPASS  Scale each element's per-pixel map by the ratio of
%   its artifact-corrected to raw net area, measured on the active image's
%   summed EDS spectrum (imaging.eds.predictArtifacts / .removeArtifacts,
%   the fitPeaks -> removeArtifacts -> refit recovery pipeline from their
%   own docstrings). Assumes the artifact-to-real-line ratio is spatially
%   uniform, so the scalar correction commutes with the per-pixel window
%   sum — the canonical Cu-Ka-escape-on-Fe-Ka contamination is removed
%   everywhere at once. Falls back to a no-op (with a status note) when no
%   EDS cube is available.
    [cube, eax, beamKV, ~, ok] = activeCube(appData);
    if ~ok
        note = 'artifact pre-pass skipped: no EDS cube available';
        return;
    end

    spec = squeeze(sum(sum(double(cube), 1), 2));
    try
        pf0 = imaging.eds.fitPeaks(eax, spec, elements, BeamKV=beamKV);
        removal = imaging.eds.removeArtifacts(eax, spec, elements, pf0.lineEnergyKeV, ...
            Residual=spec(:) - pf0.fittedCurve, ParentAreas=pf0.netArea);
        pf1 = imaging.eds.fitPeaks(eax, removal.corrected, elements, BeamKV=beamKV);
    catch ME
        note = sprintf('artifact pre-pass failed: %s', ME.message);
        return;
    end

    handled = setdiff(string({removal.artifacts.name}), removal.skipped);
    note = sprintf('artifacts removed: %s (%d measured, %d modeled, %d skipped)', ...
        strjoin(handled, ', '), numEntries(removal.measured), ...
        numEntries(removal.modeled), numel(removal.skipped));

    for i = 1:numel(elements)
        raw = pf0.netArea(i);
        corrected = pf1.netArea(i);
        if isnan(raw) || raw <= 0 || isnan(corrected) || i > numel(maps) || isempty(maps{i})
            continue;
        end
        scale = max(corrected, 0) / raw;
        maps{i} = maps{i} * scale;
    end
end
