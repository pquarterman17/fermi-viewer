function result = estimateCTF(img, opts)
%ESTIMATECTF  Estimate contrast transfer function parameters from a TEM power spectrum.
%
%   Syntax:
%       result = imaging.estimateCTF(img)
%       result = imaging.estimateCTF(img, Voltage_kV=300, Cs_mm=0.001, PixelSize=1.8)
%       result = imaging.estimateCTF(img, PixelSize=1.5, NumRings=8)
%
%   Computes the 2-D power spectrum of a TEM image, computes its radial
%   average, then estimates defocus by finding the value that best aligns
%   CTF^2 zero-crossings with minima in the radial power spectrum (Thon
%   ring analysis).  Defocus is refined with fminsearch.
%
%   No Image Processing Toolbox is required.
%
%   Inputs:
%       img — [H x W] numeric grayscale TEM image
%
%   Optional Name-Value:
%       Voltage_kV — accelerating voltage in kV (default: 200)
%       Cs_mm      — spherical aberration coefficient in mm (default: 1.2)
%       PixelSize  — pixel size in Angstroms (default: 1)
%       NumRings   — number of Thon rings expected; used to set search range
%                    (default: 10)
%
%   Output:
%       result — struct with fields:
%           .defocus       — estimated defocus in Angstroms (positive = underfocus)
%           .defocus_nm    — defocus in nm
%           .radialProfile — [numBins x 2] matrix: [spatialFreq_invA, meanPower]
%           .ctfFit        — [numBins x 1] fitted CTF^2 curve on same freq axis
%           .rSquared      — coefficient of determination for the CTF^2 fit
%           .voltage_kV    — echoed input voltage (kV)
%           .Cs_mm         — echoed input Cs (mm)
%           .lambda        — relativistic electron wavelength (Angstroms)
%
%   Algorithm:
%       1.  Relativistic wavelength: lambda = 12.2643/sqrt(V + 0.97845e-6*V^2)
%           where V is voltage in volts.
%       2.  Power spectrum: PS = |fftshift(fft2(img))|^2.
%       3.  Radial average binned over sqrt(kx^2+ky^2) in units of 1/Angstrom.
%       4.  Grid search over candidate defocus values; for each, compute
%           correlation between |CTF|^2 and the radial power spectrum.
%       5.  Refine best candidate with fminsearch (minimises negative correlation).
%       6.  Compute R^2 of the final fit.
%
%   Examples:
%       % Default parameters (200 kV, Cs=1.2 mm, 1 A/px)
%       result = imaging.estimateCTF(temImg, PixelSize=1.5);
%       fprintf('Defocus: %.1f nm\n', result.defocus_nm);
%
%       plot(result.radialProfile(:,1), result.radialProfile(:,2), 'k');
%       hold on;
%       plot(result.radialProfile(:,1), result.ctfFit, 'r');
%       xlabel('Spatial frequency (1/A)'); legend('Power spectrum','CTF^2 fit');
%
%       % Cryo-EM: 300 kV, Cs ≈ 0 (Cs-corrected), 1.06 A/px
%       result = imaging.estimateCTF(img, Voltage_kV=300, Cs_mm=0.001, PixelSize=1.06);
%
%   See also imaging.computeFFT

% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    img                  (:,:) {mustBeNumeric}
    opts.Voltage_kV      (1,1) double {mustBePositive} = 200
    opts.Cs_mm           (1,1) double = 1.2
    opts.PixelSize       (1,1) double {mustBePositive} = 1
    opts.NumRings        (1,1) double {mustBePositive} = 10
end

img = double(img);
[H, W] = size(img);

% ════════════════════════════════════════════════════════════════════════
%  Relativistic electron wavelength (Angstroms)
%  V in volts; formula: lambda = 12.2643 / sqrt(V + 0.97845e-6 * V^2)
% ════════════════════════════════════════════════════════════════════════
V      = opts.Voltage_kV * 1e3;                            % convert to volts
lambda = 12.2643 / sqrt(V + 0.97845e-6 * V^2);            % Angstroms

% ════════════════════════════════════════════════════════════════════════
%  Spherical aberration in Angstroms
% ════════════════════════════════════════════════════════════════════════
Cs = opts.Cs_mm * 1e7;    % mm -> Angstroms (1 mm = 1e7 A)

% ════════════════════════════════════════════════════════════════════════
%  2-D power spectrum
% ════════════════════════════════════════════════════════════════════════
PS = abs(fftshift(fft2(img))).^2;

% ════════════════════════════════════════════════════════════════════════
%  Spatial frequency grid (1/Angstrom)
% ════════════════════════════════════════════════════════════════════════
du = 1 / (W * opts.PixelSize);                 % frequency step along x
dv = 1 / (H * opts.PixelSize);                 % frequency step along y

uAxis = (-floor(W/2) : ceil(W/2) - 1) * du;   % [1 x W]
vAxis = (-floor(H/2) : ceil(H/2) - 1) * dv;   % [1 x H]

[Ku, Kv] = meshgrid(uAxis, vAxis);             % [H x W]
K2D = sqrt(Ku.^2 + Kv.^2);                    % radial spatial frequency [H x W]

