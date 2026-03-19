function result = buildFigurePanel(images, opts)
%BUILDFIGUREPANEL  Assemble multiple images into a labeled multi-panel figure.
%
%   Syntax:
%       result = imaging.buildFigurePanel(images)
%       result = imaging.buildFigurePanel(images, Rows=2, Cols=3)
%       result = imaging.buildFigurePanel(images, PanelLabels={'a','b','c'}, ...
%                    LabelPosition='topleft', Gap=4, ScaleBar=sb)
%
%   Assembles a cell array of 2-D grayscale or RGB images into a single
%   composite RGB uint8 image arranged on a grid.  Panel labels are rendered
%   using an embedded 5x3 bitmap font so the function requires no display and
%   no external toolboxes.
%
%   Inputs:
%       images — cell array of 2-D [H x W] or RGB [H x W x 3] images
%
%   Optional Name-Value:
%       Rows           — grid rows  (default: auto from ceil(sqrt(N)))
%       Cols           — grid cols  (default: auto from ceil(N/Rows))
%       PanelLabels    — cell array of strings; uses 'a','b',... by default
%       LabelPosition  — 'topleft' | 'topright' | 'bottomleft' (default 'topleft')
%       LabelColor     — [R G B] 0-1 foreground (default [1 1 1] white)
%       LabelFontSize  — bitmap glyph scale factor; 1=5x3 px, 2=10x6 px, ...
%                        (default 3, giving 15x9 px glyphs)
%       Gap            — gap between panels in pixels (default 2)
%       BackgroundColor — [R G B] 0-1 fill for gaps (default [0 0 0] black)
%       ScaleBar       — struct with fields:
%                          .length   — bar length in pixels (required)
%                          .label    — string label, e.g. '100 nm' (default '')
%                          .color    — [R G B] 0-1 (default [1 1 1])
%                          .position — 'bottomright'|'bottomleft' (default 'bottomright')
%                          .panel    — which panel index to decorate (default 1)
%                          .thickness — bar thickness in pixels (default 4)
%       UniformSize    — if true, resize all images to the largest H and W
%                        found among inputs via bilinear interp2 (default true)
%
%   Output:
%       result — struct with fields:
%           .composite   — assembled [H x W x 3] uint8 image
%           .panelRects  — [N x 4] double; [topRow, leftCol, height, width]
%                          for each panel (1-based pixel coords)
%           .rows        — grid rows used
%           .cols        — grid cols used
%
%   Examples:
%       imgs = {uint16(rand(256,256)*65535), uint8(rand(128,256)*255)};
%       result = imaging.buildFigurePanel(imgs, Gap=4, LabelFontSize=3);
%       imshow(result.composite);
%
%       % With scale bar on first panel
%       sb.length = 50; sb.label = '50 nm'; sb.color = [1 1 1];
%       sb.position = 'bottomright'; sb.panel = 1; sb.thickness = 4;
%       result = imaging.buildFigurePanel(imgs, ScaleBar=sb);
%
%   See also imaging.adjustContrast, imaging.generateThumbnail

% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    images               (1,:) cell
    opts.Rows            (1,1) double {mustBePositive, mustBeInteger} = 0
    opts.Cols            (1,1) double {mustBePositive, mustBeInteger} = 0
    opts.PanelLabels     (1,:) cell   = {}
    opts.LabelPosition   (1,1) string {mustBeMember(opts.LabelPosition, ...
                             {'topleft','topright','bottomleft'})} = 'topleft'
    opts.LabelColor      (1,3) double {mustBeInRange(opts.LabelColor, 0, 1)} = [1 1 1]
    opts.LabelFontSize   (1,1) double {mustBePositive, mustBeInteger} = 3
    opts.Gap             (1,1) double {mustBeNonnegative, mustBeInteger} = 2
    opts.BackgroundColor (1,3) double {mustBeInRange(opts.BackgroundColor, 0, 1)} = [0 0 0]
    opts.ScaleBar        (1,1) struct = struct()
    opts.UniformSize     (1,1) logical = true
end

numImages = numel(images);
if numImages == 0
    error('imaging:buildFigurePanel:emptyInput', 'images cell array must not be empty.');
end

