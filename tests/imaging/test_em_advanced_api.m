%TEST_EM_ADVANCED_API  Headless API tests for FermiViewer advanced analyses:
%                      virtualDarkField (api.virtualDarkField), EELS
%                      Fourier-log deconvolution (api.eelsDeconvolve),
%                      Kramers-Kronig analysis (api.eelsKramersKronig),
%                      and ELNES extraction (api.eelsELNES).
%
%   The pure +imaging/ functions are unit-tested separately in
%   test_eels_advanced.m and test_diffraction_sim.m. This suite covers the
%   FermiViewer GUI wrappers using a synthetic TIFF + injected EELS spectrum.
%
%   Run:
%       run tests/imaging/test_em_advanced_api
%       runAllTests(Group="emgui")

fprintf('\n');
fprintf('╔══════════════════════════════════════════════════════════════╗\n');
fprintf('║      FermiViewer Advanced API — VDF + EELS deconv + KK         ║\n');
fprintf('╚══════════════════════════════════════════════════════════════╝\n');

ROOT = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(ROOT);

tmpDir = fullfile(tempdir, sprintf('emadvapi_test_%s', datestr(now, 'yyyymmdd_HHMMSS')));
mkdir(tmpDir);
cleanupDir = onCleanup(@() rmdir(tmpDir, 's'));

passed = 0;
failed = 0;

% Synthetic sinusoidal grating (strong single spatial frequency → clean
% FFT spots at fixed offsets from center).
N = 128;
[X, Y] = meshgrid(1:N, 1:N);
img = uint16(32000 + 20000 * sin(2*pi*X/8));
fImg = fullfile(tmpDir, 'grating.tif');
imwrite(img, fImg);

function api = launchHeadless()
    api = FermiViewer();
    api.fig.Visible = 'off';
    drawnow;
end

function safeClose(api)
    try
        if isvalid(api.fig), api.close(); end
    catch
    end
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 1: api.virtualDarkField runs on a real loaded image
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 1: virtualDarkField ══\n');
try
    api = launchHeadless();
    cleanupApi = onCleanup(@() safeClose(api));
    api.loadImages({fImg});

    center = [N/2 + 1, N/2 + 1 + 16];   % one of the grating spots
    api.virtualDarkField(center, 6);

    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 2: eelsDeconvolve is graceful with no data loaded
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 2: eelsDeconvolve graceful (no data) ══\n');
try
    api = launchHeadless();
    cleanupApi = onCleanup(@() safeClose(api));
    api.loadImages({fImg});

    % No EELS data injected — should short-circuit cleanly
    api.eelsDeconvolve();
    assert(isempty(api.getEELSSSD()), 'SSD should remain empty without data');

    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 3: eelsDeconvolve populates SSD on injected spectrum
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 3: eelsDeconvolve with injected spectrum ══\n');
try
    api = launchHeadless();
    cleanupApi = onCleanup(@() safeClose(api));
    api.loadImages({fImg});

    % Build a synthetic low-loss spectrum: ZLP + plasmon + 2nd-order plasmon
    nE = 512;
    E  = linspace(-5, 100, nE)';
    dE = E(2) - E(1);
    ZLP = exp(-E.^2 / (2*0.5^2));
    ZLP = ZLP / (sum(ZLP)*dE);
    p1 = exp(-(E - 15).^2 / (2*3^2));
    p1 = p1 / (sum(p1)*dE);
    p2 = exp(-(E - 30).^2 / (2*(3*sqrt(2))^2));
    p2 = p2 / (sum(p2)*dE);
    I  = ZLP + 0.4*p1 + 0.15*0.16*p2;

    api.injectEELSData(E, I);
    assert(~isempty(api.getEELSData()), 'injectEELSData should populate eelsData');

    api.eelsDeconvolve();
    ssd = api.getEELSSSD();
    assert(~isempty(ssd), 'SSD should be populated after deconvolve');
    assert(~any(isnan(ssd(:))) && ~any(isinf(ssd(:))), 'SSD should be finite');
    assert(numel(ssd) == numel(E), 'SSD should have same length as energy axis');

    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 4: eelsKramersKronig graceful (no data)
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 4: eelsKramersKronig graceful (no data) ══\n');
try
    api = launchHeadless();
    cleanupApi = onCleanup(@() safeClose(api));
    api.loadImages({fImg});

    api.eelsKramersKronig();
    assert(isempty(api.getEELSKKResult()), 'KK result should be empty without data');

    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 5: eelsKramersKronig populates KK result on injected Drude ELF
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 5: eelsKramersKronig with injected Drude ELF ══\n');
try
    api = launchHeadless();
    cleanupApi = onCleanup(@() safeClose(api));
    api.loadImages({fImg});

    % Drude-like loss function for a plasmon at 15 eV
    nE = 512;
    E  = linspace(0.1, 80, nE)';
    Ep = 15;  gamma = 2;
    ELF = (E*gamma*Ep^2) ./ ((E.^2 - Ep^2).^2 + (E*gamma).^2);

    api.injectEELSData(E, ELF);
    api.eelsKramersKronig();

    res = api.getEELSKKResult();
    assert(~isempty(res), 'KK result should be populated');
    assert(isfield(res, 'eps1') && isfield(res, 'eps2'), ...
        'KK result should contain eps1 and eps2');
    assert(numel(res.eps1) == nE, 'eps1 length mismatch');
    assert(~any(isnan(res.eps1)) && ~any(isnan(res.eps2)), 'eps should be finite');

    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 6: eelsELNES runs on injected core-loss spectrum
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 6: eelsELNES with injected O-K edge ══\n');
try
    api = launchHeadless();
    cleanupApi = onCleanup(@() safeClose(api));
    api.loadImages({fImg});

    % Synthetic O-K edge at 532 eV: inverse-power-law pre-edge background
    % plus a step + broad white-line peak above the onset.
    nE = 600;
    E  = linspace(450, 650, nE)';
    bg  = 1e6 * (E.^(-3));
    edge = 0.3 * (E > 532) .* (1 + 2*exp(-((E - 538).^2)/(2*3^2)));
    I = bg + edge;

    api.injectEELSData(E, I);
    api.eelsELNES(532);    % must run without error; result storage optional

    fprintf('  PASS\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ── Summary ────────────────────────────────────────────────────────────
fprintf('\n');
fprintf('╔══════════════════════════════════════════════════════════════╗\n');
fprintf('║ Results: %2d passed, %2d failed                                ║\n', passed, failed);
fprintf('╚══════════════════════════════════════════════════════════════╝\n');

if failed > 0
    error('test_em_advanced_api: %d test(s) failed', failed);
end
