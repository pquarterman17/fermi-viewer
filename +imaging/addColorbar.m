function result = addColorbar(imgSize, opts)
%ADDCOLORBAR  Build a calibrated colorbar strip for compositing onto an image.
%
%   Syntax:
%       result = imaging.addColorbar(imgSize)
%       result = imaging.addColorbar(imgSize, Colormap=parula(256), ...
%                    Range=[0, 65535], Unit='counts', Position='right')
%
%   Creates a colorbar strip as a uint8 RGB image together with tick-label
%   metadata so the caller can composite it onto a display image or burn it
%   in for export (e.g. via getframe).  No Image Processing Toolbox is
%   required.
%
%   The returned .composite function handle accepts an RGB image and returns
%   a new image that has the colorbar strip pasted on the chosen edge, with
%   a padding gap of Padding pixels in the background color.  Text labels
%   are NOT burned into the pixel data by composite() — they are returned
%   separately in .labelPositions / .labelStrings so the GUI can place
%   text() objects for on-screen display and call getframe to burn them in
%   for export (this keeps the code toolbox-free).
%
%   Inputs:
%       imgSize — [1x2] [rows, cols] of the target image
%
%   Optional Name-Value:
%       Colormap   — [Nx3] double colormap in [0,1] (default: parula(256))
%       Range      — [1x2] [minVal, maxVal] data range for tick labels
%                    (default: [0, 1])
%       Unit       — string appended to the top tick label (default: '')
%       Position   — 'right' or 'bottom' placement (default: 'right')
%       Width      — colorbar strip width in pixels (default: 20)
%       NumTicks   — number of evenly spaced tick marks (default: 5)
%       FontSize   — informational label font size in points, returned in
%                    .labelFontSize for use by text() (default: 10)
%       Padding    — gap in pixels between image edge and strip (default: 5)
%       Background — [1x3] RGB background fill colour in [0,1]
%                    (default: [0, 0, 0])
%
%   Output:
%       result — struct with fields:
%           .strip          — [H x W x 3] uint8 RGB colorbar strip
%           .labelPositions — [NumTicks x 1] pixel positions along the strip
%                             (row for 'right'; col for 'bottom') for text()
%           .labelStrings   — {NumTicks x 1} cell array of formatted strings
%           .unitString     — unit string passed in (for text() annotation)
%           .totalSize      — [rows, cols] of the full composited image
%           .labelFontSize  — FontSize value (pass to text() FontSize property)
%           .position       — Position string (for downstream logic)
%           .composite      — function handle: newImg = result.composite(rgbImg)
%                             Pastes the strip + padding onto rgbImg.  rgbImg
%                             must be uint8 RGB with size matching imgSize.
%
%   Examples:
%       % Build a right-side colorbar for a 512x512 image
%       cb = imaging.addColorbar([512, 512], Range=[0, 65535], ...
%                Unit='counts', Colormap=parula(256));
%
%       % Composite onto an RGB image for export
%       rgbImg = repmat(uint8(128), 512, 512, 3);
%       composite = cb.composite(rgbImg);
%       imwrite(composite, 'output_with_colorbar.png');
%
%       % On-screen display: use text() for labels
%       ax = axes;  image(composite);  axis image off;
%       for k = 1:numel(cb.labelStrings)
%           text(ax, cb.totalSize(2) - 2, cb.labelPositions(k), ...
%                cb.labelStrings{k}, 'Color','w', 'FontSize',cb.labelFontSize, ...
%                'HorizontalAlignment','right', 'VerticalAlignment','middle');
%       end
%
%   See also imaging.adjustContrast, imaging.computeFFT, imaging.generateThumbnail

% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    imgSize            (1,2) double {mustBePositive, mustBeInteger}
    opts.Colormap      (:,3) double {mustBeInRange(opts.Colormap, 0, 1)} = parula(256)
    opts.Range         (1,2) double = [0, 1]
    opts.Unit          (1,1) string = ''
    opts.Position      (1,1) string {mustBeMember(opts.Position, {'right','bottom'})} = 'right'
    opts.Width         (1,1) double {mustBePositive, mustBeInteger} = 20
    opts.NumTicks      (1,1) double {mustBePositive, mustBeInteger} = 5
    opts.FontSize      (1,1) double {mustBePositive}                = 10
    opts.Padding       (1,1) double {mustBeNonnegative}             = 5
    opts.Background    (1,3) double {mustBeInRange(opts.Background, 0, 1)} = [0, 0, 0]
end

nRows  = imgSize(1);
nCols  = imgSize(2);
cmap   = opts.Colormap;
nColors = size(cmap, 1);
bg     = uint8(round(opts.Background * 255));   % [1x3] uint8

% ════════════════════════════════════════════════════════════════════════
%  Build the colour strip
% ════════════════════════════════════════════════════════════════════════
switch opts.Position
    case 'right'
        stripH = nRows;
        stripW = opts.Width;

        % Map index 1..nColors linearly over the strip height.
        % Top of strip = max value (index nColors), bottom = min (index 1).
        idxVec   = round(linspace(nColors, 1, stripH))';   % [stripH x 1]
        stripRaw = cmap(idxVec, :);                         % [stripH x 3] double [0,1]

        % Replicate across width → [stripH x stripW x 3]
        strip = repmat(reshape(uint8(round(stripRaw * 255)), stripH, 1, 3), ...
                       1, stripW, 1);

    case 'bottom'
        stripH = opts.Width;
        stripW = nCols;

        % Left = min value, right = max value.
        idxVec   = round(linspace(1, nColors, stripW));     % [1 x stripW]
        stripRaw = cmap(idxVec, :);                         % [stripW x 3]

        % Replicate across height → [stripH x stripW x 3]
        strip = repmat(reshape(uint8(round(stripRaw * 255)), 1, stripW, 3), ...
                       stripH, 1, 1);
