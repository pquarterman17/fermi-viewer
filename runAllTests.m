function runAllTests(options)
%RUNALLTESTS  Run the complete FermiViewer test suite and print a summary.
%
%   Syntax:
%       runAllTests
%       runAllTests(Group="fv")
%
%   Name-Value Options:
%       Group       "all" (default) | "fast" | "fv" | "fvgui" | "parser" |
%                   "gui" | "smoke" | "interactive" | "eds" | "eels" |
%                   "eels_adv" | "diffindex" | "diff_sim" | "edsquant" |
%                   "contour" | "spectral"
%       MaxSeconds  scalar double, default Inf. Per-test wall-clock budget
%                   (NOT per-suite). If any single test exceeds this many
%                   seconds, its execution is allowed to finish (MATLAB
%                   can't kill a running script from outside) but the test
%                   is recorded as TIMEOUT and surfaced in the final
%                   summary. Use this to identify long-running tests when
%                   debugging "is the suite hung or just slow?".
%
%   Groups:
%       fast        — curated subset that completes in <30s. Use this for
%                     post-change sanity checks before running the full
%                     suite. Excludes anything that loads real DM3 files,
%                     opens many panels, or exercises full GUI workflows.
%       parser      — EM parser smoke tests (importBCF, importDM3, ...)
%       fv          — EM image parsers + imaging utilities (synthetic data, fast)
%       fvgui       — headless FermiViewer GUI API tests
%       gui         — annotation/measurement widget tests (small, headless)
%       smoke       — headless interaction sweeps with real image data
%       interactive — *opt-in* visible-figure smoke tests with pauses for
%                     human observation. Not run by default (pointless in
%                     -batch). Use this from a real MATLAB session to
%                     watch FermiViewer click through every button.
%       eds         — EDS multi-channel composite mode tests
%       eels        — EELS imaging utilities (synthetic data)
%       eels_adv    — advanced EELS: Fourier-log, ELNES, Kramers-Kronig
%       diffindex   — diffraction indexing utilities
%       diff_sim    — diffraction simulation, virtual dark-field, ZAF
%       edsquant    — EDS quantification (k-factor table, Cliff-Lorimer)
%       contour     — contour / ring overlay tests
%       spectral    — shared spectral utilities
%       all         — every group above EXCEPT 'interactive', in order
%
%   Examples:
%       runAllTests                            % full headless suite (default)
%       runAllTests(Group="fast")              % <30s smoke check
%       runAllTests(Group="fv")                % EM parser + imaging only
%       runAllTests(Group="fvgui")             % FermiViewer GUI API
%       runAllTests(MaxSeconds=60)             % flag any test > 60s
%       runAllTests(Group="interactive")       % opt-in visible smoke
%
%   Final summary prints sorted-by-duration ranking so it's obvious
%   which tests are slow.
%
%   Throws an error if any suite fails so CI/scripts can detect failures.

arguments
    options.Group string = "all"
    options.MaxSeconds (1,1) double = Inf
end

options.Group = validatestring(options.Group, ...
    ["all", "fast", "parser", "fv", "fvgui", "gui", "smoke", "interactive", ...
     "eds", "eels", "eels_adv", "diffindex", "diff_sim", ...
     "edsquant", "contour", "spectral"]);

% 'fast' group: hand-picked subset (~30s total). These are tests that
% don't load real DM3 files or open many panels. Useful for post-change
% sanity checks before running the full ~10-minute suite.
fastTests = ["test_importBCF", "test_fv_parsers", "test_imaging_utils", ...
    "test_measurementWorkshopModel", "test_measurementWorkshop", ...
    "test_diffractionWorkshop", "test_contrastWorkshop", ...
    "test_annotationWorkshop", "test_eelsWorkshop", "test_edsWorkshop", ...
    "test_processingWorkshop", "test_calibrationWorkshop", ...
    "test_fermiViewerSize", "test_smokeRunner", "test_fv_capture_modes"];

ROOT  = fileparts(mfilename('fullpath'));
T     = @(subdir, name) fullfile(ROOT, 'tests', subdir, name);

SUITES = {
    T('parser','test_importBCF'),                       'parser', 'BCF EDS spectrum parser'
    T('imaging','test_renderingSharpness'),             'fv',     'FermiViewer display pipeline: sharpness/variance preservation regression'
    T('imaging','test_fv_parsers'),                     'fv',     'EM image parsers: importTIFF + importRawImage'
    T('imaging','test_imaging_utils'),                  'fv',     'Imaging utilities: contrast, filter, FFT, profile, scale bar, thumbnail'
    T('imaging','test_imaging_advanced'),               'fv',     'Imaging advanced: bin, unsharp, morph, Otsu, Butterworth, plane level, roughness, lattice, radial, azimuthal, interface fit, stitch, defect count'
    T('imaging','test_tiltCorrection'),                 'fv',     'SEM/FIB stage tilt: getStageTilt parsing, measureDistance/lineProfile with TiltAngle'
    T('imaging','test_tiltGeometryCorrection'),         'fv',     'Tilt geometry: Surface (1/cos) vs Cross-section (1/sin) correction factors'
    T('imaging','test_particle_clahe'),                 'fv',     'Imaging: CLAHE + connectedComponents + particleAnalysis (synthetic + real DM3/DM4)'
    T('imaging','test_measurementWorkshopModel'),       'fv',     'MeasurementWorkshopModel: handle-class state container (workshop pattern)'
    T('imaging','test_measurementWorkshop'),            'fv',     'MeasurementWorkshop facade: hook contract + bind/select/clear lifecycle'
    T('imaging','test_diffractionWorkshop'),            'fv',     'DiffractionWorkshop: model + facade for spot detection, indexing, GPA state'
    T('imaging','test_contrastWorkshop'),               'fv',     'ContrastWorkshop: model + facade for contrast limits, transform, gamma, invert'
    T('imaging','test_annotationWorkshop'),             'fv',     'AnnotationWorkshop: model + facade for text annotations CRUD, sync, selection'
    T('imaging','test_eelsWorkshop'),                   'fv',     'EELSWorkshop: model + facade for EELS state, spectrum, cube, analysis results'
    T('imaging','test_edsWorkshop'),                    'fv',     'EDSWorkshop: model + facade for EDS channels, composite, quantification'
    T('imaging','test_processingWorkshop'),             'fv',     'ProcessingWorkshop: model + facade for FFT/Particle/Align state'
    T('imaging','test_calibrationWorkshop'),            'fv',     'CalibrationWorkshop: model + facade for pixel calibration, scale bar'

    T('imaging','test_fv_gui_harness'),                 'fvgui',  'FermiViewer GUI API: load, contrast, filter, FFT, profile, export'
    T('imaging','test_fv_gui_phase2'),                  'fvgui',  'FermiViewer Phase 2: stack nav, session, compare, EDS, EELS, diffraction, annotations'
    T('imaging','test_fv_measurements'),                'fvgui',  'FermiViewer measurement/ROI API: measureDistance, dSpacing, ellipse/polygon ROI, annotRect'
    T('imaging','test_fv_contrast_stack'),              'fvgui',  'FermiViewer contrast stack API: reset, colormap set/cycle, transform, invert, colorbar'
    T('imaging','test_fv_advanced_api'),                'fvgui',  'FermiViewer advanced API: virtualDarkField, eelsDeconvolve, eelsKramersKronig'
    T('imaging','test_fv_priority3'),                   'fvgui',  'FermiViewer Priority-3 click-capture bypass: cropRect, zoomRect, resetZoom, fftMask'
    T('imaging','test_fv_gui_real_dm'),                 'fvgui',  'FermiViewer driven by real DM3/DM4 files: per-file load + full button sweep'
    T('imaging','test_fv_gui_button_wiring'),           'fvgui',  'FermiViewer Processing-panel button wiring: every control present, enabled, callback set'
    T('imaging','test_fv_angle_polyline_export'),       'fvgui',  'FermiViewer measurement API: angle (90°/45°/135°), polyline path length, CSV export round-trip'
    T('imaging','test_scaleBarPersistsThroughProcessing'),'fvgui','FermiViewer scale bar: persists across filters, rotate/flip, crop, and undo (regression)'
    T('imaging','test_transformToolbar'),               'fvgui',  'FermiViewer icon transform toolbar: rotate/flip/zoom/fit/reset/crop wiring + capital-T geometry'
    T('imaging','test_fv_clear_overlays_diff_rings'),   'fvgui',  'FermiViewer Clear Overlays removes diff_ring + diff_spot tagged handles (regression)'
    T('imaging','test_fermiViewerSize'),                'fvgui',  'Size ratchet: FermiViewer.m line count + nested-fn count stay under their ceilings'
    T('imaging','test_fv_box_profile'),                 'fvgui',  'FermiViewer Box Profile: rotated-box overlay + width-averaged profile + clearOverlays cleanup'
    T('imaging','test_fv_zoom_toggle_marquee'),         'fvgui',  'FermiViewer zoom toggle + marquee selection'
    T('imaging','test_fv_rect_roi_polyline'),           'fvgui',  'FermiViewer rect ROI + polyline interaction'

    T('gui','test_annotationColorDropdown'),            'gui',    'FermiViewer annotation-colour dropdown: items, default, 5-way RGB lookup'
    T('gui','test_measurementLabelDefaults'),           'fvgui',  'FermiViewer distance label defaults: font size, transparent background, perpendicular offset, tilt tooltip'

    T('smoke','test_smokeRunner'),                      'smoke',  'SmokeRunner framework self-test: button/dropdown/keypress/sequence + snapshot capture'
    T('smoke','test_fv_smoke'),                         'smoke',  'FermiViewer smoke: fire every button + interaction sequences with real image'
    T('smoke','test_fv_smoke_coverage'),                'smoke',  'FermiViewer coverage sweep: fires every button, categorised (safe/dialog/capture), reports real failures'
    T('smoke','test_fv_capture_modes'),                 'smoke',  'Verify every measurement/annotation button enters its expected capture mode (button-fire wiring)'

    % ── Interactive (opt-in, visible figure, requires real MATLAB session) ──
    T('smoke','test_fv_smoke_interactive'),             'interactive', 'Visible-figure smoke test: paced + Visible=on for human observation'
    T('smoke','test_fv_capture_interactive'),           'interactive', 'Visible capture-mode test: watch status bar + cursor for each measurement button'
};

% Filter suites by group.
% The 'interactive' group is opt-in: requires the user to call
% runAllTests(Group="interactive") explicitly. Default Group="all" runs
% everything *except* interactive (those tests show the figure with
% Visible='on' and pace themselves with pause() so a human can watch —
% pointless in -batch mode where nothing is rendered).
if options.Group == "fast"
    % Filter by basename matching the fastTests list
    keep = false(size(SUITES, 1), 1);
    for k = 1:size(SUITES, 1)
        [~, baseName] = fileparts(SUITES{k, 1});
        if any(strcmp(baseName, fastTests))
            keep(k) = true;
        end
    end
    SUITES = SUITES(keep, :);
elseif options.Group == "all"
    keep = ~strcmp(SUITES(:,2), 'interactive');
    SUITES = SUITES(keep, :);
else
    keep = strcmp(SUITES(:,2), options.Group);
    SUITES = SUITES(keep, :);
    if isempty(SUITES)
        fprintf('No test suites in group "%s".\n', options.Group);
        return
    end
end

nSuites = size(SUITES, 1);
results = repmat(struct('name','','passed',false,'time',0,'error',''), nSuites, 1);

fprintf('\n========================================\n');
fprintf('FermiViewer test suite — %d suites\n', nSuites);
if isfinite(options.MaxSeconds)
    fprintf('Per-test budget: %.0fs (slow tests will be flagged TIMEOUT)\n', options.MaxSeconds);
end
fprintf('========================================\n\n');

for k = 1:nSuites
    results(k) = runOneSuite(SUITES{k, 1}, SUITES{k, 3}, options.MaxSeconds);
end

% Summary
nPassed = sum([results.passed]);
nFailed = nSuites - nPassed;
nTimeout = sum(arrayfun(@(r) ~isempty(r.error) && contains(r.error, 'TIMEOUT'), results));
totalTime = sum([results.time]);

fprintf('========================================\n');
fprintf('Summary: %d/%d passed (%.1fs total)', nPassed, nSuites, totalTime);
if nTimeout > 0
    fprintf(', %d TIMEOUT', nTimeout);
end
fprintf('\n========================================\n');

% Sorted-by-duration ranking: surfaces slow tests so users know which to
% target for optimisation or exclude with Group="fast".
if nSuites > 1
    times = [results.time];
    [~, idx] = sort(times, 'descend');
    nTop = min(5, nSuites);
    fprintf('\nSlowest %d test(s):\n', nTop);
    for k = 1:nTop
        r = results(idx(k));
        marker = '   ';
        if ~r.passed, marker = ' ✘ '; end
        if isfinite(options.MaxSeconds) && r.time > options.MaxSeconds, marker = '⏰  '; end
        fprintf('  %s%6.2fs  %s\n', marker, r.time, r.name);
    end
end

if nFailed > 0
    fprintf('\nFailed suites:\n');
    for k = 1:nSuites
        if ~results(k).passed
            fprintf('  - %s: %s\n', results(k).name, results(k).error);
        end
    end
    error('runAllTests:failures', '%d test suite(s) failed.', nFailed);
end
end


function result = runOneSuite(suitePath, descr, maxSeconds)
%RUNONESUITE  Execute one test script in an isolated function workspace.
%   Test scripts often start with `clear; clc;` which nukes the workspace
%   they execute in. `run()` runs the script in the *caller's* workspace,
%   so we route the actual `run` through a minimal helper that has no
%   other locals — the clear inside the test has nothing to destroy
%   that we care about. runOneSuite's own locals (suiteName, t0,
%   result) stay safe one frame up.
%
%   maxSeconds is a SOFT budget — MATLAB can't kill a running script from
%   outside. When a test overruns we flag it TIMEOUT after the fact so
%   the summary highlights the slow one, but the test still gets to
%   finish (or fail naturally). Don't use this as a hard reliability
%   gate — use it for "which test is hanging?" diagnostics.
    if nargin < 3, maxSeconds = Inf; end

    [~, suiteName] = fileparts(suitePath);
    result = struct('name', suiteName, 'passed', false, 'time', 0, 'error', '');

    if isfinite(maxSeconds)
        fprintf('▶ %s — %s  [budget %.0fs]\n', suiteName, descr, maxSeconds);
    else
        fprintf('▶ %s — %s\n', suiteName, descr);
    end

    t0 = tic;
    try
        executeTest(suitePath);
        result.passed = true;
    catch ME
        result.passed = false;
        result.error = ME.message;
        fprintf('  ✘ FAIL: %s\n', ME.message);
    end
    result.time = toc(t0);

    % Flag overruns (soft — test already ran to completion or error)
    if result.time > maxSeconds
        if result.passed
            result.error = sprintf('TIMEOUT (ran %.1fs, budget %.0fs)', result.time, maxSeconds);
        else
            result.error = sprintf('TIMEOUT + FAIL: %s', result.error);
        end
    end

    if result.passed && result.time <= maxSeconds
        fprintf('  ✔ pass (%.2fs)\n\n', result.time);
    elseif result.passed
        fprintf('  ⏰ pass-but-slow (%.2fs > %.0fs budget)\n\n', result.time, maxSeconds);
    else
        fprintf('  ✘ fail (%.2fs)\n\n', result.time);
    end
end


function executeTest(suitePath)
%EXECUTETEST  Run one test script. Its `clear` only sees this empty frame.
    run(suitePath);
end
