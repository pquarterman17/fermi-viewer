function result = eelsELNES(energyAxis, spectrum, opts)
%EELSELNES  Extract EELS near-edge fine structure (ELNES).
%
%   Syntax:
%       result = imaging.eelsELNES(energyAxis, spectrum, ...
%           EdgeOnset=532, FitWindow=[480 525])
%       result = imaging.eelsELNES(energyAxis, spectrum, ...
%           EdgeOnset=532, FitWindow=[480 525], ...
%           ELNESWindow=[0 30], Method='powerlaw', Normalize=true)
%
%   Subtracts a pre-edge background and isolates the near-edge fine
%   structure in a chosen energy window above the edge onset.  Background
%   removal delegates to imaging.eelsBackground so the same model options
%   ('powerlaw' | 'exponential') are available.
%
%   Inputs:
%       energyAxis — [N x 1] energy-loss axis (eV)
%       spectrum   — [N x 1] intensity (counts or cps)
%
%   Required Name-Value:
%       EdgeOnset  — edge onset energy (eV).  No default; must be supplied.
%       FitWindow  — [E1, E2] pre-edge background fit window (eV).
%                   Must lie below EdgeOnset.
%
%   Optional Name-Value:
%       ELNESWindow — [dE_lo, dE_hi] range relative to onset (eV).
%                    Default: [0, 30].
%       Method      — background model: 'powerlaw' (default) | 'exponential'
%       Normalize   — divide ELNES intensities by edge jump.  Default: true.
%
%   Output struct fields:
%       .relativeEnergy   — [M x 1] energy relative to onset (eV)
%       .intensity        — [M x 1] ELNES intensity (normalised or raw)
%       .edgeJump         — scalar edge-jump value used for normalisation
%       .edgeOnset        — onset value that was used (eV)
%       .backgroundParams — fit params struct from imaging.eelsBackground
%
%   Examples:
%       % Extract O-K ELNES (onset ~532 eV)
%       res = imaging.eelsELNES(E, I, EdgeOnset=532, FitWindow=[480 525]);
%       plot(res.relativeEnergy, res.intensity);
%       xlabel('Energy relative to onset (eV)');
%       ylabel('Normalized intensity');
%
%       % Use exponential background and raw (un-normalized) output
%       res = imaging.eelsELNES(E, I, EdgeOnset=532, FitWindow=[480 525], ...
%           Method='exponential', Normalize=false);
%
%   See also imaging.eelsBackground, imaging.eelsFourierLog,
%            imaging.eelsKramersKronig

% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    energyAxis (:,1) double {mustBeNonempty}
    spectrum   (:,1) double {mustBeNonempty}
    opts.EdgeOnset   (1,1) double              % required — validated below
    opts.FitWindow   (1,2) double              % required — validated below
    opts.ELNESWindow (1,2) double = [0, 30]
    opts.Method      (1,1) string {mustBeMember(opts.Method, ...
                         {'powerlaw','exponential'})} = 'powerlaw'
    opts.Normalize   (1,1) logical = true
end

energyAxis = double(energyAxis(:));
spectrum   = double(spectrum(:));

if numel(energyAxis) ~= numel(spectrum)
    error('imaging:eelsELNES:sizeMismatch', ...
        'energyAxis and spectrum must have the same number of elements.');
end

% Confirm required arguments were supplied (arguments block sets them to
% 0/[0 0] by default when omitted — detect by checking for field existence
% via a try/catch is fragile, so instead we require callers to pass them
% and validate by checking that FitWindow lies below the onset).
if ~isfield(opts, 'EdgeOnset') || ~isfield(opts, 'FitWindow')
    error('imaging:eelsELNES:missingArgument', ...
        'Both EdgeOnset and FitWindow must be supplied.');
end

onset     = opts.EdgeOnset;
fitWindow = opts.FitWindow;

if fitWindow(1) >= fitWindow(2)
    error('imaging:eelsELNES:invalidFitWindow', ...
        'FitWindow(1) must be less than FitWindow(2).');
end
if fitWindow(2) >= onset
    error('imaging:eelsELNES:fitWindowOverlapsEdge', ...
        'FitWindow [%.1f, %.1f] must lie entirely below EdgeOnset (%.1f eV).', ...
        fitWindow(1), fitWindow(2), onset);
end

% ════════════════════════════════════════════════════════════════════════
%  Background subtraction
% ════════════════════════════════════════════════════════════════════════
[signal, ~, bgParams] = imaging.eelsBackground(energyAxis, spectrum, ...
    FitWindow=fitWindow, Method=opts.Method);

% ════════════════════════════════════════════════════════════════════════
%  Isolate ELNES region
% ════════════════════════════════════════════════════════════════════════
eMin = onset + opts.ELNESWindow(1);
eMax = onset + opts.ELNESWindow(2);

elnesMask = energyAxis >= eMin & energyAxis <= eMax;
if sum(elnesMask) < 2
    error('imaging:eelsELNES:tooFewELNESPoints', ...
        'ELNESWindow [onset%+.1f, onset%+.1f] eV contains fewer than 2 data points.', ...
        opts.ELNESWindow(1), opts.ELNESWindow(2));
end

elnesE   = energyAxis(elnesMask);
elnesI   = signal(elnesMask);

% ════════════════════════════════════════════════════════════════════════
%  Edge jump: mean signal in first 5 eV above onset
% ════════════════════════════════════════════════════════════════════════
jumpMask = energyAxis >= onset & energyAxis <= (onset + 5);
if any(jumpMask)
    edgeJump = mean(signal(jumpMask));
else
    % Fallback: use the first point in the ELNES region
    edgeJump = elnesI(1);
end
edgeJump = max(edgeJump, eps);   % prevent divide-by-zero

% ════════════════════════════════════════════════════════════════════════
%  Optional normalization
% ════════════════════════════════════════════════════════════════════════
if opts.Normalize && edgeJump > 0
    elnesI = elnesI / edgeJump;
end

% ════════════════════════════════════════════════════════════════════════
%  Pack output
% ════════════════════════════════════════════════════════════════════════
result.relativeEnergy   = elnesE - onset;
result.intensity        = elnesI;
result.edgeJump         = edgeJump;
result.edgeOnset        = onset;
result.backgroundParams = bgParams;

end
