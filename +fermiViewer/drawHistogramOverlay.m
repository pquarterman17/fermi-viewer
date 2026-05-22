function drawHistogramOverlay(histAx, lo, hi, gamma, transform, invert, rawPixels, opts)
%DRAWHISTOGRAMOVERLAY  Overlay contrast handles, transfer ramp, and clip flags on a histogram.
%   drawHistogramOverlay(histAx, lo, hi, gamma, transform, invert, rawPixels)
%   draws contrast window markers (lo/hi vertical handles, gamma midpoint
%   guide), the contrast transfer-function curve (W2 #5), and saturated-pixel
%   clipping indicator strips (W2 #7) on the FermiViewer histogram axes.
%
%   The transfer function mirrors the display pipeline in
%   `applyContrastPipeline` exactly: transform → linear stretch over [lo,hi]
%   → gamma → invert.
%
%   Inputs:
%     histAx    — uiaxes (must already contain a bar plot of rawPixels)
%     lo, hi    — contrast window low/high in raw data units
%     gamma     — gamma exponent (>=1 darkens midtones, <1 brightens)
%     transform — 'linear' | 'log' | 'sqrt' | 'power'
%     invert    — logical: invert output (1 - displayValue)
%     rawPixels — raw pixel data (any shape) used for clipping fractions
%     opts      — optional struct: .showRamp (default true),
%                                   .showClipping (default true),
%                                   .nRampSamples (default 128)
%
%   Notes:
%     - All drawn objects carry Tag='histMarker' for unified cleanup.
%     - Caller is responsible for calling
%       `delete(findobj(histAx,'Tag','histMarker'))` *before* invoking this
%       function.
%     - When opts.showClipping is true and a tail's clip fraction exceeds 1%,
%       a tinted strip is drawn at that edge with height proportional to the
%       fraction (capped at 25% of axes height).

    arguments
        histAx                                  matlab.ui.control.UIAxes
        lo                              (1,1)   double
        hi                              (1,1)   double
        gamma                           (1,1)   double {mustBePositive}
        transform                       (1,:)   char
        invert                          (1,1)   logical
        rawPixels                                       % numeric, any shape
        opts.showRamp                   (1,1)   logical = true
        opts.showClipping               (1,1)   logical = true
        opts.nRampSamples               (1,1)   double  {mustBePositive} = 128
    end

    if isempty(histAx) || ~isvalid(histAx), return; end

    yLims = histAx.YLim;
    xLims = histAx.XLim;
    if yLims(2) <= 0, yLims(2) = 1; end
    if xLims(2) <= xLims(1), return; end

    hold(histAx, 'on');
    cleanup = onCleanup(@() hold(histAx, 'off'));

    % ── Tinted contrast window patch ────────────────────────────────────
    patch(histAx, [lo lo hi hi], [0 yLims(2) yLims(2) 0], [0.3 0.9 0.3], ...
        'FaceAlpha', 0.12, 'EdgeColor', 'none', ...
        'Tag', 'histMarker', 'HitTest', 'off', 'PickableParts', 'none');

    % ── Lo / Hi handle lines ────────────────────────────────────────────
    plot(histAx, [lo lo], yLims, '-', ...
        'Color', [0 0.9 1], 'LineWidth', 2.5, ...
        'Tag', 'histMarker', 'HitTest', 'off');
    plot(histAx, [hi hi], yLims, '-', ...
        'Color', [1 0.2 1], 'LineWidth', 2.5, ...
        'Tag', 'histMarker', 'HitTest', 'off');

    % ── Gamma midpoint guide ────────────────────────────────────────────
    if gamma ~= 1.0 && hi > lo
        midX = lo + (hi - lo) * 0.5^(1/gamma);
        plot(histAx, [midX midX], yLims, '--', ...
            'Color', [1 0.8 0], 'LineWidth', 1.5, ...
            'Tag', 'histMarker', 'HitTest', 'off');
    end

    % ── Transfer-function ramp (W2 #5) ──────────────────────────────────
    if opts.showRamp && hi > lo
        xs = linspace(xLims(1), xLims(2), opts.nRampSamples);
        ys = transferFunction(xs, lo, hi, gamma, transform, invert);
        plot(histAx, xs, ys * yLims(2), '-', ...
            'Color', [1 1 1 0.85], 'LineWidth', 1.5, ...
            'Tag', 'histMarker', 'HitTest', 'off');
    end

    % ── Clipping indicators (W2 #7) ─────────────────────────────────────
    if opts.showClipping && ~isempty(rawPixels)
        v = rawPixels(:);
        % Subsample large images so drag stays smooth on 4k+ frames.
        maxN = 2e5;
        if numel(v) > maxN
            stride = ceil(numel(v) / maxN);
            v = v(1:stride:end);
        end
        v = double(v);
        v = v(isfinite(v));
        if ~isempty(v)
            n = numel(v);
            fLo = nnz(v < lo) / n;   % saturated dark
            fHi = nnz(v > hi) / n;   % saturated bright
            stripFrac = 0.02 * (xLims(2) - xLims(1));   % 2% of x-range
            maxBarH   = 0.6 * yLims(2);
            % sqrt scaling so a small clip fraction (1-5%) is still visible
            % without dominating the histogram when fully clipped.
            if fLo >= 0.01
                h = sqrt(min(fLo, 1)) * maxBarH;
                xL = xLims(1);
                patch(histAx, [xL xL xL+stripFrac xL+stripFrac], ...
                              [0 h h 0], [0.95 0.25 0.2], ...
                    'EdgeColor', 'none', 'FaceAlpha', 0.85, ...
                    'Tag', 'histMarker', 'HitTest', 'off', ...
                    'PickableParts', 'none');
            end
            if fHi >= 0.01
                h = sqrt(min(fHi, 1)) * maxBarH;
                xR = xLims(2);
                patch(histAx, [xR-stripFrac xR-stripFrac xR xR], ...
                              [0 h h 0], [1 0.55 0.1], ...
                    'EdgeColor', 'none', 'FaceAlpha', 0.85, ...
                    'Tag', 'histMarker', 'HitTest', 'off', ...
                    'PickableParts', 'none');
            end
        end
    end
end

% ════════════════════════════════════════════════════════════════════════
%  HELPER: transferFunction — Mirror applyContrastPipeline mapping
% ════════════════════════════════════════════════════════════════════════
function out = transferFunction(x, lo, hi, gamma, transform, invert)
% Apply contrast transform → linear stretch → gamma → invert. Output in [0,1].
    x = double(x);
    switch transform
        case 'log'
            x  = log1p(max(x,  -1));
            lo = log1p(max(lo, -1));
            hi = log1p(max(hi, -1));
        case 'sqrt'
            x  = sqrt(max(x,  0));
            lo = sqrt(max(lo, 0));
            hi = sqrt(max(hi, 0));
        case 'power'
            x  = max(x,  0).^0.3;
            lo = max(lo, 0)^0.3;
            hi = max(hi, 0)^0.3;
        % 'linear' — no-op
    end
    if hi <= lo, hi = lo + 1; end
    out = (x - lo) / (hi - lo);
    out = max(0, min(1, out));
    if gamma ~= 1.0
        out = out .^ gamma;
    end
    if invert
        out = 1 - out;
    end
end
