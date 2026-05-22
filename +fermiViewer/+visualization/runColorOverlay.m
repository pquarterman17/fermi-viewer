function runColorOverlay(fig, images, setStatus)
%RUNCOLOROVERLAY  Two-image color blend workflow with dialog + dispatch.
%
%   fermiViewer.visualization.runColorOverlay(fig, images, setStatus)
%
%   Prompts the user for two image indices, their colormaps, and a blend
%   alpha. Then calls fermiViewer.visualization.displayColorOverlay with
%   the converted greyscale planes. Sets status on success or warns on
%   invalid input.
%
%   INPUTS:
%       fig       - parent uifigure (alert target)
%       images    - cell array of parser data structs (appData.images)
%       setStatus - status-bar callback @(msg)

    if numel(images) < 2
        fermiViewer.chrome.quietAlert(fig, 'Need at least 2 images for color overlay.', ...
            'Color Overlay', 'Icon', 'warning');
        return;
    end
    names = cell(1, numel(images));
    for ki = 1:numel(images)
        [~, fn, fe] = fileparts(images{ki}.metadata.source);
        names{ki} = sprintf('[%d] %s%s', ki, fn, fe);
    end
    answer = inputdlg( ...
        {'Image A index (1-based):', ...
         'Image A colormap (red, green, blue, cyan, magenta, yellow):', ...
         'Image B index (1-based):', 'Image B colormap:', ...
         'Blend alpha (0-1, for image B):'}, ...
        'Color Overlay', [1 50], {'1', 'green', '2', 'magenta', '0.5'});
    if isempty(answer), return; end
    idxA = str2double(answer{1}); cmapA = lower(strtrim(answer{2}));
    idxB = str2double(answer{3}); cmapB = lower(strtrim(answer{4}));
    alpha = max(0, min(1, str2double(answer{5})));
    if isnan(idxA) || isnan(idxB) || idxA < 1 || idxB < 1 || ...
            idxA > numel(images) || idxB > numel(images)
        fermiViewer.chrome.quietAlert(fig, 'Invalid image indices.', 'Error', 'Icon', 'error');
        return;
    end
    imgA = fermiViewer.eds.getGrayscale(images{round(idxA)});
    imgB = fermiViewer.eds.getGrayscale(images{round(idxB)});
    r = fermiViewer.visualization.displayColorOverlay( ...
        imgA, imgB, cmapA, cmapB, alpha, names{round(idxA)}, names{round(idxB)});
    setStatus(r.statusMsg);
end
