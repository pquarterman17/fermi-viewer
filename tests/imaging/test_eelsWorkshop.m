%TEST_EELSWORKSHOP  Headless tests for EELSWorkshop model + facade.
%
%   Run:
%       run tests/imaging/test_eelsWorkshop
%       runAllTests(Group="em")

fprintf('\n');
fprintf('%s\n', repmat(char(9552), 1, 62));
fprintf('  EELSWorkshop — Headless Test Suite\n');
fprintf('%s\n', repmat(char(9552), 1, 62));

ROOT = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(ROOT);

passed = 0;
failed = 0;

% ═══════════════════════════════════════════════��═══════════════════════
%  TEST 1: Model defaults
% ═════════���═════════════════════════════════════════════════════════════
fprintf('\n== TEST 1: model defaults ==\n');
try
    m = emViewer.eels.EELSWorkshopModel();
    assert(~m.active, 'inactive by default');
    assert(isempty(m.energyAxis), 'no energy axis');
    assert(isempty(m.counts), 'no counts');
    assert(~m.hasCube, 'no cube');
    assert(~m.hasSSD, 'no SSD');
    assert(~m.hasKKResult, 'no KK');
    assert(~m.hasSVDResult, 'no SVD');
    assert(strcmp(m.bgMethod, 'powerlaw'), 'default bg method');
    assert(m.numChannels() == 0, 'zero channels');
    assert(~m.hasSpectrum(), 'no spectrum');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ════���═════════════════════════════════════════════════════════��════════
%  TEST 2: bindFromAppData
% ══���═══════════════���════════════════════════════════��═══════════════════
fprintf('\n== TEST 2: bindFromAppData ==\n');
try
    m = emViewer.eels.EELSWorkshopModel();
    E = linspace(0, 100, 512)';
    I = rand(512, 1);
    eelsData = struct('energyAxis', E, 'counts', I);
    cube = rand(10, 10, 512);
    m.bindFromAppData(eelsData, cube, E);
    assert(m.hasSpectrum(), 'has spectrum');
    assert(m.hasCube, 'has cube');
    assert(m.numChannels() == 512, '512 channels');
    assert(all(m.cubeSize == [10 10 512]), 'cube size');
    assert(all(abs(m.counts - I) < 1e-10), 'counts match');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════��═══════════════════════════
