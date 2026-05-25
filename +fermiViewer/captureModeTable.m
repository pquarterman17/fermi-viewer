function tbl = captureModeTable()
%CAPTUREMODETABLE  Single source of truth for capture-mode label + steps.
%
%   tbl = fermiViewer.captureModeTable()
%
%   Maps each interactive capture-mode key (the strings stored in
%   appData.captureMode) to a human label and an ordered list of step hints.
%   Consumed by the capture-mode banner and the status-bar mode readout so
%   the wording lives in ONE place instead of scattered inline strings.
%
%   Keys match the appData.captureMode vocabulary in FermiViewer.m. Unknown
%   or empty modes have no entry — callers should treat "not a field" as
%   "no banner" (see fermiViewer.chrome.captureBanner).
%
%   Each entry is a struct with:
%       .label   — display name (e.g. "Distance")
%       .steps   — 1xN cellstr of per-step hints (e.g. {'Click point A', ...})
%
%   Example:
%       tbl = fermiViewer.captureModeTable();
%       if isfield(tbl, mode)
%           m = tbl.(mode);
%           fprintf('%s — step 1/%d: %s\n', m.label, numel(m.steps), m.steps{1});
%       end
%
%   See also fermiViewer.chrome.captureBanner

    mk = @(label, steps) struct('label', label, 'steps', {steps});

    tbl.profile    = mk('Line Profile',   {'Click start point', 'Click end point'});
    tbl.boxprofile = mk('Box Profile',    {'Drag to draw box', 'Release to finish'});
    tbl.distance   = mk('Distance',       {'Click point A', 'Click point B'});
    tbl.angle      = mk('Angle (3-pt)',   {'Click vertex', 'Click ray 1', 'Click ray 2'});
    tbl.polyline   = mk('Polyline',       {'Click to add points', 'Double-click to finish'});
    tbl.dspacing   = mk('d-Spacing',      {'Click point A', 'Click point B'});
    tbl.lattice    = mk('Lattice Measure',{'Click first lattice point', 'Click second'});
    tbl.rectROI    = mk('ROI Statistics', {'Drag to draw rectangle'});
    tbl.roiellipse = mk('Elliptical ROI', {'Drag to draw ellipse'});
    tbl.crop       = mk('Crop',           {'Drag to draw region', 'Enter to apply'});
    tbl.savecrop   = mk('Save Crop',      {'Drag to draw region', 'Enter to save'});
    tbl.zoom       = mk('Zoom Box',       {'Drag to draw zoom region'});
    tbl.scalebar   = mk('Scale Bar',      {'Drag across a known distance'});
    tbl.gpa        = mk('GPA (Strain)',   {'Click first g-vector', 'Click second g-vector'});

    % Annotations
    tbl.arrow       = mk('Place Arrow',     {'Click tail', 'Click head'});
    tbl.annotline   = mk('Place Line',      {'Click start', 'Click end'});
    tbl.annotrect   = mk('Place Rectangle', {'Drag to draw rectangle'});
    tbl.annotcircle = mk('Place Circle',    {'Click center', 'Drag to set radius'});
    tbl.annotation  = mk('Text Annotation', {'Click to place text'});

    % Persistent analysis ROI
    tbl.analysisroi_rect   = mk('Analysis ROI (rect)',   {'Drag to draw rectangle'});
    tbl.analysisroi_circle = mk('Analysis ROI (circle)', {'Click center', 'Drag to set radius'});
end
