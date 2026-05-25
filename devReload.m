function devReload(guiName)
%DEVRELOAD  Close a running GUI, flush its cached code, and relaunch fresh.
%
%   Use this during development after editing a GUI file. MATLAB keeps
%   function definitions in memory once loaded, so edits to an open GUI
%   are invisible until you flush the function cache. `devReload` does
%   the minimal-sufficient reset: close the figure, clear the function,
%   and relaunch.
%
%   Usage:
%       devReload                 % default: FermiViewer
%       devReload FermiViewer
%
%   Equivalent one-liner:
%       close all force; clear functions; FermiViewer
%
%   This is *not* the same as `clear classes` or restarting MATLAB.
%   `clear classes` also destroys loaded class definitions (usually not
%   needed for edits to plain function files) and is ~3× slower.
%   Full MATLAB restart is only required when the MEX or Java state is
%   corrupted — devReload is the right first step for 99% of edits.
%
%   IMPORTANT: FermiViewer delegates to dozens of PACKAGE functions
%   (+fermiViewer/*, +imaging/*, +parser/*). `clear FermiViewer` alone does
%   NOT flush those — so edits to e.g. +fermiViewer/buildTransformPanel.m
%   would stay invisible. devReload therefore runs `clear functions` to flush
%   ALL cached function definitions, which is what makes package edits show.

    arguments
        guiName (1,:) char = 'FermiViewer'
    end

    % Close all figures (uifigures ignore non-forced close requests if
    % they have CloseRequestFcn guards, so use force).
    close all force

    % Flush the function cache so the next call reads edited source from disk.
    % `clear functions` clears EVERY cached function — crucially the package
    % functions the GUI delegates to, which `clear(guiName)` would miss.
    rehash;                  % re-scan the path so renamed/new files are seen
    clear functions          %#ok<CLFUNC>  intentional: flush package fns too
    try
        clear(guiName);      % belt-and-suspenders for the entry point itself
    catch
    end

    % Relaunch.
    if exist(guiName, 'file') ~= 2
        error('devReload:notFound', ...
            'GUI "%s" not found on path. Run setupToolbox first.', guiName);
    end
    feval(guiName);
end
