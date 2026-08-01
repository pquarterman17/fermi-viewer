function result = checkForUpdates(options)
%CHECKFORUPDATES  Compare the running version against the latest GitHub release.
%
%   Syntax
%     result = fermiViewer.checkForUpdates()
%     result = fermiViewer.checkForUpdates(Name=Value)
%
%   Name-Value
%     Timeout   (1,1) double = 5   Network timeout (seconds).
%     Endpoint  (1,1) string       GitHub "latest release" API URL
%                                  (override for tests).
%     LatestTag (1,1) string = ""  When non-empty, skip the network and
%                                  treat this as the latest tag (tests).
%
%   Outputs
%     result — struct:
%       .status   'update' | 'current' | 'offline' | 'unknown'
%       .current  running version from fermiViewer.appVersion (e.g. '0.49.0')
%       .latest   latest release version, 'v' prefix stripped ('' if unknown)
%       .url      releases page (html_url of the latest release when known)
%
%   Notification-only by design: nothing is downloaded or installed. A
%   local version AHEAD of the latest release (a dev checkout between
%   releases) reports 'current', not 'update'. Network failure of any
%   kind reports 'offline' rather than raising.
%
%   Examples
%     r = fermiViewer.checkForUpdates();
%     if strcmp(r.status, 'update'), web(r.url, '-browser'); end
%
%   See also FERMIVIEWER.APPVERSION, FERMIVIEWER.PROMPTCHECKUPDATES

    arguments
        options.Timeout   (1,1) double = 5
        options.Endpoint  (1,1) string = ...
            "https://api.github.com/repos/pquarterman17/fermi-viewer/releases/latest"
        options.LatestTag (1,1) string = ""
    end

    result = struct( ...
        'status',  'unknown', ...
        'current', fermiViewer.appVersion(), ...
        'latest',  '', ...
        'url',     'https://github.com/pquarterman17/fermi-viewer/releases');

    tag = char(options.LatestTag);
    if isempty(tag)
        try
            wo   = weboptions('Timeout', options.Timeout, 'ContentType', 'json');
            data = webread(options.Endpoint, wo);
            if isfield(data, 'tag_name'), tag = char(data.tag_name); end
            if isfield(data, 'html_url') && ~isempty(data.html_url)
                result.url = char(data.html_url);
            end
        catch
            result.status = 'offline';
            return;
        end
    end

    result.latest = regexprep(tag, '^v', '');
    pLatest  = sscanf(result.latest, '%d.');
    pCurrent = sscanf(result.current, '%d.');
    if isempty(pLatest) || isempty(pCurrent)
        result.status = 'unknown';   % unparseable tag or unknown local version
        return;
    end

    if compareVersions(pLatest, pCurrent) > 0
        result.status = 'update';
    else
        result.status = 'current';
    end
end

% ────────────────────────────────────────────────────────────────────────
function c = compareVersions(pa, pb)
%COMPAREVERSIONS  Element-wise dotted-numeric compare: sign(pa - pb).
%   Shorter version vectors are zero-padded, so 0.42 == 0.42.0.
    n = max(numel(pa), numel(pb));
    pa(end+1:n) = 0;
    pb(end+1:n) = 0;
    d = pa(:) - pb(:);
    k = find(d ~= 0, 1);
    if isempty(k)
        c = 0;
    else
        c = sign(d(k));
    end
end
