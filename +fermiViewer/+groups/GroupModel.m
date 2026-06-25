classdef GroupModel < handle
%GROUPMODEL  Named image groups + per-side bindings for compare mode.
%
%   State container for the "image groups" feature: the user selects images
%   in the file list, names them as a group, then binds one group to the
%   left compare panel and another to the right. In side-by-side compare,
%   the arrow keys then cycle only within the active panel's group.
%
%   It is a handle class on purpose (the project's "state-as-class" rule):
%   callbacks mutate it by reference, so the group/compare wiring needs no
%   accept-and-return plumbing and no new nested functions in FermiViewer.m.
%
%   Group members are stored as image indices into appData.images. Indices
%   can go stale if images are removed/reordered; membersFor() prunes to the
%   current image count at read time and falls back to "all images" so the
%   compare navigation never breaks.
%
%   See also FERMIVIEWER.GROUPS.DISPATCH, FERMIVIEWER.GROUPS.BUILDGROUPSBAR,
%   FERMIVIEWER.INTERACTION.ONKEYPRESS

    properties (SetAccess = public)
        groups  struct = struct('name', {}, 'members', {})   % .name char, .members [1xN] double
        assignL (1,1) double = 0   % group index bound to the Left panel  (0 = all images)
        assignR (1,1) double = 0   % group index bound to the Right panel (0 = all images)
    end

    methods
        function reset(obj)
            obj.groups  = struct('name', {}, 'members', {});
            obj.assignL = 0;
            obj.assignR = 0;
        end

        function n = numGroups(obj)
            n = numel(obj.groups);
        end

        function idx = addGroup(obj, name, members)
        %ADDGROUP  Append a group; returns its index. Members are deduped,
        %   sorted, and coerced to a row of positive integers.
            members = unique(round(members(:)'));
            members = members(members >= 1);
            if isempty(members)
                idx = 0;
                return;
            end
            if nargin < 2 || isempty(name) || ~(ischar(name) || isstring(name))
                name = sprintf('Group %d', obj.numGroups() + 1);
            end
            g.name    = char(name);
            g.members = members;
            obj.groups(end+1) = g;
            idx = numel(obj.groups);
        end

        function removeGroup(obj, idx)
            if idx < 1 || idx > numel(obj.groups), return; end
            obj.groups(idx) = [];
            % Re-base panel bindings after the deletion.
            obj.assignL = rebind(obj.assignL, idx);
            obj.assignR = rebind(obj.assignR, idx);
        end

        function assignToPanel(obj, side, groupIdx)
        %ASSIGNTOPANEL  Bind a group (or 0 = all images) to 'L' or 'R'.
            if groupIdx < 0 || groupIdx > numel(obj.groups), return; end
            if upper(side) == 'L'
                obj.assignL = groupIdx;
            else
                obj.assignR = groupIdx;
            end
        end

        function m = membersFor(obj, side, nImages)
        %MEMBERSFOR  Valid image indices for a panel's bound group.
        %   Returns 1:nImages when no group is bound or the group has no
        %   in-range members, so callers can always step a non-empty list.
            if upper(side) == 'L', g = obj.assignL; else, g = obj.assignR; end
            m = [];
            if g >= 1 && g <= numel(obj.groups)
                m = obj.groups(g).members;
                m = m(m >= 1 & m <= nImages);
            end
            if isempty(m)
                m = 1:nImages;
            end
        end

        function names = groupNames(obj)
            names = cell(1, numel(obj.groups));
            for k = 1:numel(obj.groups)
                names{k} = sprintf('%s (%d)', obj.groups(k).name, ...
                    numel(obj.groups(k).members));
            end
        end
    end
end

function out = rebind(cur, removedIdx)
%REBIND  Adjust a stored group binding after group removedIdx is deleted.
    if cur == removedIdx
        out = 0;                 % the bound group is gone
    elseif cur > removedIdx
        out = cur - 1;           % indices above it shift down
    else
        out = cur;
    end
end
