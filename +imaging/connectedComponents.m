function [L, numComponents] = connectedComponents(bw, options)
%CONNECTEDCOMPONENTS  Label connected regions in a binary mask.
%
%   Syntax:
%       [L, n] = imaging.connectedComponents(bw)
%       [L, n] = imaging.connectedComponents(bw, Connectivity=4)
%       [L, n] = imaging.connectedComponents(bw, Connectivity=8)
%
%   Drop-in replacement for bwlabel from the Image Processing Toolbox
%   (which this codebase cannot use). Delegates to the base-MATLAB
%   `bwlabel` built-in (available since R2006a, no toolbox required).
%
%   The output label image uses 0 for background and 1..n for foreground
%   components, consistent with the previous union-find implementation.
%
%   Inputs:
%       bw                  — [H x W] logical (or numeric, interpreted
%                             as logical via `~= 0`)
%
%   Optional Name-Value:
%       Connectivity        — 4 (N/S/E/W) or 8 (plus diagonals).
%                             Default: 8.
%
%   Outputs:
%       L             — [H x W] double label image, 0 = background.
%       numComponents — number of connected foreground components.
%
%   Examples:
%       bw = gray < 50;
%       [L, n] = imaging.connectedComponents(bw);
%       fprintf('%d particles found\n', n);
%
%   See also imaging.particleAnalysis, imaging.multiOtsu, imaging.morphOp

% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    bw                         (:,:) {mustBeNumericOrLogical}
    options.Connectivity       (1,1) double {mustBeMember(options.Connectivity, [4, 8])} = 8
end

mask = logical(bw);

if ~any(mask(:))
    L = zeros(size(mask));
    numComponents = 0;
    return;
end

% ════════════════════════════════════════════════════════════════════════
%  Delegate to bwlabel (base MATLAB, R2006a+, no toolbox required)
% ════════════════════════════════════════════════════════════════════════
[L, numComponents] = bwlabel(mask, options.Connectivity);

L = double(L);

end
