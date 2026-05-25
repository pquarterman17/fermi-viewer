function [data, header] = exportGrainCSV(result, options)
%EXPORTGRAINCSV  Per-grain measurement table from a grainStats result.
%
%   Syntax:
%       [data, header] = imaging.grains.exportGrainCSV(result)
%       imaging.grains.exportGrainCSV(result, Filename="grains.csv")
%
%   Flattens an imaging.grains.grainStats result into a numeric table (one
%   row per grain) and, when Filename is given, writes it as CSV. Returns the
%   matrix + header so callers (GUI, tests) can use the data without touching
%   disk.
%
%   Calibrated columns are included only when the result was computed with a
%   PixelSize (otherwise they would be all-NaN); the unit appears in the
%   relevant column headers.
%
%   No external toolboxes required.
%
%   Inputs:
%       result        — struct from imaging.grains.grainStats.
%
%   Optional Name-Value:
%       Filename      — output CSV path (default "": do not write).
%
%   Outputs:
%       data          — [G x K] numeric matrix, one row per grain.
%       header        — {1 x K} cellstr column names matching data columns.
%
%   Columns: id, area_px, equivDiameter_px, centroidRow, centroidCol,
%   meanIntensity [, area_<unit>, equivDiameter_<unit>].
%
%   See also imaging.grains.grainStats, imaging.grains.labelOverlay

arguments
    result            (1,1) struct
    options.Filename  (1,1) string = ""
end

g = result.grains;
G = numel(g);

hasCal = isfield(result, 'pixelSize') && ~isnan(result.pixelSize) && result.pixelSize > 0;
unit   = char(result.pixelUnit);

header = {'id', 'area_px', 'equivDiameter_px', 'centroidRow', 'centroidCol', 'meanIntensity'};
if hasCal
    header = [header, {['area_' unit], ['equivDiameter_' unit]}];
end

K = numel(header);
data = zeros(G, K);
for i = 1:G
    row = [g(i).id, g(i).area, g(i).equivDiameter, ...
           g(i).centroid(1), g(i).centroid(2), g(i).meanIntensity];
    if hasCal
        row = [row, g(i).areaCalibrated, g(i).diameterCalibrated]; %#ok<AGROW>
    end
    data(i, :) = row;
end

% ── Write CSV ───────────────────────────────────────────────────────────
if strlength(options.Filename) > 0
    fid = fopen(options.Filename, 'w');
    if fid == -1
        error('exportGrainCSV:open', 'Cannot open %s for writing.', options.Filename);
    end
    cleanup = onCleanup(@() fclose(fid));
    fprintf(fid, '%s\n', strjoin(header, ','));
    for i = 1:G
        fprintf(fid, '%g', data(i, 1));
        fprintf(fid, ',%g', data(i, 2:end));
        fprintf(fid, '\n');
    end
end
end
