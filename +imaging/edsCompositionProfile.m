function profile = edsCompositionProfile(atomicPctMaps, elements, x1, y1, x2, y2, opts)
%EDSCOMPOSITIONPROFILE  Extract a composition line profile from EDS maps.
%
%   Syntax:
%       profile = imaging.edsCompositionProfile(atomicPctMaps, elements, ...
%                     x1, y1, x2, y2)
%       profile = imaging.edsCompositionProfile(atomicPctMaps, elements, ...
%                     x1, y1, x2, y2, NumPoints=200, PixelSize=0.5, PixelUnit='nm')
%
%   Samples atomic% along a straight line from (x1,y1) to (x2,y2) using
%   bilinear interpolation (interp2).  Coordinates follow the MATLAB image
%   convention: x is the column index (horizontal), y is the row index
%   (vertical), both 1-based.
%
%   When Width > 1 the profile is averaged over a band of parallel lines
%   centred on the requested line.  Perpendicular offsets are computed in
%   pixel space and clipped to the map boundaries before interpolation.
%
%   Inputs:
%       atomicPctMaps — {1 x N} cell of [H x W] double atomic% maps
%       elements      — {1 x N} cell of element symbol strings
%       x1, y1        — start point (column, row) in pixel coordinates
%       x2, y2        — end   point (column, row) in pixel coordinates
%
%   Optional Name-Value:
%       NumPoints  — number of sample points along the line (default: 200)
%       PixelSize  — physical size of one pixel (default: 1)
%       PixelUnit  — unit string for the distance axis (default: 'px')
%       Width      — averaging width perpendicular to the profile line,
%                    in pixels (default: 1 = no averaging)
%
%   Output:
%       profile — struct with fields:
%           .distance   — [M x 1] distance along the line
%           .atomicPct  — [M x N] atomic % at each sample point for each element
%           .elements   — {1 x N} element labels
%           .unit       — distance unit string
%           .startPoint — [x1, y1]
%           .endPoint   — [x2, y2]
%
%   Examples:
%       % Simple profile across an interface
%       prof = imaging.edsCompositionProfile(res.atomicPctMaps, res.elements, ...
%                  10, 128, 500, 128);
%       plot(prof.distance, prof.atomicPct);
%       legend(prof.elements);
%       xlabel('Distance (px)'); ylabel('Atomic %');
%
%       % Calibrated profile with 5-pixel averaging width
%       prof = imaging.edsCompositionProfile(res.atomicPctMaps, res.elements, ...
%                  10, 128, 500, 128, PixelSize=0.42, PixelUnit='nm', Width=5);
%
%   See also imaging.cliffLorimer, imaging.lineProfile

% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    atomicPctMaps (1,:) cell
    elements      (1,:) cell
    x1            (1,1) double
    y1            (1,1) double
    x2            (1,1) double
    y2            (1,1) double
    opts.NumPoints  (1,1) double {mustBePositive, mustBeInteger} = 200
    opts.PixelSize  (1,1) double {mustBePositive}                = 1
    opts.PixelUnit  (1,1) string                                 = 'px'
    opts.Width      (1,1) double {mustBePositive}                = 1
end

% ════════════════════════════════════════════════════════════════════════
%  Validate inputs
% ════════════════════════════════════════════════════════════════════════
N = numel(elements);
if numel(atomicPctMaps) ~= N
    error('edsCompositionProfile:sizeMismatch', ...
        'atomicPctMaps and elements must have the same length.');
end

[H, W] = size(atomicPctMaps{1});
for i = 2:N
    if ~isequal(size(atomicPctMaps{i}), [H W])
        error('edsCompositionProfile:mapSizeMismatch', ...
            'All atomicPctMaps must be the same size.');
    end
end

M = opts.NumPoints;

% ════════════════════════════════════════════════════════════════════════
%  Sample coordinates along the primary line
% ════════════════════════════════════════════════════════════════════════
xi = linspace(x1, x2, M)';      % [M x 1] column coords (interp2 Xq)
yi = linspace(y1, y2, M)';      % [M x 1] row    coords (interp2 Yq)

% ════════════════════════════════════════════════════════════════════════
%  Perpendicular direction unit vector (for Width > 1 averaging)
% ════════════════════════════════════════════════════════════════════════
dx   = x2 - x1;
dy   = y2 - y1;
lineLen = sqrt(dx^2 + dy^2);

if lineLen == 0
    % Degenerate: start == end; return zeros
    profile.distance   = zeros(M, 1);
    profile.atomicPct  = zeros(M, N);
    profile.elements   = elements;
    profile.unit       = char(opts.PixelUnit);
    profile.startPoint = [x1, y1];
    profile.endPoint   = [x2, y2];
    return
end

% Unit vector perpendicular to the line (rotate 90°)
perpX = -dy / lineLen;   % column shift per unit offset
perpY =  dx / lineLen;   % row    shift per unit offset

% ════════════════════════════════════════════════════════════════════════
%  Interpolate each element map along the (optionally averaged) line
% ════════════════════════════════════════════════════════════════════════
nOffsets = round(opts.Width);
if nOffsets < 1
    nOffsets = 1;
end

% Perpendicular offset positions (symmetric around centre)
if nOffsets == 1
    offsets = 0;
else
    offsets = linspace(-(nOffsets-1)/2, (nOffsets-1)/2, nOffsets);
end

atomicPctOut = zeros(M, N);

for i = 1:N
    mapData = double(atomicPctMaps{i});
    accumVals = zeros(M, 1);

    for k = 1:nOffsets
        xq = xi + offsets(k) * perpX;    % [M x 1]
        yq = yi + offsets(k) * perpY;    % [M x 1]

        % Clip to map bounds so interp2 returns NaN only for true out-of-bounds
        xq = max(1, min(W, xq));
        yq = max(1, min(H, yq));

        vals = interp2(mapData, xq, yq, 'linear', NaN);
        vals(isnan(vals)) = 0;
        accumVals = accumVals + vals;
    end

    atomicPctOut(:, i) = accumVals / nOffsets;
end

% ════════════════════════════════════════════════════════════════════════
%  Distance axis
% ════════════════════════════════════════════════════════════════════════
distPx  = linspace(0, lineLen, M)';
distOut = distPx * opts.PixelSize;

% ════════════════════════════════════════════════════════════════════════
%  Assemble output struct
% ════════════════════════════════════════════════════════════════════════
profile.distance   = distOut;
profile.atomicPct  = atomicPctOut;
profile.elements   = elements;
profile.unit       = char(opts.PixelUnit);
profile.startPoint = [x1, y1];
profile.endPoint   = [x2, y2];

end
