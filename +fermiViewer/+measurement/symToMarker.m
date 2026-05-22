function mrk = symToMarker(sym)
%SYMTOMARKER  Convert measurement symbol name to MATLAB marker character.
%
% Syntax:
%   mrk = fermiViewer.measurement.symToMarker(sym)
%
% Inputs:
%   sym  — string: 'circle', 'cross', 'square', or any other (→ 'none')
%
% Outputs:
%   mrk  — single char: 'o', 'x', 's', or 'none'
%
% Examples:
%   mrk = fermiViewer.measurement.symToMarker('circle')  % mrk = 'o'
%   mrk = fermiViewer.measurement.symToMarker('cross')   % mrk = 'x'

switch sym
    case 'circle', mrk = 'o';
    case 'cross',  mrk = 'x';
    case 'square', mrk = 's';
    otherwise,     mrk = 'none';
end
