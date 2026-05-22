function result = executeTemplateMatch(filteredPixels, x1, y1, tw, th)
%EXECUTETEMPLATEMATCH  Extract a template ROI and find matches in the image.
    arguments
        filteredPixels  double
        x1              (1,1) double
        y1              (1,1) double
        tw              (1,1) double
        th              (1,1) double
    end

    [H, W] = size(filteredPixels);
    x2 = min(x1 + tw - 1, W);
    y2 = min(y1 + th - 1, H);
    template = filteredPixels(max(1,y1):y2, max(1,x1):x2);
    if numel(template) < 4
        error('emViewer:processing:templateTooSmall', 'Template too small.');
    end

    r = imaging.templateMatch(filteredPixels, template, Threshold=0.6);

    result.nMatches  = r.nMatches;
    result.locations = r.locations;
    result.threshold = r.threshold;
    result.statusMsg = sprintf('Template match: %d matches found (threshold=%.2f)', ...
        r.nMatches, r.threshold);
end
