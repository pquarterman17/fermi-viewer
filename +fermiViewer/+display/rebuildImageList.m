function rebuildImageList(images, activeIdx, lbImages)
%REBUILDIMAGELIST  Sync the image-list table with the current images array.
%
%   Syntax
%     fermiViewer.display.rebuildImageList(images, activeIdx, lbImages)
%
%   Inputs
%     images    — cell array of image structs (appData.images)
%     activeIdx — currently active image index (appData.activeIdx)
%     lbImages  — image-list uitable (2 columns: 8 px accent rail + name;
%                 handle is pass-by-reference, updated in place)
%
%   Outputs
%     (none)
%
%   Renderer (gui-redesign #7): each row shows a 16 px thumbnail icon
%   (uistyle Icon, R2022a+) beside the file name, and the accent rail in
%   column 1 marks the active image. Rows map 1:1 to image indices —
%   selection state IS the image index (see imageListSelection). The
%   placeholder "(no images loaded)" state is flagged via
%   UserData.hasImages so selection readers can ignore it.
%
%   Examples
%     fermiViewer.display.rebuildImageList(appData.images, appData.activeIdx, lbImages);

removeStyle(lbImages);   % drop all thumbnail + rail styles before rebuild

if isempty(images)
    lbImages.Data      = {'', '(no images loaded)'};
    lbImages.Selection = [];
    ud = lbImages.UserData; ud.hasImages = false; lbImages.UserData = ud;
    return;
end

n = numel(images);
D = cell(n, 2);
for k = 1:n
    [~, fname, fext] = fileparts(images{k}.metadata.source);
    D{k, 1} = '';
    D{k, 2} = [fname, fext];
end
lbImages.Data = D;
ud = lbImages.UserData; ud.hasImages = true; lbImages.UserData = ud;

for k = 1:n
    thumb = fermiViewer.display.imageThumbnail(images{k});
    if ~isempty(thumb)
        addStyle(lbImages, uistyle('Icon', thumb), 'cell', [k 2]);
    end
end

% Restore selection + rail to the active image
if activeIdx >= 1 && activeIdx <= n
    lbImages.Selection = activeIdx;
    fermiViewer.display.updateListRail(lbImages, activeIdx);
end
end
