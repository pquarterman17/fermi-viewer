function sel = quietConfirm(fig, msg, varargin)
%QUIETCONFIRM  Drop-in replacement for uiconfirm that auto-answers in
%   headless mode.
%
%   In normal use this forwards to uiconfirm() and returns the user's
%   choice.  When QUANTIZED_MATLAB_HEADLESS=1, returns the value of the
%   'DefaultOption' name-value pair if specified, otherwise the FIRST
%   entry of the 'Options' list, otherwise the string 'OK'.  The choice
%   is logged so test diaries record what was auto-confirmed.
%
%   Usage:
%       sel = bosonPlotter.quietConfirm(fig, 'Delete?', 'Confirm', ...
%               'Options', {'Yes','No','Cancel'}, ...
%               'DefaultOption', 'No', ...
%               'CancelOption',  'Cancel');
    if bosonPlotter.isHeadless()
        title = '';
        opts  = {'OK'};
        defaultOpt = '';
        if ~isempty(varargin) && (ischar(varargin{1}) || isstring(varargin{1}))
            title = char(varargin{1});
            nv = varargin(2:end);
        else
            nv = varargin;
        end
        for k = 1:2:numel(nv)-1
            key = lower(string(nv{k}));
            switch key
                case "options"
                    opts = cellstr(nv{k+1});
                case "defaultoption"
                    v = nv{k+1};
                    if isnumeric(v)
                        defaultOpt = '';   % numeric index → resolved below
                        defaultIdx = v;
                    else
                        defaultOpt = char(string(v));
                    end
            end
        end
        if isempty(defaultOpt)
            if exist('defaultIdx', 'var') && defaultIdx >= 1 && defaultIdx <= numel(opts)
                defaultOpt = opts{defaultIdx};
            else
                defaultOpt = opts{1};
            end
        end
        sel = defaultOpt;
        if isempty(title)
            fprintf('[confirm auto=%s] %s\n', sel, char(string(msg)));
        else
            fprintf('[confirm:%s auto=%s] %s\n', title, sel, char(string(msg)));
        end
        return
    end
    sel = uiconfirm(fig, msg, varargin{:});
end
