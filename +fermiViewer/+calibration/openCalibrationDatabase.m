function openCalibrationDatabase(fig, getImages, getActiveIdx, applyCalibration, setStatus)
%OPENCALIBRATIONDATABASE  Manage the persistent microscope calibration store.
%
%   fermiViewer.calibration.openCalibrationDatabase(fig, getImages, ...
%       getActiveIdx, applyCalibration, setStatus)
%
%   Opens a modal editor over the calibration database
%   (fermiViewer.calibration.calibrationStore). The table lists every
%   stored (instrument, mode, magnification | camera length) → pixel-size
%   entry; cells are editable in place. Buttons:
%     • Add Current  — append an entry from the active image's metadata
%                      (mag/camera-length) + current pixel calibration.
%     • Remove       — delete the selected row(s).
%     • Apply        — calibrate the active image from the selected row.
%     • Close        — dismiss.
%
%   Arguments (live getters / callbacks supplied by FermiViewer so the
%   dialog always sees current state):
%     getImages        @() -> appData.images cell array
%     getActiveIdx     @() -> active image index (0 if none)
%     applyCalibration @(pixelSize, unit) -> apply to the active image
%     setStatus        @(msg) -> write the status bar
%
% See also FERMIVIEWER.CALIBRATION.CALIBRATIONSTORE

    arguments
        fig
        getImages        function_handle
        getActiveIdx     function_handle
        applyCalibration function_handle
        setStatus        function_handle
    end

    themeName = fermiViewer.chrome.resolveTheme(fermiViewer.chrome.themePref('read'));
    tk = fermiViewer.chrome.uxTokens(lower(themeName));

    COLS = {'Instrument', 'Mode', 'Key Type', 'Key Value', ...
            'Pixel Size', 'Unit', 'Detector', 'Added'};

    dlg = uifigure('Name', 'Calibration Database', 'Position', [300 250 720 360]);
    try, dlg.Color = tk.color.bgFigure; catch, end
    gl = uigridlayout(dlg, [2 1], 'RowHeight', {'1x', 34}, ...
        'Padding', [10 10 10 10], 'RowSpacing', 8);
    try, gl.BackgroundColor = tk.color.bgFigure; catch, end

    tbl = uitable(gl, ...
        'ColumnName', COLS, ...
        'ColumnEditable', [true true true true true true true false], ...
        'ColumnFormat', {'char', 'char', {'mag', 'cameraLength'}, ...
                         'numeric', 'numeric', 'char', 'char', 'char'}, ...
        'RowName', {}, ...
        'SelectionType', 'row', ...
        'CellEditCallback', @(~, evt) onCellEdit(evt));
    tbl.Layout.Row = 1;
    try
        tbl.BackgroundColor = tk.color.bgTable;
        tbl.FontColor       = tk.color.text;
    catch
    end

    btnRow = uigridlayout(gl, [1 5], ...
        'ColumnWidth', {'1x', 110, 90, 110, 90}, ...
        'Padding', [0 0 0 0], 'ColumnSpacing', 6);
    btnRow.Layout.Row = 2;
    try, btnRow.BackgroundColor = tk.color.bgFigure; catch, end

    uilabel(btnRow, 'Text', '');   % spacer (auto-fills column 1)
    uibutton(btnRow, 'Text', 'Add Current', ...
        'ButtonPushedFcn', @(~, ~) onAddCurrent());
    uibutton(btnRow, 'Text', 'Remove', ...
        'ButtonPushedFcn', @(~, ~) onRemove());
    uibutton(btnRow, 'Text', 'Apply', ...
        'ButtonPushedFcn', @(~, ~) onApply());
    uibutton(btnRow, 'Text', 'Close', ...
        'ButtonPushedFcn', @(~, ~) close(dlg));

    refresh();

    % ── nested helpers (local to this package fn; not counted vs the
    %    FermiViewer.m nested-function budget) ───────────────────────────
    function refresh()
        entries = fermiViewer.calibration.calibrationStore('load');
        tbl.Data = entriesToCell(entries);
    end

    function onCellEdit(~)
        % Rebuild the entire store from the table on any edit (small table).
        entries = cellToEntries(tbl.Data);
        fermiViewer.calibration.calibrationStore('save', entries);
        refresh();
    end

    function onAddCurrent()
        imgData = activeImageData();
        if isempty(imgData)
            fermiViewer.chrome.quietAlert(dlg, 'No active image.', ...
                'Add Current', 'Icon', 'warning');
            return;
        end
        if ~(isfield(imgData, 'calibrated') && imgData.calibrated && ...
                fermiViewer.calibration.isValidPixelSize(imgData.pixelSize))
            fermiViewer.chrome.quietAlert(dlg, ...
                'The active image is not calibrated. Calibrate it first.', ...
                'Add Current', 'Icon', 'warning');
            return;
        end
        key = fermiViewer.calibration.extractCalibrationKey(imgData);
        if ~key.found
            fermiViewer.chrome.quietAlert(dlg, ...
                ['The active image has no magnification / camera-length in ' ...
                 'its metadata, so it cannot be keyed in the database.'], ...
                'Add Current', 'Icon', 'warning');
            return;
        end
        entry = fermiViewer.calibration.calibrationStore('template');
        entry.instrument = key.instrument;
        entry.mode       = key.mode;
        entry.keyType    = key.keyType;
        entry.keyValue   = key.keyValue;
        entry.pixelSize  = imgData.pixelSize;
        if isfield(imgData, 'pixelUnit') && ~isempty(imgData.pixelUnit)
            entry.pixelUnit = char(string(imgData.pixelUnit));
        end
        entry.dateAdded  = datestr(now, 'yyyy-mm-dd'); %#ok<TNOW1,DATST>
        fermiViewer.calibration.calibrationStore('add', entry);
        refresh();
        setStatus(sprintf('Added calibration entry: %s %g (%.4g %s/px)', ...
            entry.keyType, entry.keyValue, entry.pixelSize, entry.pixelUnit));
    end

    function onRemove()
        sel = tbl.Selection;
        if isempty(sel)
            return;
        end
        rows = unique(sel(:, 1));   % SelectionType 'row' → [row, col] pairs
        fermiViewer.calibration.calibrationStore('remove', rows(:)');
        refresh();
    end

    function onApply()
        sel = tbl.Selection;
        if isempty(sel)
            fermiViewer.chrome.quietAlert(dlg, 'Select a row to apply.', ...
                'Apply', 'Icon', 'warning');
            return;
        end
        if getActiveIdx() < 1
            fermiViewer.chrome.quietAlert(dlg, 'No active image.', ...
                'Apply', 'Icon', 'warning');
            return;
        end
        entries = fermiViewer.calibration.calibrationStore('load');
        r = sel(1, 1);
        if r < 1 || r > numel(entries)
            return;
        end
        e = entries(r);
        if ~fermiViewer.calibration.isValidPixelSize(e.pixelSize)
            fermiViewer.chrome.quietAlert(dlg, 'Selected entry has no valid pixel size.', ...
                'Apply', 'Icon', 'error');
            return;
        end
        applyCalibration(e.pixelSize, e.pixelUnit);
        setStatus(sprintf('Applied %.4g %s/px from calibration database.', ...
            e.pixelSize, e.pixelUnit));
    end

    function imgData = activeImageData()
        imgData = [];
        try
            images = getImages();
            idx    = getActiveIdx();
            if idx >= 1 && idx <= numel(images)
                imgData = images{idx}.metadata.parserSpecific.imageData;
            end
        catch
            imgData = [];
        end
    end
end

% ════════════════════════════════════════════════════════════════════════
function c = entriesToCell(entries)
    if isempty(entries)
        c = cell(0, 8);
        return;
    end
    n = numel(entries);
    c = cell(n, 8);
    for k = 1:n
        e = entries(k);
        c(k, :) = {e.instrument, e.mode, e.keyType, e.keyValue, ...
                   e.pixelSize, e.pixelUnit, e.detector, e.dateAdded};
    end
end

function entries = cellToEntries(c)
    tmpl = fermiViewer.calibration.calibrationStore('template');
    entries = tmpl; entries = entries(false);
    if isempty(c), return; end
    for k = 1:size(c, 1)
        e = tmpl;
        e.instrument = char(string(c{k, 1}));
        e.mode       = char(string(c{k, 2}));
        e.keyType    = char(string(c{k, 3}));
        e.keyValue   = toNum(c{k, 4});
        e.pixelSize  = toNum(c{k, 5});
        e.pixelUnit  = char(string(c{k, 6}));
        e.detector   = char(string(c{k, 7}));
        e.dateAdded  = char(string(c{k, 8}));
        entries(end+1) = e; %#ok<AGROW>
    end
end

function v = toNum(x)
    if isnumeric(x)
        v = double(x);
    else
        v = str2double(string(x));
    end
end
