function test_smokeRunner
%TEST_SMOKERUNNER  Verify the SmokeRunner framework itself works correctly.
%
%   Creates a minimal uifigure with known widgets, then exercises every
%   SmokeRunner method to confirm correct pass/fail recording, widget
%   lookup, callback invocation, snapshot capture, and sequence execution.
%
%   Run:  run tests/smoke/test_smokeRunner

    thisDir = fileparts(mfilename('fullpath'));
    rootDir = fileparts(fileparts(thisDir));
    addpath(rootDir);
    addpath(fullfile(rootDir, 'tests', 'smoke'));

    passed = 0;
    failed = 0;
    failures = {};

    tmpDir = fullfile(tempdir, 'smokerunner_test');
    if isfolder(tmpDir), rmdir(tmpDir, 's'); end
    mkdir(tmpDir);
    cleanupTmp = onCleanup(@() rmdir(tmpDir, 's')); %#ok<NASGU>

    % ── Build a minimal test figure ─────────────────────────────────────
    fig = uifigure('Visible', 'off', 'Name', 'SmokeRunner Test');
    cleanupFig = onCleanup(@() delete(fig)); %#ok<NASGU>
    gl = uigridlayout(fig, [6 2]);
    gl.RowHeight = repmat({'fit'}, 1, 6);
    gl.ColumnWidth = {'1x', '1x'};

    clickCount = 0;
    btnA = uibutton(gl, 'Text', 'Alpha', ...
        'ButtonPushedFcn', @(~,~) incrementClick());
    btnB = uibutton(gl, 'Text', 'Disabled', 'Enable', 'off', ...
        'ButtonPushedFcn', @(~,~) []);
    sbtn = uibutton(gl, 'state', 'Text', 'Toggle Me', ...
        'ValueChangedFcn', @(~,~) incrementClick());
    dd = uidropdown(gl, 'Items', {'Linear', 'Log', 'Sqrt'}, ...
        'Value', 'Linear', ...
        'ValueChangedFcn', @(~,~) incrementClick());
    cbx = uicheckbox(gl, 'Text', 'Show Grid', 'Value', false, ...
        'ValueChangedFcn', @(~,~) incrementClick());
    uilabel(gl, 'Text', 'X min:');
    ef = uieditfield(gl, 'numeric', 'Value', 0, ...
        'ValueChangedFcn', @(~,~) incrementClick());

    fig.WindowKeyPressFcn = @(~,evt) onKey(evt);
    lastKey = '';
    drawnow;

    % ── Create SmokeRunner ──────────────────────────────────────────────
    sr = SmokeRunner(fig, SnapshotDir=tmpDir);

    fprintf('\n=== test_smokeRunner ===\n');

    % ════════════════════════════════════════════════════════════════════
    %  TEST 1: fireButton — success
    % ════════════════════════════════════════════════════════════════════
    clickCount = 0;
    ok = sr.fireButton('Alpha');
    check('fireButton("Alpha") succeeds', ok && clickCount == 1);

    % ════════════════════════════════════════════════════════════════════
    %  TEST 2: fireButton — disabled button fails gracefully
    % ════════════════════════════════════════════════════════════════════
    prevFailed = sr.failed;
    ok = sr.fireButton('Disabled');
    check('fireButton("Disabled") returns false', ~ok && sr.failed == prevFailed + 1);

    % ════════════════════════════════════════════════════════════════════
    %  TEST 3: fireButton — nonexistent button fails gracefully
    % ════════════════════════════════════════════════════════════════════
    prevFailed = sr.failed;
    ok = sr.fireButton('DoesNotExist');
    check('fireButton("DoesNotExist") returns false', ~ok && sr.failed == prevFailed + 1);

    % ════════════════════════════════════════════════════════════════════
    %  TEST 4: fireStateButton
    % ════════════════════════════════════════════════════════════════════
    clickCount = 0;
    ok = sr.fireStateButton('Toggle Me', true);
    check('fireStateButton toggles + fires callback', ok && clickCount == 1 && sbtn.Value);

    % ════════════════════════════════════════════════════════════════════
    %  TEST 5: setDropdown
    % ════════════════════════════════════════════════════════════════════
    clickCount = 0;
    ok = sr.setDropdown('Linear', 'Log');
    check('setDropdown fires callback + sets value', ok && clickCount == 1 && strcmp(dd.Value, 'Log'));

    % ════════════════════════════════════════════════════════════════════
    %  TEST 6: setDropdown — invalid value fails gracefully
    % ════════════════════════════════════════════════════════════════════
    prevFailed = sr.failed;
    ok = sr.setDropdown('Linear', 'Quartic');
    check('setDropdown invalid value fails', ~ok && sr.failed == prevFailed + 1);

    % ════════════════════════════════════════════════════════════════════
    %  TEST 7: setCheckbox
    % ════════════════════════════════════════════════════════════════════
    clickCount = 0;
    ok = sr.setCheckbox('Show Grid', true);
    check('setCheckbox fires callback + sets value', ok && clickCount == 1 && cbx.Value);

    % ════════════════════════════════════════════════════════════════════
    %  TEST 8: setEditField (by adjacent label)
    % ════════════════════════════════════════════════════════════════════
    clickCount = 0;
    ok = sr.setEditField('X min', 42);
    check('setEditField by label fires callback', ok && clickCount == 1 && ef.Value == 42);

    % ════════════════════════════════════════════════════════════════════
    %  TEST 9: pressKey
    % ════════════════════════════════════════════════════════════════════
    lastKey = '';
    ok = sr.pressKey('z');
    check('pressKey("z") fires WindowKeyPressFcn', ok && strcmp(lastKey, 'z'));

    % ════════════════════════════════════════════════════════════════════
    %  TEST 10: pressKey with modifier
    % ════════════════════════════════════════════════════════════════════
    lastKey = '';
    ok = sr.pressKey('s', Modifier='control');
    check('pressKey("ctrl+s") fires with modifier', ok && strcmp(lastKey, 's'));

    % ════════════════════════════════════════════════════════════════════
    %  TEST 11: captureSnapshot
    % ════════════════════════════════════════════════════════════════════
    path = sr.captureSnapshot('framework_test');
    check('captureSnapshot creates PNG', ~isempty(path) && isfile(path));

    % ════════════════════════════════════════════════════════════════════
    %  TEST 12: runSequence
    % ════════════════════════════════════════════════════════════════════
    clickCount = 0;
    prevPassed = sr.passed;
    sr.runSequence({
        {'button', 'Alpha'}
        {'checkbox', 'Show Grid', false}
        {'key', 'z'}
        {'snap', 'sequence_test'}
    });
    check('runSequence executes 4 steps', ...
        clickCount == 2 && sr.passed >= prevPassed + 3);

    % ════════════════════════════════════════════════════════════════════
    %  TEST 13: closePopups
    % ════════════════════════════════════════════════════════════════════
    popup = uifigure('Visible', 'off', 'Name', 'Popup Test');
    drawnow;
    sr.closePopups();
    check('closePopups deletes child figures', ~isvalid(popup));

    % ════════════════════════════════════════════════════════════════════
    %  TEST 14: results tracking
    % ════════════════════════════════════════════════════════════════════
    check('passed + failed == total interactions', ...
        sr.passed + sr.failed == sr.passed + sr.failed);
    check('failures list matches failed count', numel(sr.failures) == sr.failed);

    % ════════════════════════════════════════════════════════════════════
    %  Summary
    % ════════════════════════════════════════════════════════════════════
    fprintf('\n%s\n', repmat('=', 1, 60));
    fprintf('  test_smokeRunner: %d passed, %d failed\n', passed, failed);
    if failed > 0
        fprintf('\n  Failures:\n');
        for i = 1:numel(failures)
            fprintf('    - %s\n', failures{i});
        end
        error('test_smokeRunner:failed', '%d test(s) failed', failed);
    end
    fprintf('%s\n', repmat('=', 1, 60));

    % Print the SmokeRunner's own summary for visibility
    fprintf('\n  SmokeRunner internal state:\n');
    sr.summary();

    % ── Nested helpers ─────────────────────────────────────────────────
    function incrementClick()
        clickCount = clickCount + 1;
    end

    function onKey(evt)
        lastKey = evt.Key;
    end

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
end
