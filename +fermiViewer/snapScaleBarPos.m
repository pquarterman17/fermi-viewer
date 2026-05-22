function snap = snapScaleBarPos(sb)
%SNAPSCALEBARPOS  Capture the [barX barY labelX labelY] anchor of a scale-bar overlay.
%
%   snap = emViewer.snapScaleBarPos(sb)
%
%   Inputs:
%       sb — scale-bar overlay struct with .bar (rectangle) and .label
%            (text) graphics handles, as returned by imaging.addScaleBar.
%            Tolerates [], non-struct, or invalid handles (returns []).
%
%   Output:
%       snap — 1x4 row vector [barX, barY, labelX, labelY] of the current
%              live positions, or [] if the overlay is missing/invalid.
%
%   Used by FermiViewer's rebuildScaleBar to preserve a user-dragged scale-
%   bar location across property changes (color, font size, length, unit)
%   that internally delete-and-recreate the overlay.
%
%   See also emViewer.applyScaleBarPos, imaging.addScaleBar.

snap = [];
if isempty(sb) || ~isstruct(sb), return; end
if ~isfield(sb, 'bar')   || ~isvalid(sb.bar),   return; end
if ~isfield(sb, 'label') || ~isvalid(sb.label), return; end

snap = [sb.bar.Position(1),   sb.bar.Position(2), ...
        sb.label.Position(1), sb.label.Position(2)];
end
