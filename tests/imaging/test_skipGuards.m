%TEST_SKIPGUARDS  Skip-guard ratchet for local-only (gitignored) test data.
%
%   Run standalone:  cd tests/imaging; run test_skipGuards
%   Run from root:   runAllTests(Group="fvgui")
%
%   Kills the "green locally / red CI" class: a test that loads a
%   gitignored +test_datasets/... file without an isfile()/exist() skip
%   guard passes on any dev box that has the file and hard-fails on CI or
%   a fresh clone (origin: 2026-06-25, test_eds_cube_channels loaded the
%   gitignored Fig4b_EDSmap_Bruker.bcf unguarded; fixed in c0bfb53).
%
%   How it works — source-text analysis, so it fails identically whether
%   or not the data files are present:
%
%     1. Parse .gitignore for patterns under +test_datasets/ (explicit
%        files and `dir/*` wildcards; negations noted). No hardcoded list —
%        newly gitignored data is covered automatically.
%     2. Scan every tests/**/*.m for references to those paths: quoted
%        basename literals ('Fig4b_EDSmap_Bruker.bcf') or dir references
%        (+test_datasets/EELS, fullfile-style '+test_datasets','EELS').
%     3. Taint-track variables assigned from referencing lines through
%        fullfile chains (fFig4b = fullfile(bcfDir, 'Fig4b_...') taints
%        fFig4b), then require at least one isfile/isfolder/exist guard
%        whose argument mentions a tainted variable or the literal itself.
%
%   Exceptions: tests/fetchRealEelsData.m (the downloader — its whole job
%   is referencing absent files) and this meta-test itself.
%
%   This is a ratchet like test_repoIntegrity: zero maintenance when
%   healthy, loud the moment an unguarded reference is introduced.

clear; clc;

thisDir = fileparts(mfilename('fullpath'));
ROOT    = fileparts(fileparts(thisDir));       % repo root

EXEMPT = ["fetchRealEelsData.m", "test_skipGuards.m"];

passed = 0; failed = 0;

