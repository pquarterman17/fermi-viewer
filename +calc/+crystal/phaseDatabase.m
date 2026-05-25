function db = phaseDatabase()
%PHASEDATABASE  Built-in XRD reference phase database for peak matching.
%
%   Syntax
%   ------
%   db = calc.crystal.phaseDatabase()
%
%   Output
%   ------
%   db — struct array with fields:
%     .name       — phase name (e.g. 'Si')
%     .formula    — chemical formula
%     .a          — lattice parameter a (Å)
%     .b          — lattice parameter b (Å)
%     .c          — lattice parameter c (Å)
%     .alpha      — angle alpha (deg)
%     .beta       — angle beta (deg)
%     .gamma      — angle gamma (deg)
%     .centering  — Bravais centering ('P','F','I','C','R')
%     .system     — crystal system
%     .category   — material category ('substrate','metal','oxide','semiconductor','perovskite','other')
%     .icsd       — ICSD reference number (0 = not specified)
%     .basis      — N×4 cell {symbol, x, y, z} of atomic positions in the
%                   conventional unit cell (fractional coords). Empty {} when
%                   the basis is not yet tabulated — downstream code
%                   (simulateDiffraction) then falls back to multiplicity-only
%                   intensity modelling.
%
%   The database covers ~50 common thin-film and substrate materials
%   frequently encountered in materials science XRD measurements.
%
%   Structure-type helpers at the bottom of this file (fccBasis, bccBasis,
%   diamondBasis, zincblendeBasis, rocksaltBasis, perovskiteBasis,
%   fluoriteBasis) produce the conventional-cell basis for the common cubic
%   space groups; centering-based systematic absences emerge naturally from
%   |F_hkl|² = |Σ_j f_j·exp(2πi·(h·x_j+k·y_j+l·z_j))|² when the full basis is
%   listed, so the centering field and the basis are redundant-but-consistent.
%
%   Examples
%   --------
%   db = calc.crystal.phaseDatabase();
%   fprintf('Database contains %d phases\n', numel(db));
%   % Find all oxides:
%   oxides = db(strcmp({db.category}, 'oxide'));
%   % Count phases with tabulated bases:
%   nBasis = sum(arrayfun(@(p) ~isempty(p.basis), db));

% ════════════════════════════════════════════════════════════════════

db = struct('name',{},'formula',{},'a',{},'b',{},'c',{}, ...
            'alpha',{},'beta',{},'gamma',{}, ...
            'centering',{},'system',{},'category',{},'icsd',{}, ...
            'basis',{});

% Helper to append entries — `basis` is optional (default: empty cell).
    function db = add(db, name, formula, a, b, c, al, be, ga, cent, sys, cat, icsd, basis)
        if nargin < 14
            basis = {};
        end
        entry.name      = name;
        entry.formula   = formula;
        entry.a         = a;
        entry.b         = b;
        entry.c         = c;
        entry.alpha     = al;
        entry.beta      = be;
        entry.gamma     = ga;
        entry.centering = cent;
        entry.system    = sys;
        entry.category  = cat;
        entry.icsd      = icsd;
        entry.basis     = basis;
        db(end+1) = entry;
    end

