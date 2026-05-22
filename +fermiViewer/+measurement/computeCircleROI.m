function result = computeCircleROI(pixels, cx, cy, radius)
%COMPUTECIRCLEROI  Compute statistics over a circular ROI.
    arguments
        pixels  double
        cx      (1,1) double
        cy      (1,1) double
        radius  (1,1) double
    end

    [H, W] = size(pixels);
    [XX, YY] = meshgrid(1:W, 1:H);
    mask = (XX - cx).^2 + (YY - cy).^2 <= radius^2;
    vals = pixels(mask);

    result.empty = isempty(vals);
    if result.empty
        result.mean = NaN;
        result.std  = NaN;
        result.min  = NaN;
        result.max  = NaN;
        result.area = 0;
        result.statusMsg = 'No pixels in circle ROI';
        return;
    end
    result.mean    = mean(vals);
    result.std     = std(vals);
    result.min     = min(vals);
    result.max     = max(vals);
    result.area    = numel(vals);
    result.statusMsg = sprintf( ...
        'Circle ROI (r=%.0fpx): mean=%.1f std=%.1f min=%.0f max=%.0f area=%d px', ...
        radius, result.mean, result.std, result.min, result.max, result.area);
end
