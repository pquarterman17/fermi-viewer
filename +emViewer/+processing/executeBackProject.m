function result = executeBackProject(images, anglesStr, rowIdx)
%EXECUTEBACKPROJECT  Build sinogram and run back-projection preview.
    arguments
        images      cell
        anglesStr   char
        rowIdx      double
    end

    tokens = strtrim(strsplit(anglesStr, {',', ' '}));
    tokens = tokens(~cellfun('isempty', tokens));
    angles = str2double(tokens);
    if any(isnan(angles))
        error('Tilt-angle list contains one or more non-numeric entries.');
    end
    if numel(angles) ~= numel(images)
        error('Number of angles (%d) must match frames (%d).', ...
            numel(angles), numel(images));
    end

    nFrames = numel(images);
    W = size(images{1}, 2);
    sinogram = zeros(nFrames, W);
    for fi = 1:nFrames
        frame = double(images{fi});
        sinogram(fi, :) = frame(min(rowIdx, size(frame,1)), :);
    end

    res = imaging.backProject(sinogram, Angles=angles(:));

    bpFig = figure('Name', 'Back-Projection Preview', 'NumberTitle', 'off');
    subplot(1,2,1); imagesc(sinogram); axis tight;
    xlabel('Pixel'); ylabel('Angle index'); title('Sinogram');
    subplot(1,2,2); imagesc(res.reconstruction); axis equal tight;
    colormap gray; title('Reconstruction (preview)');

    result.bpResult = res;
    result.bpFig = bpFig;
    result.statusMsg = 'Back-projection preview computed.';
end
