function [dist, unit] = measureDistance(X1, Y1, X2, Y2, options)
%MEASUREDISTANCE  Euclidean distance between two points in pixel or physical units.
%
%   Syntax:
%       [dist, unit] = imaging.measureDistance(X1, Y1, X2, Y2)
%       [dist, unit] = imaging.measureDistance(X1, Y1, X2, Y2, ...
%                          PixelSize=2.4, PixelUnit='nm')
%       [dist, unit] = imaging.measureDistance(X1, Y1, X2, Y2, ...
%                          TiltAngle=52)                     % cross-section
%       [dist, unit] = imaging.measureDistance(X1, Y1, X2, Y2, ...
%                          TiltAngle=30, Geometry="Surface") % plan-view
%
%   Computes sqrt((X2-X1)^2 + (Y2-Y1)^2). When PixelSize is provided
%   the result is multiplied by PixelSize and the unit label is returned.
%
%   SEM / FIB Tilt Correction
%   ─────────────────────────
%   When the sample is imaged at a stage tilt, the image is a projection
%   of a tilted object and must be rescaled along the foreshortened axis
%   to recover true sample-frame distances. Two geometries are supported
%   (selected via Geometry name-value; see docs/theory/imaging.md for the
%   full derivation):
%
%     Geometry="CrossSection" (default) — FIB cross-section imaging.
%     What appears in the image as the "depth" direction is the
%     projection of the true depth axis onto the image plane
%     (D_image = D_true · sin θ). Recover true depth by multiplying the
%     foreshortened axis by 1/sin(θ):
%         true = sqrt(Δx^2 + (Δy / sin θ)^2)          (TiltAxis='Y')
%
%     Geometry="Surface" — plan-view SEM of a tilted top surface. A
%     feature of true in-plane length L perpendicular to the tilt axis
%     projects to L · cos θ in the image. Recover true length by
%     multiplying the foreshortened axis by 1/cos(θ):
%         true = sqrt(Δx^2 + (Δy / cos θ)^2)          (TiltAxis='Y')
%
%   In both cases the correction is applied only to the axis specified
%   by TiltAxis (the axis perpendicular to the tilt rotation axis).
%   The axis parallel to the tilt rotation axis is unaffected.
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
%                   the tilt (perpendicular to the tilt rotation axis).
%       Geometry  — "CrossSection" (default) or "Surface"; selects the
%                   1/sin vs 1/cos correction factor.
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
%       % FIB cross-section at 52° tilt — pure vertical Δy=10 px becomes
%       % 10/sin(52°) ≈ 12.69 px after correction (default geometry).
%       [d, u] = imaging.measureDistance(0, 0, 0, 10, TiltAngle=52);
%
%       % Plan-view tilted surface at 30° — Δy=100 px on the
%       % foreshortened axis becomes 100/cos(30°) ≈ 115.47 px.
%       d = imaging.measureDistance(0, 0, 0, 100, ...
%               TiltAngle=30, Geometry="Surface");
%
%   Reference:
%       docs/theory/imaging.md, "Tilt correction in SEM/FIB imaging".
%       Derivation follows Goldstein et al., "Scanning Electron
%       Microscopy and X-Ray Microanalysis", 4th ed., Springer 2018
%       (ch. 4, geometric distortions), and Giannuzzi & Stevie,
%       "Introduction to Focused Ion Beams", Springer 2005
%       (ch. 10, cross-section metrology).
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
    options.Geometry  (1,1) string {mustBeMember(options.Geometry, ...
        ["CrossSection","Surface","crosssection","surface"])} = "CrossSection"
end

% ════════════════════════════════════════════════════════════════════════
%  Apply tilt correction to the foreshortened component
% ════════════════════════════════════════════════════════════════════════
dx = X2 - X1;
dy = Y2 - Y1;
if options.TiltAngle ~= 0
    geom = lower(char(options.Geometry));
    switch geom
        case 'surface'
            % Plan-view of tilted surface: Δy_image = Δy_true · cos(θ).
            scale = 1 / cosd(options.TiltAngle);
        otherwise  % 'crosssection'
            % FIB cross-section: Δy_image = Δy_true · sin(θ).
            scale = 1 / sind(options.TiltAngle);
    end
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
