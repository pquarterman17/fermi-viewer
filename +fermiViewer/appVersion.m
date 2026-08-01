function v = appVersion()
%APPVERSION  FermiViewer release version, read from CITATION.cff at runtime.
%
%   Syntax
%     v = fermiViewer.appVersion()
%
%   Outputs
%     v — release version string, e.g. '0.49.0'; '' when CITATION.cff is
%         missing or unparseable (e.g. a stripped deployment)
%
%   CITATION.cff (bumped once per release) is deliberately the SINGLE
%   version declaration in this repo. Reading it at runtime means there is
%   no second in-code constant that can drift from the released version —
%   the failure class the toolchain-version-discipline convention exists
%   to prevent.
%
%   Examples
%     fermiViewer.appVersion()   % -> '0.49.0'
%
%   See also FERMIVIEWER.CHECKFORUPDATES

    v = '';
    try
        root = fileparts(fileparts(mfilename('fullpath')));   % +fermiViewer/..
        txt  = fileread(fullfile(root, 'CITATION.cff'));
        tok  = regexp(txt, 'version:\s*"([^"]+)"', 'tokens', 'once');
        if ~isempty(tok)
            v = tok{1};
        end
    catch
        % missing/unreadable CITATION.cff -> '' (callers treat as unknown)
    end
end
