function s = buildStatusBar(parent)
%BUILDSTATUSBAR  Build the bottom status-bar grid + labels for FermiViewer.
%
% Syntax
%   s = fermiViewer.buildStatusBar(parent)
%
% Inputs
%   parent   rootGL uigridlayout; the status bar takes row 3, column 1.
%
% Output
%   s   struct of handles consumed by FermiViewer.m / updateStatusBar /
%       applyTheme:
%         .statusGL          — the [1 8] grid
%         .lblStatusDims     — "W x H px"            (col 1)
%         .lblStatusBits     — "N-bit"               (col 2)
%         .lblStatusPixSize  — "0.5 nm/px"/uncal     (col 3)
%         .lblStatusCount    — "3 / 12" image index  (col 4)
%         .lblStatusZoom     — "150%" view zoom      (col 5)
%         .lblStatusMouse    — cursor x/y/value      (col 6, stretches)
%         .lblStatusMode     — amber "● CROP" etc.   (col 7)
%         .lblLoadStatus     — blue I/O indicator    (col 8)
%
% Colours here are the muted literals; applyTheme re-tints them per theme.
% Extracted from FermiViewer.m inline construction to keep the orchestrator
% under its size ratchet (see CLAUDE.md "Size ratchet").

    dimFG = [0.45 0.45 0.45];

    s.statusGL = uigridlayout(parent, [1 8], ...
        'ColumnWidth', {110, 60, 100, 'fit', 'fit', '1x', 'fit', 'fit'}, ...
        'RowHeight',   {'1x'}, ...
        'Padding',     [6 0 6 0], ...
        'ColumnSpacing', 10);
    s.statusGL.Layout.Row = 3;
    s.statusGL.Layout.Column = 1;

    s.lblStatusDims = uilabel(s.statusGL, 'Text', '-- x -- px', ...
        'FontSize', 11, 'FontColor', dimFG);
    s.lblStatusDims.Layout.Row = 1; s.lblStatusDims.Layout.Column = 1;

    s.lblStatusBits = uilabel(s.statusGL, 'Text', '--bit', ...
        'FontSize', 11, 'FontColor', dimFG);
    s.lblStatusBits.Layout.Row = 1; s.lblStatusBits.Layout.Column = 2;

    s.lblStatusPixSize = uilabel(s.statusGL, 'Text', 'uncalibrated', ...
        'FontSize', 11, 'FontColor', dimFG);
    s.lblStatusPixSize.Layout.Row = 1; s.lblStatusPixSize.Layout.Column = 3;

    % Image position in the loaded list ("3 / 12"); set by updateStatusBar.
    s.lblStatusCount = uilabel(s.statusGL, 'Text', '', ...
        'FontSize', 11, 'FontColor', dimFG);
    s.lblStatusCount.Layout.Row = 1; s.lblStatusCount.Layout.Column = 4;

    % View zoom ("150%"); refreshed live by an XLim listener via
    % fermiViewer.display.updateZoomReadout (covers zoom/pan/fit/reset).
    s.lblStatusZoom = uilabel(s.statusGL, 'Text', '', ...
        'FontSize', 11, 'FontColor', dimFG);
    s.lblStatusZoom.Layout.Row = 1; s.lblStatusZoom.Layout.Column = 5;

    s.lblStatusMouse = uilabel(s.statusGL, 'Text', '', ...
        'FontSize', 11, 'FontColor', dimFG);
    s.lblStatusMouse.Layout.Row = 1; s.lblStatusMouse.Layout.Column = 6;

    % Capture-mode readout — amber when a capture mode is active (mirrors the
    % redesign's status-bar mode indicator). Populated by updateStatusBar.
    s.lblStatusMode = uilabel(s.statusGL, 'Text', '', ...
        'FontSize', 11, 'FontWeight', 'bold', ...
        'FontColor', [0.95 0.70 0.23], 'HorizontalAlignment', 'right');
    s.lblStatusMode.Layout.Row = 1; s.lblStatusMode.Layout.Column = 7;

    % Discreet loading indicator — appears during file I/O, hidden otherwise.
    s.lblLoadStatus = uilabel(s.statusGL, 'Text', '', ...
        'FontSize', 11, 'FontColor', [0.35 0.65 0.85], ...
        'HorizontalAlignment', 'right');
    s.lblLoadStatus.Layout.Row = 1; s.lblLoadStatus.Layout.Column = 8;
end
