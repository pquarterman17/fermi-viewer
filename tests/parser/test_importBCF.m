%TEST_IMPORTBCF  Smoke tests for parser.importBCF (Bruker BCF EDS files).
%   Run standalone: cd tests; run parser/test_importBCF
%   Run via group:  runAllTests(Group="em")

clear; clc;

thisDir = fileparts(mfilename('fullpath'));
rootDir = fileparts(fileparts(thisDir));
if ~contains(path, rootDir), addpath(rootDir); end

BCF1 = fullfile(rootDir, '+test_datasets', 'BCF', 'Hitachi_TM3030Plus.bcf');
BCF2 = fullfile(rootDir, '+test_datasets', 'BCF', 'test_TEM.bcf');

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
fprintf('\n\n══════════════════════════════════════════\n');
fprintf('  test_importBCF: %d passed, %d failed\n', passed, failed);
fprintf('══════════════════════════════════════════\n');
if failed > 0
    error('test_importBCF:failures', '%d test(s) failed.', failed);
end
