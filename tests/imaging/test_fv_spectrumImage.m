%TEST_FV_SPECTRUMIMAGE  Headless tests for the EDS Spectrum Image workshop.
%   Run standalone: cd tests; run imaging/test_fv_spectrumImage
%   Run via group:  runAllTests(Group="fvgui")
%
%   Drives fermiViewer.spectrumImage.openSpectrumImageWorkshop via its api
%   (no mouse events) and checks the launch adaptor's guards.

clear; clc;
thisDir = fileparts(mfilename('fullpath'));
rootDir = fileparts(fileparts(thisDir));
if ~contains(path, rootDir), addpath(rootDir); end

BCF = fullfile(rootDir, '+test_datasets', 'BCF', 'over16bit_compressed.bcf');

passed = 0; failed = 0;
figsToClose = {};

% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 1: Workshop opens from a decoded cube; window→map ══\n');
try
    d   = parser.importBCF(BCF);
    eds = d.metadata.parserSpecific.edsData;
    api = fermiViewer.spectrumImage.openSpectrumImageWorkshop(eds);
    figsToClose{end+1} = api.fig;
    assert(isgraphics(api.fig), 'no figure');
    api.setWindow(1.0, 2.0);
    w = api.getWindow();
    assert(abs(w(1)-1.0) < 1e-6 && abs(w(2)-2.0) < 1e-6, 'window not set');
    m = api.getMap();
    assert(isequal(size(m), eds.cubeSize(1:2)), 'map size != cube HxW');
    % Map for a window must equal a direct elementMap call.
    ref = imaging.eds.elementMap(eds.cube, eds.energyAxis, 1.0, 2.0, Background='linear');
    assert(isequaln(m, ref), 'workshop map disagrees with elementMap');
    fprintf('  PASS\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 2: Pixel / ROI / sum spectrum selection ══\n');
try
    d   = parser.importBCF(BCF);
    eds = d.metadata.parserSpecific.edsData;
    api = fermiViewer.spectrumImage.openSpectrumImageWorkshop(eds);
    figsToClose{end+1} = api.fig;
    H = eds.cubeSize(1); W = eds.cubeSize(2);
    api.selectPixel(1, 1);
    s1 = api.getSpectrum();
    assert(isequal(round(s1(:)), round(double(squeeze(eds.cube(1,1,:))))), 'pixel spectrum mismatch');
    api.selectROI(1, 1, H, W);
    sROI = api.getSpectrum();
    assert(isequal(round(sROI(:)), round(eds.sumSpectrum(:))), 'full ROI != sum spectrum');
    api.showSum();
    sSum = api.getSpectrum();
    assert(isequal(round(sSum(:)), round(eds.sumSpectrum(:))), 'showSum != sum spectrum');
    fprintf('  PASS\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 3: Element selection snaps window; background toggle ══\n');
try
    HIT = fullfile(rootDir, '+test_datasets', 'BCF', 'Hitachi_TM3030Plus.bcf');
    d   = parser.importBCF(HIT);
    eds = d.metadata.parserSpecific.edsData;
    api = fermiViewer.spectrumImage.openSpectrumImageWorkshop(eds);
    figsToClose{end+1} = api.fig;
    api.selectElement('Cu');
    w = api.getWindow();
    eCu = imaging.eds.lineEnergy('Cu');
    assert(w(1) < eCu && w(2) > eCu, 'window does not bracket Cu line');
    mLin = api.getMap();
    api.setBackground('none');
    mNone = api.getMap();
    assert(sum(mNone(:)) >= sum(mLin(:)) - 1e-6, 'raw map should be >= bg-subtracted');
    fprintf('  PASS\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 4: CSV export round-trips ══\n');
try
    d   = parser.importBCF(BCF);
    eds = d.metadata.parserSpecific.edsData;
    api = fermiViewer.spectrumImage.openSpectrumImageWorkshop(eds);
    figsToClose{end+1} = api.fig;
    api.showSum();
    pMap  = [tempname '.csv'];
    pSpec = [tempname '.csv'];
    cMap  = onCleanup(@() delete(pMap));
    cSpec = onCleanup(@() delete(pSpec));
    api.exportMapCSV(pMap);
    api.exportSpectrumCSV(pSpec);
    M = readmatrix(pMap);
    assert(isequal(size(M), eds.cubeSize(1:2)), 'map CSV wrong size');
    S = readmatrix(pSpec);   % has a header row -> numeric body
    assert(size(S,2) == 2 && size(S,1) == numel(eds.energyAxis), 'spectrum CSV shape');
    fprintf('  PASS\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 5: launch() guards (no image / no cube) ══\n');
try
    % No active image
    a0 = fermiViewer.spectrumImage.launch(@() {}, @() 0, @(varargin) []);
    assert(isempty(a0), 'launch should return [] with no active image');
    % Image without a cube
    fake.metadata.parserSpecific.imageData.pixels = zeros(4,4,'uint8');
    a1 = fermiViewer.spectrumImage.launch(@() {fake}, @() 1, @(varargin) []);
    assert(isempty(a1), 'launch should return [] when image has no cube');
    % Image WITH a cube -> opens
    d = parser.importBCF(BCF);
    a2 = fermiViewer.spectrumImage.launch(@() {d}, @() 1, @(varargin) []);
    assert(~isempty(a2) && isgraphics(a2.fig), 'launch should open with a cube');
    figsToClose{end+1} = a2.fig;
    fprintf('  PASS\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ── cleanup ──────────────────────────────────────────────────────────────
for k = 1:numel(figsToClose)
    if isgraphics(figsToClose{k}), delete(figsToClose{k}); end
end

fprintf('\n\n══════════════════════════════════════════\n');
fprintf('  test_fv_spectrumImage: %d passed, %d failed\n', passed, failed);
fprintf('══════════════════════════════════════════\n');
if failed > 0
    error('test_fv_spectrumImage:failures', '%d test(s) failed.', failed);
end
