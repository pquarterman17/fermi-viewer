%TEST_DIFFRACTION_SIM  Unit tests for diffraction simulation, VDF, and ZAF.
%
%   Tests kinematic diffraction simulation, virtual dark-field imaging,
%   and ZAF-corrected EDS quantification.
%
%   Run:
%       run tests/test_diffraction_sim
%       runAllTests(Group="diff_sim")
%
%   Requires: +imaging/ package (simulateDiffraction, virtualDarkField,
%             zafCorrection)
%   All test data is synthetic — no files required.

fprintf('\n');
fprintf('╔══════════════════════════════════════════════════════════════╗\n');
fprintf('║     Diffraction Sim / VDF / ZAF — Unit Test Suite          ║\n');
fprintf('╚══════════════════════════════════════════════════════════════╝\n');

ROOT = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(ROOT);

passed = 0;
failed = 0;

% ══════════════════════════════════════════════════════════════════════════
fprintf('\nTest 1: simulateDiffraction Si [001] — expected spots present\n');
try
    res = imaging.simulateDiffraction('Si', 'ZoneAxis', [0 0 1], ...
        'AccVoltage', 200, 'CameraLength', 200);

    % Required output fields
    assert(isfield(res, 'image'), 'Missing field: image');
    assert(isfield(res, 'spots'), 'Missing field: spots');

    % At least 4 spots for a [001] pattern of Si (FCC: (220) family)
    assert(numel(res.spots) >= 4, ...
        sprintf('Too few spots: %d (expected >= 4)', numel(res.spots)));

    % Image must be square and non-empty
    [nr, nc] = size(res.image);
    assert(nr > 0 && nc > 0, 'image is empty');

    % (220) is allowed for FCC — check d-spacing list if provided
    % FCC extinction: h+k+l odd, or all mixed parity → (100) forbidden
    if isfield(res, 'dspacings')
        % d(220) for Si = 1.920 Å; d(100) ≈ 5.43 Å (forbidden)
        d_vals = [res.spots.d];
        d100_Si = 5.43;
        assert(~any(abs(d_vals - d100_Si) < 0.1), ...
            'Forbidden (100) reflection present for Si FCC');
    end

    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ══════════════════════════════════════════════════════════════════════════
fprintf('\nTest 2: simulateDiffraction Friedel symmetry\n');
try
    res = imaging.simulateDiffraction('Si', 'ZoneAxis', [0 0 1], ...
        'AccVoltage', 200, 'CameraLength', 200);

    [nr, nc] = size(res.image);
    ctr_r = (nr + 1) / 2;
    ctr_c = (nc + 1) / 2;

    % For each spot above threshold, check Friedel partner exists
    thresh = max(res.image(:)) * 0.05;
    [rows, cols] = find(res.image > thresh);

    symmetry_ok = true;
    for k = 1:numel(rows)
        r_friedel = round(2 * ctr_r - rows(k));
        c_friedel = round(2 * ctr_c - cols(k));
        if r_friedel < 1 || r_friedel > nr || c_friedel < 1 || c_friedel > nc
            continue;  % outside image — skip boundary spots
        end
        if res.image(r_friedel, c_friedel) <= thresh
            symmetry_ok = false;
            break;
        end
    end
    assert(symmetry_ok, 'Friedel symmetry violated: partner spot missing');

    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ══════════════════════════════════════════════════════════════════════════
fprintf('\nTest 3: virtualDarkField basic — sinusoidal grating\n');
try
    N = 128;
    [X, ~] = meshgrid(1:N, 1:N);
    freq = 8;   % cycles across image
    img = 0.5 + 0.5 * cos(2*pi*freq*X/N);   % grating, values in [0,1]
    img = img + 0.02 * randn(N, N);
    img = max(img, 0);

    % VDF using circle mask at grating frequency peak
    % FFT peak of grating at column N/freq = 16 (freq 8 in 128-px image)
    center = [N/2, N/2 + freq];   % approximate FFT peak [row, col] (DC shifted)
    vdf = imaging.virtualDarkField(img, 'MaskCenter', center, 'MaskRadius', 5);

    assert(~isempty(vdf), 'VDF output is empty');
    assert(isequal(size(vdf), size(img)), 'VDF size mismatch');
    assert(any(vdf(:) ~= 0), 'VDF is all zeros');

    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ══════════════════════════════════════════════════════════════════════════
