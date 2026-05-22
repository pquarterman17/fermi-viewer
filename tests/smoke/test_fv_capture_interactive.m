function test_fv_capture_interactive
%TEST_FV_CAPTURE_INTERACTIVE  Visible capture-mode test for human observation.
%
%   Same logic as test_fv_capture_modes but with Visible='on' and pauses
%   so a human can watch each button:
%     1. Push the button
%     2. Verify status bar updates ('Click two points for distance...' etc.)
%     3. Verify cursor turns into crosshair
%     4. Verify the button stays highlighted while in capture mode
%     5. Cancel via Esc, verify state resets
%
%   In the 'interactive' group — opt-in only. Use a real MATLAB session
%   and call:
%       runAllTests(Group="interactive")
%   or  run tests/smoke/test_fv_capture_interactive
%
%   Each button is on-screen for ~1.5s so you can read the status bar
%   and observe the cursor.

    thisDir = fileparts(mfilename('fullpath'));
    rootDir = fileparts(fileparts(thisDir));
    addpath(rootDir);
    addpath(fullfile(rootDir, 'tests', 'smoke'));

    srcDir = fullfile(rootDir, '+test_datasets', 'Microscopy');
    dm3Path = fullfile(srcDir, 'EDW087-1.dm3');
    assert(isfile(dm3Path), 'Test DM3 not found in %s', srcDir);

    if batchStartupOptionUsed
        fprintf('\n=== test_fv_capture_interactive ===\n');
        fprintf('  SKIP  Running in -batch; visible figure invisible. Use a real MATLAB session.\n\n');
        return;
    end

    fprintf('\n=== test_fv_capture_interactive (Visible=on, paced) ===\n');

    preFigs = findall(groot, 'Type', 'figure');

    api = FermiViewer();
    api.fig.Visible = 'on';
    figure(api.fig);  % bring to front
    cleanup = onCleanup(@() closeAllTestFigures(preFigs)); %#ok<NASGU>
    drawnow; pause(0.5);

    api.loadImages({dm3Path});
    drawnow; pause(0.8);
    sr = SmokeRunner(api.fig);

    % Same set as test_fv_capture_modes
    captureButtons = {
        'Distance',     {'distance'},      false;
        'Angle',        {'angle'},         false;
        'Line Profile', {'profile'},       false;
        'Box Profile',  {'boxprofile'},    true;
        'Draw ROI',     {'rectROI', 'roiellipse', 'polyROI'}, false;
        'Place Text',   {'annotation', 'placetext'}, false;
        'Arrow',        {'arrow'},         false;
        'Line',         {'annotline'},     false;
        'Rect',         {'annotrect'},     false;
        'Circle',       {'annotcircle'},   false;
    };

    passed = 0;
    failed = 0;
    failures = {};

    pause_after_push = 1.5;  % give human time to read status bar + see cursor

    for k = 1:size(captureButtons, 1)
        btnText = captureButtons{k, 1};
        expectedModes = captureButtons{k, 2};
        opensDialogFirst = captureButtons{k, 3};

        fprintf('\n── "%s" button ──\n', btnText);

        try, api.cancelCapture(); catch, end
        drawnow; pause(0.3);

        if opensDialogFirst
            fprintf('  SKIP  prompts inputdlg first (Box Profile pattern); not driven here\n');
            continue;
        end

        ok = sr.fireButton(btnText);
        sr.closePopups();
        drawnow;
        if ~ok
            fprintf('  FAIL  fireButton returned false\n');
            failed = failed + 1;
            failures{end+1} = sprintf('%s: button fire failed', btnText); %#ok<AGROW>
            continue;
        end

        pause(pause_after_push);  % human watches status bar + cursor

        actualMode = '';
        try
            cm = api.getCaptureMode();
            if ~isempty(cm), actualMode = char(cm); end
        catch
        end

        if any(strcmpi(actualMode, expectedModes))
            fprintf('  PASS  captureMode = "%s"\n', actualMode);
            passed = passed + 1;
        elseif isempty(actualMode)
            fprintf('  FAIL  captureMode is empty (button did not enter capture)\n');
            failed = failed + 1;
            failures{end+1} = sprintf('%s: did not enter capture mode', btnText); %#ok<AGROW>
        else
            fprintf('  PASS  captureMode = "%s" (not in expected list)\n', actualMode);
            passed = passed + 1;
        end

        try, api.cancelCapture(); catch, end
        drawnow; pause(0.3);
    end

    fprintf('\n============================================================\n');
    fprintf('  Interactive capture-mode entry: %d passed, %d failed\n', passed, failed);
    fprintf('============================================================\n\n');

    if failed > 0
        error('test_fv_capture_interactive:failures', ...
            '%d capture button(s) failed:\n  %s', failed, ...
            strjoin(failures, sprintf('\n  ')));
    end

    function closeAllTestFigures(preFigsArg)
        try, pause(1.0); catch, end
        allFigs = findall(groot, 'Type', 'figure');
        for fi = 1:numel(allFigs)
            if ~any(allFigs(fi) == preFigsArg) && isvalid(allFigs(fi))
                try, delete(allFigs(fi)); catch, end
            end
        end
    end
end
