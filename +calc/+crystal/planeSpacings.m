function result = planeSpacings(a, opts)
%PLANESPACINGS  Enumerate allowed (hkl) reflections with d-spacings and 2theta.
%
%   Syntax
%   ------
%   result = calc.crystal.planeSpacings(a)
%   result = calc.crystal.planeSpacings(a, Centering='F', MaxHKL=5, Lambda=1.5406)
%
%   Inputs
%   ------
%   a          — lattice parameter a (Angstroms)
%   b          — lattice parameter b (Ang); default = a
%   c          — lattice parameter c (Ang); default = a
%   alpha      — angle between b and c (degrees); default = 90
%   beta       — angle between a and c (degrees); default = 90
%   gamma      — angle between a and b (degrees); default = 90
%   MaxHKL     — maximum |h|, |k|, |l| to enumerate (default 5)
%   Lambda     — X-ray wavelength in Angstroms (default 1.5406 Cu Ka)
%   Centering  — Bravais centering: 'P','F','I','A','B','C','R' (default 'P')
%   MinD       — minimum d-spacing to include (Ang, default 0)
%
%   Outputs
%   -------
%   result — struct with fields:
%     .hkl           — [N x 3] Miller indices (lowest lexicographic per unique d)
%     .d             — [N x 1] d-spacings (Ang), descending
%     .twoTheta      — [N x 1] 2theta values (deg); NaN if Lambda is NaN
%     .multiplicity  — [N x 1] number of symmetry-equivalent planes
%     .centering     — char, centering used
%     .system        — char, inferred crystal system
%     .lambda        — wavelength used (Ang)
%     .nReflections  — scalar, number of unique reflections
%
%   Examples
%   --------
%   % FCC Silicon — (100) absent, (111) present
%   r = calc.crystal.planeSpacings(5.431, Centering='F');
%   % BCC Iron — (100) absent, (110) present
%   r = calc.crystal.planeSpacings(2.867, Centering='I');
%   % Hexagonal sapphire
%   r = calc.crystal.planeSpacings(4.758, c=12.991, gamma=120, Centering='P');

% ════════════════════════════════════════════════════════════════════

arguments
    a     (1,1) double {mustBePositive}
    opts.b         (1,1) double {mustBePositive} = a
    opts.c         (1,1) double {mustBePositive} = a
    opts.alpha     (1,1) double = 90
    opts.beta      (1,1) double = 90
    opts.gamma     (1,1) double = 90
    opts.MaxHKL    (1,1) double {mustBePositive, mustBeInteger} = 5
    opts.Lambda    (1,1) double = 1.5406
    opts.Centering (1,:) char   = 'P'
    opts.MinD      (1,1) double = 0
end

maxH = opts.MaxHKL;
centering = upper(opts.Centering);

% ════════════════════════════════════════════════════════════════════
% Enumerate all (hkl) combinations, skipping (000)
% ════════════════════════════════════════════════════════════════════

hRange = -maxH:maxH;
nRange = numel(hRange);
nTotal = nRange^3 - 1;  % exclude (0,0,0)

hklAll = zeros(nTotal, 3);
dAll   = zeros(nTotal, 1);
idx = 0;

for ih = 1:nRange
    for ik = 1:nRange
        for il = 1:nRange
            hh = hRange(ih);
            kk = hRange(ik);
            ll = hRange(il);
            if hh == 0 && kk == 0 && ll == 0, continue; end

            % Systematic absence check
            if ~isAllowed(hh, kk, ll, centering), continue; end

            % Compute d-spacing
            r = calc.crystal.dSpacing(a, hh, kk, ll, ...
                b=opts.b, c=opts.c, ...
                alpha=opts.alpha, beta=opts.beta, gamma=opts.gamma);

            if r.d < opts.MinD, continue; end

            idx = idx + 1;
            hklAll(idx,:) = [hh, kk, ll];
            dAll(idx)     = r.d;
        end
    end
end

