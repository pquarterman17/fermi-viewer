function [energyKeV, unitsOut, converted] = toKeV(energyAxis, units)
%TOKEV  Normalize an EDS energy axis to keV.
%
%   Syntax
%     energyKeV                        = imaging.eds.toKeV(energyAxis, units)
%     [energyKeV, unitsOut, converted] = imaging.eds.toKeV(energyAxis, units)
%
%   Inputs
%     energyAxis — numeric array, energy values expressed in UNITS
%     units      — 'kev' | 'ev' | 'mev' (case-insensitive, leading/trailing
%                  whitespace ignored) | '' (default when omitted)
%
%   Outputs
%     energyKeV — ENERGYAXIS converted to keV. Returned unchanged when
%                 already keV or UNITS is not a recognised energy unit.
%     unitsOut  — 'keV' when a conversion was applied, otherwise UNITS
%                 unchanged (covers uncalibrated channel-index axes, whose
%                 units are '').
%     converted — true iff a conversion was applied.
%
%   Every EDS energy quantity elsewhere in this toolbox (characteristic-line
%   energies from imaging.eds.lineEnergy, integration windows/HalfWindow,
%   thickness/take-off inputs) is keV. The *axis* is whatever the source
%   format calibrated it in: Bruker BCF is natively keV, but Gatan DM and FEI
%   TIA/SER spectrum-image cubes commonly calibrate in eV. Comparing a keV
%   window against an un-converted eV axis silently selects almost no
%   channels, so an element map comes back blank instead of raising — call
%   this before handing an axis + keV window to imaging.eds.elementMap /
%   imaging.eds.extractElementMaps.
%
%   An unrecognised or empty UNITS returns the axis untouched (factor 1.0),
%   which also covers uncalibrated axes (channel indices, UNITS = '') —
%   scaling those would be meaningless.
%
%   Examples
%     eaxKeV    = imaging.eds.toKeV(eaxEV, 'eV');     % /1000
%     eaxKeV    = imaging.eds.toKeV(eaxKeV, 'keV');   % passthrough
%     [e, u, c] = imaging.eds.toKeV(eax, '');         % passthrough, c=false
%
%   See also IMAGING.EDS.ELEMENTMAP, IMAGING.EDS.EXTRACTELEMENTMAPS,
%            IMAGING.EDS.LINEENERGY

    arguments
        energyAxis  {mustBeNumeric}
        units       = ''
    end

    % Multiply an axis in the keyed unit by this to obtain keV.
    factors = struct('kev', 1.0, 'ev', 1e-3, 'mev', 1e-6);
    key = lower(strtrim(char(string(units))));

    if isfield(factors, key)
        factor = factors.(key);
    else
        factor = 1.0;
    end

    if factor == 1.0
        energyKeV = energyAxis;
        unitsOut  = units;
        converted = false;
    else
        energyKeV = double(energyAxis) * factor;
        unitsOut  = 'keV';
        converted = true;
    end
end
