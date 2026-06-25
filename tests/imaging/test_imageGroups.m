function test_imageGroups
%TEST_IMAGEGROUPS  Image-group model + group-aware compare navigation.
%
%   Pure-logic coverage (no GUI launch) for the compare-mode image groups
%   feature:
%     - fermiViewer.groups.GroupModel: add/remove (with binding re-base),
%       assignToPanel, membersFor pruning + all-images fallback
%     - fermiViewer.interaction.onKeyPress: left/right arrows cycle WITHIN
%       the active panel's bound group, wrapping; snap-to-first when the
%       current index is outside the group
%
%   Run:
%       run tests/imaging/test_imageGroups
%       runAllTests(Group="fv")

    ROOT = fileparts(fileparts(fileparts(mfilename('fullpath'))));
    if ~contains(path, ROOT), addpath(ROOT); end

    passed = 0; failed = 0;
    fprintf('\n== test_imageGroups ==\n');

    % ── GroupModel basics ────────────────────────────────────────────────
    m = fermiViewer.groups.GroupModel();
    check('new model has 0 groups', m.numGroups() == 0);

    gA = m.addGroup('A', [1 3 5]);
    gB = m.addGroup('B', [2 4 6]);
    check('addGroup returns sequential indices', gA == 1 && gB == 2);
    check('members deduped/sorted', isequal(m.groups(1).members, [1 3 5]));

    g0 = m.addGroup('empty', []);
    check('empty member set rejected (idx 0)', g0 == 0 && m.numGroups() == 2);

    m.addGroup('dups', [3 3 1 2 2]);
    check('addGroup dedupes + sorts', isequal(m.groups(3).members, [1 2 3]));

    % ── assignToPanel + membersFor ───────────────────────────────────────
    m.assignToPanel('L', 1);
    m.assignToPanel('R', 2);
    check('membersFor L = group A', isequal(m.membersFor('L', 10), [1 3 5]));
    check('membersFor R = group B', isequal(m.membersFor('R', 10), [2 4 6]));

    % Pruning: members beyond the current image count are dropped.
    check('membersFor prunes out-of-range', isequal(m.membersFor('L', 3), [1 3]));
    % Fallback: when every member is out of range, fall back to all images.
    mPrune = fermiViewer.groups.GroupModel();
    mPrune.addGroup('hi', [10 11]); mPrune.assignToPanel('L', 1);
    check('membersFor falls back to all when all pruned', ...
        isequal(mPrune.membersFor('L', 5), 1:5));
    % Unbound side → all images.
    fresh = fermiViewer.groups.GroupModel();
    check('unbound side = all images', isequal(fresh.membersFor('L', 7), 1:7));

    % ── removeGroup re-bases bindings ────────────────────────────────────
    m2 = fermiViewer.groups.GroupModel();
    m2.addGroup('A', 1); m2.addGroup('B', 2); m2.addGroup('C', 3);
    m2.assignToPanel('L', 3);   % bound to C
    m2.assignToPanel('R', 2);   % bound to B
    m2.removeGroup(1);          % delete A → C becomes 2, B becomes 1
    check('removeGroup re-bases L binding (3→2)', m2.assignL == 2);
    check('removeGroup re-bases R binding (2→1)', m2.assignR == 1);
    m2.removeGroup(m2.assignL); % delete the group L points to
    check('removeGroup clears L binding to 0', m2.assignL == 0);

    % ── Group-aware compare navigation via onKeyPress ────────────────────
    nav = fermiViewer.groups.GroupModel();
    nav.addGroup('left',  [1 3 5]);
    nav.addGroup('right', [2 4]);
    nav.assignToPanel('L', 1);
    nav.assignToPanel('R', 2);

    % Right arrow on Left panel: 1 → 3 (next member, not next image)
    lastL = []; lastR = [];
    press('rightarrow', 'L', 1, 0, nav);
    check('L right arrow steps within group 1→3', lastL == 3);

    % Wrap on Left panel: 5 → 1
    press('rightarrow', 'L', 5, 0, nav);
    check('L right arrow wraps 5→1', lastL == 1);

    % Left arrow wraps on Left panel: 1 → 5
    press('leftarrow', 'L', 1, 0, nav);
    check('L left arrow wraps 1→5', lastL == 5);

    % Right panel cycles its own group: 2 → 4
    press('rightarrow', 'R', 0, 2, nav);
    check('R right arrow steps within group 2→4', lastR == 4);

    % Current index outside the group snaps to first member.
    press('rightarrow', 'L', 99, 0, nav);
    check('L arrow snaps to first member when idx outside group', lastL == 1);

    % No model bound (legacy) → walks all images.
    legacy = fermiViewer.groups.GroupModel();   % no groups, no bindings
    press('rightarrow', 'L', 1, 0, legacy);
    check('no group → steps all images 1→2', lastL == 2);

    % ── summary ──────────────────────────────────────────────────────────
    fprintf('\n  test_imageGroups: %d passed, %d failed\n', passed, failed);
    if failed > 0
        error('test_imageGroups:failures', '%d test(s) failed', failed);
    end

    % ── nested helpers (share passed/failed, lastL/lastR) ────────────────
    function check(label, cond)
        if cond
            passed = passed + 1; fprintf('  PASS  %s\n', label);
        else
            failed = failed + 1; fprintf('  FAIL  %s\n', label);
        end
    end

    function press(key, side, idxL, idxR, model)
        nImages = 6;
        appData = struct( ...
            'captureMode', '', 'selectedAnnotIdx', 0, 'selectedMeasIdx', 0, ...
            'images', {cell(1, nImages)}, 'compareMode', true, ...
            'compareActivePanel', side, 'compareIdxL', idxL, 'compareIdxR', idxR, ...
            'activeIdx', max(idxL, 1), 'rawPixels', [], 'panMode', false, ...
            'groupModel', model);
        cb = struct('setCompareIdxL', @recL, 'setCompareIdxR', @recR, ...
            'setStatus', @(varargin) [], 'setComparePanelToggle', @() [], ...
            'syncCompareZoom', @(a,b) [], 'displayCompareImage', @(s) []);
        evt = struct('Key', key, 'Modifier', {{}});
        fermiViewer.interaction.onKeyPress(evt, [], [], [], appData, cb);
    end

    function recL(i), lastL = i; end
    function recR(i), lastR = i; end
end
