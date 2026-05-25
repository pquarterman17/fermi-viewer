function p = buttonPalette()
%BUTTONPALETTE  Shared button color palette for all GUIs.
%
%   p = fermiViewer.chrome.buttonPalette()
%
%   Returns a struct with named RGB color fields for consistent button
%   styling across BosonPlotter, DiraCulator, and
%   DataWorkspace.
%
%   Fields:
%       p.primary    — [0.18 0.52 0.18]  green, primary actions (Add, Apply)
%       p.accent     — [0.15 0.37 0.63]  blue, analysis/fit actions
%       p.danger     — [0.55 0.15 0.15]  red, destructive (Remove, Clear)
%       p.export     — [0.18 0.32 0.52]  slate, save/export operations
%       p.tool       — [0.28 0.28 0.28]  gray, secondary tools & utilities
%       p.secondary  — [0.25 0.28 0.35]  charcoal, figure export, copy
%       p.fg         — [1 1 1]           white text on dark buttons
%
%   Example:
%       p = fermiViewer.chrome.buttonPalette();
%       uibutton(gl, 'Text', 'Apply', ...
%           'BackgroundColor', p.primary, 'FontColor', p.fg);

    persistent cached
    if ~isempty(cached)
        p = cached;
        return;
    end

    % Aligned 2026-05-25 with the Variant A redesign palette (see
    % +fermiViewer/+chrome/uxTokens.m). `tool` tracks the new neutral
    % surface; semantic accents (primary/accent/export) unchanged.
    p.primary   = [0.18 0.52 0.18];   % green
    p.accent    = [0.15 0.37 0.63];   % blue
    p.danger    = [0.62 0.20 0.16];   % red (slightly brighter, redesign danger)
    p.export    = [0.18 0.32 0.52];   % slate
    p.tool      = [0.30 0.31 0.34];   % neutral button — light enough that the
                                      % dark (#333338) Lucide icons stay visible
    p.secondary = [0.25 0.28 0.35];   % charcoal
    p.fg        = [1.00 1.00 1.00];   % white

    cached = p;
end
