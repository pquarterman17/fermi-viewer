%TEST_REPOINTEGRITY  Structural-integrity ratchet for the FermiViewer repo.
%
%   Run standalone:  cd tests/imaging; run test_repoIntegrity
%   Run from root:   runAllTests(Group="fast")  (or Group="fvgui")
%
%   Catches the three classes of silent rot that the 2026-05-21 split from
%   quantized_matlab introduced and that a file-vs-file content diff cannot
%   see (MATLAB resolves names lazily, so none of these error until the
%   exact line runs):
%
%     A. ORPHANED TESTS   — a tests/**/test_*.m that no SUITES row registers,
%                           so runAllTests silently never executes it.
%     B. EMPTY GROUPS     — a Group name accepted by validatestring that has
%                           zero registered suites, so runAllTests(Group=g)
%                           prints "no suites" and returns without error.
%     C. DANGLING REFS    — a calc/imaging/parser/fermiViewer.<fn>( call that
%                           maps to no +pkg/<fn>.m file (missing migrated
%                           code, e.g. parser.importAFM, calc.elementData).
%
%   This is a ratchet like test_fermiViewerSize / test_layoutIntegrity: it
%   never needs maintenance when healthy, and fails loudly the moment a new
%   orphan, empty group, or dangling reference is introduced.

clear; clc;

thisDir = fileparts(mfilename('fullpath'));
ROOT    = fileparts(thisDir);          % tests/
ROOT    = fileparts(ROOT);             % repo root
if ~contains(path, ROOT), addpath(ROOT); end

passed = 0; failed = 0;
runAllSrc = fileread(fullfile(ROOT, 'runAllTests.m'));

% ════════════════════════════════════════════════════════════════════════
%  CHECK A — every tests/**/test_*.m is registered in runAllTests SUITES
% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ CHECK A: no orphaned test files ══\n');
try
    % Registered test names: T('subdir','test_xxx')
    reg = regexp(runAllSrc, "T\('[^']*',\s*'(test_\w+)'\)", 'tokens');
    registered = string(cellfun(@(c) c{1}, reg, 'UniformOutput', false));

    % Test files on disk under tests/ (any depth)
    df = dir(fullfile(ROOT, 'tests', '**', 'test_*.m'));
    onDisk = string({df.name});
    onDisk = erase(onDisk, ".m");
    onDisk = unique(onDisk);

    orphans = setdiff(onDisk, registered);
    if isempty(orphans)
        fprintf('  All %d test files registered.\n', numel(onDisk));
        fprintf('  PASS\n'); passed = passed + 1;
    else
        fprintf('  ORPHANED (present on disk, never run by runAllTests):\n');
        for k = 1:numel(orphans), fprintf('    - %s\n', orphans(k)); end
        error('repoIntegrity:orphanTests', '%d orphaned test file(s).', numel(orphans));
    end
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
%  CHECK B — every validatestring Group has at least one registered suite
% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ CHECK B: no empty (silent-skip) groups ══\n');
try
    % Group tags actually present in SUITES rows: T('dir','name'), 'group',
    grpTok = regexp(runAllSrc, "T\('[^']*',\s*'test_\w+'\),\s*'(\w+)'", 'tokens');
    suiteGroups = unique(string(cellfun(@(c) c{1}, grpTok, 'UniformOutput', false)));

    % Group names accepted by validatestring (the [...] literal)
    vs = regexp(runAllSrc, "validatestring\(options\.Group,\s*\.\.\.\s*\[(.*?)\]\)", ...
        'tokens', 'once');
    assert(~isempty(vs), 'could not locate validatestring group list');
    accepted = string(regexp(vs{1}, '"(\w+)"', 'tokens'));
    accepted = unique(accepted);

    % "all" and "fast" are meta-selectors, not suite tags — exempt.
    needSuite = setdiff(accepted, ["all", "fast"]);
    empties = setdiff(needSuite, suiteGroups);
    if isempty(empties)
        fprintf('  All %d real groups have ≥1 suite.\n', numel(needSuite));
        fprintf('  PASS\n'); passed = passed + 1;
    else
        fprintf('  EMPTY groups (accepted but no suites -> silent skip):\n');
        for k = 1:numel(empties), fprintf('    - %s\n', empties(k)); end
        error('repoIntegrity:emptyGroups', '%d empty group(s).', numel(empties));
    end
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
%  CHECK C — every package-function CALL resolves to a +pkg/fn.m file
% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ CHECK C: no dangling package references ══\n');
try
    pkgRoots = {'+calc','+imaging','+parser','+fermiViewer'};
    srcFiles = {};
    for r = 1:numel(pkgRoots)
        ff = dir(fullfile(ROOT, pkgRoots{r}, '**', '*.m'));
        for i = 1:numel(ff)
            srcFiles{end+1} = fullfile(ff(i).folder, ff(i).name); %#ok<AGROW>
        end
    end
    srcFiles{end+1} = fullfile(ROOT, 'FermiViewer.m');

    % Match pkg.sub.fn immediately followed by '(' — i.e. a CALL site.
    % The lookahead drops doc-string false positives like
    % 'docs/theory/imaging.md'. Comments are stripped per line.
    pat = '(?<![\w.])(calc|imaging|parser|fermiViewer)(\.[A-Za-z]\w*)+(?=\s*\()';
    seen = containers.Map('KeyType','char','ValueType','logical');
    dangling = strings(0,1);
    for i = 1:numel(srcFiles)
        L = readlines(srcFiles{i});
        for ln = 1:numel(L)
            s = L(ln);
            pct = strfind(s, '%'); if ~isempty(pct), s = extractBefore(s, pct(1)); end
            toks = regexp(s, pat, 'match');
            for t = 1:numel(toks)
                tok = char(toks{t});
                if isKey(seen, tok), continue; end
                seen(tok) = true;
                parts = strsplit(tok, '.');
                ok = false;
                % function may be any segment k (2..n); +dirs precede it
                for k = numel(parts):-1:2
                    segs    = parts(1:k);
                    pkgDirs = strcat('+', segs(1:end-1));
                    cand    = fullfile(ROOT, pkgDirs{:}, [segs{end} '.m']);
                    if isfile(cand), ok = true; break; end
                end
                if ~ok, dangling(end+1) = string(tok); end %#ok<AGROW>
            end
        end
    end
    if isempty(dangling)
        fprintf('  All %d package call-sites resolve.\n', seen.Count);
        fprintf('  PASS\n'); passed = passed + 1;
    else
        fprintf('  DANGLING references (call maps to no +pkg/fn.m):\n');
        for k = 1:numel(dangling), fprintf('    - %s\n', dangling(k)); end
        error('repoIntegrity:danglingRefs', '%d dangling reference(s).', numel(dangling));
    end
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
%  Summary
% ════════════════════════════════════════════════════════════════════════
fprintf('\n════════════════════════════════════════════════════════════════\n');
fprintf('  REPO INTEGRITY: %d / %d checks passed\n', passed, passed + failed);
fprintf('════════════════════════════════════════════════════════════════\n');
if failed > 0
    error('test_repoIntegrity:failures', '%d structural check(s) failed.', failed);
end
fprintf('\n✓ Repo structural integrity intact.\n\n');
