%TEST_TILTGEOMETRYCORRECTION  Unit tests for Surface vs Cross-section
%tilt-correction geometries in imaging.measureDistance / lineProfile.
%
%   Covers:
%     A) Surface geometry  — Δy = 100 at 30°  →  100 / cos(30°)
%     B) CrossSection Y    — Δy = 100 at 30°  →  100 / sin(30°)
%        (tilt-axis Y only; lateral X unaffected)
%     C) CrossSection @ 0° — identity (no correction when tilt = 0)
%     D) Backward compat   — omitting Geometry defaults to CrossSection
%
%   Run standalone:  run tests/imaging/test_tiltGeometryCorrection
%   Run from group:  runAllTests(Group="em")

clear; clc;
fprintf('\n═══ test_tiltGeometryCorrection ═══\n');

thisDir = fileparts(mfilename('fullpath'));
rootDir = fileparts(fileparts(thisDir));
if ~contains(path, rootDir)
    addpath(rootDir);
end

nPass = 0;
nFail = 0;
tol   = 1e-9;

% ════════════════════════════════════════════════════════════════════════
%  A. Surface geometry — 30° tilt, 100-unit raw vertical distance
%     Plan-view SEM: true lateral length recovered via 1/cos(θ).
% ════════════════════════════════════════════════════════════════════════
try
    d = imaging.measureDistance(0, 0, 0, 100, ...
        TiltAngle=30, TiltAxis='Y', Geometry="Surface");
    expected = 100 / cosd(30);
    assert(abs(d - expected) < 1e-9, ...
        sprintf('Surface geom: got %.6f, expected %.6f', d, expected));
    nPass = nPass + 1;
    fprintf('  ✔ Test A: Surface @ 30°, Δy=100  →  100/cos(30°)\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test A: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  B. Cross-section geometry — 30° tilt, Y-axis only.
%     True depth recovered via 1/sin(θ). X-axis unaffected.
% ════════════════════════════════════════════════════════════════════════
try
    % Pure vertical segment — all of the distance is in Δy so 1/sin applies.
    dy = imaging.measureDistance(0, 0, 0, 100, ...
        TiltAngle=30, TiltAxis='Y', Geometry="CrossSection");
    expectedDy = 100 / sind(30);
    assert(abs(dy - expectedDy) < 1e-9, ...
        sprintf('CrossSection Y: got %.6f, expected %.6f', dy, expectedDy));

    % Pure horizontal segment — orthogonal to tilt axis Y, so NO correction.
    dx = imaging.measureDistance(0, 0, 100, 0, ...
        TiltAngle=30, TiltAxis='Y', Geometry="CrossSection");
    assert(abs(dx - 100) < 1e-9, ...
        sprintf('CrossSection X (tilt-axis Y): should be unchanged, got %.6f', dx));

    % Mixed segment — only Δy gets stretched by 1/sin(30°).
    dxy = imaging.measureDistance(0, 0, 60, 80, ...
        TiltAngle=30, TiltAxis='Y', Geometry="CrossSection");
    expectedMixed = sqrt(60^2 + (80 / sind(30))^2);
    assert(abs(dxy - expectedMixed) < 1e-9, ...
        sprintf('CrossSection mixed: got %.6f, expected %.6f', dxy, expectedMixed));

    nPass = nPass + 1;
    fprintf('  ✔ Test B: CrossSection @ 30° — Y stretched by 1/sin, X unchanged\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test B: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  C. Geometry='CrossSection' with TiltAngle=0 → identity
%     Zero tilt should bypass the correction entirely (no divide-by-zero).
% ════════════════════════════════════════════════════════════════════════
try
    d = imaging.measureDistance(0, 0, 3, 4, ...
        TiltAngle=0, Geometry="CrossSection");
    assert(abs(d - 5) < tol, ...
        sprintf('Zero-tilt identity broken: got %.9f, expected 5', d));

    % Also verify Surface at 0° is identity
    d2 = imaging.measureDistance(0, 0, 3, 4, ...
        TiltAngle=0, Geometry="Surface");
    assert(abs(d2 - 5) < tol, ...
        sprintf('Surface zero-tilt identity broken: got %.9f', d2));

    nPass = nPass + 1;
    fprintf('  ✔ Test C: Zero-tilt is a no-op for both geometries\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test C: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  D. Backward compatibility — omitting Geometry defaults to CrossSection.
%     Existing callers that pre-date the Geometry parameter should get the
%     new (physically correct) 1/sin behaviour.
% ════════════════════════════════════════════════════════════════════════
try
    % Default must equal explicit CrossSection at the same tilt.
    dDefault  = imaging.measureDistance(0, 0, 0, 10, TiltAngle=30);
    dExplicit = imaging.measureDistance(0, 0, 0, 10, ...
        TiltAngle=30, Geometry="CrossSection");
    assert(abs(dDefault - dExplicit) < tol, ...
        'Omitted Geometry must equal explicit CrossSection');
    % Default must use 1/sin numerically.
    assert(abs(dDefault - 10/sind(30)) < 1e-9, ...
        sprintf('Default must use 1/sin: got %.6f, expected %.6f', ...
                dDefault, 10/sind(30)));
    % Surface must use 1/cos — confirm divergence from default at 30°
    % (at 45° the two happen to coincide since sin=cos=√2/2).
    dSurf30 = imaging.measureDistance(0, 0, 0, 10, ...
        TiltAngle=30, Geometry="Surface");
    assert(abs(dSurf30 - 10/cosd(30)) < 1e-9, ...
        'Surface must use 1/cos');
    assert(abs(dDefault - dSurf30) > 1e-3, ...
        '1/sin and 1/cos should differ materially at 30°');
    nPass = nPass + 1;
    fprintf('  ✔ Test D: Default Geometry == CrossSection (backward compat)\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test D: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  E. lineProfile — Geometry threaded through
% ════════════════════════════════════════════════════════════════════════
try
    img = repmat(linspace(0, 1, 64), 64, 1);
    [dCross, ~] = imaging.lineProfile(img, 10, 10, 10, 50, ...
        TiltAngle=40, Geometry="CrossSection");
    [dSurf,  ~] = imaging.lineProfile(img, 10, 10, 10, 50, ...
        TiltAngle=40, Geometry="Surface");
    ratioCross = dCross(end) / 40;    % 40 px raw Δy
    ratioSurf  = dSurf(end)  / 40;
    assert(abs(ratioCross - 1/sind(40)) < 1e-6, 'lineProfile CrossSection uses 1/sin');
    assert(abs(ratioSurf  - 1/cosd(40)) < 1e-6, 'lineProfile Surface uses 1/cos');
    nPass = nPass + 1;
    fprintf('  ✔ Test E: lineProfile respects Geometry parameter\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test E: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  Summary
% ════════════════════════════════════════════════════════════════════════
fprintf('\n═══ Tilt-geometry tests: %d passed, %d failed ═══\n\n', nPass, nFail);

if nFail > 0
    error('test_tiltGeometryCorrection: %d test(s) failed', nFail);
end
