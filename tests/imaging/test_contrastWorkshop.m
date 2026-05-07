%TEST_CONTRASTWORKSHOP  Headless tests for the ContrastWorkshop
%   facade and ContrastWorkshopModel.
%
%   Run:
%       run tests/imaging/test_contrastWorkshop
%       runAllTests(Group="emgui")

fprintf('\n');
fprintf('%s\n', repmat(char(9552), 1, 62));
fprintf('  ContrastWorkshop — Headless Test Suite\n');
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
    m = emViewer.contrast.ContrastWorkshopModel();
    assert(m.lo == 0, 'default lo');
    assert(m.hi == 1, 'default hi');
    assert(strcmp(m.transform, 'linear'), 'default transform');
    assert(m.gamma == 1.0, 'default gamma');
    assert(~m.invert, 'default invert false');
    assert(~m.histLogScale, 'default histLogScale false');
    assert(m.autoContrast, 'default autoContrast true');
    assert(m.range == 1, 'dependent range property');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 2: setLimits validation
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n== TEST 2: setLimits ==\n');
try
    m = emViewer.contrast.ContrastWorkshopModel();
    m.setLimits(0.2, 0.8);
    assert(abs(m.lo - 0.2) < 1e-9, 'lo set');
    assert(abs(m.hi - 0.8) < 1e-9, 'hi set');
    assert(~m.autoContrast, 'autoContrast cleared on manual set');
    m.setLimits(0.9, 0.1);
    assert(abs(m.lo - 0.2) < 1e-9, 'invalid order rejected (lo unchanged)');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 3: setTransform validates input
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n== TEST 3: setTransform ==\n');
try
    m = emViewer.contrast.ContrastWorkshopModel();
    m.setTransform('log');
    assert(strcmp(m.transform, 'log'), 'log accepted');
    m.setTransform('sqrt');
    assert(strcmp(m.transform, 'sqrt'), 'sqrt accepted');
    m.setTransform('power');
    assert(strcmp(m.transform, 'power'), 'power accepted');
    m.setTransform('invalid');
    assert(strcmp(m.transform, 'power'), 'invalid rejected');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 4: setGamma bounds
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n== TEST 4: setGamma ==\n');
try
    m = emViewer.contrast.ContrastWorkshopModel();
    m.setGamma(2.5);
    assert(abs(m.gamma - 2.5) < 1e-9, 'gamma set');
    m.setGamma(0);
    assert(abs(m.gamma - 2.5) < 1e-9, 'zero rejected');
    m.setGamma(-1);
    assert(abs(m.gamma - 2.5) < 1e-9, 'negative rejected');
    m.setGamma(11);
    assert(abs(m.gamma - 2.5) < 1e-9, 'over 10 rejected');
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
    m = emViewer.contrast.ContrastWorkshopModel();
    m.setLimits(0.3, 0.7);
    m.setTransform('log');
    m.setGamma(2.0);
    m.setInvert(true);
    m.reset();
    assert(m.lo == 0 && m.hi == 1, 'limits reset');
    assert(strcmp(m.transform, 'linear'), 'transform reset');
    assert(m.gamma == 1.0, 'gamma reset');
    assert(~m.invert, 'invert reset');
    assert(m.autoContrast, 'autoContrast restored');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 6: autoFromPixels
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n== TEST 6: autoFromPixels ==\n');
try
    m = emViewer.contrast.ContrastWorkshopModel();
    rng(42);
    pixels = randn(256, 256) * 100 + 500;
    m.autoFromPixels(pixels);
    assert(m.lo < 500, 'lo below mean');
    assert(m.hi > 500, 'hi above mean');
    assert(m.lo < m.hi, 'lo < hi');
    assert(m.autoContrast, 'autoContrast flag set');
    m.autoFromPixels([]);
    assert(m.lo < 500, 'empty is no-op');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 7: sync
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n== TEST 7: sync ==\n');
try
    m = emViewer.contrast.ContrastWorkshopModel();
    m.sync(struct('lo', 100, 'hi', 900, 'transform', 'sqrt', ...
        'gamma', 1.5, 'invert', true, 'histLogScale', true));
    assert(m.lo == 100, 'lo synced');
    assert(m.hi == 900, 'hi synced');
    assert(strcmp(m.transform, 'sqrt'), 'transform synced');
    assert(abs(m.gamma - 1.5) < 1e-9, 'gamma synced');
    assert(m.invert, 'invert synced');
    assert(m.histLogScale, 'histLogScale synced');
    m.sync('garbage');
    assert(m.lo == 100, 'garbage is no-op');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 8: toStruct round-trip
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n== TEST 8: toStruct ==\n');
try
    m = emViewer.contrast.ContrastWorkshopModel();
    m.setLimits(50, 200);
    m.setTransform('log');
    m.setGamma(0.5);
    m.setInvert(true);
    m.histLogScale = true;
    s = m.toStruct();
    assert(s.lo == 50 && s.hi == 200, 'limits exported');
    assert(strcmp(s.transform, 'log'), 'transform exported');
    assert(abs(s.gamma - 0.5) < 1e-9, 'gamma exported');
    assert(s.invert && s.histLogScale, 'flags exported');
    m2 = emViewer.contrast.ContrastWorkshopModel();
    m2.sync(s);
    assert(m2.lo == 50 && strcmp(m2.transform, 'log'), 'round-trip via sync');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 9: Facade delegation
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n== TEST 9: facade delegation ==\n');
try
    ws = emViewer.contrast.ContrastWorkshop();
    assert(isa(ws.model, 'emViewer.contrast.ContrastWorkshopModel'), 'model type');
    ws.setLimits(10, 90);
    assert(ws.model.lo == 10, 'setLimits delegates');
    ws.setTransform('sqrt');
    assert(strcmp(ws.model.transform, 'sqrt'), 'setTransform delegates');
    ws.setGamma(2.0);
    assert(abs(ws.model.gamma - 2.0) < 1e-9, 'setGamma delegates');
    ws.setInvert(true);
    assert(ws.model.invert, 'setInvert delegates');
    ws.reset();
    assert(ws.model.lo == 0 && ws.model.gamma == 1.0, 'reset delegates');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 10: Facade show/hide/close no-ops + hasHook
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n== TEST 10: facade lifecycle ==\n');
try
    hook.setStatus = @(msg) [];
    hook.replot    = @() [];
    hook.bad       = 'notHandle';
    ws = emViewer.contrast.ContrastWorkshop(hook);
    ws.show(); ws.hide(); ws.close();
    assert(ws.hasHook('setStatus'), 'setStatus detected');
    assert(ws.hasHook('replot'), 'replot detected');
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
    error('test_contrastWorkshop:failures', '%d check(s) failed.', failed);
else
    fprintf('Status: ALL PASS\n');
end
