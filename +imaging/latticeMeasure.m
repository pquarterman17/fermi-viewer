function result = latticeMeasure(spot1, spot2, imgSize, opts)
%LATTICEMEASURE  Compute real-space lattice vectors from two FFT spot positions.
%
%   Syntax:
%       result = imaging.latticeMeasure(spot1, spot2, imgSize)
%       result = imaging.latticeMeasure(spot1, spot2, imgSize, ...
%                    PixelSize=2.4, PixelUnit='nm')
%
%   Given the pixel coordinates of two diffraction spots in a centred FFT
%   image, converts them to reciprocal lattice vectors, then inverts the
%   2x2 reciprocal matrix to recover the corresponding real-space lattice
%   vectors, spacings, and unit-cell geometry.
%
%   The FFT centre is taken as floor(imgSize/2) + 1 (MATLAB fftshift
%   convention for both even and odd image sizes).
%
%   Inputs:
%       spot1   — [1x2] [row, col] pixel position of the first FFT spot
%       spot2   — [1x2] [row, col] pixel position of the second FFT spot
%       imgSize — [1x2] [rows, cols] size of the original real-space image
%
%   Optional Name-Value:
%       PixelSize — physical size of one real-space pixel (default: 1)
%       PixelUnit — string unit for PixelSize (default: 'px')
%
%   Output:
%       result — struct with fields:
%           .g1, .g2         — reciprocal lattice vectors [gx, gy] in 1/unit
%           .a1, .a2         — real-space lattice vectors [ax, ay] in unit
%           .a, .b           — lattice parameter magnitudes |a1|, |a2| in unit
%           .gamma           — angle between a1 and a2 in degrees
%           .dSpacing1       — d-spacing 1/|g1| in unit
%           .dSpacing2       — d-spacing 1/|g2| in unit
%           .unitCellArea    — |a1 x a2| (parallelogram area) in unit^2
%           .cellVertices    — [4x2] parallelogram vertices [x,y] for overlay
%                              order: origin → a1 → a1+a2 → a2
%           .pixelSize       — PixelSize used (for traceability)
%           .pixelUnit       — PixelUnit used
%
%   Examples:
%       % Spots found by clicking on the FFT image (row, col notation)
%       result = imaging.latticeMeasure([128, 160], [96, 128], [256, 256], ...
%                    PixelSize=0.195, PixelUnit='nm');
%       fprintf('a = %.3f nm,  b = %.3f nm,  gamma = %.1f deg\n', ...
%               result.a, result.b, result.gamma);
%
%       % Overlay unit-cell parallelogram on the real-space image
%       v = result.cellVertices;   % [4x2] in real-space units
%       patch(v(:,1), v(:,2), 'none', 'EdgeColor', 'r', 'LineWidth', 1.5);
%
%   See also imaging.computeFFT, imaging.measureDistance, imaging.lineProfile

% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    spot1   (1,2) double
    spot2   (1,2) double
    imgSize (1,2) double {mustBePositive, mustBeInteger}
    opts.PixelSize (1,1) double {mustBePositive} = 1
    opts.PixelUnit (1,1) string                  = 'px'
end

% ════════════════════════════════════════════════════════════════════════
%  FFT centre (MATLAB fftshift places DC at floor(N/2)+1)
% ════════════════════════════════════════════════════════════════════════
nRows = imgSize(1);
nCols = imgSize(2);
centerRow = floor(nRows / 2) + 1;
centerCol = floor(nCols / 2) + 1;

% ════════════════════════════════════════════════════════════════════════
%  Pixel offsets from centre  (row offset → gy,  col offset → gx)
% ════════════════════════════════════════════════════════════════════════
dr1 = spot1(1) - centerRow;    % row offset,  spot 1
dc1 = spot1(2) - centerCol;    % col offset,  spot 1
dr2 = spot2(1) - centerRow;    % row offset,  spot 2
dc2 = spot2(2) - centerCol;    % col offset,  spot 2

% ════════════════════════════════════════════════════════════════════════
%  Reciprocal lattice vectors
%
%  Each pixel step in the FFT represents a frequency of
%      1 / (N_dimension * PixelSize)
%  in the corresponding real-space direction.
%
%  Convention: g = [gx, gy] where gx is along columns (x) and
%  gy is along rows (y).
% ════════════════════════════════════════════════════════════════════════
g1 = [dc1 / (nCols * opts.PixelSize), ...
      dr1 / (nRows * opts.PixelSize)];   % [gx, gy]  1/unit

g2 = [dc2 / (nCols * opts.PixelSize), ...
      dr2 / (nRows * opts.PixelSize)];

% Guard: spots must not coincide and must not be collinear (singular G).
if norm(g1) == 0 || norm(g2) == 0
    error('imaging:latticeMeasure:zeroVector', ...
        'One spot coincides with the FFT centre — cannot define a reciprocal vector.');
end

G = [g1; g2];   % 2x2 matrix, each row is a reciprocal vector

if abs(det(G)) < eps * max(norm(g1), norm(g2))^2
    error('imaging:latticeMeasure:singularMatrix', ...
        'The two reciprocal vectors are (nearly) collinear — cannot invert.');
end

% ════════════════════════════════════════════════════════════════════════
%  Real-space lattice vectors via matrix inversion
%
%  The defining relation is  G * A' = I  (rows of G are g vectors,
%  columns of A are a vectors), so A' = inv(G)  →  A = inv(G)'.
%  We keep the convention that each ROW of A is a real-space vector.
%
%  Equivalently: solve G' * a_col = e_i for each basis vector.
% ════════════════════════════════════════════════════════════════════════
A = inv(G)';    % 2x2; row i is the real-space vector dual to g_i

a1 = A(1, :);   % [ax, ay]  in unit
a2 = A(2, :);

% ════════════════════════════════════════════════════════════════════════
%  Lattice parameters
% ════════════════════════════════════════════════════════════════════════
aMag = norm(a1);
bMag = norm(a2);

cosGamma = dot(a1, a2) / (aMag * bMag);
cosGamma = max(-1, min(1, cosGamma));   % clamp for floating-point safety
gamma    = acosd(cosGamma);

dSpacing1 = 1 / norm(g1);
dSpacing2 = 1 / norm(g2);

unitCellArea = abs(a1(1) * a2(2) - a1(2) * a2(1));

% ════════════════════════════════════════════════════════════════════════
%  Cell vertices (parallelogram, starting from origin)
%  Columns: [x, y] = [col-direction, row-direction]
% ════════════════════════════════════════════════════════════════════════
origin   = [0, 0];
v1       = a1;
v1v2     = a1 + a2;
v2       = a2;
cellVertices = [origin; v1; v1v2; v2];   % [4 x 2]

% ════════════════════════════════════════════════════════════════════════
%  Pack result
% ════════════════════════════════════════════════════════════════════════
result.g1           = g1;
result.g2           = g2;
result.a1           = a1;
result.a2           = a2;
result.a            = aMag;
result.b            = bMag;
result.gamma        = gamma;
result.dSpacing1    = dSpacing1;
result.dSpacing2    = dSpacing2;
result.unitCellArea = unitCellArea;
result.cellVertices = cellVertices;
result.pixelSize    = opts.PixelSize;
result.pixelUnit    = opts.PixelUnit;

end
