function [dist, intensity] = lineProfile(img, X1, Y1, X2, Y2, options)
%LINEPROFILE  Extract a sub-pixel intensity profile along a line segment.
%
%   Syntax:
%       [dist, intensity] = imaging.lineProfile(img, X1, Y1, X2, Y2)
%       [dist, intensity] = imaging.lineProfile(img, X1, Y1, X2, Y2, ...
%                               PixelSize=2.4, PixelUnit='nm')
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
%   See also imaging.measureDistance, imaging.computeFFT

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
end

% ════════════════════════════════════════════════════════════════════════
%  Sample points along the line
% ════════════════════════════════════════════════════════════════════════
pixelDist = sqrt((X2 - X1)^2 + (Y2 - Y1)^2);
N = max(2, ceil(pixelDist) + 1);        % at least 2 points

xSamples = linspace(X1, X2, N)';       % column coordinates (interp2 Xq)
ySamples = linspace(Y1, Y2, N)';       % row    coordinates (interp2 Yq)

% ════════════════════════════════════════════════════════════════════════
%  Interpolate
% ════════════════════════════════════════════════════════════════════════
intensity = interp2(double(img), xSamples, ySamples, 'linear', NaN);

% ════════════════════════════════════════════════════════════════════════
%  Distance axis
% ════════════════════════════════════════════════════════════════════════
dist = linspace(0, pixelDist, N)';

if ~isnan(options.PixelSize)
    dist = dist * options.PixelSize;
end

end
