function test_fv_eels_mode_sweep
%TEST_FV_EELS_MODE_SWEEP  Fire every EELS-mode button after entering EELS.
%
%   EELS buttons unlike EDS are unconditionally enabled by
%   setToolsEnabled when an image is loaded — so the EDS-style
%   enable-race bug doesn't apply here. The hunt here is for CRASH
%   bugs: buttons that crash when fired even though they look enabled.
%
%   Note: most EELS analysis requires actual EELS data (spectrum or
%   spectrum image) in the loaded file. The test DM3s in
%   +test_datasets/Microscopy don't have spectrum data, so EELS
%   buttons may correctly report "no EELS data" rather than crash.
%   That's acceptable. Only uncaught crashes fail the test.
%
%   Run:  runAllTests(Group="smoke")

    thisDir = fileparts(mfilename('fullpath'));
    rootDir = fileparts(fileparts(thisDir));
    addpath(rootDir);
    addpath(fullfile(rootDir, 'tests', 'smoke'));

    srcDir = fullfile(rootDir, '+test_datasets', 'Microscopy');
    dm3Path = fullfile(srcDir, 'EDW087-1.dm3');
    assert(isfile(dm3Path), 'Test DM3 not found in %s', srcDir);

    fprintf('\n=== test_fv_eels_mode_sweep ===\n');

    api = FermiViewer();
    api.fig.Visible = 'off';
    drawnow;

    api.loadImages({dm3Path});
    drawnow;

    sr = SmokeRunner(api.fig);

    % ── Enter EELS mode ──────────────────────────────────────────────
    fprintf('\n── Entering EELS mode ──\n');
    try
        api.enterEELS();
        drawnow;
        fprintf('  PASS  api.enterEELS() returned\n');
    catch ME
        error('test_fv_eels_mode_sweep:enterFailed', ...
            'api.enterEELS() crashed: %s', ME.message);
    end

    sr.captureSnapshot('eels_01_after_enter');

    % ── Fire EELS buttons ──────────────────────────────────────────
    fprintf('\n── EELS-mode buttons ──\n');
    eelsButtons = {'Fit Background', 'Extract Map', 'Thickness Map', ...
        'Align ZLP', 'Deconvolve', 'ELNES', 'Kramers-Kronig', 'SVD Decompose'};

    for k = 1:numel(eelsButtons)
        sr.startDialogAutoClose();
        sr.fireButton(eelsButtons{k});
        sr.stopDialogAutoClose();
        sr.closePopups();
    end

    sr.captureSnapshot('eels_02_after_button_fires');

    % ── Exit EELS mode ──────────────────────────────────────────────
    fprintf('\n── Exiting EELS mode ──\n');
    try
        api.exitEELS();
        drawnow;
        fprintf('  PASS  api.exitEELS() returned\n');
    catch ME
        error('test_fv_eels_mode_sweep:exitFailed', ...
            'api.exitEELS() crashed: %s', ME.message);
    end

    sr.captureSnapshot('eels_03_after_exit');

    % ── Re-enter cycle (state cleanup) ─────────────────────────────
    fprintf('\n── Re-entering EELS mode ──\n');
    try
        api.enterEELS();
        drawnow;
        api.exitEELS();
        drawnow;
        fprintf('  PASS  re-enter + exit\n');
    catch ME
        error('test_fv_eels_mode_sweep:reenterFailed', ...
            'EELS re-enter crashed: %s', ME.message);
    end

    sr.summary();
end
