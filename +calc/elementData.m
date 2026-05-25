function result = elementData(action, arg)
%ELEMENTDATA  Periodic table data for all 118 elements.
%
%   Syntax
%   ------
%   elements = calc.elementData()
%       Return a 1×118 struct array with all element data.
%
%   el = calc.elementData('bySymbol', sym)
%       Look up a single element by its symbol string (e.g. 'Fe').
%
%   el = calc.elementData('byZ', Z)
%       Look up a single element by atomic number.
%
%   vals = calc.elementData('getProperty', propName)
%       Extract a 1×118 double vector for the named property.
%       For char fields returns a 1×118 cell array of strings.
%
%   Inputs
%   ------
%   action   (optional) char — 'bySymbol', 'byZ', or 'getProperty'
%   arg      (optional) — symbol string, atomic number, or property name
%
%   Outputs
%   -------
%   result   struct array or scalar struct, depending on action
%
%   Fields per element
%   ------------------
%   Z                   int      atomic number
%   symbol              char     element symbol
%   name                char     full name
%   mass                double   atomic mass (u, IUPAC 2021)
%   group               int      group 1-18 (0 for f-block)
%   period              int      period 1-7
%   category            char     element category string
%   density             double   bulk density (g/cm^3); NaN if unavailable
%   electronConfig      char     abbreviated electron configuration
%   electronegativity   double   Pauling scale; NaN if unavailable
%   atomicRadius        double   empirical radius (pm); NaN if unavailable
%   ionizationEnergy    double   first ionization energy (eV); NaN if unavailable
%   electronAffinity    double   electron affinity (eV); NaN if unavailable
%   meltingPoint        double   melting point (K); NaN if unavailable
%   boilingPoint        double   boiling point (K); NaN if unavailable
%   thermalConductivity double   thermal conductivity W/(m*K); NaN if unavailable
%   bCoherent           double   neutron coherent scattering length (fm); NaN if unavailable
%   xrayEdges           struct   fields K, L1, L2, L3 in eV; empty struct if unavailable
%
%   Examples
%   --------
%   % Full table
%   els = calc.elementData();
%   disp(els(26).name)          % 'Iron'
%
%   % Lookup by symbol
%   fe = calc.elementData('bySymbol', 'Fe');
%   disp(fe.mass)               % 55.845
%
%   % Lookup by Z
%   el = calc.elementData('byZ', 79);
%   disp(el.symbol)             % 'Au'
%
%   % Extract mass vector
%   masses = calc.elementData('getProperty', 'mass');
%
%   Notes
%   -----
%   Atomic masses: IUPAC 2021 standard atomic weights (conventional values).
%   Neutron scattering lengths: NIST (Sears 1992, natural abundance).
%   X-ray edges: Bearden & Burr (1967) / NIST XCOM values (eV).
%   Physical properties: CRC Handbook of Chemistry and Physics, 102nd ed.
%   Deuterium (D) is an isotope of hydrogen and has no separate entry.

% ════════════════════════════════════════════════════════════════════
persistent cachedElements

if isempty(cachedElements)
    cachedElements = buildTable();
end

if nargin == 0
    result = cachedElements;
    return
end

switch lower(action)
    case 'bysymbol'
        idx = find(strcmp({cachedElements.symbol}, arg), 1);
        if isempty(idx)
            error('calc:elementData:notFound', ...
                'Element symbol ''%s'' not found.', arg);
        end
        result = cachedElements(idx);

    case 'byz'
        if arg < 1 || arg > 118
            error('calc:elementData:outOfRange', ...
                'Z must be between 1 and 118.');
        end
        result = cachedElements(arg);

    case 'getproperty'
        if isnumeric(cachedElements(1).(arg))
            result = [cachedElements.(arg)];
        else
            result = {cachedElements.(arg)};
        end

    otherwise
        error('calc:elementData:unknownAction', ...
            'Unknown action ''%s''. Use ''bySymbol'', ''byZ'', or ''getProperty''.', action);
end

end % elementData

% ════════════════════════════════════════════════════════════════════
%  Local helper: assemble the full 1×118 struct array
% ════════════════════════════════════════════════════════════════════
function elements = buildTable()

% Pre-allocate with default (NaN) values using element 1 as template
elements = repmat(makeElement(1,'H','Hydrogen',1.008,1,1,'nonmetal'), 1, 118);

% ── Period 1 ─────────────────────────────────────────────────────────
elements(1) = makeElement(1, 'H', 'Hydrogen', 1.008, 1, 1, 'nonmetal');
elements(1).density             = 0.00008988;
elements(1).electronConfig      = '1s1';
elements(1).electronegativity   = 2.20;
elements(1).atomicRadius        = 53;
elements(1).ionizationEnergy    = 13.5984;
elements(1).electronAffinity    = 0.7542;
elements(1).meltingPoint        = 14.01;
elements(1).boilingPoint        = 20.28;
elements(1).thermalConductivity = 0.1805;
elements(1).bCoherent           = -3.739;
elements(1).xrayEdges           = struct('K', 13.6, 'L1', NaN, 'L2', NaN, 'L3', NaN);

elements(2) = makeElement(2, 'He', 'Helium', 4.0026, 18, 1, 'noble gas');
elements(2).density             = 0.0001664;
elements(2).electronConfig      = '1s2';
elements(2).electronegativity   = NaN;
elements(2).atomicRadius        = 31;
elements(2).ionizationEnergy    = 24.5874;
elements(2).electronAffinity    = 0;
elements(2).meltingPoint        = 0.95;
elements(2).boilingPoint        = 4.22;
elements(2).thermalConductivity = 0.1513;
elements(2).bCoherent           = 3.26;
elements(2).xrayEdges           = struct('K', 24.6, 'L1', NaN, 'L2', NaN, 'L3', NaN);

% ── Period 2 ─────────────────────────────────────────────────────────
elements(3) = makeElement(3, 'Li', 'Lithium', 6.94, 1, 2, 'alkali metal');
elements(3).density             = 0.534;
elements(3).electronConfig      = '[He] 2s1';
elements(3).electronegativity   = 0.98;
elements(3).atomicRadius        = 167;
elements(3).ionizationEnergy    = 5.3917;
elements(3).electronAffinity    = 0.6182;
elements(3).meltingPoint        = 453.65;
elements(3).boilingPoint        = 1615;
elements(3).thermalConductivity = 84.8;
elements(3).bCoherent           = -1.90;
elements(3).xrayEdges           = struct('K', 54.7, 'L1', NaN, 'L2', NaN, 'L3', NaN);

elements(4) = makeElement(4, 'Be', 'Beryllium', 9.0122, 2, 2, 'alkaline earth metal');
elements(4).density             = 1.85;
elements(4).electronConfig      = '[He] 2s2';
elements(4).electronegativity   = 1.57;
elements(4).atomicRadius        = 112;
elements(4).ionizationEnergy    = 9.3227;
elements(4).electronAffinity    = 0;
elements(4).meltingPoint        = 1560;
elements(4).boilingPoint        = 2742;
elements(4).thermalConductivity = 200;
elements(4).bCoherent           = 7.79;
elements(4).xrayEdges           = struct('K', 111.5, 'L1', NaN, 'L2', NaN, 'L3', NaN);

elements(5) = makeElement(5, 'B', 'Boron', 10.81, 13, 2, 'metalloid');
elements(5).density             = 2.34;
elements(5).electronConfig      = '[He] 2s2 2p1';
elements(5).electronegativity   = 2.04;
elements(5).atomicRadius        = 87;
elements(5).ionizationEnergy    = 8.2980;
elements(5).electronAffinity    = 0.2797;
elements(5).meltingPoint        = 2349;
elements(5).boilingPoint        = 4200;
elements(5).thermalConductivity = 27.4;
elements(5).bCoherent           = 5.30;
elements(5).xrayEdges           = struct('K', 188.0, 'L1', NaN, 'L2', NaN, 'L3', NaN);

elements(6) = makeElement(6, 'C', 'Carbon', 12.011, 14, 2, 'nonmetal');
elements(6).density             = 2.267;
elements(6).electronConfig      = '[He] 2s2 2p2';
elements(6).electronegativity   = 2.55;
elements(6).atomicRadius        = 77;
elements(6).ionizationEnergy    = 11.2603;
elements(6).electronAffinity    = 1.2621;
elements(6).meltingPoint        = 3823;
elements(6).boilingPoint        = 4300;
elements(6).thermalConductivity = 140;
elements(6).bCoherent           = 6.646;
elements(6).xrayEdges           = struct('K', 284.2, 'L1', NaN, 'L2', NaN, 'L3', NaN);

elements(7) = makeElement(7, 'N', 'Nitrogen', 14.007, 15, 2, 'nonmetal');
elements(7).density             = 0.001251;
elements(7).electronConfig      = '[He] 2s2 2p3';
elements(7).electronegativity   = 3.04;
elements(7).atomicRadius        = 75;
elements(7).ionizationEnergy    = 14.5341;
elements(7).electronAffinity    = 0;
elements(7).meltingPoint        = 63.15;
elements(7).boilingPoint        = 77.36;
elements(7).thermalConductivity = 0.02583;
elements(7).bCoherent           = 9.36;
elements(7).xrayEdges           = struct('K', 409.9, 'L1', NaN, 'L2', NaN, 'L3', NaN);

