function dispatch(action, ctx)
%DISPATCH  Image-group callback bodies (create / assign / refresh / delete).
%
%   fermiViewer.groups.dispatch(action, ctx)
%
%   The group state lives in ctx.model (a fermiViewer.groups.GroupModel
%   handle), so every action mutates by reference — no appData round-trip.
%   The current image set and selection are read live from the listbox
%   widget (ctx.lbImages), which sidesteps the stale-appData-closure hazard.
%
%   ctx fields:
%     .model           fermiViewer.groups.GroupModel handle
%     .lbImages        image listbox (ItemsData are image indices)
%     .ddLeft,.ddRight panel-binding dropdowns (ItemsData: 0 = all, else group #)
%     .setStatus       @(msg) status sink
%     .setCompareIdxL  @(idx) set left panel image + redraw
%     .setCompareIdxR  @(idx) set right panel image + redraw
%     .fig             figure handle (for the name dialog; optional)
%     .nameOverride    char — skip the dialog and use this name (tests/API)
%
%   See also FERMIVIEWER.GROUPS.GROUPMODEL, FERMIVIEWER.GROUPS.BUILDGROUPSBAR

    model = ctx.model;

    switch action
        case 'create'
            sel = selectedIndices(ctx.lbImages);
            if numel(sel) < 1
                ctx.setStatus('Select one or more images in the list first.');
                return;
            end
            if isfield(ctx, 'nameOverride') && ~isempty(ctx.nameOverride)
                name = ctx.nameOverride;
            else
                name = promptName(ctx, model.numGroups() + 1);
                if isempty(name), return; end    % cancelled
            end
            idx = model.addGroup(name, sel);
            if idx == 0
                ctx.setStatus('No valid images selected for the group.');
                return;
            end
            refreshDropdowns(ctx);
            ctx.setStatus(sprintf('Group "%s" created from %d image(s).', ...
                model.groups(idx).name, numel(model.groups(idx).members)));

        case 'assignL'
            bindPanel(ctx, 'L', ctx.ddLeft, ctx.setCompareIdxL);

        case 'assignR'
            bindPanel(ctx, 'R', ctx.ddRight, ctx.setCompareIdxR);

        case 'delete'
            % Delete whichever group is currently selected on the Left dropdown.
            g = currentValue(ctx.ddLeft);
            if g >= 1 && g <= model.numGroups()
                nm = model.groups(g).name;
                model.removeGroup(g);
                refreshDropdowns(ctx);
                ctx.setStatus(sprintf('Group "%s" deleted.', nm));
            else
                ctx.setStatus('Pick a group in the Left dropdown to delete.');
            end

        case 'refresh'
            refreshDropdowns(ctx);

        otherwise
            error('fermiViewer:groups:dispatch:unknownAction', ...
                'Unknown group action: %s', action);
    end
end


% ── helpers ──────────────────────────────────────────────────────────────
function bindPanel(ctx, side, dd, setIdx)
    model = ctx.model;
    g = currentValue(dd);
    model.assignToPanel(side, g);
    if g >= 1 && g <= model.numGroups()
        m = model.groups(g).members;
        if ~isempty(m)
            setIdx(m(1));     % jump the panel to the group's first image
        end
        ctx.setStatus(sprintf('%s panel → group "%s".', side, model.groups(g).name));
    else
        ctx.setStatus(sprintf('%s panel → all images.', side));
    end
end


function refreshDropdowns(ctx)
%REFRESHDROPDOWNS  Repopulate both binding dropdowns from the model, keeping
%   each side's current binding selected when it still exists.
    model = ctx.model;
    items = [{'(all images)'}, model.groupNames()];
    data  = num2cell(0:model.numGroups());
    setDropdown(ctx.ddLeft,  items, data, model.assignL);
    setDropdown(ctx.ddRight, items, data, model.assignR);
end


function setDropdown(dd, items, data, want)
    if isempty(dd) || ~isvalid(dd), return; end
    dd.Items     = items;
    dd.ItemsData = data;
    if want >= 0 && want <= numel(data) - 1
        dd.Value = want;
    else
        dd.Value = 0;
    end
end


function v = currentValue(dd)
    v = 0;
    if ~isempty(dd) && isvalid(dd) && ~isempty(dd.ItemsData)
        v = dd.Value;
    end
end


function idx = selectedIndices(lb)
%SELECTEDINDICES  Image indices currently selected in the multiselect list.
    idx = [];
    if isempty(lb) || ~isvalid(lb), return; end
    v = lb.Value;
    if iscell(v), v = cell2mat(v); end
    if isempty(v), return; end
    idx = v(v >= 1);   % drop the {0} "(no images)" placeholder
end


function name = promptName(ctx, n)
    name = '';
    def = {sprintf('Group %d', n)};
    answer = inputdlg('Group name:', 'New Image Group', 1, def);
    if isempty(answer), return; end
    name = strtrim(answer{1});
    if isempty(name), name = def{1}; end
end
