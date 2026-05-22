function [dist, unit, cancelled] = promptScaleBarDistance(pxLen)
%PROMPTSCALEBARDISTANCE  Modal dialog with distance field + unit dropdown.
    arguments
        pxLen  (1,1) double
    end

    UNITS = {char(197), 'nm', [char(181) 'm'], 'mm', 'cm', 'm'};

    cancelled = true;
    dist = 0;
    unit = 'nm';

    dlgFig = uifigure('Name', 'Scale Bar Distance', ...
        'Position', [400 350 320 170], ...
        'WindowStyle', 'modal', ...
        'Resize', 'off', ...
        'Color', [0.94 0.94 0.94]);

    dlgGL = uigridlayout(dlgFig, [5 2], ...
        'RowHeight', {20, 28, 28, 10, 32}, ...
        'ColumnWidth', {'1x', '1x'}, ...
        'Padding', [15 15 15 15], ...
        'RowSpacing', 6);

    lblInfo = uilabel(dlgGL, ...
        'Text', sprintf('Drawn line: %.1f px', pxLen), ...
        'FontWeight', 'bold', 'FontSize', 12);
    lblInfo.Layout.Row = 1; lblInfo.Layout.Column = [1 2];

    lblDist = uilabel(dlgGL, 'Text', 'Distance:'); %#ok<NASGU>
    lblDist.Layout.Row = 2;
    edDist = uieditfield(dlgGL, 'numeric', ...
        'Value', 1, 'Limits', [0 Inf], ...
        'LowerLimitInclusive', 'off');
    edDist.Layout.Row = 2; edDist.Layout.Column = 2;

    lblUnit = uilabel(dlgGL, 'Text', 'Unit:'); %#ok<NASGU>
    lblUnit.Layout.Row = 3;
    ddUnit = uidropdown(dlgGL, 'Items', UNITS, 'Value', 'nm');
    ddUnit.Layout.Row = 3; ddUnit.Layout.Column = 2;

    btnOK = uibutton(dlgGL, 'Text', 'OK', ...
        'ButtonPushedFcn', @(~,~) okCB());
    btnOK.Layout.Row = 5; btnOK.Layout.Column = 1;

    btnCancel = uibutton(dlgGL, 'Text', 'Cancel', ...
        'ButtonPushedFcn', @(~,~) delete(dlgFig)); %#ok<NASGU>
    btnCancel.Layout.Row = 5; btnCancel.Layout.Column = 2;

    uiwait(dlgFig);

    function okCB()
        dist = edDist.Value;
        unit = ddUnit.Value;
        cancelled = false;
        delete(dlgFig);
    end
end
