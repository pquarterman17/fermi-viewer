function out = themePref(action, value)
%THEMEPREF  Read or write the persisted theme preference (Dark/Light/Auto).
%
% Syntax
%   t = bosonPlotter.themePref('read')          % returns 'Dark' | 'Light' | 'Auto'
%   bosonPlotter.themePref('write', 'Auto')     % persists choice
%
% 'Auto' means "follow OS appearance"; resolve via bosonPlotter.resolveTheme
% to get a concrete 'Dark'/'Light' value at apply time.
%
% Behaviour
%   The preference is stored as a tiny .mat file in `prefdir` so it is
%   shared across BosonPlotter, FermiViewer, and any other GUI that
%   wants to honour the user's mode choice. On read failure (file
%   missing, corrupted, etc.) returns 'Dark' — the historical default.
%
%   Writes are best-effort: failures are silent so a read-only prefdir
%   never blocks the toggle.
%
% File location
%   fullfile(prefdir, 'boson_theme.mat') with variable `themeName`
%   containing the char vector 'Dark' or 'Light'.

    persistent CACHED_PATH
    if isempty(CACHED_PATH)
        CACHED_PATH = fullfile(prefdir, 'boson_theme.mat');
    end

    switch lower(string(action))
        case "read"
            out = 'Dark';
            try
                if isfile(CACHED_PATH)
                    s = load(CACHED_PATH, 'themeName');
                    if isfield(s, 'themeName') && ischar(s.themeName) ...
                            && any(strcmpi(s.themeName, {'Dark','Light','Auto'}))
                        % Normalise to canonical capitalisation.
                        if strcmpi(s.themeName, 'Dark')
                            out = 'Dark';
                        elseif strcmpi(s.themeName, 'Auto')
                            out = 'Auto';
                        else
                            out = 'Light';
                        end
                    end
                end
            catch
                % Silent fallback to the historical default.
            end
        case "write"
            if nargin < 2 || ~ischar(value) && ~isstring(value)
                return;
            end
            value = char(value);
            if ~any(strcmpi(value, {'Dark','Light','Auto'}))
                return;
            end
            % Normalise.
            if strcmpi(value, 'Dark')
                themeName = 'Dark'; %#ok<NASGU>
            elseif strcmpi(value, 'Auto')
                themeName = 'Auto'; %#ok<NASGU>
            else
                themeName = 'Light'; %#ok<NASGU>
            end
            try
                save(CACHED_PATH, 'themeName');
            catch
                % Best-effort: silent on write failure.
            end
            if nargout > 0, out = value; end
        otherwise
            error('bosonPlotter:themePref:badAction', ...
                'Action must be ''read'' or ''write''.');
    end
end
