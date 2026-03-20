function result = indexDiffraction(spotPositions, imgSize, opts)
%INDEXDIFFRACTION  Match diffraction spots to crystal phases.
%
%   Syntax:
%       result = imaging.indexDiffraction(spotPositions, imgSize)
%       result = imaging.indexDiffraction(spotPositions, imgSize, ...
%                    AccVoltage=200, Tolerance=0.05, TopN=5)
%
%   Computes a d-spacing for every detected spot, then scores each phase
%   in the built-in crystal database by how many measured d-spacings fall
%   within Tolerance of a reference reflection.  Returns the top-N
%   candidate phases ranked by match score, with optional zone-axis
%   identification for spot patterns.
%
%   Two geometry modes are supported:
%
%     FFT mode (CameraLength = NaN, default):
%       d = (imgSize(2) * PixelSize) / R
%       Matches the latticeMeasure.m convention where each pixel step in
%       a centred FFT image represents one period of 1/(N*PixelSize).
%
%     TEM camera mode (CameraLength given in mm):
%       d = lambda * CameraLength_Angstrom / (R * PixelSize_Angstrom)
%       Bragg's law in the small-angle approximation.
%
%   Inputs:
%       spotPositions — [N x 2] double [row, col] pixel coordinates;
%                       typically the output of imaging.findDiffractionSpots
%       imgSize       — [1 x 2] double [rows, cols] image size in pixels
%
%   Optional Name-Value:
%       PixelSize    — real-space pixel size, in PixelUnit (default: 1)
%       PixelUnit    — unit string for display (default: 'px')
%       CameraLength — effective camera length in mm; set NaN to use
%                      FFT geometry (default: NaN)
%       AccVoltage   — TEM accelerating voltage in kV, used to compute
%                      the relativistic electron wavelength (default: 200)
%       Tolerance    — fractional d-spacing match tolerance: a spot is
%                      matched when |d_meas - d_ref| / d_ref < Tolerance
%                      (default: 0.05)
%       MaxHKL       — maximum |h|, |k|, |l| passed to planeSpacings
%                      (default: 5)
%       Phases       — cell array of phase names to restrict the search;
%                      empty cell means search all phases (default: {})
%       TopN         — number of top candidates to return (default: 5)
%
%   Output:
%       result — struct with fields:
%           .candidates  — struct array (length TopN) sorted by score:
%               .phaseName   — string phase name
%               .formula     — chemical formula string
%               .score       — match fraction: nMatched / nSpots
%               .nMatched    — number of spots with a matching reflection
%               .nSpots      — total number of input spots
%               .matchedHKL  — [M x 3] Miller indices of matched reflections
%               .matchedD    — [M x 1] measured d-spacings for matched spots (Å)
%               .refD        — [M x 1] reference d-spacings for matched reflections (Å)
%               .zoneAxis    — [1 x 3] zone axis [u v w] satisfying h*u+k*v+l*w=0
%                              for all matched hkl; [NaN NaN NaN] if not identifiable
%           .measuredD   — [N x 1] d-spacings computed from spot radii (Å)
%           .measuredR   — [N x 1] spot radii from pattern center (pixels)
%           .center      — [1 x 2] pattern center [row, col] used (floor(imgSize/2)+1)
%
%   Examples:
%       % FFT-mode indexing from spots detected automatically
%       [mag, ~] = imaging.computeFFT(img);
%       spots = imaging.findDiffractionSpots(mag, MinRadius=20);
%       result = imaging.indexDiffraction(spots, size(img), ...
%                    PixelSize=0.195, PixelUnit='nm');
%       fprintf('Best match: %s  (score %.0f%%)\n', ...
%               result.candidates(1).phaseName, ...
%               result.candidates(1).score * 100);
%
%       % TEM mode with known camera length
%       result = imaging.indexDiffraction(spots, size(img), ...
%                    PixelSize=0.05, PixelUnit='mm', ...
%                    CameraLength=800, AccVoltage=300);
%
%       % Restrict search to specific phases
%       result = imaging.indexDiffraction(spots, size(img), ...
%                    PixelSize=0.195, PixelUnit='nm', ...
%                    Phases={'Silicon','Iron','Magnetite'}, TopN=3);
%
%   See also imaging.findDiffractionSpots, imaging.latticeMeasure,
%            imaging.calcElectronWavelength, calc.crystal.phaseDatabase,
%            calc.crystal.planeSpacings

% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    spotPositions (:,2) double
    imgSize       (1,2) double {mustBePositive, mustBeInteger}
    opts.PixelSize     (1,1) double {mustBePositive}          = 1
    opts.PixelUnit     (1,1) string                           = 'px'
    opts.CameraLength  (1,1) double                           = NaN
    opts.AccVoltage    (1,1) double {mustBePositive}          = 200
    opts.Tolerance     (1,1) double {mustBePositive}          = 0.05
    opts.MaxHKL        (1,1) double {mustBePositive, mustBeInteger} = 5
    opts.Phases        (1,:) cell                             = {}
    opts.TopN          (1,1) double {mustBePositive, mustBeInteger} = 5
end

% ════════════════════════════════════════════════════════════════════════
%  Pattern center  (MATLAB fftshift convention, same as latticeMeasure)
% ════════════════════════════════════════════════════════════════════════
centerRow = floor(imgSize(1) / 2) + 1;
centerCol = floor(imgSize(2) / 2) + 1;

% ════════════════════════════════════════════════════════════════════════
%  Spot radii from center
% ════════════════════════════════════════════════════════════════════════
nSpots = size(spotPositions, 1);

dr = spotPositions(:,1) - centerRow;
dc = spotPositions(:,2) - centerCol;
R  = sqrt(dr.^2 + dc.^2);   % pixels

% ════════════════════════════════════════════════════════════════════════
%  Convert radii to d-spacings (Angstroms)
% ════════════════════════════════════════════════════════════════════════
if isnan(opts.CameraLength)
    % ── FFT mode ────────────────────────────────────────────────────────
    %  Each pixel step in the centred FFT = 1 / (N * PixelSize) in
    %  reciprocal space.  d = 1/|g| = N * PixelSize / R.
    %  Use the column dimension (nCols) for horizontal frequency scaling.
    dMeas = (imgSize(2) * opts.PixelSize) ./ R;   % same units as PixelSize
