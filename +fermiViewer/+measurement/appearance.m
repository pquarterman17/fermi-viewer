function measurements = appearance(action, measurements, varargin)
%APPEARANCE  Measurement color and symbol styling helpers.
%
% Syntax:
%   measurements = fermiViewer.measurement.appearance('applyColor',    measurements, hLine, clr)
%   measurements = fermiViewer.measurement.appearance('applyColorAll', measurements, hLine, overlayColor)
%   measurements = fermiViewer.measurement.appearance('applySymbol',   measurements, hLine, sym)
%   measurements = fermiViewer.measurement.appearance('applySymbolAll',measurements, hLine)
%
% All functions modify measurement structs in-place on the graphics objects
% and return the updated measurements cell array.
%
% Inputs:
%   measurements  — cell array of measurement structs (appData.overlays.measurements)
%   hLine         — graphics handle to identify the target measurement by identity
%   clr           — [1x3] RGB color
%   sym           — string: 'circle', 'cross', 'square', or 'none'
%   overlayColor  — fallback [1x3] RGB when target measurement has no lineColor
%
% Examples:
%   m = fermiViewer.measurement.appearance('applyColor', m, hLine, [1 0 0]);

% ════════════════════════════════════════════════════════════════════
switch lower(action)
    case 'applycolor'
        [hLine, clr] = varargin{:};
        measurements = applyMeasColor(measurements, hLine, clr);

    case 'applycolorall'
        [hLine, overlayColor] = varargin{:};
        measurements = applyMeasColorAll(measurements, hLine, overlayColor);

    case 'applysymbol'
        [hLine, sym] = varargin{:};
        measurements = applyMeasEndSymbol(measurements, hLine, sym);

    case 'applysymbolall'
        hLine = varargin{1};
        measurements = applyMeasEndSymbolAll(measurements, hLine);

    otherwise
        error('fermiViewer:measurement:appearance:unknownAction', ...
            'Unknown action "%s". Valid: applyColor, applyColorAll, applySymbol, applySymbolAll', ...
            action);
end

% ════════════════════════════════════════════════════════════════════
function measurements = applyMeasColor(measurements, hLine, clr)
    for mi = 1:numel(measurements)
        m = measurements{mi};
        if ~isfield(m,'hLine') || isempty(m.hLine) || ~isvalid(m.hLine), continue; end
        if m.hLine ~= hLine, continue; end
        m.lineColor = clr;
        m.hLine.Color = clr;
        if isfield(m,'hP1') && ~isempty(m.hP1) && isvalid(m.hP1)
            m.hP1.Color = clr; m.hP1.MarkerEdgeColor = clr;
        end
        if isfield(m,'hP2') && ~isempty(m.hP2) && isvalid(m.hP2)
            m.hP2.Color = clr; m.hP2.MarkerEdgeColor = clr;
        end
        measurements{mi} = m;
        return;
    end

% ════════════════════════════════════════════════════════════════════
function measurements = applyMeasColorAll(measurements, hLine, overlayColor)
    clr = overlayColor;
    for mi = 1:numel(measurements)
        m = measurements{mi};
        if isfield(m,'hLine') && ~isempty(m.hLine) && isvalid(m.hLine) && m.hLine == hLine
            if isfield(m, 'lineColor'), clr = m.lineColor; end
            break;
        end
    end
    for mi = 1:numel(measurements)
        m = measurements{mi};
        if isfield(m,'hLine') && ~isempty(m.hLine) && isvalid(m.hLine)
            measurements = applyMeasColor(measurements, m.hLine, clr);
        end
    end

% ════════════════════════════════════════════════════════════════════
function measurements = applyMeasEndSymbol(measurements, hLine, sym)
    mrk   = fermiViewer.measurement.symToMarker(sym);
    mrkSz = 6; if strcmp(sym, 'none'), mrkSz = 0.1; end
    for mi = 1:numel(measurements)
        m = measurements{mi};
        if ~isfield(m,'hLine') || isempty(m.hLine) || ~isvalid(m.hLine), continue; end
        if m.hLine ~= hLine, continue; end
        m.endSymbol = sym;
        for ph = {m.hP1, m.hP2}
            hp = ph{1};
            if ~isempty(hp) && isvalid(hp)
                hp.Marker = mrk; hp.MarkerSize = mrkSz;
            end
        end
        measurements{mi} = m;
        return;
    end

% ════════════════════════════════════════════════════════════════════
function measurements = applyMeasEndSymbolAll(measurements, hLine)
    sym = 'circle';
    for mi = 1:numel(measurements)
        m = measurements{mi};
        if isfield(m,'hLine') && ~isempty(m.hLine) && isvalid(m.hLine) && m.hLine == hLine
            if isfield(m, 'endSymbol'), sym = m.endSymbol; end
            break;
        end
    end
    for mi = 1:numel(measurements)
        m = measurements{mi};
        if isfield(m,'hLine') && ~isempty(m.hLine) && isvalid(m.hLine)
            measurements = applyMeasEndSymbol(measurements, m.hLine, sym);
        end
    end
