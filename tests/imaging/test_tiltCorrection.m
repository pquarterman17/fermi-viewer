%TEST_TILTCORRECTION  Unit tests for SEM/FIB stage-tilt correction path.
%
%   Covers:
%     * imaging.getStageTilt parsing (FEI radians, FEI degrees, Bruker
%       degrees, missing metadata)
%     * imaging.measureDistance with TiltAngle / TiltAxis options
%     * imaging.lineProfile with tilt correction applied to distance axis
%
%   Run standalone:  run tests/imaging/test_tiltCorrection
%   Run from group:  runAllTests(Group="em")

clear; clc;
fprintf('\n═══ test_tiltCorrection ═══\n');

thisDir = fileparts(mfilename('fullpath'));
rootDir = fileparts(fileparts(thisDir));
if ~contains(path, rootDir)
    addpath(rootDir);
end

nPass = 0;
nFail = 0;
tol   = 1e-9;

% ════════════════════════════════════════════════════════════════════════
%  1. measureDistance — pure vertical, Y-axis tilt correction
%      Default geometry is CrossSection (1/sin correction).
% ════════════════════════════════════════════════════════════════════════
try
    % 10 px Δy at 52° tilt → 10 / sin(52°) (cross-section default)
    d = imaging.measureDistance(0, 0, 0, 10, TiltAngle=52);
    expected = 10 / sind(52);
    assert(abs(d - expected) < 1e-6, sprintf('Y-tilt distance wrong: got %.6f, expected %.6f', d, expected));
    nPass = nPass + 1;
    fprintf('  ✔ Test 1: measureDistance vertical tilt correction (1/sin default)\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 1: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  2. measureDistance — pure horizontal, Y-axis tilt is no-op
% ════════════════════════════════════════════════════════════════════════
try
    d = imaging.measureDistance(0, 0, 10, 0, TiltAngle=52, TiltAxis='Y');
    assert(abs(d - 10) < tol, 'Y-tilt should not affect pure horizontal');
    nPass = nPass + 1;
    fprintf('  ✔ Test 2: measureDistance horizontal unaffected by Y-tilt\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 2: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  3. measureDistance — X-axis tilt correction (cross-section, 1/sin)
% ════════════════════════════════════════════════════════════════════════
try
    d = imaging.measureDistance(0, 0, 8, 0, TiltAngle=30, TiltAxis='X');
    expected = 8 / sind(30);
    assert(abs(d - expected) < 1e-6, 'X-tilt distance wrong');
    nPass = nPass + 1;
    fprintf('  ✔ Test 3: measureDistance X-axis tilt correction (1/sin default)\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 3: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  4. measureDistance — calibrated + tilt (cross-section default, 1/sin)
% ════════════════════════════════════════════════════════════════════════
try
    [d, u] = imaging.measureDistance(0, 0, 0, 10, ...
        PixelSize=2.5, PixelUnit='nm', TiltAngle=52);
    expected = (10 / sind(52)) * 2.5;
    assert(abs(d - expected) < 1e-6, 'Calibrated tilt wrong');
    assert(strcmp(u, 'nm'), 'Unit should be nm');
    nPass = nPass + 1;
    fprintf('  ✔ Test 4: measureDistance calibrated + tilt (1/sin)\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 4: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  5. measureDistance — zero tilt matches original
% ════════════════════════════════════════════════════════════════════════
try
    d1 = imaging.measureDistance(0, 0, 3, 4);
    d2 = imaging.measureDistance(0, 0, 3, 4, TiltAngle=0);
    assert(abs(d1 - d2) < tol && abs(d1 - 5) < tol, 'Zero tilt should equal baseline');
    nPass = nPass + 1;
    fprintf('  ✔ Test 5: measureDistance tilt=0 is a no-op\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 5: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  6. lineProfile — tilt stretches the distance axis (1/sin default)
% ════════════════════════════════════════════════════════════════════════
try
    img = repmat(linspace(0, 1, 64), 64, 1);  % horizontal intensity ramp
    [d0, i0] = imaging.lineProfile(img, 10, 10, 10, 50);   % vertical 40 px
    [d1, i1] = imaging.lineProfile(img, 10, 10, 10, 50, TiltAngle=52);
    % Intensities should match (same interpolation points); distance stretched
    assert(numel(d0) == numel(d1), 'Sample count should match');
    assert(max(abs(i0 - i1)) < 1e-9, 'Intensities should match');
    ratio = d1(end) / d0(end);
    expectedRatio = 1 / sind(52);
    assert(abs(ratio - expectedRatio) < 1e-6, ...
        sprintf('Distance-axis ratio wrong: got %.4f, expected %.4f', ratio, expectedRatio));
    nPass = nPass + 1;
    fprintf('  ✔ Test 6: lineProfile distance axis stretched by 1/sin(tilt)\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 6: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  7. getStageTilt — FEI radians (Helios/Tecnai style)
% ════════════════════════════════════════════════════════════════════════
try
    imgInfo = struct();
    imgInfo.acquiParams = struct();
    imgInfo.acquiParams.feiMetadata = struct();
    imgInfo.acquiParams.feiMetadata.Stage = struct();
    imgInfo.acquiParams.feiMetadata.Stage.StageT = '0.9076';   % ≈ 52° in radians
    [tilt, src] = imaging.getStageTilt(imgInfo);
    assert(abs(tilt - 52) < 0.05, sprintf('Expected ~52°, got %.4f', tilt));
    assert(contains(src, 'FEI'), 'Source should name FEI');
    nPass = nPass + 1;
    fprintf('  ✔ Test 7: getStageTilt FEI radians → degrees\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 7: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  8. getStageTilt — FEI degrees (when value already >= pi)
% ════════════════════════════════════════════════════════════════════════
try
    imgInfo = struct();
    imgInfo.acquiParams.feiMetadata.Stage.StageT = '52';
    [tilt, ~] = imaging.getStageTilt(imgInfo);
    assert(abs(tilt - 52) < tol, sprintf('Expected 52°, got %.4f', tilt));
    nPass = nPass + 1;
    fprintf('  ✔ Test 8: getStageTilt FEI already in degrees\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 8: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  9. getStageTilt — Bruker BCF (stageTilt_deg)
% ════════════════════════════════════════════════════════════════════════
try
    imgInfo = struct();
    imgInfo.metadata.parserSpecific.semParams.stageTilt_deg = 35.5;
    [tilt, src] = imaging.getStageTilt(imgInfo);
    assert(abs(tilt - 35.5) < tol, sprintf('Expected 35.5°, got %.4f', tilt));
    assert(contains(src, 'Bruker'), 'Source should name Bruker');
    nPass = nPass + 1;
    fprintf('  ✔ Test 9: getStageTilt Bruker BCF semParams\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 9: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  10. getStageTilt — missing metadata returns NaN
% ════════════════════════════════════════════════════════════════════════
try
    imgInfo = struct('acquiParams', struct());
    [tilt, src] = imaging.getStageTilt(imgInfo);
    assert(isnan(tilt), 'Expected NaN for missing tilt');
    assert(isempty(src), 'Source should be empty');
    nPass = nPass + 1;
    fprintf('  ✔ Test 10: getStageTilt returns NaN when tilt missing\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 10: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  11. getStageTilt — accepts imageData directly (has acquiParams field)
% ════════════════════════════════════════════════════════════════════════
try
    imgData = struct();
    imgData.acquiParams.feiMetadata.Stage.StageT = '0.6981';   % ≈ 40°
    tilt = imaging.getStageTilt(imgData);
    assert(abs(tilt - 40) < 0.05, sprintf('Expected ~40°, got %.4f', tilt));
    nPass = nPass + 1;
    fprintf('  ✔ Test 11: getStageTilt accepts plain imageData struct\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 11: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  Summary
% ════════════════════════════════════════════════════════════════════════
fprintf('\n═══ Tilt-correction tests: %d passed, %d failed ═══\n\n', nPass, nFail);

if nFail > 0
    error('test_tiltCorrection: %d test(s) failed', nFail);
end
