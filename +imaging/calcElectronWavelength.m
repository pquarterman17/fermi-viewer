function lambda = calcElectronWavelength(kV)
%CALCELECTRONWAVELENGTH  Relativistic de Broglie wavelength for electrons.
%
%   Syntax:
%       lambda = imaging.calcElectronWavelength(kV)
%
%   Computes the relativistic electron wavelength in Angstroms from the
%   accelerating voltage in kV.  Uses the full relativistic formula:
%
%       lambda = h / sqrt(2*m*e*V * (1 + e*V / (2*m*c^2)))
%
%   where h, m, e, c are CODATA 2018 values.
%
%   Inputs:
%       kV — accelerating voltage in kilovolts (positive scalar or vector)
%
%   Output:
%       lambda — relativistic electron wavelength in Angstroms; same size as kV
%
%   Examples:
%       lambda = imaging.calcElectronWavelength(200);   % 0.02508 Å
%       lambda = imaging.calcElectronWavelength(300);   % 0.01969 Å
%       lambda = imaging.calcElectronWavelength([80, 120, 200, 300]);
%
%   See also imaging.latticeMeasure, imaging.indexDiffraction

% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    kV (:,:) double {mustBePositive}
end

% ════════════════════════════════════════════════════════════════════════
%  Physical constants (CODATA 2018, SI units)
% ════════════════════════════════════════════════════════════════════════
h = 6.62607015e-34;       % Planck constant        (J·s)
m = 9.1093837015e-31;     % electron rest mass     (kg)
e = 1.602176634e-19;      % elementary charge      (C)
c = 299792458;            % speed of light         (m/s)

% ════════════════════════════════════════════════════════════════════════
%  Relativistic wavelength
%
%  V in Joules (= kV * 1000 * e / e = kV * 1000 volts)
%  lambda in metres → convert to Angstroms (* 1e10)
% ════════════════════════════════════════════════════════════════════════
V = kV * 1e3;   % volts

lambda = h ./ sqrt(2 .* m .* e .* V .* (1 + (e .* V) ./ (2 .* m .* c.^2)));

lambda = lambda * 1e10;   % metres → Angstroms

end
