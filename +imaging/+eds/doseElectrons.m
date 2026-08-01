function dose = doseElectrons(beamCurrentNA, liveTimeS)
%DOSEELECTRONS  Total electron dose D_e = I*tau/e for a probe current and time.
%
%   Syntax:
%       dose = imaging.eds.doseElectrons(beamCurrentNA, liveTimeS)
%
%   Converts a beam current and acquisition live time into the total number
%   of electrons that struck the specimen -- the normalising quantity the
%   zeta-factor method needs to turn a measured net intensity into an
%   absolute mass-thickness (see imaging.eds.zetaQuantify).
%
%   Inputs:
%       beamCurrentNA — probe/beam current in nanoamps (nA)
%       liveTimeS     — spectrum acquisition live time in seconds
%
%   Output:
%       dose — total electron dose D_e = I*tau/e (dimensionless electron count)
%
%   Examples:
%       % 1 nA for 100 s -> ~6.2415e11 electrons
%       d = imaging.eds.doseElectrons(1.0, 100.0);
%
%   See also imaging.eds.zetaQuantify, imaging.eds.zetaFromKFactors

% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    beamCurrentNA (1,1) double
    liveTimeS     (1,1) double
end

% ════════════════════════════════════════════════════════════════════════
%  Validate inputs
% ════════════════════════════════════════════════════════════════════════
if beamCurrentNA <= 0 || liveTimeS <= 0
    error('doseElectrons:invalidInput', ...
        'beamCurrentNA and liveTimeS must both be positive.');
end

% ════════════════════════════════════════════════════════════════════════
%  D_e = I*tau/e   (exact 2019-SI electron charge, C)
% ════════════════════════════════════════════════════════════════════════
ELECTRON_CHARGE_C = 1.602176634e-19;

dose = beamCurrentNA * 1e-9 * liveTimeS / ELECTRON_CHARGE_C;

end
