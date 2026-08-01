%TEST_IMAGELISTRENDERER  Image-list table renderer: thumbnails + accent rail.
%
%   Run standalone:  cd tests/gui; run test_imageListRenderer
%   Run from root:   runAllTests(Group="fvgui")
%
%   Covers gui-redesign #7 — the image list is a 2-column uitable (8 px
%   accent rail + name) where every image row carries a 16 px thumbnail
%   icon (uistyle Icon) and the rail marks the active image. Rows map 1:1
%   to image indices; the placeholder state is flagged via
%   UserData.hasImages. Asserts:
%     1. the list is a uitable with the loaded file names in column 2
%     2. every image row has an icon style on its name cell
%     3. exactly one rail style sits on [activeIdx 1] and follows
%        setActiveIdx
%     4. imageListSelection maps selection -> image indices (multi too)
%     5. the placeholder state renders and reads back as "no selection"
%     6. imageThumbnail: uint8 sz×sz×3 for images, [] for spectra

clear; clc;

thisDir = fileparts(mfilename('fullpath'));
rootDir = fileparts(fileparts(thisDir));
if ~contains(path, rootDir); addpath(rootDir); end

srcDir = fullfile(rootDir, '+test_datasets', 'Microscopy');
dm3a = fullfile(srcDir, 'EDW087-1.dm3');
dm3b = fullfile(srcDir, 'EDW087-2.dm3');
assert(isfile(dm3a) && isfile(dm3b), 'Test DM3s not found in %s', srcDir);

fprintf('\n=== test_imageListRenderer ===\n');
passed = 0; failed = 0;

api = FermiViewer();
cleanupApi = onCleanup(@() safeClose(api));
drawnow;
api.loadImages({dm3a, dm3b});
drawnow;

% ── Locate the image-list table by its content ───────────────────────────
tbls = findall(api.fig, 'Type', 'uitable');
lb = [];
for k = 1:numel(tbls)
    d = tbls(k).Data;
    if iscell(d) && size(d, 2) == 2 && any(contains(string(d(:, 2)), 'EDW087'))
        lb = tbls(k);
        break;
    end
end

try
    assert(~isempty(lb), 'image-list uitable not found');
    assert(size(lb.Data, 1) == 2, 'expected 2 rows, got %d', size(lb.Data, 1));
    assert(strcmp(lb.Data{1, 2}, 'EDW087-1.dm3') && ...
           strcmp(lb.Data{2, 2}, 'EDW087-2.dm3'), 'row names wrong');
    assert(lb.UserData.hasImages, 'hasImages flag not set');
    fprintf('  [PASS] table renders both loaded images by name\n');
    passed = passed + 1;
catch ME
    fprintf('  [FAIL] table content — %s\n', ME.message); failed = failed + 1;
end

% ── Thumbnail icon styles on every name cell ─────────────────────────────
try
    [iconRows, railRows] = styleRows(lb);
    assert(isequal(sort(iconRows), [1 2]), ...
        'icon styles on rows [%s], expected [1 2]', num2str(sort(iconRows)));
    fprintf('  [PASS] thumbnail icon style on every image row\n');
    passed = passed + 1;
catch ME
    fprintf('  [FAIL] thumbnail styles — %s\n', ME.message); failed = failed + 1;
end

% ── Accent rail on the active row, follows setActiveIdx ─────────────────
try
    [~, railRows] = styleRows(lb);
    assert(isscalar(railRows), 'expected exactly 1 rail style, got %d', numel(railRows));
    api.setActiveIdx(2); drawnow;
    [~, railRows2] = styleRows(lb);
    assert(isequal(railRows2, 2), 'rail on row %s after setActiveIdx(2)', num2str(railRows2));
    api.setActiveIdx(1); drawnow;
    [~, railRows3] = styleRows(lb);
    assert(isequal(railRows3, 1), 'rail did not return to row 1');
    fprintf('  [PASS] accent rail follows the active image\n');
    passed = passed + 1;
