function tf = figureCaptureAvailable()
%FIGURECAPTUREAVAILABLE  True if this MATLAB/env can capture a figure image.
%
%   tf = fermiViewer.chrome.figureCaptureAvailable()
%
%   Cached one-time runtime probe. Capturing a figure (exportapp / getframe /
%   print) needs a working renderer. On headless CI with older MATLAB
%   (roughly < R2025a) these error with "Running using -nodisplay ... is not
%   supported" or "Functionality not supported with figures created with the
%   figure function"; newer MATLAB renders headless fine. The product's
%   minimum is R2022b, so visual/snapshot TESTS must skip gracefully when
%   this returns false — exercising logic on every version while running the
%   pixel-capture assertions only where the environment supports them.
%
%   Probe (not a version number) so it adapts to the actual environment:
%   attempt a tiny exportapp to a temp file; success => true. Cached for the
%   session via a persistent.

    persistent cached
    if ~isempty(cached)
        tf = cached;
        return;
    end

    tf = false;
    try
        f = uifigure('Visible', 'off');
        cleanup = onCleanup(@() delete(f)); %#ok<NASGU>
        tmp = [tempname '.png'];
        exportapp(f, tmp);
        if isfile(tmp)
            delete(tmp);
            tf = true;
        end
    catch
        tf = false;
    end
    cached = tf;
end
