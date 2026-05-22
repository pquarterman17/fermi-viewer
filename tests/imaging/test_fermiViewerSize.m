function test_fermiViewerSize
%TEST_FERMIVIEWERSIZE  Ratchet test: FermiViewer.m must not grow.
%
%   MASTERPLAN W5 targets FermiViewer.m < 6,000 lines (added 2026-05-01
%   alongside the BosonPlotter <6,000 goal). Without an enforcement
%   gate, new features tend to land inside the monolith as fast as
%   extractions pull lines out, and the target never arrives. This test
%   freezes the current size (plus a small buffer for in-flight edits)
%   and fails any change that pushes above the cap.
%
%   The ceiling is meant to be ratcheted **downward** as extractions
%   land. Never raise it to accommodate growth — that defeats the
%   purpose. If a feature legitimately cannot fit under the cap,
%   extract something else first, or move the new feature into
%   +fermiViewer/ (the preferred path for any new code).
%
%   Also checks the nested-function count against the parser ceiling
%   (see global rule matlab-gui-complexity.md — hard stop at 344).
%
%   Run standalone:  run tests/imaging/test_fermiViewerSize
%   Run via group :  runAllTests(Group="emgui")

    thisDir = fileparts(mfilename('fullpath'));
    rootDir = fileparts(fileparts(thisDir));
    if ~contains(path, rootDir), addpath(rootDir); end

    passed = 0;
    failed = 0;
    failures = {};

    fvPath = fullfile(rootDir, 'FermiViewer.m');

    % ════════════════════════════════════════════════════════════════════
    %  TEST 1: Line-count ratchet
    % ════════════════════════════════════════════════════════════════════
    % Current: 5,202 lines (2026-05-22 — fv repo cleanup session, batch 6).
    % Major reductions this session (5,892 -> 5,202, -11.7%):
    %   batch 1: attachContextMenu + startHistDrag + endpointDrag
    %   batch 2: onColorOverlay/onParticleCount/onQuantifyCL/onSetPixelSize/
    %     autoDetectScaleBar
    %   batch 3: updateStatusBar/panelResize/promptAndLoadRaw + revert onStackMIP
    %     (closure-callback hazard, see memory)
    %   batch 4: sessionSave/templateMatch/stitchImages/noiseEstimate/dragModeToggle
    %   batch 5: runBatchMeasurement + promptCalibrateBar
    %   batch 6: introduced buildBigUI() helper; setToolsEnabled, clearDisplay,
    %     applyTheme, displayImage delegates collapsed from 275 lines total
    %     of ui-struct-construction to 4 tiny 3-line delegates (-148 lines net).
    %
    % Ceiling carries a small buffer (~20 lines) so one in-flight edit
    % won't fail the build before an extraction commit lands. Ratchet
    % DOWN whenever an extraction lowers the baseline.
    LINE_CEILING = 5220;

    fprintf('\n== TEST 1: FermiViewer.m line-count ratchet ==\n');
    try
        fid = fopen(fvPath, 'r');
        assert(fid > 0, 'could not open %s', fvPath);
        c = onCleanup(@() fclose(fid)); %#ok<NASGU>
        nLines = 0;
        while ~feof(fid)
            fgetl(fid);
            nLines = nLines + 1;
        end

        check(sprintf('FermiViewer.m line count %d <= %d (ceiling)', ...
                      nLines, LINE_CEILING), ...
              nLines <= LINE_CEILING);

        if nLines > LINE_CEILING
            fprintf(['\n  !! FermiViewer.m grew past its ceiling.\n' ...
                     '     Do NOT raise LINE_CEILING to make this pass.\n' ...
                     '     Instead, move new code into +fermiViewer/ ' ...
                     'or extract an\n     existing nested function ' ...
                     'and ratchet the ceiling downward.\n' ...
                     '     See MASTERPLAN W5 (FermiViewer <6k) and ' ...
                     'CLAUDE.md "GUI Development Notes".\n']);
        elseif LINE_CEILING - nLines > 100
            fprintf(['  NOTE: %d lines of slack below ceiling; ' ...
                     'ratchet LINE_CEILING down to %d on next commit.\n'], ...
                    LINE_CEILING - nLines, nLines + 25);
        end
    catch ME
        recordCrash('TEST 1', ME);
    end

    % ════════════════════════════════════════════════════════════════════
    %  TEST 2: Nested-function count vs. parser ceiling
    % ════════════════════════════════════════════════════════════════════
    % MATLAB's parser refuses to load the file past ~344 total nested
    % functions. The global rule in matlab-gui-complexity.md says warn
    % at 335, hard-stop at 340. Current FV is 280 + 0 = 280 (2026-05-22).
    % All 6 doubly-nested fns eliminated this session — promoted to
    % top-level nested where they retain identical closure semantics
    % (same enclosing FermiViewer scope, accessible via @name handles
    % from siblings). Clears matlab-gui-complexity rule violations.
    % 64 slots headroom before 344.
    NESTED_FN_CEILING        = 280;
    DOUBLY_NESTED_CEILING    = 0;

    fprintf('\n== TEST 2: Nested-function count vs. parser ceiling ==\n');
    try
        src = fileread(fvPath);
        lines = splitlines(src);
        topLevel   = sum(startsWith(lines, '    function '));
        doublyNest = sum(startsWith(lines, '        function '));
        total      = topLevel + doublyNest;

        check(sprintf(['FermiViewer.m nested fns: %d top-level + ' ...
                       '%d doubly-nested = %d <= %d'], ...
                      topLevel, doublyNest, total, NESTED_FN_CEILING), ...
              total <= NESTED_FN_CEILING);

        check(sprintf('no new doubly-nested functions: %d <= %d', ...
                      doublyNest, DOUBLY_NESTED_CEILING), ...
              doublyNest <= DOUBLY_NESTED_CEILING);

        if total > NESTED_FN_CEILING
            fprintf(['\n  !! Nested-function count crossed the soft ' ...
                     'ceiling.\n     Extract a callback into +fermiViewer/ ' ...
                     'before adding more.\n     Parser hard cap is 344.\n']);
        end
    catch ME
        recordCrash('TEST 2', ME);
    end

    % ════════════════════════════════════════════════════════════════════
    %  Summary
    % ════════════════════════════════════════════════════════════════════
    fprintf('\n%s\n', repmat('=', 1, 68));
    fprintf('  test_fermiViewerSize: %d passed, %d failed\n', passed, failed);
    if failed > 0
        fprintf('\n  Failures:\n');
        for i = 1:numel(failures)
            fprintf('    - %s\n', failures{i});
        end
        error('test_fermiViewerSize:failed', '%d test(s) failed', failed);
    end
    fprintf('%s\n', repmat('=', 1, 68));

    % ── Nested helpers ─────────────────────────────────────────────
    function check(label, cond)
        if cond
            passed = passed + 1;
            fprintf('  PASS  %s\n', label);
        else
            failed = failed + 1;
            failures{end+1} = label; %#ok<AGROW>
            fprintf('  FAIL  %s\n', label);
        end
    end

    function recordCrash(testName, ME)
        failed = failed + 1;
        failures{end+1} = sprintf('%s crashed: %s', testName, ME.message); %#ok<AGROW>
        fprintf('  CRASH %s: %s\n', testName, ME.message);
    end
end
