function buildPreferencesDialog(prefs, prefsFilePath, btnColors, hook)
%BUILDPREFERENCESDIALOG  Modal preferences editor for FermiViewer.
    arguments
        prefs         struct
        prefsFilePath char
        btnColors     struct
        hook          struct
    end

    pFig2 = uifigure('Name', 'Preferences', 'Position', [350 250 360 280]);
    pGL = uigridlayout(pFig2, [7 2], ...
        'RowHeight', {25, 25, 25, 25, 25, 25, 30}, ...
        'ColumnWidth', {160, '1x'}, ...
        'Padding', [10 10 10 10], 'RowSpacing', 4);

    lbl1 = uilabel(pGL, 'Text', 'Default Colormap:'); %#ok<NASGU>
    lbl1.Layout.Row = 1;
    ddPrefCmap = uidropdown(pGL, 'Items', {'gray','parula','hot','jet','bone'}, ...
        'Value', prefs.defaultColormap);
    ddPrefCmap.Layout.Row = 1; ddPrefCmap.Layout.Column = 2;

    lbl2 = uilabel(pGL, 'Text', 'Auto-Contrast Low %:'); %#ok<NASGU>
    lbl2.Layout.Row = 2;
    spnPrefLow = uispinner(pGL, 'Value', prefs.autoContrastLow, ...
        'Limits', [0 49], 'Step', 1);
    spnPrefLow.Layout.Row = 2; spnPrefLow.Layout.Column = 2;

    lbl3 = uilabel(pGL, 'Text', 'Auto-Contrast High %:'); %#ok<NASGU>
    lbl3.Layout.Row = 3;
    spnPrefHigh = uispinner(pGL, 'Value', prefs.autoContrastHigh, ...
        'Limits', [51 100], 'Step', 1);
    spnPrefHigh.Layout.Row = 3; spnPrefHigh.Layout.Column = 2;

    lbl4 = uilabel(pGL, 'Text', 'Export DPI:'); %#ok<NASGU>
    lbl4.Layout.Row = 4;
    spnPrefDPI = uispinner(pGL, 'Value', prefs.exportDPI, ...
        'Limits', [72 600], 'Step', 50);
    spnPrefDPI.Layout.Row = 4; spnPrefDPI.Layout.Column = 2;

    lbl5 = uilabel(pGL, 'Text', 'Pixel Inspector Size:'); %#ok<NASGU>
    lbl5.Layout.Row = 5;
    spnPrefInsp = uispinner(pGL, 'Value', prefs.pixelInspectorSize, ...
        'Limits', [3 15], 'Step', 2);
    spnPrefInsp.Layout.Row = 5; spnPrefInsp.Layout.Column = 2;

    btnRowP = uigridlayout(pGL, [1 2], 'ColumnWidth', {'1x', '1x'}, ...
        'Padding', [0 0 0 0]);
    btnRowP.Layout.Row = 7; btnRowP.Layout.Column = [1 2];

    uibutton(btnRowP, 'Text', 'Save', ...
        'BackgroundColor', btnColors.primary, 'FontColor', btnColors.fg, ...
        'ButtonPushedFcn', @(~,~) savePrefs());
    uibutton(btnRowP, 'Text', 'Cancel', ...
        'ButtonPushedFcn', @(~,~) close(pFig2));

    function savePrefs()
        newPrefs.defaultColormap    = ddPrefCmap.Value;
        newPrefs.autoContrastLow    = spnPrefLow.Value;
        newPrefs.autoContrastHigh   = spnPrefHigh.Value;
        newPrefs.exportDPI          = spnPrefDPI.Value;
        newPrefs.pixelInspectorSize = spnPrefInsp.Value;
        close(pFig2);
        hook.applyPrefs(newPrefs);
    end
end