% ── Substrates ─────────────────────────────────────────────────────
%                        name                formula          a        b        c      al   be   ga   cent  system          category      ICSD   basis
db = add(db, 'Silicon',                     'Si',          5.4309,  5.4309,  5.4309,  90,  90,  90,  'F', 'cubic',        'substrate',  51688, diamondBasis('Si'));
db = add(db, 'Sapphire (Al2O3)',            'Al2O3',       4.7589,  4.7589, 12.9910,  90,  90, 120,  'R', 'hexagonal',    'substrate',  10425);
db = add(db, 'SrTiO3',                     'SrTiO3',      3.9050,  3.9050,  3.9050,  90,  90,  90,  'P', 'cubic',        'substrate',  80871, perovskiteBasis('Sr','Ti','O'));
db = add(db, 'MgO',                        'MgO',         4.2112,  4.2112,  4.2112,  90,  90,  90,  'F', 'cubic',        'substrate',  52026, rocksaltBasis('Mg','O'));
db = add(db, 'LaAlO3',                     'LaAlO3',      3.7900,  3.7900,  3.7900,  90,  90,  90,  'P', 'cubic',        'substrate',  56941, perovskiteBasis('La','Al','O'));
db = add(db, 'GaAs',                       'GaAs',        5.6533,  5.6533,  5.6533,  90,  90,  90,  'F', 'cubic',        'substrate',  41674, zincblendeBasis('Ga','As'));
db = add(db, 'Ge',                         'Ge',          5.6576,  5.6576,  5.6576,  90,  90,  90,  'F', 'cubic',        'substrate',  41980, diamondBasis('Ge'));
db = add(db, 'GaN (wurtzite)',             'GaN',         3.1890,  3.1890,  5.1864,  90,  90, 120,  'P', 'hexagonal',    'substrate',  67782, wurtziteBasis('Ga','N',0.376));
db = add(db, 'TiO2 rutile',               'TiO2',        4.5941,  4.5941,  2.9589,  90,  90,  90,  'P', 'tetragonal',   'substrate',  44882, rutileBasis('Ti','O',0.3051));
db = add(db, 'SiC 4H',                    'SiC',         3.0730,  3.0730, 10.0530,  90,  90, 120,  'P', 'hexagonal',    'substrate',      0);

% ── Metals ─────────────────────────────────────────────────────────
db = add(db, 'Aluminum',                   'Al',          4.0495,  4.0495,  4.0495,  90,  90,  90,  'F', 'cubic',        'metal',      64700, fccBasis('Al'));
db = add(db, 'Copper',                     'Cu',          3.6149,  3.6149,  3.6149,  90,  90,  90,  'F', 'cubic',        'metal',      43493, fccBasis('Cu'));
db = add(db, 'Gold',                       'Au',          4.0782,  4.0782,  4.0782,  90,  90,  90,  'F', 'cubic',        'metal',      44362, fccBasis('Au'));
db = add(db, 'Silver',                     'Ag',          4.0862,  4.0862,  4.0862,  90,  90,  90,  'F', 'cubic',        'metal',      64706, fccBasis('Ag'));
db = add(db, 'Platinum',                   'Pt',          3.9231,  3.9231,  3.9231,  90,  90,  90,  'F', 'cubic',        'metal',      64923, fccBasis('Pt'));
db = add(db, 'Palladium',                  'Pd',          3.8898,  3.8898,  3.8898,  90,  90,  90,  'F', 'cubic',        'metal',      64918, fccBasis('Pd'));
db = add(db, 'Nickel',                     'Ni',          3.5238,  3.5238,  3.5238,  90,  90,  90,  'F', 'cubic',        'metal',      64989, fccBasis('Ni'));
db = add(db, 'Iron (BCC)',                 'Fe',          2.8665,  2.8665,  2.8665,  90,  90,  90,  'I', 'cubic',        'metal',      64795, bccBasis('Fe'));
db = add(db, 'Iron (FCC)',                 'Fe',          3.5910,  3.5910,  3.5910,  90,  90,  90,  'F', 'cubic',        'metal',      44863, fccBasis('Fe'));
db = add(db, 'Tungsten',                   'W',           3.1648,  3.1648,  3.1648,  90,  90,  90,  'I', 'cubic',        'metal',      43421, bccBasis('W'));
db = add(db, 'Chromium',                   'Cr',          2.8839,  2.8839,  2.8839,  90,  90,  90,  'I', 'cubic',        'metal',      64711, bccBasis('Cr'));
db = add(db, 'Titanium (HCP)',             'Ti',          2.9505,  2.9505,  4.6826,  90,  90, 120,  'P', 'hexagonal',    'metal',      44872, hcpBasis('Ti'));
db = add(db, 'Cobalt (HCP)',              'Co',          2.5071,  2.5071,  4.0695,  90,  90, 120,  'P', 'hexagonal',    'metal',      44989, hcpBasis('Co'));
db = add(db, 'Molybdenum',                'Mo',          3.1472,  3.1472,  3.1472,  90,  90,  90,  'I', 'cubic',        'metal',      64915, bccBasis('Mo'));
db = add(db, 'Tantalum (BCC)',             'Ta',          3.3013,  3.3013,  3.3013,  90,  90,  90,  'I', 'cubic',        'metal',      64946, bccBasis('Ta'));

