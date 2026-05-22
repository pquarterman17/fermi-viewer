function out = buildSingleViewPanel(axPanel, iconDir, callbacks, theme, modes)
%BUILDSINGLEVIEWPANEL  Rebuild the single-image view panel after exiting compare mode.
%
% Called by exitCompareMode to reconstruct the axGL grid, icon transform
% toolbar, image axes, and stack navigator after the side-by-side compare
% layout is torn down. Also used by the initial build path.
%
% Syntax:
%   out = emViewer.buildSingleViewPanel(axPanel, iconDir, callbacks, theme, modes)
%
% Inputs:
%   axPanel   - uipanel that hosts the view layout
%   iconDir   - char path to the fermiviewer icons directory
%   callbacks - struct of nested function handles:
%     .onRotateFlip     @(action)
%     .onDragModeToggle @(src,evt,mode)
%     .onResetZoom      @(src,evt)
%     .setActiveIdxAPI  @(idx)
%     .getActiveIdxAPI  @()
%     .onCropImage      @(src,evt)
%     .onAnnotUndo      @()
%     .onStackNav       @(delta)
%     .onStackSlider    @(src,evt)
%     .onStackMIP       @(src,evt)
%   theme     - struct with fields: btnTool, btnFg (color vectors)
%   modes     - struct with fields: zoomMode, panMode (logicals)
%
% Outputs:
%   out - struct with fields:
%     .axGL             uigridlayout (parent of toolbar + axes + stack)
%     .ax               uiaxes (main image display)
%     .stackGL          uigridlayout (stack navigator row)
%     .btnStackPrev     uibutton
%     .btnStackNext     uibutton
%     .sldStackFrame    uislider
%     .btnStackMIP      uibutton
%     .lblStackFrame    uilabel
%     .transformToolbarBtns  1xN gobjects array
%     .toolbarIconPaths      1xN cell of icon file paths
%
% Examples:
%   out = emViewer.buildSingleViewPanel(axPanel, iconDir, cbs, theme, modes);
%   axGL = out.axGL;  ax = out.ax;

% ════════════════════════════════════════════════════════════════════

BTN_TOOL = theme.btnTool;
BTN_FG   = theme.btnFg;

% Top-level 3-row grid: [toolbar row, image row, stack row]
axGL = uigridlayout(axPanel, [3 1], ...
    'RowHeight', {32, '1x', 0}, 'Padding', [2 2 2 2], ...
    'RowSpacing', 2);

% ── Row 1: icon transform toolbar ────────────────────────────────
rcToolbarGL = uigridlayout(axGL, [1 15], ...
    'ColumnWidth', {28, 28, 4, 28, 28, 4, 28, 28, 28, 4, 28, 28, 4, 28, '1x'}, ...
    'RowHeight',   {28}, ...
    'Padding',     [2 2 2 2], ...
    'ColumnSpacing', 0);
rcToolbarGL.Layout.Row = 1;

