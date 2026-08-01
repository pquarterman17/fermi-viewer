%TEST_EDSWORKSHOP  Headless tests for EDSWorkshop model + facade.
%
%   Run:
%       run tests/imaging/test_edsWorkshop
%       runAllTests(Group="em")

fprintf('\n');
fprintf('%s\n', repmat(char(9552), 1, 62));
fprintf('  EDSWorkshop — Headless Test Suite\n');
fprintf('%s\n', repmat(char(9552), 1, 62));

ROOT = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(ROOT);

passed = 0;
failed = 0;

% ═══════════════════════════════════════════════════════════════════════
%  TEST 1: Model defaults
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n== TEST 1: model defaults ==\n');
try
    m = fermiViewer.eds.EDSWorkshopModel();
    assert(~m.active, 'inactive by default');
    assert(m.numChannels() == 0, 'no channels');
    assert(m.numVisible() == 0, 'no visible');
    assert(~m.hasComposite, 'no composite');
    assert(~m.quantified, 'not quantified');
    assert(isempty(m.elements), 'no elements');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 2: addChannel / getChannel / removeChannel
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n== TEST 2: channel CRUD ==\n');
try
    m = fermiViewer.eds.EDSWorkshopModel();
    ch1 = struct('imageIdx', 1, 'label', 'Fe_Ka', 'color', [1 0 0], 'visible', true, 'intensity', 1.0);
    ch2 = struct('imageIdx', 2, 'label', 'O_Ka', 'color', [0 1 0], 'visible', false, 'intensity', 0.8);
    m.addChannel(ch1);
    m.addChannel(ch2);
    assert(m.numChannels() == 2, 'two channels');
    assert(m.numVisible() == 1, 'one visible');
    got = m.getChannel(1);
    assert(strcmp(got.label, 'Fe_Ka'), 'label preserved');
    m.removeChannel(1);
    assert(m.numChannels() == 1, 'one after remove');
    assert(strcmp(m.getChannel(1).label, 'O_Ka'), 'O_Ka is now first');
    m.removeChannel(99);
    assert(m.numChannels() == 1, 'out-of-range no-op');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 3: setChannelVisible / setChannelIntensity / setChannelColor
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n== TEST 3: channel setters ==\n');
try
    m = fermiViewer.eds.EDSWorkshopModel();
    ch = struct('imageIdx', 1, 'label', 'Ti', 'color', [1 0 0], 'visible', true, 'intensity', 1.0);
    m.addChannel(ch);
    m.setChannelVisible(1, false);
    assert(~m.getChannel(1).visible, 'set invisible');
    assert(m.numVisible() == 0, '0 visible');
    m.setChannelIntensity(1, 1.5);
    assert(abs(m.getChannel(1).intensity - 1.5) < 1e-10, 'intensity set');
    m.setChannelIntensity(1, 3.0);
    assert(abs(m.getChannel(1).intensity - 2.0) < 1e-10, 'intensity clamped to 2');
    m.setChannelColor(1, [0 0 1]);
    assert(all(m.getChannel(1).color == [0 0 1]), 'color changed');
    m.setChannelLabel(1, 'Titanium');
    assert(strcmp(m.getChannel(1).label, 'Titanium'), 'label changed');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 4: normalizeChannel fills missing fields
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n== TEST 4: normalizeChannel ==\n');
try
    m = fermiViewer.eds.EDSWorkshopModel();
    m.addChannel(struct('label', 'X'));
    ch = m.getChannel(1);
    assert(isfield(ch, 'imageIdx') && ch.imageIdx == 0, 'imageIdx filled');
    assert(isfield(ch, 'visible') && ch.visible == true, 'visible filled');
    assert(isfield(ch, 'intensity') && ch.intensity == 1.0, 'intensity filled');
    assert(isfield(ch, 'color'), 'color filled');
    m.addChannel('not a struct');
    assert(m.numChannels() == 1, 'non-struct rejected');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 5: sync from appData
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n== TEST 5: sync ==\n');
try
    m = fermiViewer.eds.EDSWorkshopModel();
    ad.edsMode = true;
    ad.edsChannels = { ...
        struct('imageIdx', 1, 'label', 'Fe', 'color', [1 0 0], 'visible', true, 'intensity', 1), ...
        struct('imageIdx', 2, 'label', 'O', 'color', [0 1 0], 'visible', true, 'intensity', 1)};
    ad.edsComposite = rand(64, 64, 3);
    ad.edsQuantified = true;
    ad.edsElements = {'Fe', 'O'};
    ad.edsAtomicPct = {rand(64,64), rand(64,64)};
    ad.edsWeightPct = {rand(64,64), rand(64,64)};
    m.sync(ad);
    assert(m.active, 'active');
    assert(m.numChannels() == 2, '2 channels');
    assert(m.hasComposite, 'has composite');
    assert(all(m.compositeSize == [64 64]), 'composite size');
    assert(m.quantified, 'quantified');
    assert(numel(m.elements) == 2, '2 elements');
    assert(m.numMaps == 2, '2 maps');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 6: reset
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n== TEST 6: reset ==\n');
try
    m = fermiViewer.eds.EDSWorkshopModel();
    m.active = true;
    m.quantified = true;
    m.elements = {'Fe'};
    m.addChannel(struct('label', 'X'));
    m.reset();
    assert(~m.active, 'inactive');
    assert(m.numChannels() == 0, 'channels cleared');
    assert(~m.quantified, 'not quantified');
    assert(isempty(m.elements), 'elements cleared');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 7: summarize
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n== TEST 7: summarize ==\n');
try
    m = fermiViewer.eds.EDSWorkshopModel();
    assert(contains(m.summarize(), 'inactive'), 'inactive summary');
    m.active = true;
    assert(contains(m.summarize(), 'no channels'), 'no channels');
    m.addChannel(struct('label', 'Fe', 'visible', true));
    m.addChannel(struct('label', 'O', 'visible', false));
    s = m.summarize();
    assert(contains(s, '2 ch'), '2 channels in summary');
    assert(contains(s, '1 visible'), '1 visible in summary');
    m.quantified = true;
    m.elements = {'Fe', 'O'};
    s = m.summarize();
    assert(contains(s, 'quantified'), 'quantified in summary');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 8: Facade delegation
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n== TEST 8: facade ==\n');
try
    ws = fermiViewer.eds.EDSWorkshop();
    assert(isa(ws.model, 'fermiViewer.eds.EDSWorkshopModel'), 'model type');
    assert(~ws.isActive(), 'inactive');
    assert(ws.numChannels() == 0, 'no channels');
    assert(~ws.isQuantified(), 'not quantified');
    ws.model.active = true;
    ws.model.addChannel(struct('label', 'X', 'visible', true));
    assert(ws.isActive(), 'active');
    assert(ws.numChannels() == 1, '1 channel');
    assert(ws.numVisible() == 1, '1 visible');
    ws.reset();
    assert(~ws.isActive(), 'reset');
    ws.show(); ws.hide(); ws.close();
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 9: hasHook
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n== TEST 9: hasHook ==\n');
try
    hook.replot = @() [];
    hook.bad = 42;
    ws = fermiViewer.eds.EDSWorkshop(hook);
    assert(ws.hasHook('replot'), 'detected');
    assert(~ws.hasHook('bad'), 'non-handle rejected');
    assert(~ws.hasHook('missing'), 'absent rejected');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 10: facade sync delegates
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n== TEST 10: facade sync ==\n');
try
    ws = fermiViewer.eds.EDSWorkshop();
    ad.edsMode = true;
    ad.edsChannels = {struct('imageIdx', 1, 'label', 'Ni', 'color', [0 1 1], 'visible', true, 'intensity', 1)};
    ad.edsComposite = [];
    ad.edsQuantified = false;
    ad.edsElements = {};
    ad.edsAtomicPct = {};
    ad.edsWeightPct = {};
    ws.sync(ad);
    assert(ws.isActive(), 'active');
    assert(ws.numChannels() == 1, '1 channel');
    assert(~ws.isQuantified(), 'not quantified');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 11: Method dropdown exists, defaults to Window integration, and
