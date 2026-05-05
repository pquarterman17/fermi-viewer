function test_fv_smoke
%TEST_FV_SMOKE  Full interaction smoke test for FermiViewer.
%
%   Loads real DM3 images, fires every reachable button callback in each
%   Processing tab, exercises keyboard shortcuts, and captures exportapp
%   screenshots. Uses SmokeRunner — any callback crash registers as a
%   failure without aborting the suite.
%
%   Specifically designed to catch the class of bugs found on 2026-05-04:
%   invisible buttons, uninitialized variables in callbacks, and broken
%   interaction flows.
%
%   Run:  runAllTests(Group="smoke")
%   Or:   run tests/smoke/test_fv_smoke

    thisDir = fileparts(mfilename('fullpath'));
    rootDir = fileparts(fileparts(thisDir));
    if ~contains(path, rootDir), addpath(rootDir); end

    srcDir = fullfile(rootDir, '+test_datasets', 'Microscopy');
    dm3a = fullfile(srcDir, 'EDW087-1.dm3');
    dm3b = fullfile(srcDir, 'EDW087-2.dm3');
    assert(isfile(dm3a) && isfile(dm3b), 'Test DM3s not found in %s', srcDir);

    fprintf('\n=== test_fv_smoke ===\n');

    % ── Launch FermiViewer ──────────────────────────────────────────────
    api = FermiViewer();
    cleanupApi = onCleanup(@() safeClose(api));
    drawnow;

    sr = SmokeRunner(api.fig);

    % ── Load test images ────────────────────────────────────────────────
    fprintf('\n── Loading test images ──\n');
    api.loadImages({dm3a, dm3b});
    drawnow;
    nImg = numel(api.getImages());
    fprintf('  Loaded %d images\n', nImg);
    assert(nImg == 2, 'Failed to load both DM3 files');

    sr.captureSnapshot('fv_01_after_load');

    % ════════════════════════════════════════════════════════════════════
    %  A. Transform tab — geometry operations
    % ════════════════════════════════════════════════════════════════════
    fprintf('\n── A. Transform tab ──\n');

    sr.fireButton('Rot 90 CW');
    sr.captureSnapshot('fv_02_rot_cw');
    sr.fireButton('Rot 90 CCW');
    sr.fireButton('Flip H');
    sr.fireButton('Flip V');
    sr.fireButton('Flip V');  % undo flip
    sr.fireButton('Reset Zoom');

    % Zoom box (non-modal, just starts capture mode — press Escape to exit)
    sr.fireButton('Zoom Box');
    sr.pressKey('escape');

    % Fixed Size Zoom — the button that exposed tonight's bug
    sr.startDialogAutoClose(Timeout=3);
    sr.fireButton('Fixed Size Zoom');
    sr.stopDialogAutoClose();
    sr.closePopups();
    sr.captureSnapshot('fv_03_after_transform');

    % Crop (needs a zoom region first — just fire and expect graceful no-op)
    sr.fireButton('Crop');

    % Set Pixel Size (dialog)
    sr.startDialogAutoClose(Timeout=3);
    sr.fireButton('Set Pixel Size');
    sr.stopDialogAutoClose();
    sr.closePopups();

    % ════════════════════════════════════════════════════════════════════
    %  B. Filter tab — image filters
    % ════════════════════════════════════════════════════════════════════
    fprintf('\n── B. Filter tab ──\n');

    filterButtons = {'Gaussian', 'Median', 'CLAHE', 'Sharpen', ...
                     'Morph Op', 'Butterworth', 'Threshold'};
    for ii = 1:numel(filterButtons)
        sr.startDialogAutoClose(Timeout=3);
        sr.fireButton(filterButtons{ii});
        sr.stopDialogAutoClose();
        sr.closePopups();
    end

    sr.fireButton('Undo Filters');
    sr.captureSnapshot('fv_04_after_filters');

    % Pixel Inspector checkbox
    sr.setCheckbox('Pixel Inspector', true);
    sr.setCheckbox('Pixel Inspector', false);

    % ════════════════════════════════════════════════════════════════════
    %  C. FFT & Analysis tab
    % ════════════════════════════════════════════════════════════════════
    fprintf('\n── C. FFT & Analysis tab ──\n');

    sr.fireButton('Show FFT');
    sr.closePopups();
    sr.captureSnapshot('fv_05_fft');

    sr.fireStateButton('Live FFT', true);
    sr.fireStateButton('Live FFT', false);

    sr.fireButton('Noise Est.');
    sr.closePopups();

    % ════════════════════════════════════════════════════════════════════
    %  D. Surface & Stack tab
    % ════════════════════════════════════════════════════════════════════
    fprintf('\n── D. Surface & Stack tab ──\n');

    sr.startDialogAutoClose(Timeout=3);
    sr.fireButton('3D Surface');
    sr.stopDialogAutoClose();
    sr.closePopups();

    sr.startDialogAutoClose(Timeout=3);
    sr.fireButton('Surface Plot');
    sr.stopDialogAutoClose();
    sr.closePopups();

    sr.captureSnapshot('fv_06_after_surface');

    % ════════════════════════════════════════════════════════════════════
    %  E. Export & Style section
    % ════════════════════════════════════════════════════════════════════
    fprintf('\n── E. Export section ──\n');

    sr.fireButton('Copy');
    sr.fireButton('EM Colormaps');
    sr.closePopups();

    sr.captureSnapshot('fv_07_export');

    % ════════════════════════════════════════════════════════════════════
    %  F. Multi-image operations
    % ════════════════════════════════════════════════════════════════════
    fprintf('\n── F. Multi-image ──\n');

    % Switch between images
    api.setActiveIdx(2); drawnow;
    sr.captureSnapshot('fv_08_image2');
    api.setActiveIdx(1); drawnow;

    % ════════════════════════════════════════════════════════════════════
    %  G. Keyboard shortcuts
    % ════════════════════════════════════════════════════════════════════
    fprintf('\n── G. Keyboard shortcuts ──\n');

    sr.pressKey('r');           % reset zoom
    sr.pressKey('f');           % fit to window
    sr.pressKey('h');           % flip horizontal
    sr.pressKey('h');           % flip back
    sr.pressKey('i');           % invert
    sr.pressKey('i');           % invert back
    sr.pressKey('bracketright');% next image
    sr.pressKey('bracketleft'); % prev image
    sr.pressKey('g');           % toggle grid
    sr.pressKey('s');           % toggle scale bar
    sr.pressKey('c');           % cycle colormap

    sr.captureSnapshot('fv_09_after_keys');

    % ════════════════════════════════════════════════════════════════════
    %  H. Zoom-out button (tonight's invisible-button bug)
    % ════════════════════════════════════════════════════════════════════
    fprintf('\n── H. Zoom-out button ──\n');

    % The zoom-out button is icon-only (empty Text) — find by Tooltip
    allBtns = findall(api.fig, 'Type', 'uibutton');
    zoomOutBtn = [];
    for ii = 1:numel(allBtns)
        if contains(allBtns(ii).Tooltip, 'Zoom out', 'IgnoreCase', true)
            zoomOutBtn = allBtns(ii);
            break;
        end
    end
    if ~isempty(zoomOutBtn) && ~isempty(zoomOutBtn.ButtonPushedFcn)
        try
            zoomOutBtn.ButtonPushedFcn(zoomOutBtn, []);
            drawnow;
            sr.passed = sr.passed + 1; %#ok<MCNPN>
            fprintf('  PASS  fireButton(zoom-out by tooltip)\n');
        catch ME
            sr.failed = sr.failed + 1; %#ok<MCNPN>
            sr.failures{end+1} = sprintf('zoom-out — %s', ME.message); %#ok<AGROW,MCNPN>
            fprintf('  FAIL  zoom-out — %s\n', ME.message);
        end
    else
        fprintf('  SKIP  zoom-out button not found by Tooltip\n');
    end

    sr.captureSnapshot('fv_10_final');

    % ════════════════════════════════════════════════════════════════════
    %  Summary
    % ════════════════════════════════════════════════════════════════════
    sr.summary();
    sr.assertAllPassed();

    function safeClose(a)
        try
            if isfield(a, 'close')
                a.close();
            end
        catch
        end
    end
end
