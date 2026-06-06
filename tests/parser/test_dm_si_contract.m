%TEST_DM_SI_CONTRACT  DM4 format-contract tests via synthetic fixtures.
%
%   CI-runnable regression coverage for the 2026-06-06 real-data bugs,
%   using writeMiniDM4 fixtures instead of large instrument files:
%     - energy-dimension detection in 3D SI cubes (energy-last GMS
%       layout, energy-first legacy layout, no-units fallback)
%     - DM calibration convention value = (index − origin) × scale
%     - cube orientation: voxels encode their own (x, y, E) position, so
%       any transposition produces wrong values, not just wrong sizes
%     - inline (<1000 elements) and offset-record (>1000) Data paths
%
%   Run standalone:  cd tests; run parser/test_dm_si_contract
%   Run via group:   runAllTests(Group="parser")

clear; clc;
fprintf('\n═══ test_dm_si_contract ═══\n');

thisDir = fileparts(mfilename('fullpath'));
rootDir = fileparts(fileparts(thisDir));
if ~contains(path, rootDir)
    addpath(rootDir);
end
addpath(thisDir);   % writeMiniDM4 lives next to this test

nPass = 0;
nFail = 0;
nSkip = 0;

tmpFiles = {};
cleanupTmp = onCleanup(@() cellfun(@(f) delete(f), tmpFiles, 'UniformOutput', false));

% Voxel value encodes its own position: v(x,y,e) = x + 10*y + 100*e
% (0-based x/y/e; small dims keep values inside uint16).
encode = @(x, y, e) x + 10*y + 100*e;

try  % outer guard

