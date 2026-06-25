function composite = computeComposite(grayImages, channels)
%COMPUTECOMPOSITE  Additive blend of grayscale images with color channels.
%   composite = computeComposite(grayImages, channels)
%   grayImages: cell array of 2D double matrices (pre-extracted grayscale)
%   channels:   cell array of structs with .visible, .intensity, .color and
%               EITHER .imageIdx (index into grayImages) OR a direct .map
%               (2-D matrix, e.g. a cube-derived EDS element map). A non-empty
%               .map takes precedence over .imageIdx, so cube channels need no
%               entry in grayImages.
    arguments
        grayImages cell
        channels   cell
    end

    H = Inf; W = Inf;
    hasVisible = false;
    for ci = 1:numel(channels)
        ch = channels{ci};
        if ~ch.visible, continue; end
        src = channelSource(ch, grayImages);
        if isempty(src), continue; end
        [h2, w2] = size(src);
        H = min(H, h2);
        W = min(W, w2);
        hasVisible = true;
    end

    if ~hasVisible
        composite = zeros(256, 256, 3);
        return;
    end

    composite = zeros(H, W, 3);
    for ci = 1:numel(channels)
        ch = channels{ci};
        if ~ch.visible, continue; end
        gray = channelSource(ch, grayImages);
        if isempty(gray), continue; end
        gray = gray(1:H, 1:W);
        gmin = min(gray(:));
        gmax = max(gray(:));
        if gmax > gmin
            gray = (gray - gmin) / (gmax - gmin);
        else
            gray = zeros(H, W);
        end
        rgb = fermiViewer.display.applyColorChannel(gray * ch.intensity, ch.color);
        composite = composite + rgb;
    end
    composite = min(1, composite);
end


function src = channelSource(ch, grayImages)
%CHANNELSOURCE  Resolve a channel's 2-D source: direct .map first, else the
%   grayImages entry at .imageIdx. Returns [] when neither is available.
    src = [];
    if isfield(ch, 'map') && ~isempty(ch.map)
        src = double(ch.map);
        return;
    end
    if isfield(ch, 'imageIdx') && ch.imageIdx >= 1 && ch.imageIdx <= numel(grayImages)
        src = grayImages{ch.imageIdx};
    end
end