% ════════════════════════════════════════════════════════════════════════
%  Grid layout
% ════════════════════════════════════════════════════════════════════════
if opts.Rows == 0 && opts.Cols == 0
    nRows = ceil(sqrt(numImages));
    nCols = ceil(numImages / nRows);
elseif opts.Rows == 0
    nCols = opts.Cols;
    nRows = ceil(numImages / nCols);
elseif opts.Cols == 0
    nRows = opts.Rows;
    nCols = ceil(numImages / nRows);
else
    nRows = opts.Rows;
    nCols = opts.Cols;
end

if nRows * nCols < numImages
    error('imaging:buildFigurePanel:gridTooSmall', ...
        'Grid (%d x %d) too small for %d images.', nRows, nCols, numImages);
end

% ════════════════════════════════════════════════════════════════════════
%  Default panel labels: 'a', 'b', ...
% ════════════════════════════════════════════════════════════════════════
if isempty(opts.PanelLabels)
    labels = cell(1, numImages);
    for k = 1:numImages
        labels{k} = char(96 + k);   % 97='a'
    end
else
    labels = opts.PanelLabels;
    if numel(labels) < numImages
        for k = numel(labels)+1:numImages
            labels{k} = char(96 + k);
        end
    end
end

% ════════════════════════════════════════════════════════════════════════
%  Convert all inputs to RGB uint8
% ════════════════════════════════════════════════════════════════════════
rgbImages = cell(1, numImages);
for k = 1:numImages
    rgbImages{k} = toRgbUint8(images{k});
end

% ════════════════════════════════════════════════════════════════════════
%  Optionally resize to uniform dimensions
% ════════════════════════════════════════════════════════════════════════
maxH = 0;
maxW = 0;
for k = 1:numImages
    [h, w, ~] = size(rgbImages{k});
    if h > maxH, maxH = h; end
    if w > maxW, maxW = w; end
end

if opts.UniformSize
    for k = 1:numImages
        [h, w, ~] = size(rgbImages{k});
        if h ~= maxH || w ~= maxW
            rgbImages{k} = resizePanelImage(rgbImages{k}, maxH, maxW);
        end
    end
    panelH = maxH;
    panelW = maxW;
else
    panelH = maxH;
    panelW = maxW;
end

% ════════════════════════════════════════════════════════════════════════
%  Allocate composite canvas
% ════════════════════════════════════════════════════════════════════════
gap     = opts.Gap;
bgColor = uint8(round(opts.BackgroundColor * 255));    % [1 x 3] uint8

totalH = panelH * nRows + gap * (nRows - 1);
totalW = panelW * nCols + gap * (nCols - 1);

composite = zeros(totalH, totalW, 3, 'uint8');
% Fill background
for c = 1:3
    composite(:,:,c) = bgColor(c);
end

% ════════════════════════════════════════════════════════════════════════
%  Place each panel
% ════════════════════════════════════════════════════════════════════════
panelRects = zeros(numImages, 4);   % [topRow, leftCol, height, width]

for k = 1:numImages
    gridRow = ceil(k / nCols);          % 1-based row in grid
    gridCol = mod(k - 1, nCols) + 1;   % 1-based col in grid

    topRow  = (gridRow - 1) * (panelH + gap) + 1;
    leftCol = (gridCol - 1) * (panelW + gap) + 1;

    [imgH, imgW, ~] = size(rgbImages{k});

    % Actual height/width for this panel (may differ if UniformSize=false)
    pH = imgH;
    pW = imgW;

    composite(topRow:topRow+pH-1, leftCol:leftCol+pW-1, :) = rgbImages{k};

    panelRects(k, :) = [topRow, leftCol, pH, pW];
end

% ════════════════════════════════════════════════════════════════════════
%  Bitmap font (5 rows x 3 cols per glyph) for a–z, A–Z, 0–9, space
%  Each glyph is stored as a 15-element binary vector (row-major).
% ════════════════════════════════════════════════════════════════════════
bitmapFont = buildBitmapFont();

