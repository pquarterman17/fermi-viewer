function test_fv_smoke
%TEST_FV_SMOKE  Full interaction smoke test for FermiViewer.
%
%   Loads real DM3 images, fires every reachable button callback in each
%   Processing tab, exercises keyboard shortcuts, and captures exportapp
%   screenshots. Uses SmokeRunner — any callback crash registers as a
%   failure without aborting the suite.
%
%   Many FermiViewer buttons open inputdlg/uiconfirm which block in
%   -batch mode. These are skipped with an explanatory message. The test
%   still validates: geometry ops, non-dialog filters, FFT, surface,
%   export, multi-image, and keyboard shortcuts.
%
%   Run:  runAllTests(Group="smoke")
%   Or:   run tests/smoke/test_fv_smoke

    thisDir = fileparts(mfilename('fullpath'));
    rootDir = fileparts(fileparts(thisDir));
    addpath(rootDir);
    addpath(fullfile(rootDir, 'tests', 'smoke'));

    srcDir = fullfile(rootDir, '+test_datasets', 'Microscopy');
    dm3a = fullfile(srcDir, 'EDW087-1.dm3');
    dm3b = fullfile(srcDir, 'EDW087-2.dm3');
    assert(isfile(dm3a) && isfile(dm3b), 'Test DM3s not found in %s', srcDir);

    isBatch = batchStartupOptionUsed;

    fprintf('\n=== test_fv_smoke ===\n');

    % ── Launch FermiViewer ──────────────────────────────────────────────
    api = FermiViewer();
    api.fig.Visible = 'off';
    cleanupApi = onCleanup(@() safeClose(api)); %#ok<NASGU>
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
    %  A. Transform tab — geometry operations (no dialogs)
    % ════════════════════════════════════════════════════════════════════
    fprintf('\n── A. Transform tab ──\n');

    sr.fireButton('Rot 90 CW');
    sr.captureSnapshot('fv_02_rot_cw');
    sr.fireButton('Rot 90 CCW');
    sr.fireButton('Flip H');
    sr.fireButton('Flip V');
    sr.fireButton('Flip V');
    sr.fireButton('Reset Zoom');
    sr.fireButton('Crop');

    sr.captureSnapshot('fv_03_after_transform');

    if ~isBatch
        sr.fireButton('Zoom Box');
        sr.pressKey('escape');
        sr.fireButton('Fixed Size Zoom');
        sr.fireButton('Set Pixel Size');
    else
        fprintf('  SKIP  Zoom Box/Fixed Size Zoom/Set Pixel Size (inputdlg in -batch)\n');
    end

    % ════════════════════════════════════════════════════════════════════
    %  B. Filter tab — most open inputdlg, skip in batch
    % ════════════════════════════════════════════════════════════════════
    fprintf('\n── B. Filter tab ──\n');

    if ~isBatch
        filterButtons = {'Gaussian', 'Median', 'CLAHE', 'Sharpen', ...
                         'Morph Op', 'Butterworth'};
        for ii = 1:numel(filterButtons)
            sr.fireButton(filterButtons{ii});
        end
    else
        fprintf('  SKIP  filter dialogs (inputdlg not supported in -batch)\n');
    end

    sr.fireButton('Threshold');
    sr.fireButton('Undo Filters');
    sr.captureSnapshot('fv_04_after_filters');

    % ════════════════════════════════════════════════════════════════════
    %  C. FFT & Analysis tab
    % ════════════════════════════════════════════════════════════════════
    fprintf('\n── C. FFT & Analysis tab ──\n');

    sr.fireButton('Show FFT');
    sr.closePopups();
    sr.captureSnapshot('fv_05_fft');

    sr.fireStateButton('Live FFT', true);
    sr.fireStateButton('Live FFT', false);

    % ════════════════════════════════════════════════════════════════════
    %  D. Surface & Stack tab
    % ════════════════════════════════════════════════════════════════════
    fprintf('\n── D. Surface & Stack tab ──\n');

    sr.fireButton('3D Surface');
    sr.closePopups();

    sr.fireButton('Surface Plot');
    sr.closePopups();

    sr.captureSnapshot('fv_06_after_surface');

    % ════════════════════════════════════════════════════════════════════
    %  E. Export & Style section
    % ════════════════════════════════════════════════════════════════════
    fprintf('\n── E. Export section ──\n');

    sr.fireButton('Copy');
    sr.captureSnapshot('fv_07_export');

    % ════════════════════════════════════════════════════════════════════
    %  F. Multi-image operations
    % ════════════════════════════════════════════════════════════════════
    fprintf('\n── F. Multi-image ──\n');

    api.setActiveIdx(2); drawnow;
    sr.captureSnapshot('fv_08_image2');
    api.setActiveIdx(1); drawnow;

    % ════════════════════════════════════════════════════════════════════
    %  G. Keyboard shortcuts
    % ════════════════════════════════════════════════════════════════════
    fprintf('\n── G. Keyboard shortcuts ──\n');

    if ~isBatch
        sr.pressKey('r');
        sr.pressKey('f');
        sr.pressKey('h');
        sr.pressKey('h');
        sr.pressKey('i');
        sr.pressKey('i');
        sr.pressKey('bracketright');
        sr.pressKey('bracketleft');
        sr.pressKey('g');
        sr.pressKey('s');
        sr.pressKey('c');
    else
        fprintf('  SKIP  keyboard shortcuts (WindowKeyPressFcn empty in -batch)\n');
    end

    sr.captureSnapshot('fv_09_final');

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
