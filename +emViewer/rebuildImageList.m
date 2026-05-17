function rebuildImageList(images, activeIdx, lbImages)
%REBUILDIMAGELIST  Sync the image listbox with the current images array.
%
%   Syntax
%     emViewer.rebuildImageList(images, activeIdx, lbImages)
%
%   Inputs
%     images    — cell array of image structs (appData.images)
%     activeIdx — currently active image index (appData.activeIdx)
%     lbImages  — uilistbox handle for the image list
%
%   Outputs
%     (none — updates lbImages in-place; handle is pass-by-reference)
%
%   Examples
%     emViewer.rebuildImageList(appData.images, appData.activeIdx, lbImages);

if isempty(images)
    lbImages.Items     = {'(no images loaded)'};
    lbImages.ItemsData = {0};
    return;
end

items = cell(1, numel(images));
idata = cell(1, numel(images));
for k = 1:numel(images)
    [~, fname, fext] = fileparts(images{k}.metadata.source);
    items{k} = [fname, fext];
    idata{k} = k;
end

lbImages.Items     = items;
lbImages.ItemsData = idata;

% Restore selection to active index
if activeIdx >= 1 && activeIdx <= numel(images)
    lbImages.Value = {activeIdx};
end
end
