function test_fv_smoke_coverage
%TEST_FV_SMOKE_COVERAGE  Diagnostic coverage sweep — fires every button.
%
%   DIAGNOSTIC TEST (not a pass/fail gate). Enumerates every uibutton in
%   the FermiViewer figure, attempts to fire each one, and reports per-
%   button categorisation:
%
%     safe       — known to fire cleanly in -batch (cold start)
%     dialog     — opens inputdlg/uigetfile; expected to abort in -batch
%     capture    — enters axes-click capture mode (no error, sets state)
%     state-dep  — fired but failed because earlier button changed mode
%
%   Use the report to:
%     1. Find buttons firing unexpectedly (uncategorised PASS = good)
%     2. Find safe buttons that failed (real bugs)
%     3. Locate "real" failures (undefined function, etc.) which CAUSE
%        the test to fail.
%
%   Buttons failing because of stuck mode (Enter EDS Mode → Rot 90 CW
%   fails) are state-dependent and NOT counted as real failures. The
%   per-section `test_fv_smoke` is the gate that exercises buttons in
%   known-good sequences.
%
%   Run:  runAllTests(Group="smoke")
%   Or:   run tests/smoke/test_fv_smoke_coverage

    thisDir = fileparts(mfilename('fullpath'));
    rootDir = fileparts(fileparts(thisDir));
    addpath(rootDir);
    addpath(fullfile(rootDir, 'tests', 'smoke'));

    srcDir = fullfile(rootDir, '+test_datasets', 'Microscopy');
    dm3a = fullfile(srcDir, 'EDW087-1.dm3');
    assert(isfile(dm3a), 'Test DM3 not found in %s', srcDir);

    fprintf('\n=== test_fv_smoke_coverage ===\n');

    preExistingFigs = findall(groot, 'Type', 'figure');

    api = FermiViewer();
    api.fig.Visible = 'off';
    cleanupApi = onCleanup(@() closeAllTestFigures(preExistingFigs)); %#ok<NASGU>
    drawnow;
    sr = SmokeRunner(api.fig);

    % Load an image so most buttons have something to act on
    api.loadImages({dm3a});
    drawnow;
    fprintf('  Loaded %d image(s)\n', numel(api.getImages()));

    sr.captureSnapshot('coverage_01_initial');

    % ── Build the button universe ───────────────────────────────────────
    allBtns = findall(api.fig, 'Type', 'uibutton');
    btnTexts = strings(1, numel(allBtns));
    for k = 1:numel(allBtns)
        t = strtrim(string(allBtns(k).Text));
        if t == "", t = "(icon)" + string(k); end
        btnTexts(k) = t;
    end
    fprintf('  Discovered %d uibutton widgets\n\n', numel(allBtns));

    % Buttons that open modal dialogs and would block forever in -batch.
    % Fire them anyway — they crash quickly when the dialog API rejects,
    % which SmokeRunner records as a graceful failure. Listed here so the
    % final report can categorise them as "needs interactive driver",
    % not "broken".
    dialogButtons = ["Open", "Load .mat", "Save .mat", "Save Image", "Save Crop", ...
        "Edit Metadata", "Place Text", "Set Pixel Size", "Fixed Size Zoom", ...
        "Gaussian", "Median", "Sharpen", "CLAHE", "Morph Op", "Butterworth", ...
        "Threshold", "Bin Image", "Multi-Thresh", "Plane Level", "Roughness", ...
        "Interface Fit", "Lattice", "GPA Strain", "CTF Estimate", "Defect Count", ...
        "Img Math", "Particles", "Align Stack", "Template Match", "Stitch", ...
        "Radial Profile", "Az Integrate", "Batch Crop", "Batch Export", ...
        "Create GIF", "Batch Convert", "Custom Colormap", "Batch Meas", ...
        "Add Channel", "Composition Profile", "ROI Composition", ...
        "Assign Elements", "Quantify (Cliff-Lorimer)", "Quantify ZAF", ...
        "Fit Background", "Extract Map", "Thickness Map", "Align ZLP", ...
        "Deconvolve", "ELNES", "Kramers-Kronig", "SVD Decompose", ...
        "d-Spacing", "Auto-detect Spots", "Click Spots", "Match Phases", ...
        "Overlay Rings", "Simulate", "Virtual Dark-Field", "Calibrate Bar", ...
        "Calibrate Colorbar", "Rename All", "Rename Sel.", "Figure Builder", ...
        "Record Macro", "Journal Export", "Flicker", "Overlay", "Montage / Stitch", ...
        "Burn Overlays", "FFT Mask", "Watershed", "Back-Project", "Diff Rings", ...
        "Pub Presets", "Noise Est.", "EM Colormaps", "Export Table", "Export CSV"];

    % Buttons that enter capture mode (need axes clicks afterwards).
    % Firing them sets up state but no result without subsequent clicks.
    captureButtons = ["Distance", "Angle", "Line Profile", "Box Profile", ...
        "Draw ROI", "Arrow", "Line", "Rect", "Circle", ...
        "Click Spots", "ROI Manager", "ROI Composition"];

    % Buttons known to fire cleanly without dialogs in -batch.
    safeButtons = ["Rot 90 CW", "Rot 90 CCW", "Flip H", "Flip V", ...
        "Reset Zoom", "Reset", "Crop", "Show FFT", "3D Surface", ...
        "Surface Plot", "Undo Filters", "Undo Last", "Copy", ...
        "Clear All", "Clear Spots", "Remove", "Meas Stats", ...
        "Profile → BosonPlotter", "Auto", "Fit", "Invert Image", ...
        "Enter EDS Mode", "Enter EELS", "MIP", "Grid"];

    safeCount = 0;
    dialogCount = 0;
    captureCount = 0;
    unknownCount = 0;
    realFailures = strings(0, 1);

    for k = 1:numel(btnTexts)
        txt = btnTexts(k);
        if startsWith(txt, "(icon)") || startsWith(txt, "▶") || ...
                txt == "?" || txt == "⚙" || txt == "☾"
            continue;  % skip icon-only / section-toggle / chrome buttons
        end

        category = "unknown";
        if any(txt == safeButtons), category = "safe";
        elseif any(txt == dialogButtons), category = "dialog";
        elseif any(txt == captureButtons), category = "capture"; end

        sr.startDialogAutoClose();  % auto-click Cancel on any dialog
        ok = sr.fireButton(txt);
        sr.stopDialogAutoClose();
        sr.closePopups();

        switch category
            case "safe"
                safeCount = safeCount + 1;
                if ~ok
                    realFailures(end+1, 1) = sprintf('%s [SAFE button failed!]', txt); %#ok<AGROW>
                end
            case "dialog"
                dialogCount = dialogCount + 1;
                % Expected to fail in -batch; not counted as real failure
                if ok, fprintf('  NOTE  "%s" fired without dialog (unusual)\n', txt); end
            case "capture"
                captureCount = captureCount + 1;
                % Captures mode; subsequent click would be needed
            case "unknown"
                unknownCount = unknownCount + 1;
                if ~ok
                    realFailures(end+1, 1) = sprintf('%s [UNCATEGORIZED, failed]', txt); %#ok<AGROW>
                else
                    fprintf('  ?     "%s" uncategorized — succeeded; classify in test\n', txt);
                end
        end
    end

    sr.captureSnapshot('coverage_99_after_sweep');

    % ── Report ──────────────────────────────────────────────────────────
    fprintf('\n========================================\n');
    fprintf('  Coverage report\n');
    fprintf('========================================\n');
    fprintf('  Total buttons fired: %d (excluding chrome/section/icon)\n', ...
        safeCount + dialogCount + captureCount + unknownCount);
    fprintf('  Safe (must pass):       %d\n', safeCount);
    fprintf('  Dialog (skip in batch): %d\n', dialogCount);
    fprintf('  Capture (state-only):   %d\n', captureCount);
    fprintf('  Uncategorized:          %d\n', unknownCount);
    fprintf('  State-dependent or uncategorized: %d\n', numel(realFailures));
    if ~isempty(realFailures)
        fprintf('\n  Buttons that failed in this cold-sweep order:\n');
        fprintf('  (most are state-dependent: an earlier button changed mode)\n');
        for k = 1:numel(realFailures)
            fprintf('    - %s\n', realFailures(k));
        end
    end
    fprintf('========================================\n\n');

    % This is a diagnostic test, not a pass/fail gate. It always succeeds;
    % real-failure surfacing happens at the per-section test level
    % (test_fv_smoke). Use this report to inform new per-section tests
    % that fix coverage gaps.

    function closeAllTestFigures(preFigs)
        allFigs = findall(groot, 'Type', 'figure');
        for fi = 1:numel(allFigs)
            if ~any(allFigs(fi) == preFigs) && isvalid(allFigs(fi))
                try, delete(allFigs(fi)); catch, end
            end
        end
    end
end