%  TEST 3: sync from appData struct
% ══════════════════════════════════════════════════════��════════════════
fprintf('\n== TEST 3: sync ==\n');
try
    m = emViewer.eels.EELSWorkshopModel();
    ad.eelsMode = true;
    ad.eelsData = struct('energyAxis', (1:100)', 'counts', rand(100,1));
    ad.eelsCube = rand(5, 5, 100);
    ad.eelsEnergyAxis = (1:100)';
    ad.eelsSSD = rand(100, 1);
    ad.eelsKKResult = struct('energy', [], 'eps1', []);
    ad.eelsSVDResult = [];
    m.sync(ad);
    assert(m.active, 'active after sync');
    assert(m.hasCube, 'cube from sync');
    assert(m.hasSSD, 'SSD from sync');
    assert(m.hasKKResult, 'KK from sync');
    assert(~m.hasSVDResult, 'no SVD');
    assert(m.numChannels() == 100, '100 channels');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ════════════��═══════════════���═══════════════════════════════════════��══
%  TEST 4: reset
% ══════════════════════════════════════════════════════════════��════════
fprintf('\n== TEST 4: reset ==\n');
try
    m = emViewer.eels.EELSWorkshopModel();
    m.active = true;
    m.energyAxis = (1:50)';
    m.counts = rand(50,1);
    m.hasCube = true;
    m.hasSSD = true;
    m.reset();
    assert(~m.active, 'inactive after reset');
    assert(isempty(m.energyAxis), 'energy cleared');
    assert(~m.hasCube, 'cube cleared');
    assert(~m.hasSSD, 'SSD cleared');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═════════════���═════════════════════════════════════════════════════��═══
%  TEST 5: setPreEdgeWindow / setSignalWindow / setEdgeOnset
% ═══════════════════��═══════════════════════════════════════════════════
fprintf('\n== TEST 5: parameter setters ==\n');
try
    m = emViewer.eels.EELSWorkshopModel();
    m.setPreEdgeWindow(200, 280);
    assert(all(m.preEdgeWindow == [200 280]), 'pre-edge window');
    m.setPreEdgeWindow(300, 100);  % invalid: e1 >= e2
    assert(all(m.preEdgeWindow == [200 280]), 'invalid ignored');
    m.setSignalWindow(300, 400);
    assert(all(m.signalWindow == [300 400]), 'signal window');
    m.setEdgeOnset(284);
    assert(m.edgeOnset == 284, 'edge onset');
    m.setBgMethod('exponential');
    assert(strcmp(m.bgMethod, 'exponential'), 'bg method');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═════���═════════��═══════════════════════════════════════════════════════
%  TEST 6: summarize
% ══��═════════════════��══════════════════════════════════════════════════
fprintf('\n== TEST 6: summarize ==\n');
try
    m = emViewer.eels.EELSWorkshopModel();
    assert(contains(m.summarize(), 'inactive'), 'inactive summary');
    m.active = true;
    assert(contains(m.summarize(), 'no spectrum'), 'no spectrum summary');
    m.energyAxis = (1:200)';
    m.counts = rand(200,1);
    s = m.summarize();
    assert(contains(s, '200'), 'channel count in summary');
    m.hasCube = true;
    m.cubeSize = [64 64 200];
    m.hasSSD = true;
    s = m.summarize();
    assert(contains(s, 'cube'), 'cube in summary');
    assert(contains(s, 'SSD'), 'SSD in summary');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ══════���═════════════════════��═══════════════════════════════════════���══
%  TEST 7: Facade delegation
% ════���══════════════════════════════════════════════════════════════════
fprintf('\n== TEST 7: facade ==\n');
try
    ws = emViewer.eels.EELSWorkshop();
    assert(isa(ws.model, 'emViewer.eels.EELSWorkshopModel'), 'model type');
    assert(~ws.isActive(), 'inactive');
    assert(~ws.hasSpectrum(), 'no spectrum');
    assert(~ws.hasCube(), 'no cube');
    assert(ws.numChannels() == 0, 'zero channels');
    ws.model.active = true;
    ws.model.energyAxis = (1:50)';
    ws.model.counts = rand(50,1);
    assert(ws.isActive(), 'active via model');
    assert(ws.hasSpectrum(), 'spectrum via model');
    assert(ws.numChannels() == 50, '50 channels');
    ws.reset();
    assert(~ws.isActive(), 'reset delegates');
    ws.show(); ws.hide(); ws.close();
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═════════════════════════════════════════════════════════════════���═════
%  TEST 8: hasHook
% ═══════════════════════════════════════════════════════════════��═══════
fprintf('\n== TEST 8: hasHook ==\n');
try
    hook.setStatus = @(msg) [];
    hook.bad = 'string';
    ws = emViewer.eels.EELSWorkshop(hook);
    assert(ws.hasHook('setStatus'), 'detected');
    assert(~ws.hasHook('bad'), 'non-handle rejected');
    assert(~ws.hasHook('missing'), 'absent rejected');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═════════════════════════════════════════════════��═════════════════════
%  TEST 9: sync tolerates missing fields
% ═══��═════════════════════��═════════════════════════════════════════════
fprintf('\n== TEST 9: sync tolerates partial appData ==\n');
try
    m = emViewer.eels.EELSWorkshopModel();
    ad.eelsMode = false;
    ad.eelsData = [];
    ad.eelsCube = [];
    ad.eelsEnergyAxis = [];
    ad.eelsSSD = [];
    ad.eelsKKResult = [];
    ad.eelsSVDResult = [];
    m.sync(ad);
    assert(~m.active, 'inactive');
    assert(~m.hasSpectrum(), 'no spectrum');
    assert(~m.hasCube, 'no cube');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════��═══════════
%  TEST 10: facade sync delegates
% ═══════════════════════════════════════════════════════════��═══════════
fprintf('\n== TEST 10: facade sync ==\n');
try
    ws = emViewer.eels.EELSWorkshop();
    ad.eelsMode = true;
    ad.eelsData = struct('energyAxis', (1:80)', 'counts', rand(80,1));
    ad.eelsCube = [];
    ad.eelsEnergyAxis = (1:80)';
    ad.eelsSSD = [];
    ad.eelsKKResult = [];
    ad.eelsSVDResult = [];
    ws.sync(ad);
    assert(ws.isActive(), 'active after sync');
    assert(ws.numChannels() == 80, '80 channels');
    s = ws.summarize();
    assert(contains(s, '80'), 'summary has count');
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
    error('test_eelsWorkshop:failures', '%d check(s) failed.', failed);
else
    fprintf('Status: ALL PASS\n');
end
