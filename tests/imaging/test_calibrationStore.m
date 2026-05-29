%TEST_CALIBRATIONSTORE  Headless tests for the persistent calibration database.
%
%   Covers fermiViewer.calibration.calibrationStore (load/save/add/remove/
%   match/dedup), extractCalibrationKey (metadata heuristics), and
%   autoApplyFromDatabase (import-time auto-calibration).
%
%   Run:
%       run tests/imaging/test_calibrationStore
%       runAllTests(Group="fv")

fprintf('\n');
fprintf('%s\n', repmat(char(9552), 1, 62));
fprintf('  Calibration Database — Headless Test Suite\n');
fprintf('%s\n', repmat(char(9552), 1, 62));

ROOT = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(ROOT);

passed = 0;
failed = 0;

% Redirect the store to a throwaway temp file so the real prefdir store is
% never touched. Guaranteed reset/cleanup in the finally-style block below.
tmpStore = [tempname, '.mat'];
fermiViewer.calibration.calibrationStore('setPath', tmpStore);
cleanupObj = onCleanup(@() resetStore(tmpStore)); %#ok<NASGU>

CS = @(varargin) fermiViewer.calibration.calibrationStore(varargin{:});

% ═══════════════════════════════════════════════════════════════════════
%  TEST 1: template + empty load
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n== TEST 1: template + empty store ==\n');
try
    CS('clear');
    e0 = CS('load');
    assert(isstruct(e0) && numel(e0) == 0, 'empty store is 0x struct');
    tmpl = CS('template');
    assert(all(isfield(tmpl, {'instrument','mode','keyType','keyValue', ...
        'pixelSize','pixelUnit','detector','dateAdded'})), 'template fields');
    fprintf('  PASS\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 2: add + round-trip load
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n== TEST 2: add + round-trip ==\n');
try
    CS('clear');
    e = CS('template');
    e.instrument = 'Titan'; e.mode = 'imaging'; e.keyType = 'mag';
    e.keyValue = 50000; e.pixelSize = 0.012; e.pixelUnit = 'nm';
    CS('add', e);
    loaded = CS('load');
    assert(numel(loaded) == 1, 'one entry');
    assert(strcmp(loaded(1).instrument, 'Titan'), 'instrument round-trip');
    assert(abs(loaded(1).pixelSize - 0.012) < 1e-12, 'pixelSize round-trip');
    assert(strcmp(loaded(1).pixelUnit, 'nm'), 'unit round-trip');
    fprintf('  PASS\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 3: match within tolerance + miss outside
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n== TEST 3: match tolerance ==\n');
try
    % 50000 is in the store from TEST 2. 50100 is within 1%, 60000 is not.
    m1 = CS('match', 'Titan', 'mag', 50100);
    assert(~isempty(m1), 'match within 1%');
    assert(abs(m1.pixelSize - 0.012) < 1e-12, 'matched pixel size');
    m2 = CS('match', 'Titan', 'mag', 60000);
    assert(isempty(m2), 'no match outside tolerance');
    m3 = CS('match', 'Titan', 'cameraLength', 50000);
    assert(isempty(m3), 'keyType must agree');
    fprintf('  PASS\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 4: add dedups same (instrument, keyType, keyValue)
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n== TEST 4: dedup on add ==\n');
try
    e = CS('template');
    e.instrument = 'titan';   % case-insensitive match to 'Titan'
    e.keyType = 'mag'; e.keyValue = 50000; e.pixelSize = 0.015; e.pixelUnit = 'nm';
    CS('add', e);
    loaded = CS('load');
    assert(numel(loaded) == 1, 'still one entry (replaced)');
    assert(abs(loaded(1).pixelSize - 0.015) < 1e-12, 'pixel size overwritten');
    fprintf('  PASS\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 5: empty-instrument entry is a wildcard
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n== TEST 5: wildcard instrument ==\n');
try
    CS('clear');
    e = CS('template');
    e.instrument = ''; e.keyType = 'mag'; e.keyValue = 100000;
    e.pixelSize = 0.006; e.pixelUnit = 'nm';
    CS('add', e);
    m = CS('match', 'AnyScope', 'mag', 100000);
    assert(~isempty(m), 'empty instrument matches any query');
    assert(abs(m.pixelSize - 0.006) < 1e-12, 'wildcard pixel size');
    fprintf('  PASS\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 6: remove
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n== TEST 6: remove ==\n');
try
    CS('clear');
    for k = 1:3
        e = CS('template'); e.instrument = sprintf('S%d', k);
        e.keyValue = 1000 * k; e.pixelSize = 0.1 * k;
        CS('add', e);
    end
    assert(numel(CS('load')) == 3, 'three entries');
    CS('remove', 2);
    rem = CS('load');
    assert(numel(rem) == 2, 'two after remove');
    assert(~any(strcmp({rem.instrument}, 'S2')), 'S2 gone');
    fprintf('  PASS\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 7: extractCalibrationKey — magnification (imaging)
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n== TEST 7: extractCalibrationKey mag ==\n');
try
    imgData = struct('pixels', zeros(4), 'calibrated', false, ...
        'pixelSize', NaN, 'pixelUnit', 'px', ...
        'acquiParams', struct( ...
            'Microscope_Info_Name', 'Titan-X', ...
            'Microscope_Info_Indicated_Magnification', 80000));
    key = fermiViewer.calibration.extractCalibrationKey(imgData);
    assert(key.found, 'key found');
    assert(strcmp(key.keyType, 'mag'), 'keyType mag');
    assert(abs(key.keyValue - 80000) < 1e-6, 'mag value');
    assert(strcmp(key.mode, 'imaging'), 'imaging mode');
    assert(strcmp(key.instrument, 'Titan-X'), 'instrument parsed');
    fprintf('  PASS\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 8: extractCalibrationKey — camera length (diffraction) + miss
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n== TEST 8: extractCalibrationKey camera length / miss ==\n');
try
    d = struct('pixels', zeros(4), ...
        'acquiParams', struct('STEM_Camera_Length', 195));
    key = fermiViewer.calibration.extractCalibrationKey(d);
    assert(key.found && strcmp(key.keyType, 'cameraLength'), 'camera length found');
    assert(abs(key.keyValue - 195) < 1e-6, 'camera length value');
    assert(strcmp(key.mode, 'diffraction'), 'diffraction mode');

    none = struct('pixels', zeros(4), 'acquiParams', struct('dataType', 6));
    keyN = fermiViewer.calibration.extractCalibrationKey(none);
    assert(~keyN.found, 'no key when metadata is bare');
    fprintf('  PASS\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 9: autoApplyFromDatabase — match calibrates an uncalibrated image
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n== TEST 9: autoApplyFromDatabase ==\n');
try
    CS('clear');
    e = CS('template');
    e.instrument = 'Titan-X'; e.keyType = 'mag'; e.keyValue = 80000;
    e.pixelSize = 0.0125; e.pixelUnit = 'nm';
    CS('add', e);

    data = makeImageData(false, NaN, 'px', 'Titan-X', 80000);
    [out, msg] = fermiViewer.calibration.autoApplyFromDatabase(data);
    od = out.metadata.parserSpecific.imageData;
    assert(od.calibrated, 'image now calibrated');
    assert(abs(od.pixelSize - 0.0125) < 1e-12, 'pixel size applied');
    assert(strcmp(od.pixelUnit, 'nm'), 'unit applied');
    assert(~isempty(msg) && contains(msg, 'Auto-calibrated'), 'notify message');
    fprintf('  PASS\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 10: autoApplyFromDatabase respects embedded calibration + no match
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n== TEST 10: autoApply leaves calibrated / unmatched images ==\n');
try
    % Already calibrated → untouched even though a DB entry matches.
    pre = makeImageData(true, 0.99, 'nm', 'Titan-X', 80000);
    [out1, msg1] = fermiViewer.calibration.autoApplyFromDatabase(pre);
    assert(abs(out1.metadata.parserSpecific.imageData.pixelSize - 0.99) < 1e-12, ...
        'embedded calibration preserved');
    assert(isempty(msg1), 'no message when already calibrated');

    % Uncalibrated but no matching mag → unchanged.
    miss = makeImageData(false, NaN, 'px', 'OtherScope', 12345);
    [out2, msg2] = fermiViewer.calibration.autoApplyFromDatabase(miss);
    assert(~out2.metadata.parserSpecific.imageData.calibrated, 'still uncalibrated');
    assert(isempty(msg2), 'no message on miss');
    fprintf('  PASS\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ── Summary ────────────────────────────────────────────────────────────
fprintf('\n%s\n', repmat(char(9552), 1, 62));
fprintf('Results: %2d passed, %2d failed\n', passed, failed);
fprintf('%s\n', repmat(char(9552), 1, 62));
if failed > 0
    error('test_calibrationStore:failures', '%d check(s) failed.', failed);
else
    fprintf('Status: ALL PASS\n');
end

% ── helpers ──────────────────────────────────────────────────────────────
function data = makeImageData(calibrated, pixelSize, pixelUnit, instrument, mag)
    imgData = struct( ...
        'pixels', zeros(8), 'calibrated', calibrated, ...
        'pixelSize', pixelSize, 'pixelUnit', pixelUnit, ...
        'acquiParams', struct( ...
            'Microscope_Info_Name', instrument, ...
            'Microscope_Info_Magnification', mag));
    data = struct('metadata', struct('parserSpecific', struct( ...
        'isImage', true, 'imageData', imgData)));
end

function resetStore(tmpStore)
    % Restore the real prefdir store path and delete the throwaway file.
    try, fermiViewer.calibration.calibrationStore('setPath', ''); catch, end
    try
        if isfile(tmpStore), delete(tmpStore); end
    catch
    end
end