% ════════════════════════════════════════════════════════════════════════
%  Render panel labels
% ════════════════════════════════════════════════════════════════════════
scale    = opts.LabelFontSize;    % pixels per bitmap pixel
glyphH   = 5 * scale;
glyphW   = 3 * scale;
padding  = scale;                 % margin from panel edge
fgColor  = uint8(round(opts.LabelColor * 255));

for k = 1:numImages
    rect  = panelRects(k, :);   % [topRow, leftCol, height, width]
    pTop  = rect(1);
    pLeft = rect(2);
    pH    = rect(3);
    pW    = rect(4);
    label = labels{k};

    % Total text block width
    textW = numel(label) * (glyphW + scale) - scale;   % inter-glyph gap = scale
    textH = glyphH;

    % Compute top-left corner of text block
    switch opts.LabelPosition
        case 'topleft'
            txtRow = pTop  + padding;
            txtCol = pLeft + padding;
        case 'topright'
            txtRow = pTop  + padding;
            txtCol = pLeft + pW - padding - textW;
        case 'bottomleft'
            txtRow = pTop  + pH - padding - textH;
            txtCol = pLeft + padding;
        otherwise
            txtRow = pTop  + padding;
            txtCol = pLeft + padding;
    end

    % Draw a semi-transparent shadow rectangle (filled with bg-like tone)
    shadowPad = max(1, round(scale * 0.5));
    srTop  = max(1, txtRow  - shadowPad);
    srLeft = max(1, txtCol  - shadowPad);
    srBot  = min(size(composite, 1), txtRow  + textH + shadowPad);
    srRight= min(size(composite, 2), txtCol  + textW + shadowPad);
    % Darken background area by 50% toward black for contrast
    composite(srTop:srBot, srLeft:srRight, :) = ...
        uint8(double(composite(srTop:srBot, srLeft:srRight, :)) * 0.4);

    % Render each character
    for ci = 1:numel(label)
        ch      = label(ci);
        glyph   = lookupGlyph(bitmapFont, ch);   % [5 x 3] binary
        charCol = txtCol + (ci - 1) * (glyphW + scale);

        % Scale up: each bitmap pixel → scale x scale block
        for br = 1:5
            for bc = 1:3
                if glyph(br, bc)
                    rowStart = txtRow  + (br - 1) * scale;
                    colStart = charCol + (bc - 1) * scale;
                    rowEnd   = min(size(composite, 1), rowStart + scale - 1);
                    colEnd   = min(size(composite, 2), colStart + scale - 1);
                    if rowStart >= 1 && colStart >= 1
                        for ch3 = 1:3
                            composite(rowStart:rowEnd, colStart:colEnd, ch3) = fgColor(ch3);
                        end
                    end
                end
            end
        end
    end
end

% ════════════════════════════════════════════════════════════════════════
%  Scale bar
% ════════════════════════════════════════════════════════════════════════
if isfield(opts.ScaleBar, 'length') && ~isempty(opts.ScaleBar.length)
    sb = opts.ScaleBar;

    % Defaults for optional scale-bar fields
    if ~isfield(sb, 'color'),     sb.color     = [1 1 1]; end
    if ~isfield(sb, 'position'),  sb.position  = 'bottomright'; end
    if ~isfield(sb, 'panel'),     sb.panel     = 1; end
    if ~isfield(sb, 'thickness'), sb.thickness = 4; end
    if ~isfield(sb, 'label'),     sb.label     = ''; end

    sbPanelIdx = min(sb.panel, numImages);
    rect   = panelRects(sbPanelIdx, :);
    pTop   = rect(1);
    pLeft  = rect(2);
    pH     = rect(3);
    pW     = rect(4);

    sbLen   = round(sb.length);
    sbThick = max(1, round(sb.thickness));
    sbColor = uint8(round(sb.color * 255));
    sbPad   = max(4, round(padding * 2));

    switch sb.position
        case 'bottomright'
            sbRow = pTop  + pH  - sbPad - sbThick;
            sbCol = pLeft + pW  - sbPad - sbLen;
        case 'bottomleft'
            sbRow = pTop  + pH  - sbPad - sbThick;
            sbCol = pLeft + sbPad;
        otherwise
            sbRow = pTop  + pH  - sbPad - sbThick;
            sbCol = pLeft + pW  - sbPad - sbLen;
    end

    sbRow = max(1, sbRow);
    sbCol = max(1, sbCol);
    sbRowEnd = min(size(composite, 1), sbRow + sbThick - 1);
    sbColEnd = min(size(composite, 2), sbCol + sbLen  - 1);

    for c = 1:3
        composite(sbRow:sbRowEnd, sbCol:sbColEnd, c) = sbColor(c);
    end

    % Render scale bar label above the bar (using bitmap font)
    if ~isempty(sb.label)
        lblTextW = numel(sb.label) * (glyphW + scale) - scale;
        lblRow   = max(1, sbRow - glyphH - scale);
        lblCol   = sbCol + round((sbLen - lblTextW) / 2);

        for ci = 1:numel(sb.label)
            ch      = sb.label(ci);
            glyph   = lookupGlyph(bitmapFont, ch);
            charCol = lblCol + (ci - 1) * (glyphW + scale);
            for br = 1:5
                for bc = 1:3
                    if glyph(br, bc)
                        rowStart = lblRow  + (br - 1) * scale;
                        colStart = charCol + (bc - 1) * scale;
                        rowEnd   = min(size(composite, 1), rowStart + scale - 1);
                        colEnd   = min(size(composite, 2), colStart + scale - 1);
                        if rowStart >= 1 && colStart >= 1
                            for c = 1:3
                                composite(rowStart:rowEnd, colStart:colEnd, c) = sbColor(c);
                            end
                        end
                    end
                end
            end
        end
    end
