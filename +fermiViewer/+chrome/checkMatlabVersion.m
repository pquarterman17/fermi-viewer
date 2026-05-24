function ok = checkMatlabVersion()
%CHECKMATLABVERSION  Warn if MATLAB is older than the supported minimum.
%
%   ok = fermiViewer.chrome.checkMatlabVersion()
%
%   FermiViewer is developed and tested on R2024a and later. It uses a few
%   R2024a/R2023a features (e.g. local functions anywhere in a script;
%   Placeholder on numeric edit fields). On older releases the toolbox will
%   still attempt to run — feature code is written to degrade gracefully
%   where feasible (see e.g. the Placeholder guard in buildMeasurementPanel)
%   — but some things may be unavailable or error. This emits a one-time
%   console warning so users on old MATLAB understand why.
%
%   Returns true if the release meets the supported minimum, false (with a
%   warning) otherwise. Safe on R2022b+ (isMATLABReleaseOlderThan is R2020b).

    minRelease = 'R2024a';
    ok = ~isMATLABReleaseOlderThan(minRelease);
    if ~ok
        warning('fermiViewer:unsupportedMATLAB', ...
            ['FermiViewer is developed and tested on %s and later; you are ' ...
             'running R%s. The toolbox will attempt to run with graceful ' ...
             'fallbacks, but some features may be unavailable or behave ' ...
             'unexpectedly. Upgrade to %s+ for full support.'], ...
            minRelease, version('-release'), minRelease);
    end
end
