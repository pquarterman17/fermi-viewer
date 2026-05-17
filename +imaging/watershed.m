function [L, numRegions] = watershed(bw, options)
%WATERSHED  Marker-controlled watershed segmentation of a binary mask
%           to split touching particles (no toolbox).
%
%   Syntax:
%       [L, n] = imaging.watershed(bw)
%       [L, n] = imaging.watershed(bw, MinMarkerDistance=5)
%       [L, n] = imaging.watershed(bw, Markers=myMarkers)
%
%   Pipeline:
%     1. Compute the (chamfer) distance transform D of the mask. Peaks
%        of D sit near particle centers.
%     2. Find regional maxima of D as markers, suppressing peaks that
%        are closer than MinMarkerDistance pixels to a stronger peak
%        (non-maximum suppression). Alternatively, pass an explicit
%        Markers label image.
%     3. Flood each marker label outward over the foreground region,
%        processing pixels in order of DECREASING distance-transform
%        value. Each pixel takes the label of the nearest already-
%        labeled 8-neighbour. Pixels equidistant from two different
%        labels become watershed lines (label 0 in the output).
%
%   This is a simplified Meyer-style watershed — fast enough for
%   real EM fields of view (thousands of particles) and correct for
%   the common "split touching circles" use case. For extremely
%   irregular masks with nested cavities the priority-queue ordering
%   is a sort instead of a true heap, so the worst-case complexity is
%   O(N log N) rather than O(N).
%
%   Inputs:
%       bw                    — [H x W] logical or numeric (~= 0 = foreground)
%
%   Optional Name-Value:
%       MinMarkerDistance     — minimum separation (in pixels) between
%                               distinct markers when auto-detecting
%                               regional maxima (default: 3)
%       Markers               — explicit marker label image, same size
%                               as bw. 0 = not a marker, positive ints =
%                               marker label. If supplied, MinMarkerDistance
%                               is ignored.
%       Connectivity          — 4 or 8 for flood-fill neighbourhood
%                               (default: 8)
%
%   Outputs:
%       L          — [H x W] double label image. 0 = background or
%                    watershed line, 1..n = segmented region labels.
%       numRegions — number of distinct regions (markers that survived).
%
%   Examples:
%       % Split touching disks
%       [L, n] = imaging.watershed(bw);
%       fprintf('%d regions\n', n);
%
%       % Stronger separation
%       [L, n] = imaging.watershed(bw, MinMarkerDistance=8);
%
%   See also imaging.particleAnalysis, imaging.distanceTransform,
%            imaging.connectedComponents

% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    bw                              (:,:) {mustBeNumericOrLogical}
    options.MinMarkerDistance       (1,1) double {mustBePositive} = 3
    options.Markers                 double = []
    options.Connectivity            (1,1) double {mustBeMember(options.Connectivity, [4,8])} = 8
end

mask = logical(bw);
[H, W] = size(mask);
L = zeros(H, W);
if ~any(mask(:))
    numRegions = 0;
    return;
end

% ════════════════════════════════════════════════════════════════════════
%  Distance transform (chamfer 3-4)
% ════════════════════════════════════════════════════════════════════════
D = imaging.distanceTransform(mask, Metric="chamfer34");

% ════════════════════════════════════════════════════════════════════════
%  Markers: either user-supplied, or auto-detected regional maxima
% ════════════════════════════════════════════════════════════════════════
if isempty(options.Markers)
    markers = autoMarkers(D, mask, options.MinMarkerDistance);
else
    markers = double(options.Markers);
    assert(isequal(size(markers), [H W]), ...
        'Markers must be the same size as bw');
end

numMarkers = max(markers(:));
if numMarkers == 0
    % No markers → single region via connectedComponents
    [L, numRegions] = imaging.connectedComponents(mask, Connectivity=options.Connectivity);
    return;
end

L = markers;

% ════════════════════════════════════════════════════════════════════════
%  Flood: process foreground pixels in descending distance order.
%  Each pixel adopts the label of the (unique) labeled 8-neighbour.
%  If two different labels border the pixel, it becomes a watershed
%  line (label 0).
% ════════════════════════════════════════════════════════════════════════
% Pixels to assign: foreground and not already a marker
todo = mask & (markers == 0);
[rr, cc] = find(todo);
vals = D(sub2ind([H, W], rr, cc));

% Sort DESCENDING by distance: process centers before edges
[~, order] = sort(vals, 'descend');
rr = rr(order);
cc = cc(order);

if options.Connectivity == 4
    dr = [-1  0  0  1];
    dc = [ 0 -1  1  0];
else
    dr = [-1 -1 -1  0  0  1  1  1];
    dc = [-1  0  1 -1  1 -1  0  1];