fprintf('\nTest 4: virtualDarkField annulus vs circle — outputs differ\n');
try
    N = 128;
    [X, ~] = meshgrid(1:N, 1:N);
    freq = 8;
    img = 0.5 + 0.5 * cos(2*pi*freq*X/N) + 0.02*randn(N,N);
    img = max(img, 0);

    center = [N/2, N/2 + freq];
    vdf_circle  = imaging.virtualDarkField(img, 'MaskCenter', center, 'MaskRadius', 5);
    vdf_annulus = imaging.virtualDarkField(img, 'MaskCenter', center, ...
        'MaskRadius', 5, 'MaskShape', 'annulus', 'InnerRadius', 2);

    % The two masks should produce different results
    diff_rms = sqrt(mean((vdf_circle(:) - vdf_annulus(:)).^2));
    assert(diff_rms > 0, 'Circle and annulus VDF are identical — mask type ignored');

    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ══════════════════════════════════════════════════════════════════════════
fprintf('\nTest 5: zafCorrection convergence — result stable by iteration 10\n');
try
    % Simple 2-element Fe-O system, synthetic uniform maps
    N = 16;
    feMap = 0.6 * ones(N, N);   % 60% Fe signal
    oMap  = 0.4 * ones(N, N);   % 40% O signal

    res3  = imaging.zafCorrection({feMap, oMap}, {'Fe', 'O'}, ...
        'Thickness', 50, 'TakeOffAngle', 20, 'Iterations', 3);
    res10 = imaging.zafCorrection({feMap, oMap}, {'Fe', 'O'}, ...
        'Thickness', 50, 'TakeOffAngle', 20, 'Iterations', 10);

    % Mean atomic percent should converge within 0.5%
    for k = 1:2
        diff_k = abs(res3.meanAtomicPct(k) - res10.meanAtomicPct(k));
        assert(diff_k < 0.5, ...
            sprintf('ZAF not converged for element %d: iter3=%.2f%%, iter10=%.2f%%', ...
                k, res3.meanAtomicPct(k), res10.meanAtomicPct(k)));
    end

    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ══════════════════════════════════════════════════════════════════════════
fprintf('\nTest 6: zafCorrection zero-thickness — approaches Cliff-Lorimer\n');
try
    N = 16;
    feMap = 0.6 * ones(N, N);
    oMap  = 0.4 * ones(N, N);

    resZAF_thin = imaging.zafCorrection({feMap, oMap}, {'Fe', 'O'}, ...
        'Thickness', 0.0001, 'TakeOffAngle', 20);
    resCL = imaging.cliffLorimer({feMap, oMap}, {'Fe', 'O'});

    % For near-zero thickness, ZAF should match CL within 5%
    for k = 1:2
        diff_k = abs(resZAF_thin.meanAtomicPct(k) - resCL.meanAtomicPct(k));
        assert(diff_k < 5.0, ...
            sprintf('ZAF at zero thickness deviates from CL for element %d: ZAF=%.2f%%, CL=%.2f%%', ...
                k, resZAF_thin.meanAtomicPct(k), resCL.meanAtomicPct(k)));
    end

    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ══════════════════════════════════════════════════════════════════════════
fprintf('\nTest 7: massAbsorptionCoeff basic — positive values\n');
try
    % Fe absorber, O emitter
    mac_FeO = imaging.massAbsorptionCoeff('Fe', 'O');
    assert(mac_FeO > 0, ...
        sprintf('mac(Fe,O) = %.4g is not positive', mac_FeO));

    % Self-absorption: Fe in Fe
    mac_FeFe = imaging.massAbsorptionCoeff('Fe', 'Fe');
    assert(mac_FeFe > 0, ...
        sprintf('mac(Fe,Fe) = %.4g is not positive', mac_FeFe));

    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ══════════════════════════════════════════════════════════════════════════
%  SUMMARY
% ══════════════════════════════════════════════════════════════════════════
fprintf('\n');
fprintf('════════════════════════════════════════════════════\n');
fprintf('  Diffraction Sim / VDF / ZAF: %d passed, %d failed (of %d)\n', ...
    passed, failed, passed + failed);
fprintf('════════════════════════════════════════════════════\n\n');

if failed > 0
    error('test_diffraction_sim:failures', ...
        '%d test(s) failed in test_diffraction_sim.', failed);
end
