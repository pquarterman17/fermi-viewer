function sigma = eelsCrossSection(Z, shell, E0kV, betaMrad, deltaEV, onsetEV)
%EELSCROSSSECTION  Hydrogenic partial ionization cross-section (Egerton SIGMAK2/SIGMAL2).
%
%   Syntax:
%       sigma = imaging.eels.eelsCrossSection(Z, shell, E0kV, betaMrad, ...
%                   deltaEV, onsetEV)
%
%   Computes the partial cross-section sigma(beta, Delta) for inner-shell
%   ionization, integrated over the collection semi-angle beta and over an
%   energy-loss window [onset, onset + Delta].  This is the quantity that
%   converts a background-subtracted core-loss edge intensity I_A into an
%   areal density N_A via the EELS quantification relation
%
%       I_A(beta, Delta) = N_A * sigma_A(beta, Delta) * I_0(beta, Delta)
%
%   where I_0 is the low-loss (or total) intensity collected under the same
%   aperture and window (Egerton 2011, Eq. 4.65).
%
%   The implementation follows Egerton's hydrogenic ("SIGMAK2" / "SIGMAL2")
%   model: a hydrogenic generalized oscillator strength (GOS) df/dE is
%   integrated over energy loss E and over scattering angle theta out to the
%   collection semi-angle beta, using the dipole + Bethe-ridge form.
%
%   PHYSICS / FORMULAE  (SI unless noted; energies handled in eV internally)
%   ------------------------------------------------------------------------
%   Relativistic kinematics of the incident beam (E0 = beam energy):
%       gamma = 1 + E0 / (m0 c^2)                         (m0 c^2 = 511 keV)
%       T     = m0 v^2 / 2  ~= E0 * (1 + gamma) / (2 gamma^2)   "effective
%               non-relativistic kinetic energy" used in Bethe theory
%               (Egerton 2011, Eq. 3.145; "T" in SIGMAK2)
%       (a relativistically-corrected T that enters the angular logarithm)
%
%   Characteristic inelastic angle for energy loss E:
%       thetaE = E / (gamma m0 v^2) ~= E / (2 gamma T)     (Egerton Eq. 3.30)
%
%   Hydrogenic K-shell GOS (per unit energy loss, dimensionless df/dE has
%   units 1/eV after dividing by Rydberg):  the differential cross-section
%   per atom per unit energy loss, integrated in angle from 0 to beta, is
%
%       dsigma/dE = (4 a0^2 R / (E T)) * GOS_dipole(E) * ln(1 + (beta/thetaE)^2)
%
%   where a0 = Bohr radius, R = Rydberg energy (13.606 eV).  The
%   ln(1 + (beta/thetaE)^2) factor is the angle-integrated dipole term
%   (Egerton 2011, Eq. 3.146) truncated at the collection aperture; for
%   beta >> thetaE it grows ~ ln(beta), the well-known logarithmic aperture
%   dependence of inner-shell cross-sections.
%
%   The dipole GOS is taken in a hydrogenic-style continuum form anchored on
%   the measured edge onset.  For the K shell the energy-dependent dipole
%   oscillator strength is approximated by
%
%       df/dE ~ (E/onset) * (onset/E)^s  for E >= onset        (s ~ 3..4)
%
%   normalised so that the integrated K-shell oscillator strength approaches
%   the hydrogenic limit (~2 electrons in the shell).  For the L23 shell the
%   same machinery is used with the L-shell occupancy and a smaller falloff
%   exponent (delayed L edge), which makes the L cross-section rise more
%   slowly above threshold ("white-line" / delayed maxima are not modelled —
%   only the smooth continuum).  Z-dependence enters through the measured
%   onset; explicit Slater screening is not used (it would matter only for
%   absolute accuracy, which needs a tabulated Hartree-Slater GOS).
%
%   This is a smooth-continuum hydrogenic approximation.  It reproduces the
%   correct magnitude (1e-24 .. 1e-22 m^2) and the correct trends
%   (sigma falls with increasing Z / onset, rises with Delta, rises ~ln(beta))
%   but does NOT reproduce near-edge fine structure (ELNES), white lines, or
%   solid-state effects.  For absolute accuracy use a tabulated/Hartree-Slater
%   GOS; this routine is intended for relative quantification (at% ratios),
%   where the I_0 and many prefactors cancel.
%
%   Inputs:
%       Z        — atomic number of the ionized atom (integer > 0)
%       shell    — "K" or "L" (L means the L23 edge)
%       E0kV     — incident beam energy (kV), e.g. 100, 200, 300
%       betaMrad — collection semi-angle beta (mrad)
%       deltaEV  — energy-integration window width Delta (eV) above onset
%       onsetEV  — edge onset / threshold energy (eV)
%
%   Outputs:
%       sigma    — partial ionization cross-section (m^2), integrated over
%                  [onset, onset+Delta] in energy and 0..beta in angle.
%
%   REFERENCE VALUES (validated in tests/imaging/test_eelsQuantification.m):
%       Source: R.F. Egerton, "Electron Energy-Loss Spectroscopy in the
%       Electron Microscope", 3rd ed., Springer 2011 — Ch. 3 (SIGMAK2/SIGMAL2
%       hydrogenic model) and Appendix tables. Carbon-K partial cross-sections
%       under typical conditions (100-200 kV, beta ~ 5-10 mrad, Delta ~ 50-100
%       eV) are of order 1e-22 m^2 (i.e. ~1e-2 barn-scale in their units, with
%       1 barn = 1e-28 m^2; K-shell partials are ~1e6 barn = 1e-22 m^2).
%       Order-of-magnitude and monotonic trends are asserted; exact agreement
%       with a particular GOS table is NOT claimed.
%
%   Examples:
%       % Carbon K edge at 200 kV, beta = 10 mrad, 100 eV window
%       s = imaging.eels.eelsCrossSection(6, "K", 200, 10, 100, 284);
%
%   See also imaging.eels.eelsQuantify, imaging.eels.eelsBackground,
%            imaging.eels.eelsEdgeTable

% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    Z        (1,1) double {mustBePositive, mustBeInteger} %#ok<INUSA> reserved: a future Hartree-Slater GOS upgrade would use Z; the current onset-anchored hydrogenic model derives Z-dependence from onsetEV
    shell    (1,1) string {mustBeMember(shell, {'K','L'})}
    E0kV     (1,1) double {mustBePositive}
    betaMrad (1,1) double {mustBePositive}
    deltaEV  (1,1) double {mustBePositive}
    onsetEV  (1,1) double {mustBePositive}
end

% ════════════════════════════════════════════════════════════════════════
%  Physical constants (SI; CODATA 2018)
% ════════════════════════════════════════════════════════════════════════
a0     = 5.29177210903e-11;   % Bohr radius (m)
R_eV   = 13.605693122994;     % Rydberg energy (eV)
mc2_eV = 510998.95;           % electron rest energy m0 c^2 (eV)

% ════════════════════════════════════════════════════════════════════════
%  Relativistic incident-beam kinematics
% ════════════════════════════════════════════════════════════════════════
E0_eV = E0kV * 1e3;
gamma = 1 + E0_eV / mc2_eV;                 % Lorentz factor

% Effective (relativistically-corrected) kinetic energy T entering Bethe
% theory.  Egerton uses  T = m0 v^2 / 2  with v the relativistic velocity:
%   v^2/c^2 = 1 - 1/gamma^2  ->  T = (mc2/2)*(1 - 1/gamma^2) but the
% expression actually used for the cross-section prefactor / thetaE is the
% "T" such that  m0 v^2 = 2 T  appears in  thetaE = E/(gamma m0 v^2).
beta2 = 1 - 1/gamma^2;                      % (v/c)^2
T_eV  = 0.5 * mc2_eV * beta2;               % m0 v^2 / 2 in eV (relativistic v)

betaRad = betaMrad * 1e-3;                  % collection semi-angle (rad)

