%TEST_CHECKFORUPDATES  Update-check plumbing: version read, compare, statuses.
%
%   Run standalone:  cd tests/gui; run test_checkForUpdates
%   Run from root:   runAllTests(Group="gui")
%
%   Network-free: the latest tag is injected via the LatestTag option, and
%   the offline path is exercised against a connection-refused localhost
%   endpoint. Nothing here talks to GitHub.

clear; clc;

thisDir = fileparts(mfilename('fullpath'));
rootDir = fileparts(fileparts(thisDir));
if ~contains(path, rootDir); addpath(rootDir); end

fprintf('\n=== test_checkForUpdates ===\n');
passed = 0; failed = 0;

% ── 1. appVersion reads CITATION.cff ─────────────────────────────────────
try
    v = fermiViewer.appVersion();
    txt = fileread(fullfile(rootDir, 'CITATION.cff'));
    tok = regexp(txt, 'version:\s*"([^"]+)"', 'tokens', 'once');
    assert(~isempty(v), 'appVersion returned empty');
    assert(strcmp(v, tok{1}), 'appVersion %s != CITATION.cff %s', v, tok{1});
    fprintf('  [PASS] appVersion matches CITATION.cff (%s)\n', v);
    passed = passed + 1;
catch ME
    fprintf('  [FAIL] appVersion — %s\n', ME.message); failed = failed + 1;
end

% ── 2. Injected-tag statuses: newer / same / older / short tag ───────────
try
    r = fermiViewer.checkForUpdates('LatestTag', "v99.0.0");
    assert(strcmp(r.status, 'update'), 'newer tag: got %s', r.status);
    assert(strcmp(r.latest, '99.0.0'), 'v-prefix not stripped: %s', r.latest);

    r = fermiViewer.checkForUpdates('LatestTag', string(['v' fermiViewer.appVersion()]));
    assert(strcmp(r.status, 'current'), 'same tag: got %s', r.status);

    r = fermiViewer.checkForUpdates('LatestTag', "v0.1.0");
    assert(strcmp(r.status, 'current'), 'older tag (dev ahead): got %s', r.status);

    % Two-part legacy tag (v0.42 era) must compare, not error
    r = fermiViewer.checkForUpdates('LatestTag', "v0.42");
    assert(strcmp(r.status, 'current'), 'short legacy tag: got %s', r.status);

    fprintf('  [PASS] status for newer/same/older/legacy tags\n');
    passed = passed + 1;
catch ME
    fprintf('  [FAIL] injected tags — %s\n', ME.message); failed = failed + 1;
end

% ── 3. Unparseable tag -> unknown ────────────────────────────────────────
try
    r = fermiViewer.checkForUpdates('LatestTag', "nightly");
    assert(strcmp(r.status, 'unknown'), 'garbage tag: got %s', r.status);
    fprintf('  [PASS] unparseable tag reports unknown\n');
    passed = passed + 1;
catch ME
    fprintf('  [FAIL] unparseable tag — %s\n', ME.message); failed = failed + 1;
end

% ── 4. Network failure -> offline (connection-refused localhost) ─────────
try
    r = fermiViewer.checkForUpdates('Endpoint', "http://127.0.0.1:1/latest", ...
                                    'Timeout', 2);
    assert(strcmp(r.status, 'offline'), 'refused endpoint: got %s', r.status);
    assert(contains(r.url, 'github.com'), 'fallback releases url missing');
    fprintf('  [PASS] unreachable endpoint reports offline\n');
    passed = passed + 1;
catch ME
    fprintf('  [FAIL] offline path — %s\n', ME.message); failed = failed + 1;
end

% ── 5. shouldAutoCheck: truth table (pure, deterministic, no clock reads) ─
try
    nowNum = now();

    p = struct('autoCheckUpdates', false, 'lastUpdateCheck', nowNum - 30);
    assert(~fermiViewer.shouldAutoCheck(p, nowNum), 'pref off must be false regardless of age');

    p = struct('autoCheckUpdates', true, 'lastUpdateCheck', nowNum - 8);
    assert(fermiViewer.shouldAutoCheck(p, nowNum), 'pref on + 8 days elapsed should be due');

    p = struct('autoCheckUpdates', true, 'lastUpdateCheck', nowNum - 2);
    assert(~fermiViewer.shouldAutoCheck(p, nowNum), 'pref on + 2 days elapsed should not be due');

    p = struct('autoCheckUpdates', true, 'lastUpdateCheck', 0);
    assert(fermiViewer.shouldAutoCheck(p, nowNum), 'never-checked (lastUpdateCheck=0) should be due');

    assert(~fermiViewer.shouldAutoCheck(struct(), nowNum), 'missing fields must return false, not error');

    p = struct('autoCheckUpdates', true, 'lastUpdateCheck', 'garbage');
    assert(~fermiViewer.shouldAutoCheck(p, nowNum), 'non-numeric lastUpdateCheck must return false, not error');

    fprintf('  [PASS] shouldAutoCheck truth table\n');
    passed = passed + 1;
