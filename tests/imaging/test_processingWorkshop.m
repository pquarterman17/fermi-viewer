%TEST_PROCESSINGWORKSHOP  Headless tests for ProcessingWorkshop model + facade.
%
%   Run:
%       run tests/imaging/test_processingWorkshop
%       runAllTests(Group="em")

fprintf('\n');
fprintf('%s\n', repmat(char(9552), 1, 62));
fprintf('  ProcessingWorkshop — Headless Test Suite\n');
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
    m = emViewer.processing.ProcessingWorkshopModel();
    assert(~m.liveFFTActive, 'liveFFT off');
    assert(m.lastParticleCount == 0, 'no particles');
    assert(isnan(m.lastThreshold), 'no threshold');
    assert(m.lastMinArea == 10, 'default minArea');
    assert(m.numAligned == 0, 'no aligned');
    assert(isempty(m.lastAlignShifts), 'no shifts');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 2: setLiveFFT
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n== TEST 2: setLiveFFT ==\n');
try
    m = emViewer.processing.ProcessingWorkshopModel();
    m.setLiveFFT(true);
    assert(m.liveFFTActive, 'on');
    m.setLiveFFT(false);
    assert(~m.liveFFTActive, 'off');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 3: recordParticleResult
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n== TEST 3: recordParticleResult ==\n');
try
    m = emViewer.processing.ProcessingWorkshopModel();
    m.recordParticleResult(42, 128, 15);
    assert(m.lastParticleCount == 42, 'count');
    assert(m.lastThreshold == 128, 'threshold');
    assert(m.lastMinArea == 15, 'minArea');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 4: recordAlignment
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n== TEST 4: recordAlignment ==\n');
try
    m = emViewer.processing.ProcessingWorkshopModel();
    shifts = [0 0; 3 -2; 5 1];
    m.recordAlignment(shifts);
    assert(m.numAligned == 3, '3 aligned');
    assert(all(all(m.lastAlignShifts == shifts)), 'shifts stored');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 5: reset
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n== TEST 5: reset ==\n');
try
    m = emViewer.processing.ProcessingWorkshopModel();
    m.setLiveFFT(true);
    m.recordParticleResult(10, 50, 5);
    m.recordAlignment([1 2; 3 4]);
    m.reset();
    assert(~m.liveFFTActive, 'liveFFT off');
    assert(m.lastParticleCount == 0, 'particles reset');
    assert(m.numAligned == 0, 'aligned reset');
    assert(isempty(m.lastAlignShifts), 'shifts cleared');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 6: summarize
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n== TEST 6: summarize ==\n');
try
    m = emViewer.processing.ProcessingWorkshopModel();
    assert(contains(m.summarize(), 'idle'), 'idle summary');
    m.setLiveFFT(true);
    assert(contains(m.summarize(), 'Live FFT'), 'live FFT in summary');
    m.recordParticleResult(7, 100, 10);
    s = m.summarize();
    assert(contains(s, '7 particles'), 'particles in summary');
    m.recordAlignment([0 0; 1 1; 2 2]);
    s = m.summarize();
    assert(contains(s, '3 aligned'), 'aligned in summary');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 7: Facade delegation
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n== TEST 7: facade ==\n');
try
    ws = emViewer.processing.ProcessingWorkshop();
    assert(isa(ws.model, 'emViewer.processing.ProcessingWorkshopModel'), 'model type');
    assert(~ws.isLiveFFTActive(), 'not active');
    ws.setLiveFFT(true);
    assert(ws.isLiveFFTActive(), 'active');
    ws.recordParticleResult(5, 80, 8);
    assert(ws.model.lastParticleCount == 5, 'particle via facade');
    ws.recordAlignment([1 2]);
    assert(ws.model.numAligned == 1, 'align via facade');
    ws.reset();
    assert(~ws.isLiveFFTActive(), 'reset');
    ws.show(); ws.hide(); ws.close();
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 8: hasHook
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n== TEST 8: hasHook ==\n');
try
    hook.replot = @() [];
    hook.bad = 'str';
    ws = emViewer.processing.ProcessingWorkshop(hook);
    assert(ws.hasHook('replot'), 'detected');
    assert(~ws.hasHook('bad'), 'non-handle rejected');
    assert(~ws.hasHook('missing'), 'absent rejected');
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
    error('test_processingWorkshop:failures', '%d check(s) failed.', failed);
else
    fprintf('Status: ALL PASS\n');
end