% ════════════════════════════════════════════════════════════════════
%  1. 3D SI, energy LAST (real GMS layout): dims = [Nx Ny nE] = [4 3 5],
%     'eV' units on dimension 2. Every voxel checked by position.
% ════════════════════════════════════════════════════════════════════
try
    Nx = 4; Ny = 3; nE = 5;
    [xg, yg, eg] = ndgrid(0:Nx-1, 0:Ny-1, 0:nE-1);   % d0 fastest = file order
    spec.dims     = [Nx, Ny, nE];
    spec.data     = encode(xg, yg, eg);
    spec.dataType = 10;   % uint16
    spec.cal = struct( ...
        'scale',  {0.5,  0.5,  0.05}, ...
        'origin', {0,    0,    40}, ...
        'units',  {'nm', 'nm', 'eV'});

    f = [tempname '.dm4'];  tmpFiles{end+1} = f;
    writeMiniDM4(f, spec);
    data = parser.importDM4(f);
    si = data.metadata.parserSpecific.spectrumImage;

    assert(si.nChannels == nE && si.Nx == Nx && si.Ny == Ny, ...
        sprintf('dims: got Ny=%d Nx=%d nE=%d', si.Ny, si.Nx, si.nChannels));

    expected = zeros(Ny, Nx, nE);
    for e = 0:nE-1
        for y = 0:Ny-1
            for x = 0:Nx-1
                expected(y+1, x+1, e+1) = encode(x, y, e);
            end
        end
    end
    assert(isequal(double(si.cube), expected), ...
        'cube voxels misplaced — orientation/transposition bug');

    % DM convention: value = (index − origin) × scale → starts at −2 eV
    assert(abs(si.energyScale - 0.05) < 1e-12, 'energy scale wrong');
    assert(abs(si.energyAxis(1) - (-40*0.05)) < 1e-9, ...
        sprintf('energy axis starts at %.3f — origin convention broken', si.energyAxis(1)));
    assert(strcmp(si.energyUnit, 'eV'), 'energy unit not read from dim 2');
    assert(abs(si.pixelSize - 0.5) < 1e-12 && strcmp(si.pixelUnit, 'nm'), ...
        'spatial calibration not taken from spatial dim');

    nPass = nPass + 1;
    fprintf('  ✔ Test 1: energy-last SI — voxel-exact cube, origin convention OK\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 1: energy-last SI: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════
%  2. 3D SI, energy FIRST (legacy layout): dims = [nE Nx Ny] = [5 4 3],
%     'eV' units on dimension 0, single-precision data path.
% ════════════════════════════════════════════════════════════════════
try
    Nx = 4; Ny = 3; nE = 5;
    [eg, xg, yg] = ndgrid(0:nE-1, 0:Nx-1, 0:Ny-1);   % d0 = energy, fastest
    spec = struct();
    spec.dims     = [nE, Nx, Ny];
    spec.data     = encode(xg, yg, eg);
    spec.dataType = 2;    % single
    spec.cal = struct( ...
        'scale',  {0.05, 0.5,  0.5}, ...
        'origin', {40,   0,    0}, ...
        'units',  {'eV', 'nm', 'nm'});

    f = [tempname '.dm4'];  tmpFiles{end+1} = f;
    writeMiniDM4(f, spec);
    data = parser.importDM4(f);
    si = data.metadata.parserSpecific.spectrumImage;

    assert(si.nChannels == nE && si.Nx == Nx && si.Ny == Ny, ...
        sprintf('dims: got Ny=%d Nx=%d nE=%d', si.Ny, si.Nx, si.nChannels));
    ok = true;
    for e = 0:nE-1
        for y = 0:Ny-1
            for x = 0:Nx-1
                ok = ok && (double(si.cube(y+1, x+1, e+1)) == encode(x, y, e));
            end
        end
    end
    assert(ok, 'cube voxels misplaced in energy-first layout');
    assert(abs(si.energyAxis(1) - (-2)) < 1e-6, 'origin convention broken (energy-first)');

    nPass = nPass + 1;
    fprintf('  ✔ Test 2: energy-first SI — legacy layout still decodes correctly\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 2: energy-first SI: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════
%  3. 3D SI with NO energy units anywhere → fallback picks the GMS
%     layout (energy = last dimension).
% ════════════════════════════════════════════════════════════════════
try
    Nx = 4; Ny = 3; nE = 5;
    [xg, yg, eg] = ndgrid(0:Nx-1, 0:Ny-1, 0:nE-1);
    spec = struct();
    spec.dims     = [Nx, Ny, nE];
    spec.data     = encode(xg, yg, eg);
    spec.dataType = 10;
    spec.cal = struct( ...
        'scale',  {0.5,  0.5,  1}, ...
        'origin', {0,    0,    0}, ...
        'units',  {'nm', 'nm', ''});

    f = [tempname '.dm4'];  tmpFiles{end+1} = f;
    writeMiniDM4(f, spec);
    data = parser.importDM4(f);
    si = data.metadata.parserSpecific.spectrumImage;

    assert(si.nChannels == nE, ...
        sprintf('fallback chose wrong energy dim (nE=%d)', si.nChannels));
    assert(double(si.cube(2, 3, 4)) == encode(2, 1, 3), 'fallback cube misplaced');

    nPass = nPass + 1;
    fprintf('  ✔ Test 3: no-units fallback — defaults to energy-last\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 3: no-units fallback: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════
%  4. 1D spectrum with nonzero origin: ZLP-like peak must land at 0 eV.
% ════════════════════════════════════════════════════════════════════
try
    nCh = 64;  zlpCh = 20;
    counts = round(1000 * exp(-((0:nCh-1) - zlpCh).^2 / 8)) + 1;
    spec = struct();
    spec.dims     = nCh;
    spec.data     = counts;
    spec.dataType = 10;
    spec.cal = struct('scale', 0.05, 'origin', zlpCh, 'units', 'eV');

    f = [tempname '.dm4'];  tmpFiles{end+1} = f;
    writeMiniDM4(f, spec);
    data = parser.importDM4(f);
    sp = data.metadata.parserSpecific.spectrumData;

    assert(sp.nChannels == nCh, 'channel count wrong');
    assert(abs(min(sp.energyAxis) - (-zlpCh*0.05)) < 1e-9, ...
        sprintf('axis starts at %.3f, expected %.3f', min(sp.energyAxis), -zlpCh*0.05));
    [~, pk] = max(sp.counts);
    assert(abs(sp.energyAxis(pk)) < 1e-9, ...
        sprintf('peak at %.3f eV — origin convention broken in 1D', sp.energyAxis(pk)));

    nPass = nPass + 1;
    fprintf('  ✔ Test 4: 1D spectrum — nonzero origin puts peak at 0 eV\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 4: 1D origin convention: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════
%  5. Large-array offset-record path (>1000 elements) — same contract.
% ════════════════════════════════════════════════════════════════════
try
    Nx = 9; Ny = 8; nE = 16;    % 1152 voxels > LARGE_ARRAY_THRESHOLD
    [xg, yg, eg] = ndgrid(0:Nx-1, 0:Ny-1, 0:nE-1);
    spec = struct();
    spec.dims     = [Nx, Ny, nE];
    spec.data     = encode(xg, yg, eg);
    spec.dataType = 10;
    spec.cal = struct( ...
        'scale',  {1, 1, 0.1}, ...
        'origin', {0, 0, 0}, ...
        'units',  {'nm', 'nm', 'eV'});

    f = [tempname '.dm4'];  tmpFiles{end+1} = f;
    writeMiniDM4(f, spec);
    data = parser.importDM4(f);
    si = data.metadata.parserSpecific.spectrumImage;

    assert(si.nChannels == nE && si.Nx == Nx && si.Ny == Ny, 'dims wrong (offset path)');
    assert(double(si.cube(8, 9, 16)) == encode(8, 7, 15), 'corner voxel misplaced');
    assert(double(si.cube(1, 1, 1)) == encode(0, 0, 0), 'origin voxel misplaced');
    % Sum spectrum must equal cube column-sum (pipeline self-consistency)
    cubeSum = squeeze(sum(sum(double(si.cube), 1), 2));
    assert(isequal(cubeSum, si.sumSpectrum), 'sumSpectrum != cube sum');

    nPass = nPass + 1;
    fprintf('  ✔ Test 5: offset-record Data path — voxel-exact at 1152 elements\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 5: offset-record path: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════
%  6. 2D image backward-compat: pixels(y+1, x+1) orientation unchanged.
% ════════════════════════════════════════════════════════════════════
try
    W = 6; H = 4;
    [xg, yg] = ndgrid(0:W-1, 0:H-1);
    spec = struct();
    spec.dims     = [W, H];
    spec.data     = encode(xg, yg, 0);
    spec.dataType = 10;
    spec.cal = struct('scale', {0.2, 0.2}, 'origin', {0, 0}, 'units', {'nm', 'nm'});

    f = [tempname '.dm4'];  tmpFiles{end+1} = f;
    writeMiniDM4(f, spec);
    data = parser.importDM4(f);
    img = data.metadata.parserSpecific.imageData;

    assert(img.width == W && img.height == H, 'image dims wrong');
    assert(double(img.pixels(3, 5)) == encode(4, 2, 0), '2D pixel orientation changed');
    assert(abs(img.pixelSize - 0.2) < 1e-12, '2D pixel calibration lost');

    nPass = nPass + 1;
    fprintf('  ✔ Test 6: 2D image — orientation and calibration unchanged\n');
catch ME
    nFail = nFail + 1;
    fprintf('  ✘ Test 6: 2D backward compat: %s\n', ME.message);
end

% ════════════════════════════════════════════════════════════════════

catch fatalErr
    fprintf('  ✘ FATAL error in test harness: %s\n', fatalErr.message);
    nFail = nFail + 1;
end

% ── Summary ──────────────────────────────────────────────────────────
fprintf('\n═══ Results: %d passed, %d failed, %d skipped ═══\n\n', ...
    nPass, nFail, nSkip);

if nFail > 0
    error('test_dm_si_contract:failures', '%d test(s) failed.', nFail);
end
