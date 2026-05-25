function appData = pushUndo(appData)
%PUSHUNDO  Push the current pixel state onto the undo stack (accept-and-return).
%
%   appData = fermiViewer.display.pushUndo(appData)
%
%   Snapshots {rawPixels, filteredPixels} and appends it to
%   appData.undoStack, capped at appData.undoStackMax (oldest discarded).
%
%   ACCEPT-AND-RETURN CONTRACT — read carefully. This MUST be called as
%   `appData = fermiViewer.display.pushUndo(appData)`. Package functions
%   (filterOps, processActions, rotateFlip, captureDispatch, ...) hold a
%   LOCAL copy of appData and return it to the caller. The previous design
%   pushed via a fire-and-forget closure callback `cb.undoPush()`, which
%   mutated the *closure's* appData; the package function then returned its
%   own local appData, silently clobbering the push. That lost the snapshot
%   and broke undo for any operation that also changes rawPixels (crop,
%   rotate) — the canonical "can't undo a crop" bug. Pushing onto the local
%   appData here, and returning it, keeps the snapshot in the value that the
%   caller actually assigns back.

    if ~isfield(appData, 'undoStack'),    appData.undoStack    = {}; end
    if ~isfield(appData, 'undoStackMax'), appData.undoStackMax = 5;  end

    appData.undoStack{end+1} = {appData.rawPixels, appData.filteredPixels};
    if numel(appData.undoStack) > appData.undoStackMax
        appData.undoStack(1) = [];   % discard oldest
    end
end