end

% ════════════════════════════════════════════════════════════════════════
%  Pack result
% ════════════════════════════════════════════════════════════════════════
result.composite  = composite;
result.panelRects = panelRects;
result.rows       = nRows;
result.cols       = nCols;

end

% ════════════════════════════════════════════════════════════════════════
%  Local helper: convert any image to RGB uint8
% ════════════════════════════════════════════════════════════════════════
function rgb = toRgbUint8(img)
    if islogical(img)
        img = uint8(img) * 255;
    end

    % Normalise non-uint8 types to 0-255
    cls = class(img);
    switch cls
        case 'uint8'
            d = double(img);
        case 'uint16'
            d = double(img) / 65535 * 255;
        case 'uint32'
            d = double(img) / double(intmax('uint32')) * 255;
        case 'double'
            mn = min(img(:));
            mx = max(img(:));
            if mx > mn
                d = (double(img) - mn) / (mx - mn) * 255;
            else
                d = zeros(size(img));
            end
        case 'single'
            mn = min(img(:));
            mx = max(img(:));
            if mx > mn
                d = (double(img) - mn) / (mx - mn) * 255;
            else
                d = zeros(size(img));
            end
        otherwise
            d = double(img);
            mn = min(d(:)); mx = max(d(:));
            if mx > mn, d = (d - mn)/(mx - mn) * 255; end
    end
    d = max(0, min(255, d));

    if ndims(img) == 2 %#ok<ISMAT>
        % Grayscale → replicate to 3 channels
        u = uint8(round(d));
        rgb = cat(3, u, u, u);
    elseif ndims(img) == 3 && size(img, 3) == 3
        rgb = uint8(round(d));
    elseif ndims(img) == 3 && size(img, 3) == 4
        % RGBA → drop alpha
        rgb = uint8(round(d(:,:,1:3)));
    else
        error('imaging:buildFigurePanel:unsupportedChannels', ...
            'Image must be 2-D grayscale or [H x W x 3] RGB.');
    end
end

% ════════════════════════════════════════════════════════════════════════
%  Local helper: bilinear resize of an RGB uint8 panel
% ════════════════════════════════════════════════════════════════════════
function out = resizePanelImage(img, newH, newW)
    [H, W, ~] = size(img);
    rowQ = linspace(1, H, newH)';
    colQ = linspace(1, W, newW);
    [colGrid, rowGrid] = meshgrid(colQ, rowQ);
    out = zeros(newH, newW, 3, 'uint8');
    for c = 1:3
        ch = interp2(double(img(:,:,c)), colGrid, rowGrid, 'linear');
        out(:,:,c) = uint8(max(0, min(255, round(ch))));
    end
end