end

% ════════════════════════════════════════════════════════════════════════
%  Tick labels
% ════════════════════════════════════════════════════════════════════════
tickVals = linspace(opts.Range(1), opts.Range(2), opts.NumTicks);

% Choose a concise format: use %g (adaptive) but fall back to exponential
% for very large or very small absolute values.
absMax = max(abs(tickVals));
if absMax == 0
    fmtStr = '%.4g';
elseif absMax >= 1e5 || (absMax < 1e-3 && absMax > 0)
    fmtStr = '%.3e';
else
    % Determine decimal places needed to distinguish adjacent ticks.
    if opts.NumTicks > 1
        step = abs(tickVals(2) - tickVals(1));
        if step == 0
            fmtStr = '%.4g';
        else
            dpNeeded = max(0, ceil(-log10(step)) + 1);
            dpNeeded = min(dpNeeded, 6);
            fmtStr = sprintf('%%.%df', dpNeeded);
        end
    else
        fmtStr = '%.4g';
    end
end

labelStrings = cell(opts.NumTicks, 1);
for k = 1:opts.NumTicks
    labelStrings{k} = sprintf(fmtStr, tickVals(k));
end

% Append unit to the top tick (max value).
if strlength(opts.Unit) > 0
    labelStrings{end} = [labelStrings{end}, ' ', char(opts.Unit)];
end

% Tick pixel positions along the strip dimension.
switch opts.Position
    case 'right'
        % Strip runs top (max) to bottom (min). Ticks at same relative positions.
        labelPositions = round(linspace(1, stripH, opts.NumTicks))';   % row coords
    case 'bottom'
        % Strip runs left (min) to right (max).
        labelPositions = round(linspace(1, stripW, opts.NumTicks))';   % col coords
end

% ════════════════════════════════════════════════════════════════════════
%  Total composited image size
% ════════════════════════════════════════════════════════════════════════
padPx = round(opts.Padding);

switch opts.Position
    case 'right'
        totalRows = nRows;
        totalCols = nCols + padPx + opts.Width;
    case 'bottom'
        totalRows = nRows + padPx + opts.Width;
        totalCols = nCols;
end

% ════════════════════════════════════════════════════════════════════════
%  Composite function handle
% ════════════════════════════════════════════════════════════════════════
% Capture everything needed from this scope.
capturedStrip   = strip;
capturedPos     = opts.Position;
capturedPadPx   = padPx;
capturedStripW  = opts.Width;
capturedBg      = bg;
capturedNRows   = nRows;
capturedNCols   = nCols;
capturedTotalR  = totalRows;
capturedTotalC  = totalCols;

compositeFn = @(rgbImg) doComposite(rgbImg, capturedStrip, capturedPos, ...
    capturedPadPx, capturedStripW, capturedBg, ...
    capturedNRows, capturedNCols, capturedTotalR, capturedTotalC);

% ════════════════════════════════════════════════════════════════════════
%  Pack result
% ════════════════════════════════════════════════════════════════════════
result.strip          = strip;
result.labelPositions = labelPositions;
result.labelStrings   = labelStrings;
result.unitString     = char(opts.Unit);
result.totalSize      = [totalRows, totalCols];
result.labelFontSize  = opts.FontSize;
result.position       = char(opts.Position);
result.composite      = compositeFn;

end

% ════════════════════════════════════════════════════════════════════════
%  Local: doComposite
% ════════════════════════════════════════════════════════════════════════
function out = doComposite(rgbImg, strip, position, padPx, stripW, bg, ...
                           nRows, nCols, totalRows, totalCols)
%DOCOMPOSITE  Paste the colorbar strip onto rgbImg with a padding gap.

% Ensure input is uint8 RGB.
if ~isa(rgbImg, 'uint8')
    rgbImg = uint8(round(double(rgbImg)));
end
if ndims(rgbImg) == 2    % grayscale → replicate to RGB
    rgbImg = repmat(rgbImg, 1, 1, 3);
end

% Allocate output filled with background colour.
out = repmat(reshape(bg, 1, 1, 3), totalRows, totalCols, 1);

% Paste original image.
out(1:nRows, 1:nCols, :) = rgbImg;

% Paste strip.
switch position
    case 'right'
        stripH = size(strip, 1);
        colStart = nCols + padPx + 1;
        colEnd   = colStart + stripW - 1;
        % Clip strip height to output height (should always match, but guard).
        rEnd = min(stripH, totalRows);
        out(1:rEnd, colStart:colEnd, :) = strip(1:rEnd, :, :);

    case 'bottom'
        stripW2 = size(strip, 2);   % may differ from stripW param for 'bottom'
        rowStart = nRows + padPx + 1;
        rowEnd   = rowStart + size(strip, 1) - 1;
        cEnd = min(stripW2, totalCols);
        out(rowStart:rowEnd, 1:cEnd, :) = strip(:, 1:cEnd, :);
end

end
