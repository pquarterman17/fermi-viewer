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
    % ────────────────────────────────────────────────────────────────────
    % Vectorised per-pixel background fit.
    %
    %   powerlaw:    log(I) = log(A) - r * log(E)
    %                ↔ linear fit y = a + b·x with y=log(I), x=log(E)
    %                Background restored as  A * E^(-r) = exp(a) * E^b.
    %   exponential: log(I) = log(A) + b * E
    %                ↔ linear fit y = a + b·x with x=E
    %                Background restored as  A * exp(b·E) = exp(a) * exp(b·E).
    %
    % All Np = Ny*Nx pixels are fit simultaneously via X \ Y on a
    % [K × Np] log-intensity matrix where K is the pre-edge channel count.
    % MATLAB's `\` on a tall [K×2] design matrix reduces to QR-based least
    % squares per column — one BLAS call instead of Np polyfit calls.
    %
    % Background reconstruction uses the SAME two-step exp formulation as
    % the scalar imaging.eelsBackground (`A = exp(intercept); bg = A * E^(-r)`).
    % This matters for degenerate pixels (all-zero or all-noise pre-edge
    % windows) where the fit returns extreme exponents — the two-step form
    % overflows/underflows identically in both code paths, so the resulting
    % map values agree to floating-point round-off even for pathological
    % pixels.
    % ────────────────────────────────────────────────────────────────────
    if any(isnan(opts.BackgroundWindow))
        % Mirror imaging.eelsBackground default: first 20% of energy span
        eMin = min(energyAxis);
        eMax = max(energyAxis);
        bgWin = [eMin, eMin + 0.2*(eMax - eMin)];
    else
        bgWin = opts.BackgroundWindow;
    end

    fitMask = energyAxis >= bgWin(1) & energyAxis <= bgWin(2);
    if sum(fitMask) < 2
        error('imaging:eelsExtractMap:tooFewBgPoints', ...
            'BackgroundWindow [%.1f, %.1f] eV contains fewer than 2 channels.', ...
            bgWin(1), bgWin(2));
    end

    Np    = Ny * Nx;
    Efit  = energyAxis(fitMask);                            % [K  x 1]
    Esig  = energyAxis(sigMask);                            % [Ks x 1]
    K     = numel(Efit);

    % Reshape cube to [nE x Np] for matrix ops
    specMat = reshape(permute(cubeD, [3 1 2]), nE, Np);     % [nE x Np]
    Ifit    = specMat(fitMask, :);                          % [K  x Np]
    Isig    = specMat(sigMask, :);                          % [Ks x Np]

    % Clamp non-positive pre-edge intensities before log (matches scalar
    % imaging.eelsBackground's `Ifit = max(Ifit, eps)`).
    IfitClamped = max(Ifit, eps);

    switch opts.Method
        case 'powerlaw'
            % Design matrix in log-log space; row order [r-coeff, intercept]
            % to match polyfit(log(E), log(I), 1) output: coeffs(1) = slope,
            % coeffs(2) = intercept.
            x = log(Efit);                                   % [K x 1]
            X = [x, ones(K, 1)];                             % [K x 2]  (slope, intercept)
            Y = log(IfitClamped);                            % [K x Np]
            coeffs = X \ Y;                                  % [2 x Np]
            slope     = coeffs(1, :);                        % [1 x Np]  = -r
            intercept = coeffs(2, :);                        % [1 x Np]  = log(A)

            A = exp(intercept);                              % [1 x Np]
            r = -slope;                                      % [1 x Np]

            % Background under signal window:  bg = A * Esig.^(-r)
            % Use Eguard = max(Esig, eps) to mirror the scalar version.
            Eguard = max(Esig, eps);                         % [Ks x 1]
            % bgSig [Ks x Np] = (Eguard.^(-r))  .*  A
            bgSig = (Eguard .^ (-r)) .* A;

        case 'exponential'
            x = Efit;
            X = [x, ones(K, 1)];
            Y = log(IfitClamped);
            coeffs = X \ Y;
            b         = coeffs(1, :);                        % [1 x Np]
            intercept = coeffs(2, :);                        % [1 x Np]
            A = exp(intercept);

            % bg = A * exp(b * Esig)
            bgSig = exp(Esig * b) .* A;                      % [Ks x Np]
    end

    % Background-subtract over signal window, clamp negatives to 0
    sigSubtr = max(Isig - bgSig, 0);                         % [Ks x Np]

    % NaN-safe: pathological pixels may yield NaN background (0*Inf etc.);
    % the scalar version's max(spec-NaN, 0) collapses to 0 via MATLAB's
    % NaN-handling in max with a numeric second arg, but be explicit.
    sigSubtr(isnan(sigSubtr)) = 0;

    % Sum over signal channels → [1 x Np] → reshape to [Ny x Nx]
    mapVec = sum(sigSubtr, 1);
    map = reshape(mapVec, Ny, Nx);
end

end