catch ME
    fprintf('  [FAIL] accent rail — %s\n', ME.message); failed = failed + 1;
end

% ── imageListSelection: single + multi ───────────────────────────────────
try
    sel = fermiViewer.display.imageListSelection(lb);
    assert(isequal(sel, 1), 'expected selection [1], got [%s]', num2str(sel));
    lb.Selection = [1 2];
    sel = fermiViewer.display.imageListSelection(lb);
    assert(isequal(sel, [1 2]), 'multi-select read failed: [%s]', num2str(sel));
    lb.Selection = 1;
    fprintf('  [PASS] imageListSelection single + multi\n');
    passed = passed + 1;
catch ME
    fprintf('  [FAIL] imageListSelection — %s\n', ME.message); failed = failed + 1;
end

% ── Thumbnail generator contract ─────────────────────────────────────────
try
    imgs = api.getImages();
    t = fermiViewer.display.imageThumbnail(imgs{1});
    assert(isa(t, 'uint8') && isequal(size(t), [16 16 3]), 'bad thumbnail shape/class');
    assert(numel(unique(t)) > 1, 'thumbnail is a flat tile (contrast stretch broken?)');
    fake = struct('metadata', struct('parserSpecific', struct('isImage', false)));
    assert(isempty(fermiViewer.display.imageThumbnail(fake)), ...
        'spectrum entry should yield []');
    fprintf('  [PASS] imageThumbnail contract (image + spectrum)\n');
    passed = passed + 1;
catch ME
    fprintf('  [FAIL] imageThumbnail — %s\n', ME.message); failed = failed + 1;
end

% ── Placeholder state ────────────────────────────────────────────────────
try
    fermiViewer.display.rebuildImageList({}, 0, lb);
    assert(~lb.UserData.hasImages, 'hasImages still true');
    assert(strcmp(lb.Data{1, 2}, '(no images loaded)'), 'placeholder text missing');
    assert(isempty(fermiViewer.display.imageListSelection(lb)), ...
        'placeholder must read back as no selection');
    assert(isempty(lb.StyleConfigurations) || height(lb.StyleConfigurations) == 0, ...
        'stale styles survive the placeholder rebuild');
    % restore for clean teardown
    fermiViewer.display.rebuildImageList(api.getImages(), 1, lb);
    fprintf('  [PASS] placeholder state\n');
    passed = passed + 1;
catch ME
    fprintf('  [FAIL] placeholder — %s\n', ME.message); failed = failed + 1;
end

% ════════════════════════════════════════════════════════════════════════
fprintf('\n%s\n', repmat(char(9552), 1, 72));
fprintf('SUMMARY: %d/%d checks passed\n', passed, passed + failed);
if failed > 0
    error('test_imageListRenderer:failures', '%d check(s) failed.', failed);
else
    fprintf('Status: ALL PASS\n');
end

% ════════════════════════════════════════════════════════════════════════
% Local helpers
% ════════════════════════════════════════════════════════════════════════
function [iconRows, railRows] = styleRows(tbl)
%STYLEROWS  Rows carrying icon styles (col 2) and rail styles (col 1).
    iconRows = []; railRows = [];
    sc = tbl.StyleConfigurations;
    for k = 1:height(sc)
        if sc.Target(k) ~= "cell", continue; end
        tgt = sc.TargetIndex{k};
        for r = 1:size(tgt, 1)
            if tgt(r, 2) == 2 && ~isempty(sc.Style(k).Icon)
                iconRows(end+1) = tgt(r, 1); %#ok<AGROW>
            elseif tgt(r, 2) == 1
                railRows(end+1) = tgt(r, 1); %#ok<AGROW>
            end
        end
    end
end

function safeClose(api)
    try
        if ~isempty(api) && isstruct(api) && isfield(api, 'close') && isvalid(api.fig)
            api.close();
        end
    catch
    end
end
