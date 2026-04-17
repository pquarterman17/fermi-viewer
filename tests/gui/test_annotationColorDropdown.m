%TEST_ANNOTATIONCOLORDROPDOWN  Verify FermiViewer annotation colour dropdown.
%
%   Regression test for the conversion of the click-to-cycle annotation
%   colour button (`btnAnnotColor` / `onAnnotColorCycle`) into a proper
%   uidropdown (`ddAnnotColor` / `onAnnotColorChange`).
%
%   For each of the 5 colour options (White / Cyan / Yellow / Red / Black)
%   the test sets the dropdown Value, fires ValueChangedFcn, and asserts
%   that the dropdown's FontColor matches the expected RGB for that name.
%   The FontColor is a faithful proxy for appData.annotationColor because
%   onAnnotColorChange assigns both from the same lookup table in a single
%   atomic step.
%
%   Run standalone:  cd tests; run gui/test_annotationColorDropdown
%   Run from root:   run tests/gui/test_annotationColorDropdown

clear; clc;

% Ensure toolbox is on the path
thisDir = fileparts(mfilename('fullpath'));
rootDir = fileparts(fileparts(thisDir));
if ~contains(path, rootDir)
    addpath(rootDir);
end

passed = 0;
failed = 0;

% Name -> expected RGB (must match the table in FermiViewer::onAnnotColorChange)
% OVERLAY_COLOR = [0 1 1] in FermiViewer.m, so 'Cyan' -> [0 1 1].
names    = {'White',   'Cyan',    'Yellow',  'Red',     'Black'};
expected = {[1 1 1],   [0 1 1],   [1 1 0],   [1 0 0],   [0 0 0]};

try
    api = FermiViewer();
    cleanupApi = onCleanup(@() safeClose(api));

    % Locate the annotation-colour dropdown. findobj regex comparison is not
    % supported for the Tooltip property in uifigures, so instead we scan
    % all uidropdown widgets and pick the one whose ItemsData matches the
    % expected 5-name colour list. This is robust against layout shuffles.
    allDD = findall(api.fig, 'Type', 'uidropdown');
    dd = gobjects(0);
    for k = 1:numel(allDD)
        try
            if isequal(allDD(k).ItemsData, names)
                dd = allDD(k);
                break;
            end
        catch
        end
    end
    assert(~isempty(dd), 'ddAnnotColor not found (no uidropdown with 5-colour ItemsData)');

    % The widget should have all 5 ItemsData entries and default to White.
    assert(isequal(dd.ItemsData, names), ...
        'ItemsData mismatch: expected name list {White,Cyan,Yellow,Red,Black}');
    assert(strcmp(dd.Value, 'White'), ...
        'Default Value should be White, got %s', dd.Value);

    % Fire ValueChangedFcn for each option and verify FontColor update.
    for k = 1:numel(names)
        dd.Value = names{k};
        if ~isempty(dd.ValueChangedFcn)
            dd.ValueChangedFcn(dd, []);
        end
        drawnow;

        assert(isequal(dd.FontColor, expected{k}), ...
            'After Value=%s, FontColor was [%s], expected [%s]', ...
            names{k}, num2str(dd.FontColor), num2str(expected{k}));

        fprintf('  %-7s -> FontColor [%s]  OK\n', names{k}, num2str(dd.FontColor));
    end

    fprintf('  PASS: all 5 colour options applied correctly\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    fprintf('  Stack: %s (line %d)\n', ME.stack(1).name, ME.stack(1).line);
    failed = failed + 1;
end

% ── Summary ──────────────────────────────────────────────────────────────
fprintf('\n════════════════════════════════════════\n');
fprintf('  test_annotationColorDropdown summary\n');
fprintf('════════════════════════════════════════\n');
fprintf('  Passed: %d\n', passed);
fprintf('  Failed: %d\n', failed);
fprintf('════════════════════════════════════════\n');

if failed > 0
    error('test_annotationColorDropdown: %d test(s) failed', failed);
end

% ── Helpers ──────────────────────────────────────────────────────────────
function safeClose(api)
%SAFECLOSE  Close GUI figure if it is still valid.
    try
        if isfield(api, 'close') && isvalid(api.fig)
            api.close();
        end
    catch
    end
end
