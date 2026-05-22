function result = selectColormapPreset()
%SELECTCOLORMAPPRESET  Present EM mode listdlg and return colormap choice.
    modes = {'SEM (gray)', 'TEM BF (gray)', 'STEM-HAADF (hot)', ...
             'STEM-ABF (bone)', 'EDS (parula)', 'Phase (hsv)', ...
             'Topography (turbo)', 'Diff. pattern (copper)'};
    cmaps = {'gray', 'gray', 'hot', 'bone', 'parula', 'hsv', 'turbo', 'copper'};
    [sel, ok] = listdlg('ListString', modes, 'SelectionMode', 'single', ...
        'PromptString', 'Select EM imaging mode:', 'ListSize', [220 120]);

    result.selected = ok;
    if ~ok, return; end
    result.cmapName  = cmaps{sel};
    result.modeName  = modes{sel};
    result.statusMsg = sprintf('Colormap: %s (%s)', cmaps{sel}, modes{sel});
end
