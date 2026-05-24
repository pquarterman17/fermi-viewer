%TEST_FV_PARSER_EDGE_CASES  Edge-case and error-handling tests for +parser.
%
%   Run standalone:  cd tests/parser; run test_fv_parser_edge_cases
%   Run from root:   runAllTests(Group="parser")
%
%   Negative-path coverage for the EM parsers and the dispatch layer
%   (importAuto / resolveParser). Each test feeds deliberately bad input
%   — empty files, truncated binaries, wrong magic bytes, unknown
%   extensions, missing files, size mismatches — and asserts the parser
%   fails the RIGHT way: a clean parser:* error (or documented MATLAB
%   validator error), never a raw internal stack trace.
%
%   Mirrors quantized_matlab's test_parsers_edge_cases.m, adapted to the
%   EM binary formats (DM3/DM4/MRC/SER/BCF) and headerless RAW.
%
%   All fixtures are tiny synthetic files written to tempdir — no
%   dependency on +test_datasets/, runs in well under a second.

clear; clc;

% Ensure toolbox is on the path
thisDir = fileparts(mfilename('fullpath'));
rootDir = fileparts(fileparts(thisDir));
if ~contains(path, rootDir)
    addpath(rootDir);
end

passed = 0;
failed = 0;
tmpDir = tempdir();

% Helper: write raw bytes to a temp file, return path + cleanup object.
writeBytes = @(name, bytes) iWriteBytes(fullfile(tmpDir, name), bytes);