%  the default path is byte-identical to pre-Method-dropdown behaviour.
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n== TEST 11: Method dropdown default + byte-identical results ==\n');
try
    ctx = buildHeadlessEDSCtx();
    cleanupFig1 = onCleanup(@() safeCloseFig(ctx.fig));
    assert(isfield(ctx.panel, 'ddEDSMethod'), 'panel exposes ddEDSMethod');
    assert(strcmp(ctx.panel.ddEDSMethod.Value, 'Window integration'), ...
        'Method dropdown defaults to Window integration');
    assert(ctx.panel.cbEDSRemoveArtifacts.Value == false, ...
        'artifact removal defaults off');

    ad = baseAppData();
    ad.edsElements = {'Fe', 'Cu'};
    ad.edsChannels = {mkChannel(50 * ones(4,4), 'Fe'), mkChannel(150 * ones(4,4), 'Cu')};

    log1 = makeStatusLogger();
    ad1 = fermiViewer.eds.runQuantifyCL(ad, log1.log);        % legacy 2-arg call
    log2 = makeStatusLogger();
    ad2 = fermiViewer.eds.runQuantifyCL(ad, log2.log, ctx);   % 3-arg, default widget state

    assert(isequal(ad1.edsAtomicPct, ad2.edsAtomicPct), 'atomic%% maps byte-identical');
    assert(isequal(ad1.edsWeightPct, ad2.edsWeightPct), 'weight%% maps byte-identical');
    assert(isequal(ad1.edsElements, ad2.edsElements), 'element list byte-identical');
    assert(strcmp(ad2.edsQuantifyMethod, 'Window integration'), ...
        'method recorded as Window integration');

    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 12: Peak fit recovers an overlapping-line ratio far better than
