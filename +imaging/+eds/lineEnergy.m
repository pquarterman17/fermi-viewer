function [energy, lineUsed] = lineEnergy(symbol, options)
%LINEENERGY  Principal characteristic X-ray line energy for an element (keV).
%
%   energy = imaging.eds.lineEnergy(symbol) returns the energy in keV of the
%   strongest readily-excited characteristic line for the element SYMBOL
%   (e.g. 'Cu', 'Fe', 'O'), auto-selecting the family (K, L or M) that falls
%   in the usual EDS range.
%
%   energy = imaging.eds.lineEnergy(symbol, Line=L) forces a family,
%   L in {'K','L','M','auto'} (default 'auto').
%
%   energy = imaging.eds.lineEnergy(symbol, BeamKV=hv) prefers the highest-Z
%   family whose line is comfortably excited at accelerating voltage hv
%   (a line is "excitable" when its energy < ~hv; default Inf = no limit).
%
%   [energy, lineUsed] = imaging.eds.lineEnergy(...) also returns the family
%   actually used ('K'/'L'/'M'), or '' if the element/line is unknown
%   (energy is then NaN).
%
%   Values are principal-line energies (K = Kα1, L = Lα1, M = Mα1) in keV,
%   rounded to the published precision. Source: Bearden, "X-Ray Wavelengths",
%   Rev. Mod. Phys. 39, 78 (1967), cross-checked against the NIST X-ray
%   Transition Energies database. These match EDS peak positions to well
%   within a typical 10–20 eV/channel calibration.
%
%   Example
%   ───────
%     e = imaging.eds.lineEnergy('Fe')              % 6.404  (Kα)
%     e = imaging.eds.lineEnergy('Au', Line='M')    % 2.123  (Mα)
%     e = imaging.eds.lineEnergy('W',  BeamKV=15)   % 1.775  (Mα; Lα at 8.4 keV)
%
%   See also IMAGING.EDS.ELEMENTMAP, IMAGING.EDS.EXTRACTELEMENTMAPS

    arguments
        symbol  (1,1) string
        options.Line   (1,1) string = "auto"
        options.BeamKV (1,1) double = Inf
    end

    [K, L, M] = lineTables();
    sym = char(strtrim(symbol));
    energy = NaN; lineUsed = '';
    if isempty(sym), return; end

    kE = lookup(K, sym);
    lE = lookup(L, sym);
    mE = lookup(M, sym);

    switch upper(char(options.Line))
        case 'K', energy = kE; lineUsed = pick('K', kE);
        case 'L', energy = lE; lineUsed = pick('L', lE);
        case 'M', energy = mE; lineUsed = pick('M', mE);
        otherwise
            % auto: pick by overvoltage U = hv / Ec, where Ec is the
            % absorption edge approximated from the line energy via a
            % per-family factor (Kα≈0.90·Ec_K, Lα≈0.80·Ec_L, Mα≈0.93·Ec_M).
            % Prefer K>L>M among families with U ≥ UMIN (adequately excited);
            % if none qualify, take the family with the largest U. This makes
            % e.g. W and Au resolve to Mα at 15 kV but Lα at 300 kV.
            UMIN = 1.5;
            hv   = options.BeamKV;
            edgeK = kE / 0.90;
            edgeL = lE / 0.80;
            edgeM = mE / 0.93;
            cand = {'K', kE, edgeK; 'L', lE, edgeL; 'M', mE, edgeM};
            bestU = -Inf; bestI = 0;
            for i = 1:size(cand,1)
                e = cand{i,2};
                if isnan(e), continue; end
                U = hv / cand{i,3};
                if U >= UMIN
                    energy = e; lineUsed = cand{i,1};   % K>L>M order: first wins
                    return;
                end
                if U > bestU, bestU = U; bestI = i; end
            end
            if bestI > 0
                energy = cand{bestI,2}; lineUsed = cand{bestI,1};
            end
    end
end


function f = pick(name, e)
    if isnan(e), f = ''; else, f = name; end
end


function e = lookup(map, sym)
    if isKey(map, sym), e = map(sym); else, e = NaN; end
end


function [K, L, M] = lineTables()
%LINETABLES  keV energies of principal lines (Kα1 / Lα1 / Mα1).
%   Persistent so the maps build only once per session.
    persistent Kp Lp Mp
    if ~isempty(Kp)
        K = Kp; L = Lp; M = Mp; return;
    end

    % --- Kα1 (keV) ---
    ksym = {'Be','B','C','N','O','F','Ne','Na','Mg','Al','Si','P','S','Cl', ...
            'Ar','K','Ca','Sc','Ti','V','Cr','Mn','Fe','Co','Ni','Cu','Zn', ...
            'Ga','Ge','As','Se','Br','Rb','Sr','Y','Zr','Nb','Mo','Ru','Rh', ...
            'Pd','Ag','Cd','In','Sn'};
    kval = [0.108,0.183,0.277,0.392,0.525,0.677,0.849,1.041,1.254,1.487, ...
            1.740,2.013,2.307,2.622,2.957,3.314,3.692,4.091,4.511,4.952, ...
            5.415,5.899,6.404,6.930,7.478,8.048,8.639,9.252,9.886,10.544, ...
            11.222,11.924,13.395,14.165,14.958,15.775,16.615,17.479,19.279,20.216, ...
            21.177,22.163,23.174,24.210,25.271];

    % --- Lα1 (keV) ---
    lsym = {'Ca','Ti','V','Cr','Mn','Fe','Co','Ni','Cu','Zn','Ga','Ge','As', ...
            'Zr','Nb','Mo','Ru','Rh','Pd','Ag','Cd','In','Sn','Sb','Ba','La', ...
            'Ce','Nd','Sm','Gd','Dy','Er','Yb','Hf','Ta','W','Re','Os','Ir', ...
            'Pt','Au','Hg','Tl','Pb','Bi','Th','U'};
    lval = [0.341,0.452,0.511,0.573,0.637,0.705,0.776,0.851,0.930,1.012, ...
            1.098,1.188,1.282,2.042,2.166,2.293,2.559,2.697,2.839,2.984, ...
            3.133,3.287,3.444,3.605,4.466,4.651,4.840,5.230,5.636,6.057, ...
            6.495,6.949,7.416,7.899,8.146,8.398,8.652,8.911,9.175,9.442, ...
            9.713,9.989,10.269,10.551,10.839,12.968,13.615];

    % --- Mα1 (keV) ---
    msym = {'Hf','Ta','W','Re','Os','Ir','Pt','Au','Hg','Tl','Pb','Bi', ...
            'Th','U'};
    mval = [1.645,1.710,1.775,1.843,1.910,1.980,2.051,2.123,2.196,2.271, ...
            2.342,2.420,2.996,3.171];

    Kp = containers.Map(ksym, num2cell(kval));
    Lp = containers.Map(lsym, num2cell(lval));
    Mp = containers.Map(msym, num2cell(mval));
    K = Kp; L = Lp; M = Mp;
end
