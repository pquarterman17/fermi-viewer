function result = detectScaleBar(pixels)
%DETECTSCALEBAR  Find a scale bar in the bottom 15% of an EM image.
%   result = emViewer.calibration.detectScaleBar(pixels)
%   Returns struct with .found, .barLen, .barX1, .barX2, .barY, .msg.
    arguments
        pixels  double
    end

    [H, W] = size(pixels);
    px = double(pixels);

    stripH = max(10, round(H * 0.15));
    strip = px(H - stripH + 1 : H, :);

    stripMin = min(strip(:));
    stripMax = max(strip(:));
    stripRange = stripMax - stripMin;

    result = struct('found', false, 'barLen', 0, ...
        'barX1', 0, 'barX2', 0, 'barY', 0, 'msg', '');

    if stripRange < 1
        result.msg = 'Could not detect a scale bar (bottom strip is uniform).';
        return;
    end

    stripNorm = (strip - stripMin) / stripRange;

    bestBarLen = 0;
    bestBarRow = 0;
    bestBarX1  = 0;
    bestBarX2  = 0;

    for tryWhite = [true, false]
        if tryWhite
            bw = stripNorm > 0.85;
        else
            bw = stripNorm < 0.15;
        end

        for ri = 1:size(bw, 1)
            row = bw(ri, :);
            d = diff([0, row, 0]);
            starts = find(d == 1);
            ends   = find(d == -1) - 1;

            for si = 1:numel(starts)
                runLen = ends(si) - starts(si) + 1;
                if runLen > bestBarLen && runLen >= 20 && ...
                        runLen >= W * 0.03 && runLen <= W * 0.60
                    barHeight = 1;
                    for rr = ri+1:size(bw, 1)
                        sampCols = max(1, starts(si)+2) : min(W, ends(si)-2);
                        if numel(sampCols) < 3, break; end
                        if mean(bw(rr, sampCols)) > 0.7
                            barHeight = barHeight + 1;
                        else
                            break;
                        end
                    end
                    if barHeight >= 1 && barHeight <= 15
                        bestBarLen  = runLen;
                        bestBarRow  = ri;
                        bestBarX1   = starts(si);
                        bestBarX2   = ends(si);
                    end
                end
            end
        end
    end

    if bestBarLen == 0
        result.msg = 'Could not detect a scale bar in the bottom 15% of the image. Use "Draw on Bar" instead.';
        return;
    end

    result.found  = true;
    result.barLen = bestBarLen;
    result.barX1  = bestBarX1;
    result.barX2  = bestBarX2;
    result.barY   = H - stripH + bestBarRow;
    result.msg    = sprintf('%.0f px detected', bestBarLen);
end