rcResetFcn = @(~,~) callbacks.setActiveIdxAPI(callbacks.getActiveIdxAPI());
rcSpecs = {
    'rot_cw.png',    'CW',    'Rotate 90° clockwise',                                   @(~,~) callbacks.onRotateFlip('rot90cw'),  'push';
    'rot_ccw.png',   'CCW',   'Rotate 90° counter-clockwise',                           @(~,~) callbacks.onRotateFlip('rot90ccw'), 'push';
    'flip_h.png',    'FH',    'Flip horizontally (left-right mirror)',                  @(~,~) callbacks.onRotateFlip('fliph'),    'push';
    'flip_v.png',    'FV',    'Flip vertically (top-bottom mirror)',                    @(~,~) callbacks.onRotateFlip('flipv'),    'push';
    'zoom.png',      'Z',     'Drag-to-zoom mode (toggle off for marquee-select)',      @(s,e) callbacks.onDragModeToggle(s,e,'zoom'), 'state';
    'pan.png',       'Pan',   'Pan mode — drag to scroll when zoomed in (middle-drag always pans)', @(s,e) callbacks.onDragModeToggle(s,e,'pan'), 'state';
    'fit.png',       'Fit',   'Fit image to window (reset zoom)',                       callbacks.onResetZoom,                    'push';
    'reset_all.png', 'Reset', 'Reset all transforms (reload original image)',           rcResetFcn,                               'push';
    'crop.png',      'Crop',  'Crop to rectangle (destructive — Undo Filters reverts)', callbacks.onCropImage,                    'push';
    'del_annot.png', 'Del',       'Delete last annotation (Delete key)',                @(~,~) callbacks.onAnnotUndo(),           'push';
};
rcCols = [1, 2, 4, 5, 7, 8, 9, 11, 12, 14];
rcBtns = gobjects(1, size(rcSpecs, 1));
for rcK = 1:size(rcSpecs, 1)
    rcP     = fullfile(iconDir, rcSpecs{rcK, 1});
    isState = strcmp(rcSpecs{rcK, 5}, 'state');
    cbProp  = 'ButtonPushedFcn';
    btnType = {};
    if isState
        cbProp  = 'ValueChangedFcn';
        btnType = {'state'};
    end
    if isfile(rcP)
        rcBtns(rcK) = uibutton(rcToolbarGL, btnType{:}, ...
            'Icon', rcP, 'Text', '', 'IconAlignment', 'center', ...
            'BackgroundColor', BTN_TOOL, ...
            'Tooltip', rcSpecs{rcK, 3}, ...
            cbProp, rcSpecs{rcK, 4}, ...
            'Enable', 'on');
    else
        rcBtns(rcK) = uibutton(rcToolbarGL, btnType{:}, ...
            'Text', rcSpecs{rcK, 2}, 'FontSize', 11, ...
            'BackgroundColor', BTN_TOOL, ...
            'FontColor', BTN_FG, ...
            'Tooltip', rcSpecs{rcK, 3}, ...
            cbProp, rcSpecs{rcK, 4}, ...
            'Enable', 'on');
    end
    if isState
        if rcK == 5,     rcBtns(rcK).Value = modes.zoomMode;
        elseif rcK == 6, rcBtns(rcK).Value = modes.panMode;
        end
    end
    rcBtns(rcK).Layout.Row    = 1;
    rcBtns(rcK).Layout.Column = rcCols(rcK);
end

% ── Row 2: image axes ─────────────────────────────────────────────
ax = uiaxes(axGL);
ax.Layout.Row = 2;
ax.Box = 'on';
ax.XTick = [];
ax.YTick = [];
title(ax, 'Open an image file to begin', 'Interpreter', 'none');
xlabel(ax, '');
ylabel(ax, '');
colormap(ax, gray(256));
ax.Toolbar.Visible = 'off';

% ── Row 3: stack navigator (hidden until multi-frame) ────────────
stackGL = uigridlayout(axGL, [1 5], ...
    'ColumnWidth', {40, 40, '1x', 40, 80}, 'Padding', [0 0 0 0]);
stackGL.Layout.Row = 3;

btnStackPrev = uibutton(stackGL, 'Text', '<', ...
    'ButtonPushedFcn', @(~,~) callbacks.onStackNav(-1), ...
    'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, ...
    'Tooltip', 'Previous frame');
btnStackPrev.Layout.Column = 1;

btnStackNext = uibutton(stackGL, 'Text', '>', ...
    'ButtonPushedFcn', @(~,~) callbacks.onStackNav(1), ...
    'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, ...
    'Tooltip', 'Next frame');
btnStackNext.Layout.Column = 2;

sldStackFrame = uislider(stackGL, ...
    'Value', 1, 'Limits', [1 2], ...
    'ValueChangedFcn', callbacks.onStackSlider, ...
    'Tooltip', 'Scroll through frames');
sldStackFrame.Layout.Column = 3;
sldStackFrame.MajorTicks = [];
sldStackFrame.MinorTicks = [];

btnStackMIP = uibutton(stackGL, 'Text', 'MIP', ...
    'ButtonPushedFcn', callbacks.onStackMIP, ...
    'BackgroundColor', BTN_TOOL, 'FontColor', BTN_FG, ...
    'Tooltip', 'Maximum Intensity Projection across all frames');
btnStackMIP.Layout.Column = 4;

lblStackFrame = uilabel(stackGL, 'Text', '1 / 1', ...
    'FontSize', 11, 'HorizontalAlignment', 'center', ...
    'FontColor', [0.7 0.7 0.7]);
lblStackFrame.Layout.Column = 5;

% ── Assemble output ────────────────────────────────────────────────
out = struct( ...
    'axGL',             axGL, ...
    'ax',               ax, ...
    'stackGL',          stackGL, ...
    'btnStackPrev',     btnStackPrev, ...
    'btnStackNext',     btnStackNext, ...
    'sldStackFrame',    sldStackFrame, ...
    'btnStackMIP',      btnStackMIP, ...
    'lblStackFrame',    lblStackFrame, ...
    'transformToolbarBtns', rcBtns, ...
    'toolbarIconPaths', {cellfun(@(f) fullfile(iconDir, f), rcSpecs(:,1), 'UniformOutput', false)'});
end
