function drawMatchedRings(targetAx, candidate, center, measuredR)
%DRAWMATCHEDRINGS  Overlay matched diffraction rings on axes.
%   drawMatchedRings(targetAx, candidate, center, measuredR)
%   candidate: struct with .matchedD, .matchedHKL
%   center:    [row, col] of pattern center
%   measuredR: vector of measured radii in pixels
    arguments
        targetAx
        candidate  struct
        center     (1,2) double
        measuredR  double
    end

    theta = linspace(0, 2*pi, 100);
    hold(targetAx, 'on');
    for k = 1:numel(candidate.matchedD)
        R = measuredR(k);
        plot(targetAx, center(2) + R*cos(theta), center(1) + R*sin(theta), 'g-', ...
            'LineWidth', 0.8, 'Tag', 'diff_ring', 'HandleVisibility', 'off');
        if ~isempty(candidate.matchedHKL) && size(candidate.matchedHKL, 1) >= k
            hkl = candidate.matchedHKL(k,:);
            text(targetAx, center(2) + R*1.05, center(1), ...
                sprintf('(%d%d%d)', hkl(1), hkl(2), hkl(3)), ...
                'Color', 'g', 'FontSize', 9, 'Tag', 'diff_ring');
        end
    end
    hold(targetAx, 'off');
end