elements(8) = makeElement(8, 'O', 'Oxygen', 15.999, 16, 2, 'nonmetal');
elements(8).density             = 0.001429;
elements(8).electronConfig      = '[He] 2s2 2p4';
elements(8).electronegativity   = 3.44;
elements(8).atomicRadius        = 73;
elements(8).ionizationEnergy    = 13.6181;
elements(8).electronAffinity    = 1.4611;
elements(8).meltingPoint        = 54.36;
elements(8).boilingPoint        = 90.20;
elements(8).thermalConductivity = 0.02658;
elements(8).bCoherent           = 5.803;
elements(8).xrayEdges           = struct('K', 543.1, 'L1', NaN, 'L2', NaN, 'L3', NaN);

elements(9) = makeElement(9, 'F', 'Fluorine', 18.998, 17, 2, 'halogen');
elements(9).density             = 0.001696;
elements(9).electronConfig      = '[He] 2s2 2p5';
elements(9).electronegativity   = 3.98;
elements(9).atomicRadius        = 64;
elements(9).ionizationEnergy    = 17.4228;
elements(9).electronAffinity    = 3.4012;
elements(9).meltingPoint        = 53.53;
elements(9).boilingPoint        = 85.03;
elements(9).thermalConductivity = 0.0277;
elements(9).bCoherent           = 5.654;
elements(9).xrayEdges           = struct('K', 696.7, 'L1', NaN, 'L2', NaN, 'L3', NaN);

elements(10) = makeElement(10, 'Ne', 'Neon', 20.180, 18, 2, 'noble gas');
elements(10).density             = 0.0009002;
elements(10).electronConfig      = '[He] 2s2 2p6';
elements(10).electronegativity   = NaN;
elements(10).atomicRadius        = 38;
elements(10).ionizationEnergy    = 21.5645;
elements(10).electronAffinity    = 0;
elements(10).meltingPoint        = 24.56;
elements(10).boilingPoint        = 27.07;
elements(10).thermalConductivity = 0.0491;
elements(10).bCoherent           = 4.566;
elements(10).xrayEdges           = struct('K', 870.2, 'L1', NaN, 'L2', NaN, 'L3', NaN);

% ── Period 3 ─────────────────────────────────────────────────────────
elements(11) = makeElement(11, 'Na', 'Sodium', 22.990, 1, 3, 'alkali metal');
elements(11).density             = 0.968;
elements(11).electronConfig      = '[Ne] 3s1';
elements(11).electronegativity   = 0.93;
elements(11).atomicRadius        = 190;
elements(11).ionizationEnergy    = 5.1391;
elements(11).electronAffinity    = 0.5479;
elements(11).meltingPoint        = 370.87;
elements(11).boilingPoint        = 1156;
elements(11).thermalConductivity = 142;
elements(11).bCoherent           = 3.63;
elements(11).xrayEdges           = struct('K', 1070.8, 'L1', 63.5, 'L2', 30.5, 'L3', 30.4);

elements(12) = makeElement(12, 'Mg', 'Magnesium', 24.305, 2, 3, 'alkaline earth metal');
elements(12).density             = 1.738;
elements(12).electronConfig      = '[Ne] 3s2';
elements(12).electronegativity   = 1.31;
elements(12).atomicRadius        = 145;
elements(12).ionizationEnergy    = 7.6462;
elements(12).electronAffinity    = 0;
elements(12).meltingPoint        = 923;
elements(12).boilingPoint        = 1363;
elements(12).thermalConductivity = 156;
elements(12).bCoherent           = 5.375;
elements(12).xrayEdges           = struct('K', 1303.0, 'L1', 88.7, 'L2', 49.8, 'L3', 49.2);

elements(13) = makeElement(13, 'Al', 'Aluminium', 26.982, 13, 3, 'post-transition metal');
elements(13).density             = 2.70;
elements(13).electronConfig      = '[Ne] 3s2 3p1';
elements(13).electronegativity   = 1.61;
elements(13).atomicRadius        = 118;
elements(13).ionizationEnergy    = 5.9858;
elements(13).electronAffinity    = 0.4328;
elements(13).meltingPoint        = 933.47;
elements(13).boilingPoint        = 2792;
elements(13).thermalConductivity = 237;
elements(13).bCoherent           = 3.449;
elements(13).xrayEdges           = struct('K', 1559.6, 'L1', 117.8, 'L2', 72.9, 'L3', 72.5);

elements(14) = makeElement(14, 'Si', 'Silicon', 28.085, 14, 3, 'metalloid');
elements(14).density             = 2.3296;
elements(14).electronConfig      = '[Ne] 3s2 3p2';
elements(14).electronegativity   = 1.90;
elements(14).atomicRadius        = 111;
elements(14).ionizationEnergy    = 8.1517;
elements(14).electronAffinity    = 1.3895;
elements(14).meltingPoint        = 1687;
elements(14).boilingPoint        = 3538;
elements(14).thermalConductivity = 149;
elements(14).bCoherent           = 4.1491;
elements(14).xrayEdges           = struct('K', 1839.0, 'L1', 149.7, 'L2', 99.8, 'L3', 99.2);

elements(15) = makeElement(15, 'P', 'Phosphorus', 30.974, 15, 3, 'nonmetal');
elements(15).density             = 1.823;
elements(15).electronConfig      = '[Ne] 3s2 3p3';
elements(15).electronegativity   = 2.19;
elements(15).atomicRadius        = 98;
elements(15).ionizationEnergy    = 10.4867;
elements(15).electronAffinity    = 0.7465;
elements(15).meltingPoint        = 317.25;
elements(15).boilingPoint        = 553.65;
elements(15).thermalConductivity = 0.236;
elements(15).bCoherent           = 5.13;
elements(15).xrayEdges           = struct('K', 2145.5, 'L1', 189.3, 'L2', 136.0, 'L3', 135.0);

elements(16) = makeElement(16, 'S', 'Sulfur', 32.06, 16, 3, 'nonmetal');
elements(16).density             = 2.07;
elements(16).electronConfig      = '[Ne] 3s2 3p4';
elements(16).electronegativity   = 2.58;
elements(16).atomicRadius        = 88;
elements(16).ionizationEnergy    = 10.3600;
elements(16).electronAffinity    = 2.0771;
elements(16).meltingPoint        = 388.36;
elements(16).boilingPoint        = 717.87;
elements(16).thermalConductivity = 0.205;
elements(16).bCoherent           = 2.847;
elements(16).xrayEdges           = struct('K', 2472.0, 'L1', 229.2, 'L2', 165.5, 'L3', 164.1);

elements(17) = makeElement(17, 'Cl', 'Chlorine', 35.45, 17, 3, 'halogen');
elements(17).density             = 0.003214;
elements(17).electronConfig      = '[Ne] 3s2 3p5';
elements(17).electronegativity   = 3.16;
elements(17).atomicRadius        = 79;
elements(17).ionizationEnergy    = 12.9676;
elements(17).electronAffinity    = 3.6127;
elements(17).meltingPoint        = 171.65;
elements(17).boilingPoint        = 239.11;
elements(17).thermalConductivity = 0.0089;
elements(17).bCoherent           = 9.577;
elements(17).xrayEdges           = struct('K', 2822.4, 'L1', 270.2, 'L2', 201.6, 'L3', 200.0);

elements(18) = makeElement(18, 'Ar', 'Argon', 39.948, 18, 3, 'noble gas');
elements(18).density             = 0.001784;
elements(18).electronConfig      = '[Ne] 3s2 3p6';
elements(18).electronegativity   = NaN;
elements(18).atomicRadius        = 71;
elements(18).ionizationEnergy    = 15.7596;
elements(18).electronAffinity    = 0;
elements(18).meltingPoint        = 83.80;
elements(18).boilingPoint        = 87.30;
elements(18).thermalConductivity = 0.01772;
elements(18).bCoherent           = 1.909;
elements(18).xrayEdges           = struct('K', 3205.9, 'L1', 326.3, 'L2', 250.6, 'L3', 248.4);

% ── Period 4 ─────────────────────────────────────────────────────────
elements(19) = makeElement(19, 'K', 'Potassium', 39.098, 1, 4, 'alkali metal');
elements(19).density             = 0.862;
elements(19).electronConfig      = '[Ar] 4s1';
elements(19).electronegativity   = 0.82;
elements(19).atomicRadius        = 243;
elements(19).ionizationEnergy    = 4.3407;
elements(19).electronAffinity    = 0.5015;
elements(19).meltingPoint        = 336.53;
elements(19).boilingPoint        = 1032;
elements(19).thermalConductivity = 102.5;
elements(19).bCoherent           = 3.67;
elements(19).xrayEdges           = struct('K', 3608.4, 'L1', 378.6, 'L2', 297.3, 'L3', 294.6);

elements(20) = makeElement(20, 'Ca', 'Calcium', 40.078, 2, 4, 'alkaline earth metal');
elements(20).density             = 1.55;
elements(20).electronConfig      = '[Ar] 4s2';
elements(20).electronegativity   = 1.00;
elements(20).atomicRadius        = 194;
elements(20).ionizationEnergy    = 6.1132;
elements(20).electronAffinity    = 0.02455;
elements(20).meltingPoint        = 1115;
elements(20).boilingPoint        = 1757;
elements(20).thermalConductivity = 201;
elements(20).bCoherent           = 4.70;
elements(20).xrayEdges           = struct('K', 4038.5, 'L1', 437.8, 'L2', 350.0, 'L3', 346.2);

