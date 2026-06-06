%TEST_IMPORTBCF  Smoke tests for parser.importBCF (Bruker BCF EDS files).
%   Run standalone: cd tests; run parser/test_importBCF
%   Run via group:  runAllTests(Group="em")

clear; clc;

thisDir = fileparts(mfilename('fullpath'));
rootDir = fileparts(fileparts(thisDir));
if ~contains(path, rootDir), addpath(rootDir); end

BCF1 = fullfile(rootDir, '+test_datasets', 'BCF', 'Hitachi_TM3030Plus.bcf');
BCF2 = fullfile(rootDir, '+test_datasets', 'BCF', 'test_TEM.bcf');
% Compressed-HeaderData regression vector. Both files above store HeaderData
% as plain XML; this one is AACS/zlib-compressed (the common Esprit export),
% exercising decompressIfNeeded -> zlibInflate. A by-value MATLAB->Java buffer
% bug previously made every compressed file decode to all-zero bytes -> noData.
BCF_COMPRESSED = fullfile(rootDir, '+test_datasets', 'BCF', 'over16bit_compressed.bcf');

passed = 0;
failed = 0;

% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 1: Import Hitachi BCF ══\n');
try
    d = parser.importBCF(BCF1);
    assert(~isempty(d.time),   'time is empty');
    assert(~isempty(d.values), 'values is empty');
    assert(~isempty(d.labels), 'labels is empty');
    assert(isfield(d, 'metadata'), 'metadata missing');
    fprintf('  Channels: %d, Points: %d\n', numel(d.labels), numel(d.time));
    fprintf('  Labels: %s\n', strjoin(d.labels, ', '));
    fprintf('  PASS\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 2: Import TEM BCF ══\n');
try
    d = parser.importBCF(BCF2);
    assert(~isempty(d.time),   'time is empty');
    assert(~isempty(d.values), 'values is empty');
    fprintf('  Channels: %d, Points: %d\n', numel(d.labels), numel(d.time));
    fprintf('  PASS\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 3: resolveParser dispatches .bcf ══\n');
try
    r = parser.resolveParser(BCF1);
    assert(strcmp(r.name, 'importBCF'), ...
        sprintf('Expected importBCF, got %s', r.name));
    fprintf('  PASS\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 4: Struct contract (createDataStruct fields) ══\n');
try
    d = parser.importBCF(BCF1);
    reqFields = {'time', 'values', 'labels', 'units', 'metadata'};
    for k = 1:numel(reqFields)
        assert(isfield(d, reqFields{k}), sprintf('Missing field: %s', reqFields{k}));
    end
    assert(numel(d.time) == size(d.values, 1), 'time/values row count mismatch');
    fprintf('  PASS\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 5: Import AACS-compressed HeaderData BCF ══\n');
try
    d = parser.importBCF(BCF_COMPRESSED);
    ps = d.metadata.parserSpecific;
    % The decompressed XML must yield real content — a decoded SEM image with
    % non-zero pixels. The old by-value Java inflate bug produced all-zero
    % bytes, so the XML parsed to nothing and import threw noData.
    assert(isfield(ps, 'isImage') && ps.isImage, ...
        'compressed BCF produced no SEM image (decompression likely failed)');
    assert(~isempty(ps.allImages), 'allImages empty for compressed BCF');
    px = ps.imageData.pixels;
    assert(any(px(:) ~= 0), 'decoded image is all zeros — zlib inflate returned an empty buffer');
    fprintf('  Image: %dx%d, nonzero pixels=%d\n', ...
        ps.imageData.width, ps.imageData.height, nnz(px));
    fprintf('  PASS\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 6: Non-SFS file rejected with clear error ══\n');
try
    tmpBad = [tempname '.bcf'];
    fid = fopen(tmpBad, 'wb'); fwrite(fid, uint8('NotToday-not-an-sfs')); fclose(fid);
    cleanupBad = onCleanup(@() delete(tmpBad));
    threw = false;
    try
        parser.importBCF(tmpBad);
    catch innerME
        threw = true;
        assert(strcmp(innerME.identifier, 'parser:importBCF:badMagic'), ...
            sprintf('expected badMagic, got %s', innerME.identifier));
    end
    assert(threw, 'non-SFS file did not raise an error');
    fprintf('  PASS\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 7: Sample-vector variants import + struct contract ══\n');
%   Distinct format variants from the public RosettaSciIO corpus:
%   a 12-bit-packed map and an Esprit v2 container (SpectrumPositions0 +
%   compressed header). Cube totals are pinned in test_eds_hypercube.
variants = { '12bit_packed_16x16.bcf', 'esprit_v2_50x50.bcf' };
reqFields = {'time', 'values', 'labels', 'units', 'metadata'};
for vi = 1:numel(variants)
    fp = fullfile(rootDir, '+test_datasets', 'BCF', variants{vi});
    try
        d = parser.importBCF(fp);
        for k = 1:numel(reqFields)
            assert(isfield(d, reqFields{k}), sprintf('%s missing field %s', variants{vi}, reqFields{k}));
        end
        assert(numel(d.time) == size(d.values, 1), 'time/values row mismatch');
        assert(strcmp(parser.resolveParser(fp).name, 'importBCF'), 'resolveParser mismatch');
        fprintf('  %-26s OK (%d pts)\n', variants{vi}, numel(d.time));
        passed = passed + 1;
    catch ME
        fprintf('  %-26s FAIL: %s\n', variants{vi}, ME.message); failed = failed + 1;
    end
end

% ════════════════════════════════════════════════════════════════════════
fprintf('\n\n══════════════════════════════════════════\n');
fprintf('  test_importBCF: %d passed, %d failed\n', passed, failed);
fprintf('══════════════════════════════════════════\n');
if failed > 0
    error('test_importBCF:failures', '%d test(s) failed.', failed);
end
