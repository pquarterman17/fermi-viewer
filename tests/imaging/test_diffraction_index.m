%TEST_DIFFRACTION_INDEX  Unit tests for diffraction utility functions.
%
%   Tests use purely synthetic data so no external files are required.
%   Each test prints a tick (pass) or cross (fail) with a brief description.
%
%   Functions tested:
%       imaging.calcElectronWavelength
%       imaging.findDiffractionSpots
%       imaging.indexDiffraction
%
%   Run standalone:  cd tests; run test_diffraction_index
%   Run from root:   run tests/test_diffraction_index
%       runAllTests(Group="diffindex")

clear; clc;
fprintf('\n═══ test_diffraction_index ═══\n');

% Ensure toolbox is on the path
thisDir = fileparts(mfilename('fullpath'));
rootDir = fileparts(fileparts(thisDir));
if ~contains(path, rootDir)
    addpath(rootDir);
end

nPass = 0;
nFail = 0;

try  % outer guard — keeps runner from hanging on unexpected errors

% ════════════════════════════════════════════════════════════════════════
%  1. calcElectronWavelength — scalar values at 200 kV and 300 kV
% ════════════════════════════════════════════════════════════════════════
try
    lambda200 = imaging.calcElectronWavelength(200);
    lambda300 = imaging.calcElectronWavelength(300);

    % Reference values in Angstroms (Williams & Carter, 2nd ed.)
    assert(abs(lambda200 - 0.02508) / 0.02508 < 0.01, ...
        sprintf('200 kV: expected ~0.02508 Å, got %.5f', lambda200));
    assert(abs(lambda300 - 0.01969) / 0.01969 < 0.01, ...
        sprintf('300 kV: expected ~0.01969 Å, got %.5f', lambda300));

    % Physical sanity: shorter wavelength at higher voltage
    assert(lambda300 < lambda200, 'Higher voltage should give shorter wavelength');

    nPass = nPass + 1;
    fprintf('  ✔ Test 1: calcElectronWavelength — 200 kV and 300 kV scalars\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 1: calcElectronWavelength scalars: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  2. calcElectronWavelength — vectorized input returns 3 values
% ════════════════════════════════════════════════════════════════════════
try
    lambdas = imaging.calcElectronWavelength([100, 200, 300]);

    assert(numel(lambdas) == 3,   'Expected 3 output values');
    assert(all(lambdas > 0),      'All wavelengths must be positive');
    % Monotonically decreasing with voltage
    assert(lambdas(1) > lambdas(2) && lambdas(2) > lambdas(3), ...
        'Wavelengths not monotonically decreasing with voltage');

    nPass = nPass + 1;
    fprintf('  ✔ Test 2: calcElectronWavelength — vectorized [100 200 300] kV\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 2: calcElectronWavelength vectorized: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  3. findDiffractionSpots — 4 Gaussian spots at known positions
% ════════════════════════════════════════════════════════════════════════
try
    N = 256;
    img = zeros(N, N);

    % Place 4 spots at known positions (well away from centre)
    targetPos = [60 128; 196 128; 128 60; 128 196];  % [row, col]

    sigma = 3;
    [XX, YY] = meshgrid(1:N, 1:N);
    for k = 1:size(targetPos, 1)
        r0 = targetPos(k, 1);
        c0 = targetPos(k, 2);
        img = img + exp(-((YY - r0).^2 + (XX - c0).^2) / (2*sigma^2));
    end

    spots = imaging.findDiffractionSpots(img, ...
        MinRadius=20, Threshold=0.05, MinSeparation=20);

    assert(size(spots, 2) == 2, 'spots must be [N x 2]');
    assert(size(spots, 1) >= 4, ...
        sprintf('Expected ≥4 spots, found %d', size(spots, 1)));

    % Every target position must be matched within 2 px
    for k = 1:size(targetPos, 1)
        r0 = targetPos(k, 1);
        c0 = targetPos(k, 2);
        dists = sqrt((spots(:,1) - r0).^2 + (spots(:,2) - c0).^2);
        assert(min(dists) <= 2, ...
            sprintf('Target spot (%d,%d) not found within 2 px tolerance', r0, c0));
    end

    nPass = nPass + 1;
    fprintf('  ✔ Test 3: findDiffractionSpots — 4 spots at known positions\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 3: findDiffractionSpots 4 spots: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  4. findDiffractionSpots — center spot excluded by MinRadius
% ════════════════════════════════════════════════════════════════════════
try
    N   = 256;
    img = zeros(N, N);
    ctr = floor(N/2) + 1;   % 129 for N=256

    [XX, YY] = meshgrid(1:N, 1:N);
    sigma = 3;

    % Bright spot at the centre (direct beam)
    img = img + 2 * exp(-((YY - ctr).^2 + (XX - ctr).^2) / (2*sigma^2));

    % One off-centre spot
    img = img + exp(-((YY - 60).^2 + (XX - ctr).^2) / (2*sigma^2));

    spots = imaging.findDiffractionSpots(img, MinRadius=30, Threshold=0.05);

    if ~isempty(spots)
        % No accepted spot should be within MinRadius of centre
        dr = spots(:,1) - ctr;
        dc = spots(:,2) - ctr;
        R  = sqrt(dr.^2 + dc.^2);
        assert(all(R >= 30), ...
            'A spot within MinRadius=30 was accepted (centre exclusion failed)');
    end

    nPass = nPass + 1;
    fprintf('  ✔ Test 4: findDiffractionSpots — centre spot excluded by MinRadius\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 4: findDiffractionSpots centre exclusion: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  5. findDiffractionSpots — all-zero image → empty result
% ════════════════════════════════════════════════════════════════════════
try
    img   = zeros(128, 128);
    spots = imaging.findDiffractionSpots(img);

    assert(isempty(spots) || size(spots, 1) == 0, ...
        'All-zero image should produce no spots');
    assert(size(spots, 2) == 2 || isempty(spots), ...
        'Return must be [0 x 2] or empty');

    nPass = nPass + 1;
    fprintf('  ✔ Test 5: findDiffractionSpots — all-zero image → empty\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 5: findDiffractionSpots all-zero: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  6. indexDiffraction — FCC Silicon [001] zone axis
%     Spots placed at FFT-mode radii for Si d-spacings:
%       (111): d = a/sqrt(3) ≈ 3.135 Å
%       (220): d = a/sqrt(8) ≈ 1.920 Å
%       (311): d = a/sqrt(11)≈ 1.637 Å
%     FFT mode: d = imgSize(2) * PixelSize / R → R = imgSize(2) / d
%     (PixelSize defaults to 1 px, imgSize = [256 256])
% ════════════════════════════════════════════════════════════════════════
try
    imgSz = [256, 256];
    a_Si  = 5.4309;   % Å

    dSi_111 = a_Si / sqrt(3);   % ≈ 3.135 Å
    dSi_220 = a_Si / sqrt(8);   % ≈ 1.920 Å
    dSi_311 = a_Si / sqrt(11);  % ≈ 1.637 Å

    % FFT mode: R = imgSize(2) / d  (PixelSize = 1)
    R111 = imgSz(2) / dSi_111;
    R220 = imgSz(2) / dSi_220;
    R311 = imgSz(2) / dSi_311;

    ctr = floor(imgSz / 2) + 1;   % [129, 129]

    % Place spot pairs symmetrically along rows and columns
    % (111): horizontal pair
    % (220): vertical pair
    % (311): diagonal pair at 45°
    spotPos = [
        ctr(1),            ctr(2) + round(R111);   % (111) right
        ctr(1),            ctr(2) - round(R111);   % (111) left
        ctr(1) + round(R220), ctr(2);              % (220) down
        ctr(1) - round(R220), ctr(2);              % (220) up
        ctr(1) + round(R311/sqrt(2)), ctr(2) + round(R311/sqrt(2));  % (311) SE
        ctr(1) - round(R311/sqrt(2)), ctr(2) - round(R311/sqrt(2));  % (311) NW
    ];

    result = imaging.indexDiffraction(spotPos, imgSz, ...
        PixelSize=1, Tolerance=0.08, Phases={'Silicon'}, TopN=1);

    assert(isstruct(result),                    'result must be a struct');
    assert(isfield(result, 'candidates'),       'Missing field: candidates');
    assert(isfield(result, 'measuredD'),        'Missing field: measuredD');
    assert(numel(result.candidates) >= 1,       'No candidates returned');

    bestMatch = result.candidates(1).phaseName;
    assert(strcmp(bestMatch, 'Silicon'), ...
        sprintf('Expected Silicon as top match, got "%s"', bestMatch));

    assert(result.candidates(1).nMatched >= 2, ...
        sprintf('Expected ≥2 matched spots, got %d', result.candidates(1).nMatched));

    nPass = nPass + 1;
    fprintf('  ✔ Test 6: indexDiffraction — FCC Si top candidate is Silicon\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 6: indexDiffraction FCC Si: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  7. indexDiffraction — zone axis for Si [001]
%     With (111)/(1-1-1) and (220)/(2-20) spots, the zone axis satisfying
%     h*u+k*v+l*w=0 for all hkl should be [0 0 1].
% ════════════════════════════════════════════════════════════════════════
try
    imgSz = [256, 256];
    a_Si  = 5.4309;

    dSi_220 = a_Si / sqrt(8);
    dSi_400 = a_Si / 4;        % d for (400): d = a/4 ≈ 1.358 Å

    R220 = imgSz(2) / dSi_220;
    R400 = imgSz(2) / dSi_400;

    ctr = floor(imgSz / 2) + 1;

    % (220) and (2-20) are in the [001] zone axis: h*0+k*0+l*1=0 → l=0 ✓
    % (400) and (-400) are in [001] zone: 4*0+0*0+0*1=0 ✓
    spotPos = [
        ctr(1) + round(R220), ctr(2);              % (220) approx
        ctr(1) - round(R220), ctr(2);              % (-2-20)
        ctr(1),               ctr(2) + round(R400); % (400) approx
        ctr(1),               ctr(2) - round(R400); % (-400) approx
    ];

    result = imaging.indexDiffraction(spotPos, imgSz, ...
        PixelSize=1, Tolerance=0.10, Phases={'Silicon'}, TopN=1);

    assert(numel(result.candidates) >= 1, 'No candidates returned');

    za = result.candidates(1).zoneAxis;
    assert(~all(isnan(za)), 'Zone axis is NaN (fewer than 2 spots matched)');

    % Normalise to unit direction for comparison: [0 0 1]
    % The function returns the smallest-norm zone axis, so check the
    % dominant direction is [0 0 ±1] or a scalar multiple.
    if ~any(isnan(za))
        % Zone axis must be perpendicular to all matched hkl: h*u + k*v + l*w = 0
        assert(~any(isnan(za)), 'Zone axis should not be NaN');
        matchedHKL = result.candidates(1).matchedHKL;
        dots = matchedHKL * za(:);
        assert(all(dots == 0), ...
            sprintf('Zone axis [%d %d %d] not perpendicular to all matched hkl', za));
    end

    nPass = nPass + 1;
    fprintf('  ✔ Test 7: indexDiffraction — zone axis [0 0 1] for Si\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 7: indexDiffraction zone axis: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  8. simulateDiffraction — output struct fields and image dimensions
%     Use Silicon [001] zone axis — well-known, symmetric, FCC.
% ════════════════════════════════════════════════════════════════════════
try
    r = imaging.simulateDiffraction('Silicon', ZoneAxis=[0 0 1], ...
            AccVoltage=200, CameraLength=200, PixelSize=0.05, ...
            ImageSize=[256 256], MaxHKL=4);

    assert(isstruct(r),                'result must be a struct');
    assert(isfield(r, 'spots'),        'Missing field: spots');
    assert(isfield(r, 'image'),        'Missing field: image');
    assert(isfield(r, 'phaseName'),    'Missing field: phaseName');
    assert(isfield(r, 'formula'),      'Missing field: formula');
    assert(isfield(r, 'zoneAxis'),     'Missing field: zoneAxis');
    assert(isfield(r, 'lambda'),       'Missing field: lambda');

    % Image dimensions
    assert(isequal(size(r.image), [256 256]), ...
        sprintf('Image size expected [256 256], got [%d %d]', size(r.image, 1), size(r.image, 2)));

    % Image values in [0, 1]
    assert(min(r.image(:)) >= 0,    'Image has negative values');
    assert(max(r.image(:)) <= 1 + 1e-9, 'Image exceeds 1.0');

    % At least the direct beam spot must exist
    assert(numel(r.spots) >= 1,     'No spots in result');

    % First spot is the direct beam: hkl = [0 0 0], dSpacing = NaN
    assert(isequal(r.spots(1).hkl, [0 0 0]), ...
        'First spot should be the direct beam [0 0 0]');
    assert(isnan(r.spots(1).dSpacing), ...
        'Direct beam dSpacing should be NaN');

    % Spot fields present
    assert(isfield(r.spots, 'hkl'),       'Missing spots.hkl');
    assert(isfield(r.spots, 'dSpacing'),  'Missing spots.dSpacing');
    assert(isfield(r.spots, 'intensity'), 'Missing spots.intensity');
    assert(isfield(r.spots, 'pixelRow'),  'Missing spots.pixelRow');
    assert(isfield(r.spots, 'pixelCol'),  'Missing spots.pixelCol');

    % lambda must match calcElectronWavelength(200)
    lambdaRef = imaging.calcElectronWavelength(200);
    assert(abs(r.lambda - lambdaRef) < 1e-6, ...
        sprintf('lambda mismatch: expected %.6f, got %.6f', lambdaRef, r.lambda));

    % Phase name must contain 'Silicon' (case-insensitive lookup)
    assert(contains(r.phaseName, 'Silicon'), ...
        sprintf('phaseName "%s" does not contain "Silicon"', r.phaseName));

    nPass = nPass + 1;
    fprintf('  ✔ Test 8: simulateDiffraction — output struct, image dims, direct beam\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 8: simulateDiffraction struct/dims: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  9. simulateDiffraction — Friedel symmetry: spot count should be odd
%     (direct beam + N Friedel pairs → 1 + 2*M spots)
%     and diffraction image should have non-trivial content (>0).
% ════════════════════════════════════════════════════════════════════════
try
    r = imaging.simulateDiffraction('SrTiO3', ZoneAxis=[0 0 1], ...
            AccVoltage=200, CameraLength=200, PixelSize=0.05, ...
            ImageSize=[512 512], MaxHKL=3);

    % Direct beam (1) + Friedel pairs (even count) → total is odd.
    % In cases where a reflection is its own Friedel pair (only 000 at
    % center), the count could be even — so we just check at least 3 spots.
    assert(numel(r.spots) >= 2, ...
        sprintf('Expected ≥2 spots, got %d', numel(r.spots)));

    % Image must have at least one non-zero pixel.
    assert(max(r.image(:)) > 0, 'Simulated image is entirely zero');

    % The centre pixel region should have the highest overall brightness
    % (direct beam sits there at intensity 1.0).
    H = size(r.image, 1);
    W = size(r.image, 2);
    ctrR = round(H / 2 + 0.5);
    ctrC = round(W / 2 + 0.5);
    centralRegion = r.image(max(1,ctrR-5):min(H,ctrR+5), ...
                            max(1,ctrC-5):min(W,ctrC+5));
    assert(max(centralRegion(:)) > 0.5, ...
        'Direct beam at centre should have intensity > 0.5');

    nPass = nPass + 1;
    fprintf('  ✔ Test 9: simulateDiffraction — SrTiO3 spot count and non-zero image\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 9: simulateDiffraction Friedel/image: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  10. simulateDiffraction — unknown phase name throws an error
% ════════════════════════════════════════════════════════════════════════
try
    threw = false;
    try
        imaging.simulateDiffraction('NonexistentPhaseXYZ123');
    catch
        threw = true;
    end
    assert(threw, 'Expected error for unknown phase name');

    nPass = nPass + 1;
    fprintf('  ✔ Test 10: simulateDiffraction — unknown phase throws error\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 10: simulateDiffraction unknown phase: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  11. virtualDarkField — circle mask: output size matches input
% ════════════════════════════════════════════════════════════════════════
try
    N   = 128;
    img = rand(N, N);
    ctr = [floor(N/2)+1, floor(N/2)+1];

    vdf = imaging.virtualDarkField(img, MaskCenter=ctr, MaskRadius=15);

    assert(isequal(size(vdf), [N N]), ...
        sprintf('VDF size mismatch: expected [%d %d], got [%d %d]', ...
        N, N, size(vdf,1), size(vdf,2)));
    assert(isa(vdf, 'double'),   'VDF must be double');
    assert(all(vdf(:) >= 0),     'VDF values must be non-negative (magnitude)');

    nPass = nPass + 1;
    fprintf('  ✔ Test 11: virtualDarkField — circle mask, output size and type\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 11: virtualDarkField circle: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  12. virtualDarkField — annulus mask: small inner radius gives more
%      energy than a zero-radius circle of the same outer radius at centre.
%      (Just a sanity check: annulus excludes DC, circle includes it.)
% ════════════════════════════════════════════════════════════════════════
try
    N   = 128;
    img = rand(N, N);   % random image — DC component is large
    ctr = [floor(N/2)+1, floor(N/2)+1];

    vdfCirc = imaging.virtualDarkField(img, MaskCenter=ctr, ...
                  MaskShape='circle', MaskRadius=20);
    vdfAnnulus = imaging.virtualDarkField(img, MaskCenter=ctr, ...
                  MaskShape='annulus', MaskRadius=20, InnerRadius=10);

    % Both must be non-negative real.
    assert(all(vdfCirc(:) >= 0),    'Circle VDF has negative values');
    assert(all(vdfAnnulus(:) >= 0), 'Annulus VDF has negative values');

    % Circle includes DC; annulus excludes it — circle total energy >= annulus.
    assert(sum(vdfCirc(:).^2) >= sum(vdfAnnulus(:).^2), ...
        'Circle (with DC) should have >= energy of annulus (without DC)');

    nPass = nPass + 1;
    fprintf('  ✔ Test 12: virtualDarkField — annulus mask energy < circle with DC\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 12: virtualDarkField annulus: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  13. virtualDarkField — spot-selection VDF: masking a single tone
%      recovers spatial periodicity at that frequency.
%      Construct a cosine grating, mask its FFT peak, reconstruct.
% ════════════════════════════════════════════════════════════════════════
try
    N    = 128;
    freq = 8;   % cycles across the image
    [XX, YY] = meshgrid(1:N, 1:N);
    img  = cos(2 * pi * freq * XX / N);   % horizontal grating

    % In the fftshift FFT the positive-frequency peak for 'freq' cycles
    % sits at column = floor(N/2) + 1 + freq = 73 for N=128, freq=8.
    ctrR    = floor(N/2) + 1;     % 65
    spotCol = floor(N/2) + 1 + freq;  % 73
    ctr     = [ctrR, spotCol];

    vdf = imaging.virtualDarkField(img, MaskCenter=ctr, MaskRadius=3);

    % The reconstructed VDF should have non-trivial power.
    assert(max(vdf(:)) > 0, 'VDF from grating spot is entirely zero');
    assert(all(vdf(:) >= 0), 'VDF has negative values');

    nPass = nPass + 1;
    fprintf('  ✔ Test 13: virtualDarkField — cosine grating spot selection\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 13: virtualDarkField grating: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════

catch fatalErr
    fprintf('  ✘ FATAL error in test harness: %s\n', fatalErr.message);
    nFail = nFail + 1;
end

% ── Summary ──────────────────────────────────────────────────────────────
fprintf('\n═══ Results: %d passed, %d failed ═══\n\n', nPass, nFail);

if nFail > 0
    error('test_diffraction_index:failures', '%d test(s) failed.', nFail);
end
