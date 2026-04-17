function [dist, intensity] = lineProfile(img, X1, Y1, X2, Y2, options)
%LINEPROFILE  Extract a sub-pixel intensity profile along a line segment.
%
%   Syntax:
%       [dist, intensity] = imaging.lineProfile(img, X1, Y1, X2, Y2)
%       [dist, intensity] = imaging.lineProfile(img, X1, Y1, X2, Y2, ...
%                               PixelSize=2.4, PixelUnit='nm')
%       [dist, intensity] = imaging.lineProfile(img, X1, Y1, X2, Y2, ...
%                               TiltAngle=52)     % FIB tilt correction
%
%   Samples N points along the line from (X1,Y1) to (X2,Y2) using bilinear
%   interpolation via interp2, where N = ceil(Euclidean pixel distance).
%   Coordinates follow MATLAB image convention: X is the column index
%   (horizontal), Y is the row index (vertical), both 1-based.
%
%   Inputs:
%       img       — [H x W] numeric matrix
%       X1, Y1    — start point (column, row) in pixel coordinates
%       X2, Y2    — end   point (column, row) in pixel coordinates
%
%   Optional Name-Value:
%       PixelSize — physical size of one pixel (default: NaN = uncalibrated)
%       PixelUnit — string unit label when PixelSize is set (default: 'px')
%       TiltAngle — stage tilt in degrees (default: 0 = no correction).
%                   When non-zero, the returned distance axis is stretched
%                   along the foreshortened axis (see Geometry) so that
%                   labels reflect the true in-plane distance.
%       TiltAxis  — 'Y' (default) or 'X'; image axis foreshortened by tilt.
%       Geometry  — "CrossSection" (default) or "Surface"; selects 1/sin
%                   vs 1/cos correction (see imaging.measureDistance for
%                   the full physics derivation).
%
%   Outputs:
%       dist      — [Nx1] distance vector along the line.
%                   In pixels when PixelSize is NaN; in PixelUnit otherwise.
%       intensity — [Nx1] interpolated pixel values along the line
%
%   Examples:
%       % Horizontal profile across the middle row
%       [d, I] = imaging.lineProfile(img, 1, 256, 512, 256);
%       plot(d, I); xlabel('Distance (px)'); ylabel('Intensity');
%
%       % Calibrated diagonal profile
%       [d, I] = imaging.lineProfile(img, 10, 10, 200, 200, ...
%                    PixelSize=2.4, PixelUnit='nm');
%
%   See also imaging.measureDistance, imaging.computeFFT, imaging.getStageTilt

% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    img              (:,:) {mustBeNumeric, mustBeNonempty}
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
%  Sample points along the line (image-space pixel positions)
% ════════════════════════════════════════════════════════════════════════
pixelDist = sqrt((X2 - X1)^2 + (Y2 - Y1)^2);
N = max(2, ceil(pixelDist) + 1);        % at least 2 points

xSamples = linspace(X1, X2, N)';       % column coordinates (interp2 Xq)
ySamples = linspace(Y1, Y2, N)';       % row    coordinates (interp2 Yq)

% ════════════════════════════════════════════════════════════════════════
%  Interpolate intensities at the image-space samples
% ════════════════════════════════════════════════════════════════════════
intensity = interp2(double(img), xSamples, ySamples, 'linear', NaN);

% ════════════════════════════════════════════════════════════════════════
%  Distance axis — apply tilt correction if requested
% ════════════════════════════════════════════════════════════════════════
dx = X2 - X1;
dy = Y2 - Y1;
if options.TiltAngle ~= 0
    geom = lower(char(options.Geometry));
    switch geom
        case 'surface'
            % Plan-view of tilted surface: Δ_image = Δ_true · cos(θ).
            scale = 1 / cosd(options.TiltAngle);
        otherwise  % 'crosssection'
            % FIB cross-section: Δ_image = Δ_true · sin(θ).
            scale = 1 / sind(options.TiltAngle);
    end
    switch upper(char(options.TiltAxis))
        case 'Y'
            dy = dy * scale;
        case 'X'
            dx = dx * scale;
    end
end
correctedPixelDist = sqrt(dx^2 + dy^2);

dist = linspace(0, correctedPixelDist, N)';

if ~isnan(options.PixelSize)
    dist = dist * options.PixelSize;
end

end