hklAll = hklAll(1:idx,:);
dAll   = dAll(1:idx);

% ════════════════════════════════════════════════════════════════════
% Group by unique d-spacing and pick canonical representative
% ════════════════════════════════════════════════════════════════════

% Round d to avoid floating-point splitting of equivalent planes
dRound = round(dAll, 8);
[uniqueD, ~, groupIdx] = unique(dRound, 'stable');
nGroups = numel(uniqueD);

hklOut  = zeros(nGroups, 3);
dOut    = zeros(nGroups, 1);
multOut = zeros(nGroups, 1);

for gi = 1:nGroups
    members = find(groupIdx == gi);
    multOut(gi) = numel(members);
    dOut(gi)    = mean(dAll(members));

    % Pick canonical representative: prefer all-nonneg indices, then
    % fewest negatives, then largest sum, then lexicographic on abs values.
    memberHKL = hklAll(members,:);
    % Filter to positive-first entries (h>0, or h==0&k>0, or h==0&k==0&l>0)
    posIdx = (memberHKL(:,1) > 0) | ...
             (memberHKL(:,1) == 0 & memberHKL(:,2) > 0) | ...
             (memberHKL(:,1) == 0 & memberHKL(:,2) == 0 & memberHKL(:,3) > 0);
    if any(posIdx)
        posHKL = memberHKL(posIdx,:);
    else
        posHKL = memberHKL;
    end
    % Rank: fewest negative indices first, then largest sum, then lex on abs
    nNegs = sum(posHKL < 0, 2);
    hklSum = sum(posHKL, 2);
    absHKL = abs(posHKL);
    [~, si] = sortrows([nNegs, -hklSum, absHKL]);
    hklOut(gi,:) = posHKL(si(1),:);
end

% Sort by descending d (ascending 2theta)
[dOut, sortIdx] = sort(dOut, 'descend');
hklOut  = hklOut(sortIdx,:);
multOut = multOut(sortIdx);

% ════════════════════════════════════════════════════════════════════
% Compute 2theta if wavelength given
% ════════════════════════════════════════════════════════════════════

if ~isnan(opts.Lambda)
    sinTheta = opts.Lambda ./ (2 * dOut);
    twoThetaOut = 2 * asind(min(sinTheta, 1));  % clamp to avoid complex
    % Mark physically unreachable reflections as NaN
    twoThetaOut(sinTheta > 1) = NaN;
else
    twoThetaOut = NaN(size(dOut));
end

% ════════════════════════════════════════════════════════════════════
% Infer crystal system from the first dSpacing call
% ════════════════════════════════════════════════════════════════════

r0 = calc.crystal.dSpacing(a, 1, 0, 0, ...
    b=opts.b, c=opts.c, ...
    alpha=opts.alpha, beta=opts.beta, gamma=opts.gamma);

% ════════════════════════════════════════════════════════════════════
% Build result struct
% ════════════════════════════════════════════════════════════════════

result.hkl          = hklOut;
result.d            = dOut;
result.twoTheta     = twoThetaOut;
result.multiplicity = multOut;
result.centering    = centering;
result.system       = r0.system;
result.lambda       = opts.Lambda;
result.nReflections = numel(dOut);

end

% ════════════════════════════════════════════════════════════════════
% Systematic absence rules
% ════════════════════════════════════════════════════════════════════

function ok = isAllowed(h, k, l, centering)
    switch centering
        case 'P'
            ok = true;
        case 'F'
            % All odd or all even
            parity = mod([h, k, l], 2);
            ok = all(parity == 0) || all(parity == 1);
        case 'I'
            ok = mod(h + k + l, 2) == 0;
        case 'A'
            ok = mod(k + l, 2) == 0;
        case 'B'
            ok = mod(h + l, 2) == 0;
        case 'C'
            ok = mod(h + k, 2) == 0;
        case 'R'
            ok = mod(h - k + l, 3) == 0;  % obverse setting (IUCr standard)
        otherwise
            ok = true;
    end
end
