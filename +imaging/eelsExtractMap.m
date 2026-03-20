function map = eelsExtractMap(cube, energyAxis, signalWindow, opts)
%EELSEXTRACTMAP  Extract an elemental intensity map from an EELS spectrum image.
%
%   Syntax:
%       map = imaging.eelsExtractMap(cube, energyAxis, signalWindow)
%       map = imaging.eelsExtractMap(cube, energyAxis, signalWindow, ...
%                 BackgroundWindow=[E1,E2])
%       map = imaging.eelsExtractMap(cube, energyAxis, signalWindow, ...
%                 BackgroundWindow=[E1,E2], Method='exponential')
%
%   Integrates the EELS signal over signalWindow after optional power-law
%   background subtraction.  When BackgroundWindow is provided, the
%   background is fitted per spatial pixel using imaging.eelsBackground and
%   subtracted before integration.  Without BackgroundWindow the raw counts
%   in signalWindow are summed directly.
%
%   Inputs:
%       cube          — [Ny x Nx x nE] spectrum image (any numeric type)
%       energyAxis    — [nE x 1] energy-loss axis (eV)
%       signalWindow  — [E_start, E_end] edge integration window (eV)
%
%   Optional Name-Value:
%       BackgroundWindow — [E1, E2] pre-edge window for background fit (eV).
%                         Default: [] (no background subtraction)
%       Method           — background model: 'powerlaw' (default) |
%                         'exponential' — passed to imaging.eelsBackground
%
%   Outputs:
%       map — [Ny x Nx] double; integrated elemental intensity map.
%             Units match the cube (counts or cps × channels).
%
%   Examples:
%       % Fe-L23 map with power-law background subtraction
%       map = imaging.eelsExtractMap(cube, E, [700, 750], ...
%                 BackgroundWindow=[650, 700]);
%       imagesc(map); colorbar; title('Fe-L_{23} intensity'); axis image;
%
%       % Simple window sum, no background
%       map = imaging.eelsExtractMap(cube, E, [525, 560]);
%
%   See also imaging.eelsBackground, imaging.eelsAlignZLP,
%            imaging.eelsThicknessMap, imaging.eelsEdgeTable

% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    cube         (:,:,:) {mustBeNumeric, mustBeNonempty}
    energyAxis   (:,1)   double {mustBeNonempty}
    signalWindow (1,2)   double
    opts.BackgroundWindow (1,2) double = [NaN, NaN]
    opts.Method          (1,1) string ...
        {mustBeMember(opts.Method, {'powerlaw','exponential'})} = 'powerlaw'
end

[Ny, Nx, nE] = size(cube);

if numel(energyAxis) ~= nE
    error('imaging:eelsExtractMap:sizeMismatch', ...
        'energyAxis length (%d) must match cube third dimension (%d).', ...
        numel(energyAxis), nE);
end

energyAxis = double(energyAxis(:));

% ════════════════════════════════════════════════════════════════════════
%  Signal window channel indices
% ════════════════════════════════════════════════════════════════════════
sigMask = energyAxis >= signalWindow(1) & energyAxis <= signalWindow(2);
if ~any(sigMask)
    error('imaging:eelsExtractMap:emptySignalWindow', ...
        'signalWindow [%.1f, %.1f] eV contains no channels.', ...
        signalWindow(1), signalWindow(2));
end

doBackground = ~any(isnan(opts.BackgroundWindow));

% ════════════════════════════════════════════════════════════════════════
%  Build elemental map
% ════════════════════════════════════════════════════════════════════════
map     = zeros(Ny, Nx);
cubeD   = double(cube);

if ~doBackground
    % Fast path: vectorised sum over signal channels
    sigSlice = cubeD(:, :, sigMask);           % [Ny x Nx x nSig]
    map      = sum(sigSlice, 3);               % [Ny x Nx]

else
    % Per-pixel background subtraction then integrate
    for row = 1:Ny
        for col = 1:Nx
            spec = squeeze(cubeD(row, col, :));   % [nE x 1]
            try
                sig = imaging.eelsBackground(energyAxis, spec, ...
                    FitWindow = opts.BackgroundWindow, ...
                    Method    = opts.Method);
            catch
                % If background fit fails (e.g. all-zero pixel), use raw
                sig = spec;
            end
            map(row, col) = sum(sig(sigMask));
        end
    end
end

end
