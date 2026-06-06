function [appData, r] = stackOps(action, appData, fig, varargin)
%STACKOPS  Accept-and-return stack / image-math operations for FermiViewer.
%
%   [appData, r] = fermiViewer.processing.stackOps('clahe',      appData, fig)
%   [appData, r] = fermiViewer.processing.stackOps('mip',        appData, fig)
%   [appData, r] = fermiViewer.processing.stackOps('imageMath',  appData, fig, getGrayscaleFn)
%   [appData, r] = fermiViewer.processing.stackOps('alignStack', appData, fig)
%
%   Each action prompts (where applicable), computes, and mutates the
%   LOCAL appData copy, returning it with a result struct r. r is []
%   when the user cancelled or the operation failed — the caller skips
%   its follow-ups in that case.
%
%   ORDERING CONTRACT: closure follow-ups that must observe the new
%   appData (refreshDisplay, displayImage, onContrastOp, setStatus with
%   r fields) are executed BY THE CALLER after the `appData = ...`
%   assignment. Calling them from inside this function would read the
%   parent's STALE closure copy and the work would be clobbered on
%   return — the exact hazard that blocked these extractions until the
%   follow-up-after-assignment pattern (see onStackMIP history).
%
%   r fields per action:
%       clahe      — .statusMsg
%       mip        — .nFrames, .dMin, .dMax   (caller sets slider limits,
%                    then onContrastOp('auto') + status)
%       imageMath  — .statusMsg, .applied     (caller refreshes if applied)
%       alignStack — .statusMsg               (caller calls displayImage)
%       batchCrop  — .statusMsg               (caller calls displayImage)

r = [];
switch lower(strtrim(action))
    case 'clahe',      [appData, r] = doClahe(appData, fig);
    case 'mip',        [appData, r] = doMip(appData, fig);
    case 'imagemath',  [appData, r] = doImageMath(appData, fig, varargin{1});
    case 'alignstack', [appData, r] = doAlignStack(appData, fig);
    case 'batchcrop',  [appData, r] = doBatchCrop(appData, varargin{1:4});
    otherwise
        error('fermiViewer:processing:stackOps:unknownAction', ...
            'Unknown action: ''%s''', action);
end
end


% ════════════════════════════════════════════════════════════════════
%  clahe — prompt for tile/clip, run CLAHE on filteredPixels
% ════════════════════════════════════════════════════════════════════
function [appData, r] = doClahe(appData, fig)
    r = [];
    if isempty(appData.filteredPixels), return; end
    answer = inputdlg( ...
        {'Tile size (pixels per tile, e.g. 64):', ...
         'Clip limit (contrast factor, e.g. 3.0):'}, ...
        'CLAHE Parameters', [1 44], {'64', '3.0'});
    if isempty(answer), return; end
    tileSize  = round(str2double(answer{1}));
    clipLimit = str2double(answer{2});
    if isnan(tileSize) || tileSize < 8
        fermiViewer.chrome.quietAlert(fig, 'Tile size must be >= 8.', ...
            'Invalid Input', 'Icon', 'error'); return;
    end
    if isnan(clipLimit) || clipLimit <= 0
        fermiViewer.chrome.quietAlert(fig, 'Clip limit must be positive.', ...
            'Invalid Input', 'Icon', 'error'); return;
    end
    fig.Pointer = 'watch'; drawnow;
    try
        appData = fermiViewer.display.pushUndo(appData);   % undoPush in try only
        res = fermiViewer.processing.executeFilter(appData.filteredPixels, 'clahe', ...
            struct('tileSize', tileSize, 'clipLimit', clipLimit));
        appData.filteredPixels = res.pixels;
        r.statusMsg = res.statusMsg;
    catch ME
        fermiViewer.chrome.quietAlert(fig, sprintf('CLAHE failed:\n%s', ME.message), ...
            'Filter Error', 'Icon', 'error');
    end
    fig.Pointer = 'arrow';
end


% ════════════════════════════════════════════════════════════════════
%  mip — Maximum Intensity Projection across all stack frames
% ════════════════════════════════════════════════════════════════════
function [appData, r] = doMip(appData, fig)
    r = [];
    if isempty(appData.stackFrames), return; end

    fig.Pointer = 'watch'; drawnow;

    nFrames = numel(appData.stackFrames);
    [H2, W2] = size(appData.stackFrames{1});
    stack3D = zeros(H2, W2, nFrames);
    for fm = 1:nFrames
        frame = appData.stackFrames{fm};
        [fh, fw] = size(frame);
        mh = min(H2, fh); mw = min(W2, fw);
        stack3D(1:mh, 1:mw, fm) = frame(1:mh, 1:mw);
    end

    mipImg = max(stack3D, [], 3);

    appData.rawPixels      = mipImg;
    appData.filteredPixels = mipImg;

    dMin = min(mipImg(:));
    dMax = max(mipImg(:));
    if dMax == dMin, dMax = dMin + 1; end

    r.nFrames = nFrames;
    r.dMin    = dMin;
    r.dMax    = dMax;
    fig.Pointer = 'arrow';
