function result = dSpacing(a, h, k, l, opts)
%DSPACING  Compute the interplanar d-spacing for a given (hkl) reflection.
%
%   Syntax
%   ------
%   result = calc.crystal.dSpacing(a, h, k, l)
%   result = calc.crystal.dSpacing(a, h, k, l, b=b, c=c, alpha=alpha, beta=beta, gamma=gamma)
%
%   Inputs
%   ------
%   a      — lattice parameter a (Angstroms)
%   h,k,l  — Miller indices (integers)
%   b      — lattice parameter b (Ang); default = a  (tetragonal/cubic)
%   c      — lattice parameter c (Ang); default = a  (cubic)
%   alpha  — angle between b and c (degrees); default = 90
%   beta   — angle between a and c (degrees); default = 90
%   gamma  — angle between a and b (degrees); default = 90
%
%   Outputs
%   -------
%   result — struct with fields:
%     .d       — d-spacing (Angstroms)
%     .system  — inferred crystal system string
%     .latex   — LaTeX-formatted result string
%
%   Examples
%   --------
%   r = calc.crystal.dSpacing(3.905, 1, 0, 0);       % cubic (STO a-axis)
%   r = calc.crystal.dSpacing(3.905, 0, 0, 1, c=3.95); % tetragonal
%   r = calc.crystal.dSpacing(5.0, 1, 1, 1);          % cubic fcc-like

% ════════════════════════════════════════════════════════════════════

arguments
    a     (1,1) double {mustBePositive}
    h     (1,1) double
    k     (1,1) double
    l     (1,1) double
    opts.b     (1,1) double {mustBePositive} = a
    opts.c     (1,1) double {mustBePositive} = a
    opts.alpha (1,1) double = 90
    opts.beta  (1,1) double = 90
    opts.gamma (1,1) double = 90
end

b = opts.b;
c = opts.c;
al = deg2rad(opts.alpha);
be = deg2rad(opts.beta);
ga = deg2rad(opts.gamma);

% Infer crystal system from supplied parameters
[system, b, c] = inferSystem(a, b, c, opts.alpha, opts.beta, opts.gamma);

% Compute volume for triclinic formula
V = a*b*c * sqrt(1 - cos(al)^2 - cos(be)^2 - cos(ga)^2 ...
    + 2*cos(al)*cos(be)*cos(ga));

% General triclinic reciprocal metric tensor (1/d^2)
invD2 = (  h^2 * b^2 * c^2 * sin(al)^2 ...
         + k^2 * a^2 * c^2 * sin(be)^2 ...
         + l^2 * a^2 * b^2 * sin(ga)^2 ...
         + 2*h*k * a*b*c^2 * (cos(al)*cos(be) - cos(ga)) ...
         + 2*k*l * a^2*b*c * (cos(be)*cos(ga) - cos(al)) ...
         + 2*h*l * a*b^2*c * (cos(al)*cos(ga) - cos(be)) ) / V^2;

d = 1 / sqrt(invD2);

result.d      = d;
result.system = system;
result.latex  = sprintf('$d_{%d%d%d} = %.4g\\,\\text{\\AA}$', h, k, l, d);
end

% ════════════════════════════════════════════════════════════════════

function [sys, b, c] = inferSystem(a, b, c, alpha, beta, gamma)
    isRightAngles = (alpha == 90) && (beta == 90) && (gamma == 90);
    bIsA = (b == a);
    cIsA = (c == a);
    if isRightAngles && bIsA && cIsA
        sys = 'cubic';
    elseif isRightAngles && bIsA && ~cIsA
        sys = 'tetragonal';
    elseif (alpha == 90) && (beta == 90) && (gamma == 120) && bIsA
        sys = 'hexagonal';
    elseif isRightAngles
        sys = 'orthorhombic';
    else
        sys = 'triclinic';
    end
end