elements(21) = makeElement(21, 'Sc', 'Scandium', 44.956, 3, 4, 'transition metal');
elements(21).density             = 2.985;
elements(21).electronConfig      = '[Ar] 3d1 4s2';
elements(21).electronegativity   = 1.36;
elements(21).atomicRadius        = 184;
elements(21).ionizationEnergy    = 6.5615;
elements(21).electronAffinity    = 0.188;
elements(21).meltingPoint        = 1814;
elements(21).boilingPoint        = 3109;
elements(21).thermalConductivity = 15.8;
elements(21).bCoherent           = 12.29;
elements(21).xrayEdges           = struct('K', 4492.8, 'L1', 500.4, 'L2', 403.6, 'L3', 398.7);

elements(22) = makeElement(22, 'Ti', 'Titanium', 47.867, 4, 4, 'transition metal');
elements(22).density             = 4.507;
elements(22).electronConfig      = '[Ar] 3d2 4s2';
elements(22).electronegativity   = 1.54;
elements(22).atomicRadius        = 176;
elements(22).ionizationEnergy    = 6.8281;
elements(22).electronAffinity    = 0.0787;
elements(22).meltingPoint        = 1941;
elements(22).boilingPoint        = 3560;
elements(22).thermalConductivity = 21.9;
elements(22).bCoherent           = -3.438;
elements(22).xrayEdges           = struct('K', 4966.4, 'L1', 563.4, 'L2', 461.2, 'L3', 453.8);

elements(23) = makeElement(23, 'V', 'Vanadium', 50.942, 5, 4, 'transition metal');
elements(23).density             = 6.11;
elements(23).electronConfig      = '[Ar] 3d3 4s2';
elements(23).electronegativity   = 1.63;
elements(23).atomicRadius        = 171;
elements(23).ionizationEnergy    = 6.7462;
elements(23).electronAffinity    = 0.5258;
elements(23).meltingPoint        = 2183;
elements(23).boilingPoint        = 3680;
elements(23).thermalConductivity = 30.7;
elements(23).bCoherent           = -0.3824;
elements(23).xrayEdges           = struct('K', 5465.1, 'L1', 626.7, 'L2', 519.8, 'L3', 512.1);

elements(24) = makeElement(24, 'Cr', 'Chromium', 51.996, 6, 4, 'transition metal');
elements(24).density             = 7.19;
elements(24).electronConfig      = '[Ar] 3d5 4s1';
elements(24).electronegativity   = 1.66;
elements(24).atomicRadius        = 166;
elements(24).ionizationEnergy    = 6.7665;
elements(24).electronAffinity    = 0.6680;
elements(24).meltingPoint        = 2180;
elements(24).boilingPoint        = 2944;
elements(24).thermalConductivity = 93.9;
elements(24).bCoherent           = 3.635;
elements(24).xrayEdges           = struct('K', 5988.8, 'L1', 695.7, 'L2', 583.8, 'L3', 574.1);

elements(25) = makeElement(25, 'Mn', 'Manganese', 54.938, 7, 4, 'transition metal');
elements(25).density             = 7.47;
elements(25).electronConfig      = '[Ar] 3d5 4s2';
elements(25).electronegativity   = 1.55;
elements(25).atomicRadius        = 161;
elements(25).ionizationEnergy    = 7.4340;
elements(25).electronAffinity    = 0;
elements(25).meltingPoint        = 1519;
elements(25).boilingPoint        = 2334;
elements(25).thermalConductivity = 7.81;
elements(25).bCoherent           = -3.73;
elements(25).xrayEdges           = struct('K', 6539.0, 'L1', 769.1, 'L2', 649.9, 'L3', 638.7);

elements(26) = makeElement(26, 'Fe', 'Iron', 55.845, 8, 4, 'transition metal');
elements(26).density             = 7.874;
elements(26).electronConfig      = '[Ar] 3d6 4s2';
elements(26).electronegativity   = 1.83;
elements(26).atomicRadius        = 156;
elements(26).ionizationEnergy    = 7.9024;
elements(26).electronAffinity    = 0.1510;
elements(26).meltingPoint        = 1811;
elements(26).boilingPoint        = 3134;
elements(26).thermalConductivity = 80.4;
elements(26).bCoherent           = 9.45;
elements(26).xrayEdges           = struct('K', 7112.0, 'L1', 844.6, 'L2', 719.9, 'L3', 706.8);

elements(27) = makeElement(27, 'Co', 'Cobalt', 58.933, 9, 4, 'transition metal');
elements(27).density             = 8.90;
elements(27).electronConfig      = '[Ar] 3d7 4s2';
elements(27).electronegativity   = 1.88;
elements(27).atomicRadius        = 152;
elements(27).ionizationEnergy    = 7.8810;
elements(27).electronAffinity    = 0.6633;
elements(27).meltingPoint        = 1768;
elements(27).boilingPoint        = 3200;
elements(27).thermalConductivity = 100;
elements(27).bCoherent           = 2.49;
elements(27).xrayEdges           = struct('K', 7709.0, 'L1', 925.1, 'L2', 793.2, 'L3', 778.1);

elements(28) = makeElement(28, 'Ni', 'Nickel', 58.693, 10, 4, 'transition metal');
elements(28).density             = 8.908;
elements(28).electronConfig      = '[Ar] 3d8 4s2';
elements(28).electronegativity   = 1.91;
elements(28).atomicRadius        = 149;
elements(28).ionizationEnergy    = 7.6398;
elements(28).electronAffinity    = 1.1562;
elements(28).meltingPoint        = 1728;
elements(28).boilingPoint        = 3186;
elements(28).thermalConductivity = 90.9;
elements(28).bCoherent           = 10.3;
elements(28).xrayEdges           = struct('K', 8333.0, 'L1', 1008.6, 'L2', 870.0, 'L3', 852.7);

elements(29) = makeElement(29, 'Cu', 'Copper', 63.546, 11, 4, 'transition metal');
elements(29).density             = 8.96;
elements(29).electronConfig      = '[Ar] 3d10 4s1';
elements(29).electronegativity   = 1.90;
elements(29).atomicRadius        = 145;
elements(29).ionizationEnergy    = 7.7264;
elements(29).electronAffinity    = 1.2357;
elements(29).meltingPoint        = 1357.77;
elements(29).boilingPoint        = 2835;
elements(29).thermalConductivity = 401;
elements(29).bCoherent           = 7.718;
elements(29).xrayEdges           = struct('K', 8979.0, 'L1', 1096.7, 'L2', 952.3, 'L3', 932.7);

elements(30) = makeElement(30, 'Zn', 'Zinc', 65.38, 12, 4, 'transition metal');
elements(30).density             = 7.14;
elements(30).electronConfig      = '[Ar] 3d10 4s2';
elements(30).electronegativity   = 1.65;
elements(30).atomicRadius        = 142;
elements(30).ionizationEnergy    = 9.3942;
elements(30).electronAffinity    = 0;
elements(30).meltingPoint        = 692.68;
elements(30).boilingPoint        = 1180;
elements(30).thermalConductivity = 116;
elements(30).bCoherent           = 5.680;
elements(30).xrayEdges           = struct('K', 9659.0, 'L1', 1196.2, 'L2', 1044.9, 'L3', 1021.8);

elements(31) = makeElement(31, 'Ga', 'Gallium', 69.723, 13, 4, 'post-transition metal');
elements(31).density             = 5.91;
elements(31).electronConfig      = '[Ar] 3d10 4s2 4p1';
elements(31).electronegativity   = 1.81;
elements(31).atomicRadius        = 136;
elements(31).ionizationEnergy    = 5.9993;
elements(31).electronAffinity    = 0.3012;
elements(31).meltingPoint        = 302.91;
elements(31).boilingPoint        = 2477;
elements(31).thermalConductivity = 40.6;
elements(31).bCoherent           = 7.288;
elements(31).xrayEdges           = struct('K', 10367.0, 'L1', 1299.0, 'L2', 1143.2, 'L3', 1116.4);

elements(32) = makeElement(32, 'Ge', 'Germanium', 72.630, 14, 4, 'metalloid');
elements(32).density             = 5.323;
elements(32).electronConfig      = '[Ar] 3d10 4s2 4p2';
elements(32).electronegativity   = 2.01;
elements(32).atomicRadius        = 125;
elements(32).ionizationEnergy    = 7.8994;
elements(32).electronAffinity    = 1.2328;
elements(32).meltingPoint        = 1211.40;
elements(32).boilingPoint        = 3106;
elements(32).thermalConductivity = 60.2;
elements(32).bCoherent           = 8.185;
elements(32).xrayEdges           = struct('K', 11103.1, 'L1', 1414.6, 'L2', 1248.1, 'L3', 1217.0);

