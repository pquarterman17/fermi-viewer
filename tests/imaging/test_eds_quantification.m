%TEST_EDS_QUANTIFICATION  Unit tests for EDS quantification functions.
%
%   Tests use purely synthetic data so no external files are required.
%   Each test prints a tick (pass) or cross (fail) with a brief description.
%
%   Functions tested:
%       imaging.eds.edsKFactorTable
%       imaging.eds.cliffLorimer
%       imaging.eds.edsCompositionProfile
%       imaging.eds.mapIsBlank
%       imaging.eds.toKeV
%       imaging.eds.extractElementMaps (Units option)
%
%   Run standalone:  cd tests; run test_eds_quantification
%   Run from root:   run tests/test_eds_quantification
%       runAllTests(Group="edsquant")

clear; clc;
fprintf('\n═══ test_eds_quantification ═══\n');

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
%  1. edsKFactorTable — returns containers.Map; Si=1.00; Fe has value;
%     table contains >30 elements
% ════════════════════════════════════════════════════════════════════════
try
    kt = imaging.eds.edsKFactorTable();

    assert(isa(kt, 'dictionary'), 'Return type must be dictionary');
    assert(isKey(kt, 'Si'),      'Table must contain Si');
    assert(abs(kt('Si') - 1.00) < 1e-9, ...
        sprintf('Si k-factor expected 1.00, got %.4f', kt('Si')));
    assert(isKey(kt, 'Fe'), 'Table must contain Fe');
    assert(kt('Fe') > 0,    'Fe k-factor must be positive');
    assert(numEntries(kt) > 30, sprintf('Expected >30 elements, got %d', numEntries(kt)));

    nPass = nPass + 1;
    fprintf('  ✔ Test 1: edsKFactorTable — Si=1.00, Fe present, >30 elements\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 1: edsKFactorTable: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  2. edsKFactorTable — non-200 kV voltage triggers warning but returns table
% ════════════════════════════════════════════════════════════════════════
try
    warnState = warning('off', 'edsKFactorTable:voltageNotBuiltIn');
    cleanupWarn = onCleanup(@() warning(warnState));

    [~, warnInfo] = lastwarn('');   % clear previous warning
    kt = imaging.eds.edsKFactorTable(Voltage=100);

    assert(isa(kt, 'dictionary'), 'Table must still be returned for non-200 kV');
    assert(isKey(kt, 'Si'),           'Si must be present in fallback table');

    % Verify a warning was issued
    lastMsg = lastwarn();
    assert(~isempty(lastMsg), 'Expected a warning for non-200 kV voltage');

    nPass = nPass + 1;
    fprintf('  ✔ Test 2: edsKFactorTable — non-200 kV issues warning, returns table\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 2: edsKFactorTable non-200 kV: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  3. cliffLorimer — two elements (Fe, O), equal intensities
%     k_Fe = 1.21, k_O = 1.80; with I_Fe = I_O:
%       w_Fe = 1.21*1 / (1.21 + 1.80) ≈ 40.2 wt%
%       w_O  = 1.80*1 / (1.21 + 1.80) ≈ 59.8 wt%
%     Sum must be 100 wt% and 100 at%.
% ════════════════════════════════════════════════════════════════════════
try
    H = 10; W = 10;
    IFe = ones(H, W) * 1000;
    IO  = ones(H, W) * 1000;

    kFe = 1.21;   kO = 1.80;

    res = imaging.eds.cliffLorimer({IFe, IO}, {'Fe', 'O'}, KFactors=[kFe, kO]);

    assert(isfield(res, 'weightPctMaps'),  'Missing field: weightPctMaps');
    assert(isfield(res, 'atomicPctMaps'),  'Missing field: atomicPctMaps');
    assert(isfield(res, 'meanWeightPct'),  'Missing field: meanWeightPct');
    assert(isfield(res, 'meanAtomicPct'),  'Missing field: meanAtomicPct');

    % Weight% must sum to 100
    wSum = res.meanWeightPct(1) + res.meanWeightPct(2);
    assert(abs(wSum - 100) < 0.1, ...
        sprintf('Weight%% sum expected 100, got %.3f', wSum));

    % Atomic% must sum to 100
    aSum = res.meanAtomicPct(1) + res.meanAtomicPct(2);
    assert(abs(aSum - 100) < 0.1, ...
        sprintf('Atomic%% sum expected 100, got %.3f', aSum));

    % Fe wt% = k_Fe / (k_Fe + k_O) * 100
    expectedFePct = kFe / (kFe + kO) * 100;
    assert(abs(res.meanWeightPct(1) - expectedFePct) < 0.5, ...
        sprintf('Fe wt%% expected %.2f, got %.2f', expectedFePct, res.meanWeightPct(1)));

    nPass = nPass + 1;
    fprintf('  ✔ Test 3: cliffLorimer — two elements, equal intensities, wt/at sum 100\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 3: cliffLorimer two elements: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  4. cliffLorimer — MaskThreshold: zero-intensity pixels → NaN
% ════════════════════════════════════════════════════════════════════════
try
    H = 10; W = 10;
    IFe = ones(H, W) * 500;
    IO  = ones(H, W) * 500;

    % Set top-left 3×3 to zero intensity
    IFe(1:3, 1:3) = 0;
    IO(1:3,  1:3) = 0;

    res = imaging.eds.cliffLorimer({IFe, IO}, {'Fe', 'O'}, ...
        KFactors=[1.21, 1.80], MaskThreshold=0);

    % The mask should mark zero-intensity pixels as invalid
    assert(isfield(res, 'mask'), 'Missing field: mask');
    maskSub = logical(res.mask(1:3, 1:3));
    maskedOut = ~maskSub;
    assert(all(maskedOut(:)), 'Zero-intensity pixels should be masked out');

    % Check those pixels are NaN in the output maps
    feMap = res.weightPctMaps{1};
    nanCheck = isnan(feMap(1:3, 1:3));
    assert(all(nanCheck(:)), ...
        'Masked pixels must be NaN in weight% map');

    % Valid pixels should not be NaN
    validCheck = ~isnan(feMap(4:end, 4:end));
    assert(all(validCheck(:)), ...
        'Valid pixels must not be NaN');

    nPass = nPass + 1;
    fprintf('  ✔ Test 4: cliffLorimer — zero-intensity mask produces NaN\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 4: cliffLorimer mask: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  5. cliffLorimer — uniform intensities for 3 elements
%     With equal I for all elements, w_i = k_i / sum(k), so weight
%     fractions are proportional to k-factors (not equal to each other
%     unless k-factors are equal).  Sum must still equal 100 for each pixel.
% ════════════════════════════════════════════════════════════════════════
try
    H = 5; W = 5;
    maps = {ones(H,W)*200, ones(H,W)*200, ones(H,W)*200};
    els  = {'Fe', 'O', 'Si'};
    kFe = 1.21; kO = 1.80; kSi = 1.00;

    res = imaging.eds.cliffLorimer(maps, els, KFactors=[kFe, kO, kSi]);

    wSum = res.meanWeightPct(1) + res.meanWeightPct(2) + res.meanWeightPct(3);
    assert(abs(wSum - 100) < 0.1, ...
        sprintf('3-element wt%% sum expected 100, got %.3f', wSum));

    aSum = res.meanAtomicPct(1) + res.meanAtomicPct(2) + res.meanAtomicPct(3);
    assert(abs(aSum - 100) < 0.1, ...
        sprintf('3-element at%% sum expected 100, got %.3f', aSum));

    % Fe wt% should be proportional to k_Fe relative to total k
    expectedFePct = kFe / (kFe + kO + kSi) * 100;
    assert(abs(res.meanWeightPct(1) - expectedFePct) < 0.5, ...
        sprintf('Fe wt%% expected %.2f, got %.2f', expectedFePct, res.meanWeightPct(1)));

    nPass = nPass + 1;
    fprintf('  ✔ Test 5: cliffLorimer — 3-element uniform, sum = 100, k-proportional\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 5: cliffLorimer 3-element uniform: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  6. edsCompositionProfile — gradient maps, Fe increases left→right
% ════════════════════════════════════════════════════════════════════════
try
    H = 50; W = 100;

    % Fe increases left to right (0 to 80 at%); O decreases (80 to 0 at%)
    FeMap = repmat(linspace(0, 80, W), H, 1);
    OMap  = repmat(linspace(80, 0, W), H, 1);

    % Horizontal profile across the middle row
    prof = imaging.eds.edsCompositionProfile({FeMap, OMap}, {'Fe', 'O'}, ...
        1, round(H/2), W, round(H/2));

    assert(isstruct(prof),                   'Return must be a struct');
    assert(isfield(prof, 'distance'),        'Missing field: distance');
    assert(isfield(prof, 'atomicPct'),       'Missing field: atomicPct');
    assert(isfield(prof, 'elements'),        'Missing field: elements');
    assert(numel(prof.distance) > 1,         'Profile must have >1 sample points');

    % Fe column (index 1) must increase along the profile
    fePct = prof.atomicPct(:, 1);
    oPct  = prof.atomicPct(:, 2);

    % Compare first quarter vs last quarter of profile
    n = numel(fePct);
    feMid1 = mean(fePct(1 : round(n/4)));
    feMid2 = mean(fePct(round(3*n/4) : end));
    assert(feMid2 > feMid1, ...
        sprintf('Fe should increase along profile: start=%.1f, end=%.1f', ...
        feMid1, feMid2));

    % O should decrease along the same profile
    oMid1 = mean(oPct(1 : round(n/4)));
    oMid2 = mean(oPct(round(3*n/4) : end));
    assert(oMid2 < oMid1, ...
        sprintf('O should decrease along profile: start=%.1f, end=%.1f', ...
        oMid1, oMid2));

    nPass = nPass + 1;
    fprintf('  ✔ Test 6: edsCompositionProfile — Fe increases, O decreases\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 6: edsCompositionProfile gradient: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  7. edsCompositionProfile — Width=3 averaging, profile still directional
% ════════════════════════════════════════════════════════════════════════
try
    H = 50; W = 100;

    FeMap = repmat(linspace(0, 80, W), H, 1);
    OMap  = repmat(linspace(80, 0, W), H, 1);

    % Width=1 profile (reference)
    prof1 = imaging.eds.edsCompositionProfile({FeMap, OMap}, {'Fe', 'O'}, ...
        1, round(H/2), W, round(H/2), NumPoints=50);

    % Width=3 averaged profile
    prof3 = imaging.eds.edsCompositionProfile({FeMap, OMap}, {'Fe', 'O'}, ...
        1, round(H/2), W, round(H/2), NumPoints=50, Width=3);

    % Both should have the same number of sample points
    assert(numel(prof1.distance) == numel(prof3.distance), ...
        'Width averaging should not change NumPoints');

    % Width=3 should still be directional (Fe increasing)
    fePct3 = prof3.atomicPct(:, 1);
    n = numel(fePct3);
    fe3Start = mean(fePct3(1 : round(n/4)));
    fe3End   = mean(fePct3(round(3*n/4) : end));
    assert(fe3End > fe3Start, ...
        'Fe should still increase with Width=3 averaging');

    nPass = nPass + 1;
    fprintf('  ✔ Test 7: edsCompositionProfile — Width=3, directional profile preserved\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 7: edsCompositionProfile Width=3: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  8. edsCompositionProfile — degenerate: start == end → graceful output
% ════════════════════════════════════════════════════════════════════════
try
    H = 20; W = 20;
    FeMap = ones(H, W) * 50;
    OMap  = ones(H, W) * 50;

    % Same start and end point
    prof = imaging.eds.edsCompositionProfile({FeMap, OMap}, {'Fe', 'O'}, ...
        10, 10, 10, 10);

    assert(isstruct(prof), 'Must return a struct even for degenerate case');
    assert(isfield(prof, 'distance'),  'Missing field: distance');
    assert(isfield(prof, 'atomicPct'), 'Missing field: atomicPct');

    % Either zero-length or single-point profile is acceptable
    n = numel(prof.distance);
    assert(n == 0 || n >= 1, 'Distance vector must be empty or have ≥1 points');

    nPass = nPass + 1;
    fprintf('  ✔ Test 8: edsCompositionProfile — degenerate start==end, no error\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 8: edsCompositionProfile degenerate: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  TEST 9: fanoResolution — Fiori-Newbury detector resolution model
% ════════════════════════════════════════════════════════════════════════
try
    % Anchor: the curve passes exactly through (5.899 keV, 130 eV)
    f0 = imaging.eds.fanoResolution(5.899);
    assert(abs(f0 - 130.0) < 1e-9, 'Mn-Ka anchor: got %.6f eV', f0);

    % Monotone in energy: Cu-Ka broader than Mn-Ka, O-Ka narrower
    fCu = imaging.eds.fanoResolution(8.048);
    fO  = imaging.eds.fanoResolution(0.525);
    assert(fCu > 130.0 && fO < 130.0, 'FWHM not monotone in energy');

    % sigma output consistent: sigmaKeV = fwhmEV/2.3548/1000
    [fw, sg] = imaging.eds.fanoResolution([0.525 5.899 8.048]);
    assert(max(abs(sg - fw / (2*sqrt(2*log(2))) / 1000)) < 1e-15, ...
        'sigmaKeV inconsistent with fwhmEV');
    assert(isequal(size(fw), [1 3]), 'array shape not preserved');

    % Clamp: far-below-reference energy returns a real, non-negative width
    fLow = imaging.eds.fanoResolution(1e-6, 'RefFwhmEV', 1);
    assert(isreal(fLow) && fLow >= 0, 'variance clamp failed');

    nPass = nPass + 1;
    fprintf('  ✔ Test 9: fanoResolution — anchor, monotonicity, sigma, clamp\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 9: fanoResolution: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  TEST 10: mapIsBlank — coverage-based blank-map discrimination
% ════════════════════════════════════════════════════════════════════════
try
    H = 100; W = 100;

    % 50 pixels at 100 at% out of 10000 = 0.5% coverage -> blank
    mSparse = zeros(H, W);
    mSparse(1:50) = 100;
    assert(imaging.eds.mapIsBlank(mSparse), ...
        '0.5%% coverage at 100 at%% must be judged blank');

    % Same map but 5% coverage (500 px) -> not blank
    mCovered = zeros(H, W);
    mCovered(1:500) = 100;
    assert(~imaging.eds.mapIsBlank(mCovered), ...
        '5%% coverage at 100 at%% must NOT be judged blank');

    % All-NaN map -> blank (NaN never satisfies > ValueThreshold)
    mNaN = nan(H, W);
    assert(imaging.eds.mapIsBlank(mNaN), 'all-NaN map must be judged blank');

    % Uniform 100 at% map (single-element quant, 100% coverage) -> NOT blank
    mUniform = ones(H, W) * 100;
    assert(~imaging.eds.mapIsBlank(mUniform), ...
        'a present-everywhere (100%% coverage) map must NOT be judged blank');

    nPass = nPass + 1;
    fprintf('  ✔ Test 10: mapIsBlank — sparse spike, coverage, all-NaN, uniform\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 10: mapIsBlank: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  TEST 11: toKeV — eV/keV/unknown-unit energy-axis normalization
% ════════════════════════════════════════════════════════════════════════
try
    eaxEV = [0; 1000; 8048; 20000];

    eaxKeV = imaging.eds.toKeV(eaxEV, 'eV');
    assert(max(abs(eaxKeV - eaxEV/1000)) < 1e-12, 'eV axis must be divided by 1000');

    [eaxSame, unitsOut, converted] = imaging.eds.toKeV(eaxKeV, 'keV');
    assert(isequal(eaxSame, eaxKeV), 'keV axis must pass through unchanged');
    assert(strcmpi(unitsOut, 'keV'), 'keV units must pass through unchanged');
    assert(~converted, 'keV input must report converted=false');

    [eaxUnk, unitsUnk, convertedUnk] = imaging.eds.toKeV(eaxEV, 'furlongs');
    assert(isequal(eaxUnk, eaxEV), 'unknown units must pass the axis through unchanged');
    assert(strcmp(unitsUnk, 'furlongs'), 'unknown units string must be returned unchanged');
    assert(~convertedUnk, 'unknown units must report converted=false');

    [~, unitsEmpty, convertedEmpty] = imaging.eds.toKeV(eaxEV, '');
    assert(strcmp(unitsEmpty, ''), 'empty units must pass through unchanged');
    assert(~convertedEmpty, 'empty units must report converted=false');

    nPass = nPass + 1;
    fprintf('  ✔ Test 11: toKeV — eV division, keV/unknown/empty passthrough\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 11: toKeV: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════
%  TEST 12: extractElementMaps Units='ev' fixes an eV-axis/keV-window
%  mismatch — without it, the window silently selects ~no channels and the
%  map comes back blank rather than raising (the shipped Python-port bug).
% ════════════════════════════════════════════════════════════════════════
try
    C = 2001;
    eaxEV = linspace(0, 20000, C)';   % eV-calibrated axis, 10 eV/channel
    peakEV = 8048;                    % Cu Kalpha, in eV
    sigmaEV = 60;
    profile = exp(-0.5 * ((eaxEV - peakEV) / sigmaEV).^2);

    Hc = 4; Wc = 4;
    cube = repmat(reshape(profile, 1, 1, C), Hc, Wc, 1) * 1000;

    mapsNoUnits = imaging.eds.extractElementMaps(cube, eaxEV, {'Cu'});
    mapsEV      = imaging.eds.extractElementMaps(cube, eaxEV, {'Cu'}, Units='eV');

    assert(isscalar(mapsEV), 'Units=eV path must find the Cu line within range');
    totalEV = mapsEV(1).total;
    assert(totalEV > 0, 'Units=eV map must have nonzero signal at the planted peak');

    assert(isscalar(mapsNoUnits), ...
        'unconverted-axis path still finds the line by name (window is just wrong)');
    totalNoUnits = mapsNoUnits(1).total;
    assert(totalNoUnits == 0, ...
        'without Units, the eV-scaled axis must select ~no channels vs the keV window');

    nPass = nPass + 1;
    fprintf('  ✔ Test 12: extractElementMaps Units=eV fixes eV-axis/keV-window mismatch\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 12: extractElementMaps Units integration: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════════

catch fatalErr
    fprintf('  ✘ FATAL error in test harness: %s\n', fatalErr.message);
    nFail = nFail + 1;
end

% ── Summary ──────────────────────────────────────────────────────────────
fprintf('\n═══ Results: %d passed, %d failed ═══\n\n', nPass, nFail);

if nFail > 0
    error('test_eds_quantification:failures', '%d test(s) failed.', nFail);
end
