%TEST_COMMANDPALETTE  Headless tests for the ⌘K command palette + captureModeTable.
%
%   Covers (no real keystrokes — drives the palette API directly):
%     1. captureModeTable: known modes have .label + non-empty .steps
%     2. buildCommandPalette: items populate from the cb registry
%     3. setQuery filters the list (case-insensitive substring)
%     4. dispatch runs the matching callback + hides the palette
%     5. only registry entries present in cb are offered
%
%   Run:
%       run tests/gui/test_commandPalette
%       runAllTests(Group="fvgui")

fprintf('\n');
fprintf('╔══════════════════════════════════════════════════════════════╗\n');
fprintf('║  Command palette + captureModeTable                          ║\n');
fprintf('╚══════════════════════════════════════════════════════════════╝\n');

ROOT = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(ROOT);

passed = 0; failed = 0;
set(groot, 'DefaultFigureVisible', 'off');

parent = []; palette = [];

% ═══════════════════════════════════════════════════════════════════════
%  TEST 1: captureModeTable
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 1: captureModeTable ══\n');
try
    tbl = fermiViewer.captureModeTable();
    for m = ["distance","angle","crop","profile","gpa"]
        assert(isfield(tbl, m), sprintf('missing mode %s', m));
        e = tbl.(m);
        assert(isfield(e,'label') && strlength(e.label) > 0, 'label present');
        assert(iscell(e.steps) && ~isempty(e.steps), 'steps non-empty');
    end
    assert(numel(tbl.angle.steps) == 3, 'angle has 3 steps');
    fprintf('  PASS (modes have labels + steps)\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ═══════════════════════════════════════════════════════════════════════
%  TEST 2-4: command palette build / filter / dispatch
% ═══════════════════════════════════════════════════════════════════════
fprintf('\n══ TEST 2: palette build + items ══\n');
firedFlag = struct('autoContrast', false, 'gaussian', false);
try
    parent = uifigure('Visible', 'off', 'Position', [100 100 900 600]);
    tk = fermiViewer.chrome.uxTokens('dark');
    % Spy cb: a couple of real registry fields wired to flag-setters.
    cb = struct( ...
        'onAutoContrast',  @(varargin) assignFlag('autoContrast'), ...
        'onGaussianFilter',@(varargin) assignFlag('gaussian'), ...
        'onOpenFiles',     @(varargin) []);
    palette = fermiViewer.buildCommandPalette(parent, tk, cb);

    items0 = palette.items();
    assert(any(items0 == "Auto Contrast"), 'Auto Contrast offered');
    assert(any(items0 == "Gaussian Filter…"), 'Gaussian offered');
    % onDistance is NOT in the spy cb → must be absent.
    assert(~any(items0 == "Distance"), 'absent cb fields are not offered');
    fprintf('  PASS (%d items, registry filtered to present cb)\n', numel(items0));
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

fprintf('\n══ TEST 3: setQuery filters ══\n');
try
    palette.setQuery('gauss');
    f = palette.items();
    assert(all(contains(lower(f), 'gauss')), 'filtered to matches');
    assert(any(f == "Gaussian Filter…"), 'gaussian survives filter');
    palette.setQuery('');
    assert(numel(palette.items()) >= 3, 'empty query restores full list');
    fprintf('  PASS (case-insensitive substring filter)\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

fprintf('\n══ TEST 4: dispatch runs the callback + hides ══\n');
try
    palette.show();
    assert(strcmp(palette.fig.Visible, 'on'), 'palette shows');
    palette.dispatch('Auto Contrast');
    assert(getappdata(0, 'cmdpal_autoContrast') == true, 'callback fired'); %#ok<NASGU>
    assert(strcmp(palette.fig.Visible, 'off'), 'palette hides after dispatch');
    fprintf('  PASS (dispatch fired callback + hid palette)\n');
    passed = passed + 1;
catch ME
    fprintf('  FAIL: %s\n', ME.message);
    failed = failed + 1;
end

% ── Cleanup ──────────────────────────────────────────────────────────────
try, if ~isempty(palette) && isvalid(palette.fig), close(palette.fig); end, catch, end
try, if ~isempty(parent) && isvalid(parent), close(parent); end, catch, end
if isappdata(0, 'cmdpal_autoContrast'), rmappdata(0, 'cmdpal_autoContrast'); end
if isappdata(0, 'cmdpal_gaussian'), rmappdata(0, 'cmdpal_gaussian'); end

% ── Summary ────────────────────────────────────────────────────────────
fprintf('\n');
fprintf('╔══════════════════════════════════════════════════════════════╗\n');
fprintf('║ Results: %2d passed, %2d failed                                ║\n', passed, failed);
fprintf('╚══════════════════════════════════════════════════════════════╝\n');

if failed > 0
    error('test_commandPalette: %d test(s) failed', failed);
end

% Flag-setter: records into root appdata so the closure works across the
% palette's dispatch boundary.
function assignFlag(name)
    setappdata(0, ['cmdpal_' name], true);
end
