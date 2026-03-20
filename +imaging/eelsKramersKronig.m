function result = eelsKramersKronig(energyAxis, spectrum, opts)
%EELSKRAMERSKRONIG  Compute complex dielectric function via Kramers-Kronig.
%
%   Syntax:
%       result = imaging.eelsKramersKronig(energyAxis, spectrum)
%       result = imaging.eelsKramersKronig(energyAxis, spectrum, ...
%           ZLPWindow=[-5 5], RefractiveIndex=1.5, AccVoltage=200, ...
%           CollectionAngle=10, Thickness=50)
%
%   Implements the Kramers-Kronig analysis procedure described in Egerton,
%   "Electron Energy-Loss Spectroscopy in the Electron Microscope", Ch. 4.
%   From the low-loss EELS spectrum, the function extracts the energy-loss
%   function Im(-1/ε), applies a Kramers-Kronig sum rule to normalise it,
%   then uses an FFT-based Hilbert transform to obtain Re(1/ε) and inverts
%   to give the full complex dielectric function ε = ε₁ + iε₂.
%
%   Inputs:
%       energyAxis — [N x 1] energy-loss axis (eV), should span 0 to ~50 eV
%                   for typical low-loss analysis
%       spectrum   — [N x 1] counts or cps (low-loss region)
%
%   Optional Name-Value:
%       ZLPWindow       — [E_lo, E_hi] eV window for ZLP removal.
%                         Default: [-5, 5].
%       RefractiveIndex — real part of refractive index n at optical limit,
%                         used for the KK sum rule (1 - 1/n²).
%                         Default: NaN — assumes n = 1 (vacuum), giving
%                         sum-rule target = 0; use n = 1 for relative
%                         normalisation only.
%       CollectionAngle — EELS collection semi-angle β (mrad). Default: 10.
%       AccVoltage      — accelerating voltage (kV). Default: 200.
%       Thickness       — specimen thickness (nm). If NaN (default), it is
%                         estimated from t/λ using the ZLP integral ratio.
%
%   Output struct fields:
%       .energy              — [M x 1] eV (positive-energy region only)
%       .eps1                — [M x 1] Re(ε)
%       .eps2                — [M x 1] Im(ε)
%       .elf                 — [M x 1] energy-loss function Im(-1/ε)
%       .opticalConductivity — [M x 1] σ₁ (S/m = 1/(Ω·m))
%       .refractiveIndex     — [M x 1] real refractive index n = sqrt((|ε|+ε₁)/2)
%       .thickness           — scalar estimated or supplied thickness (nm)
%
%   Examples:
%       % Basic KK analysis using an n=1 (vacuum) sum-rule target
%       res = imaging.eelsKramersKronig(E, I);
%       plot(res.energy, res.eps1, res.energy, res.eps2);
%       legend('\epsilon_1','\epsilon_2'); xlabel('Energy (eV)');
%
%       % Supply known refractive index for absolute normalisation
%       res = imaging.eelsKramersKronig(E, I, RefractiveIndex=1.5, ...
%           ZLPWindow=[-3 3], AccVoltage=300);
%
%   See also imaging.eelsFourierLog, imaging.eelsBackground,
%            imaging.eelsELNES

% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    energyAxis (:,1) double {mustBeNonempty}
    spectrum   (:,1) double {mustBeNonempty}
    opts.ZLPWindow       (1,2) double = [-5, 5]
    opts.RefractiveIndex (1,1) double = NaN
    opts.CollectionAngle (1,1) double {mustBePositive} = 10    % mrad
    opts.AccVoltage      (1,1) double {mustBePositive} = 200   % kV
    opts.Thickness       (1,1) double = NaN                    % nm
end

% ════════════════════════════════════════════════════════════════════════
%  Physical constants
% ════════════════════════════════════════════════════════════════════════
eCharge = 1.602e-19;   % C
hbar    = 1.055e-34;   % J*s
eps0    = 8.854e-12;   % F/m (vacuum permittivity, for sigma conversion)

energyAxis = double(energyAxis(:));
spectrum   = double(spectrum(:));
N          = numel(energyAxis);

if numel(spectrum) ~= N
    error('imaging:eelsKramersKronig:sizeMismatch', ...
        'energyAxis and spectrum must have the same number of elements.');
end

% ════════════════════════════════════════════════════════════════════════
%  Remove ZLP: zero out spectrum in ZLP window
% ════════════════════════════════════════════════════════════════════════
zlpMask = energyAxis >= opts.ZLPWindow(1) & energyAxis <= opts.ZLPWindow(2);
if sum(zlpMask) < 1
    error('imaging:eelsKramersKronig:emptyZLPWindow', ...
        'ZLPWindow [%.1f, %.1f] eV contains no data points.', ...
        opts.ZLPWindow(1), opts.ZLPWindow(2));
end

% Estimate t/lambda from ZLP integral ratio before zeroing
I_0     = sum(spectrum(zlpMask));
I_total = sum(max(spectrum, 0));
if I_0 > 0
    tLambda = log(max(I_total / I_0, 1 + eps));
else
    tLambda = 0;
end

specCorr              = max(spectrum, 0);
specCorr(zlpMask)     = 0;   % zero ZLP region

% ════════════════════════════════════════════════════════════════════════
%  Restrict to positive-energy region
% ════════════════════════════════════════════════════════════════════════
posMask = energyAxis > 0;
if sum(posMask) < 4
    error('imaging:eelsKramersKronig:insufficientPositiveEnergy', ...
        'Fewer than 4 data points with E > 0.  Check energyAxis range.');
