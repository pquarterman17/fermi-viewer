function appData = runStackMIP(appData, ui, setStatus, onContrastOp)
%RUNSTACKMIP  Maximum-intensity projection across a stack of frames.
%
%   appData = fermiViewer.analysis.runStackMIP(appData, ui, setStatus, onContrastOp)
%
%   Combines appData.stackFrames into a 3-D array, max-projects along
%   the frame axis, and replaces appData.rawPixels/filteredPixels with
%   the result. Updates the contrast slider limits and re-applies auto
%   contrast. Accept-and-return.
%
%   ui fields: .fig, .sldLow, .sldHigh

    if isempty(appData.stackFrames)
        return;
    end

    ui.fig.Pointer = 'watch'; drawnow;

    nFrames = numel(appData.stackFrames);
    [H2, W2] = size(appData.stackFrames{1});
    stack3D = zeros(H2, W2, nFrames);
    for fm = 1:nFrames
        frame = appData.stackFrames{fm};
        [fh, fw] = size(frame);
        mh = min(H2, fh); mw = min(W2, fw);
        stack3D(1:mh, 1:mw, fm) = frame(1:mh, 1:mw);
    end

    mipImg = max(stack3D, [], 3);

    appData.rawPixels      = mipImg;
    appData.filteredPixels = mipImg;

    dMin = min(mipImg(:));
    dMax = max(mipImg(:));
    if dMax == dMin, dMax = dMin + 1; end
    ui.sldLow.Limits = [dMin, dMax];
    ui.sldHigh.Limits = [dMin, dMax];

    onContrastOp('auto');
    setStatus(sprintf('MIP of %d frames', nFrames));
    ui.fig.Pointer = 'arrow';
end
