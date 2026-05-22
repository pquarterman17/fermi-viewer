function quietAlert(fig, msg, varargin)
%QUIETALERT  Drop-in replacement for uialert that no-ops in headless mode.
%
%   In normal interactive use this forwards every argument to uialert(),
%   so callers swap "uialert" → "bosonPlotter.quietAlert" without changing
%   call sites otherwise.  When QUANTIZED_MATLAB_HEADLESS=1 (see
%   bosonPlotter.isHeadless), the call is suppressed and the message is
%   logged to the Command Window prefixed with [alert] so the test diary
%   still records what would have been shown.
%
%   Usage:
%       bosonPlotter.quietAlert(fig, 'message');
%       bosonPlotter.quietAlert(fig, 'message', 'Title');
%       bosonPlotter.quietAlert(fig, 'message', 'Title', 'Icon', 'error');
    if bosonPlotter.isHeadless()
        title = '';
        if ~isempty(varargin) && (ischar(varargin{1}) || isstring(varargin{1}))
            title = char(varargin{1});
        end
        if isempty(title)
            fprintf('[alert] %s\n', char(string(msg)));
        else
            fprintf('[alert][%s] %s\n', title, char(string(msg)));
        end
        return
    end
    uialert(fig, msg, varargin{:});
end