%  window integration (Mo-La/Pb-Ma, 49 eV apart at BeamKV=15).
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n== TEST 12: Peak fit beats window integration on overlapping lines ==\n');
try
    warnState = warning('off', 'cliffLorimer:unknownElement');
    cleanupWarn12 = onCleanup(@() warning(warnState));

    e = linspace(0, 20, 4001)';
    beamKV = 15;
    [eMo, famMo] = imaging.eds.lineEnergy('Mo', BeamKV=beamKV);
    [ePb, famPb] = imaging.eds.lineEnergy('Pb', BeamKV=beamKV);
    assert(strcmp(famMo, 'L') && strcmp(famPb, 'M'), ...
        'expected Mo-L/Pb-M overlap at BeamKV=15');

    areaMo = 5000; areaPb = 2000;
    spec = gaussCurve(e, areaMo, eMo) + gaussCurve(e, areaPb, ePb);
    cube = reshape(spec, 1, 1, numel(e));

    ad = baseAppData();
    ad.activeIdx = 1;
    ad.images = {struct('metadata', struct('parserSpecific', struct( ...
        'edsData', struct('cube', cube, 'cubeEnergyAxis', e), ...
        'semParams', struct('voltage_kV', beamKV))))};
    ad.edsElements = {'Mo', 'Pb'};

    hw = 0.085;
    winMo = sum(spec(e >= eMo - hw & e <= eMo + hw));
    winPb = sum(spec(e >= ePb - hw & e <= ePb + hw));
    ad.edsChannels = {mkChannel(winMo, 'Mo'), mkChannel(winPb, 'Pb')};

    trueComp = imaging.eds.cliffLorimer({areaMo, areaPb}, {'Mo', 'Pb'});

    ctx = buildHeadlessEDSCtx();
    cleanupFig2 = onCleanup(@() safeCloseFig(ctx.fig));

    ctx.panel.ddEDSMethod.Value = 'Window integration';
    logW = makeStatusLogger();
    adW = fermiViewer.eds.runQuantifyCL(ad, logW.log, ctx);

    ctx.panel.ddEDSMethod.Value = 'Peak fit';
    logP = makeStatusLogger();
    adP = fermiViewer.eds.runQuantifyCL(ad, logP.log, ctx);

    errW = abs(adW.edsAtomicPct{1}(1) - trueComp.meanAtomicPct(1));
    errP = abs(adP.edsAtomicPct{1}(1) - trueComp.meanAtomicPct(1));
    assert(errP < errW, sprintf( ...
        'peak-fit error (%.3f) should beat window-integration error (%.3f)', errP, errW));
    assert(strcmp(adP.edsQuantifyMethod, 'Peak fit'), 'method recorded as Peak fit');

    fprintf('  PASS  (window err=%.3f at%%, peak-fit err=%.3f at%%)\n', errW, errP);
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 13: zeta-factor returns composition + positive mass-thickness;
%  composition is dose-independent, mass-thickness scales inversely
%  with dose.
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n== TEST 13: zeta-factor mass-thickness + dose (in)dependence ==\n');
try
    ad = baseAppData();
    ad.edsElements = {'Fe', 'O'};
    ad.edsChannels = {mkChannel(3000 * ones(3,3), 'Fe'), mkChannel(1000 * ones(3,3), 'O')};

    ctx = buildHeadlessEDSCtx();
    cleanupFig3 = onCleanup(@() safeCloseFig(ctx.fig));
    ctx.panel.ddEDSMethod.Value = [char(950) '-factor'];
    ctx.panel.edtEDSZetaSi.Value = '1000';
    ctx.panel.edtEDSDoseCurrentNA.Value = '1.0';
    ctx.panel.edtEDSDoseLiveTimeS.Value = '100';

    log1 = makeStatusLogger();
    ad1 = fermiViewer.eds.runQuantifyCL(ad, log1.log, ctx);

    assert(strcmp(ad1.edsQuantifyMethod, [char(950) '-factor']), ...
        'method recorded as zeta-factor');
    assert(isfield(ad1, 'edsMeanMassThicknessKgM2') && ad1.edsMeanMassThicknessKgM2 > 0, ...
        'positive mass-thickness reported');
    comp1 = cellfun(@(m) m(1), ad1.edsAtomicPct);

    % Doubling live time (dose) at fixed measured intensity must leave
    % composition unchanged and HALVE mass-thickness (rho*t = sum(zeta*I)/dose).
    ctx.panel.edtEDSDoseLiveTimeS.Value = '200';
    log2 = makeStatusLogger();
    ad2 = fermiViewer.eds.runQuantifyCL(ad, log2.log, ctx);
    comp2 = cellfun(@(m) m(1), ad2.edsAtomicPct);

    assert(max(abs(comp1 - comp2)) < 1e-9, 'composition must be dose-independent');
    ratio = ad1.edsMeanMassThicknessKgM2 / ad2.edsMeanMassThicknessKgM2;
    assert(abs(ratio - 2.0) < 1e-6, sprintf( ...
        'mass-thickness should scale inversely with dose (2x), got ratio=%.4f', ratio));

    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 14: artifact pre-pass toggle changes the Fe result in the
