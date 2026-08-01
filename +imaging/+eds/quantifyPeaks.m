function [pf, cl] = quantifyPeaks(energy, counts, elements, options)
%QUANTIFYPEAKS  Deconvolve overlapping peaks then Cliff-Lorimer quantify.
%
%   Syntax
%     [pf, cl] = imaging.eds.quantifyPeaks(energy, counts, elements)
%     [pf, cl] = imaging.eds.quantifyPeaks(energy, counts, elements, Name=Value)
%
%   Thin composition layer: net peak areas from imaging.eds.fitPeaks become
%   1x1 intensity "maps" fed unchanged to imaging.eds.cliffLorimer. This is
%   the "peakfit" quantification path -- an alternative net intensity source
%   to a simple window-integration sum, useful when characteristic lines
%   overlap (S-Ka/Mo-La/Pb-Ma, Ti-Kb/V-Ka, ...).
%
%   Inputs
%     energy, counts  numeric vectors, the summed spectrum (keV axis + counts)
%     elements        {1xN} cellstr, elements to fit and quantify
%
%   Name-Value
%     KFactors      [1xN] double = []   Cliff-Lorimer k-factors, forwarded to
%                   imaging.eds.cliffLorimer. Default: looked up from
%                   imaging.eds.edsKFactorTable at Voltage.
%     Voltage       (1,1) double = 200  forwarded to imaging.eds.cliffLorimer
%                   when KFactors is not supplied
%     BeamKV        (1,1) double = 200  forwarded to imaging.eds.fitPeaks
%     CenterTolKeV  (1,1) double = 0    forwarded to imaging.eds.fitPeaks
%     Weights       (1,1) string = "uniform"   forwarded to imaging.eds.fitPeaks
%
%   Output
%     pf  the imaging.eds.fitPeaks result struct
%     cl  the imaging.eds.cliffLorimer result struct (1x1 maps, so
%         cl.meanAtomicPct / cl.meanWeightPct ARE the per-pixel values --
%         i.e. the composition)
%
%   Example
%     [pf, cl] = imaging.eds.quantifyPeaks(e, counts, {'Fe','O'}, ...
%         KFactors=[1.21 1.80]);
%     cl.meanWeightPct       % -> [Fe wt%, O wt%]
%
%   See also IMAGING.EDS.FITPEAKS, IMAGING.EDS.CLIFFLORIMER
%
%   Port of fermiviewer calc/eds_peakfit.py (quantify_peaks).

    arguments
        energy   {mustBeNumeric, mustBeVector}
        counts   {mustBeNumeric, mustBeVector}
        elements (1,:) cell
        options.KFactors     (1,:) double = []
        options.Voltage      (1,1) double = 200
        options.BeamKV       (1,1) double = 200
        options.CenterTolKeV (1,1) double = 0
        options.Weights      (1,1) string {mustBeMember(options.Weights, ["uniform", "poisson"])} = "uniform"
    end

pf = imaging.eds.fitPeaks(energy, counts, elements, ...
    BeamKV=options.BeamKV, CenterTolKeV=options.CenterTolKeV, Weights=options.Weights);

N = numel(elements);
maps = cell(1, N);
for i = 1:N
    area = pf.netArea(i);
    if isnan(area), area = 0; end
    maps{i} = max(area, 0);
end

if isempty(options.KFactors)
    cl = imaging.eds.cliffLorimer(maps, elements, Voltage=options.Voltage);
else
    cl = imaging.eds.cliffLorimer(maps, elements, KFactors=options.KFactors);
end

end
