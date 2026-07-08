%TEST_SER_SPECTRA  SER 0x4120 spectrum/spectrum-image import (synthetic).
%
%   Pins the TIA spectrum path added to parser.importSER (port of the
%   Python fermiviewer ser.py 0x4120 support) using writeMiniSer synthetic
%   fixtures — the same analytic layout as the Python tests: channel c of
%   element k holds k*100 + c, energy_i = calOffset + (i - calElement)*
%   calDelta.
%
%   Covered: single spectrum (narrow + wide header), line profile, 2-D
%   spectrum image (cube orientation, survey, edsData contract), and the
%   0x4122 multi-frame warning.
%
%   Run standalone:  run tests/parser/test_ser_spectra
%   Run via group :  runAllTests(Group="parser")

clear; clc;
thisDir = fileparts(mfilename('fullpath'));
rootDir = fileparts(fileparts(thisDir));
if ~contains(path, rootDir), addpath(rootDir); end
if ~contains(path, thisDir), addpath(thisDir); end

fprintf('\n=== test_ser_spectra ===\n');
passed = 0; failed = 0;
tmpDir = tempdir();

% ════════════════════════════════════════════════════════════════════════
% 1. Single spectrum → 1-D struct with energy axis
% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 1: single 0x4120 spectrum ══\n');
try
    f = fullfile(tmpDir, 'ser_single.ser');
    info = writeMiniSer(f, ScanDims=[], NChannels=8);
    c1 = onCleanup(@() delete(f));

    d = parser.importSER(f);
    assert(~d.metadata.parserSpecific.isImage, 'single spectrum must not be an image');
    assert(isequal(d.values, (0:7)'), 'counts should be 0..7');
    assert(max(abs(d.time - info.energyAxis)) < 1e-12, 'energy axis mismatch');
    assert(strcmp(d.metadata.xColumnName, 'Energy'), 'xColumnName should be Energy');
    sd = d.metadata.parserSpecific.spectrumData;
    assert(isequal(sd.counts, (0:7)') && numel(sd.energyAxis) == 8, ...
        'spectrumData counts/energyAxis wrong');
    fprintf('  PASS\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
% 2. Wide header (version 0x0220, 64-bit offsets)
% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 2: single spectrum, wide (0x0220) header ══\n');
try
    f = fullfile(tmpDir, 'ser_wide.ser');
    writeMiniSer(f, ScanDims=[], NChannels=8, Version=hex2dec('0220'));
    c2 = onCleanup(@() delete(f));

    d = parser.importSER(f);
    assert(isequal(d.values, (0:7)'), 'wide-header counts should be 0..7');
    fprintf('  PASS\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
% 3. Line profile ([5] scan) → 1 x 5 x nCh cube
% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 3: 0x4120 line profile ══\n');
try
    f = fullfile(tmpDir, 'ser_line.ser');
    writeMiniSer(f, ScanDims=5, NChannels=8);
    c3 = onCleanup(@() delete(f));

    d = parser.importSER(f);
    eds = d.metadata.parserSpecific.edsData;
    assert(isequal(size(eds.cube), [1 5 8]), ...
        sprintf('cube size %s, expected [1 5 8]', mat2str(size(eds.cube))));
    % element k (0-based) channel c holds k*100 + c
    assert(eds.cube(1, 4, 3) == 302, 'cube value (x=4, c=2) should be 302');
    fprintf('  PASS\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
% 4. 2-D spectrum image ([2 3] scan) → cube orientation + survey + contract
% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 4: 0x4120 2-D spectrum image ══\n');
try
    f = fullfile(tmpDir, 'ser_map.ser');
    info = writeMiniSer(f, ScanDims=[2 3], NChannels=8);
    c4 = onCleanup(@() delete(f));

    d  = parser.importSER(f);
    ps = d.metadata.parserSpecific;
    eds = ps.edsData;
    assert(isequal(size(eds.cube), [2 3 8]), ...
        sprintf('cube size %s, expected [2 3 8]', mat2str(size(eds.cube))));

    % Row-major scan order, x fastest: element k=(y-1)*nx+(x-1), value k*100+c
    for y = 1:2
        for x = 1:3
            k = (y-1)*3 + (x-1);
            assert(eds.cube(y, x, 1) == k*100, ...
                sprintf('cube(%d,%d,1)=%g, expected %d', y, x, eds.cube(y,x,1), k*100));
        end
    end

    % Survey image = total counts per pixel; element k sums to 8k*100 + 28
    assert(ps.isImage && isequal(size(ps.imageData.pixels), [2 3]), ...
        'survey image should be 2x3');
    assert(ps.imageData.pixels(1, 1) == sum(0:7), 'survey(1,1) = sum of 0..7');
    assert(ps.imageData.pixels(2, 3) == 5*100*8 + sum(0:7), 'survey(2,3) mismatch');

    % Workshop contract: energyAxis in keV, sumSpectrum per channel
    assert(max(abs(eds.energyAxis - info.energyAxis/1000)) < 1e-15, ...
        'edsData.energyAxis should be keV (eV/1000)');
    assert(numel(eds.sumSpectrum) == 8, 'sumSpectrum should have nCh entries');
    assert(eds.sumSpectrum(1) == 100*(0+1+2+3+4+5), 'sumSpectrum(1) mismatch');
    fprintf('  PASS\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
% 5. Multi-frame 0x4122 image series → warning, first frame imported
% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 5: 0x4122 multi-frame warns, imports frame 1 ══\n');
try
    f = fullfile(tmpDir, 'ser_frames.ser');
    writeMiniSer(f, Kind="image", Width=4, Height=3, NElem=3);
    c5 = onCleanup(@() delete(f));

    lastwarn('');
    d = parser.importSER(f);
    [~, warnId] = lastwarn();
    assert(strcmp(warnId, 'parser:importSER:multiFrame'), ...
        sprintf('expected multiFrame warning, got "%s"', warnId));
    img = d.metadata.parserSpecific.imageData;
    assert(img.width == 4 && img.height == 3, 'frame-1 dimensions wrong');
    assert(isequal(img.pixels, reshape(uint16(1:12), [4 3])'), ...
        'frame-1 pixels should be 1..12 row-major');
    fprintf('  PASS\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
%  Summary
% ════════════════════════════════════════════════════════════════════════
fprintf('\n════════════════════════════════════════════════════════════════\n');
fprintf('  SER SPECTRA TEST SUMMARY: %d passed, %d failed\n', passed, failed);
fprintf('════════════════════════════════════════════════════════════════\n');
if failed > 0
    error('test_ser_spectra:failures', '%d test(s) failed.', failed);
end
