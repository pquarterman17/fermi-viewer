function result = applyPubPreset(scalebarObj, textAnnotations)
%APPLYPUBPRESET  Apply journal-specific annotation formatting.
    arguments
        scalebarObj
        textAnnotations cell
    end

    journals = {'APS (Phys Rev)', 'Nature', 'ACS (JACS/Nano)', 'Elsevier'};
    [sel, ok] = listdlg('ListString', journals, 'SelectionMode', 'single', ...
        'PromptString', 'Select journal preset:', 'ListSize', [200 80]);

    result.applied = false;
    result.statusMsg = '';
    if ~ok, return; end

    presets = [
        struct('sbFont', 10, 'sbColor', [1 1 1], 'annFont',  8);
        struct('sbFont', 12, 'sbColor', [1 1 1], 'annFont', 10);
        struct('sbFont', 10, 'sbColor', [0 0 0], 'annFont',  9);
        struct('sbFont', 11, 'sbColor', [1 1 1], 'annFont',  9);
    ];
    p = presets(sel);

    if ~isempty(scalebarObj)
        if isfield(scalebarObj, 'label') && isvalid(scalebarObj.label)
            scalebarObj.label.FontSize = p.sbFont;
            scalebarObj.label.Color    = p.sbColor;
        end
    end

    for ai = 1:numel(textAnnotations)
        ann = textAnnotations{ai};
        if isfield(ann, 'hText') && ~isempty(ann.hText) && isvalid(ann.hText)
            ann.hText.FontSize = p.annFont;
        end
    end

    result.applied = true;
    result.statusMsg = sprintf('Applied %s publication preset', journals{sel});
end
