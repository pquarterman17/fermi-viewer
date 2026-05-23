function test_fv_diffraction_mode_sweep
%TEST_FV_DIFFRACTION_MODE_SWEEP  Fire every Diffraction-section button.
%
%   Diffraction buttons don't have a mode-entry pattern like EDS/EELS —
%   they operate directly on the FFT or diffraction pattern of the
%   loaded image. This test loads a real DM3, fires each Diffraction
%   button, and verifies none crash.
%
%   Many of these buttons compute on the active image's FFT, which we
%   trigger first via Show FFT. Some need interactive picking (Click
%   Spots) which won't fire in -batch but won't crash either.
%
%   Run:  runAllTests(Group="smoke")

    thisDir = fileparts(mfilename('fullpath'));
    rootDir = fileparts(fileparts(thisDir));
    addpath(rootDir);
    addpath(fullfile(rootDir, 'tests', 'smoke'));

    srcDir = fullfile(rootDir, '+test_datasets', 'Microscopy');
    dm3Path = fullfile(srcDir, 'EDW087-1.dm3');
    assert(isfile(dm3Path), 'Test DM3 not found in %s', srcDir);

    fprintf('\n=== test_fv_diffraction_mode_sweep ===\n');

    api = FermiViewer();
    api.fig.Visible = 'off';
    drawnow;

    api.loadImages({dm3Path});
    drawnow;

    sr = SmokeRunner(api.fig);

    % ── Compute FFT first (most diffraction buttons need it) ──────
    fprintf('\n── Compute FFT ──\n');
    sr.startDialogAutoClose();
    sr.fireButton('Show FFT');
    sr.stopDialogAutoClose();
    sr.closePopups();
    drawnow;

    sr.captureSnapshot('diff_01_after_fft');

    % ── Fire diffraction buttons ──────────────────────────────────
    fprintf('\n── Diffraction buttons ──\n');
    diffButtons = {'Auto-detect Spots', 'Clear Spots', ...
        'Match Phases', 'Overlay Rings', 'Diff Rings', 'Simulate', ...
        'Virtual Dark-Field', 'd-Spacing'};

    for k = 1:numel(diffButtons)
        sr.startDialogAutoClose();
        sr.fireButton(diffButtons{k});
        sr.stopDialogAutoClose();
        sr.closePopups();
    end

    sr.captureSnapshot('diff_02_after_button_fires');

    sr.summary();
end
