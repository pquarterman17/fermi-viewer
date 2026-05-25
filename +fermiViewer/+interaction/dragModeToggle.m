function appData = dragModeToggle(appData, fig, mode, src, setStatus)
%DRAGMODETOGGLE  Unified handler for zoom/pan toolbar toggles.
%
%   appData = fermiViewer.interaction.dragModeToggle(appData, fig, mode, src, setStatus)
%
%   `mode` is 'zoom' or 'pan'; ensures mutual exclusivity. Updates the
%   transform toolbar button Values to reflect the state change.
%   Accept-and-return for appData.zoomMode + .panMode mutations.

    val = logical(src.Value);
    btns = appData.transformToolbarBtns;
    % Toolbar order (see FermiViewer.m / buildSingleViewPanel.m rcSpecs):
    %   5 = zoom (Z), 6 = zoom-out, 7 = pan. The zoom/pan toggles sync each
    %   other for mutual exclusivity, so they index 5 and 7 here.
    ZOOM_BTN = 5; PAN_BTN = 7;
    if strcmp(mode, 'zoom')
        appData.zoomMode = val;
        if val
            appData.panMode = false;
            if numel(btns) >= PAN_BTN && isvalid(btns(PAN_BTN)), btns(PAN_BTN).Value = false; end
            fig.Pointer = 'arrow';
            setStatus('Drag to zoom into a region. Toggle off for marquee-select.');
        else
            setStatus('Drag to marquee-select items. Toggle on for box-zoom.');
        end
    else
        appData.panMode = val;
        if numel(btns) >= PAN_BTN && isvalid(btns(PAN_BTN)), btns(PAN_BTN).Value = val; end
        if val
            appData.zoomMode = false;
            if numel(btns) >= ZOOM_BTN && isvalid(btns(ZOOM_BTN)), btns(ZOOM_BTN).Value = false; end
            fig.Pointer = 'hand';
            setStatus('Drag to pan. Middle-drag always pans regardless of mode.');
        else
            fig.Pointer = 'arrow';
            setStatus('Pan mode off. Drag to marquee-select items.');
        end
    end
end
