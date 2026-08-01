function shapeFn = eelsEdgeShape(Z, shell, E0kV, betaMrad, onsetEV)
%EELSEDGESHAPE  Differential ionization cross-section (per-channel edge shape).
%
%   Syntax:
%       shapeFn = imaging.eels.eelsEdgeShape(Z, shell, E0kV, betaMrad, onsetEV)
%
%   Returns a function handle shapeFn(E) -> dsigma/dE (m^2/eV), evaluated at
%   caller-supplied energy-loss values E, zero below onsetEV. This is the
%   per-CHANNEL form of imaging.eels.eelsCrossSection's per-WINDOW integral:
%   integrating shapeFn(E) with trapz over [onset, onset+Delta] reproduces
%   eelsCrossSection(Z, shell, E0kV, betaMrad, Delta, onset) to ~1e-9
%   relative (same Egerton hydrogenic model, same energy grid density, same
%   normalisation-grid floor — see tests/imaging/test_eels_model.m). This
%   shape is the model term that imaging.eels.eelsFitEdges /
%   eelsFitEdgesMap sum (scaled by a fitted amplitude a_X) alongside a
%   power-law background to separate OVERLAPPING edges that
%   window-integration (imaging.eels.eelsQuantify) mis-assigns.
%
%   The (relatively expensive, 4000-point) occupancy normalisation integral
%   is computed ONCE inside this factory; the returned closure is then
%   cheap to call repeatedly inside eelsFitEdges' background-exponent
%   search (fminbnd calls it once per trial r).
%
%   Inputs:
%       Z        — atomic number of the ionized atom (integer > 0). Not
%                  used directly by the onset-anchored hydrogenic model
%                  (Z-dependence enters through onsetEV) — kept for
%                  interface parity with eelsCrossSection and a possible
%                  future Hartree-Slater GOS upgrade.
%       shell    — "K" or "L" (L means the L23 edge)
%       E0kV     — incident beam energy (kV)
%       betaMrad — collection semi-angle beta (mrad)
%       onsetEV  — edge onset / threshold energy (eV)
%
%   Outputs:
%       shapeFn  — function handle: E (numeric array, eV) -> dsigma/dE
%                  (m^2/eV, same size as E), 0 for E < onsetEV
%
%   Examples:
%       % O-K edge shape at 200 kV, beta = 10 mrad
%       fn = imaging.eels.eelsEdgeShape(8, "K", 200, 10, 532);
%       E  = linspace(532, 632, 400);
%       sigma = trapz(E, fn(E));   % ~= eelsCrossSection(8,"K",200,10,100,532)
%
%   See also imaging.eels.eelsCrossSection, imaging.eels.eelsFitEdges,
%            imaging.eels.eelsFitEdgesMap

% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    Z        (1,1) double {mustBePositive, mustBeInteger} %#ok<INUSA> reserved: a future Hartree-Slater GOS upgrade would use Z; the current onset-anchored hydrogenic model derives Z-dependence from onsetEV (mirrors eelsCrossSection)
    shell    (1,1) string {mustBeMember(shell, {'K','L'})}
    E0kV     (1,1) double {mustBePositive}
    betaMrad (1,1) double {mustBePositive}
    onsetEV  (1,1) double {mustBePositive}
end

% ════════════════════════════════════════════════════════════════════════
%  Physical constants (SI; CODATA 2018) — mirror imaging.eels.eelsCrossSection
%  verbatim so this shape's window integral reproduces that function's
%  output (required to ~1e-9 relative by tests/imaging/test_eels_model.m).
% ════════════════════════════════════════════════════════════════════════
a0        = 5.29177210903e-11;   % Bohr radius (m)
R_eV      = 13.605693122994;     % Rydberg energy (eV)
mc2_eV    = 510998.95;           % electron rest energy m0 c^2 (eV)
normFloor = 5000;                % normalisation-grid span floor (eV) — mirrors eelsCrossSection's max(50*Delta, 5000)

% ════════════════════════════════════════════════════════════════════════
%  Relativistic incident-beam kinematics (identical to eelsCrossSection)
% ════════════════════════════════════════════════════════════════════════
E0_eV   = E0kV * 1e3;
gamma   = 1 + E0_eV / mc2_eV;
beta2   = 1 - 1/gamma^2;
T_eV    = 0.5 * mc2_eV * beta2;
betaRad = betaMrad * 1e-3;

% ════════════════════════════════════════════════════════════════════════
%  Shell-dependent parameters (hydrogenic, screened) — identical to
%  eelsCrossSection: occ = shell electron count, sExp = high-energy
%  falloff exponent of the dipole GOS.
% ════════════════════════════════════════════════════════════════════════
switch char(shell)
    case 'K'
        occ  = 2;
        sExp = 3.7;
    case 'L'
        occ  = 4;
        sExp = 2.7;
end

% Dipole oscillator-strength shape (unnormalised), anchored on onsetEV.
gShape = @(E) (E ./ onsetEV) .* (onsetEV ./ E) .^ sExp;

% Normalise ONCE here so the total oscillator strength carries `occ`
% electrons — the same normalisation eelsCrossSection performs per call.
% NOTE: eelsCrossSection sizes its normalisation grid to
% max(50*Delta, 5000) for its OWN integration window Delta; this factory
% has no Delta at construction time (the shape is evaluated on whatever
% grid the caller later supplies), so it always uses the fixed 5000 eV
% floor (matching the Python port's _NORM_FLOOR). Since 50*Delta <= 5000
% for any Delta <= 100 eV — the window widths exercised by
% test_eels_model.m and by typical EELS signal windows — this reproduces
% eelsCrossSection exactly for those cases; a caller integrating a shape
% over Delta > 100 eV would see the two normalisations diverge slightly.
Enorm = linspace(onsetEV, onsetEV + normFloor, 4000);
gNorm = occ / trapz(Enorm, gShape(Enorm));

epsVal = eps;

shapeFn = @evalShape;

    function out = evalShape(E)
        E   = double(E);
        out = zeros(size(E));
        above = E >= onsetEV;
        Ea = max(E(above), epsVal);

        thetaE  = Ea ./ (2 * gamma * T_eV);           % characteristic inelastic angle (rad)
        angTerm = log(1 + (betaRad ./ thetaE) .^ 2);  % angle-integrated dipole logarithm
        pref    = 4 * pi * a0^2 .* (R_eV ./ Ea) .* (R_eV / T_eV);

        out(above) = pref .* gNorm .* gShape(Ea) .* angTerm;   % m^2 / eV
    end
end
