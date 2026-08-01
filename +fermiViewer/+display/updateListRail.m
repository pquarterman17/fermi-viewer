function updateListRail(tbl, activeIdx)
%UPDATELISTRAIL  Move the accent rail to the active image's row.
%
%   Syntax
%     fermiViewer.display.updateListRail(tbl, activeIdx)
%
%   Inputs
%     tbl       — the image-list uitable (column 1 is the 8 px rail
%                 column; UserData carries .hasImages and .accentColor)
%     activeIdx — currently active image index (appData.activeIdx)
%
%   Outputs
%     (none — restyles tbl in place)
%
%   The rail is a BackgroundColor style on the [activeIdx 1] cell. Any
%   previous rail (every cell style targeting column 1) is removed first;
%   thumbnail icon styles live on column 2 and are untouched.
%
%   Examples
%     fermiViewer.display.updateListRail(ui.lbImages, appData.activeIdx);

    if isempty(tbl) || ~isvalid(tbl), return; end
    ud = tbl.UserData;
    if ~isstruct(ud) || ~isfield(ud, 'hasImages') || ~ud.hasImages
        return;
    end
    n = size(tbl.Data, 1);
    if activeIdx < 1 || activeIdx > n, return; end

    sc = tbl.StyleConfigurations;
    for k = height(sc):-1:1
        tgt = sc.TargetIndex{k};
        if sc.Target(k) == "cell" && ~isempty(tgt) && all(tgt(:, 2) == 1)
            removeStyle(tbl, k);
        end
    end

    accent = [0.345 0.689 0.911];   % uxTokens dark accent (fallback)
    if isfield(ud, 'accentColor') && ~isempty(ud.accentColor)
        accent = ud.accentColor;
    end
    addStyle(tbl, uistyle('BackgroundColor', accent), 'cell', [activeIdx 1]);
end