end


% ════════════════════════════════════════════════════════════════════
%  imageMath — prompt for A/B/op, run arithmetic between loaded images
% ════════════════════════════════════════════════════════════════════
function [appData, r] = doImageMath(appData, fig, getGrayscaleFn)
    r = [];
    if numel(appData.images) < 2, return; end
    names = cell(1, numel(appData.images));
    for mi = 1:numel(appData.images)
        [~, fn, fe] = fileparts(appData.images{mi}.metadata.source);
        names{mi} = sprintf('%d: %s%s', mi, fn, fe);
    end
    answer = inputdlg( ...
        {'Image A (index):', 'Image B (index):', ...
         'Operation (subtract, divide, ratio, add):'}, ...
        'Image Arithmetic', [1 44], {num2str(1), num2str(2), 'subtract'});
    if isempty(answer), return; end
    idxA = str2double(answer{1}); idxB = str2double(answer{2});
    op = lower(strtrim(answer{3}));
    if isnan(idxA) || isnan(idxB) || idxA < 1 || idxB < 1 || ...
            idxA > numel(appData.images) || idxB > numel(appData.images)
        fermiViewer.chrome.quietAlert(fig, 'Invalid image indices.', 'Error', 'Icon', 'error');
        return;
    end
    try
        res = fermiViewer.processing.executeImageMath( ...
            getGrayscaleFn(idxA), getGrayscaleFn(idxB), op, names{idxA});
    catch ME
        fermiViewer.chrome.quietAlert(fig, ME.message, 'Error', 'Icon', 'error'); return;
    end
    applied = appData.activeIdx >= 1 && ~isempty(appData.imgHandle) ...
        && isvalid(appData.imgHandle);
    if applied
        appData = fermiViewer.display.pushUndo(appData);
        appData.rawPixels      = res.pixels;
        appData.filteredPixels = res.pixels;
    end
    r.applied   = applied;
    r.statusMsg = sprintf('Image math: %s (A=%d, B=%d)', op, idxA, idxB);
end


% ════════════════════════════════════════════════════════════════════
%  alignStack — cross-correlation drift correction over loaded images
% ════════════════════════════════════════════════════════════════════
function [appData, r] = doAlignStack(appData, fig)
    r = [];
    if numel(appData.images) < 2
        fermiViewer.chrome.quietAlert(fig, 'Need at least 2 images to align.', ...
            'Align Stack', 'Icon', 'warning'); return;
    end
    answer = questdlg( ...
        sprintf('Align %d loaded images using cross-correlation?\nThe first image is the reference.', ...
        numel(appData.images)), 'Drift Correction', 'Align', 'Cancel', 'Align');
    if ~strcmp(answer, 'Align'), return; end
    fig.Pointer = 'watch'; drawnow;
    try
        res = fermiViewer.processing.executeAlignStack(appData.images);
        appData.images = res.images;
        fig.Pointer = 'arrow';
        fermiViewer.chrome.quietAlert(fig, sprintf('Alignment complete:\n\n%s', res.shiftStr), ...
            'Drift Correction', 'Icon', 'info');
        appData.procWorkshop.recordAlignment(res.shifts);
        r.statusMsg = res.statusMsg;
    catch ME
        fig.Pointer = 'arrow';
        fermiViewer.chrome.quietAlert(fig, sprintf('Alignment failed:\n%s', ME.message), ...
            'Error', 'Icon', 'error');
    end
end


% ════════════════════════════════════════════════════════════════════
%  batchCrop — apply the same crop region to all loaded images
% ════════════════════════════════════════════════════════════════════
function [appData, r] = doBatchCrop(appData, xMin, xMax, yMin, yMax)
    nCropped = 0;
    for ci = 1:numel(appData.images)
        try
            imgInfo = appData.images{ci}.metadata.parserSpecific.imageData;
            px = imgInfo.pixels;
            [pH, pW, ~] = size(px);
            x1 = max(1, min(pW, xMin));
            x2 = max(1, min(pW, xMax));
            y1 = max(1, min(pH, yMin));
            y2 = max(1, min(pH, yMax));
            if x2 > x1 && y2 > y1
                appData.images{ci}.metadata.parserSpecific.imageData.pixels = px(y1:y2, x1:x2, :);
                [newH, newW, ~] = size(appData.images{ci}.metadata.parserSpecific.imageData.pixels);
                appData.images{ci}.metadata.parserSpecific.imageData.width  = newW;
                appData.images{ci}.metadata.parserSpecific.imageData.height = newH;
                nCropped = nCropped + 1;
            end
        catch
        end
    end
    r.statusMsg = sprintf('Batch crop applied to %d / %d images [%d:%d, %d:%d]', ...
        nCropped, numel(appData.images), xMin, xMax, yMin, yMax);
end
