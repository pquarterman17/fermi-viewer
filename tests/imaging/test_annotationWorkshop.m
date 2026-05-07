%TEST_ANNOTATIONWORKSHOP  Headless tests for AnnotationWorkshop model + facade.
%
%   Run:
%       run tests/imaging/test_annotationWorkshop
%       runAllTests(Group="em")

fprintf('\n');
fprintf('%s\n', repmat(char(9552), 1, 62));
fprintf('  AnnotationWorkshop — Headless Test Suite\n');
fprintf('%s\n', repmat(char(9552), 1, 62));

ROOT = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(ROOT);

passed = 0;
failed = 0;

% ═══════════════════════════════════════════════════════════════════════
%  TEST 1: Model defaults
% ═════════════════════════════════════════════════════��═════════════════
fprintf('\n== TEST 1: model defaults ==\n');
try
    m = emViewer.annotation.AnnotationWorkshopModel();
    assert(m.numAnnotations() == 0, 'starts empty');
    assert(m.selectedIdx == 0, 'no selection');
    assert(all(m.defaultColor == [1 1 1]), 'default white');
    assert(m.defaultFontSize == 12, 'default size 12');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 2: add / get / numAnnotations
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n== TEST 2: add + get ==\n');
try
    m = emViewer.annotation.AnnotationWorkshopModel();
    m.add(100, 200, 'Hello', 14, [1 0 0]);
    assert(m.numAnnotations() == 1, 'one annotation');
    a = m.get(1);
    assert(a.x == 100 && a.y == 200, 'coords');
    assert(strcmp(a.str, 'Hello'), 'text');
    assert(a.fontSize == 14, 'font size');
    assert(all(a.color == [1 0 0]), 'color');
    m.add(50, 60, 'World');
    assert(m.numAnnotations() == 2, 'two annotations');
    a2 = m.get(2);
    assert(a2.fontSize == 12, 'default fontSize used');
    assert(isempty(m.get(99)), 'out-of-range returns empty');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 3: remove + selection adjustment
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n== TEST 3: remove ==\n');
try
    m = emViewer.annotation.AnnotationWorkshopModel();
    m.add(10, 20, 'A'); m.add(30, 40, 'B'); m.add(50, 60, 'C');
    m.select(2);
    m.remove(1);
    assert(m.numAnnotations() == 2, 'one removed');
    assert(m.selectedIdx == 1, 'selection shifted down');
    a = m.get(1);
    assert(strcmp(a.str, 'B'), 'B is now first');
    m.remove(1);
    assert(m.selectedIdx == 0, 'selection cleared on remove');
    m.remove(99);
    assert(m.numAnnotations() == 1, 'out-of-range is no-op');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 4: select / deselect / clearAll
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n== TEST 4: select + clearAll ==\n');
try
    m = emViewer.annotation.AnnotationWorkshopModel();
    m.add(1, 2, 'X'); m.add(3, 4, 'Y');
    m.select(2);
    assert(m.selectedIdx == 2, 'selected 2');
    m.deselect();
    assert(m.selectedIdx == 0, 'deselected');
    m.clearAll();
    assert(m.numAnnotations() == 0, 'cleared');
    assert(m.selectedIdx == 0, 'selection cleared');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 5: update
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n== TEST 5: update ==\n');
try
    m = emViewer.annotation.AnnotationWorkshopModel();
    m.add(10, 20, 'Test', 12, [1 1 1]);
    m.update(1, 'str', 'Changed');
    assert(strcmp(m.get(1).str, 'Changed'), 'str updated');
    m.update(1, 'fontSize', 18);
    assert(m.get(1).fontSize == 18, 'fontSize updated');
    m.update(1, 'nonexistent', 42);
    m.update(99, 'str', 'nope');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 6: sync from overlay cell array
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n== TEST 6: sync ==\n');
try
    m = emViewer.annotation.AnnotationWorkshopModel();
    overlays = { ...
        struct('hText', [], 'x', 10, 'y', 20, 'str', 'A', 'fontSize', 14, 'color', [1 0 0]), ...
        struct('hText', [], 'x', 30, 'y', 40, 'str', 'B', 'fontSize', 11, 'color', [0 1 0])};
    m.sync(overlays);
    assert(m.numAnnotations() == 2, '2 annotations synced');
    a1 = m.get(1);
    assert(a1.x == 10 && strcmp(a1.str, 'A'), 'first annotation data');
    m.sync({});
    assert(m.numAnnotations() == 0, 'empty sync clears');
    m.sync({'not a struct', 42});
    assert(m.numAnnotations() == 0, 'invalid items skipped');
    m.sync('garbage');
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
    m = emViewer.annotation.AnnotationWorkshopModel();
    assert(contains(m.summarize(), 'No annotations'), 'empty summary');
    m.add(1, 2, 'X'); m.add(3, 4, 'Y');
    assert(contains(m.summarize(), '2'), 'count in summary');
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
    ws = emViewer.annotation.AnnotationWorkshop();
    assert(isa(ws.model, 'emViewer.annotation.AnnotationWorkshopModel'), 'model type');
    ws.model.add(1, 2, 'A');
    assert(ws.numAnnotations() == 1, 'numAnnotations delegates');
    ws.clearAll();
    assert(ws.numAnnotations() == 0, 'clearAll delegates');
    overlays = {struct('x', 5, 'y', 6, 'str', 'Z', 'fontSize', 10, 'color', [0 0 1])};
    ws.sync(overlays);
    assert(ws.numAnnotations() == 1, 'sync delegates');
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
    hook.drawOverlay = @(t, a) [];
    hook.bad = 'nope';
    ws = emViewer.annotation.AnnotationWorkshop(hook);
    assert(ws.hasHook('drawOverlay'), 'detected');
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
    error('test_annotationWorkshop:failures', '%d check(s) failed.', failed);
else
    fprintf('Status: ALL PASS\n');
end