%  canonical Cu-escape-on-Fe-Ka scenario, and status names what was
%  removed.
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n== TEST 14: artifact pre-pass changes Fe result (Cu-escape-on-Fe) ==\n');
try
    e = linspace(0, 20, 4001)';
    FE = imaging.eds.lineEnergy('Fe', BeamKV=200);
    CU = imaging.eds.lineEnergy('Cu', BeamKV=200);
    FRACTION = 0.01;
    SI_ESC = 1.740;
    spec = gaussCurve(e, 4000, FE) + gaussCurve(e, 6000, CU) ...
        + gaussCurve(e, FRACTION * 4000, FE - SI_ESC) ...
        + gaussCurve(e, FRACTION * 6000, CU - SI_ESC);
    cube = reshape(spec, 1, 1, numel(e));

    ad = baseAppData();
    ad.activeIdx = 1;
    ad.images = {struct('metadata', struct('parserSpecific', struct( ...
        'edsData', struct('cube', cube, 'cubeEnergyAxis', e), ...
        'semParams', struct('voltage_kV', 200))))};
    ad.edsElements = {'Fe', 'Cu'};
    % Arbitrary placeholder per-pixel maps -- the pre-pass rescales them by
    % the spectral correction ratio, independent of their absolute values.
    ad.edsChannels = {mkChannel(500 * ones(2,2), 'Fe'), mkChannel(500 * ones(2,2), 'Cu')};

    ctx = buildHeadlessEDSCtx();
    cleanupFig4 = onCleanup(@() safeCloseFig(ctx.fig));

    ctx.panel.cbEDSRemoveArtifacts.Value = false;
    logOff = makeStatusLogger();
    adOff = fermiViewer.eds.runQuantifyCL(ad, logOff.log, ctx);

    ctx.panel.cbEDSRemoveArtifacts.Value = true;
    logOn = makeStatusLogger();
    adOn = fermiViewer.eds.runQuantifyCL(ad, logOn.log, ctx);

    feOff = adOff.edsAtomicPct{1}(1);
    feOn  = adOn.edsAtomicPct{1}(1);
    assert(abs(feOff - feOn) > 1e-6, 'Fe result should change with the artifact pre-pass toggle');
    assert(contains(logOn.last(), 'artifacts removed'), 'status should name what was removed');

    fprintf('  PASS  (Fe at%% off=%.3f, on=%.3f)\n', feOff, feOn);
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 15: bremsstrahlung background is selectable at the map-building
%  layer and produces a different (flatter-background) map than linear
%  on a synthetic ramped-continuum cube.
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n== TEST 15: bremsstrahlung vs linear background (ramped continuum) ==\n');
try
    e = linspace(0.2, 20, 800)';
    E0 = 20;
    FE = imaging.eds.lineEnergy('Fe');
    continuum = 200 * max(E0 - e, 0) ./ max(e, 1e-9);
    spec = continuum + gaussCurve(e, 8000, FE);
    cube = reshape(spec, 1, 1, numel(e));

    img = struct();
    img.metadata.parserSpecific.edsData = struct('cube', cube, 'cubeEnergyAxis', e, ...
        'elements', {{'Fe'}});
    img.metadata.parserSpecific.semParams = struct('voltage_kV', E0);

    colors = {'red', 'green', 'blue', 'cyan', 'magenta', 'yellow', 'white'};
    chLinear = fermiViewer.eds.buildCubeChannels(img, colors, Background='linear');
    chBrem   = fermiViewer.eds.buildCubeChannels(img, colors, Background='bremsstrahlung');

    assert(~isempty(chLinear) && ~isempty(chBrem), 'both backgrounds should return a channel');
    mapLinear = chLinear{1}.map;
    mapBrem   = chBrem{1}.map;
    assert(abs(mapLinear - mapBrem) > 1e-6, 'bremsstrahlung map should differ from linear');

    % E0KeV auto-sourced from beam-energy metadata must match an explicit
    % E0KeV equal to that same beam voltage.
    chBremExplicit = fermiViewer.eds.buildCubeChannels(img, colors, ...
        Background='bremsstrahlung', E0KeV=E0);
    assert(abs(chBremExplicit{1}.map - mapBrem) < 1e-9, ...
        'metadata-sourced E0KeV should match an explicit E0KeV=beam kV');

    fprintf('  PASS  (linear=%.3f, bremsstrahlung=%.3f)\n', mapLinear, mapBrem);
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ── Summary ────────────────────────────────────────────────────────────
fprintf('\n%s\n', repmat(char(9552), 1, 62));
fprintf('Results: %2d passed, %2d failed\n', passed, failed);
fprintf('%s\n', repmat(char(9552), 1, 62));
if failed > 0
    error('test_edsWorkshop:failures', '%d check(s) failed.', failed);
