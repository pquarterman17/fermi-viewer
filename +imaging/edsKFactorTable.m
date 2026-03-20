function kTable = edsKFactorTable(opts)
%EDSKFACTORTABLE  Built-in Cliff-Lorimer k-factors relative to Si.
%
%   Syntax:
%       kTable = imaging.edsKFactorTable()
%       kTable = imaging.edsKFactorTable(Voltage=200)
%
%   Returns a containers.Map of element symbol → k-factor (relative to Si = 1.00).
%   Default values are for 200 kV with a SiLi detector (Williams & Carter,
%   "Transmission Electron Microscopy", 2nd ed.).
%
%   Inputs:
%       (none required)
%
%   Optional Name-Value:
%       Voltage — accelerating voltage in kV (default: 200).
%                 Only 200 kV values are built-in; other voltages emit a
%                 warning and fall back to the 200 kV table.
%
%   Output:
%       kTable — containers.Map with keys = element symbols (char),
%                values = k-factors (double, relative to Si = 1.00)
%
%   Examples:
%       % Get default table
%       kt = imaging.edsKFactorTable();
%       kFe = kt('Fe');   % → 1.21
%
%       % Lookup multiple elements
%       elements = {'Fe', 'O', 'Si'};
%       kVals = cellfun(@(e) kt(e), elements);
%
%   See also imaging.cliffLorimer, imaging.edsCompositionProfile

% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    opts.Voltage (1,1) double = 200
end

% ════════════════════════════════════════════════════════════════════════
%  Voltage check
% ════════════════════════════════════════════════════════════════════════
if opts.Voltage ~= 200
    warning('edsKFactorTable:voltageNotBuiltIn', ...
        'Only 200 kV k-factors are built-in. Using 200 kV values for %.0f kV.', ...
        opts.Voltage);
end

% ════════════════════════════════════════════════════════════════════════
%  200 kV Cliff-Lorimer k-factors (Williams & Carter, SiLi detector)
%  All values relative to Si = 1.00
% ════════════════════════════════════════════════════════════════════════
symbols = { ...
    'B',  'C',  'N',  'O',  'F',  ...
    'Na', 'Mg', 'Al', 'Si', 'P',  ...
    'S',  'Cl', 'K',  'Ca', 'Sc', ...
    'Ti', 'V',  'Cr', 'Mn', 'Fe', ...
    'Co', 'Ni', 'Cu', 'Zn', 'Ga', ...
    'Ge', 'As', 'Se', 'Br', 'Sr', ...
    'Y',  'Zr', 'Nb', 'Mo', 'Ru', ...
    'Pd', 'Ag', 'Sn', 'Sb', 'Ba', ...
    'La', 'Ce', 'Hf', 'Ta', 'W',  ...
    'Pt', 'Au'};

kValues = [ ...
    4.50, 3.00, 2.20, 1.80, 1.50, ...   % B  C  N  O  F
    1.10, 0.95, 0.87, 1.00, 0.97, ...   % Na Mg Al Si P
    0.93, 0.92, 1.01, 1.03, 1.05, ...   % S  Cl K  Ca Sc
    1.07, 1.09, 1.13, 1.18, 1.21, ...   % Ti V  Cr Mn Fe
    1.25, 1.28, 1.32, 1.36, 1.52, ...   % Co Ni Cu Zn Ga
    1.56, 1.58, 1.62, 1.66, 2.50, ...   % Ge As Se Br Sr
    2.55, 2.60, 2.65, 2.70, 2.80, ...   % Y  Zr Nb Mo Ru
    2.85, 2.90, 2.95, 3.00, 2.70, ...   % Pd Ag Sn Sb Ba
    2.10, 2.15, 1.70, 1.75, 1.80, ...   % La Ce Hf Ta W
    1.90, 1.85];                         % Pt Au

kTable = containers.Map(symbols, num2cell(kValues));

end
