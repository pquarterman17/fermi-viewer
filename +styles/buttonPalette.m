function p = buttonPalette()
%BUTTONPALETTE  Shared button color palette for all GUIs.
%
%   p = styles.buttonPalette()
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
%       p = styles.buttonPalette();
%       uibutton(gl, 'Text', 'Apply', ...
%           'BackgroundColor', p.primary, 'FontColor', p.fg);

    persistent cached
    if ~isempty(cached)
        p = cached;
        return;
    end

    p.primary   = [0.18 0.52 0.18];   % green
    p.accent    = [0.15 0.37 0.63];   % blue
    p.danger    = [0.55 0.15 0.15];   % red
    p.export    = [0.18 0.32 0.52];   % slate
    p.tool      = [0.28 0.28 0.28];   % gray
    p.secondary = [0.25 0.28 0.35];   % charcoal
    p.fg        = [1.00 1.00 1.00];   % white

    cached = p;
end
