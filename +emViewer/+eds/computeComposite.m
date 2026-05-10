function composite = computeComposite(grayImages, channels)
%COMPUTECOMPOSITE  Additive blend of grayscale images with color channels.
%   composite = computeComposite(grayImages, channels)
%   grayImages: cell array of 2D double matrices (pre-extracted grayscale)
%   channels:   cell array of structs with .visible, .intensity, .color, .imageIdx
    arguments
        grayImages cell
        channels   cell
    end

    H = Inf; W = Inf;
    hasVisible = false;
    for ci = 1:numel(channels)
        ch = channels{ci};
        if ~ch.visible, continue; end
        if ch.imageIdx < 1 || ch.imageIdx > numel(grayImages), continue; end
        [h2, w2] = size(grayImages{ch.imageIdx});
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
        if ch.imageIdx < 1 || ch.imageIdx > numel(grayImages), continue; end
        gray = grayImages{ch.imageIdx};
        gray = gray(1:H, 1:W);
        gmin = min(gray(:));
        gmax = max(gray(:));
        if gmax > gmin
            gray = (gray - gmin) / (gmax - gmin);
        else
            gray = zeros(H, W);
        end
        rgb = emViewer.applyColorChannel(gray * ch.intensity, ch.color);
        composite = composite + rgb;
    end
    composite = min(1, composite);
end