% ════════════════════════════════════════════════════════════════════════
%  Radial average of power spectrum
% ════════════════════════════════════════════════════════════════════════
kMax      = min([max(abs(uAxis)), max(abs(vAxis))]);
numBins   = max(64, min(512, floor(min(H, W) / 2)));
binEdges  = linspace(0, kMax, numBins + 1);    % [1 x numBins+1]
binCentres = 0.5 * (binEdges(1:end-1) + binEdges(2:end));  % [1 x numBins]

radialPow = zeros(numBins, 1);
radialCnt = zeros(numBins, 1);

kFlat  = K2D(:);
psFlat = PS(:);

% Bin each pixel into the radial bin it belongs to
[~, binIdx] = histc(kFlat, binEdges);          %#ok<HISTC>  (no toolbox equivalent)
binIdx(binIdx == numBins + 1) = numBins;       % absorb pixels exactly on upper edge
valid = binIdx >= 1 & binIdx <= numBins;

for b = 1 : numBins
    sel = valid & (binIdx == b);
    if any(sel)
        radialPow(b) = mean(psFlat(sel));
        radialCnt(b) = sum(sel);
    end
end

% Remove empty bins
nonEmpty = radialCnt > 0;
freqAxis = binCentres(nonEmpty)';   % [M x 1]
radPow   = radialPow(nonEmpty);     % [M x 1]

% Normalise power spectrum to [0,1] for correlation
if max(radPow) > 0
    radPowN = radPow / max(radPow);
else
    radPowN = radPow;
end

% ════════════════════════════════════════════════════════════════════════
%  Defocus search range
%  Estimate from the expected position of the first Thon ring minimum:
%  first zero of CTF at k1: Df ≈ 1 / (lambda * k1^2)
%  Use kMax as a rough upper frequency to bound the range.
% ════════════════════════════════════════════════════════════════════════
kFirst   = kMax / (opts.NumRings + 1);         % rough first ring frequency
DfMin    = max(100, 0.5 / (lambda * kMax^2));  % at least 100 A, conservative low
DfMax    = 1.5 / (lambda * kFirst^2);          % enough to push ring 1 inward

numSearch = 200;
dfCandidates = linspace(DfMin, DfMax, numSearch);

% ════════════════════════════════════════════════════════════════════════
%  Grid search: pick defocus that maximises correlation with radial PS
% ════════════════════════════════════════════════════════════════════════
corrVals = zeros(numSearch, 1);
k2  = freqAxis.^2;
k4  = freqAxis.^4;

for idx = 1 : numSearch
    Df       = dfCandidates(idx);
    ctfArg   = pi * lambda * k2 * Df - 0.5 * pi * Cs * lambda^3 * k4;
    ctfSq    = sin(ctfArg).^2;                 % |CTF|^2 (envelope = 1)
    corrVals(idx) = sum(ctfSq .* radPowN);     % dot-product correlation
end

[~, bestIdx] = max(corrVals);
DfInit = dfCandidates(bestIdx);

% ════════════════════════════════════════════════════════════════════════
%  Refine with fminsearch (no optimisation toolbox needed)
% ════════════════════════════════════════════════════════════════════════
negCorr = @(Df) NegCorrelation(Df, lambda, Cs, k2, k4, radPowN);

fmOpts = optimset('TolX', 1, 'TolFun', 1e-6, 'MaxFunEvals', 500, 'Display', 'off');
DfFit  = fminsearch(negCorr, DfInit, fmOpts);

% Clamp to physical range
DfFit = max(DfMin * 0.5, min(DfMax * 1.5, DfFit));

% ════════════════════════════════════════════════════════════════════════
%  Compute fitted CTF^2 and R^2
% ════════════════════════════════════════════════════════════════════════
ctfArgFit = pi * lambda * k2 * DfFit - 0.5 * pi * Cs * lambda^3 * k4;
ctfSqFit  = sin(ctfArgFit).^2;

% R^2 between |CTF|^2 and normalised radial power spectrum
ssTot = sum((radPowN - mean(radPowN)).^2);
ssRes = sum((radPowN - ctfSqFit).^2);
if ssTot > 0
    rSq = 1 - ssRes / ssTot;
else
    rSq = 0;
end

% ════════════════════════════════════════════════════════════════════════
%  Assemble output
% ════════════════════════════════════════════════════════════════════════
result.defocus        = DfFit;
result.defocus_nm     = DfFit / 10;           % Angstroms -> nm
result.radialProfile  = [freqAxis, radPow];   % [M x 2]: freq (1/A), mean power
result.ctfFit         = ctfSqFit;             % [M x 1]: fitted |CTF|^2
result.rSquared       = rSq;
result.voltage_kV     = opts.Voltage_kV;
result.Cs_mm          = opts.Cs_mm;
result.lambda         = lambda;               % Angstroms

end % estimateCTF

% ════════════════════════════════════════════════════════════════════════
%  Local helper: negative correlation (objective for fminsearch)
% ════════════════════════════════════════════════════════════════════════
function nc = NegCorrelation(Df, lambda, Cs, k2, k4, radPowN)
%NEGCORRELATION  Return negative dot-product of |CTF|^2 with radial PS.
ctfArg = pi * lambda * k2 * Df - 0.5 * pi * Cs * lambda^3 * k4;
ctfSq  = sin(ctfArg).^2;
nc     = -sum(ctfSq .* radPowN);
end
