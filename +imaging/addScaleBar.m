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
end

% ════════════════════════════════════════════════════════════════════════
%  Choose a nice bar length (~1/5 of axes width)
% ════════════════════════════════════════════════════════════════════════
xLims = ax.XLim;
yLims = ax.YLim;

axWidthPx    = abs(xLims(2) - xLims(1));   % width in data (pixel) units
targetPhys   = axWidthPx * PixelSize / 5;  % target bar length in physical units

niceLengths  = [1 2 5 10 20 50 100 200 500 1000];
[~, idx]     = min(abs(niceLengths - targetPhys));
barLenPhys   = niceLengths(idx);           % chosen bar length in PixelUnit
barLenPx     = barLenPhys / PixelSize;     % bar length in data (pixel) units

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
switch options.Position
    case {'bottom-right', 'bottom-left'}
        labelY = barY - barH * 0.5;
        vAlign = 'bottom';
    case {'top-right', 'top-left'}
        labelY = barY + barH * 1.5;
        vAlign = 'top';
    otherwise
        labelY = barY - barH * 0.5;
        vAlign = 'bottom';
end

if barLenPhys == round(barLenPhys)
    labelStr = sprintf('%d %s', round(barLenPhys), char(PixelUnit));
else
    labelStr = sprintf('%.2g %s', barLenPhys, char(PixelUnit));
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