catch ME
    fprintf('  [FAIL] shouldAutoCheck truth table — %s\n', ME.message); failed = failed + 1;
end

% ── 6. shouldAutoCheck: IntervalDays override ─────────────────────────────
try
    nowNum = now();
    p = struct('autoCheckUpdates', true, 'lastUpdateCheck', nowNum - 10);
    assert(~fermiViewer.shouldAutoCheck(p, nowNum, 'IntervalDays', 30), ...
        '10 days elapsed < 30-day interval should not be due');
    assert(fermiViewer.shouldAutoCheck(p, nowNum, 'IntervalDays', 7), ...
        '10 days elapsed >= 7-day interval should be due');
    fprintf('  [PASS] IntervalDays override respected\n');
    passed = passed + 1;
catch ME
    fprintf('  [FAIL] IntervalDays override — %s\n', ME.message); failed = failed + 1;
end

% ── 7. autoCheckUpdates: no-op in headless mode (no network, no timer) ───
try
    prevHeadlessEnv = getenv('FERMI_VIEWER_HEADLESS');
    setenv('FERMI_VIEWER_HEADLESS', '1');
    assert(fermiViewer.chrome.isHeadless(), 'expected isHeadless() true under FERMI_VIEWER_HEADLESS=1');

    delete(timerfindall('Tag', 'fermiViewerUpdateCheck'));   % clean slate

    tmpPrefsFile = [tempname() '.mat'];
    figH = uifigure('Visible', 'off');

    p  = struct('autoCheckUpdates', true, 'lastUpdateCheck', 0);
    p2 = fermiViewer.autoCheckUpdates(figH, p, tmpPrefsFile, @(msg) []);

    assert(isequal(p2.lastUpdateCheck, 0), ...
        'headless call must not stamp lastUpdateCheck (no check performed)');
    assert(isempty(timerfindall('Tag', 'fermiViewerUpdateCheck')), ...
        'headless call must not create the deferred-check timer');
    assert(~isfile(tmpPrefsFile), 'headless call must not persist prefs to disk');

    delete(figH);
    setenv('FERMI_VIEWER_HEADLESS', prevHeadlessEnv);

    fprintf('  [PASS] autoCheckUpdates is a no-op in headless mode\n');
    passed = passed + 1;
catch ME
    fprintf('  [FAIL] headless no-op — %s\n', ME.message); failed = failed + 1;
end

% ── 8. prefs round-trip: new fields survive .mat persistence ─────────────
try
    tmpPrefsFile2 = [tempname() '.mat'];
    prefs = struct('defaultColormap', 'gray', 'autoContrastLow', 2, ...
        'autoContrastHigh', 98, 'exportDPI', 300, 'pixelInspectorSize', 7, ...
        'autoCheckUpdates', true, 'lastUpdateCheck', 12345.5); %#ok<NASGU>
    save(tmpPrefsFile2, 'prefs');
    clear prefs;
    tmp = load(tmpPrefsFile2, 'prefs');
    if isfile(tmpPrefsFile2), delete(tmpPrefsFile2); end

    assert(isfield(tmp, 'prefs'), 'round-trip: prefs variable missing after load');
    assert(isequal(tmp.prefs.autoCheckUpdates, true), 'round-trip: autoCheckUpdates not preserved');
    assert(isequal(tmp.prefs.lastUpdateCheck, 12345.5), 'round-trip: lastUpdateCheck not preserved');

    fprintf('  [PASS] prefs .mat round-trip preserves new fields\n');
    passed = passed + 1;
catch ME
    fprintf('  [FAIL] prefs round-trip — %s\n', ME.message); failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
fprintf('\n%s\n', repmat(char(9552), 1, 72));
fprintf('SUMMARY: %d/%d checks passed\n', passed, passed + failed);
if failed > 0
    error('test_checkForUpdates:failures', '%d check(s) failed.', failed);
else
    fprintf('Status: ALL PASS\n');
end