% ── Simple Oxides ──────────────────────────────────────────────────
db = add(db, 'ZnO (wurtzite)',             'ZnO',         3.2498,  3.2498,  5.2066,  90,  90, 120,  'P', 'hexagonal',    'oxide',      67849, wurtziteBasis('Zn','O',0.3826));
db = add(db, 'Fe2O3 (hematite)',           'Fe2O3',       5.0356,  5.0356, 13.7489,  90,  90, 120,  'R', 'hexagonal',    'oxide',      82137);
db = add(db, 'Fe3O4 (magnetite)',          'Fe3O4',       8.3941,  8.3941,  8.3941,  90,  90,  90,  'F', 'cubic',        'oxide',      26410);
db = add(db, 'NiO',                        'NiO',         4.1771,  4.1771,  4.1771,  90,  90,  90,  'F', 'cubic',        'oxide',      24018, rocksaltBasis('Ni','O'));
db = add(db, 'CoO',                        'CoO',         4.2612,  4.2612,  4.2612,  90,  90,  90,  'F', 'cubic',        'oxide',      24019, rocksaltBasis('Co','O'));
db = add(db, 'CuO (tenorite)',             'CuO',         4.6837,  3.4226,  5.1288,  90, 99.54, 90, 'C', 'monoclinic',  'oxide',      16025);
db = add(db, 'Cu2O (cuprite)',             'Cu2O',        4.2696,  4.2696,  4.2696,  90,  90,  90,  'P', 'cubic',        'oxide',      63281, cupriteBasis());
db = add(db, 'TiO2 (anatase)',             'TiO2',        3.7852,  3.7852,  9.5139,  90,  90,  90,  'I', 'tetragonal',   'oxide',      44882);
db = add(db, 'SiO2 (quartz)',              'SiO2',        4.9134,  4.9134,  5.4052,  90,  90, 120,  'P', 'hexagonal',    'oxide',      16331);
db = add(db, 'SnO2 (cassiterite)',         'SnO2',        4.7382,  4.7382,  3.1871,  90,  90,  90,  'P', 'tetragonal',   'oxide',      39173, rutileBasis('Sn','O',0.3056));
db = add(db, 'In2O3 (bixbyite)',           'In2O3',      10.1170, 10.1170, 10.1170,  90,  90,  90,  'I', 'cubic',        'oxide',      14388);
db = add(db, 'Cr2O3 (eskolaite)',          'Cr2O3',       4.9570,  4.9570, 13.5920,  90,  90, 120,  'R', 'hexagonal',    'oxide',      25781);

% ── Perovskites ────────────────────────────────────────────────────
db = add(db, 'BaTiO3',                    'BaTiO3',      3.9945,  3.9945,  4.0335,  90,  90,  90,  'P', 'tetragonal',   'perovskite', 67520, perovskiteBasis('Ba','Ti','O'));
db = add(db, 'PbTiO3',                    'PbTiO3',      3.8990,  3.8990,  4.1530,  90,  90,  90,  'P', 'tetragonal',   'perovskite',     0, perovskiteBasis('Pb','Ti','O'));
db = add(db, 'La0.7Sr0.3MnO3',            'LSMO',        3.8760,  3.8760,  3.8760,  90,  90,  90,  'P', 'cubic',        'perovskite',     0, perovskiteBasis('La','Mn','O'));
db = add(db, 'BiFeO3',                    'BiFeO3',      5.5876,  5.5876, 13.8670,  90,  90, 120,  'R', 'hexagonal',    'perovskite', 15299);
db = add(db, 'LaNiO3',                    'LaNiO3',      3.8380,  3.8380,  3.8380,  90,  90,  90,  'P', 'cubic',        'perovskite',     0, perovskiteBasis('La','Ni','O'));
db = add(db, 'SrRuO3',                    'SrRuO3',      5.5670,  5.5304,  7.8446,  90,  90,  90,  'P', 'orthorhombic', 'perovskite',     0);

