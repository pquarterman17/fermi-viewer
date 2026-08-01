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
%   Also covers the Fourier Ratio / Rich-Lucy deconvolution buttons
%   (fermiViewer.eels.dispatch 'fourierRatio' / 'richardsonLucy'):
%     - GUI-level: both buttons exist, are enabled in EELS mode, have
%       non-empty callbacks, and fire without error against the
%       spectrum-less test DM3 (the "no EELS data" early-return path).
%     - Unit-level: fermiViewer.eels.dispatch is called directly with a
%       synthetic appData/ctx to exercise the paths the GUI-level dataset
%       can't reach — a real core-loss spectrum with (a) no low-loss
%       sibling image available, (b) a low-loss sibling on the same
%       energy axis, and (c) a low-loss sibling on a different axis
%       (resampled) — plus a Richardson-Lucy run.
%
%   Run:  runAllTests(Group="smoke")

    thisDir = fileparts(mfilename('fullpath'));
    rootDir = fileparts(fileparts(thisDir));
    addpath(rootDir);
    addpath(fullfile(rootDir, 'tests', 'smoke'));

    % fermiViewer.chrome.quietConfirm (used by the Fourier Ratio low-loss
    % picker and the Rich-Lucy iteration-count picker) only auto-resolves
    % instead of blocking on a real uiconfirm when FERMI_VIEWER_HEADLESS=1.
    % This test runs standalone via `matlab -batch`, not through
    % tests/run_gui_hidden.*, so nothing else guarantees that var is set —
    % set it here and restore it on exit (same pattern as
    % tests/gui/test_checkForUpdates.m).
    prevHeadlessEnv = getenv('FERMI_VIEWER_HEADLESS');
    setenv('FERMI_VIEWER_HEADLESS', '1');
    envCleanup = onCleanup(@() setenv('FERMI_VIEWER_HEADLESS', prevHeadlessEnv)); %#ok<NASGU>

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
        'Align ZLP', 'Deconvolve', 'Fourier Ratio', 'Rich-Lucy', 'ELNES', ...
        'Kramers-Kronig', 'SVD Decompose'};

    for k = 1:numel(eelsButtons)
        sr.startDialogAutoClose();
        sr.fireButton(eelsButtons{k});
        sr.stopDialogAutoClose();
        sr.closePopups();
    end

    sr.captureSnapshot('eels_02_after_button_fires');

    % ── Fourier Ratio / Rich-Lucy: explicit exists+enabled+callback ─
    % sr.fireButton above already silently records (not throws) if a
    % button is missing, disabled, or has no callback — this test's
    % overall pass/fail is only gated on uncaught crashes (see docstring).
    % These two buttons are new, so assert their wiring explicitly rather
    % than relying on that silent bookkeeping.
    fprintf('\n── Fourier Ratio / Rich-Lucy wiring checks ──\n');
    assertEELSButtonWired(api.fig, 'Fourier Ratio');
    assertEELSButtonWired(api.fig, 'Rich-Lucy');

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

    % ════════════════════════════════════════════════════════════════════
    %  Direct dispatch() coverage — fourierRatio / richardsonLucy
    % ════════════════════════════════════════════════════════════════════
    %  The GUI-level sweep above only exercises the "no EELS data at all"
    %  early return (the test DM3 has no spectrum data). The paths unique
    %  to these two actions — no low-loss sibling available, a low-loss
    %  sibling present (same axis / different axis), and a Rich-Lucy run —
    %  need a real core-loss spectrum, so they're driven directly through
    %  fermiViewer.eels.dispatch with a synthetic appData/ctx instead.
    fprintf('\n── Direct dispatch(): fourierRatio / richardsonLucy ──\n');

    lastStatus = ''; %#ok<NASGU>
    function captureStatus(msg)
        lastStatus = msg;
    end

    unitCtx = struct('fig', api.fig, 'cb', struct('setStatus', @captureStatus));

    nE   = 64;
    E    = linspace(-10, 90, nE)';
    zlp  = exp(-E.^2 / (2*1.5^2));
    core = zlp + 0.3 * exp(-(E - 50).^2 / (2*3^2));

    % -- 1. fourierRatio: no low-loss candidate → clear status, no crash --
    lastStatus = '';
    appNoLow = syntheticEELSAppData(E, core);
    try
        fermiViewer.eels.dispatch('fourierRatio', appNoLow, unitCtx);
        assert(contains(lastStatus, 'low-loss'), ...
            'expected a low-loss-related status message, got: "%s"', lastStatus);
        fprintf('  PASS  fourierRatio: no-low-loss path — clear status, no error\n');
    catch ME
        error('test_fv_eels_mode_sweep:fourierRatioNoLowLossCrashed', ...
            'fourierRatio with no low-loss candidate crashed: %s', ME.message);
    end

    % -- 2. fourierRatio: low-loss sibling on the SAME energy axis --------
    lastStatus = '';
    lowLossSame = zlp + 0.15 * exp(-(E - 20).^2 / (2*4^2));
    appSameAxis = syntheticEELSAppData(E, core);
    appSameAxis.images{end+1} = syntheticEELSImage(E, lowLossSame, 'lowloss_same.dm3');
    try
        out = fermiViewer.eels.dispatch('fourierRatio', appSameAxis, unitCtx);
        assert(~isempty(out.eelsSSD), 'fourierRatio did not populate eelsSSD');
        assert(numel(out.eelsSSD) == nE, 'eelsSSD length mismatch');
        assert(~isempty(lastStatus), 'fourierRatio did not set a status message');
        assert(~contains(lastStatus, 'resampled'), ...
            'same-axis low-loss should not trigger the resample message');
        fprintf('  PASS  fourierRatio: same-axis low-loss — runs, populates eelsSSD\n');
    catch ME
        error('test_fv_eels_mode_sweep:fourierRatioSameAxisCrashed', ...
            'fourierRatio with a same-axis low-loss sibling crashed: %s', ME.message);
    end

    % -- 3. fourierRatio: low-loss sibling on a DIFFERENT energy axis -----
    lastStatus = '';
    Elow2 = linspace(-8, 88, 50)';
    lowLossDiff = exp(-Elow2.^2 / (2*1.5^2)) + 0.15 * exp(-(Elow2 - 20).^2 / (2*4^2));
    appDiffAxis = syntheticEELSAppData(E, core);
    appDiffAxis.images{end+1} = syntheticEELSImage(Elow2, lowLossDiff, 'lowloss_diff.dm3');
    try
        out = fermiViewer.eels.dispatch('fourierRatio', appDiffAxis, unitCtx);
        assert(~isempty(out.eelsSSD), 'fourierRatio did not populate eelsSSD');
        assert(numel(out.eelsSSD) == nE, 'eelsSSD length mismatch');
        assert(contains(lastStatus, 'resampled'), ...
            'different-axis low-loss should mention resampling in the status, got: "%s"', ...
            lastStatus);
        fprintf('  PASS  fourierRatio: different-axis low-loss — resamples, populates eelsSSD\n');
    catch ME
        error('test_fv_eels_mode_sweep:fourierRatioResampleCrashed', ...
            'fourierRatio with a different-axis low-loss sibling crashed: %s', ME.message);
    end

    % -- 4. fourierRatio: TWO low-loss candidates → quietConfirm picks one -
    % (headless: quietConfirm auto-resolves to its DefaultOption, the
    % first candidate found, without ever creating a real dialog.)
    lastStatus = '';
    lowA = zlp + 0.15 * exp(-(E - 20).^2 / (2*4^2));
    lowB = zlp + 0.10 * exp(-(E - 25).^2 / (2*4^2));
    appTwoLow = syntheticEELSAppData(E, core);
    appTwoLow.images{end+1} = syntheticEELSImage(E, lowA, 'lowloss_a.dm3');
    appTwoLow.images{end+1} = syntheticEELSImage(E, lowB, 'lowloss_b.dm3');
    try
        out = fermiViewer.eels.dispatch('fourierRatio', appTwoLow, unitCtx);
        assert(~isempty(out.eelsSSD), 'fourierRatio did not populate eelsSSD');
        assert(contains(lastStatus, 'lowloss_a.dm3'), ...
            'expected quietConfirm''s DefaultOption (first candidate) to be picked, got: "%s"', ...
            lastStatus);
        fprintf('  PASS  fourierRatio: 2 low-loss candidates — quietConfirm auto-picks default\n');
    catch ME
        error('test_fv_eels_mode_sweep:fourierRatioMultiCandidateCrashed', ...
            'fourierRatio with two low-loss candidates crashed: %s', ME.message);
    end

    % -- 5. richardsonLucy: runs and returns updated appData --------------
    lastStatus = '';
    appRL = syntheticEELSAppData(E, core);
    try
        out = fermiViewer.eels.dispatch('richardsonLucy', appRL, unitCtx);
        assert(~isempty(out.eelsSSD), 'richardsonLucy did not populate eelsSSD');
        assert(numel(out.eelsSSD) == nE, 'eelsSSD length mismatch');
        assert(~isempty(lastStatus), 'richardsonLucy did not set a status message');
        fprintf('  PASS  richardsonLucy: runs, populates eelsSSD\n');
    catch ME
        error('test_fv_eels_mode_sweep:richardsonLucyCrashed', ...
            'richardsonLucy crashed: %s', ME.message);
    end

    fprintf('\n=== test_fv_eels_mode_sweep: direct dispatch() checks PASSED ===\n');