elements(33) = makeElement(33, 'As', 'Arsenic', 74.922, 15, 4, 'metalloid');
elements(33).density             = 5.727;
elements(33).electronConfig      = '[Ar] 3d10 4s2 4p3';
elements(33).electronegativity   = 2.18;
elements(33).atomicRadius        = 114;
elements(33).ionizationEnergy    = 9.7886;
elements(33).electronAffinity    = 0.8048;
elements(33).meltingPoint        = 1090;
elements(33).boilingPoint        = 887;
elements(33).thermalConductivity = 50.2;
elements(33).bCoherent           = 6.58;
elements(33).xrayEdges           = struct('K', 11867.0, 'L1', 1526.5, 'L2', 1358.6, 'L3', 1323.1);

elements(34) = makeElement(34, 'Se', 'Selenium', 78.971, 16, 4, 'nonmetal');
elements(34).density             = 4.81;
elements(34).electronConfig      = '[Ar] 3d10 4s2 4p4';
elements(34).electronegativity   = 2.55;
elements(34).atomicRadius        = 103;
elements(34).ionizationEnergy    = 9.7524;
elements(34).electronAffinity    = 2.0207;
elements(34).meltingPoint        = 494;
elements(34).boilingPoint        = 958;
elements(34).thermalConductivity = 0.52;
elements(34).bCoherent           = 7.970;
elements(34).xrayEdges           = struct('K', 12657.8, 'L1', 1652.0, 'L2', 1474.3, 'L3', 1433.9);

elements(35) = makeElement(35, 'Br', 'Bromine', 79.904, 17, 4, 'halogen');
elements(35).density             = 3.1028;
elements(35).electronConfig      = '[Ar] 3d10 4s2 4p5';
elements(35).electronegativity   = 2.96;
elements(35).atomicRadius        = 94;
elements(35).ionizationEnergy    = 11.8138;
elements(35).electronAffinity    = 3.3636;
elements(35).meltingPoint        = 265.8;
elements(35).boilingPoint        = 332.0;
elements(35).thermalConductivity = 0.122;
elements(35).bCoherent           = 6.795;
elements(35).xrayEdges           = struct('K', 13474.0, 'L1', 1782.0, 'L2', 1596.0, 'L3', 1549.9);

elements(36) = makeElement(36, 'Kr', 'Krypton', 83.798, 18, 4, 'noble gas');
elements(36).density             = 0.003749;
elements(36).electronConfig      = '[Ar] 3d10 4s2 4p6';
elements(36).electronegativity   = 3.00;
elements(36).atomicRadius        = 88;
elements(36).ionizationEnergy    = 13.9996;
elements(36).electronAffinity    = 0;
elements(36).meltingPoint        = 115.79;
elements(36).boilingPoint        = 119.93;
elements(36).thermalConductivity = 0.00943;
elements(36).bCoherent           = 7.81;
elements(36).xrayEdges           = struct('K', 14325.6, 'L1', 1921.0, 'L2', 1730.9, 'L3', 1678.4);

% ── Period 5 ─────────────────────────────────────────────────────────
elements(37) = makeElement(37, 'Rb', 'Rubidium', 85.468, 1, 5, 'alkali metal');
elements(37).density             = 1.532;
elements(37).electronConfig      = '[Kr] 5s1';
elements(37).electronegativity   = 0.82;
elements(37).atomicRadius        = 265;
elements(37).ionizationEnergy    = 4.1771;
elements(37).electronAffinity    = 0.4860;
elements(37).meltingPoint        = 312.46;
elements(37).boilingPoint        = 961;
elements(37).thermalConductivity = 58.2;
elements(37).bCoherent           = 7.09;
elements(37).xrayEdges           = struct('K', 15199.7, 'L1', 2065.1, 'L2', 1863.9, 'L3', 1804.4);

elements(38) = makeElement(38, 'Sr', 'Strontium', 87.62, 2, 5, 'alkaline earth metal');
elements(38).density             = 2.64;
elements(38).electronConfig      = '[Kr] 5s2';
elements(38).electronegativity   = 0.95;
elements(38).atomicRadius        = 219;
elements(38).ionizationEnergy    = 5.6949;
elements(38).electronAffinity    = 0.0518;
elements(38).meltingPoint        = 1050;
elements(38).boilingPoint        = 1655;
elements(38).thermalConductivity = 35.4;
elements(38).bCoherent           = 7.02;
elements(38).xrayEdges           = struct('K', 16104.6, 'L1', 2216.3, 'L2', 2006.8, 'L3', 1939.6);

elements(39) = makeElement(39, 'Y', 'Yttrium', 88.906, 3, 5, 'transition metal');
elements(39).density             = 4.472;
elements(39).electronConfig      = '[Kr] 4d1 5s2';
elements(39).electronegativity   = 1.22;
elements(39).atomicRadius        = 212;
elements(39).ionizationEnergy    = 6.2173;
elements(39).electronAffinity    = 0.307;
elements(39).meltingPoint        = 1799;
elements(39).boilingPoint        = 3609;
elements(39).thermalConductivity = 17.2;
elements(39).bCoherent           = 7.75;
elements(39).xrayEdges           = struct('K', 17038.4, 'L1', 2372.5, 'L2', 2155.5, 'L3', 2080.0);

elements(40) = makeElement(40, 'Zr', 'Zirconium', 91.224, 4, 5, 'transition metal');
elements(40).density             = 6.52;
elements(40).electronConfig      = '[Kr] 4d2 5s2';
elements(40).electronegativity   = 1.33;
elements(40).atomicRadius        = 206;
elements(40).ionizationEnergy    = 6.6339;
elements(40).electronAffinity    = 0.426;
elements(40).meltingPoint        = 2128;
elements(40).boilingPoint        = 4682;
elements(40).thermalConductivity = 22.6;
elements(40).bCoherent           = 7.16;
elements(40).xrayEdges           = struct('K', 17998.0, 'L1', 2531.6, 'L2', 2306.7, 'L3', 2222.3);

elements(41) = makeElement(41, 'Nb', 'Niobium', 92.906, 5, 5, 'transition metal');
elements(41).density             = 8.57;
elements(41).electronConfig      = '[Kr] 4d4 5s1';
elements(41).electronegativity   = 1.60;
elements(41).atomicRadius        = 198;
elements(41).ionizationEnergy    = 6.7589;
elements(41).electronAffinity    = 0.8935;
elements(41).meltingPoint        = 2750;
elements(41).boilingPoint        = 5017;
elements(41).thermalConductivity = 53.7;
elements(41).bCoherent           = 7.054;
elements(41).xrayEdges           = struct('K', 18986.0, 'L1', 2697.7, 'L2', 2464.7, 'L3', 2370.5);

elements(42) = makeElement(42, 'Mo', 'Molybdenum', 95.95, 6, 5, 'transition metal');
elements(42).density             = 10.28;
elements(42).electronConfig      = '[Kr] 4d5 5s1';
elements(42).electronegativity   = 2.16;
elements(42).atomicRadius        = 190;
elements(42).ionizationEnergy    = 7.0924;
elements(42).electronAffinity    = 0.7472;
elements(42).meltingPoint        = 2896;
elements(42).boilingPoint        = 4912;
elements(42).thermalConductivity = 138;
elements(42).bCoherent           = 6.715;
elements(42).xrayEdges           = struct('K', 19999.5, 'L1', 2865.5, 'L2', 2625.1, 'L3', 2520.2);

elements(43) = makeElement(43, 'Tc', 'Technetium', 97.0, 7, 5, 'transition metal');
elements(43).density             = 11.5;
elements(43).electronConfig      = '[Kr] 4d5 5s2';
elements(43).electronegativity   = 1.90;
elements(43).atomicRadius        = 183;
elements(43).ionizationEnergy    = 7.28;
elements(43).electronAffinity    = 0.55;
elements(43).meltingPoint        = 2430;
elements(43).boilingPoint        = 4538;
elements(43).thermalConductivity = 50.6;
elements(43).bCoherent           = 6.8;
elements(43).xrayEdges           = struct('K', 21044.0, 'L1', 3042.5, 'L2', 2793.2, 'L3', 2676.9);

elements(44) = makeElement(44, 'Ru', 'Ruthenium', 101.07, 8, 5, 'transition metal');
elements(44).density             = 12.45;
elements(44).electronConfig      = '[Kr] 4d7 5s1';
elements(44).electronegativity   = 2.20;
elements(44).atomicRadius        = 178;
elements(44).ionizationEnergy    = 7.3605;
elements(44).electronAffinity    = 1.04638;
elements(44).meltingPoint        = 2607;
elements(44).boilingPoint        = 4423;
elements(44).thermalConductivity = 117;
elements(44).bCoherent           = 7.03;
elements(44).xrayEdges           = struct('K', 22117.2, 'L1', 3224.0, 'L2', 2966.9, 'L3', 2837.9);

elements(45) = makeElement(45, 'Rh', 'Rhodium', 102.91, 9, 5, 'transition metal');
elements(45).density             = 12.41;
elements(45).electronConfig      = '[Kr] 4d8 5s1';
elements(45).electronegativity   = 2.28;
elements(45).atomicRadius        = 173;
elements(45).ionizationEnergy    = 7.4589;
elements(45).electronAffinity    = 1.14289;
elements(45).meltingPoint        = 2237;
elements(45).boilingPoint        = 3968;
elements(45).thermalConductivity = 150;
elements(45).bCoherent           = 5.88;
elements(45).xrayEdges           = struct('K', 23219.9, 'L1', 3411.9, 'L2', 3146.1, 'L3', 3003.8);

