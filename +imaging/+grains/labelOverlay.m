function rgb = labelOverlay(labels, options)
%LABELOVERLAY  Render a grain label map as a colored RGB overlay.
%
%   Syntax:
%       rgb = imaging.grains.labelOverlay(labels)
%       rgb = imaging.grains.labelOverlay(labels, BaseImage=img, Boundary=mask)
%
%   Produces an [H x W x 3] RGB image colouring each grain with a distinct,
%   deterministic colour, optionally blended over a grayscale base image and
%   with the grain-boundary network drawn on top. For display in the GUI or
%   export to PNG/TIFF.
%
%   Colours are assigned by evenly spacing hues around the HSV wheel, so the
%   same label map always yields the same colours (reproducible figures).
%   No Image Processing Toolbox required (hsv2rgb is base MATLAB).
%
%   Inputs:
%       labels        — [H x W] integer grain label map (0 = background).
%
%   Optional Name-Value:
%       BaseImage     — [H x W] grayscale image to blend the colours over
%                       (default []: solid Background where unlabelled). Scaled
%                       to [0,1] internally.
%       Boundary      — [H x W] logical boundary mask to draw (default []:
%                       none). Typically grainStats result .boundaryMask.
%       Alpha         — colour opacity over BaseImage in [0,1] (default 0.5).
%       BoundaryColor — [1 x 3] RGB for boundary pixels (default [0 0 0]).
%       Background    — [1 x 3] RGB for unlabelled pixels when no BaseImage
%                       (default [0 0 0]).
%       Seed          — hue-rotation offset for the palette (default 0). Change
%                       to recolour without altering the segmentation.
%
%   Output:
%       rgb           — [H x W x 3] double image in [0,1].
%
%   See also imaging.grains.grainStats, imaging.grains.segmentAuto

arguments
    labels                (:,:) {mustBeNumeric}
    options.BaseImage     double = []
    options.Boundary      (:,:) = []
    options.Alpha         (1,1) double {mustBeInRange(options.Alpha, 0, 1)} = 0.5
    options.BoundaryColor (1,3) double = [0 0 0]
    options.Background    (1,3) double = [0 0 0]
    options.Seed          (1,1) double = 0
end

L = double(labels);
[H, W] = size(L);
nLab = max(L(:));

% ── Deterministic palette (HSV hues, shuffled so neighbours differ) ─────
if nLab > 0
    hues = mod((0:nLab-1) / nLab + options.Seed, 1);
    % Bit-reversal-style spread so adjacent labels aren't adjacent hues.
    [~, order] = sort(mod((1:nLab) * 0.61803398875, 1));   % golden-ratio scramble
    hues = hues(order);
    palette = hsv2rgb([hues(:), ones(nLab, 1), ones(nLab, 1)]);   % [nLab x 3]
else
    palette = zeros(0, 3);
end

% ── Per-pixel colour ────────────────────────────────────────────────────
R = zeros(H, W); G = zeros(H, W); B = zeros(H, W);
R(:) = options.Background(1);
G(:) = options.Background(2);
B(:) = options.Background(3);

for k = 1:nLab
    m = (L == k);
    if any(m(:))
        R(m) = palette(k, 1);
        G(m) = palette(k, 2);
        B(m) = palette(k, 3);
    end
end
rgb = cat(3, R, G, B);

% ── Blend over the base image ───────────────────────────────────────────
if ~isempty(options.BaseImage)
    base = double(options.BaseImage);
    lo = min(base(:)); hi = max(base(:));
    if hi > lo
        base = (base - lo) / (hi - lo);
    else
        base = zeros(size(base));
    end
    base3 = cat(3, base, base, base);
    labeled3 = repmat(L > 0, 1, 1, 3);
    % Blend only where there is a grain colour; leave background = base.
    rgb = labeled3 .* (options.Alpha * rgb + (1 - options.Alpha) * base3) ...
        + ~labeled3 .* base3;
end

% ── Draw boundaries ─────────────────────────────────────────────────────
if ~isempty(options.Boundary)
    bnd = logical(options.Boundary);
    if ~isequal(size(bnd), [H, W])
        error('labelOverlay:boundarySize', 'Boundary must match labels size.');
    end
    chans = {options.BoundaryColor(1), options.BoundaryColor(2), options.BoundaryColor(3)};
    for c = 1:3
        ch = rgb(:, :, c);
        ch(bnd) = chans{c};
        rgb(:, :, c) = ch;
    end
end

rgb = min(max(rgb, 0), 1);
end
