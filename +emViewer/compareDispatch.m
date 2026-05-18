function [appData, outHandles] = compareDispatch(action, appData, ctx, varargin)
%COMPAREDISPATCH  Unified compare-mode dispatcher extracted from FermiViewer.
%
% Syntax:
%   [appData, outHandles] = emViewer.compareDispatch(action, appData, ctx)
%
% Actions:
%   'toggle'          — onCompareToggle: enter or exit based on ctx.toggleValue
%   'enter'           — enterCompareMode: split view, create axL/axR
%   'exit'            — exitCompareMode: destroy compare layout (axes cleanup only)
%   'syncZoom'        — syncCompareZoom: copy axis limits source → target
%   'updateHighlight' — updateCompareHighlight: show active panel border
%   'flicker'         — onFlickerCompare: flicker animation between two images
%
% Inputs:
%   action  — char; one of the action strings above
%   appData — FermiViewer appData struct (modified via output)
%   ctx     — context struct with handles and callbacks (see buildCompareCtx)
%             Required fields vary by action — see body below.
%   varargin — action-specific args:
%             'syncZoom': (sourceAx, targetAx)
%
% Outputs:
%   appData    — updated appData
%   outHandles — struct:
%     .axL, .axR, .compareGL  — created by 'enter' ([] on other actions)
%
% Note on 'exit': the caller (FermiViewer.m) must assign axL=[], axR=[],
%   compareGL=[] and rebuild the single-view ax itself (the layout rebuild
%   references too many FermiViewer closure variables to extract cleanly).
%
% Examples:
%   ctx = buildCompareCtx();
%   [appData, h] = emViewer.compareDispatch('enter', appData, ctx);
%   axL = h.axL; axR = h.axR; compareGL = h.compareGL;
%
%   [appData, ~] = emViewer.compareDispatch('updateHighlight', appData, ctx);

    outHandles = struct('axL', [], 'axR', [], 'compareGL', []);

    switch action
        case 'toggle'
            if ctx.toggleValue
                [appData, outHandles] = doEnter(appData, ctx);
            else
                appData = doExit(appData, ctx);
            end
        case 'enter'
            [appData, outHandles] = doEnter(appData, ctx);
        case 'exit'
            appData = doExit(appData, ctx);
        case 'syncZoom'
            sourceAx = varargin{1};
            targetAx = varargin{2};
            doSyncZoom(sourceAx, targetAx, ctx);
        case 'updateHighlight'
            doUpdateHighlight(appData, ctx);
        case 'flicker'
            appData = doFlicker(appData, ctx);
        otherwise
            error('emViewer:compareDispatch:unknownAction', ...
                'Unknown action: %s', action);
    end
end

% ════════════════════════════════════════════════════════════════════════════
%  enterCompareMode — split the view into two side-by-side axes
% ════════════════════════════════════════════════════════════════════════════
function [appData, outHandles] = doEnter(appData, ctx)
    outHandles = struct('axL', [], 'axR', [], 'compareGL', []);

    if numel(appData.images) < 2
        return;
    end

    % Mutually exclusive with EDS mode
    if appData.edsMode
        ctx.cb.onExitEDS();
    end

    appData.compareMode = true;

    % Pick indices for left and right panels
    appData.compareIdxL = appData.activeIdx;
    nextIdx = appData.activeIdx + 1;
    if nextIdx > numel(appData.images), nextIdx = 1; end
    appData.compareIdxR = nextIdx;
    appData.compareActivePanel = 'L';

    % Cancel any in-progress capture
    if ~isempty(appData.captureMode)
        ctx.cb.cancelCapture();
        appData.captureMode   = '';
        appData.captureClicks = [];
    end

    % Clear overlays before destroying the axes
    ctx.cb.clearAllOverlays();

    % Destroy single-view axes
    delete(ctx.axGL);

    % Create side-by-side layout inside axPanel
    compareGL = uigridlayout(ctx.axPanel, [1 2], ...
        'ColumnWidth', {'1x', '1x'}, ...
        'Padding', [2 2 2 2], ...
        'ColumnSpacing', 4);

    axL = uiaxes(compareGL);
    axL.Layout.Row = 1; axL.Layout.Column = 1;
    axL.Box = 'on';
    axL.XTick = []; axL.YTick = [];
    axL.Toolbar.Visible = 'off';
    try, disableDefaultInteractivity(axL); catch, end
    axL.Interactions = [];
    colormap(axL, gray(256));

    axR = uiaxes(compareGL);
    axR.Layout.Row = 1; axR.Layout.Column = 2;
    axR.Box = 'on';
    axR.XTick = []; axR.YTick = [];
    axR.Toolbar.Visible = 'off';
    try, disableDefaultInteractivity(axR); catch, end
    axR.Interactions = [];
    colormap(axR, gray(256));

    % Return created handles; FermiViewer.m wrapper assigns them to closure
    % variables (axL, axR, compareGL) BEFORE calling displayCompareImage and
    % updateCompareHighlight, because those functions read axL/axR from their
    % own closure. The wrapper also calls setToolsEnabled and setStatus.
    outHandles.axL       = axL;
    outHandles.axR       = axR;
    outHandles.compareGL = compareGL;
end

