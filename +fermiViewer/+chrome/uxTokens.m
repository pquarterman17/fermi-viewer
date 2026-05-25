function tk = uxTokens(theme)
%UXTOKENS  Centralised UI design tokens for FermiViewer and dialogs.
%
% Returns a struct of typography, colour, padding, and spacing values
% that act as the single source of truth for the toolbox's GUI look-and-
% feel. Use these tokens instead of literal numbers in every panel/
% control construction so global rescaling is one edit.
%
% Palette refreshed 2026-05-25 from the "Variant A" redesign
% (design/2026-05-redesign/handoff.html). The redesign specified an
% oklch() neutral-cool palette; the RGB triplets below are the [0,1]
% conversions. The EXISTING token names (tk.color.bgPanel, tk.font.label,
% …) are preserved so no call site breaks; the redesign's new roles
% (border, accentBg, capture, axesBg, hover/active surfaces) are added.
%
% Usage
%   tk = fermiViewer.chrome.uxTokens();         % default (dark)
%   tk = fermiViewer.chrome.uxTokens('dark');   % explicit dark
%   tk = fermiViewer.chrome.uxTokens('light');  % light theme
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
%   tk.color.text          primary text on widgets        (redesign: text)
%   tk.color.textMuted     secondary labels, captions      (redesign: textDim)
%   tk.color.textDim       placeholders, low-contrast hints (redesign: textFaint)
%   tk.color.textDisabled  greyed-out / inactive state
%   tk.color.textHighlight emphasised header text
%   tk.color.textAccent    stats / region info
%   tk.color.textOk        units row, success hints
%   tk.color.textWarn      warning text (== capture amber)
%   tk.color.textError     error text (== danger)
%
% Backgrounds:
%   tk.color.bgFigure      figure root background          (redesign: surface0)
%   tk.color.bgPanel       uipanel / uigridlayout / header (redesign: surface1)
%   tk.color.bgSidebar     nav sidebar / image list (deepest, == app bg)
%   tk.color.bgTable       table / content-area background
%   tk.color.bgInput       edit fields, listboxes          (redesign: surface1)
%   tk.color.bgSubtle      secondary surface               (redesign: surface2)
%   tk.color.bgHover       hover state                     (redesign: surface2)
%   tk.color.bgActive      pressed / active state          (redesign: surface3)
%
% Borders (NEW — redesign hairlines):
%   tk.color.borderSoft    hairlines between rows / groups
%   tk.color.border        stronger dividers
%
% Accent / status:
%   tk.color.accent        interactive selection / primary action / active
%   tk.color.accentBg      selected-row tint (pre-composited, no alpha)
%   tk.color.capture       capture-mode amber (banner, active measurement tile)
%   tk.color.captureBg     capture-mode banner background (pre-composited)
%   tk.color.danger        destructive accent (brighter than btn.danger)
%   tk.color.axesBg        uiaxes background — STAYS DARK in both themes
%                          (microscopy images need a black backdrop)
%
% Compatibility alias:
%   tk.color.bgDark        — alias for bgInput (legacy name).
%
% ── Button palette (theme-aware) ──────────────────────────────────────
%   tk.color.btn.tool      — tertiary / utility buttons (neutral surface)
%   tk.color.btn.fg        — text-on-button colour
%   tk.color.btn.primary   green  — primary actions
%   tk.color.btn.accent    blue   — analysis / fit
%   tk.color.btn.danger    red    — destructive
%   tk.color.btn.export    slate  — save/export
%   tk.color.btn.external  teal · session steel · secondary charcoal
%   tk.color.btn.interact  amber  · animate warm
%
% ── Padding & spacing (theme-independent) ─────────────────────────────
%   tk.pad.{flush,tight,normal,comfortable,barH}
%   tk.gap.{row,rowTight,rowComfy,col,colTight,colComfy}

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
        % Foreground / text (DARK) — redesign text/textDim/textFaint
        tk.color.text          = [0.937 0.945 0.953];
        tk.color.textMuted     = [0.642 0.659 0.677];
        tk.color.textDim       = [0.434 0.452 0.471];
        tk.color.textDisabled  = [0.330 0.345 0.360];
        tk.color.textHighlight = [0.970 0.972 0.980];
        tk.color.textAccent    = [0.550 0.720 0.950];
        tk.color.textOk        = [0.500 0.850 0.500];
        tk.color.textWarn      = [0.951 0.704 0.226];
        tk.color.textError     = [0.890 0.421 0.302];

        % Backgrounds (DARK) — redesign surface0..3
        tk.color.bgFigure      = [0.121 0.131 0.144];
        tk.color.bgPanel       = [0.158 0.169 0.182];
        tk.color.bgSidebar     = [0.121 0.131 0.144];
        tk.color.bgTable       = [0.121 0.131 0.144];
        tk.color.bgInput       = [0.158 0.169 0.182];
        tk.color.bgSubtle      = [0.190 0.202 0.215];
        tk.color.bgHover       = [0.190 0.202 0.215];
        tk.color.bgActive      = [0.229 0.242 0.257];

        % Borders (DARK)
        tk.color.borderSoft    = [0.233 0.247 0.262];
        tk.color.border        = [0.292 0.308 0.325];

        % Accent / status (DARK)
        tk.color.accent        = [0.345 0.689 0.911];
        tk.color.accentBg      = [0.075 0.222 0.345];
        tk.color.capture       = [0.951 0.704 0.226];
        tk.color.captureBg     = [0.290 0.215 0.075];
        tk.color.danger        = [0.890 0.421 0.302];

        % Button palette: theme-aware members (DARK). btn.tool is a flat dark
        % surface; the toolbar icons are now light (recoloured), so they pop.
        tk.color.btn.tool      = [0.210 0.220 0.250];
        tk.color.btn.fg        = [1 1 1];
        tk.color.icon          = [0.90 0.90 0.92];
    else
        % Foreground / text (LIGHT)
        tk.color.text          = [0.10 0.10 0.10];
        tk.color.textMuted     = [0.40 0.40 0.42];
        tk.color.textDim       = [0.55 0.56 0.58];
        tk.color.textDisabled  = [0.70 0.70 0.72];
        tk.color.textHighlight = [0.05 0.05 0.05];
        tk.color.textAccent    = [0.18 0.40 0.70];
        tk.color.textOk        = [0.10 0.45 0.10];
        tk.color.textWarn      = [0.70 0.45 0.05];
        tk.color.textError     = [0.75 0.20 0.12];

        % Backgrounds (LIGHT)
        tk.color.bgFigure      = [0.940 0.940 0.950];
        tk.color.bgPanel       = [0.980 0.980 0.990];
        tk.color.bgSidebar     = [0.920 0.920 0.930];
        tk.color.bgTable       = [0.980 0.980 0.990];
        tk.color.bgInput       = [1.000 1.000 1.000];
        tk.color.bgSubtle      = [0.900 0.900 0.910];
        tk.color.bgHover       = [0.900 0.900 0.910];
        tk.color.bgActive      = [0.840 0.860 0.900];

        % Borders (LIGHT)
        tk.color.borderSoft    = [0.820 0.820 0.840];
        tk.color.border        = [0.700 0.710 0.740];

        % Accent / status (LIGHT)
        tk.color.accent        = [0.200 0.500 0.850];
        tk.color.accentBg      = [0.800 0.880 0.970];
        tk.color.capture       = [0.850 0.550 0.100];
        tk.color.captureBg     = [1.000 0.930 0.780];
        tk.color.danger        = [0.800 0.250 0.180];

        % Button palette: theme-aware members (LIGHT)
        tk.color.btn.tool      = [0.85 0.85 0.86];
        tk.color.btn.fg        = [1 1 1];
        tk.color.icon          = [0.20 0.20 0.22];
    end

    % uiaxes background stays dark in BOTH themes (open question 5 — microscopy
    % images need a black backdrop even in light mode).
    tk.color.axesBg = [0.062 0.068 0.075];

    % Legacy alias for the input background colour.
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
