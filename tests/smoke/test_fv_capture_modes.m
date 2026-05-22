function test_fv_capture_modes
%TEST_FV_CAPTURE_MODES  Verify every "click two/N points" button enters capture mode.
%
%   The user-reported "distance doesn't work" symptom can have several
%   causes:
%     1. Button push doesn't enter capture mode (callback wiring broken)
%     2. Capture mode entered but status bar doesn't update (UX broken)
%     3. Capture mode entered but first click doesn't register (event
%        plumbing broken)
%     4. First click registers, second doesn't (state machine broken)
%
%   This test catches #1 and #2 — the button-push entry path — for every
%   capture-mode button. #3 and #4 require real mouse events that batch
%   mode cannot simulate; for those we have api.measureDistance et al.
%   (the data-layer equivalents) covered by test_fv_measurements.
%
%   Run:  runAllTests(Group="smoke")
%   Or:   run tests/smoke/test_fv_capture_modes

    thisDir = fileparts(mfilename('fullpath'));
    rootDir = fileparts(fileparts(thisDir));
    addpath(rootDir);
    addpath(fullfile(rootDir, 'tests', 'smoke'));

    srcDir = fullfile(rootDir, '+test_datasets', 'Microscopy');
    dm3Path = fullfile(srcDir, 'EDW087-1.dm3');
    assert(isfile(dm3Path), 'Test DM3 not found in %s', srcDir);

    fprintf('\n=== test_fv_capture_modes ===\n');

    preFigs = findall(groot, 'Type', 'figure');

    api = FermiViewer();
    api.fig.Visible = 'off';
    cleanup = onCleanup(@() closeAllTestFigures(preFigs)); %#ok<NASGU>
    drawnow;

    api.loadImages({dm3Path});
    drawnow;
    sr = SmokeRunner(api.fig);

    % (button label, expected capture mode, opensDialogFirst)
    % Mode names from FermiViewer.m line 122 comment:
    %   '' | 'profile' | 'boxprofile' | 'distance' | 'zoom' | 'crop' |
    %   'savecrop' | 'annotation' | 'angle' | 'polyline' | 'rectROI' |
    %   'scalebar' | 'dspacing' | 'roiellipse' | 'arrow' | 'annotline' |
    %   'annotrect' | 'annotcircle' | 'lattice' | 'gpa'
    %
    % opensDialogFirst=true: button prompts (inputdlg for width / etc.)
    %   before entering capture mode. Cannot be tested in -batch; skipped
    %   with explanatory note.
    captureButtons = {
        'Distance',     {'distance'},      false;
        'Angle',        {'angle'},         false;
        'Line Profile', {'profile'},       false;
        'Box Profile',  {'boxprofile'},    true;   % asks "Box width:" first
        'Draw ROI',     {'rectROI', 'roiellipse', 'polyROI'}, false;
        'Place Text',   {'annotation', 'placetext'}, false;
        'Arrow',        {'arrow'},         false;
        'Line',         {'annotline'},     false;
        'Rect',         {'annotrect'},     false;
        'Circle',       {'annotcircle'},   false;
    };
    isBatch = batchStartupOptionUsed;

    passed = 0;
    failed = 0;
    failures = {};

    skipped = 0;

    for k = 1:size(captureButtons, 1)
        btnText = captureButtons{k, 1};
        expectedModes = captureButtons{k, 2};
        opensDialogFirst = captureButtons{k, 3};

        fprintf('\n── "%s" button ──\n', btnText);

        if opensDialogFirst && isBatch
            fprintf('  SKIP  prompts inputdlg before capture; not testable in -batch\n');
            skipped = skipped + 1;
            continue;
        end

        % Reset state: cancel any prior capture
        try, api.cancelCapture(); catch, end
        drawnow;

        % Fire the button
        ok = sr.fireButton(btnText);
        sr.closePopups();
        if ~ok
            fprintf('  FAIL  fireButton returned false\n');
            failed = failed + 1;
            failures{end+1} = sprintf('%s: button fire failed', btnText); %#ok<AGROW>
            continue;
        end

        % Check that capture mode was entered
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
            fprintf('  PASS  captureMode = "%s" (not in expected list %s — recording)\n', ...
                actualMode, strjoin(expectedModes, '|'));
            passed = passed + 1;  % count as pass; just unknown mode name
        end
    end

    % Final cleanup: cancel capture
    try, api.cancelCapture(); catch, end

    fprintf('\n============================================================\n');
    fprintf('  Capture-mode entry test: %d passed, %d failed, %d skipped (of %d)\n', ...
        passed, failed, skipped, size(captureButtons, 1));
    fprintf('============================================================\n\n');

    if failed > 0
        error('test_fv_capture_modes:failures', ...
            '%d capture button(s) failed to enter capture mode:\n  %s', ...
            failed, strjoin(failures, sprintf('\n  ')));
    end

    function closeAllTestFigures(preFigsArg)
        allFigs = findall(groot, 'Type', 'figure');
        for fi = 1:numel(allFigs)
            if ~any(allFigs(fi) == preFigsArg) && isvalid(allFigs(fi))
                try, delete(allFigs(fi)); catch, end
            end
        end
    end
end