elements(46) = makeElement(46, 'Pd', 'Palladium', 106.42, 10, 5, 'transition metal');
elements(46).density             = 12.023;
elements(46).electronConfig      = '[Kr] 4d10';
elements(46).electronegativity   = 2.20;
elements(46).atomicRadius        = 169;
elements(46).ionizationEnergy    = 8.3369;
elements(46).electronAffinity    = 0.5613;
elements(46).meltingPoint        = 1828.05;
elements(46).boilingPoint        = 3236;
elements(46).thermalConductivity = 71.8;
elements(46).bCoherent           = 5.91;
elements(46).xrayEdges           = struct('K', 24350.3, 'L1', 3604.3, 'L2', 3330.3, 'L3', 3173.3);

elements(47) = makeElement(47, 'Ag', 'Silver', 107.87, 11, 5, 'transition metal');
elements(47).density             = 10.49;
elements(47).electronConfig      = '[Kr] 4d10 5s1';
elements(47).electronegativity   = 1.93;
elements(47).atomicRadius        = 165;
elements(47).ionizationEnergy    = 7.5762;
elements(47).electronAffinity    = 1.30447;
elements(47).meltingPoint        = 1234.93;
elements(47).boilingPoint        = 2435;
elements(47).thermalConductivity = 429;
elements(47).bCoherent           = 5.922;
elements(47).xrayEdges           = struct('K', 25514.0, 'L1', 3805.8, 'L2', 3523.7, 'L3', 3351.1);

elements(48) = makeElement(48, 'Cd', 'Cadmium', 112.41, 12, 5, 'transition metal');
elements(48).density             = 8.65;
elements(48).electronConfig      = '[Kr] 4d10 5s2';
elements(48).electronegativity   = 1.69;
elements(48).atomicRadius        = 161;
elements(48).ionizationEnergy    = 8.9938;
elements(48).electronAffinity    = 0;
elements(48).meltingPoint        = 594.22;
elements(48).boilingPoint        = 1040;
elements(48).thermalConductivity = 96.6;
elements(48).bCoherent           = 4.87;
elements(48).xrayEdges           = struct('K', 26711.2, 'L1', 4018.0, 'L2', 3727.0, 'L3', 3537.5);

elements(49) = makeElement(49, 'In', 'Indium', 114.82, 13, 5, 'post-transition metal');
elements(49).density             = 7.31;
elements(49).electronConfig      = '[Kr] 4d10 5s2 5p1';
elements(49).electronegativity   = 1.78;
elements(49).atomicRadius        = 156;
elements(49).ionizationEnergy    = 5.7864;
elements(49).electronAffinity    = 0.3040;
elements(49).meltingPoint        = 429.75;
elements(49).boilingPoint        = 2345;
elements(49).thermalConductivity = 81.8;
elements(49).bCoherent           = 4.065;
elements(49).xrayEdges           = struct('K', 27939.9, 'L1', 4237.5, 'L2', 3938.0, 'L3', 3730.1);

elements(50) = makeElement(50, 'Sn', 'Tin', 118.71, 14, 5, 'post-transition metal');
elements(50).density             = 7.265;
elements(50).electronConfig      = '[Kr] 4d10 5s2 5p2';
elements(50).electronegativity   = 1.96;
elements(50).atomicRadius        = 145;
elements(50).ionizationEnergy    = 7.3439;
elements(50).electronAffinity    = 1.1121;
elements(50).meltingPoint        = 505.08;
elements(50).boilingPoint        = 2875;
elements(50).thermalConductivity = 66.8;
elements(50).bCoherent           = 6.225;
elements(50).xrayEdges           = struct('K', 29200.1, 'L1', 4464.7, 'L2', 4156.1, 'L3', 3928.8);

elements(51) = makeElement(51, 'Sb', 'Antimony', 121.76, 15, 5, 'metalloid');
elements(51).density             = 6.697;
elements(51).electronConfig      = '[Kr] 4d10 5s2 5p3';
elements(51).electronegativity   = 2.05;
elements(51).atomicRadius        = 133;
elements(51).ionizationEnergy    = 8.6084;
elements(51).electronAffinity    = 1.0672;
elements(51).meltingPoint        = 903.78;
elements(51).boilingPoint        = 1908;
elements(51).thermalConductivity = 24.3;
elements(51).bCoherent           = 5.57;
elements(51).xrayEdges           = struct('K', 30491.2, 'L1', 4698.3, 'L2', 4380.4, 'L3', 4132.2);

elements(52) = makeElement(52, 'Te', 'Tellurium', 127.60, 16, 5, 'metalloid');
elements(52).density             = 6.24;
elements(52).electronConfig      = '[Kr] 4d10 5s2 5p4';
elements(52).electronegativity   = 2.10;
elements(52).atomicRadius        = 123;
elements(52).ionizationEnergy    = 9.0096;
elements(52).electronAffinity    = 1.9708;
elements(52).meltingPoint        = 722.66;
elements(52).boilingPoint        = 1261;
elements(52).thermalConductivity = 2.35;
elements(52).bCoherent           = 5.80;
elements(52).xrayEdges           = struct('K', 31814.0, 'L1', 4939.2, 'L2', 4612.0, 'L3', 4341.4);

elements(53) = makeElement(53, 'I', 'Iodine', 126.90, 17, 5, 'halogen');
elements(53).density             = 4.933;
elements(53).electronConfig      = '[Kr] 4d10 5s2 5p5';
elements(53).electronegativity   = 2.66;
elements(53).atomicRadius        = 115;
elements(53).ionizationEnergy    = 10.4513;
elements(53).electronAffinity    = 3.0590;
elements(53).meltingPoint        = 386.85;
elements(53).boilingPoint        = 457.55;
elements(53).thermalConductivity = 0.449;
elements(53).bCoherent           = 5.28;
elements(53).xrayEdges           = struct('K', 33169.4, 'L1', 5188.1, 'L2', 4852.1, 'L3', 4557.1);

elements(54) = makeElement(54, 'Xe', 'Xenon', 131.29, 18, 5, 'noble gas');
elements(54).density             = 0.005887;
elements(54).electronConfig      = '[Kr] 4d10 5s2 5p6';
elements(54).electronegativity   = 2.60;
elements(54).atomicRadius        = 108;
elements(54).ionizationEnergy    = 12.1298;
elements(54).electronAffinity    = 0;
elements(54).meltingPoint        = 161.36;
elements(54).boilingPoint        = 165.03;
elements(54).thermalConductivity = 0.00565;
elements(54).bCoherent           = 4.92;
elements(54).xrayEdges           = struct('K', 34561.4, 'L1', 5452.8, 'L2', 5103.7, 'L3', 4782.2);

% ── Period 6 ─────────────────────────────────────────────────────────
elements(55) = makeElement(55, 'Cs', 'Caesium', 132.91, 1, 6, 'alkali metal');
elements(55).density             = 1.93;
elements(55).electronConfig      = '[Xe] 6s1';
elements(55).electronegativity   = 0.79;
elements(55).atomicRadius        = 298;
elements(55).ionizationEnergy    = 3.8939;
elements(55).electronAffinity    = 0.4716;
elements(55).meltingPoint        = 301.59;
elements(55).boilingPoint        = 944;
elements(55).thermalConductivity = 35.9;
elements(55).bCoherent           = 5.42;
elements(55).xrayEdges           = struct('K', 35984.6, 'L1', 5714.3, 'L2', 5359.4, 'L3', 5012.0);

elements(56) = makeElement(56, 'Ba', 'Barium', 137.33, 2, 6, 'alkaline earth metal');
elements(56).density             = 3.51;
elements(56).electronConfig      = '[Xe] 6s2';
elements(56).electronegativity   = 0.89;
elements(56).atomicRadius        = 253;
elements(56).ionizationEnergy    = 5.2117;
elements(56).electronAffinity    = 0.14462;
elements(56).meltingPoint        = 1000;
elements(56).boilingPoint        = 2118;
elements(56).thermalConductivity = 18.4;
elements(56).bCoherent           = 5.07;
elements(56).xrayEdges           = struct('K', 37440.6, 'L1', 5988.6, 'L2', 5623.6, 'L3', 5247.0);

% Lanthanides (Z 57-71, group 0, period 6)
elements(57) = makeElement(57, 'La', 'Lanthanum', 138.91, 0, 6, 'lanthanide');
elements(57).density             = 6.145;
elements(57).electronConfig      = '[Xe] 5d1 6s2';
elements(57).electronegativity   = 1.10;
elements(57).atomicRadius        = 195;
elements(57).ionizationEnergy    = 5.5769;
elements(57).electronAffinity    = 0.47;
elements(57).meltingPoint        = 1193;
elements(57).boilingPoint        = 3737;
elements(57).thermalConductivity = 13.4;
elements(57).bCoherent           = 8.24;
elements(57).xrayEdges           = struct('K', 38924.6, 'L1', 6266.3, 'L2', 5890.6, 'L3', 5482.7);

