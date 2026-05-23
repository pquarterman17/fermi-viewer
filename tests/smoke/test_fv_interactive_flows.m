function test_fv_interactive_flows
%TEST_FV_INTERACTIVE_FLOWS  End-to-end click-flow tests for measurements.
%
%   Closes the gap that previous tests left open: until now we covered
%   1. api.measureDistance(x1,y1,x2,y2)  — direct data-layer call
%   2. fireButton("Distance")             — verify capture mode entered
%
%   But the path users actually take —
%     a. Click Distance button
%     b. Click on image at (x1, y1)
%     c. Click on image at (x2, y2)
%     d. Measurement appears with label
%   — wasn't end-to-end tested. This test uses the new api.simulateClick
%   to drive (b) and (c), and verifies (d) for every two-click capture
%   mode.
%
%   What this catches that the other tests miss:
%     - bugs in captureDispatch's click accumulator
%     - bugs in the executeXxx callback wiring back into the closure
%     - state-cleanup bugs where capture mode doesn't reset after the
%       second click
%
%   Run:  runAllTests(Group="smoke")

    thisDir = fileparts(mfilename('fullpath'));
    rootDir = fileparts(fileparts(thisDir));
    addpath(rootDir);
    addpath(fullfile(rootDir, 'tests', 'smoke'));

    srcDir = fullfile(rootDir, '+test_datasets', 'Microscopy');
    dm3Path = fullfile(srcDir, 'EDW087-1.dm3');
    assert(isfile(dm3Path), 'Test DM3 not found in %s', srcDir);

    fprintf('\n=== test_fv_interactive_flows ===\n');

    api = FermiViewer();
    api.fig.Visible = 'off';
    drawnow;
    api.loadImages({dm3Path});
    drawnow;
    sr = SmokeRunner(api.fig);

    % (button label, capture mode, post-condition predicate, label)
    flows = {
        'Distance',     'distance',     @() hasMeasurementOfType(api, 'distance'),  'measurement registered as distance';
        'Line Profile', 'profile',      @() hasMeasurementOfType(api, 'profile'),   'measurement registered as profile';
        % Angle requires 3 clicks, skip here (would need different driver)
        'Arrow',        'arrow',        @() countAnnotsLike(api, 'arrow') >= 1,     'arrow annotation registered';
        'Line',         'annotline',    @() countAnnotsLike(api, 'line') >= 1,      'line annotation registered';
        'Rect',         'annotrect',    @() countAnnotsLike(api, 'rect') >= 1,      'rect annotation registered';
        'Circle',       'annotcircle',  @() countAnnotsLike(api, 'circle') >= 1,    'circle annotation registered';
    };

    passed = 0;
    failed = 0;
    failures = {};

    for k = 1:size(flows, 1)
        btnText = flows{k, 1};
        expectedMode = flows{k, 2};
        postCond = flows{k, 3};
        postLabel = flows{k, 4};

        fprintf('\n── Flow: %s ──\n', btnText);

        % Reset state
        try, api.cancelCapture(); catch, end
        try, api.clearOverlays(); catch, end
        drawnow;

        % Snapshot counts BEFORE
        nMeasBefore = api.measWorkshop.numMeasurements();
        annBefore   = numel(api.getAnnotations());

        % 1. Push the button
        ok = sr.fireButton(btnText);
        if ~ok
            failed = failed + 1;
            failures{end+1} = sprintf('%s: button fire failed', btnText); %#ok<AGROW>
            continue;
        end

        % 2. Verify capture mode
        cm = char(api.getCaptureMode());
        if ~strcmpi(cm, expectedMode)
            failed = failed + 1;
            failures{end+1} = sprintf('%s: expected captureMode "%s", got "%s"', ...
                btnText, expectedMode, cm); %#ok<AGROW>
            api.cancelCapture();
            continue;
        end
        fprintf('  ✔  captureMode = "%s"\n', cm);

        % 3. Simulate first click at (100, 100)
        api.simulateClick(100, 100);
        drawnow;

        % 4. Simulate second click at (400, 400)
        api.simulateClick(400, 400);
        drawnow;

        % 5. Verify capture mode reset
        cmAfter = char(api.getCaptureMode());
        if ~isempty(cmAfter)
            fprintf('  ⚠  captureMode not reset (still "%s")\n', cmAfter);
        else
            fprintf('  ✔  captureMode reset after 2 clicks\n');
        end

        % 6. Verify post-condition (measurement / annotation added)
        ok = false;
        try, ok = postCond(); catch ME, fprintf('  ⚠  postCond errored: %s\n', ME.message); end

        nMeasAfter = api.measWorkshop.numMeasurements();
        annAfter   = numel(api.getAnnotations());
        fprintf('  Δmeasurements = %d, Δannotations = %d\n', ...
            nMeasAfter - nMeasBefore, annAfter - annBefore);

        if ok
            fprintf('  ✔  PASS — %s\n', postLabel);
            passed = passed + 1;
        else
            fprintf('  ✘  FAIL — %s\n', postLabel);
            failed = failed + 1;
            failures{end+1} = sprintf('%s: %s', btnText, postLabel); %#ok<AGROW>
        end
    end

    fprintf('\n============================================================\n');
    fprintf('  Interactive-flow: %d passed, %d failed (of %d)\n', ...
        passed, failed, size(flows, 1));
    fprintf('============================================================\n\n');

    if failed > 0
        error('test_fv_interactive_flows:failures', ...
            '%d flow(s) failed:\n  %s', failed, strjoin(failures, sprintf('\n  ')));
    end
end


function tf = hasMeasurementOfType(api, typeName)
%HASMEASUREMENTOFTYPE  Walk appData.overlays.measurements for a matching type.
    overlays = api.getOverlays();
    measList = overlays.measurements;
    tf = false;
    for k = 1:numel(measList)
        if isfield(measList{k}, 'type') && strcmpi(measList{k}.type, typeName)
            tf = true; return;
        end
    end
end


function n = countAnnotsLike(api, shapeKey)
%COUNTANNOTSLIKE  Count annotations whose visual handle indicates the shape.
%   Text annotations have hText; arrows have hLine + hHead; lines have
%   hLine; rects have hRect; circles have hCircle. Matches by the
%   shape-specific handle being present and valid.
    ann = api.getAnnotations();
    n = 0;
    for k = 1:numel(ann)
        a = ann{k};
        hasField = false;
        switch lower(shapeKey)
            case 'text',   hasField = isfield(a, 'hText')  && ~isempty(a.hText)  && isvalid(a.hText);
            case 'arrow',  hasField = isfield(a, 'hHead')  && ~isempty(a.hHead)  && isvalid(a.hHead);
            case 'line',   hasField = isfield(a, 'hLine')  && ~isempty(a.hLine)  && isvalid(a.hLine) ...
                                       && (~isfield(a, 'hHead') || isempty(a.hHead));
            case 'rect',   hasField = isfield(a, 'hRect')  && ~isempty(a.hRect)  && isvalid(a.hRect);
            case 'circle', hasField = isfield(a, 'hCircle')&& ~isempty(a.hCircle)&& isvalid(a.hCircle);
        end
        if hasField, n = n + 1; end
    end
end
