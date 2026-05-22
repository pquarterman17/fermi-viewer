function tk = uxTokens(theme)
%UXTOKENS  Centralised UI design tokens for BosonPlotter and dialogs.
%
% Returns a struct of typography, colour, padding, and spacing values
% that act as the single source of truth for the toolbox's GUI look-and-
% feel. Use these tokens instead of literal numbers in every panel/
% control construction so global rescaling is one edit.
%
% Usage
%   tk = bosonPlotter.uxTokens();         % default (dark)
%   tk = bosonPlotter.uxTokens('dark');   % explicit dark
%   tk = bosonPlotter.uxTokens('light');  % light theme
%   uilabel(g, 'Text', 'X:', 'FontSize', tk.font.label);
%   pnl.BackgroundColor = tk.color.bgPanel;
%   gl.Padding = tk.pad.normal;
%
% ── Typography (theme-independent) ─────────────────────────────────────
%
%   tk.font.title    = 12   panel titles
%   tk.font.label    = 11   form labels (right-aligned, ":" terminator)
%   tk.font.body     = 12   default control text + typed inputs
%   tk.font.caption  = 11   dense tables, footnotes, tick labels
%   tk.font.hero     = 22   figure-builder splash only
%
% ── Colour (theme-dependent) ───────────────────────────────────────────
%
% Foreground / text (semantic):
%   tk.color.text          primary text on widgets
%   tk.color.textMuted     secondary labels, captions
%   tk.color.textDim       placeholders, low-contrast hints
%   tk.color.textDisabled  greyed-out / inactive state
%   tk.color.textHighlight emphasised header text
%   tk.color.textAccent    stats / region info
%   tk.color.textOk        units row, success hints
%   tk.color.textWarn      warning text
%   tk.color.textError     error text
%
% Backgrounds:
%   tk.color.bgFigure      figure root background
%   tk.color.bgPanel       uipanel / uigridlayout
%   tk.color.bgSidebar     nav sidebar / status bar (deeper than bgPanel)
%   tk.color.bgTable       table / content-area background
%   tk.color.bgInput       edit fields, listboxes, tables
%   tk.color.bgSubtle      secondary button bg / muted surfaces
%
% Accent:
%   tk.color.accent        interactive selection / active-state highlight
%
% Compatibility alias:
%   tk.color.bgDark        — alias for bgInput (legacy name; bg of input
%                            fields. White in light mode, dark grey in
%                            dark mode. Renamed in concept; kept for
%                            existing call sites.)
%
% ── Button palette (theme-aware) ──────────────────────────────────────
%
% Button background colours. Most stay constant across themes (they're
% semantic accents, like green = primary action), but two adapt to the
% surrounding theme so they don't look out of place:
%   tk.color.btn.tool      — tertiary / utility buttons
%   tk.color.btn.fg        — text-on-button colour
%
% Static accent colours (theme-independent):
%   tk.color.btn.primary   green  — primary actions
%   tk.color.btn.accent    blue   — analysis / fit
%   tk.color.btn.danger    red    — destructive
%   tk.color.btn.export    slate  — save/export
%   tk.color.btn.external  teal   — external integrations
%   tk.color.btn.session   steel  — session save/load
%   tk.color.btn.secondary charcoal — figure export, copy
%   tk.color.btn.interact  amber  — interactive plot tools
%   tk.color.btn.animate   warm   — playback
%
% ── Padding & spacing (theme-independent) ─────────────────────────────
%
%   tk.pad.flush       = [0 0 0 0]   nested sub-grids
%   tk.pad.tight       = [2 2 2 2]   small inner panels
%   tk.pad.normal      = [4 4 4 4]   standard panel inset
%   tk.pad.comfortable = [6 6 6 6]   root grid only
%   tk.pad.barH        = [2 0 2 0]   horizontal toolbars
%
%   tk.gap.row{Tight,Comfy}   row spacing variants
%   tk.gap.col{Tight,Comfy}   column spacing variants

    if nargin < 1 || isempty(theme)
        theme = 'dark';
    end
    isDark = strcmpi(theme, 'dark');

    % ── Typography (theme-independent) ─────────────────────────────────
    tk.font.title    = 12;
    tk.font.label    = 11;
    tk.font.body     = 12;
    tk.font.caption  = 11;
    tk.font.hero     = 22;

    % ── Colour (theme-dependent) ───────────────────────────────────────
    if isDark
        % Foreground / text greys (DARK)
        tk.color.text          = [0.92 0.92 0.92];
        tk.color.textMuted     = [0.75 0.75 0.75];
        tk.color.textDim       = [0.55 0.55 0.55];
        tk.color.textDisabled  = [0.40 0.40 0.40];
        tk.color.textHighlight = [0.85 0.85 0.85];
        tk.color.textAccent    = [0.55 0.65 0.90];
        tk.color.textOk        = [0.50 0.85 0.50];
        tk.color.textWarn      = [1.00 0.65 0.20];
        tk.color.textError     = [1.00 0.45 0.45];

        % Backgrounds (DARK)
        tk.color.bgFigure      = [0.13 0.13 0.13];
        tk.color.bgPanel       = [0.18 0.18 0.18];
        tk.color.bgSidebar     = [0.10 0.10 0.10];
        tk.color.bgTable       = [0.13 0.13 0.13];
        tk.color.bgInput       = [0.17 0.17 0.17];
        tk.color.bgSubtle      = [0.28 0.28 0.28];

        % Accent (DARK)
        tk.color.accent        = [0.24 0.52 0.90];

        % Button palette: theme-aware members
        tk.color.btn.tool      = [0.28 0.28 0.28];
        tk.color.btn.fg        = [1 1 1];

        % Icon stroke colour — pale grey so Lucide outline icons are
        % readable on the dark btn.tool / panel backgrounds.
        tk.color.icon          = [0.90 0.90 0.92];
    else
        % Foreground / text greys (LIGHT)
        tk.color.text          = [0.10 0.10 0.10];
        tk.color.textMuted     = [0.40 0.40 0.40];
        tk.color.textDim       = [0.55 0.55 0.55];
        tk.color.textDisabled  = [0.70 0.70 0.70];
        tk.color.textHighlight = [0.05 0.05 0.05];
        tk.color.textAccent    = [0.20 0.30 0.65];
        tk.color.textOk        = [0.10 0.45 0.10];
        tk.color.textWarn      = [0.70 0.40 0.00];
        tk.color.textError     = [0.70 0.10 0.10];

        % Backgrounds (LIGHT)
        tk.color.bgFigure      = [0.94 0.94 0.94];
        tk.color.bgPanel       = [0.97 0.97 0.97];
        tk.color.bgSidebar     = [0.92 0.92 0.92];
        tk.color.bgTable       = [0.97 0.97 0.97];
        tk.color.bgInput       = [1.00 1.00 1.00];
        tk.color.bgSubtle      = [0.88 0.88 0.88];

        % Accent (LIGHT)
        tk.color.accent        = [0.20 0.45 0.85];

        % Button palette: theme-aware members
        tk.color.btn.tool      = [0.85 0.85 0.85];
        tk.color.btn.fg        = [1 1 1];

        % Icon stroke colour — dark slate so Lucide outline icons stay
        % readable on the light btn.tool / panel backgrounds.
        tk.color.icon          = [0.20 0.20 0.22];
    end

    % Legacy alias for the input background colour. Many call sites use
    % tk.color.bgDark — keeping it pointed at bgInput preserves behaviour
    % without forcing a mass-rename.
    tk.color.bgDark = tk.color.bgInput;

    % ── Button BG palette — semantic accents (theme-independent) ───────
    tk.color.btn.primary   = [0.18 0.52 0.18];
    tk.color.btn.accent    = [0.15 0.37 0.63];
    tk.color.btn.danger    = [0.55 0.15 0.15];
    tk.color.btn.export    = [0.18 0.32 0.52];
    tk.color.btn.external  = [0.12 0.38 0.38];
    tk.color.btn.session   = [0.22 0.32 0.42];
    tk.color.btn.secondary = [0.25 0.28 0.35];
    tk.color.btn.interact  = [0.50 0.28 0.05];
    tk.color.btn.animate   = [0.50 0.35 0.15];

    % ── Padding (theme-independent) ────────────────────────────────────
    tk.pad.flush       = [0 0 0 0];
    tk.pad.tight       = [2 2 2 2];
    tk.pad.normal      = [4 4 4 4];
    tk.pad.comfortable = [6 6 6 6];
    tk.pad.barH        = [2 0 2 0];

    % ── Spacing (theme-independent) ────────────────────────────────────
    tk.gap.row      = 2;  tk.gap.rowTight = 1;  tk.gap.rowComfy = 4;
    tk.gap.col      = 3;  tk.gap.colTight = 2;  tk.gap.colComfy = 6;

    % Record the theme so consumers can branch where needed
    tk.theme = lower(theme);
end