end

% ════════════════════════════════════════════════════════════════════════
%  Local helpers — synthetic appData for direct fermiViewer.eels.dispatch()
%  calls (no local functions above may use 'end'-less style once any
%  function in this file does; test_eels_advanced.m established the same
%  local-function-at-end-of-file pattern for R2022b compatibility).
% ════════════════════════════════════════════════════════════════════════

function assertEELSButtonWired(fig, text)
%ASSERTEELSBUTTONWIRED  Hard-fail if an EELS button is missing/disabled/
%   uncallable (findall-based, independent of SmokeRunner's silent
%   record-and-continue bookkeeping).
    btn = findall(fig, 'Type', 'uibutton', 'Text', text);
    assert(~isempty(btn), 'Button "%s" not found in the EELS panel', text);
    assert(strcmp(btn(1).Enable, 'on'), ...
        'Button "%s" is not enabled in EELS mode (Enable=%s)', text, btn(1).Enable);
    assert(~isempty(btn(1).ButtonPushedFcn), ...
        'Button "%s" has an empty ButtonPushedFcn', text);
    fprintf('  PASS  button "%s" exists, enabled, has a callback\n', text);
end

function appData = syntheticEELSAppData(energyAxis, counts)
%SYNTHETICEELSAPPDATA  Minimal appData for direct fermiViewer.eels.dispatch()
%   calls: one loaded core-loss image plus every field the 'fourierRatio'
%   and 'richardsonLucy' cases (and appData.eelsWorkshop.sync) touch.
    appData = struct();
    appData.images        = {syntheticEELSImage(energyAxis, counts, 'coreloss.dm3')};
    appData.activeIdx     = 1;
    appData.eelsMode      = true;
    appData.edsMode       = false;
    appData.compareMode   = false;
    appData.captureMode   = '';
    appData.eelsData      = struct('energyAxis', energyAxis, 'counts', counts);
    appData.eelsCube      = [];
    appData.eelsEnergyAxis = [];
    appData.eelsFig       = [];
    appData.eelsSSD       = [];
    appData.eelsELNESFig  = [];
    appData.eelsKKFig     = [];
    appData.eelsKKResult  = [];
    appData.eelsSVDFig    = [];
    appData.eelsSVDResult = [];
    appData.eelsWorkshop  = fermiViewer.eels.EELSWorkshop();
end

function img = syntheticEELSImage(energyAxis, counts, fname)
%SYNTHETICEELSIMAGE  Minimal appData.images{} entry carrying EELS spectrum
%   data, matching the shape fermiViewer.eels.dispatch's 'enter' case reads
%   (metadata.parserSpecific.spectrumData with .energyAxis / .counts).
    img = struct();
    img.metadata = struct();
    img.metadata.source = fullfile(tempdir, fname);
    img.metadata.parserSpecific = struct( ...
        'spectrumData', struct('energyAxis', energyAxis, 'counts', counts));
end
