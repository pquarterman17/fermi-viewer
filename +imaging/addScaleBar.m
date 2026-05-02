function hBar = addScaleBar(ax, PixelSize, PixelUnit, options)
%ADDSCALEBAR  Draw a calibrated scale bar overlay on an image axes.
%
%   Syntax:
%       hBar = imaging.addScaleBar(ax, PixelSize, PixelUnit)
%       hBar = imaging.addScaleBar(ax, PixelSize, PixelUnit, ...
%                  Position='bottom-left', Color=[0 0 0], FontSize=10)
%
%   Draws a scale bar (rectangle + text label) on the given axes using
%   a "nice" round length chosen to be approximately 1/5 of the axes
%   width.  All graphics objects use HandleVisibility='off' so they are
%   not included in legend entries or cleared by cla().
%
%   Inputs:
%       ax         — axes handle on which to draw
%       PixelSize  — physical size of one pixel (e.g. 2.4)
%       PixelUnit  — unit string (e.g. 'nm', 'um')
%
%   Optional Name-Value:
%       Position   — bar corner: 'bottom-right' (default) | 'bottom-left' |
%                    'top-right' | 'top-left'
%       Color      — [1x3] RGB colour (default: [1 1 1])
%       FontSize   — label font size in points (default: 12)
%       BarHeight  — bar height as a fraction of image height (default: 0.02)
%       BarLength  — explicit bar length (numeric, in BarUnit). 0 or NaN =
%                    auto-pick a nice round length ≈ 1/5 of axes width.
%       BarUnit    — unit for BarLength: 'um' | 'nm' | 'A' | 'angstrom' |
%                    'Å'. Ignored when BarLength is 0/NaN. Converted to
%                    PixelUnit internally.
%
%   Output:
%       hBar — struct with fields .bar (rectangle handle) and .label (text handle);
%              pass to delete(hBar.bar); delete(hBar.label) to remove the overlay
%
%   Examples:
%       hBar = imaging.addScaleBar(gca, 2.4, 'nm');
%       % Remove later:
%       delete(hBar.bar); delete(hBar.label);
%
%   See also imaging.measureDistance, imaging.lineProfile

% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    ax               (1,1) {mustBeA(ax, 'matlab.graphics.axis.Axes')}
    PixelSize        (1,1) double {mustBePositive}
    PixelUnit        (1,1) string
    options.Position (1,1) string {mustBeMember(options.Position, ...
                         {'bottom-right','bottom-left','top-right','top-left'})} ...
                         = 'bottom-right'
    options.Color    (1,3) double = [1 1 1]
    options.FontSize (1,1) double {mustBePositive} = 12
    options.BarHeight (1,1) double {mustBePositive} = 0.02
    options.BarLength (1,1) double = 0
    options.BarUnit  (1,1) string = ""
end

% ════════════════════════════════════════════════════════════════════════
%  Choose bar length — explicit override, else a nice round ~1/5 width
% ════════════════════════════════════════════════════════════════════════
xLims = ax.XLim;
yLims = ax.YLim;

axWidthPx = abs(xLims(2) - xLims(1));   % width in data (pixel) units

if options.BarLength > 0 && isfinite(options.BarLength)
    % User-specified length. Convert to PixelUnit if BarUnit provided.
    if strlength(options.BarUnit) > 0
        scale = unitFactor(options.BarUnit) / unitFactor(PixelUnit);
    else
        scale = 1;
    end
    barLenPhys = options.BarLength;                % in BarUnit (or PixelUnit if unset)
    barLenPx   = barLenPhys * scale / PixelSize;   % convert to PixelUnit then to data px
    % Label in the unit the user asked for; fall back to PixelUnit if unset
    if strlength(options.BarUnit) > 0
        labelUnit = char(options.BarUnit);
    else
        labelUnit = char(PixelUnit);
    end
else
    targetPhys   = axWidthPx * PixelSize / 5;
    niceLengths  = [1 2 5 10 20 50 100 200 500 1000];
    [~, idx]     = min(abs(niceLengths - targetPhys));
    barLenPhys   = niceLengths(idx);
    barLenPx     = barLenPhys / PixelSize;
    labelUnit    = char(PixelUnit);
end

% ════════════════════════════════════════════════════════════════════════
%  Bar geometry
% ════════════════════════════════════════════════════════════════════════
axH    = abs(yLims(2) - yLims(1));
barH   = axH * options.BarHeight;
margin = barLenPx * 0.3;                   % inset from edge

switch options.Position
    case 'bottom-right'
        barX = xLims(2) - margin - barLenPx;
        barY = yLims(2) - margin - barH;    % yLims(2) is bottom when axis is not flipped
    case 'bottom-left'
        barX = xLims(1) + margin;
        barY = yLims(2) - margin - barH;
    case 'top-right'
        barX = xLims(2) - margin - barLenPx;
        barY = yLims(1) + margin;
    case 'top-left'
        barX = xLims(1) + margin;
        barY = yLims(1) + margin;
end

% ════════════════════════════════════════════════════════════════════════
%  Draw
% ════════════════════════════════════════════════════════════════════════
hRec = rectangle(ax, ...
    'Position',        [barX, barY, barLenPx, barH], ...
    'FaceColor',       options.Color, ...
    'EdgeColor',       options.Color, ...
    'HandleVisibility','off');

% Centre label horizontally; place above bar for bottom, below for top
labelX = barX + barLenPx / 2;
% Gap between bar edge and label = barH * 0.425 (15% tighter than the
% original 0.5 — keeps the label visually associated with the bar).
switch options.Position
    case {'bottom-right', 'bottom-left'}
        labelY = barY - barH * 0.425;
        vAlign = 'bottom';
    case {'top-right', 'top-left'}
        labelY = barY + barH * 1.425;
        vAlign = 'top';
    otherwise
        labelY = barY - barH * 0.425;
        vAlign = 'bottom';
end

if barLenPhys == round(barLenPhys)
    labelStr = sprintf('%d %s', round(barLenPhys), labelUnit);
else
    labelStr = sprintf('%.2g %s', barLenPhys, labelUnit);
end

hTxt = text(ax, labelX, labelY, labelStr, ...
    'Color',            options.Color, ...
    'FontSize',         options.FontSize, ...
    'HorizontalAlignment', 'center', ...
    'VerticalAlignment',   vAlign, ...
    'HandleVisibility', 'off');

% ════════════════════════════════════════════════════════════════════════
%  Return handles
% ════════════════════════════════════════════════════════════════════════
hBar.bar   = hRec;
hBar.label = hTxt;

end

% ════════════════════════════════════════════════════════════════════════
%  LOCAL: unit conversion factor to nm
% ════════════════════════════════════════════════════════════════════════
function f = unitFactor(u)
%UNITFACTOR  Return the number of nanometres in one unit of u.
    s = lower(strtrim(char(u)));
    % Strip any leading Greek/µ encoding so 'µm', 'μm', 'um' all map alike
    s = strrep(s, 'μ', 'u');
    s = strrep(s, 'µ', 'u');
    switch s
        case {'nm'}
            f = 1;
        case {'um', 'micron', 'microns'}
            f = 1000;
        case {'mm'}
            f = 1e6;
        case {'a', 'å', 'angstrom', 'angstroms'}
            f = 0.1;
        case {'pm'}
            f = 1e-3;
        otherwise
            % Unknown — assume same unit (scale = 1), so BarLength is used raw
            f = NaN;
    end
    if isnan(f)
        error('imaging:addScaleBar:UnknownUnit', ...
            'Unknown length unit "%s". Supported: nm, um, mm, Å, pm.', char(u));
    end
end