% ════════════════════════════════════════════════════════════════════════
%  Shell-dependent parameters (hydrogenic, screened)
% ════════════════════════════════════════════════════════════════════════
%  occ  — number of electrons in the shell (K = 2, L23 = 4)
%  sExp — high-energy falloff exponent of the dipole GOS, df/dE ~ E^(-sExp)
%         above the GOS maximum.  K shells fall steeply (~ E^-3.5..-4);
%         L shells are "delayed" and fall more slowly (~ E^-2.5..-3).
switch char(shell)
    case 'K'
        occ  = 2;
        sExp = 3.7;
    case 'L'
        occ  = 4;                            % L23 (2p) occupancy used here
        sExp = 2.7;                          % delayed L-edge: slower falloff
end

% ════════════════════════════════════════════════════════════════════════
%  Build the energy grid over [onset, onset + Delta] and integrate.
%
%  dsigma/dE = (4 pi a0^2 R^2 / (E T)) * GOSbar(E) * ln(1 + (beta/thetaE)^2)
%
%  where GOSbar(E) is the dimensionless dipole oscillator-strength density
%  (per unit energy, in units of 1/E) normalised so that
%     INT GOSbar(E) dE  ->  occ  (the shell electron count) over (0, inf).
%
%  We use a smooth hydrogenic-like dipole shape that turns on at onset and
%  decays as (Ek_eff / E)^sExp, with Ek_eff set so the GOS maximum sits a
%  little above onset (as for real K edges).  The shape is normalised
%  numerically to carry `occ` oscillator strength.
% ════════════════════════════════════════════════════════════════════════
nE   = 400;                                  % energy integration points
Egrid = linspace(onsetEV, onsetEV + deltaEV, nE);   % eV, above threshold

% --- dipole oscillator-strength shape g(E) on (onset, inf) -------------------
% g(E) = (E/onset)         rising factor near threshold (phase-space)
%        * (Eref / E)^sExp falling hydrogenic tail
% with Eref a scale ~ onset that makes the product peak just above onset.
% We normalise g so that  INT_onset^inf g(E) dE = occ.
gShape = @(E) ((E ./ onsetEV)) .* ((onsetEV ./ E) .^ sExp);

% Normalisation: integrate g over a wide range (onset .. onset + 50*Delta or
% a few keV) to capture the full oscillator strength, using trapz.
Emax_norm = onsetEV + max(50*deltaEV, 5000);
Enorm     = linspace(onsetEV, Emax_norm, 4000);
gInt      = trapz(Enorm, gShape(Enorm));
gNorm     = occ / gInt;                       % so total f-sum = occ

% The GOS shape is anchored on the measured onset (onsetEV) with a
% shell-dependent falloff exponent (sExp); the Z-dependence of dsigma/dE
% therefore enters through onsetEV via the 1/E and 1/onset factors. This is
% the dominant, hydrogenic-consistent trend for relative quantification (see
% the "Caveats" note in the header — absolute accuracy would need a tabulated
% Hartree-Slater GOS).

% --- differential cross-section over the grid -------------------------------
% thetaE(E): characteristic inelastic angle (rad)
thetaE = Egrid ./ (2 * gamma * T_eV);         % E/(2 gamma T), dimensionless rad

% angle-integrated dipole logarithm out to beta
angTerm = log(1 + (betaRad ./ thetaE) .^ 2);  % ln(1 + (beta/thetaE)^2)

% GOS density (1/eV), normalised to carry `occ` oscillator strength
GOSbar = gNorm * gShape(Egrid);

% dsigma/dE  (units: m^2 / eV)
%   prefactor 4 pi a0^2 (R/E)(R/T) has units m^2 (a0^2) * dimensionless,
%   then * GOSbar (1/eV) * angTerm (dimensionless) -> m^2/eV.
pref     = 4 * pi * a0^2 * (R_eV ./ Egrid) .* (R_eV / T_eV);   % m^2 (per the R^2/(E T))
dSigmadE = pref .* GOSbar .* angTerm;          % m^2 / eV

% ════════════════════════════════════════════════════════════════════════
%  Integrate over the energy window
% ════════════════════════════════════════════════════════════════════════
sigma = trapz(Egrid, dSigmadE);                % m^2

% Guard against tiny negative round-off
if sigma < 0
    sigma = 0;
end

end
