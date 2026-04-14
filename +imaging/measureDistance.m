function [dist, unit] = measureDistance(X1, Y1, X2, Y2, options)
%MEASUREDISTANCE  Euclidean distance between two points in pixel or physical units.
%
%   Syntax:
%       [dist, unit] = imaging.measureDistance(X1, Y1, X2, Y2)
%       [dist, unit] = imaging.measureDistance(X1, Y1, X2, Y2, ...
%                          PixelSize=2.4, PixelUnit='nm')
%
%   Computes sqrt((X2-X1)^2 + (Y2-Y1)^2).  When PixelSize is provided
%   the result is multiplied by PixelSize and the unit label is returned.
%
%   Inputs:
%       X1, Y1 — start point (column, row) in pixel coordinates
%       X2, Y2 — end   point (column, row) in pixel coordinates
%
%   Optional Name-Value:
%       PixelSize — physical size of one pixel; e.g. 2.4 (default: NaN)
%       PixelUnit — unit label string; e.g. 'nm' (default: 'px')
%
%   Outputs:
%       dist — scalar distance
%       unit — string: PixelUnit when calibrated, 'px' otherwise
%
%   Examples:
%       % Pixel distance — (0,0) to (3,4) = 5
%       [d, u] = imaging.measureDistance(0, 0, 3, 4);   % d=5, u='px'
%
%       % Calibrated — (0,0) to (3,4) at 2 nm/px = 10 nm
%       [d, u] = imaging.measureDistance(0, 0, 3, 4, PixelSize=2, PixelUnit='nm');
%
%   See also imaging.lineProfile

% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    X1               (1,1) double
    Y1               (1,1) double
    X2               (1,1) double
    Y2               (1,1) double
    options.PixelSize (1,1) double = NaN
    options.PixelUnit {mustBeTextScalar} = "px"
end

% ════════════════════════════════════════════════════════════════════════
%  Compute distance
% ════════════════════════════════════════════════════════════════════════
dist = sqrt((X2 - X1)^2 + (Y2 - Y1)^2);

if ~isnan(options.PixelSize)
    dist = dist * options.PixelSize;
    unit = char(options.PixelUnit);
else
    unit = 'px';
end

end