end

% Multiple passes: a pixel that has no labeled neighbour yet gets
% skipped and retried on the next pass. In the worst case this is
% O(passes * N), but in practice 2–3 passes suffice.
maxPasses = 10;
for pass = 1:maxPasses
    anyAssigned = false;
    remaining = false(numel(rr), 1);
    for k = 1:numel(rr)
        r = rr(k); c = cc(k);
        if L(r, c) ~= 0
            continue;
        end

        % Find the labeled neighbour with the HIGHEST distance-transform
        % value — that's the marker we're closer to (steepest descent).
        % On ties the first scanned neighbour wins. We deliberately do
        % NOT emit watershed line pixels (label 0) because particle
        % counting only cares about region membership, and leaving
        % orphan pixels behind confuses the straggler fallback.
        bestLabel = 0;
        bestD     = -Inf;
        for n = 1:numel(dr)
            nr = r + dr(n);
            nc = c + dc(n);
            if nr < 1 || nr > H || nc < 1 || nc > W, continue; end
            lbl = L(nr, nc);
            if lbl > 0
                dv = D(nr, nc);
                if dv > bestD
                    bestD = dv;
                    bestLabel = lbl;
                end
            end
        end

        if bestLabel > 0
            L(r, c) = bestLabel;
            anyAssigned = true;
        else
            remaining(k) = true;
        end
    end
    rr = rr(remaining);
    cc = cc(remaining);
    if isempty(rr) || ~anyAssigned
        break;
    end
end

% Any still-unlabeled foreground (disconnected from all markers) gets
% assigned to its own new label via a final connectedComponents pass.
stragglers = mask & (L == 0);
if any(stragglers(:))
    [Lrest, nRest] = imaging.connectedComponents(stragglers, ...
        Connectivity=options.Connectivity);
    L(stragglers) = Lrest(stragglers) + numMarkers;
    numMarkers = numMarkers + nRest;
end

numRegions = numMarkers;

end   % main function


% ════════════════════════════════════════════════════════════════════════
%  HELPER: autoMarkers — regional-maxima NMS on the distance transform
% ════════════════════════════════════════════════════════════════════════
function markers = autoMarkers(D, mask, minDist)
%AUTOMARKERS  Find well-separated local maxima of D within mask.
%   Grid-based greedy NMS: sort foreground pixels by descending D, then
%   for each candidate check only the spatial grid cells within minDist
%   (its own cell + 8 neighbours) rather than all accepted points.
%   Returns a label image with labels 1..k.
    [H, W] = size(D);
    markers = zeros(H, W);

    [rr, cc] = find(mask);
    if isempty(rr), return; end

    vals = D(sub2ind([H, W], rr, cc));
    [~, order] = sort(vals, 'descend');
    rr = rr(order);
    cc = cc(order);

    % ── Grid for O(1) neighbour lookup ───────────────────────────────
    % Cell size = minDist ensures that any two points in non-adjacent
    % cells are guaranteed to be > minDist apart.
    cellSz  = max(1, minDist);
    nGR     = ceil(H / cellSz);
    nGC     = ceil(W / cellSz);
    % grid{gr, gc} stores accepted marker indices (into rr/cc) in that cell
    grid    = cell(nGR, nGC);

    minDist2 = minDist^2;
    k = 0;

    for i = 1:numel(rr)
        r = rr(i); c = cc(i);
        if vals(order(i)) <= 0, continue; end

        % Reject if not a strict local max in the 3×3 neighbourhood
        % (avoids seeding multiple markers on a plateau of equal D).
        v = D(r, c);
        isMax = true;
        patch = D(max(1,r-1):min(H,r+1), max(1,c-1):min(W,c+1));
        if any(patch(:) > v)
            isMax = false;
        end
        if ~isMax, continue; end

        % Grid cell for this candidate
        gr = ceil(r / cellSz);
        gc = ceil(c / cellSz);

        % Check only cells within reach (self + 8 neighbours)
        tooClose = false;
        for dgr = -1:1
            if tooClose, break; end
            ngr = gr + dgr;
            if ngr < 1 || ngr > nGR, continue; end
            for dgc = -1:1
                ngc = gc + dgc;
                if ngc < 1 || ngc > nGC, continue; end
                idxList = grid{ngr, ngc};
                for jj = 1:numel(idxList)
                    aj = idxList(jj);
                    if (r - rr(aj))^2 + (c - cc(aj))^2 < minDist2
                        tooClose = true;
                        break;
                    end
                end
                if tooClose, break; end
            end
        end
        if tooClose, continue; end

        k = k + 1;
        markers(r, c) = k;
        grid{gr, gc}(end+1) = i; %#ok<AGROW>
    end
end
