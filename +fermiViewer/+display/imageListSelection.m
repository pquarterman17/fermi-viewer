function idx = imageListSelection(tbl)
%IMAGELISTSELECTION  Image indices currently selected in the image list.
%
%   Syntax
%     idx = fermiViewer.display.imageListSelection(tbl)
%
%   Inputs
%     tbl — the image-list uitable (SelectionType='row'; rows map 1:1 to
%           appData.images indices; UserData.hasImages flags the
%           placeholder "(no images loaded)" state)
%
%   Outputs
%     idx — row vector of selected image indices; [] when nothing is
%           selected or the list is in its placeholder state
%
%   Examples
%     sel = fermiViewer.display.imageListSelection(lbImages);
%     if isempty(sel), return; end

    idx = [];
    if isempty(tbl) || ~isvalid(tbl), return; end
    ud = tbl.UserData;
    if ~isstruct(ud) || ~isfield(ud, 'hasImages') || ~ud.hasImages
        return;
    end
    sel = tbl.Selection;
    if isempty(sel), return; end
    idx = double(reshape(sel, 1, []));
end