% ════════════════════════════════════════════════════════════════════════
%  Local helper: build bitmap font lookup table
%  Each glyph is a [5 x 3] binary matrix (5 rows, 3 cols).
%  Covers a-z, A-Z, 0-9, space, and common punctuation ( . - / ' ).
% ════════════════════════════════════════════════════════════════════════
function font = buildBitmapFont()
    % Glyphs are 5 rows x 3 cols, stored as 15-element row vectors
    % (row-major: pixel (r,c) = vec(3*(r-1)+c)).

    % ------ lowercase a-z ------
    g = containers.Map('KeyType','char','ValueType','any');

    g('a') = [0,1,0, 0,1,1, 1,0,1, 1,1,1, 1,0,1];
    g('b') = [1,0,0, 1,1,0, 1,0,1, 1,1,0, 1,1,0];  % b
    g('c') = [0,1,1, 1,0,0, 1,0,0, 1,0,0, 0,1,1];
    g('d') = [0,0,1, 0,1,1, 1,0,1, 1,0,1, 0,1,1];
    g('e') = [0,1,1, 1,0,0, 1,1,0, 1,0,0, 0,1,1];
    g('f') = [0,1,1, 1,0,0, 1,1,0, 1,0,0, 1,0,0];
    g('g') = [0,1,1, 1,0,0, 1,0,1, 1,0,1, 0,1,1];
    g('h') = [1,0,1, 1,0,1, 1,1,1, 1,0,1, 1,0,1];
    g('i') = [1,1,1, 0,1,0, 0,1,0, 0,1,0, 1,1,1];
    g('j') = [0,0,1, 0,0,1, 0,0,1, 1,0,1, 0,1,0];
    g('k') = [1,0,1, 1,1,0, 1,0,0, 1,1,0, 1,0,1];
    g('l') = [1,0,0, 1,0,0, 1,0,0, 1,0,0, 1,1,1];
    g('m') = [1,0,1, 1,1,1, 1,0,1, 1,0,1, 1,0,1];
    g('n') = [1,1,0, 1,0,1, 1,0,1, 1,0,1, 1,0,1];
    g('o') = [0,1,0, 1,0,1, 1,0,1, 1,0,1, 0,1,0];
    g('p') = [1,1,0, 1,0,1, 1,1,0, 1,0,0, 1,0,0];
    g('q') = [0,1,0, 1,0,1, 1,0,1, 0,1,1, 0,0,1];
    g('r') = [1,1,0, 1,0,1, 1,1,0, 1,1,0, 1,0,1];
    g('s') = [0,1,1, 1,0,0, 0,1,0, 0,0,1, 1,1,0];
    g('t') = [1,1,1, 0,1,0, 0,1,0, 0,1,0, 0,1,0];
    g('u') = [1,0,1, 1,0,1, 1,0,1, 1,0,1, 0,1,1];
    g('v') = [1,0,1, 1,0,1, 1,0,1, 1,0,1, 0,1,0];
    g('w') = [1,0,1, 1,0,1, 1,0,1, 1,1,1, 1,0,1];
    g('x') = [1,0,1, 1,0,1, 0,1,0, 1,0,1, 1,0,1];
    g('y') = [1,0,1, 1,0,1, 0,1,0, 0,1,0, 0,1,0];
    g('z') = [1,1,1, 0,0,1, 0,1,0, 1,0,0, 1,1,1];

    % ------ uppercase A-Z (reuse lowercase glyphs, add caps) ------
    g('A') = [0,1,0, 1,0,1, 1,1,1, 1,0,1, 1,0,1];
    g('B') = [1,1,0, 1,0,1, 1,1,0, 1,0,1, 1,1,0];
    g('C') = [0,1,1, 1,0,0, 1,0,0, 1,0,0, 0,1,1];
    g('D') = [1,1,0, 1,0,1, 1,0,1, 1,0,1, 1,1,0];
    g('E') = [1,1,1, 1,0,0, 1,1,0, 1,0,0, 1,1,1];
    g('F') = [1,1,1, 1,0,0, 1,1,0, 1,0,0, 1,0,0];
    g('G') = [0,1,1, 1,0,0, 1,0,1, 1,0,1, 0,1,1];
    g('H') = [1,0,1, 1,0,1, 1,1,1, 1,0,1, 1,0,1];
    g('I') = [1,1,1, 0,1,0, 0,1,0, 0,1,0, 1,1,1];
    g('J') = [0,1,1, 0,0,1, 0,0,1, 1,0,1, 0,1,0];
    g('K') = [1,0,1, 1,1,0, 1,0,0, 1,1,0, 1,0,1];
    g('L') = [1,0,0, 1,0,0, 1,0,0, 1,0,0, 1,1,1];
    g('M') = [1,0,1, 1,1,1, 1,0,1, 1,0,1, 1,0,1];
    g('N') = [1,0,1, 1,1,1, 1,1,1, 1,0,1, 1,0,1];
    g('O') = [0,1,0, 1,0,1, 1,0,1, 1,0,1, 0,1,0];
    g('P') = [1,1,0, 1,0,1, 1,1,0, 1,0,0, 1,0,0];
    g('Q') = [0,1,0, 1,0,1, 1,0,1, 1,1,1, 0,1,1];
    g('R') = [1,1,0, 1,0,1, 1,1,0, 1,1,0, 1,0,1];
    g('S') = [0,1,1, 1,0,0, 0,1,0, 0,0,1, 1,1,0];
    g('T') = [1,1,1, 0,1,0, 0,1,0, 0,1,0, 0,1,0];
    g('U') = [1,0,1, 1,0,1, 1,0,1, 1,0,1, 0,1,1];
    g('V') = [1,0,1, 1,0,1, 1,0,1, 1,0,1, 0,1,0];
    g('W') = [1,0,1, 1,0,1, 1,0,1, 1,1,1, 1,0,1];
    g('X') = [1,0,1, 1,0,1, 0,1,0, 1,0,1, 1,0,1];
    g('Y') = [1,0,1, 1,0,1, 0,1,1, 0,1,0, 0,1,0];
    g('Z') = [1,1,1, 0,0,1, 0,1,0, 1,0,0, 1,1,1];

    % ------ digits 0-9 ------
    g('0') = [0,1,0, 1,0,1, 1,0,1, 1,0,1, 0,1,0];
    g('1') = [0,1,0, 1,1,0, 0,1,0, 0,1,0, 1,1,1];
    g('2') = [1,1,0, 0,0,1, 0,1,0, 1,0,0, 1,1,1];
    g('3') = [1,1,0, 0,0,1, 0,1,0, 0,0,1, 1,1,0];
    g('4') = [1,0,1, 1,0,1, 1,1,1, 0,0,1, 0,0,1];
    g('5') = [1,1,1, 1,0,0, 1,1,0, 0,0,1, 1,1,0];
    g('6') = [0,1,1, 1,0,0, 1,1,0, 1,0,1, 0,1,0];
    g('7') = [1,1,1, 0,0,1, 0,1,0, 0,1,0, 0,1,0];
    g('8') = [0,1,0, 1,0,1, 0,1,0, 1,0,1, 0,1,0];
    g('9') = [0,1,0, 1,0,1, 0,1,1, 0,0,1, 1,1,0];

    % ------ common punctuation ------
    g(' ') = [0,0,0, 0,0,0, 0,0,0, 0,0,0, 0,0,0];
    g('.') = [0,0,0, 0,0,0, 0,0,0, 0,0,0, 0,1,0];
    g('-') = [0,0,0, 0,0,0, 1,1,1, 0,0,0, 0,0,0];
    g('/') = [0,0,1, 0,0,1, 0,1,0, 1,0,0, 1,0,0];
    g('''') = [0,1,0, 0,1,0, 0,0,0, 0,0,0, 0,0,0];  % apostrophe

    font = g;
end

% ════════════════════════════════════════════════════════════════════════
%  Local helper: look up a character glyph (5 x 3 binary matrix)
%  Returns a question-mark-like pattern for unknown characters.
% ════════════════════════════════════════════════════════════════════════
function glyph = lookupGlyph(font, ch)
    if isKey(font, ch)
        vec   = font(ch);
        glyph = reshape(vec, 3, 5)';   % reshape row-major to [5 x 3]
    else
        % Unknown character: solid block
        glyph = ones(5, 3);
    end
end
