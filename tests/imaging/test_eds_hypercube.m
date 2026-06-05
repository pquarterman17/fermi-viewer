%TEST_EDS_HYPERCUBE  EDS SpectrumData0 cube decode + imaging.eds map helpers.
%   Run standalone: cd tests; run imaging/test_eds_hypercube
%   Run via group:  runAllTests(Group="eds")

clear; clc;
thisDir = fileparts(mfilename('fullpath'));
rootDir = fileparts(fileparts(thisDir));
if ~contains(path, rootDir), addpath(rootDir); end

% over16bit_compressed.bcf: AACS-compressed, 3x4 map, instructive packing,
% per-pixel counts exceeding 16-bit (forces uint32). Ground-truth cube total
% verified against HyperSpy/RosettaSciIO's py_parse_hypermap reference.
BCF = fullfile(rootDir, '+test_datasets', 'BCF', 'over16bit_compressed.bcf');
EXPECTED_TOTAL = 176786251;
EXPECTED_SIZE  = [3 4 4096];

passed = 0; failed = 0;
check = @(cond, msg) deal(cond, msg);

% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 1: Cube decodes with correct shape/dtype/total ══\n');
try
    d   = parser.importBCF(BCF);
    eds = d.metadata.parserSpecific.edsData;
    assert(~isempty(eds.cube), 'cube empty');
    assert(isequal(eds.cubeSize, EXPECTED_SIZE), ...
        sprintf('cubeSize [%s] != [%s]', num2str(eds.cubeSize), num2str(EXPECTED_SIZE)));
    assert(isequal(size(eds.cube), EXPECTED_SIZE), 'size(cube) mismatch');
    assert(isa(eds.cube, 'uint32'), ...
        sprintf('expected uint32 (>16-bit counts), got %s', class(eds.cube)));
    tot = sum(double(eds.cube(:)));
    assert(tot == EXPECTED_TOTAL, sprintf('cube total %d != %d', tot, EXPECTED_TOTAL));
    fprintf('  cube [%s] %s, total=%d\n', num2str(eds.cubeSize), class(eds.cube), tot);
    fprintf('  PASS\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 2: Sum spectrum == cube summed over pixels (self-consistency) ══\n');
try
    d   = parser.importBCF(BCF);
    eds = d.metadata.parserSpecific.edsData;
    assert(numel(eds.sumSpectrum) == EXPECTED_SIZE(3), 'sumSpectrum length wrong');
    assert(numel(eds.energyAxis)  == EXPECTED_SIZE(3), 'energyAxis length wrong');
    cubeSum = squeeze(sum(sum(double(eds.cube), 1), 2));
    assert(isequal(round(cubeSum), round(eds.sumSpectrum(:))), ...
        'sumSpectrum disagrees with cube column-sum');
    % ROI-over-all-pixels spectrum must equal the sum spectrum exactly
    mask = true(EXPECTED_SIZE(1), EXPECTED_SIZE(2));
    spAll = imaging.eds.pixelSpectrum(eds.cube, mask);
    assert(isequal(round(spAll), round(eds.sumSpectrum(:))), 'ROI(all) != sumSpectrum');
    fprintf('  PASS\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 3: LoadCube=false skips cube; MaxCubeBytes cap honoured ══\n');
try
    d0 = parser.importBCF(BCF, LoadCube=false);
    assert(isempty(d0.metadata.parserSpecific.edsData.cube), 'LoadCube=false still made a cube');
    % Tiny cap -> cube skipped with a warning, image still returned
    ws = warning('off', 'parser:importBCF:cubeTooLarge'); clean = onCleanup(@() warning(ws));
    d1 = parser.importBCF(BCF, MaxCubeBytes=1);
    assert(isempty(d1.metadata.parserSpecific.edsData.cube), 'MaxCubeBytes cap not honoured');
    fprintf('  PASS\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 4: lineEnergy values + voltage-aware auto selection ══\n');