% ── Semiconductors ─────────────────────────────────────────────────
db = add(db, 'InAs',                       'InAs',        6.0583,  6.0583,  6.0583,  90,  90,  90,  'F', 'cubic',        'semiconductor',43479, zincblendeBasis('In','As'));
db = add(db, 'InP',                        'InP',         5.8688,  5.8688,  5.8688,  90,  90,  90,  'F', 'cubic',        'semiconductor',41432, zincblendeBasis('In','P'));
db = add(db, 'CdTe',                       'CdTe',        6.4810,  6.4810,  6.4810,  90,  90,  90,  'F', 'cubic',        'semiconductor',    0, zincblendeBasis('Cd','Te'));
db = add(db, 'ZnSe',                       'ZnSe',        5.6676,  5.6676,  5.6676,  90,  90,  90,  'F', 'cubic',        'semiconductor',    0, zincblendeBasis('Zn','Se'));
db = add(db, 'AlN (wurtzite)',             'AlN',         3.1114,  3.1114,  4.9792,  90,  90, 120,  'P', 'hexagonal',    'semiconductor',    0, wurtziteBasis('Al','N',0.3821));

% ── Other common phases ────────────────────────────────────────────
db = add(db, 'LaB6 (standard)',            'LaB6',        4.1569,  4.1569,  4.1569,  90,  90,  90,  'P', 'cubic',        'other',      30450, laB6Basis());
db = add(db, 'CaF2 (fluorite)',            'CaF2',        5.4626,  5.4626,  5.4626,  90,  90,  90,  'F', 'cubic',        'other',      41413, fluoriteBasis('Ca','F'));
db = add(db, 'NaCl (halite)',              'NaCl',        5.6402,  5.6402,  5.6402,  90,  90,  90,  'F', 'cubic',        'other',      18189, rocksaltBasis('Na','Cl'));
db = add(db, 'BN (hexagonal)',             'BN',          2.5040,  2.5040,  6.6612,  90,  90, 120,  'P', 'hexagonal',    'other',          0);

end

% ════════════════════════════════════════════════════════════════════
%  Structure-type basis helpers — conventional unit cell, fractional coords
% ════════════════════════════════════════════════════════════════════

function basis = fccBasis(sym)
%FCCBASIS  Four atoms per conventional FCC cell (Fm-3m, space group 225).
    basis = { ...
        sym, 0.0, 0.0, 0.0; ...
        sym, 0.5, 0.5, 0.0; ...
        sym, 0.5, 0.0, 0.5; ...
        sym, 0.0, 0.5, 0.5};
end

function basis = bccBasis(sym)
%BCCBASIS  Two atoms per conventional BCC cell (Im-3m, space group 229).
    basis = { ...
        sym, 0.0, 0.0, 0.0; ...
        sym, 0.5, 0.5, 0.5};
end

function basis = diamondBasis(sym)
%DIAMONDBASIS  Eight atoms per conventional diamond cell (Fd-3m, space group 227).
%  FCC sublattice + FCC shifted by (1/4,1/4,1/4); correctly produces the
%  diamond-glide extinction (e.g. (200) forbidden in Si).
    basis = [fccBasis(sym); ...
        {sym, 0.25, 0.25, 0.25; ...
         sym, 0.75, 0.75, 0.25; ...
         sym, 0.75, 0.25, 0.75; ...
         sym, 0.25, 0.75, 0.75}];
end

function basis = zincblendeBasis(A, B)
%ZINCBLENDEBASIS  Two species on diamond sites (F-43m, space group 216).
%  A on the FCC sublattice, B on the shifted sublattice.
    basis = [fccBasis(A); ...
        {B, 0.25, 0.25, 0.25; ...
         B, 0.75, 0.75, 0.25; ...
         B, 0.75, 0.25, 0.75; ...
         B, 0.25, 0.75, 0.75}];
end

function basis = rocksaltBasis(cation, anion)
%ROCKSALTBASIS  NaCl structure (Fm-3m, space group 225): cation on FCC,
%  anion displaced by (1/2,0,0).
    basis = [fccBasis(cation); ...
        {anion, 0.5, 0.0, 0.0; ...
         anion, 0.0, 0.5, 0.0; ...
         anion, 0.0, 0.0, 0.5; ...
         anion, 0.5, 0.5, 0.5}];
