function vis = resolveVisible(req)
%RESOLVEVISIBLE  Map a GUI launcher's Visible="on"|"off"|"auto" to a
%   concrete "on"/"off" string suitable for uifigure().
%
%   "auto" → "off" when FERMI_VIEWER_HEADLESS=1 (see
%   fermiViewer.chrome.isHeadless), otherwise "on". Explicit "on"/"off" pass
%   through unchanged. Centralizing the resolution lets every GUI
%   constructor be one line instead of an 8-line branch.
    if req == "auto"
        if fermiViewer.chrome.isHeadless()
            vis = "off";
        else
            vis = "on";
        end
    else
        vis = req;
    end
end
