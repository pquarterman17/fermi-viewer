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

% ════════════════════════════════════════════════════════════════════════
fprintf('\n%s\n', repmat(char(9552), 1, 72));
fprintf('SUMMARY: %d/%d checks passed\n', passed, passed + failed);
if failed > 0
    error('test_checkForUpdates:failures', '%d check(s) failed.', failed);
else
    fprintf('Status: ALL PASS\n');
end
