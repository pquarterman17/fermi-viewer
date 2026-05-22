function result = executeRotateFlip(rawPixels, filteredPixels, mode)
%EXECUTEROTATEFLIP  Apply rotation or flip to both raw and filtered pixel buffers.
    arguments
        rawPixels       double
        filteredPixels  double
        mode            char
    end

    switch mode
        case 'rot90cw'
            rawPixels      = rot90(rawPixels, -1);
            filteredPixels = rot90(filteredPixels, -1);
            msg = 'Rotated 90° CW';
        case 'rot90ccw'
            rawPixels      = rot90(rawPixels, 1);
            filteredPixels = rot90(filteredPixels, 1);
            msg = 'Rotated 90° CCW';
        case 'fliph'
            rawPixels      = fliplr(rawPixels);
            filteredPixels = fliplr(filteredPixels);
            msg = 'Flipped horizontally';
        case 'flipv'
            rawPixels      = flipud(rawPixels);
            filteredPixels = flipud(filteredPixels);
            msg = 'Flipped vertically';
        otherwise
            result = struct('rawPixels', rawPixels, 'filteredPixels', filteredPixels, ...
                'msg', '', 'applied', false);
            return;
    end

    result = struct('rawPixels', rawPixels, 'filteredPixels', filteredPixels, ...
        'msg', msg, 'applied', true);
end