elements(58) = makeElement(58, 'Ce', 'Cerium', 140.12, 0, 6, 'lanthanide');
elements(58).density             = 6.770;
elements(58).electronConfig      = '[Xe] 4f1 5d1 6s2';
elements(58).electronegativity   = 1.12;
elements(58).atomicRadius        = 185;
elements(58).ionizationEnergy    = 5.5387;
elements(58).electronAffinity    = 0.50;
elements(58).meltingPoint        = 1068;
elements(58).boilingPoint        = 3716;
elements(58).thermalConductivity = 11.3;
elements(58).bCoherent           = 4.84;
elements(58).xrayEdges           = struct('K', 40443.0, 'L1', 6548.8, 'L2', 6164.2, 'L3', 5723.4);

elements(59) = makeElement(59, 'Pr', 'Praseodymium', 140.91, 0, 6, 'lanthanide');
elements(59).density             = 6.77;
elements(59).electronConfig      = '[Xe] 4f3 6s2';
elements(59).electronegativity   = 1.13;
elements(59).atomicRadius        = 185;
elements(59).ionizationEnergy    = 5.473;
elements(59).electronAffinity    = 0.50;
elements(59).meltingPoint        = 1208;
elements(59).boilingPoint        = 3793;
elements(59).thermalConductivity = 12.5;
elements(59).bCoherent           = 4.58;
elements(59).xrayEdges           = struct('K', 41990.6, 'L1', 6834.8, 'L2', 6440.4, 'L3', 5964.3);

elements(60) = makeElement(60, 'Nd', 'Neodymium', 144.24, 0, 6, 'lanthanide');
elements(60).density             = 7.01;
elements(60).electronConfig      = '[Xe] 4f4 6s2';
elements(60).electronegativity   = 1.14;
elements(60).atomicRadius        = 185;
elements(60).ionizationEnergy    = 5.5250;
elements(60).electronAffinity    = 0.50;
elements(60).meltingPoint        = 1297;
elements(60).boilingPoint        = 3347;
elements(60).thermalConductivity = 16.5;
elements(60).bCoherent           = 7.69;
elements(60).xrayEdges           = struct('K', 43568.9, 'L1', 7126.0, 'L2', 6721.5, 'L3', 6207.9);

elements(61) = makeElement(61, 'Pm', 'Promethium', 145.0, 0, 6, 'lanthanide');
elements(61).density             = 7.26;
elements(61).electronConfig      = '[Xe] 4f5 6s2';
elements(61).electronegativity   = 1.13;
elements(61).atomicRadius        = 185;
elements(61).ionizationEnergy    = 5.582;
elements(61).electronAffinity    = 0.50;
elements(61).meltingPoint        = 1315;
elements(61).boilingPoint        = 3273;
elements(61).thermalConductivity = 17.9;
elements(61).bCoherent           = NaN;
elements(61).xrayEdges           = struct('K', 45184.0, 'L1', 7428.0, 'L2', 7012.8, 'L3', 6459.3);

elements(62) = makeElement(62, 'Sm', 'Samarium', 150.36, 0, 6, 'lanthanide');
elements(62).density             = 7.52;
elements(62).electronConfig      = '[Xe] 4f6 6s2';
elements(62).electronegativity   = 1.17;
elements(62).atomicRadius        = 185;
elements(62).ionizationEnergy    = 5.6437;
elements(62).electronAffinity    = 0.50;
elements(62).meltingPoint        = 1345;
elements(62).boilingPoint        = 2067;
elements(62).thermalConductivity = 13.3;
elements(62).bCoherent           = 0.80;
elements(62).xrayEdges           = struct('K', 46834.2, 'L1', 7736.8, 'L2', 7311.8, 'L3', 6716.2);

elements(63) = makeElement(63, 'Eu', 'Europium', 151.96, 0, 6, 'lanthanide');
elements(63).density             = 5.244;
elements(63).electronConfig      = '[Xe] 4f7 6s2';
elements(63).electronegativity   = 1.20;
elements(63).atomicRadius        = 185;
elements(63).ionizationEnergy    = 5.6704;
elements(63).electronAffinity    = 0.50;
elements(63).meltingPoint        = 1099;
elements(63).boilingPoint        = 1802;
elements(63).thermalConductivity = 13.9;
elements(63).bCoherent           = 7.22;
elements(63).xrayEdges           = struct('K', 48519.0, 'L1', 8052.0, 'L2', 7617.1, 'L3', 6976.9);

elements(64) = makeElement(64, 'Gd', 'Gadolinium', 157.25, 0, 6, 'lanthanide');
elements(64).density             = 7.90;
elements(64).electronConfig      = '[Xe] 4f7 5d1 6s2';
elements(64).electronegativity   = 1.20;
elements(64).atomicRadius        = 180;
elements(64).ionizationEnergy    = 6.1501;
elements(64).electronAffinity    = 0.50;
elements(64).meltingPoint        = 1585;
elements(64).boilingPoint        = 3546;
elements(64).thermalConductivity = 10.6;
elements(64).bCoherent           = 9.5;
elements(64).xrayEdges           = struct('K', 50239.1, 'L1', 8375.6, 'L2', 7930.3, 'L3', 7242.8);

elements(65) = makeElement(65, 'Tb', 'Terbium', 158.93, 0, 6, 'lanthanide');
elements(65).density             = 8.23;
elements(65).electronConfig      = '[Xe] 4f9 6s2';
elements(65).electronegativity   = 1.10;
elements(65).atomicRadius        = 175;
elements(65).ionizationEnergy    = 5.8638;
elements(65).electronAffinity    = 0.50;
elements(65).meltingPoint        = 1629;
elements(65).boilingPoint        = 3503;
elements(65).thermalConductivity = 11.1;
elements(65).bCoherent           = 7.38;
elements(65).xrayEdges           = struct('K', 51995.7, 'L1', 8708.0, 'L2', 8251.6, 'L3', 7514.0);

elements(66) = makeElement(66, 'Dy', 'Dysprosium', 162.50, 0, 6, 'lanthanide');
elements(66).density             = 8.55;
elements(66).electronConfig      = '[Xe] 4f10 6s2';
elements(66).electronegativity   = 1.22;
elements(66).atomicRadius        = 175;
elements(66).ionizationEnergy    = 5.9389;
elements(66).electronAffinity    = 0.50;
elements(66).meltingPoint        = 1680;
elements(66).boilingPoint        = 2840;
elements(66).thermalConductivity = 10.7;
elements(66).bCoherent           = 16.9;
elements(66).xrayEdges           = struct('K', 53788.5, 'L1', 9045.8, 'L2', 8580.6, 'L3', 7790.1);

elements(67) = makeElement(67, 'Ho', 'Holmium', 164.93, 0, 6, 'lanthanide');
elements(67).density             = 8.80;
elements(67).electronConfig      = '[Xe] 4f11 6s2';
elements(67).electronegativity   = 1.23;
elements(67).atomicRadius        = 175;
elements(67).ionizationEnergy    = 6.0215;
elements(67).electronAffinity    = 0.50;
elements(67).meltingPoint        = 1734;
elements(67).boilingPoint        = 2993;
elements(67).thermalConductivity = 16.2;
elements(67).bCoherent           = 8.01;
elements(67).xrayEdges           = struct('K', 55617.7, 'L1', 9394.2, 'L2', 8917.8, 'L3', 8071.1);

elements(68) = makeElement(68, 'Er', 'Erbium', 167.26, 0, 6, 'lanthanide');
elements(68).density             = 9.07;
elements(68).electronConfig      = '[Xe] 4f12 6s2';
elements(68).electronegativity   = 1.24;
elements(68).atomicRadius        = 175;
elements(68).ionizationEnergy    = 6.1077;
elements(68).electronAffinity    = 0.50;
elements(68).meltingPoint        = 1802;
elements(68).boilingPoint        = 3141;
elements(68).thermalConductivity = 14.5;
elements(68).bCoherent           = 7.79;
elements(68).xrayEdges           = struct('K', 57485.5, 'L1', 9751.3, 'L2', 9264.3, 'L3', 8357.9);

elements(69) = makeElement(69, 'Tm', 'Thulium', 168.93, 0, 6, 'lanthanide');
elements(69).density             = 9.32;
elements(69).electronConfig      = '[Xe] 4f13 6s2';
elements(69).electronegativity   = 1.25;
elements(69).atomicRadius        = 175;
elements(69).ionizationEnergy    = 6.1843;
elements(69).electronAffinity    = 0.50;
elements(69).meltingPoint        = 1818;
elements(69).boilingPoint        = 2223;
elements(69).thermalConductivity = 16.9;
elements(69).bCoherent           = 7.07;
elements(69).xrayEdges           = struct('K', 59389.6, 'L1', 10115.7, 'L2', 9616.9, 'L3', 8648.0);

elements(70) = makeElement(70, 'Yb', 'Ytterbium', 173.04, 0, 6, 'lanthanide');
elements(70).density             = 6.90;
elements(70).electronConfig      = '[Xe] 4f14 6s2';
elements(70).electronegativity   = 1.10;
elements(70).atomicRadius        = 175;
elements(70).ionizationEnergy    = 6.2542;
elements(70).electronAffinity    = 0.02;
elements(70).meltingPoint        = 1097;
elements(70).boilingPoint        = 1469;
elements(70).thermalConductivity = 38.5;
elements(70).bCoherent           = 12.43;
elements(70).xrayEdges           = struct('K', 61332.3, 'L1', 10486.4, 'L2', 9978.2, 'L3', 8943.6);