% ════════════════════════════════════════════════════════════════════════════
%  exitCompareMode — clean up compare state; caller rebuilds single-view ax
% ════════════════════════════════════════════════════════════════════════════
function appData = doExit(appData, ctx)
    appData.compareMode = false;

    % Clean up compare scale bars (handles destroyed with axes)
    appData.overlays.scalebarL = [];
    appData.overlays.scalebarR = [];

    % Destroy compare layout (caller must set compareGL/axL/axR = [] after)
    if ~isempty(ctx.compareGL) && isvalid(ctx.compareGL)
        delete(ctx.compareGL);
    end

    % NOTE: caller must also:
    %   compareGL = []; axL = []; axR = [];
    %   ... rebuild axGL, ax, stackGL widgets ...
    %   fig.WindowButtonMotionFcn = @onMouseMotion;
    %   displayImage();
    ctx.cb.setStatus('Compare mode off.');
end

% ════════════════════════════════════════════════════════════════════════════
%  syncCompareZoom — copy axis limits source → target
% ════════════════════════════════════════════════════════════════════════════
function doSyncZoom(sourceAx, targetAx, ctx)
    if ~ctx.compareLinkedZoom, return; end
    if isempty(sourceAx) || ~isvalid(sourceAx), return; end
    if isempty(targetAx)  || ~isvalid(targetAx),  return; end
    targetAx.XLim = sourceAx.XLim;
    targetAx.YLim = sourceAx.YLim;
end

% ════════════════════════════════════════════════════════════════════════════
%  updateCompareHighlight — show cyan border on the active compare panel
% ════════════════════════════════════════════════════════════════════════════
function doUpdateHighlight(appData, ctx)
    doUpdateHighlightDirect(appData, ctx.axL, ctx.axR, ctx);
end

function doUpdateHighlightDirect(appData, axL, axR, ctx)
    if isempty(axL) || ~isvalid(axL), return; end
    if isempty(axR) || ~isvalid(axR), return; end

    inactiveBorder = [0.4 0.4 0.4];
    if appData.compareActivePanel == 'L'
        axL.XColor = ctx.OVERLAY_COLOR; axL.YColor = ctx.OVERLAY_COLOR;
        axL.LineWidth = 2;
        axR.XColor = inactiveBorder;   axR.YColor = inactiveBorder;
        axR.LineWidth = 0.5;
        ctx.cb.setStatus(sprintf( ...
            'Compare: LEFT [%d] active — click or Tab to switch, arrows to scroll', ...
            appData.compareIdxL));
    else
        axR.XColor = ctx.OVERLAY_COLOR; axR.YColor = ctx.OVERLAY_COLOR;
        axR.LineWidth = 2;
        axL.XColor = inactiveBorder;   axL.YColor = inactiveBorder;
        axL.LineWidth = 0.5;
        ctx.cb.setStatus(sprintf( ...
            'Compare: RIGHT [%d] active — click or Tab to switch, arrows to scroll', ...
            appData.compareIdxR));
    end
end

% ════════════════════════════════════════════════════════════════════════════
%  onFlickerCompare — flicker animation between two images
% ════════════════════════════════════════════════════════════════════════════
function appData = doFlicker(appData, ctx)
    if ~isfield(appData, 'images') || numel(appData.images) < 2
        bosonPlotter.quietAlert(ctx.fig, 'Load at least 2 images.', 'Need 2+ images');
        return;
    end

    % Stop if already running
    if isfield(appData, 'flickerTimer') && ~isempty(appData.flickerTimer) ...
            && isvalid(appData.flickerTimer)
        stop(appData.flickerTimer);
        delete(appData.flickerTimer);
        appData.flickerTimer = [];
        ctx.ui.btnFlickerCompare.Text = 'Flicker';
        ctx.cb.setStatus('Flicker mode stopped.');
        return;
    end

    answer = inputdlg({'Flicker rate (Hz):', 'Image A index:', 'Image B index:'}, ...
        'Flicker Compare', [1 30; 1 30; 1 30], ...
        {'2', '1', num2str(min(2, numel(appData.images)))});
    if isempty(answer), return; end
    rate = str2double(answer{1});
    idxA = str2double(answer{2});
    idxB = str2double(answer{3});
    if any(isnan([rate, idxA, idxB])), return; end
    rate = max(0.5, min(rate, 10));

    imgA = appData.images{idxA};
    imgB = appData.images{idxB};

    % Resize B to match A if needed
    [HA, WA] = size(imgA, [1 2]);
    [HB, WB] = size(imgB, [1 2]);
    if HA ~= HB || WA ~= WB
        [Xq, Yq] = meshgrid(linspace(1, WB, WA), linspace(1, HB, HA));
        imgB = interp2(double(imgB), Xq, Yq, 'nearest');
    end

    flickerState = struct('imgA', imgA, 'imgB', imgB, 'showA', true);
    appData.flickerState = flickerState;

    t = timer('ExecutionMode', 'fixedRate', 'Period', 1/rate, ...
        'TimerFcn', @(~,~) ctx.cb.flickerTick());
    appData.flickerTimer = t;
    start(t);
    ctx.ui.btnFlickerCompare.Text = 'Stop Flicker';
    ctx.cb.setStatus(sprintf('Flicker: %.1f Hz between images %d and %d', rate, idxA, idxB));
end
