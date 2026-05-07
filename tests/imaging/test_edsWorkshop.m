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
    m = emViewer.eds.EDSWorkshopModel();
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
    m = emViewer.eds.EDSWorkshopModel();
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
    m = emViewer.eds.EDSWorkshopModel();
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
    m = emViewer.eds.EDSWorkshopModel();
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
    m = emViewer.eds.EDSWorkshopModel();
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
    m = emViewer.eds.EDSWorkshopModel();
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
    m = emViewer.eds.EDSWorkshopModel();
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
    ws = emViewer.eds.EDSWorkshop();
    assert(isa(ws.model, 'emViewer.eds.EDSWorkshopModel'), 'model type');
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
    ws = emViewer.eds.EDSWorkshop(hook);
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
    ws = emViewer.eds.EDSWorkshop();
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

% ── Summary ────────────────────────────────────────────────────────────
fprintf('\n%s\n', repmat(char(9552), 1, 62));
fprintf('Results: %2d passed, %2d failed\n', passed, failed);
fprintf('%s\n', repmat(char(9552), 1, 62));
if failed > 0
    error('test_edsWorkshop:failures', '%d check(s) failed.', failed);
else
    fprintf('Status: ALL PASS\n');
end
