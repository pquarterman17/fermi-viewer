%TEST_CALIBRATIONWORKSHOP  Headless tests for CalibrationWorkshop model + facade.
%
%   Run:
%       run tests/imaging/test_calibrationWorkshop
%       runAllTests(Group="em")

fprintf('\n');
fprintf('%s\n', repmat(char(9552), 1, 62));
fprintf('  CalibrationWorkshop — Headless Test Suite\n');
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
    m = emViewer.calibration.CalibrationWorkshopModel();
    assert(~m.calibrated, 'uncalibrated');
    assert(isnan(m.pixelSize), 'NaN pixel size');
    assert(strcmp(m.pixelUnit, 'px'), 'px unit');
    assert(~m.scaleBarVisible, 'bar hidden');
    assert(all(m.scaleBarColor == [1 1 1]), 'white bar');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 2: applyCalibration / clearCalibration
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n== TEST 2: apply + clear calibration ==\n');
try
    m = emViewer.calibration.CalibrationWorkshopModel();
    m.applyCalibration(0.5, 'nm');
    assert(m.calibrated, 'calibrated');
    assert(abs(m.pixelSize - 0.5) < 1e-10, 'pixel size');
    assert(strcmp(m.pixelUnit, 'nm'), 'unit');
    m.clearCalibration();
    assert(~m.calibrated, 'cleared');
    assert(isnan(m.pixelSize), 'NaN after clear');
    assert(strcmp(m.pixelUnit, 'px'), 'px after clear');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 3: scale bar setters
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n== TEST 3: scale bar setters ==\n');
try
    m = emViewer.calibration.CalibrationWorkshopModel();
    m.setScaleBarColor([0 1 1]);
    assert(all(m.scaleBarColor == [0 1 1]), 'color set');
    m.setScaleBarVisible(true);
    assert(m.scaleBarVisible, 'visible');
    m.setScaleBarFontSize(14);
    assert(m.scaleBarFontSize == 14, 'font size');
    m.setScaleBarFontSize(3);
    assert(m.scaleBarFontSize == 6, 'clamped low');
    m.setScaleBarFontSize(30);
    assert(m.scaleBarFontSize == 24, 'clamped high');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 4: bindFromImageData
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n== TEST 4: bindFromImageData ==\n');
try
    m = emViewer.calibration.CalibrationWorkshopModel();
    imgData = struct('calibrated', true, 'pixelSize', 2.5, 'pixelUnit', 'um');
    m.bindFromImageData(imgData);
    assert(m.calibrated, 'calibrated from imageData');
    assert(abs(m.pixelSize - 2.5) < 1e-10, 'size from imageData');
    assert(strcmp(m.pixelUnit, 'um'), 'unit from imageData');
    m.bindFromImageData(struct('calibrated', false));
    assert(~m.calibrated, 'uncalibrated after bind');
    m.bindFromImageData('garbage');
    assert(~m.calibrated, 'survives non-struct');
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
    m = emViewer.calibration.CalibrationWorkshopModel();
    imgData = struct('calibrated', true, 'pixelSize', 1.2, 'pixelUnit', 'nm', ...
        'pixels', zeros(10), 'numChannels', 1);
    ad.scaleBarColor = [1 0 0];
    ad.activeIdx = 1;
    ad.images = {struct('metadata', struct('parserSpecific', struct('imageData', imgData)))};
    m.sync(ad);
    assert(m.calibrated, 'calibrated from sync');
    assert(abs(m.pixelSize - 1.2) < 1e-10, 'size from sync');
    assert(all(m.scaleBarColor == [1 0 0]), 'color from sync');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 6: sync with no active image
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n== TEST 6: sync no image ==\n');
try
    m = emViewer.calibration.CalibrationWorkshopModel();
    m.applyCalibration(1.0, 'nm');
    ad.scaleBarColor = [1 1 1];
    ad.activeIdx = 0;
    ad.images = {};
    m.sync(ad);
    assert(~m.calibrated, 'uncalibrated when no image');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 7: reset
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n== TEST 7: reset ==\n');
try
    m = emViewer.calibration.CalibrationWorkshopModel();
    m.applyCalibration(3.0, 'um');
    m.setScaleBarVisible(true);
    m.reset();
    assert(~m.calibrated, 'uncalibrated');
    assert(~m.scaleBarVisible, 'bar hidden');
    assert(all(m.scaleBarColor == [1 1 1]), 'color reset');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 8: summarize
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n== TEST 8: summarize ==\n');
try
    m = emViewer.calibration.CalibrationWorkshopModel();
    assert(contains(m.summarize(), 'Uncalibrated'), 'uncalibrated summary');
    m.applyCalibration(0.25, 'nm');
    s = m.summarize();
    assert(contains(s, '0.25'), 'size in summary');
    assert(contains(s, 'nm'), 'unit in summary');
    m.scaleBarVisible = true;
    s = m.summarize();
    assert(contains(s, 'scale bar on'), 'bar in summary');
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 9: Facade delegation
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n== TEST 9: facade ==\n');
try
    ws = emViewer.calibration.CalibrationWorkshop();
    assert(isa(ws.model, 'emViewer.calibration.CalibrationWorkshopModel'), 'model type');
    assert(~ws.isCalibrated(), 'uncalibrated');
    ws.model.applyCalibration(1.5, 'um');
    assert(ws.isCalibrated(), 'calibrated via facade');
    [sz, u] = ws.getPixelSize();
    assert(abs(sz - 1.5) < 1e-10, 'size via facade');
    assert(strcmp(u, 'um'), 'unit via facade');
    ws.reset();
    assert(~ws.isCalibrated(), 'reset');
    ws.show(); ws.hide(); ws.close();
    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 10: hasHook
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n== TEST 10: hasHook ==\n');
try
    hook.replot = @() [];
    hook.bad = 'x';
    ws = emViewer.calibration.CalibrationWorkshop(hook);
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
    error('test_calibrationWorkshop:failures', '%d check(s) failed.', failed);
else
    fprintf('Status: ALL PASS\n');
end
