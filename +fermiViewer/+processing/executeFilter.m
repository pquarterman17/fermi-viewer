function result = executeFilter(filteredPixels, filterType, params)
%EXECUTEFILTER  Apply a named filter with validated parameters.
%   result = emViewer.processing.executeFilter(pixels, 'gaussian', struct('sigma', 1.5))
%   result = emViewer.processing.executeFilter(pixels, 'median', struct('windowSize', 3))
%   result = emViewer.processing.executeFilter(pixels, 'clahe', struct('tileSize', 64, 'clipLimit', 3))
%
%   Returns struct with .pixels (filtered), .statusMsg, .applied (logical).
    arguments
        filteredPixels  double
        filterType      char
        params          struct
    end

    switch lower(filterType)
        case 'gaussian'
            sigma = params.sigma;
            result.pixels = imaging.applyGaussian(filteredPixels, Sigma=sigma);
            result.statusMsg = sprintf('Gaussian filter applied (sigma = %.2g px)', sigma);

        case 'median'
            wSize = params.windowSize;
            result.pixels = imaging.applyMedian(filteredPixels, WindowSize=wSize);
            result.statusMsg = sprintf('Median filter applied (%dx%d window)', wSize, wSize);

        case 'clahe'
            result.pixels = emViewer.processing.applyCLAHE( ...
                filteredPixels, params.tileSize, params.clipLimit);
            result.statusMsg = sprintf('CLAHE applied (tile=%d, clip=%.1f)', ...
                params.tileSize, params.clipLimit);

        otherwise
            error('emViewer:processing:unknownFilter', ...
                'Unknown filter type "%s".', filterType);
    end

    result.applied = true;
end
