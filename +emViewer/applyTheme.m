function applyTheme(ui, appData)
%APPLYTHEME  Apply dark or light colour scheme to all FermiViewer GUI elements.
%
% Syntax:
%   emViewer.applyTheme(ui, appData)
%
% Inputs:
%   ui       - Struct of UI handles (see ui struct fields below)
%   appData  - FermiViewer appData struct; reads .darkMode,
%              .toolbarIconPaths, .transformToolbarBtns
%
% ui struct fields:
%   .fig              — uifigure handle
%   .ax               — main image axes handle
%   .histAx           — histogram axes handle
%   .listPanel        — file list panel
%   .toolsPanel       — tools panel
%   .pnlContrast      — Contrast section panel
%   .pnlHistogram     — Histogram section panel
%   .pnlMeasure       — Measure section panel
%   .pnlProcess       — Process section panel
%   .pnlExport        — Export section panel
%   .pnlAnnot         — Annotations section panel
%   .pnlEDS           — EDS section panel
%   .btnThemeToggle   — toolbar theme toggle button
%   .btnContrastHeader, .btnHistogramHeader, .btnMeasureHeader
%   .btnProcessHeader, .btnExportHeader, .btnAnnotHeader
%   .btnEDSHeader, .btnEELSHeader, .btnDiffHeader, .btnMetaHeader
%   .lblStatusDims, .lblStatusBits, .lblStatusPixSize, .lblStatusMouse
%   .lblFilename      — filename label
%   .lblSep, .lblSep2, .lblSep3, .lblSep4  — separator labels
%   .lblRename, .lblDPI, .lblPubHeader, .lblUtilHeader
%   .taMetadata       — metadata textarea
%   .efRenameBase     — rename base edit field
%   .efAnnotText      — annotation text edit field
%   .lbImages         — image listbox
%   .rootGL, .mainGL, .toolbarGL, .statusGL, .listGL, .toolsGL
%   .contrastInnerGL, .measureInnerGL, .processInnerGL
%   .exportInnerGL, .annotInnerGL, .edsInnerGL
%   .processTabGrids  — cell array of process tab grid handles
%
% Drives MATLAB's built-in theme layer (uitable chrome, scrollbars,
% dropdown overlays) and pulls all per-widget colours from
% bosonPlotter.uxTokens — the toolbox-wide single source of truth.

% ════════════════════════════════════════════════════════════════════
%  Resolve theme name and token table
% ════════════════════════════════════════════════════════════════════
if appData.darkMode
    themeName_ = 'dark';
else
    themeName_ = 'light';
end
try, theme(ui.fig, themeName_); catch, end
tkFV_      = bosonPlotter.uxTokens(themeName_);
figBG      = tkFV_.color.bgFigure;
panelBG    = tkFV_.color.bgPanel;
panelFG    = tkFV_.color.text;
hdrBG      = tkFV_.color.bgPanel;          % unified with panel; section
                                            % headers no longer carry a
                                            % distinct background tint.
hdrFG      = tkFV_.color.textHighlight;
statusFG   = tkFV_.color.textDim;
filenameFG = tkFV_.color.textHighlight;
sepFG      = tkFV_.color.textDim;
editBG     = tkFV_.color.bgInput;
editFG     = tkFV_.color.text;
% Pure black/white axes background — kept as literals because the
% image viewer needs maximum contrast against arbitrary pixel data,
% and uxTokens has no axes-specific token (every other consumer
% uses the panel background).
if appData.darkMode
    axBG = [0 0 0];
    ui.btnThemeToggle.Text    = char(9790);   % moon
    ui.btnThemeToggle.Tooltip = 'Switch to light mode';
else
    axBG = [1 1 1];
    ui.btnThemeToggle.Text    = char(9728);   % sun
    ui.btnThemeToggle.Tooltip = 'Switch to dark mode';
end

% ════════════════════════════════════════════════════════════════════
%  Figure
% ════════════════════════════════════════════════════════════════════
ui.fig.Color = figBG;

% ════════════════════════════════════════════════════════════════════
%  Panels
% ════════════════════════════════════════════════════════════════════
ui.listPanel.BackgroundColor  = panelBG;
ui.listPanel.ForegroundColor  = panelFG;
ui.toolsPanel.BackgroundColor = panelBG;
ui.toolsPanel.ForegroundColor = panelFG;
% Section panels
ui.pnlContrast.BackgroundColor  = panelBG;
ui.pnlHistogram.BackgroundColor = panelBG;
ui.pnlMeasure.BackgroundColor   = panelBG;
ui.pnlProcess.BackgroundColor   = panelBG;
ui.pnlExport.BackgroundColor    = panelBG;
ui.pnlAnnot.BackgroundColor     = panelBG;
ui.pnlEDS.BackgroundColor       = panelBG;

% ════════════════════════════════════════════════════════════════════
%  Section header buttons
% ════════════════════════════════════════════════════════════════════
ui.btnContrastHeader.BackgroundColor  = hdrBG;
ui.btnContrastHeader.FontColor        = hdrFG;
ui.btnHistogramHeader.BackgroundColor = hdrBG;
ui.btnHistogramHeader.FontColor       = hdrFG;
ui.btnMeasureHeader.BackgroundColor   = hdrBG;
ui.btnMeasureHeader.FontColor         = hdrFG;
ui.btnProcessHeader.BackgroundColor   = hdrBG;
ui.btnProcessHeader.FontColor         = hdrFG;
% Export header keeps its distinct accent (it's the prominent
% section in this panel). Pull both shades from uxTokens via the
% textAccent / btn.session aliases — both are theme-aware blues.
ui.btnExportHeader.BackgroundColor = tkFV_.color.btn.session;
if appData.darkMode
    ui.btnExportHeader.FontColor = tkFV_.color.btn.fg;
