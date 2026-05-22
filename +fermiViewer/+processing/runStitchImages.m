function runStitchImages(fig, images, setStatus)
%RUNSTITCHIMAGES  Prompt for layout, stitch the loaded images.

    if numel(images) < 2
        fermiViewer.chrome.quietAlert(fig, 'Need at least 2 images to stitch.', 'Stitch', 'Icon', 'warning'); return;
    end
    layouts = {'horizontal', 'vertical', 'auto'};
    [sel, ok] = listdlg('ListString', layouts, 'SelectionMode', 'single', ...
        'PromptString', 'Layout direction:', 'ListSize', [150 60]);
    if ~ok, return; end
    fig.Pointer = 'watch'; drawnow;
    try
        r = fermiViewer.processing.executeStitchImages(images, layouts{sel});
        fig.Pointer = 'arrow';
        setStatus(r.statusMsg);
    catch ME
        fig.Pointer = 'arrow';
        fermiViewer.chrome.quietAlert(fig, sprintf('Stitch failed:\n%s', ME.message), 'Error', 'Icon', 'error');
    end
end
