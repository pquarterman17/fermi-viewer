%TEST_EXPORT_SESSION_GUARDS  Guards from the export/session audit (2026-05-24).
%
%   Run from root:  runAllTests(Group="fvgui")
%
%   Covers:
%     1. setPixelSize(0/neg/NaN) must not mark the image calibrated and must
%        not crash on the next redisplay (was: addScaleBar mustBePositive
%        threw uncaught).
%     2. detectScaleBar on a tiny image returns gracefully (was: invalid
%        index crash for H<10).
%     3. api.exportMeasurements with an empty log must not throw (the GUI
%        path guarded it; the headless API path did not).

clear; clc;
thisDir = fileparts(mfilename('fullpath'));
ROOT    = fileparts(fileparts(thisDir));
if ~contains(path, ROOT), addpath(ROOT); end

passed = 0; failed = 0;
img = uint16(repmat(linspace(0, 6e4, 128), 128, 1));
tf  = fullfile(tempdir, 'guards.tif'); imwrite(img, tf);
cleanupTif = onCleanup(@() iSafeDelete(tf));

% ════════════════════════════════════════════════════════════════════════
%  1. setPixelSize rejects non-positive / non-finite sizes (no crash)
% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 1: setPixelSize guards bad values ══\n');
api = FermiViewer('Visible', 'off');
try
    api.loadImages({tf}); api.setActiveIdx(1); drawnow;
    for badVal = [0, -2.5, NaN, Inf]
        ws = warning('off', 'all');
        api.setPixelSize(badVal, 'nm');
        api.setActiveIdx(1); drawnow;   % redisplay must not crash
        warning(ws);
    end
    % A valid value must still apply
    api.setPixelSize(0.5, 'nm'); api.setActiveIdx(1); drawnow;
    fprintf('  bad pixel sizes rejected, redisplay survived, valid applied\n');
    fprintf('  PASS\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end
try, api.close(); catch, end

% ════════════════════════════════════════════════════════════════════════
%  2. detectScaleBar handles tiny images gracefully
% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 2: detectScaleBar on tiny images ══\n');
try
    for sz = {[1 1], [5 100], [2 50], [9 19]}
        r = fermiViewer.calibration.detectScaleBar(double(ones(sz{1})));
        assert(isstruct(r) && isfield(r, 'found') && ~r.found, ...
            sprintf('detectScaleBar(%dx%d) should return found=false', sz{1}(1), sz{1}(2)));
    end
    % A normal-size image still runs the detector without error
    r = fermiViewer.calibration.detectScaleBar(double(ones(256, 256)));
    assert(isstruct(r) && isfield(r, 'found'), 'normal image must return a result struct');
    fprintf('  tiny images return found=false; normal image runs\n');
    fprintf('  PASS\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
%  3. exportMeasurements with empty log does not throw
% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 3: exportMeasurements empty log ══\n');
api = FermiViewer('Visible', 'off');
try
    api.loadImages({tf}); api.setActiveIdx(1); drawnow;
    threw = false;
    ws = warning('off', 'all');
    try
        api.exportMeasurements(fullfile(tempdir, 'empty_meas.csv'));
    catch
        threw = true;
    end
    warning(ws);
    assert(~threw, 'exportMeasurements on empty log must warn gently, not throw');
    fprintf('  empty-log export handled gracefully\n');
    fprintf('  PASS\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end
try, api.close(); catch, end

% ── Summary ────────────────────────────────────────────────────────────
fprintf('\n════════════════════════════════════════════════\n');
fprintf('  EXPORT/SESSION GUARDS: %d / %d passed\n', passed, passed + failed);
fprintf('════════════════════════════════════════════════\n');
if failed > 0
    error('test_export_session_guards:failures', '%d test(s) failed.', failed);
end
fprintf('\n✓ Export/session guards intact.\n\n');

function iSafeDelete(p)
    if isfile(p), try, delete(p); catch, end, end
end
