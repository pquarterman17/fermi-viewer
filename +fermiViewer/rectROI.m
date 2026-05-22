function result = rectROI(pixels, xMin, xMax, yMin, yMax, imgInfo)
%RECTROI  Compute ROI statistics and show histogram figure.
%
% Syntax:
%   result = emViewer.rectROI(pixels, xMin, xMax, yMin, yMax, imgInfo)
%
% Inputs:
%   pixels  - [H x W] numeric array (filteredPixels)
%   xMin, xMax, yMin, yMax - integer pixel bounds (1-indexed, inclusive)
%   imgInfo - struct with fields: calibrated, pixelSize, pixelUnit
%             (from imageData metadata). Pass [] to skip calibration.
%
% Outputs:
%   result - struct with fields:
%     .mean, .std, .min, .max, .area  - scalar statistics
%     .areaStr  - human-readable area string (px² or calibrated)
%     .statsLines - cell array of text lines for display
%
% Examples:
%   r = emViewer.rectROI(pixels, 10, 50, 20, 60, imgInfo);
%   fprintf('Mean: %.2f\n', r.mean);

% ════════════════════════════════════════════════════════════════════

roiPx = pixels(yMin:yMax, xMin:xMax);
vals  = double(roiPx(:));

roiMean = mean(vals);
roiStd  = std(vals);
roiMin  = min(vals);
roiMax  = max(vals);
roiArea = numel(vals);

% Calibrated area string
sq = char(178);   % superscript 2 (U+00B2)
areaStr = sprintf('%d px%s', roiArea, sq);
if ~isempty(imgInfo) && isfield(imgInfo, 'calibrated') && ...
        imgInfo.calibrated && isfield(imgInfo, 'pixelSize') && ...
        ~isnan(imgInfo.pixelSize)
    calibArea = roiArea * imgInfo.pixelSize^2;
    areaStr = sprintf('%.4g %s%s', calibArea, char(imgInfo.pixelUnit), sq);
end

% Stats text lines
statsLines = { ...
    sprintf('ROI: [%d:%d, %d:%d]', xMin, xMax, yMin, yMax), ...
    sprintf('Size: %d x %d px', xMax - xMin + 1, yMax - yMin + 1), ...
    sprintf('Area: %s', areaStr), ...
    '', ...
    sprintf('Mean:  %.4g', roiMean), ...
    sprintf('Std:   %.4g', roiStd), ...
    sprintf('Min:   %.4g', roiMin), ...
    sprintf('Max:   %.4g', roiMax), ...
    sprintf('Range: %.4g', roiMax - roiMin)};

% Show figure with histogram and stats
roiFig = figure('Name', 'ROI Statistics', 'NumberTitle', 'off', ...
    'Units', 'pixels', 'Position', [300 250 420 380]);
roiLayout = uigridlayout(roiFig, [2 1], ...
    'RowHeight', {'1x', '1x'}, 'Padding', [10 10 10 10]);

roiAx = uiaxes(roiLayout);
roiAx.Layout.Row = 1;
histogram(roiAx, vals, 128, 'FaceColor', [0.4 0.6 0.8], 'EdgeColor', 'none');
title(roiAx, 'ROI Histogram', 'Interpreter', 'none');
xlabel(roiAx, 'Intensity');
ylabel(roiAx, 'Count');
roiAx.Box = 'on';

taStats = uitextarea(roiLayout, 'Value', statsLines, 'Editable', 'off', ...
    'FontName', 'Courier New', 'FontSize', 11);
taStats.Layout.Row = 2;

% Return stats struct
result = struct( ...
    'mean',       roiMean, ...
    'std',        roiStd, ...
    'min',        roiMin, ...
    'max',        roiMax, ...
    'area',       roiArea, ...
    'areaStr',    areaStr, ...
    'statsLines', {statsLines});
end
