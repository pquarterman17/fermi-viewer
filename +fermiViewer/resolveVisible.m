function vis = resolveVisible(req)
%RESOLVEVISIBLE  Map a GUI launcher's Visible="on"|"off"|"auto" to a
%   concrete "on"/"off" string suitable for uifigure().
%
%   "auto" → "off" when QUANTIZED_MATLAB_HEADLESS=1 (see
%   bosonPlotter.isHeadless), otherwise "on". Explicit "on"/"off" pass
%   through unchanged. Centralizing the resolution lets every GUI
%   constructor be one line instead of an 8-line branch.
    if req == "auto"
        if bosonPlotter.isHeadless()
            vis = "off";
        else
            vis = "on";
        end
    else
        vis = req;
    end
end
