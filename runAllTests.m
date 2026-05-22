function runAllTests(options)
%RUNALLTESTS  Run the complete FermiViewer test suite and print a summary.
%
%   Syntax:
%       runAllTests
%       runAllTests(Group="fv")
%
%   Name-Value Options:
%       Group    "all" (default) | "fv" | "fvgui" | "parser" | "gui" | "smoke" |
%                "eds" | "eels" | "eels_adv" | "diffindex" | "diff_sim" |
%                "edsquant" | "contour" | "spectral"
%
%   Groups:
%       parser    — EM parser smoke tests (importBCF, importDM3, ...)
%       fv        — EM image parsers + imaging utilities (synthetic data, fast)
%       fvgui     — headless FermiViewer GUI API tests
%       gui       — annotation/measurement widget tests (small, headless)
%       smoke     — full interaction sequences with real image data
%       eds       — EDS multi-channel composite mode tests
%       eels      — EELS imaging utilities (synthetic data)
%       eels_adv  — advanced EELS: Fourier-log, ELNES, Kramers-Kronig
%       diffindex — diffraction indexing utilities
%       diff_sim  — diffraction simulation, virtual dark-field, ZAF correction
%       edsquant  — EDS quantification (k-factor table, Cliff-Lorimer)
%       contour   — contour / ring overlay tests
%       spectral  — shared spectral utilities
%       all       — every group above, in order
%
%   Examples:
%       runAllTests                      % full suite
%       runAllTests(Group="fv")          % EM parser + imaging utilities only
%       runAllTests(Group="fvgui")       % FermiViewer GUI API tests
%       runAllTests(Group="eels_adv")    % advanced EELS only
%
%   Throws an error if any suite fails so CI/scripts can detect failures.

arguments
    options.Group string = "all"
end

options.Group = validatestring(options.Group, ...
    ["all", "parser", "fv", "fvgui", "gui", "smoke", ...
     "eds", "eels", "eels_adv", "diffindex", "diff_sim", ...
     "edsquant", "contour", "spectral"]);

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

    T('smoke','test_fv_smoke'),                         'smoke',  'FermiViewer smoke: fire every button + interaction sequences with real image'
};

% Filter suites by group
if options.Group ~= "all"
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
fprintf('========================================\n\n');

for k = 1:nSuites
    results(k) = runOneSuite(SUITES{k, 1}, SUITES{k, 3});
end

% Summary
nPassed = sum([results.passed]);
nFailed = nSuites - nPassed;
totalTime = sum([results.time]);

fprintf('========================================\n');
fprintf('Summary: %d/%d passed (%.1fs total)\n', nPassed, nSuites, totalTime);
fprintf('========================================\n');

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


function result = runOneSuite(suitePath, descr)
%RUNONESUITE  Execute one test script in an isolated function workspace.
%   Test scripts often start with `clear; clc;` which nukes the caller's
%   workspace. Wrapping each `run()` in a function isolates that side
%   effect so the outer loop's bookkeeping variables (k, results, etc.)
%   survive.
    [~, suiteName] = fileparts(suitePath);
    result = struct('name', suiteName, 'passed', false, 'time', 0, 'error', '');

    fprintf('▶ %s — %s\n', suiteName, descr);

    t0 = tic;
    try
        run(suitePath);
        result.passed = true;
    catch ME
        result.passed = false;
        result.error = ME.message;
        fprintf('  ✘ FAIL: %s\n', ME.message);
    end
    result.time = toc(t0);

    if result.passed
        fprintf('  ✔ pass (%.2fs)\n\n', result.time);
    else
        fprintf('  ✘ fail (%.2fs)\n\n', result.time);
    end
end
