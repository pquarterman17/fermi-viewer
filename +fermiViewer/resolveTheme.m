function out = resolveTheme(value)
%RESOLVETHEME  Resolve a theme preference (Dark/Light/Auto) to a concrete
%   'Dark' or 'Light' string. Used by GUIs that need an actual theme to
%   apply at any moment — `'Auto'` means "follow the OS appearance" and
%   is resolved here.
%
% Syntax
%   t = bosonPlotter.resolveTheme()            % reads themePref, resolves Auto
%   t = bosonPlotter.resolveTheme('Auto')      % resolves Auto → Dark/Light
%   t = bosonPlotter.resolveTheme('Dark')      % passthrough
%
% Resolution order for 'Auto':
%   1. MATLAB R2025a+ — use settings('matlab').appearance.MATLABTheme
%      (built-in OS-following appearance) when available.
%   2. Windows fallback — read HKCU\…\Themes\Personalize\AppsUseLightTheme.
%   3. macOS fallback — `defaults read -g AppleInterfaceStyle`.
%   4. Final fallback — return 'Dark' (the toolbox's historical default).
%
% Failure mode: every probe is wrapped in try/catch; on any error this
% function returns 'Dark' rather than throwing.

    if nargin < 1 || isempty(value)
        value = bosonPlotter.themePref('read');
    end
    value = char(value);
    if strcmpi(value, 'Dark') || strcmpi(value, 'Light')
        if strcmpi(value, 'Dark')
            out = 'Dark';
        else
            out = 'Light';
        end
        return;
    end
    if ~strcmpi(value, 'Auto')
        out = 'Dark';
        return;
    end

    % ── 'Auto' resolution ───────────────────────────────────────────────
    out = '';

    % 1. MATLAB R2025a+ MATLABTheme setting (best signal — already follows
    %    OS unless the user pinned MATLAB to a specific theme).
    try
        s = settings;
        if isprop(s, 'matlab') && isprop(s.matlab, 'appearance') ...
                && isprop(s.matlab.appearance, 'MATLABTheme')
            t = s.matlab.appearance.MATLABTheme.ActiveValue;
            if ischar(t) || isstring(t)
                t = char(t);
                if strcmpi(t, 'Dark')
                    out = 'Dark';
                elseif strcmpi(t, 'Light')
                    out = 'Light';
                end
            end
        end
    catch
    end
    if ~isempty(out), return; end

    % 2. Windows: registry probe.
    if ispc
        try
            [status, result] = system( ...
                'reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v AppsUseLightTheme');
            if status == 0
                tok = regexp(result, 'AppsUseLightTheme\s+REG_DWORD\s+0x([0-9a-fA-F]+)', 'tokens', 'once');
                if ~isempty(tok)
                    if strcmp(tok{1}, '0')
                        out = 'Dark';
                    else
                        out = 'Light';
                    end
                end
            end
        catch
        end
    end
    if ~isempty(out), return; end

    % 3. macOS: `defaults read -g AppleInterfaceStyle` returns 'Dark' iff dark
    %    mode is on, else exits non-zero.
    if ismac
        try
            [status, result] = system('defaults read -g AppleInterfaceStyle 2>/dev/null');
            if status == 0 && contains(strtrim(result), 'Dark', 'IgnoreCase', true)
                out = 'Dark';
            else
                out = 'Light';
            end
        catch
        end
    end
    if ~isempty(out), return; end

    % 4. Linux / unknown — historical default.
    out = 'Dark';
end
