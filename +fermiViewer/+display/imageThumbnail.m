function thumb = imageThumbnail(img, sz)
%IMAGETHUMBNAIL  Small truecolor thumbnail of an image struct for the list.
%
%   Syntax
%     thumb = fermiViewer.display.imageThumbnail(img)
%     thumb = fermiViewer.display.imageThumbnail(img, sz)
%
%   Inputs
%     img — one appData.images{k} struct (unified parser struct)
%     sz  — thumbnail edge length in pixels (default 16)
%
%   Outputs
%     thumb — sz×sz×3 uint8 truecolor array, or [] when the entry has no
%             displayable image data (e.g. a 1D spectrum from DM3/DM4)
%
%   Built-ins only: pixels are stride-sampled (sz² reads regardless of
%   image size — never a full-image scan) and contrast-stretched between
%   the ~2nd and ~98th percentile of the SAMPLE so hot pixels don't
%   flatten the thumbnail. Grayscale replicates to RGB; RGB channels
%   share one lo/hi so colors aren't distorted.
%
%   Examples
%     t = fermiViewer.display.imageThumbnail(appData.images{1});

    arguments
        img (1,1) struct
        sz  (1,1) double {mustBePositive} = 16
    end

    thumb = [];
    try
        ps = img.metadata.parserSpecific;
        if ~isfield(ps, 'imageData') || ~isfield(ps, 'isImage') || ~ps.isImage
            return;
        end
        px = ps.imageData.pixels;
        if isempty(px) || size(px, 1) < 2 || size(px, 2) < 2
            return;
        end

        r = round(linspace(1, size(px, 1), sz));
        c = round(linspace(1, size(px, 2), sz));
        if ~ismatrix(px) && size(px, 3) == 3
            s = double(px(r, c, :));
        else
            if ~ismatrix(px)
                px = px(:, :, 1);   % stack/cube: first slice
            end
            s = repmat(double(px(r, c)), 1, 1, 3);
        end

        % Percentile stretch on the sample (robust to hot pixels)
        v  = sort(s(:));
        n  = numel(v);
        lo = v(max(1, round(0.02 * n)));
        hi = v(min(n, round(0.98 * n)));
        if hi <= lo
            lo = v(1); hi = v(end);
        end
        if hi <= lo
            thumb = zeros(sz, sz, 3, 'uint8');
            return;
        end
        thumb = uint8(255 * min(1, max(0, (s - lo) / (hi - lo))));
    catch
        thumb = [];   % never let a malformed entry break the list rebuild
    end
end
