function applyScaleBarPos(hBar, snap)
%APPLYSCALEBARPOS  Re-apply a saved drag offset to a freshly-built scale bar.
%
%   emViewer.applyScaleBarPos(hBar, snap)
%
%   After a property change (color, font size, length, unit) the scale-bar
%   overlay is deleted and recreated with default placement; this helper
%   restores the user's drag offset so the bar visually stays put.
%
%   The offset is computed from the bar anchor (snap(1:2) minus the new
%   bar's default position) and applied to BOTH the bar and label. This
%   matters because bar width may have changed (length/unit edit): the
%   freshly-built label is centered over the NEW width, and adding the
%   same dx/dy keeps it centered while preserving the user's chosen
%   location.
%
%   Inputs:
%       hBar — newly-created scale-bar overlay (struct with .bar, .label
%              valid graphics handles, as returned by imaging.addScaleBar).
%       snap — 1x4 row vector from emViewer.snapScaleBarPos, or [] to skip
%              (no previous position to restore).
%
%   See also emViewer.snapScaleBarPos, imaging.addScaleBar.

if isempty(snap) || ~isstruct(hBar), return; end
if ~isfield(hBar, 'bar')   || ~isvalid(hBar.bar),   return; end
if ~isfield(hBar, 'label') || ~isvalid(hBar.label), return; end

dx = snap(1) - hBar.bar.Position(1);
dy = snap(2) - hBar.bar.Position(2);

hBar.bar.Position(1) = snap(1);
hBar.bar.Position(2) = snap(2);
hBar.label.Position(1) = hBar.label.Position(1) + dx;
hBar.label.Position(2) = hBar.label.Position(2) + dy;
end
