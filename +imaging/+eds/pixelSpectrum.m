function spec = pixelSpectrum(cube, rows, cols)
%PIXELSPECTRUM  Extract a single-pixel or ROI-summed EDS spectrum from a cube.
%
%   spec = imaging.eds.pixelSpectrum(cube, row, col) returns the [C x 1]
%   spectrum at pixel (row, col).
%
%   spec = imaging.eds.pixelSpectrum(cube, rows, cols) with vector ROW/COL
%   indices returns the spectrum SUMMED over all listed pixels (the pixels
%   are the element-wise pairs (rows(i), cols(i))). Pass meshgrid output for
%   a rectangular ROI.
%
%   spec = imaging.eds.pixelSpectrum(cube, mask) with a logical [H x W] MASK
%   returns the spectrum summed over all true pixels.
%
%   Returned as double. Out-of-range indices are ignored.
%
%   See also IMAGING.EDS.ELEMENTMAP, IMPORTBCF

    arguments
        cube         {mustBeNumeric}
        rows
        cols = []
    end

    sz = size(cube);
    if numel(sz) < 3
        error('imaging:eds:pixelSpectrum:notACube', 'cube must be [H x W x C].');
    end
    H = sz(1); W = sz(2); C = sz(3);

    if islogical(rows)
        mask = rows;
        if ~isequal(size(mask), [H W])
            error('imaging:eds:pixelSpectrum:badMask', ...
                'mask must be [%d x %d].', H, W);
        end
        flat = reshape(double(cube), H*W, C);
        spec = sum(flat(mask(:), :), 1).';
        return;
    end

    r = round(rows(:)); c = round(cols(:));
    if numel(r) ~= numel(c)
        error('imaging:eds:pixelSpectrum:sizeMismatch', ...
            'rows and cols must have the same number of elements.');
    end
    keep = r >= 1 & r <= H & c >= 1 & c <= W;
    r = r(keep); c = c(keep);
    if isempty(r)
        spec = zeros(C, 1);
        return;
    end
    lin = sub2ind([H W], r, c);
    flat = reshape(double(cube), H*W, C);
    spec = sum(flat(lin, :), 1).';
end
