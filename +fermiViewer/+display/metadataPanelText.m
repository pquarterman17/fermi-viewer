function txt = metadataPanelText(appData)
%METADATAPANELTEXT  Text for the metadata side panel.
%   txt = fermiViewer.display.metadataPanelText(appData)
%   Returns formatMetadata for the active image, or a placeholder cell when
%   no valid image is active. Centralises a block duplicated across the
%   calibration/display callbacks.
    if appData.activeIdx >= 1 && appData.activeIdx <= numel(appData.images)
        txt = fermiViewer.display.formatMetadata(appData.images{appData.activeIdx});
    else
        txt = {'(no image loaded)'};
    end
end