try
    tol = 1e-3;
    assert(abs(imaging.eds.lineEnergy('Cu') - 8.048) < tol, 'Cu Ka');
    assert(abs(imaging.eds.lineEnergy('Fe') - 6.404) < tol, 'Fe Ka');
    assert(abs(imaging.eds.lineEnergy('O')  - 0.525) < tol, 'O Ka');
    [e,l] = imaging.eds.lineEnergy('Au', Line='M');
    assert(abs(e - 2.123) < tol && strcmp(l,'M'), 'Au Ma forced');
    [e,l] = imaging.eds.lineEnergy('W', BeamKV=15);
    assert(abs(e - 1.775) < tol && strcmp(l,'M'), 'W @15kV should be Ma');
    [e,l] = imaging.eds.lineEnergy('W', BeamKV=300);
    assert(abs(e - 8.398) < tol && strcmp(l,'L'), 'W @300kV should be La');
    assert(isnan(imaging.eds.lineEnergy('Zz')), 'unknown element should be NaN');
    fprintf('  PASS\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 5: elementMap window integration + linear background (synthetic) ══\n');
try
    % 2x2 map, 11 channels at 0..10 keV. Flat background of 2 counts/chan
    % everywhere, plus a peak of +10 at channel 5 (5 keV) in pixel (1,1).
    C = 11; eax = (0:C-1)';
    cube = 2 * ones(2, 2, C);
    cube(1,1,6) = cube(1,1,6) + 10;   % channel index 6 == 5 keV (0-based 5)
    % Window [4.5 5.5] -> just channel @5 keV. Raw sum: bg(2) + peak in (1,1).
    [mRaw, info] = imaging.eds.elementMap(cube, eax, 4.5, 5.5, Background='none');
    assert(isequal(info.peakChans, 6), 'peak channel index');
    assert(mRaw(1,1) == 12 && mRaw(2,2) == 2, 'raw window sum wrong');
    % Linear background should remove the flat continuum -> ~10 at (1,1), ~0 else.
    mNet = imaging.eds.elementMap(cube, eax, 4.5, 5.5, Background='linear', BgWidth=1);
    assert(abs(mNet(1,1) - 10) < 1e-9, sprintf('net peak %.3f != 10', mNet(1,1)));
    assert(all(mNet(2:end) < 1e-9), 'net background not removed');
    fprintf('  PASS\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 6: extractElementMaps from identified elements (Hitachi) ══\n');
try
    HIT = fullfile(rootDir, '+test_datasets', 'BCF', 'Hitachi_TM3030Plus.bcf');
    d   = parser.importBCF(HIT);
    eds = d.metadata.parserSpecific.edsData;
    assert(~isempty(eds.elements), 'no elements extracted from Hitachi file');
    assert(any(strcmp(eds.elements, 'Cu')), 'expected Cu among elements');
    assert(numel(eds.elementZ) == numel(eds.elements), 'elementZ/elements length mismatch');
    maps = imaging.eds.extractElementMaps(eds.cube, eds.energyAxis, eds.elements);
    assert(~isempty(maps), 'no element maps produced');
    assert(isequal(size(maps(1).map), eds.cubeSize(1:2)), 'map size != cube HxW');
    fprintf('  elements {%s}; %d maps\n', strjoin(eds.elements, ','), numel(maps));
    fprintf('  PASS\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 7: decodeBcfCube guards (empty / tiny buffer) ══\n');
try
    c = parser.decodeBcfCube(uint8([]), 16);
    assert(isempty(c), 'empty buffer should give empty cube');
    c = parser.decodeBcfCube(uint8(1:4), 16);
    assert(isempty(c), 'sub-header buffer should give empty cube');
    fprintf('  PASS\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
fprintf('\n\n══════════════════════════════════════════\n');
fprintf('  test_eds_hypercube: %d passed, %d failed\n', passed, failed);
fprintf('══════════════════════════════════════════\n');
if failed > 0
    error('test_eds_hypercube:failures', '%d test(s) failed.', failed);
end