elements(71) = makeElement(71, 'Lu', 'Lutetium', 174.97, 3, 6, 'lanthanide');
elements(71).density             = 9.841;
elements(71).electronConfig      = '[Xe] 4f14 5d1 6s2';
elements(71).electronegativity   = 1.27;
elements(71).atomicRadius        = 175;
elements(71).ionizationEnergy    = 5.4259;
elements(71).electronAffinity    = 0.34;
elements(71).meltingPoint        = 1925;
elements(71).boilingPoint        = 3675;
elements(71).thermalConductivity = 16.4;
elements(71).bCoherent           = 7.21;
elements(71).xrayEdges           = struct('K', 63313.8, 'L1', 10870.4, 'L2', 10348.6, 'L3', 9244.1);

elements(72) = makeElement(72, 'Hf', 'Hafnium', 178.49, 4, 6, 'transition metal');
elements(72).density             = 13.31;
elements(72).electronConfig      = '[Xe] 4f14 5d2 6s2';
elements(72).electronegativity   = 1.30;
elements(72).atomicRadius        = 167;
elements(72).ionizationEnergy    = 6.8251;
elements(72).electronAffinity    = 0;
elements(72).meltingPoint        = 2506;
elements(72).boilingPoint        = 4876;
elements(72).thermalConductivity = 23.0;
elements(72).bCoherent           = 7.77;
elements(72).xrayEdges           = struct('K', 65350.8, 'L1', 11270.7, 'L2', 10739.4, 'L3', 9560.7);

elements(73) = makeElement(73, 'Ta', 'Tantalum', 180.95, 5, 6, 'transition metal');
elements(73).density             = 16.69;
elements(73).electronConfig      = '[Xe] 4f14 5d3 6s2';
elements(73).electronegativity   = 1.50;
elements(73).atomicRadius        = 149;
elements(73).ionizationEnergy    = 7.5496;
elements(73).electronAffinity    = 0.3226;
elements(73).meltingPoint        = 3290;
elements(73).boilingPoint        = 5731;
elements(73).thermalConductivity = 57.5;
elements(73).bCoherent           = 6.91;
elements(73).xrayEdges           = struct('K', 67416.4, 'L1', 11681.5, 'L2', 11136.1, 'L3', 9881.1);

elements(74) = makeElement(74, 'W', 'Tungsten', 183.84, 6, 6, 'transition metal');
elements(74).density             = 19.25;
elements(74).electronConfig      = '[Xe] 4f14 5d4 6s2';
elements(74).electronegativity   = 2.36;
elements(74).atomicRadius        = 141;
elements(74).ionizationEnergy    = 7.8640;
elements(74).electronAffinity    = 0.81626;
elements(74).meltingPoint        = 3695;
elements(74).boilingPoint        = 6203;
elements(74).thermalConductivity = 173;
elements(74).bCoherent           = 4.86;
elements(74).xrayEdges           = struct('K', 69525.0, 'L1', 12099.8, 'L2', 11544.0, 'L3', 10206.8);

elements(75) = makeElement(75, 'Re', 'Rhenium', 186.21, 7, 6, 'transition metal');
elements(75).density             = 21.02;
elements(75).electronConfig      = '[Xe] 4f14 5d5 6s2';
elements(75).electronegativity   = 1.90;
elements(75).atomicRadius        = 137;
elements(75).ionizationEnergy    = 7.8335;
elements(75).electronAffinity    = 0.15;
elements(75).meltingPoint        = 3459;
elements(75).boilingPoint        = 5869;
elements(75).thermalConductivity = 48.0;
elements(75).bCoherent           = 9.2;
elements(75).xrayEdges           = struct('K', 71676.4, 'L1', 12526.7, 'L2', 11958.7, 'L3', 10535.3);

elements(76) = makeElement(76, 'Os', 'Osmium', 190.23, 8, 6, 'transition metal');
elements(76).density             = 22.59;
elements(76).electronConfig      = '[Xe] 4f14 5d6 6s2';
elements(76).electronegativity   = 2.20;
elements(76).atomicRadius        = 135;
elements(76).ionizationEnergy    = 8.4382;
elements(76).electronAffinity    = 1.0778;
elements(76).meltingPoint        = 3306;
elements(76).boilingPoint        = 5285;
elements(76).thermalConductivity = 87.6;
elements(76).bCoherent           = 10.7;
elements(76).xrayEdges           = struct('K', 73870.8, 'L1', 12968.0, 'L2', 12385.0, 'L3', 10870.9);

elements(77) = makeElement(77, 'Ir', 'Iridium', 192.22, 9, 6, 'transition metal');
elements(77).density             = 22.56;
elements(77).electronConfig      = '[Xe] 4f14 5d7 6s2';
elements(77).electronegativity   = 2.20;
elements(77).atomicRadius        = 136;
elements(77).ionizationEnergy    = 8.9670;
elements(77).electronAffinity    = 1.5638;
elements(77).meltingPoint        = 2719;
elements(77).boilingPoint        = 4701;
elements(77).thermalConductivity = 147;
elements(77).bCoherent           = 10.6;
elements(77).xrayEdges           = struct('K', 76111.0, 'L1', 13418.5, 'L2', 12824.1, 'L3', 11215.2);

elements(78) = makeElement(78, 'Pt', 'Platinum', 195.08, 10, 6, 'transition metal');
elements(78).density             = 21.45;
elements(78).electronConfig      = '[Xe] 4f14 5d9 6s1';
elements(78).electronegativity   = 2.28;
elements(78).atomicRadius        = 139;
elements(78).ionizationEnergy    = 8.9587;
elements(78).electronAffinity    = 2.1251;
elements(78).meltingPoint        = 2041.4;
elements(78).boilingPoint        = 4098;
elements(78).thermalConductivity = 71.6;
elements(78).bCoherent           = 9.60;
elements(78).xrayEdges           = struct('K', 78394.8, 'L1', 13879.9, 'L2', 13272.6, 'L3', 11563.7);

elements(79) = makeElement(79, 'Au', 'Gold', 196.97, 11, 6, 'transition metal');
elements(79).density             = 19.32;
elements(79).electronConfig      = '[Xe] 4f14 5d10 6s1';
elements(79).electronegativity   = 2.54;
elements(79).atomicRadius        = 144;
elements(79).ionizationEnergy    = 9.2255;
elements(79).electronAffinity    = 2.3086;
elements(79).meltingPoint        = 1337.33;
elements(79).boilingPoint        = 3129;
elements(79).thermalConductivity = 318;
elements(79).bCoherent           = 7.63;
elements(79).xrayEdges           = struct('K', 80724.9, 'L1', 14352.8, 'L2', 13733.6, 'L3', 11918.7);

elements(80) = makeElement(80, 'Hg', 'Mercury', 200.59, 12, 6, 'transition metal');
elements(80).density             = 13.534;
elements(80).electronConfig      = '[Xe] 4f14 5d10 6s2';
elements(80).electronegativity   = 2.00;
elements(80).atomicRadius        = 151;
elements(80).ionizationEnergy    = 10.4375;
elements(80).electronAffinity    = 0;
elements(80).meltingPoint        = 234.32;
elements(80).boilingPoint        = 629.88;
elements(80).thermalConductivity = 8.30;
elements(80).bCoherent           = 12.692;
elements(80).xrayEdges           = struct('K', 83102.3, 'L1', 14839.3, 'L2', 14208.7, 'L3', 12283.9);

elements(81) = makeElement(81, 'Tl', 'Thallium', 204.38, 13, 6, 'post-transition metal');
elements(81).density             = 11.85;
elements(81).electronConfig      = '[Xe] 4f14 5d10 6s2 6p1';
elements(81).electronegativity   = 1.62;
elements(81).atomicRadius        = 170;
elements(81).ionizationEnergy    = 6.1082;
elements(81).electronAffinity    = 0.3213;
elements(81).meltingPoint        = 577;
elements(81).boilingPoint        = 1746;
elements(81).thermalConductivity = 46.1;
elements(81).bCoherent           = 8.776;
elements(81).xrayEdges           = struct('K', 85530.4, 'L1', 15346.7, 'L2', 14697.9, 'L3', 12657.5);

elements(82) = makeElement(82, 'Pb', 'Lead', 207.2, 14, 6, 'post-transition metal');
elements(82).density             = 11.34;
elements(82).electronConfig      = '[Xe] 4f14 5d10 6s2 6p2';
elements(82).electronegativity   = 2.33;
elements(82).atomicRadius        = 175;
elements(82).ionizationEnergy    = 7.4167;
elements(82).electronAffinity    = 0.3644;
elements(82).meltingPoint        = 600.61;
elements(82).boilingPoint        = 2022;
elements(82).thermalConductivity = 35.3;
elements(82).bCoherent           = 9.405;
elements(82).xrayEdges           = struct('K', 88004.5, 'L1', 15860.8, 'L2', 15200.0, 'L3', 13035.2);

elements(83) = makeElement(83, 'Bi', 'Bismuth', 208.98, 15, 6, 'post-transition metal');
elements(83).density             = 9.807;
elements(83).electronConfig      = '[Xe] 4f14 5d10 6s2 6p3';
elements(83).electronegativity   = 2.02;
elements(83).atomicRadius        = 156;
elements(83).ionizationEnergy    = 7.2856;
elements(83).electronAffinity    = 0.9463;
elements(83).meltingPoint        = 544.55;
elements(83).boilingPoint        = 1837;
elements(83).thermalConductivity = 7.97;
elements(83).bCoherent           = 8.532;
elements(83).xrayEdges           = struct('K', 90525.9, 'L1', 16387.5, 'L2', 15711.1, 'L3', 13418.6);