% ════════════════════════════════════════════════════════════════════════
%  1. resolveParser — unknown extension
% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 1: resolveParser – unknown extension ══\n');
try
    [f, c] = writeBytes('edge_unknown.xyz', uint8('dummy')); %#ok<ASGLU>
    try
        parser.resolveParser(f);
        error('test:noThrow', 'Should have errored on unknown extension');
    catch ME
        assert(strcmp(ME.identifier, 'parser:resolveParser:unknownExtension'), ...
            sprintf('expected unknownExtension id, got "%s"', ME.identifier));
        assert(contains(ME.message, 'No EM parser'), 'message should explain no parser');
        fprintf('  Expected error: %s\n', firstLine(ME.message));
    end
    fprintf('  PASS\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
%  2. importAuto — unknown extension propagates
% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 2: importAuto – unknown extension ══\n');
try
    [f, c] = writeBytes('edge_unknown2.xyz', uint8('dummy')); %#ok<ASGLU>
    try
        parser.importAuto(f);
        error('test:noThrow', 'Should have errored on unknown extension');
    catch ME
        assert(strcmp(ME.identifier, 'parser:resolveParser:unknownExtension'), ...
            sprintf('expected unknownExtension id, got "%s"', ME.identifier));
        fprintf('  Expected error: %s\n', firstLine(ME.message));
    end
    fprintf('  PASS\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
%  3. importAuto — non-existent file (mustBeFile validator)
% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 3: importAuto – missing file ══\n');
try
    missing = fullfile(tmpDir, 'fv_does_not_exist_98765.dm3');
    if isfile(missing), delete(missing); end
    try
        parser.importAuto(missing);
        error('test:noThrow', 'Should have errored on missing file');
    catch ME
        % mustBeFile throws MATLAB:validators:mustBeFile
        assert(contains(ME.identifier, 'mustBeFile') || ...
               contains(ME.message, 'file', 'IgnoreCase', true), ...
               sprintf('expected a file-existence error, got "%s"', ME.identifier));
        fprintf('  Expected error: %s\n', firstLine(ME.message));
    end
    fprintf('  PASS\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
%  4. resolveParser — positive dispatch table (extension → parser name)
% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 4: resolveParser – extension dispatch table ══\n');
try
    expect = { '.dm3','importDM3'; '.dm4','importDM4'; '.ser','importSER'; ...
               '.mrc','importMRC'; '.bcf','importBCF'; '.tif','importTIFF'; ...
               '.tiff','importTIFF'; '.png','importImage'; '.jpg','importImage' };
    for r = 1:size(expect,1)
        ext = expect{r,1}; want = expect{r,2};
        [f, c] = writeBytes(['edge_disp' ext], uint8(0)); %#ok<ASGLU>
        res = parser.resolveParser(f);
        assert(strcmp(res.name, want), ...
            sprintf('%s → expected %s, got %s', ext, want, res.name));
    end
    fprintf('  All %d extensions dispatched correctly\n', size(expect,1));
    fprintf('  PASS\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
%  5. importDM3 — empty file
% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 5: importDM3 – empty file ══\n');
try
    [f, c] = writeBytes('edge_empty.dm3', uint8([])); %#ok<ASGLU>
    try
        parser.importDM3(f);
        error('test:noThrow', 'Should have errored on empty DM3');
    catch ME
        assert(startsWith(ME.identifier, 'parser:importDM3'), ...
            sprintf('expected a parser:importDM3:* error, got "%s"', ME.identifier));
        fprintf('  Expected error: [%s] %s\n', ME.identifier, firstLine(ME.message));
    end
    fprintf('  PASS\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
%  6. importDM3 — wrong version (garbage header)
% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 6: importDM3 – bad version bytes ══\n');
try
    % version uint32 big-endian = 999 (not 3 or 4), + padding
    bytes = [typecast(swapbytes(uint32(999)), 'uint8'), uint8(zeros(1,60))];
    [f, c] = writeBytes('edge_badver.dm3', bytes); %#ok<ASGLU>
    try
        parser.importDM3(f);
        error('test:noThrow', 'Should have errored on bad version');
    catch ME
        assert(strcmp(ME.identifier, 'parser:importDM3:badVersion'), ...
            sprintf('expected badVersion, got "%s"', ME.identifier));
        fprintf('  Expected error: %s\n', firstLine(ME.message));
    end
    fprintf('  PASS\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
%  7. importDM4 — wrong version (garbage header)
% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 7: importDM4 – bad version bytes ══\n');
try
    bytes = [typecast(swapbytes(uint32(999)), 'uint8'), uint8(zeros(1,60))];
    [f, c] = writeBytes('edge_badver.dm4', bytes); %#ok<ASGLU>
    try
        parser.importDM4(f);
        error('test:noThrow', 'Should have errored on bad version');
    catch ME
        assert(strcmp(ME.identifier, 'parser:importDM4:badVersion'), ...
            sprintf('expected DM4 badVersion, got "%s"', ME.identifier));
        fprintf('  Expected error: %s\n', firstLine(ME.message));
    end
    fprintf('  PASS\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
%  8. importMRC — truncated (shorter than 1024-byte header)
% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 8: importMRC – truncated header ══\n');
try
    [f, c] = writeBytes('edge_trunc.mrc', uint8(zeros(1,100))); %#ok<ASGLU>
    try
        parser.importMRC(f);
        error('test:noThrow', 'Should have errored on truncated MRC');
    catch ME
        assert(startsWith(ME.identifier, 'parser:importMRC'), ...
            sprintf('expected parser:importMRC:* error, got "%s"', ME.identifier));
        fprintf('  Expected error: [%s] %s\n', ME.identifier, firstLine(ME.message));
    end
    fprintf('  PASS\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
%  9. importSER — bad byte-order magic
% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 9: importSER – bad byte-order magic ══\n');
try
    % SER expects byteOrder magic 0x4949 at offset 0; write garbage.
    [f, c] = writeBytes('edge_bad.ser', uint8([1 2 3 4 zeros(1,60)])); %#ok<ASGLU>
    try
        parser.importSER(f);
        error('test:noThrow', 'Should have errored on bad SER header');
    catch ME
        assert(startsWith(ME.identifier, 'parser:importSER'), ...
            sprintf('expected parser:importSER:* error, got "%s"', ME.identifier));
        fprintf('  Expected error: [%s] %s\n', ME.identifier, firstLine(ME.message));
    end
    fprintf('  PASS\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
% 10. importBCF — bad magic (not 'AAMVHFSS')
% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 10: importBCF – bad magic ══\n');
try
    [f, c] = writeBytes('edge_badmagic.bcf', uint8([uint8('NOTMAGIC'), zeros(1,400)])); %#ok<ASGLU>
    try
        parser.importBCF(f);
        error('test:noThrow', 'Should have errored on bad BCF magic');
    catch ME
        assert(strcmp(ME.identifier, 'parser:importBCF:badMagic'), ...
            sprintf('expected badMagic, got "%s"', ME.identifier));
        fprintf('  Expected error: %s\n', firstLine(ME.message));
    end
    fprintf('  PASS\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
% 11. importBCF — truncated (< 336 bytes)
% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 11: importBCF – truncated file ══\n');
try
    [f, c] = writeBytes('edge_trunc.bcf', uint8([uint8('AAMVHFSS'), zeros(1,50)])); %#ok<ASGLU>
    try
        parser.importBCF(f);
        error('test:noThrow', 'Should have errored on truncated BCF');
    catch ME
        assert(strcmp(ME.identifier, 'parser:importBCF:badMagic'), ...
            sprintf('expected badMagic (size guard), got "%s"', ME.identifier));
        fprintf('  Expected error: %s\n', firstLine(ME.message));
    end
    fprintf('  PASS\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
% 12. importRawImage — size mismatch
% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 12: importRawImage – size mismatch ══\n');
try
    % 100 bytes but claim 512x512x16-bit (= 524288 bytes)
    [f, c] = writeBytes('edge_size.raw', uint8(zeros(1,100))); %#ok<ASGLU>
    try
        parser.importRawImage(f, Width=512, Height=512, BitDepth=16);
        error('test:noThrow', 'Should have errored on size mismatch');
    catch ME
        assert(strcmp(ME.identifier, 'parser:importRawImage:sizeMismatch'), ...
            sprintf('expected sizeMismatch, got "%s"', ME.identifier));
        fprintf('  Expected error: %s\n', firstLine(ME.message));
    end
    fprintf('  PASS\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
% 13. importRawImage — invalid BitDepth
% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 13: importRawImage – invalid BitDepth ══\n');
try
    [f, c] = writeBytes('edge_bd.raw', uint8(zeros(1,64))); %#ok<ASGLU>
    try
        parser.importRawImage(f, Width=8, Height=8, BitDepth=12);
        error('test:noThrow', 'Should have errored on invalid BitDepth');
    catch ME
        assert(strcmp(ME.identifier, 'parser:importRawImage:badBitDepth'), ...
            sprintf('expected badBitDepth, got "%s"', ME.identifier));
        fprintf('  Expected error: %s\n', firstLine(ME.message));
    end
    fprintf('  PASS\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
% 14. importImage — non-image content in an image extension
% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 14: importImage – non-image .png content ══\n');
try
    [f, c] = writeBytes('edge_fake.png', uint8('this is plainly not a PNG')); %#ok<ASGLU>
    try
        parser.importImage(f);
        error('test:noThrow', 'Should have errored on fake PNG');
    catch ME
        assert(strcmp(ME.identifier, 'parser:importImage:infofail') || ...
               strcmp(ME.identifier, 'parser:importImage:readfail'), ...
            sprintf('expected infofail/readfail, got "%s"', ME.identifier));
        fprintf('  Expected error: [%s] %s\n', ME.identifier, firstLine(ME.message));
    end
    fprintf('  PASS\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
% 15. importDM4 — empty file (regression: empty `version` glided past the
%     `version ~= 4` guard into a MATLAB:nonLogicalConditional crash)
% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 15: importDM4 – empty file ══\n');
try
    [f, c] = writeBytes('edge_empty.dm4', uint8([])); %#ok<ASGLU>
    try
        parser.importDM4(f);
        error('test:noThrow', 'Should have errored on empty DM4');
    catch ME
        assert(strcmp(ME.identifier, 'parser:importDM4:badVersion'), ...
            sprintf('expected DM4 badVersion, got "%s"', ME.identifier));
        fprintf('  Expected error: %s\n', firstLine(ME.message));
    end
    fprintf('  PASS\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
% 16. importMRC — empty file (regression: empty NX glided past `NX<=0||NY<=0`
%     into a MATLAB:nonLogicalConditional crash at the `||`)
% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 16: importMRC – empty file ══\n');
try
    [f, c] = writeBytes('edge_empty.mrc', uint8([])); %#ok<ASGLU>
    try
        parser.importMRC(f);
        error('test:noThrow', 'Should have errored on empty MRC');
    catch ME
        assert(strcmp(ME.identifier, 'parser:importMRC:badDimensions'), ...
            sprintf('expected MRC badDimensions, got "%s"', ME.identifier));
        fprintf('  Expected error: %s\n', firstLine(ME.message));
    end
    fprintf('  PASS\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
% 17. importSER — empty file (regression: empty byteOrder fell through every
%     magic `~=` check until `W<=0||H<=0` crashed)
% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 17: importSER – empty file ══\n');
try
    [f, c] = writeBytes('edge_empty.ser', uint8([])); %#ok<ASGLU>
    try
        parser.importSER(f);
        error('test:noThrow', 'Should have errored on empty SER');
    catch ME
        assert(strcmp(ME.identifier, 'parser:importSER:badByteOrder'), ...
            sprintf('expected SER badByteOrder, got "%s"', ME.identifier));
        fprintf('  Expected error: %s\n', firstLine(ME.message));
    end
    fprintf('  PASS\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
% 18. importDM4 — corrupt nTags must NOT hang (missing sanity guard)
% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 18: importDM4 – corrupt nTags (no infinite loop) ══\n');
try
    b = zeros(1,200,'uint8');
    b(1:4)   = typecast(swapbytes(uint32(4)),  'uint8');   % version 4
    b(5:12)  = typecast(swapbytes(uint64(100)),'uint8');   % rootDirSize
    b(13:16) = typecast(swapbytes(uint32(1)),  'uint8');   % byteOrder LE
    b(17:24) = typecast(swapbytes(uint64(99999999)),'uint8'); % bogus nTags
    [f, c] = writeBytes('edge_corruptn.dm4', b); %#ok<ASGLU>
    t0 = tic;
    try
        parser.importDM4(f);
        error('test:noThrow', 'Should have errored on corrupt DM4');
    catch ME
        % DM4 reuses some parser:importDM3:* ids (e.g. noImage); accept either.
        assert(startsWith(ME.identifier, 'parser:importDM'), ...
            sprintf('expected parser:importDM*:* error, got "%s"', ME.identifier));
    end
    el = toc(t0);
    assert(el < 5, sprintf('importDM4 took %.1fs — likely hung (guard missing)', el));
    fprintf('  Errored cleanly in %.2fs (no hang)\n', el);
    fprintf('  PASS\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
% 19. importDM3/DM4 — truncated mid-tag-entry → clean error, not crash
% ════════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 19: importDM3 – truncated after header (no nonLogicalConditional) ══\n');
try
    b = zeros(1,13,'uint8');
    b(1:4) = typecast(swapbytes(uint32(3)),   'uint8');   % version 3
    b(5:8) = typecast(swapbytes(uint32(1000)),'uint8');   % rootDirSize
    b(9:12)= typecast(swapbytes(uint32(1)),   'uint8');   % byteOrder
    % 1 trailing byte: truncates inside the root tag group's nTags read
    [f, c] = writeBytes('edge_truncentry.dm3', b); %#ok<ASGLU>
    try
        parser.importDM3(f);
        error('test:noThrow', 'Should have errored on truncated DM3');
    catch ME
        assert(startsWith(ME.identifier, 'parser:importDM3'), ...
            sprintf('expected parser:importDM3:* error (not nonLogicalConditional), got "%s"', ME.identifier));
        fprintf('  Expected error: [%s]\n', ME.identifier);
    end
    fprintf('  PASS\n'); passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message); failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
%  Summary
% ════════════════════════════════════════════════════════════════════════
fprintf('\n');
fprintf('════════════════════════════════════════════════════════════════\n');
fprintf('  FV PARSER EDGE CASE TEST SUMMARY\n');
fprintf('════════════════════════════════════════════════════════════════\n');
fprintf('  Passed: %d / %d\n', passed, passed + failed);
fprintf('  Failed: %d / %d\n', failed, passed + failed);
fprintf('════════════════════════════════════════════════════════════════\n');

if failed == 0
    fprintf('\n✓ All edge case tests passed!\n\n');
else
    fprintf('\n✗ %d test(s) failed.\n\n', failed);
    error('test_fv_parser_edge_cases:failures', '%d test(s) failed.', failed);
end


% ════════════════════════════════════════════════════════════════════════
%  Local helpers
% ════════════════════════════════════════════════════════════════════════
function [fpath, cleanup] = iWriteBytes(fpath, bytes)
%IWRITEBYTES  Write raw bytes to fpath; return path + onCleanup deleter.
    fid = fopen(fpath, 'w');
    if fid == -1
        error('test:writeFail', 'Could not create temp file %s', fpath);
    end
    if ~isempty(bytes)
        fwrite(fid, uint8(bytes), 'uint8');
    end
    fclose(fid);
    cleanup = onCleanup(@() iSafeDelete(fpath));
end

function iSafeDelete(fpath)
    if isfile(fpath)
        try, delete(fpath); catch, end
    end
end

function s = firstLine(msg)
%FIRSTLINE  First line of an error message, trimmed to 70 chars.
    nl = find(msg == newline, 1);
    if ~isempty(nl), msg = msg(1:nl-1); end
    s = msg(1:min(70, numel(msg)));
end
