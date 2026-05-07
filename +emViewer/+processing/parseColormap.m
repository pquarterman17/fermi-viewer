function cmap = parseColormap(stopsStr)
%PARSECOLORMAP  Parse color stop string into a 256x3 colormap.
%   cmap = parseColormap('0 0 0; 1 0 0; 1 1 1') returns a 256x3 matrix
%   interpolating black → red → white.
    arguments
        stopsStr    char
    end

    rawRows = strsplit(strtrim(stopsStr), ';');
    stops = zeros(numel(rawRows), 3);
    for rr = 1:numel(rawRows)
        rowVals = str2double(strsplit(strtrim(rawRows{rr})));
        if numel(rowVals) ~= 3 || any(isnan(rowVals))
            error('parseColormap:badInput', ...
                'Row %d is not 3 valid numbers.', rr);
        end
        stops(rr, :) = rowVals;
    end
    if size(stops, 1) < 2
        error('parseColormap:tooFew', ...
            'Need at least 2 color stops.');
    end
    stops = max(0, min(1, stops));
    nStops = size(stops, 1);
    cmap = zeros(256, 3);
    for ch = 1:3
        cmap(:, ch) = interp1(linspace(0, 1, nStops), stops(:, ch), ...
            linspace(0, 1, 256), 'linear');
    end
end
