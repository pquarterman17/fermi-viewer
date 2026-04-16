function [dist, unit] = measureDistance(X1, Y1, X2, Y2, options)
%MEASUREDISTANCE  Euclidean distance between two points in pixel or physical units.
%
%   Syntax:
%       [dist, unit] = imaging.measureDistance(X1, Y1, X2, Y2)
%       [dist, unit] = imaging.measureDistance(X1, Y1, X2, Y2, ...
%                          PixelSize=2.4, PixelUnit='nm')
%       [dist, unit] = imaging.measureDistance(X1, Y1, X2, Y2, ...
%                          TiltAngle=52)              % FIB tilt correction
%
%   Computes sqrt((X2-X1)^2 + (Y2-Y1)^2).  When PixelSize is provided
%   the result is multiplied by PixelSize and the unit label is returned.
%
%   FIB/SEM Tilt Correction
%   ───────────────────────
%   When the sample is imaged at a stage tilt, the component along the
%   tilt-axis direction is foreshortened by cos(tilt). Pass the tilt
%   angle (degrees) via TiltAngle and the axis via TiltAxis ('Y' or 'X')
%   to recover the true in-plane distance:
%       true = sqrt(Δx^2 + (Δy / cos θ)^2)   (TiltAxis='Y', the default)
%
%   Inputs:
%       X1, Y1 — start point (column, row) in pixel coordinates
%       X2, Y2 — end   point (column, row) in pixel coordinates
%
%   Optional Name-Value:
%       PixelSize — physical size of one pixel; e.g. 2.4 (default: NaN)
%       PixelUnit — unit label string; e.g. 'nm' (default: 'px')
%       TiltAngle — stage tilt angle in degrees (default: 0, i.e. no
%                   correction). Values within (-90, 90) are accepted.
%       TiltAxis  — 'Y' (default) or 'X'; image axis foreshortened by
%                   the tilt.
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
%       % FIB cross-section at 52 deg stage tilt — pure vertical Δy=10 px
%       % becomes 10/cos(52°) ≈ 16.24 px after correction
%       [d, u] = imaging.measureDistance(0, 0, 0, 10, TiltAngle=52);
%
%   See also imaging.lineProfile, imaging.getStageTilt

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
    options.TiltAngle (1,1) double {mustBeGreaterThan(options.TiltAngle, -90), ...
                                    mustBeLessThan(options.TiltAngle, 90)} = 0
    options.TiltAxis  (1,1) string {mustBeMember(options.TiltAxis, ["X","Y","x","y"])} = "Y"
end

% ════════════════════════════════════════════════════════════════════════
%  Apply tilt correction to the foreshortened component
% ════════════════════════════════════════════════════════════════════════
dx = X2 - X1;
dy = Y2 - Y1;
if options.TiltAngle ~= 0
    scale = 1 / cosd(options.TiltAngle);
    switch upper(char(options.TiltAxis))
        case 'Y'
            dy = dy * scale;
        case 'X'
            dx = dx * scale;
    end
end

% ════════════════════════════════════════════════════════════════════════
%  Compute distance
% ════════════════════════════════════════════════════════════════════════
dist = sqrt(dx^2 + dy^2);

if ~isnan(options.PixelSize)
    dist = dist * options.PixelSize;
    unit = char(options.PixelUnit);
else
    unit = 'px';
end

end