end

E  = energyAxis(posMask);
S  = specCorr(posMask);
M  = numel(E);

% ════════════════════════════════════════════════════════════════════════
%  Energy spacing (assume uniform or use trapz weighting via dE vector)
% ════════════════════════════════════════════════════════════════════════
% Build a dE vector for numerical integration (works for non-uniform grids)
dE       = zeros(M, 1);
dE(1)    = E(2) - E(1);
dE(end)  = E(end) - E(end-1);
dE(2:end-1) = (E(3:end) - E(1:end-2)) / 2;   % central differences

% ════════════════════════════════════════════════════════════════════════
%  KK sum-rule normalisation
% ════════════════════════════════════════════════════════════════════════
% Target: (2/pi) * integral( Im(-1/eps) * dE/E ) = 1 - 1/n^2
% Treat S as proportional to Im(-1/eps): Im(-1/eps) = K * S
% Solve for K.

% Protect against zero or very small E in the integration denominator
Eguard = max(E, eps);

rawIntegral = sum(S .* dE ./ Eguard);   % integral(S * dE / E)

if isnan(opts.RefractiveIndex) || opts.RefractiveIndex <= 0
    n          = 1.0;
    sumTarget  = 0;   % vacuum: no absolute normalisation; K set to avoid blow-up
else
    n         = opts.RefractiveIndex;
    sumTarget = 1 - 1/n^2;
end

if rawIntegral > eps && sumTarget > 0
    K = sumTarget * pi / (2 * rawIntegral);
else
    % Relative normalisation: scale so max(ELF) = 1 for display
    peakS = max(S);
    K = (peakS > 0) * (1 / max(peakS, eps)) + (peakS <= 0);
end

elf = K * S;   % Im(-1/eps)  [M x 1]

% ════════════════════════════════════════════════════════════════════════
%  Hilbert transform for Re(1/eps) via FFT
% ════════════════════════════════════════════════════════════════════════
% Standard Hilbert-transform sign convention:
%   H{x}(t) = (1/pi) * P.V. integral x(tau)/(t-tau) dtau
%
% FFT implementation on a uniformly sampled discrete signal:
%   H = real(ifft(-1i * sign(freq) .* fft(x)))
% where freq(k) > 0.5 is mapped to freq(k) - 1 (negative frequencies).

N2   = 2 ^ nextpow2(M);           % next power of 2 for FFT efficiency
freq = (0:N2-1)' / N2;            % normalised frequency [0, 1)
freq(freq > 0.5) = freq(freq > 0.5) - 1;   % map to [-0.5, 0.5)

elfPad  = [elf; zeros(N2 - M, 1)];

% Compute Hilbert transform of ELF
H_elf   = real(ifft(-1i * sign(freq) .* fft(elfPad)));
H_elf   = H_elf(1:M);             % truncate to original length

% Re(1/eps) = 1 - H{ Im(-1/eps) }  (Kramers-Kronig dispersion relation)
re_inv_eps = 1 - H_elf;

% ════════════════════════════════════════════════════════════════════════
%  Invert to obtain complex dielectric function
% ════════════════════════════════════════════════════════════════════════
% 1/eps = re_inv_eps + i * elf  (using Im(-1/eps) = -Im(1/eps), so elf here is Im(-1/eps))
% eps   = 1 / (re_inv_eps - i * elf)

inv_eps = re_inv_eps - 1i * elf;   % 1/eps = Re(1/eps) + i*Im(1/eps) = re_inv_eps - i*elf

% Avoid division by zero in the inversion
denom   = real(inv_eps).^2 + imag(inv_eps).^2;
denom   = max(denom, eps^2);

eps_cmplx = conj(inv_eps) ./ denom;   % eps = conj(1/eps) / |1/eps|^2  (same as 1/inv_eps)
eps1 = real(eps_cmplx);
eps2 = imag(eps_cmplx);

% ════════════════════════════════════════════════════════════════════════
%  Derived optical quantities
% ════════════════════════════════════════════════════════════════════════
% Optical conductivity: sigma1 = eps2 * omega * eps0
%   omega (rad/s) = E (eV) * eCharge / hbar
omega = E * eCharge ./ hbar;                  % [M x 1] rad/s
opticalConductivity = eps2 .* omega * eps0;   % S/m

% Real refractive index: n = sqrt( (|eps| + eps1) / 2 )
epsAbs       = sqrt(eps1.^2 + eps2.^2);
nIdx         = sqrt(max((epsAbs + eps1) / 2, 0));

% ════════════════════════════════════════════════════════════════════════
%  Thickness estimate
% ════════════════════════════════════════════════════════════════════════
if isnan(opts.Thickness)
    % Use mean free path approximation: lambda ~ 100 nm for 200 kV typical
    % Scale crudely with accelerating voltage (Malis formula estimate)
    lambdaEst  = 100 * sqrt(opts.AccVoltage / 200);   % nm (rough)
    thickness  = tLambda * lambdaEst;
else
    thickness  = opts.Thickness;
end

% ════════════════════════════════════════════════════════════════════════
%  Pack output
% ════════════════════════════════════════════════════════════════════════
result.energy              = E;
result.eps1                = eps1;
result.eps2                = eps2;
result.elf                 = elf;
result.opticalConductivity = opticalConductivity;
result.refractiveIndex     = nIdx;
result.thickness           = thickness;

end
