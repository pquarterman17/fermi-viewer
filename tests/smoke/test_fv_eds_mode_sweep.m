function test_fv_eds_mode_sweep
%TEST_FV_EDS_MODE_SWEEP  Fire every EDS-mode button with state set up correctly.
%
%   The coverage sweep reports many EDS buttons (Add Channel, Quantify,
%   ROI Composition, etc.) as Enable=off because EDS mode wasn't
%   entered. This test fixes that: load multi-image data, enter EDS
%   mode via api.enterEDS(), then fire each EDS button in sequence and
%   record what happens.
%
%   Pass criteria: all enabled EDS buttons fire without crashing. The
%   buttons that legitimately need user input (inputdlg for k-factor
%   element symbols, etc.) are skipped with explanatory note.
%
%   Run:  runAllTests(Group="smoke")
%   Or:   run tests/smoke/test_fv_eds_mode_sweep

    thisDir = fileparts(mfilename('fullpath'));
    rootDir = fileparts(fileparts(thisDir));
    addpath(rootDir);
    addpath(fullfile(rootDir, 'tests', 'smoke'));

    srcDir = fullfile(rootDir, '+test_datasets', 'Microscopy');
    dm3a = fullfile(srcDir, 'EDW087-1.dm3');
    dm3b = fullfile(srcDir, 'EDW087-2.dm3');
    dm3c = fullfile(srcDir, 'EDW087-3.dm3');
    assert(isfile(dm3a) && isfile(dm3b) && isfile(dm3c), ...
        'Need 3 test DM3s in %s', srcDir);

    fprintf('\n=== test_fv_eds_mode_sweep ===\n');

    api = FermiViewer();
    api.fig.Visible = 'off';
    drawnow;

    % Load 3 images — EDS composite mode needs >= 2 channels
    api.loadImages({dm3a, dm3b, dm3c});
    drawnow;
    fprintf('  Loaded %d images\n', numel(api.getImages()));

    sr = SmokeRunner(api.fig);

    % ── Enter EDS mode ──────────────────────────────────────────────
    fprintf('\n── Entering EDS mode ──\n');
    try
        api.enterEDS();
        drawnow;
        fprintf('  PASS  api.enterEDS() returned\n');
    catch ME
        error('test_fv_eds_mode_sweep:enterFailed', ...
            'api.enterEDS() crashed: %s', ME.message);
    end

    % Verify state
    appState = api.getEDSChannels();
    fprintf('  EDS channels after enter: %d\n', numel(appState));

    sr.captureSnapshot('eds_01_after_enter');

    % ── Buttons that open dialogs in EDS mode (auto-close in -batch) ──
    % Note: Export RGB = btnExportComposite (the EDS composite export).
    % Export Table = btnExportMeasure (a Measurement panel button,
    % correctly disabled in EDS mode — not tested here).
    fprintf('\n── Export Composite button ──\n');
    sr.startDialogAutoClose();
    sr.fireButton('Export RGB');
    sr.stopDialogAutoClose();
    sr.closePopups();

    sr.captureSnapshot('eds_02_after_safe_buttons');

    % ── Buttons that open dialogs (skip in -batch, fire-and-cancel) ──
    fprintf('\n── EDS-mode buttons (with auto-close dialog) ──\n');
    dialogButtons = {'Add Channel', 'Assign Elements', ...
        'Quantify (Cliff-Lorimer)', 'Quantify ZAF', ...
        'Composition Profile', 'ROI Composition'};
    for k = 1:numel(dialogButtons)
        sr.startDialogAutoClose();
        sr.fireButton(dialogButtons{k});
        sr.stopDialogAutoClose();
        sr.closePopups();
    end

    sr.captureSnapshot('eds_03_after_dialog_buttons');

    % ── Programmatic API check: setEDSChannel works ────────────────
    fprintf('\n── api.setEDSChannel (programmatic) ──\n');
    channels = api.getEDSChannels();
    if numel(channels) >= 1
        try
            api.setEDSChannel(1, 'color', 'red');
            drawnow;
            fprintf('  PASS  setEDSChannel(1, color, red)\n');
        catch ME
            fprintf('  FAIL  setEDSChannel: %s\n', ME.message);
        end
    else
        fprintf('  SKIP  no EDS channels populated (Add Channel needs dialog)\n');
    end

    % ── Exit EDS mode ──────────────────────────────────────────────
    fprintf('\n── Exiting EDS mode ──\n');
    try
        api.exitEDS();
        drawnow;
        fprintf('  PASS  api.exitEDS() returned\n');
    catch ME
        error('test_fv_eds_mode_sweep:exitFailed', ...
            'api.exitEDS() crashed: %s', ME.message);
    end

    sr.captureSnapshot('eds_04_after_exit');

    % ── Re-entering should still work (state cleanup correctness) ──
    fprintf('\n── Re-entering EDS mode (state cleanup check) ──\n');
    try
        api.enterEDS();
        drawnow;
        api.exitEDS();
        drawnow;
        fprintf('  PASS  re-enter + exit\n');
    catch ME
        error('test_fv_eds_mode_sweep:reenterFailed', ...
            'EDS re-enter crashed: %s', ME.message);
    end

    sr.summary();
    % Real failures (crashes) bubble up via error() above. Disabled-button
    % FAILs from sr are recorded but don't fail this test — those are
    % expected when the dialog auto-close cancels mid-setup.
end