elements(84) = makeElement(84, 'Po', 'Polonium', 209.0, 16, 6, 'post-transition metal');
elements(84).density             = 9.32;
elements(84).electronConfig      = '[Xe] 4f14 5d10 6s2 6p4';
elements(84).electronegativity   = 2.00;
elements(84).atomicRadius        = 167;
elements(84).ionizationEnergy    = 8.414;
elements(84).electronAffinity    = 1.9;
elements(84).meltingPoint        = 527;
elements(84).boilingPoint        = 1235;
elements(84).thermalConductivity = 20.0;
elements(84).bCoherent           = NaN;
elements(84).xrayEdges           = struct('K', 93104.9, 'L1', 16939.3, 'L2', 16244.3, 'L3', 13813.8);

elements(85) = makeElement(85, 'At', 'Astatine', 210.0, 17, 6, 'halogen');
elements(85).density             = 7.0;
elements(85).electronConfig      = '[Xe] 4f14 5d10 6s2 6p5';
elements(85).electronegativity   = 2.20;
elements(85).atomicRadius        = 150;
elements(85).ionizationEnergy    = 9.3;
elements(85).electronAffinity    = 2.8;
elements(85).meltingPoint        = 575;
elements(85).boilingPoint        = 610;
elements(85).thermalConductivity = NaN;
elements(85).bCoherent           = NaN;
elements(85).xrayEdges           = struct('K', 95729.9, 'L1', 17493.0, 'L2', 16784.7, 'L3', 14213.5);

elements(86) = makeElement(86, 'Rn', 'Radon', 222.0, 18, 6, 'noble gas');
elements(86).density             = 0.00973;
elements(86).electronConfig      = '[Xe] 4f14 5d10 6s2 6p6';
elements(86).electronegativity   = 2.20;
elements(86).atomicRadius        = 145;
elements(86).ionizationEnergy    = 10.7485;
elements(86).electronAffinity    = 0;
elements(86).meltingPoint        = 202;
elements(86).boilingPoint        = 211.5;
elements(86).thermalConductivity = 0.00364;
elements(86).bCoherent           = NaN;
elements(86).xrayEdges           = struct('K', 98404.0, 'L1', 18049.0, 'L2', 17337.1, 'L3', 14619.4);

% ── Period 7 ─────────────────────────────────────────────────────────
elements(87) = makeElement(87, 'Fr', 'Francium', 223.0, 1, 7, 'alkali metal');
elements(87).xrayEdges = struct('K', 101137.0, 'L1', 18639.0, 'L2', 17906.5, 'L3', 15031.2);

elements(88) = makeElement(88, 'Ra', 'Radium', 226.0, 2, 7, 'alkaline earth metal');
elements(88).density             = 5.0;
elements(88).xrayEdges = struct('K', 103921.9, 'L1', 19236.7, 'L2', 18484.3, 'L3', 15444.4);

% Actinides (Z 89-103, group 0, period 7)
elements(89) = makeElement(89, 'Ac', 'Actinium', 227.0, 0, 7, 'actinide');
elements(89).density             = 10.07;
elements(89).xrayEdges = struct('K', 106755.3, 'L1', 19840.0, 'L2', 19083.2, 'L3', 15871.0);

elements(90) = makeElement(90, 'Th', 'Thorium', 232.04, 0, 7, 'actinide');
elements(90).density             = 11.72;
elements(90).electronConfig      = '[Rn] 6d2 7s2';
elements(90).electronegativity   = 1.30;
elements(90).ionizationEnergy    = 6.3067;
elements(90).meltingPoint        = 2115;
elements(90).boilingPoint        = 5061;
elements(90).thermalConductivity = 54.0;
elements(90).bCoherent           = 10.31;
elements(90).xrayEdges = struct('K', 109650.9, 'L1', 20472.1, 'L2', 19693.2, 'L3', 16300.3);

elements(91) = makeElement(91, 'Pa', 'Protactinium', 231.04, 0, 7, 'actinide');
elements(91).density             = 15.37;
elements(91).xrayEdges = struct('K', 112601.4, 'L1', 21104.6, 'L2', 20313.7, 'L3', 16733.1);

elements(92) = makeElement(92, 'U', 'Uranium', 238.03, 0, 7, 'actinide');
elements(92).density             = 19.05;
elements(92).electronConfig      = '[Rn] 5f3 6d1 7s2';
elements(92).electronegativity   = 1.38;
elements(92).ionizationEnergy    = 6.1941;
elements(92).meltingPoint        = 1405.3;
elements(92).boilingPoint        = 4404;
elements(92).thermalConductivity = 27.5;
elements(92).bCoherent           = 8.417;
elements(92).xrayEdges = struct('K', 115606.1, 'L1', 21757.4, 'L2', 20947.6, 'L3', 17166.3);

elements(93) = makeElement(93, 'Np', 'Neptunium', 237.0, 0, 7, 'actinide');
elements(93).density             = 20.45;

elements(94) = makeElement(94, 'Pu', 'Plutonium', 244.0, 0, 7, 'actinide');
elements(94).density             = 19.84;

elements(95) = makeElement(95, 'Am', 'Americium', 243.0, 0, 7, 'actinide');
elements(95).density             = 12.0;

elements(96) = makeElement(96, 'Cm', 'Curium', 247.0, 0, 7, 'actinide');
elements(96).density             = 13.51;

elements(97) = makeElement(97, 'Bk', 'Berkelium', 247.0, 0, 7, 'actinide');
elements(97).density             = 14.79;

elements(98) = makeElement(98, 'Cf', 'Californium', 251.0, 0, 7, 'actinide');
elements(98).density             = 15.1;

elements(99) = makeElement(99, 'Es', 'Einsteinium', 252.0, 0, 7, 'actinide');

elements(100) = makeElement(100, 'Fm', 'Fermium', 257.0, 0, 7, 'actinide');

elements(101) = makeElement(101, 'Md', 'Mendelevium', 258.0, 0, 7, 'actinide');

elements(102) = makeElement(102, 'No', 'Nobelium', 259.0, 0, 7, 'actinide');

elements(103) = makeElement(103, 'Lr', 'Lawrencium', 262.0, 3, 7, 'actinide');

% Post-actinide transition metals (Z 104-112)
elements(104) = makeElement(104, 'Rf', 'Rutherfordium', 267.0, 4, 7, 'transition metal');
elements(105) = makeElement(105, 'Db', 'Dubnium', 268.0, 5, 7, 'transition metal');
elements(106) = makeElement(106, 'Sg', 'Seaborgium', 271.0, 6, 7, 'transition metal');
elements(107) = makeElement(107, 'Bh', 'Bohrium', 274.0, 7, 7, 'transition metal');
elements(108) = makeElement(108, 'Hs', 'Hassium', 277.0, 8, 7, 'transition metal');
elements(109) = makeElement(109, 'Mt', 'Meitnerium', 278.0, 9, 7, 'unknown');
elements(110) = makeElement(110, 'Ds', 'Darmstadtium', 281.0, 10, 7, 'unknown');
elements(111) = makeElement(111, 'Rg', 'Roentgenium', 282.0, 11, 7, 'unknown');
elements(112) = makeElement(112, 'Cn', 'Copernicium', 285.0, 12, 7, 'transition metal');

% Post-transition metals / metalloids / nonmetals (Z 113-118)
elements(113) = makeElement(113, 'Nh', 'Nihonium', 286.0, 13, 7, 'unknown');
elements(114) = makeElement(114, 'Fl', 'Flerovium', 289.0, 14, 7, 'unknown');
elements(115) = makeElement(115, 'Mc', 'Moscovium', 290.0, 15, 7, 'unknown');
elements(116) = makeElement(116, 'Lv', 'Livermorium', 293.0, 16, 7, 'unknown');
elements(117) = makeElement(117, 'Ts', 'Tennessine', 294.0, 17, 7, 'unknown');
elements(118) = makeElement(118, 'Og', 'Oganesson', 294.0, 18, 7, 'unknown');

end % buildTable

% ════════════════════════════════════════════════════════════════════
%  Local helper: create a default element struct with NaN/empty fields
% ════════════════════════════════════════════════════════════════════
function el = makeElement(Z, sym, name, mass, group, period, category)
%MAKEELEMENT  Create element struct with mandatory fields and NaN defaults.

el.Z                   = Z;
el.symbol              = sym;
el.name                = name;
el.mass                = mass;
el.group               = group;
el.period              = period;
el.category            = category;
el.density             = NaN;
el.electronConfig      = '';
el.electronegativity   = NaN;
el.atomicRadius        = NaN;
el.ionizationEnergy    = NaN;
el.electronAffinity    = NaN;
el.meltingPoint        = NaN;
el.boilingPoint        = NaN;
el.thermalConductivity = NaN;
el.bCoherent           = NaN;
el.xrayEdges           = struct('K', NaN, 'L1', NaN, 'L2', NaN, 'L3', NaN);

end % makeElement
