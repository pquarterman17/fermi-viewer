function appData = panelContrast(action, appData, ui, panel)
%PANELCONTRAST  Per-panel contrast state for compare mode.
%
%   appData = fermiViewer.compare.panelContrast(action, appData, ui, panel)
%
%   In compare mode each side (L / R) keeps its own contrast window so the
%   contrast controls can target whichever panel is active. The state lives
%   in appData.comparePanelContrast.(panel) as a struct with fields:
%       lo, hi      - contrast window (raw pixel units)
%       loLim       - [min max] data range, used for the slider Limits
%       gamma       - gamma exponent
%       transform   - 'linear' | 'log' | 'sqrt' | 'power'
%       invert      - logical
%
%   action
%     'sync'    - ensure the active panel has a state (auto-stretch if it
%                 has none yet) and push it onto the contrast widgets so the
%                 sliders reflect the active panel.
%     'capture' - read the contrast widgets back into the panel's state
%                 (called after the user moves a slider / gamma).
%     'auto'    - 0.35/99.65 percentile auto-stretch the panel; store + push.
%     'reset'   - full data range, gamma 1; store + push.
%
%   ui must expose: sldLow, sldHigh, sldGamma, efLow, efHigh, efGamma,
%   lblGamma, ddContrastTransform, cbInvert.

    panel = char(panel);
    if ~isfield(appData, 'comparePanelContrast') || ~isstruct(appData.comparePanelContrast)
        appData.comparePanelContrast = struct('L', [], 'R', []);
    end
    if panel == 'L'
        idx = appData.compareIdxL;
    else
        idx = appData.compareIdxR;
    end
    if idx < 1 || idx > numel(appData.images)
        return;
    end

    switch action
        case 'sync'
            st = appData.comparePanelContrast.(panel);
            if isempty(st) || ~isstruct(st)
                st = autoState(grayOf(appData.images{idx}));
            end
            appData.comparePanelContrast.(panel) = st;
            pushToWidgets(ui, st);
            appData.gamma             = st.gamma;
            appData.contrastTransform = st.transform;
            appData.contrastInvert    = st.invert;

        case 'capture'
            st = appData.comparePanelContrast.(panel);
            if isempty(st) || ~isstruct(st)
                st = autoState(grayOf(appData.images{idx}));
            end
            st.lo        = ui.sldLow.Value;
            st.hi        = ui.sldHigh.Value;
            st.loLim     = ui.sldLow.Limits;
            st.gamma     = ui.sldGamma.Value;
            st.transform = ui.ddContrastTransform.Value;
            st.invert    = logical(ui.cbInvert.Value);
            appData.comparePanelContrast.(panel) = st;

        case 'auto'
            st = autoState(grayOf(appData.images{idx}));
            appData.comparePanelContrast.(panel) = st;
            pushToWidgets(ui, st);

        case 'reset'
            st = fullRangeState(grayOf(appData.images{idx}));
            appData.comparePanelContrast.(panel) = st;
            pushToWidgets(ui, st);
    end
end

% ════════════════════════════════════════════════════════════════════════
%  LOCAL HELPERS
% ════════════════════════════════════════════════════════════════════════

function g = grayOf(dataStruct)
    info = dataStruct.metadata.parserSpecific.imageData;
    px   = info.pixels;
    if info.numChannels == 3
        p = double(px);
        g = 0.299*p(:,:,1) + 0.587*p(:,:,2) + 0.114*p(:,:,3);
    else
        g = double(px);
    end
end

function st = autoState(g)
    dMin = min(g(:)); dMax = max(g(:));
    if dMax <= dMin, dMax = dMin + 1; end
    lo = imaging.percentile(g(:), 0.35);
    hi = imaging.percentile(g(:), 99.65);
    if lo >= hi, lo = dMin; hi = dMax; end
    st = struct('lo', lo, 'hi', hi, 'loLim', [dMin dMax], ...
        'gamma', 1.0, 'transform', 'linear', 'invert', false);
end

function st = fullRangeState(g)
    dMin = min(g(:)); dMax = max(g(:));
    if dMax <= dMin, dMax = dMin + 1; end
    st = struct('lo', dMin, 'hi', dMax, 'loLim', [dMin dMax], ...
        'gamma', 1.0, 'transform', 'linear', 'invert', false);
end

function pushToWidgets(ui, st)
    ui.sldLow.Limits  = st.loLim;
    ui.sldHigh.Limits = st.loLim;
    ui.sldLow.Value   = max(st.loLim(1), min(st.loLim(2), st.lo));
    ui.sldHigh.Value  = max(st.loLim(1), min(st.loLim(2), st.hi));
    ui.efLow.Value    = st.lo;
    ui.efHigh.Value   = st.hi;
    ui.sldGamma.Value = max(ui.sldGamma.Limits(1), min(ui.sldGamma.Limits(2), st.gamma));
    ui.efGamma.Value  = st.gamma;
    ui.lblGamma.Text  = 'Gamma';
    if any(strcmp(st.transform, ui.ddContrastTransform.Items))
        ui.ddContrastTransform.Value = st.transform;
    end
    ui.cbInvert.Value = logical(st.invert);
end
