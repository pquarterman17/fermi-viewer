function mac = massAbsorptionCoeff(emitter, absorber)
%MASSABSORPTIONCOEFF  Mass absorption coefficient (mu/rho) lookup.
%
%   Syntax:
%       mac = imaging.massAbsorptionCoeff(emitter, absorber)
%
%   Returns the mass absorption coefficient in cm^2/g for the characteristic
%   K-alpha X-ray of the emitter element absorbed by the absorber element.
%
%   Values are computed using the empirical formula (Heinrich 1986):
%
%       mac = C * Z^4 * lambda^3 / A
%
%   where C = 3.2e-20, Z and A are the absorber atomic number and mass,
%   and lambda is the K-alpha wavelength of the emitter in cm.
%
%   K-alpha energies are from Heinrich (1986) and Henke et al. (1993) tables.
%
%   Inputs:
%       emitter  — element symbol emitting X-rays (e.g. 'Fe')
%       absorber — element symbol of absorbing matrix (e.g. 'O')
%
%   Output:
%       mac — mass absorption coefficient (cm^2/g).
%             Returns NaN if emitter is not in the K-alpha energy table
%             or if absorber is not found in calc.elementData.
%
%   Examples:
%       % Fe K-alpha absorbed by O
%       mac = imaging.massAbsorptionCoeff('Fe', 'O');
%
%       % Build a matrix for a multi-element specimen
%       els = {'Fe', 'O', 'Si'};
%       macMatrix = zeros(numel(els));
%       for i = 1:numel(els)
%           for j = 1:numel(els)
%               macMatrix(i,j) = imaging.massAbsorptionCoeff(els{i}, els{j});
%           end
%       end
%
%   See also imaging.zafCorrection, imaging.cliffLorimer

% ════════════════════════════════════════════════════════════════════════
%  K-alpha energy table (keV)  — Heinrich (1986) / Henke et al. (1993)
% ════════════════════════════════════════════════════════════════════════
kAlphaKeV = containers.Map( ...
    { 'C',  'N',  'O',  'F',  'Na', 'Mg', 'Al', 'Si', ...
      'P',  'S',  'Cl', 'K',  'Ca', 'Ti', 'V',  'Cr', ...
      'Mn', 'Fe', 'Co', 'Ni', 'Cu', 'Zn', 'Ga', 'Ge', ...
      'As', 'Sr', 'Y',  'Zr', 'Nb', 'Mo', 'Ba', 'La' }, ...
    {  0.277,  0.392,  0.525,  0.677,  1.041,  1.254,  1.487,  1.740, ...
       2.013,  2.308,  2.622,  3.314,  3.692,  4.511,  4.952,  5.415, ...
       5.899,  6.404,  6.930,  7.478,  8.048,  8.639,  9.252,  9.886, ...
      10.544, 14.165, 14.958, 15.775, 16.615, 17.479, 32.194, 33.442 } );

% ════════════════════════════════════════════════════════════════════════
%  Look up emitter K-alpha energy
% ════════════════════════════════════════════════════════════════════════
if ~isKey(kAlphaKeV, emitter)
    warning('massAbsorptionCoeff:unknownEmitter', ...
        'K-alpha energy not available for emitter "%s". Returning NaN.', emitter);
    mac = NaN;
    return
end

energyKeV = kAlphaKeV(emitter);

% Convert keV → wavelength in cm
%   lambda(Å) = 12.398 / E(keV),  then  lambda(cm) = lambda(Å) * 1e-8
lambdaCm = (12.398 / energyKeV) * 1e-8;

% ════════════════════════════════════════════════════════════════════════
%  Look up absorber Z and A from calc.elementData
% ════════════════════════════════════════════════════════════════════════
try
    absEl = calc.elementData('bySymbol', absorber);
catch
    warning('massAbsorptionCoeff:unknownAbsorber', ...
        'Element data not found for absorber "%s". Returning NaN.', absorber);
    mac = NaN;
    return
end

Z = double(absEl.Z);
A = absEl.mass;

if A <= 0 || isnan(A)
    warning('massAbsorptionCoeff:badAtomicMass', ...
        'Invalid atomic mass for absorber "%s". Returning NaN.', absorber);
    mac = NaN;
    return
end

% ════════════════════════════════════════════════════════════════════════
%  Empirical Heinrich formula:  mac = C * Z^4 * lambda^3 / A
%  C = 3.2e-20  (empirical constant; produces mac in cm^2/g when
%  lambda is in cm and A in atomic mass units)
% ════════════════════════════════════════════════════════════════════════
C   = 3.2e-20;
mac = C * Z^4 * lambdaCm^3 / A;

end