else
    fprintf('Status: ALL PASS\n');
end


% ═══════════════════════════════════════════════════════════════════════
%  Local helpers (script-local functions -- supported since R2016b)
% ═══════════════════════════════════════════════════════════════════════

function c = gaussCurve(e, area, centerKeV)
%GAUSSCURVE  Area-parametrised Gaussian at the Fano (detector) width -- the
%   same "plant a known peak" construction used across the EDS test suite
%   (see test_eds_peakfit.m), duplicated here (test-local) to build
%   synthetic spectra with known ground-truth areas.
    [~, sigma] = imaging.eds.fanoResolution(centerKeV);
    amp = area / (sigma * sqrt(2 * pi));
    c = amp * exp(-0.5 * ((e - centerKeV) / sigma) .^ 2);
end


function ch = mkChannel(map, symbol)
%MKCHANNEL  A minimal cube-derived EDS channel struct: a per-pixel .map
%   plus the element .symbol runQuantifyCL reads for peak-fit line lookup.
    ch = struct('imageIdx', 0, 'label', symbol, 'color', 'red', ...
        'visible', true, 'intensity', 1.0, 'map', map, 'symbol', symbol);
end


function ad = baseAppData()
%BASEAPPDATA  Minimal appData struct with the fields runQuantifyCL touches
%   unconditionally (edsMode, edsWorkshop.sync, activeIdx/images lookup).
    ad = struct();
    ad.edsMode      = true;
    ad.edsWorkshop  = fermiViewer.eds.EDSWorkshop();
    ad.activeIdx    = 0;
    ad.images       = {};
    ad.edsQuantified = false;
