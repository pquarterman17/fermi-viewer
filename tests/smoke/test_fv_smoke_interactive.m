function test_fv_smoke_interactive
%TEST_FV_SMOKE_INTERACTIVE  Visible-figure smoke test for human observation.
%
%   Same flow as test_fv_smoke but with the figure SHOWN (Visible='on')
%   and a brief pause between each significant action so a human watching
%   can see what's happening. Useful for production-readiness validation
%   when you want to confirm the GUI looks right, not just that the
%   callbacks don't crash.
%
%   This test is in the 'interactive' group, which is OPT-IN — not run
%   by default. To run it, open a real MATLAB session (not -batch) and:
%
%       runAllTests(Group="interactive")
%   or  run tests/smoke/test_fv_smoke_interactive
%
%   Pacing: ~0.4s between actions, ~0.8s after major operations. Total
%   runtime ~30–60s depending on machine. Pauses use pause() not
%   drawnow(limitrate) because we want the user to register what
%   happened, not just the renderer to keep up.

    thisDir = fileparts(mfilename('fullpath'));
    rootDir = fileparts(fileparts(thisDir));
    addpath(rootDir);
    addpath(fullfile(rootDir, 'tests', 'smoke'));

    srcDir = fullfile(rootDir, '+test_datasets', 'Microscopy');
    dm3a = fullfile(srcDir, 'EDW087-1.dm3');
    dm3b = fullfile(srcDir, 'EDW087-2.dm3');
    assert(isfile(dm3a) && isfile(dm3b), 'Test DM3s not found in %s', srcDir);

    if batchStartupOptionUsed
        fprintf('\n=== test_fv_smoke_interactive ===\n');
        fprintf('  SKIP  Running in -batch; visible figure invisible. Use a real MATLAB session.\n\n');
        return;
    end

    fprintf('\n=== test_fv_smoke_interactive (Visible=on, paced) ===\n');

    preExistingFigs = findall(groot, 'Type', 'figure');

    % Launch VISIBLE — that's the whole point of this test
    api = FermiViewer();
    api.fig.Visible = 'on';
    figure(api.fig);  % bring to front
    cleanupApi = onCleanup(@() closeAllTestFigures(preExistingFigs)); %#ok<NASGU>
    drawnow;
    pause(0.5);  % let the window paint

    sr = SmokeRunner(api.fig);
    pacing = 0.4;  % seconds between minor actions
    bigPace = 0.8; % seconds after major operations

    fprintf('\n── Loading test images ──\n');
    api.loadImages({dm3a, dm3b});
    drawnow; pause(bigPace);
    assert(numel(api.getImages()) == 2, 'Failed to load both DM3 files');
    sr.captureSnapshot('interactive_01_after_load');

    % A. Transform — geometry operations
    fprintf('\n── A. Transform (watch the image rotate/flip) ──\n');
    sr.fireButton('Rot 90 CW'); drawnow; pause(pacing);
    sr.fireButton('Rot 90 CCW'); drawnow; pause(pacing);
    sr.fireButton('Flip H'); drawnow; pause(pacing);
    sr.fireButton('Flip V'); drawnow; pause(pacing);
    sr.fireButton('Flip V'); drawnow; pause(pacing);
    sr.fireButton('Reset Zoom'); drawnow; pause(bigPace);
    sr.captureSnapshot('interactive_02_after_transform');

    % B. FFT — visual confirmation
    fprintf('\n── B. FFT (watch frequency-domain panel appear) ──\n');
    sr.fireButton('Show FFT'); drawnow; pause(bigPace);
    sr.closePopups();
    sr.captureSnapshot('interactive_03_fft');

    sr.fireStateButton('Live FFT', true); drawnow; pause(pacing);
    sr.fireStateButton('Live FFT', false); drawnow; pause(pacing);

    % C. Surface — 3D rendering
    fprintf('\n── C. 3D surface (watch the 3D plot pop up) ──\n');
    sr.fireButton('3D Surface'); drawnow; pause(bigPace);
    sr.closePopups();
    sr.fireButton('Surface Plot'); drawnow; pause(bigPace);
    sr.closePopups();
    sr.captureSnapshot('interactive_04_surface');

    % D. Multi-image — switch active
    fprintf('\n── D. Multi-image (watch image 2 load) ──\n');
    api.setActiveIdx(2); drawnow; pause(bigPace);
    sr.captureSnapshot('interactive_05_image2');
    api.setActiveIdx(1); drawnow; pause(bigPace);

    % E. Export operation
    fprintf('\n── E. Copy to clipboard ──\n');
    sr.fireButton('Copy'); drawnow; pause(pacing);

    % F. Keyboard shortcuts
    fprintf('\n── F. Keyboard shortcuts (watch for state changes) ──\n');
    keys = {'r', 'f', 'h', 'h', 'i', 'i'};
    for k = 1:numel(keys)
        sr.pressKey(keys{k}); drawnow; pause(pacing);
    end

    sr.captureSnapshot('interactive_06_final');

    fprintf('\n');
    sr.summary();
    sr.assertAllPassed();

    function closeAllTestFigures(preFigs)
        % Give human a moment to look at final state before closing
        try, pause(1.0); catch, end
        allFigs = findall(groot, 'Type', 'figure');
        for fi = 1:numel(allFigs)
            if ~any(allFigs(fi) == preFigs) && isvalid(allFigs(fi))
                try, delete(allFigs(fi)); catch, end
            end
        end
    end
end