% ════════════════════════════════════════════════════════════════════════
%  CHECK A — enumerate gitignored +test_datasets patterns from .gitignore
% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ CHECK A: parse local-only data patterns from .gitignore ══\n');
fileSentinels = strings(0,1);   % quoted basename literals of ignored files
dirSentinels  = strings(0,1);   % dir relpaths ignored via trailing /*
try
    gi = readlines(fullfile(ROOT, '.gitignore'));
    for k = 1:numel(gi)
        s = strtrim(gi(k));
        if s == "" || startsWith(s, "#"), continue; end
        if startsWith(s, "!")
            % Negations (e.g. !+test_datasets/EELS/README.md) re-track a
            % file, so it needs no guard; nothing to seed from them.
            continue;
        end
        if ~startsWith(s, "+test_datasets/"), continue; end
        if endsWith(s, "/*") || endsWith(s, "/")
            rel = extractAfter(s, "+test_datasets/");
            rel = regexprep(rel, "/\*?$", "");
            dirSentinels(end+1) = rel; %#ok<SAGROW>
        elseif ~contains(s, "*")
            [~, base, ext] = fileparts(char(s));
            fileSentinels(end+1) = string([base ext]); %#ok<SAGROW>
        else
            % A glob form this scanner does not model (e.g. *.bcf) —
            % fail loudly rather than silently not enforcing it.
            error('skipGuards:unhandledPattern', ...
                'Unhandled .gitignore pattern under +test_datasets: "%s" — extend test_skipGuards.', s);
        end
    end
    assert(~isempty(fileSentinels) || ~isempty(dirSentinels), ...
        'no +test_datasets patterns found — .gitignore moved or reformatted?');
    fprintf('  %d ignored file(s): %s\n', numel(fileSentinels), strjoin(fileSentinels, ', '));
    fprintf('  %d ignored dir(s):  %s\n', numel(dirSentinels), strjoin(dirSentinels, ', '));
    fprintf('  PASS\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
%  CHECK B — every referencing test carries an isfile/exist skip guard
% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ CHECK B: every local-only data reference is skip-guarded ══\n');
try
    % Seed patterns: quoted ignored-file basenames, or ignored-dir refs
    % (path literal or fullfile component form, e.g. '+test_datasets',
    % 'EELS'). Plain-word matches ("EELS" as a technique name in a mode
    % label) deliberately do NOT seed. Comment-only refs never seed
    % (comments are stripped in readCode).
    seedPat = strings(0,1);
    for f = fileSentinels(:)'
        seedPat(end+1) = "'" + regexptranslate('escape', f) + "'"; %#ok<SAGROW>
    end
    for d = dirSentinels(:)'
        esc = regexptranslate('escape', d);
        seedPat(end+1) = "\+test_datasets/" + esc; %#ok<SAGROW>
        % fullfile form: each / becomes a ','-separated quoted segment
        ffForm = strrep(esc, "/", "'\s*,\s*'");
        seedPat(end+1) = "'\+test_datasets'\s*,\s*'" + ffForm + "'"; %#ok<SAGROW>
    end
    seedRx = "(" + strjoin(seedPat, "|") + ")";

    df = dir(fullfile(ROOT, 'tests', '**', '*.m'));
    offenders = strings(0,1);
    nRef = 0;
    for i = 1:numel(df)
        if ismember(string(df(i).name), EXEMPT), continue; end
        fpath = fullfile(df(i).folder, df(i).name);
        code  = readCode(fpath);

        seedLines = find(~cellfun(@isempty, regexp(code, seedRx, 'once')));
        if isempty(seedLines), continue; end
        nRef = nRef + 1;

        % Taint: vars assigned on seed lines, propagated through later
        % assignments whose RHS uses a tainted var (fullfile chains).
        tainted = strings(0,1);
        for ln = seedLines'
            t = regexp(code{ln}, '^\s*(\w+)\s*=', 'tokens', 'once');
            if ~isempty(t), tainted(end+1) = string(t{1}); end %#ok<SAGROW>
        end
        changed = true;
        while changed
            changed = false;
            for ln = 1:numel(code)
                t = regexp(code{ln}, '^\s*(\w+)\s*=(.*)$', 'tokens', 'once');
                if isempty(t) || ismember(string(t{1}), tainted), continue; end
                for v = tainted(:)'
                    if ~isempty(regexp(t{2}, "\<" + v + "\>", 'once'))
                        tainted(end+1) = string(t{1}); %#ok<SAGROW>
                        changed = true; break;
                    end
                end
            end
        end

        % Guard: isfile/isfolder/exist whose argument text (rest of line)
        % mentions a tainted var or the ignored literal itself.
        guarded = false;
        for ln = 1:numel(code)
            g = regexp(code{ln}, '(?:isfile|isfolder|exist)\s*\((.*)$', 'tokens', 'once');
            if isempty(g), continue; end
            argTxt = g{1};
            if ~isempty(regexp(argTxt, seedRx, 'once')), guarded = true; break; end
            for v = tainted(:)'
                if ~isempty(regexp(argTxt, "\<" + v + "\>", 'once'))
                    guarded = true; break;
                end
            end
            if guarded, break; end
        end

        if ~guarded
            rel = erase(fpath, [ROOT filesep]);
            offenders(end+1) = sprintf('%s  (lines %s; tainted vars: %s)', ...
                rel, strjoin(string(seedLines'), ','), strjoin(tainted, ',')); %#ok<SAGROW>
        end
    end

    if isempty(offenders)
        fprintf('  %d test file(s) reference local-only data; all guarded.\n', nRef);
        fprintf('  PASS\n'); passed = passed + 1;
    else
        fprintf('  UNGUARDED local-only data references (green locally, red CI):\n');
        for k = 1:numel(offenders), fprintf('    - %s\n', offenders(k)); end
        fprintf('  Fix: guard with isfile()/exist() and skip gracefully —\n');
        fprintf('  see tests/imaging/test_eds_cube_channels.m (fig4bPresent).\n');
        error('skipGuards:unguarded', '%d unguarded file(s).', numel(offenders));
    end
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
%  Summary
% ════════════════════════════════════════════════════════════════════════
fprintf('\n════════════════════════════════════════════════════════════════\n');
fprintf('  SKIP GUARDS: %d / %d checks passed\n', passed, passed + failed);
fprintf('════════════════════════════════════════════════════════════════\n');
if failed > 0
    error('test_skipGuards:failures', '%d skip-guard check(s) failed.', failed);
end
fprintf('\n✓ All local-only data references are skip-guarded.\n\n');

% ────────────────────────────────────────────────────────────────────────
function code = readCode(fpath)
%READCODE  File lines with `...` continuations joined and comments
%   stripped (naive first-% cut, same convention as test_repoIntegrity —
%   a % inside a string truncates that line, which at worst hides a
%   guard written after an fprintf; guards in this repo lead their line).
    L = readlines(fpath);
    code = cell(numel(L), 1);
    carry = '';
    for k = 1:numel(L)
        s = char(L(k));
        pct = strfind(s, '%');
        if ~isempty(pct), s = s(1:pct(1)-1); end
        dots = strfind(s, '...');
        if ~isempty(dots)
            carry = [carry, s(1:dots(1)-1), ' ']; %#ok<AGROW>
            code{k} = '';
            continue;
        end
        code{k} = [carry, s];
        carry = '';
    end
end
