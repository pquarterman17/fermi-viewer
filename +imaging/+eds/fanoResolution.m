function [fwhmEV, sigmaKeV] = fanoResolution(energyKeV, options)
%FANORESOLUTION  EDS detector energy resolution from the Fiori-Newbury model.
%
%   Syntax
%     fwhmEV            = imaging.eds.fanoResolution(energyKeV)
%     [fwhmEV, sigmaKeV] = imaging.eds.fanoResolution(energyKeV, Name=Value)
%
%   Inputs
%     energyKeV — scalar or array of X-ray line energies (keV)
%
%   Name-Value
%     Fano         (1,1) double = 0.12   Fano factor (Si)
%     EpsilonEV    (1,1) double = 3.85   mean energy per e-h pair, Si (eV)
%     RefEnergyKeV (1,1) double = 5.899  anchor line energy (Mn-Kα, keV)
%     RefFwhmEV    (1,1) double = 130    detector FWHM at the anchor (eV)
%
%   Outputs
%     fwhmEV   — detector FWHM at each energy (eV), same size as energyKeV
%     sigmaKeV — Gaussian sigma (keV): fwhmEV / (2*sqrt(2*log(2))) / 1000
%
%   Model (Fiori-Newbury):  FWHM(E)^2 = FWHM_noise^2 + k*F*eps*E  [eV^2],
%   k = (2*sqrt(2*log 2))^2. The electronic-noise term is back-solved so
%   the curve passes exactly through (RefEnergyKeV, RefFwhmEV) — the
%   Mn-Kα 130 eV SDD spec by default. The value under the square root is
%   clamped at 0 so far-below-reference energies return a real (small)
%   width rather than a complex number.
%
%   This is the single source of EDS peak widths: peak-fit models take
%   sigmaKeV as their fixed Gaussian width, continuum fitting masks
%   characteristic peaks at a multiple of fwhmEV, and escape/sum-peak
%   clearance tests scale with it.
%
%   Examples
%     imaging.eds.fanoResolution(5.899)          % -> 130 (the anchor)
%     [~, s] = imaging.eds.fanoResolution(8.048) % Cu-Kα sigma in keV
%
%   Reference: Fiori & Newbury, SEM/1978/I, 401; Egerton conventions.
%   Port of fermiviewer calc/eds_calib.py (fano_fwhm / fano_sigma_kev).

    arguments
        energyKeV            {mustBeNumeric}
        options.Fano         (1,1) double = 0.12
        options.EpsilonEV    (1,1) double = 3.85
        options.RefEnergyKeV (1,1) double = 5.899
        options.RefFwhmEV    (1,1) double = 130.0
    end

    kFWHM = (2 * sqrt(2 * log(2)))^2;                 % FWHM<->sigma factor, squared
    slope = kFWHM * options.Fano * options.EpsilonEV; % eV^2 per eV

    eEV     = double(energyKeV) * 1000;
    refEV   = options.RefEnergyKeV * 1000;
    noiseSq = options.RefFwhmEV^2 - slope * refEV;

    fwhmEV   = sqrt(max(noiseSq + slope * eEV, 0));
    sigmaKeV = fwhmEV / (2 * sqrt(2 * log(2))) / 1000;
end
