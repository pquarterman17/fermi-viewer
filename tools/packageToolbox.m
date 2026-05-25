function outFile = packageToolbox(versionStr)
%PACKAGETOOLBOX  Build a FermiViewer .mltbx for release.
%
%   packageToolbox                 % version from $MLTBX_VERSION or 0.0.0
%   packageToolbox('1.2.3')        % explicit version
%   outFile = packageToolbox(...)  % returns the .mltbx path
%
%   Packages the runtime toolbox (the +parser/+imaging/+fermiViewer/+calc
%   packages + FermiViewer.m + setupToolbox.m + license files) into
%   FermiViewer.mltbx. Deliberately EXCLUDES tests/, +test_datasets/
%   (~210 MB of sample data), docs/, plans/, and CI config — none of which
%   belong in an installable toolbox.
%
%   Run from the repo root. Used by .github/workflows/release.yml on a
%   vX.Y.Z tag; the version is the tag with any leading 'v' stripped.
%
%   Requires R2023a+ (matlab.addons.toolbox.ToolboxOptions).

    if nargin < 1 || isempty(versionStr)
        versionStr = getenv('MLTBX_VERSION');
    end
    if isempty(versionStr)
        versionStr = '0.0.0';
    end
    versionStr = char(versionStr);
    if startsWith(versionStr, 'v')
        versionStr = versionStr(2:end);   % strip leading 'v' from git tag
    end

    root = pwd;

    % Stable identifier — must NOT change across releases, or Add-On Manager
    % treats each upload as a different toolbox instead of an update.
    identifier = 'b3f1c8e2-7a4d-4e9b-9c21-fe7a1d0c5e84';

    % Runtime files only (directories are included recursively).
    runtime = ["+parser", "+imaging", "+fermiViewer", "+calc", ...
               "FermiViewer.m", "setupToolbox.m", ...
               "LICENSE", "NOTICE", "README.md"];
    present = runtime(arrayfun(@(p) isfile(p) || isfolder(p), runtime));

    opts = matlab.addons.toolbox.ToolboxOptions(root, identifier);
    opts.ToolboxName       = "FermiViewer";
    opts.ToolboxVersion    = versionStr;
    opts.Summary           = "Electron-microscopy image analysis (TEM/STEM): EELS, EDS, diffraction indexing, FFT, measurements.";
    opts.Description       = "MATLAB GUI for EM image analysis. Imports DM3/DM4, SER, BCF, MRC, TIFF/PNG/JPG/RAW. EELS background/edge ID, EDS Cliff-Lorimer quantification, electron-diffraction indexing, FFT analysis, and image processing — MATLAB built-ins only.";
    opts.AuthorName        = "Paige Quarterman";
    opts.MinimumMatlabRelease = "R2022b";
    opts.ToolboxFiles      = fullfile(root, present);
    opts.ToolboxMatlabPath = root;   % so the +packages resolve on install
    opts.OutputFile        = fullfile(root, "FermiViewer.mltbx");

    matlab.addons.toolbox.packageToolbox(opts);
    outFile = char(opts.OutputFile);
    fprintf('Packaged %s (v%s, %d top-level items).\n', outFile, versionStr, numel(present));
end