end

function basis = perovskiteBasis(A, B, X)
%PEROVSKITEBASIS  Cubic ABX3 perovskite (Pm-3m, space group 221).
%  A at cell corner, B at body centre, X on the three face centres
%  (octahedral cage around B).
    basis = { ...
        A, 0.0, 0.0, 0.0; ...
        B, 0.5, 0.5, 0.5; ...
        X, 0.5, 0.5, 0.0; ...
        X, 0.5, 0.0, 0.5; ...
        X, 0.0, 0.5, 0.5};
end

function basis = fluoriteBasis(cation, anion)
%FLUORITEBASIS  CaF2 (Fm-3m, space group 225): cation on FCC, anion at the
%  eight tetrahedral sites (1/4,1/4,1/4) and equivalents.
    basis = [fccBasis(cation); ...
        {anion, 0.25, 0.25, 0.25; ...
         anion, 0.75, 0.75, 0.25; ...
         anion, 0.75, 0.25, 0.75; ...
         anion, 0.25, 0.75, 0.75; ...
         anion, 0.25, 0.25, 0.75; ...
         anion, 0.75, 0.75, 0.75; ...
         anion, 0.75, 0.25, 0.25; ...
         anion, 0.25, 0.75, 0.25}];
end

function basis = hcpBasis(sym)
%HCPBASIS  Hexagonal close-packed (P63/mmc, space group 194), two atoms at
%  (0,0,0) and (1/3,2/3,1/2) using the standard a-a-c conventional cell.
    basis = { ...
        sym, 0.0,    0.0,    0.0; ...
        sym, 1/3,    2/3,    0.5};
end

function basis = wurtziteBasis(A, B, u)
%WURTZITEBASIS  Wurtzite (P6_3mc, space group 186). Two A-B pairs; the u
%  parameter fixes the anion z-offset (ideal 3/8 ≈ 0.375; material-specific
%  values are provided per entry).
    basis = { ...
        A, 1/3, 2/3, 0.0;       ...
        A, 2/3, 1/3, 0.5;       ...
        B, 1/3, 2/3, u;         ...
        B, 2/3, 1/3, 0.5 + u};
end

function basis = rutileBasis(cation, anion, u)
%RUTILEBASIS  Rutile structure (P4_2/mnm, space group 136), two formula
%  units per cell; u is the internal oxygen parameter (0.3051 for TiO2).
    basis = { ...
        cation, 0.0,      0.0,      0.0; ...
        cation, 0.5,      0.5,      0.5; ...
        anion,  u,        u,        0.0; ...
        anion,  -u+1,     -u+1,     0.0; ...
        anion,  0.5+u,    0.5-u,    0.5; ...
        anion,  0.5-u,    0.5+u,    0.5};
end

function basis = cupriteBasis()
%CUPRITEBASIS  Cu2O (Pn-3m, space group 224). Two O atoms on BCC sites,
%  four Cu atoms at tetrahedral positions.
    basis = { ...
        'O',  0.0,  0.0,  0.0; ...
        'O',  0.5,  0.5,  0.5; ...
        'Cu', 0.25, 0.25, 0.25; ...
        'Cu', 0.75, 0.75, 0.25; ...
        'Cu', 0.75, 0.25, 0.75; ...
        'Cu', 0.25, 0.75, 0.75};
end

function basis = laB6Basis()
%LAB6BASIS  LaB6 (Pm-3m, space group 221): La at corner, B6 octahedron
%  around cell centre. Standard boron parameter x ≈ 0.1993.
    x = 0.1993;
    basis = { ...
        'La', 0.0,     0.0,     0.0;     ...
        'B',  0.5 + x, 0.5,     0.5;     ...
        'B',  0.5 - x, 0.5,     0.5;     ...
        'B',  0.5,     0.5 + x, 0.5;     ...
        'B',  0.5,     0.5 - x, 0.5;     ...
        'B',  0.5,     0.5,     0.5 + x; ...
        'B',  0.5,     0.5,     0.5 - x};
end