end


function logger = makeStatusLogger()
%MAKESTATUSLOGGER  Tiny status-message recorder standing in for setStatus.
%   Returns a struct with .log (pass as the setStatus handle) and .last
%   (the most recent logged message). Both are handles to NESTED functions
%   sharing this local function's workspace, so .last re-reads the live
%   value of lastMsg at call time. An anonymous function (@() lastMsg)
%   would capture lastMsg BY VALUE at creation time instead and never see
%   later writes from .log -- nested functions are required here, not
%   anonymous ones.
    lastMsg = '';
    logger.log  = @setMsg;
    logger.last = @getMsg;
    function setMsg(m)
        lastMsg = m;
    end
    function m = getMsg()
        m = lastMsg;
    end
end


function ctx = buildHeadlessEDSCtx()
%BUILDHEADLESSEDSCTX  Build a real (invisible) EDS panel via
%   fermiViewer.eds.buildEDSPanel and return a ctx struct exposing
%   ctx.btnQuantifyCL exactly like FermiViewer.m's buildEDSCtx() would, so
%   runQuantifyCL's Tag-based widget lookups exercise the real wiring
%   (edsGridOf(ctx) -> ctx.btnQuantifyCL.Parent -> findobj by Tag).
%   ctx.panel exposes every widget handle directly for test setup;
%   ctx.fig should be closed by the caller (onCleanup) when done.
    fig = uifigure('Visible', 'off');
    gl = uigridlayout(fig, [1 1]);
    palette = struct('primary', [0 0 0], 'tool', [0 0 0], ...
        'danger', [0 0 0], 'export', [0 0 0], 'fg', [1 1 1]);
    noop2 = @(~,~) [];
    noop1 = @(~) [];
    callbacks = struct('onEnterEDS', noop2, 'onEDSListChange', noop1, ...
        'onEDSChannelSelected', noop2, 'onEDSChannelPropChanged', noop1, ...
        'onExportEDSComposite', noop2, 'onAssignElements', noop2, ...
        'onQuantifyCL', noop2, 'onCompositionProfile', noop2, ...
        'onROIComposition', noop2, 'onQuantifyZAF', noop2);
    s = fermiViewer.eds.buildEDSPanel(gl, struct(), palette, callbacks);
    ctx = struct('btnQuantifyCL', s.btnQuantifyCL, 'panel', s, 'fig', fig);
end


function safeCloseFig(fig)
%SAFECLOSEFIG  close(fig,'force'), tolerating a handle already invalidated
%   by -batch teardown (onCleanup destructors on script-level variables
%   can fire after MATLAB has already torn down figures on exit).
    try
        if isvalid(fig)
            close(fig, 'force');
        end
    catch
    end
end