else
    % ── TEM camera mode ──────────────────────────────────────────────────
    %  Bragg law in small-angle limit: d = lambda * L / r
    %  lambda in Å, L in Å (camera length converted from mm), r in Å.
    lambda   = imaging.calcElectronWavelength(opts.AccVoltage);   % Å
    L_ang    = opts.CameraLength * 1e7;    % mm → Å
    r_ang    = R * opts.PixelSize * 1e7;   % PixelSize in mm → Å (per pixel)
    % If PixelUnit suggests the size is already in a reasonable unit,
    % use it directly in Å assuming the user supplied PixelSize in mm.
    % (The unit string is stored for display only; conversion is the
    %  user's responsibility in this mode.)
    dMeas = (lambda .* L_ang) ./ r_ang;   % Å
end

% Guard: zero-radius spots (centre) produce Inf — remove them.
validSpot = isfinite(dMeas) & R > 0;
dMeas(~validSpot) = NaN;

% ════════════════════════════════════════════════════════════════════════
%  Load phase database and apply optional name filter
% ════════════════════════════════════════════════════════════════════════
db = calc.crystal.phaseDatabase();

if ~isempty(opts.Phases)
    dbNames  = {db.name};
    keepMask = ismember(dbNames, opts.Phases);
    if ~any(keepMask)
        warning('imaging:indexDiffraction:noPhaseMatch', ...
            'None of the requested phase names matched the database. Searching all phases.');
    else
        db = db(keepMask);
    end
end

nPhases = numel(db);

% ════════════════════════════════════════════════════════════════════════
%  Score each phase
% ════════════════════════════════════════════════════════════════════════
% Pre-allocate candidate struct array with empty fields.
emptyCandidate = struct( ...
    'phaseName',  '', ...
    'formula',    '', ...
    'score',      0,  ...
    'nMatched',   0,  ...
    'nSpots',     nSpots, ...
    'matchedHKL', zeros(0,3), ...
    'matchedD',   zeros(0,1), ...
    'refD',       zeros(0,1), ...
    'zoneAxis',   [NaN NaN NaN]);

candidates(nPhases) = emptyCandidate;   % pre-allocate

for ip = 1:nPhases
    ph = db(ip);

    % ── Enumerate allowed reflections (Lambda=NaN → skip 2theta) ────────
    try
        refs = calc.crystal.planeSpacings(ph.a, ...
            b=ph.b, c=ph.c, ...
            alpha=ph.alpha, beta=ph.beta, gamma=ph.gamma, ...
            Centering=ph.centering, ...
            MaxHKL=opts.MaxHKL, ...
            Lambda=NaN);
    catch
        % If planeSpacings fails for this phase, skip it.
        candidates(ip) = emptyCandidate;
        candidates(ip).phaseName = ph.name;
        candidates(ip).formula   = ph.formula;
        continue;
    end

    refD   = refs.d;     % [K x 1] Å, descending
    refHKL = refs.hkl;   % [K x 3]

    % ── Match each measured d to the closest reference d ─────────────
    nRef = numel(refD);
    matchedRows   = false(nSpots, 1);   % which spots were matched
    matchedHKLout = zeros(nSpots, 3);
    matchedDout   = zeros(nSpots, 1);
    refDout       = zeros(nSpots, 1);

    for is = 1:nSpots
        if ~validSpot(is), continue; end
        dm = dMeas(is);

        % Find closest reference d-spacing
        fracErr = abs(refD - dm) ./ refD;
        [minErr, minIdx] = min(fracErr);

        if minErr < opts.Tolerance
            matchedRows(is)      = true;
            matchedHKLout(is,:)  = refHKL(minIdx,:);
            matchedDout(is)      = dm;
            refDout(is)          = refD(minIdx);
        end
    end

    nMatched = sum(matchedRows);
    score    = nMatched / max(nSpots, 1);

    % ── Zone-axis identification ─────────────────────────────────────
    zoneAxis = [NaN NaN NaN];
    if nMatched >= 2
        hklMatched = matchedHKLout(matchedRows, :);   % [M x 3]
        zoneAxis   = findZoneAxis(hklMatched);
    end

    % ── Store candidate ──────────────────────────────────────────────
    c            = emptyCandidate;
    c.phaseName  = ph.name;
    c.formula    = ph.formula;
    c.score      = score;
    c.nMatched   = nMatched;
    c.nSpots     = nSpots;
    c.matchedHKL = matchedHKLout(matchedRows, :);
    c.matchedD   = matchedDout(matchedRows);
    c.refD       = refDout(matchedRows);
    c.zoneAxis   = zoneAxis;

    candidates(ip) = c;
end

% ════════════════════════════════════════════════════════════════════════
%  Sort by score descending; tiebreak by mean relative error (ascending)
% ════════════════════════════════════════════════════════════════════════
scores = [candidates.score];
[~, sortOrd] = sort(scores, 'descend');
candidates   = candidates(sortOrd);

% Tiebreak within equal-score groups by mean relative error.
candidates = tiebreakByError(candidates);

% Return at most TopN candidates.
nReturn    = min(opts.TopN, nPhases);
candidates = candidates(1:nReturn);

% ════════════════════════════════════════════════════════════════════════
%  Pack result struct
% ════════════════════════════════════════════════════════════════════════
result.candidates = candidates;
result.measuredD  = dMeas;
result.measuredR  = R;
result.center     = [centerRow, centerCol];

end   % main function

% ════════════════════════════════════════════════════════════════════════
%  Local helper: zone-axis identification
% ════════════════════════════════════════════════════════════════════════
function za = findZoneAxis(hklMatched)
%FINDZONEAXIS  Find [uvw] such that h*u + k*v + l*w = 0 for all rows.
%   Tries all [uvw] with |u|, |v|, |w| <= 3 (excluding [0 0 0]).
%   Returns the smallest-norm valid zone axis, or [NaN NaN NaN].

za = [NaN NaN NaN];

uvRange = -3:3;
nU = numel(uvRange);
nCandidates = nU^3 - 1;

if nCandidates <= 0 || isempty(hklMatched)
    return;
end

bestNorm = Inf;

for iu = 1:nU
    for iv = 1:nU
        for iw = 1:nU
            u = uvRange(iu);
            v = uvRange(iv);
            w = uvRange(iw);
            if u == 0 && v == 0 && w == 0, continue; end

            % Check h*u + k*v + l*w == 0 for all matched (hkl)
            dots = hklMatched(:,1)*u + hklMatched(:,2)*v + hklMatched(:,3)*w;

            if all(dots == 0)
                n = norm([u v w]);
                if n < bestNorm
                    bestNorm = n;
                    za = [u v w];
                end
            end
        end
    end
end

end   % findZoneAxis

% ════════════════════════════════════════════════════════════════════════
%  Local helper: tiebreak candidates with equal score by mean rel. error
% ════════════════════════════════════════════════════════════════════════
function candidates = tiebreakByError(candidates)
%TIEBREAKBYERROR  Within groups sharing the same score, sort by mean
%   relative d-spacing error (ascending).

if numel(candidates) <= 1
    return;
end

scores  = [candidates.score];
uScores = unique(scores, 'stable');

for is = 1:numel(uScores)
    idx = find(scores == uScores(is));
    if numel(idx) <= 1, continue; end

    % Compute mean relative error for each tied candidate.
    meanErr = zeros(1, numel(idx));
    for k = 1:numel(idx)
        c = candidates(idx(k));
        if c.nMatched > 0
            relErr = abs(c.matchedD - c.refD) ./ c.refD;
            meanErr(k) = mean(relErr);
        else
            meanErr(k) = Inf;
        end
    end

    [~, errOrd]    = sort(meanErr, 'ascend');
    candidates(idx) = candidates(idx(errOrd));
end

end   % tiebreakByError
