function zeta = zetaFromKFactors(elements, zetaSi, opts)
%ZETAFROMKFACTORS  Estimate per-element zeta-factors from one absolute
%standard plus the built-in Cliff-Lorimer k-factor table.
%
%   Syntax:
%       zeta = imaging.eds.zetaFromKFactors(elements, zetaSi)
%       zeta = imaging.eds.zetaFromKFactors(elements, zetaSi, KFactors=k)
%
%   Cliff-Lorimer and zeta-factor quantification both relate composition to
%   intensity ratios linearly, so the two systems' constants are tied by
%   k_ij = zeta_i / zeta_j exactly. With the built-in 200 kV table (k
%   relative to Si) this gives:
%
%       zeta_i = k_i * zeta_Si
%
%   One measured absolute standard (e.g. a pure-Si reference foil of known
%   mass-thickness) fixes the whole zeta scale for every other element.
%   Rigorous work should still supply per-element zeta from real standards;
%   this bridge is an estimate for when only one absolute value is known.
%
%   Inputs:
%       elements — {1 x N} cell array of element symbol strings
%       zetaSi   — scalar, absolute zeta-factor for Si-Kalpha measured on
%                  this detector/voltage/geometry (kg/m^2)
%
%   Optional Name-Value:
%       KFactors — [1 x N] explicit k-factors (relative to Si) overriding
%                  the built-in 200 kV table.
%       Voltage  — accelerating voltage kV passed to edsKFactorTable when
%                  KFactors is not supplied (default: 200).
%
%   Output:
%       zeta — [1 x N] estimated zeta-factors (kg/m^2), aligned with elements
%
%   Examples:
%       % Scale the whole 200 kV k-table from one measured zeta_Si
%       zeta = imaging.eds.zetaFromKFactors({'Si', 'Fe', 'Cu'}, 1000.0);
%       zeta(1)   % == 1000.0  (k_Si = 1.00 exactly)
%
%   See also imaging.eds.zetaQuantify, imaging.eds.edsKFactorTable,
%            imaging.eds.cliffLorimer

% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    elements   (1,:) cell
    zetaSi     (1,1) double
    opts.KFactors (1,:) double = []
    opts.Voltage  (1,1) double = 200
end

% ════════════════════════════════════════════════════════════════════════
%  Validate inputs
% ════════════════════════════════════════════════════════════════════════
if zetaSi <= 0
    error('zetaFromKFactors:invalidZetaSi', 'zetaSi must be positive.');
end

N = numel(elements);

% ════════════════════════════════════════════════════════════════════════
%  Resolve k-factors (built-in 200 kV table, or user-supplied)
% ════════════════════════════════════════════════════════════════════════
if isempty(opts.KFactors)
    kTable = imaging.eds.edsKFactorTable(Voltage=opts.Voltage);
    kVals  = zeros(1, N);
    for i = 1:N
        sym = elements{i};
        if isKey(kTable, sym)
            kVals(i) = kTable(sym);
        else
            warning('zetaFromKFactors:unknownElement', ...
                'No built-in k-factor for "%s". Using k = 1.00 (Si reference).', sym);
            kVals(i) = 1.00;
        end
    end
else
    if numel(opts.KFactors) ~= N
        error('zetaFromKFactors:kFactorLength', ...
            'KFactors must have the same length as elements.');
    end
    kVals = opts.KFactors;
end

% ════════════════════════════════════════════════════════════════════════
%  zeta_i = k_i * zeta_Si
% ════════════════════════════════════════════════════════════════════════
zeta = kVals * zetaSi;

end