else
    ui.btnExportHeader.FontColor = tkFV_.color.text;
end
ui.btnAnnotHeader.BackgroundColor     = hdrBG;
ui.btnAnnotHeader.FontColor           = hdrFG;
ui.btnEDSHeader.BackgroundColor       = hdrBG;
ui.btnEDSHeader.FontColor             = hdrFG;
ui.btnEELSHeader.BackgroundColor      = hdrBG;
ui.btnEELSHeader.FontColor            = hdrFG;
ui.btnDiffHeader.BackgroundColor      = hdrBG;
ui.btnDiffHeader.FontColor            = hdrFG;
ui.btnMetaHeader.BackgroundColor      = hdrBG;
ui.btnMetaHeader.FontColor            = hdrFG;

% ════════════════════════════════════════════════════════════════════
%  Status bar labels
% ════════════════════════════════════════════════════════════════════
ui.lblStatusDims.FontColor    = statusFG;
ui.lblStatusBits.FontColor    = statusFG;
ui.lblStatusPixSize.FontColor = statusFG;
ui.lblStatusMouse.FontColor   = statusFG;

% Filename label
ui.lblFilename.FontColor = filenameFG;

% Separator labels
ui.lblSep.FontColor  = sepFG;
ui.lblSep2.FontColor = sepFG;
ui.lblSep3.FontColor = sepFG;
ui.lblSep4.FontColor = sepFG;

% ════════════════════════════════════════════════════════════════════
%  Axes
% ════════════════════════════════════════════════════════════════════
% Image axes
if ~isempty(ui.ax) && isvalid(ui.ax)
    ui.ax.Color = axBG;
end

% Histogram axes
ui.histAx.Color  = axBG;
ui.histAx.XColor = sepFG;
ui.histAx.YColor = sepFG;

% ════════════════════════════════════════════════════════════════════
%  Edit fields, textarea, and listbox
% ════════════════════════════════════════════════════════════════════
ui.taMetadata.BackgroundColor    = editBG;
ui.taMetadata.FontColor          = editFG;
ui.efRenameBase.BackgroundColor  = editBG;
ui.efRenameBase.FontColor        = editFG;
ui.efAnnotText.BackgroundColor   = editBG;
ui.efAnnotText.FontColor         = editFG;
ui.lbImages.BackgroundColor      = editBG;
ui.lbImages.FontColor            = editFG;

% ════════════════════════════════════════════════════════════════════
%  Grid layout backgrounds
% ════════════════════════════════════════════════════════════════════
ui.rootGL.BackgroundColor    = figBG;
ui.mainGL.BackgroundColor    = figBG;
ui.toolbarGL.BackgroundColor = figBG;
ui.statusGL.BackgroundColor  = figBG;
ui.listGL.BackgroundColor    = panelBG;

% Inner section grid backgrounds
try
    ui.contrastInnerGL.BackgroundColor = panelBG;
    ui.measureInnerGL.BackgroundColor  = panelBG;
    ui.processInnerGL.BackgroundColor  = panelBG;
    ui.exportInnerGL.BackgroundColor   = panelBG;
    for pg = 1:numel(ui.processTabGrids)
        ui.processTabGrids{pg}.BackgroundColor = panelBG;
    end
    ui.annotInnerGL.BackgroundColor    = panelBG;
    ui.edsInnerGL.BackgroundColor      = panelBG;
    ui.toolsGL.BackgroundColor         = panelBG;
catch
end

% ════════════════════════════════════════════════════════════════════
%  Export sub-headers and labels
% ════════════════════════════════════════════════════════════════════
ui.lblRename.FontColor     = hdrFG;
ui.lblDPI.FontColor        = hdrFG;
ui.lblPubHeader.FontColor  = statusFG;
ui.lblUtilHeader.FontColor = statusFG;

% ════════════════════════════════════════════════════════════════════
%  Re-tint transform toolbar icons for theme visibility
% ════════════════════════════════════════════════════════════════════
% Icons were drawn with near-black fg on transparent BG; re-read the
% originals each time so alpha is always correct.
if appData.darkMode
    iconFG_ = uint8([255 255 255]);
else
    iconFG_ = uint8([51 51 56]);   % matches build_icons fg [0.20 0.20 0.22]
end
if isfield(appData, 'toolbarIconPaths') && isfield(appData, 'transformToolbarBtns')
    for tiK_ = 1:numel(appData.transformToolbarBtns)
        btn_ = appData.transformToolbarBtns(tiK_);
        if isempty(btn_) || ~isgraphics(btn_) || ~isvalid(btn_), continue; end
        if tiK_ > numel(appData.toolbarIconPaths), break; end
        iPath_ = appData.toolbarIconPaths{tiK_};
        if ~isfile(iPath_), continue; end
        [img_, ~, alpha_] = imread(iPath_);
        mask_ = alpha_ > 0;
        for ch_ = 1:3
            pl_ = img_(:,:,ch_);
            pl_(mask_) = iconFG_(ch_);
            img_(:,:,ch_) = pl_;
        end
        btn_.Icon = img_;
    end
end
end
