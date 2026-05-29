function varargout = calibrationStore(action, varargin)
%CALIBRATIONSTORE  Persistent microscope calibration database (prefdir-backed).
%
%   Read/write a small table of (instrument, mode, magnification | camera
%   length) → pixel-size entries so a known acquisition mode can be
%   auto-calibrated on import instead of per-image only.
%
% Syntax
%   entries = fermiViewer.calibration.calibrationStore('load')
%   fermiViewer.calibration.calibrationStore('save', entries)
%   entries = fermiViewer.calibration.calibrationStore('add', entry)
%   entries = fermiViewer.calibration.calibrationStore('remove', idx)
%   entries = fermiViewer.calibration.calibrationStore('clear')
%   match   = fermiViewer.calibration.calibrationStore('match', instrument, keyType, keyValue)
%   tmpl    = fermiViewer.calibration.calibrationStore('template')
%   p       = fermiViewer.calibration.calibrationStore('path')
%   fermiViewer.calibration.calibrationStore('setPath', p)   % test override; '' resets
%
% Entry struct fields (canonical order, see 'template'):
%   instrument  char    microscope name/ID ('' = wildcard, matches any)
%   mode        char    'imaging' | 'diffraction' | free text
%   keyType     char    'mag' | 'cameraLength'
%   keyValue    double  magnification (×) or camera length (mm)
%   pixelSize   double  physical size of one pixel (> 0)
%   pixelUnit   char    'nm', 'um', 'A', 'mm', ...
%   detector    char    optional detector/camera name ('' default)
%   dateAdded   char    ISO date the entry was stored
%
% Behaviour
%   The store is a tiny .mat file in `prefdir` (variable `entries`,
%   a struct array) shared across FermiViewer sessions. Reads are
%   best-effort: a missing/corrupt file returns an empty 1x0 struct
%   array with the canonical fields. Writes are best-effort and silent
%   on failure so a read-only prefdir never blocks the GUI.
%
%   'add' replaces an existing entry with the same instrument
%   (case-insensitive), keyType, and keyValue (within MATCH_TOL); else
%   it appends. 'match' returns the closest entry whose instrument,
%   keyType, and keyValue agree within MATCH_TOL, or [] if none.
%
% See also FERMIVIEWER.CALIBRATION.EXTRACTCALIBRATIONKEY,
%          FERMIVIEWER.CALIBRATION.AUTOAPPLYFROMDATABASE

    persistent STORE_PATH
    if isempty(STORE_PATH)
        STORE_PATH = defaultPath();
    end

    % Relative tolerance for treating two key values as the same mode.
    MATCH_TOL = 0.01;   % 1%

    switch lower(string(action))
        case "path"
            varargout{1} = STORE_PATH;

        case "setpath"
            if nargin >= 2 && ~isempty(varargin{1}) && ...
                    (ischar(varargin{1}) || isstring(varargin{1}))
                STORE_PATH = char(varargin{1});
            else
                STORE_PATH = defaultPath();   % '' / no-arg resets to prefdir
            end

        case "template"
            varargout{1} = entryTemplate();

        case "load"
            varargout{1} = loadEntries(STORE_PATH);

        case "save"
            entries = normalizeEntries(varargin{1});
            saveEntries(STORE_PATH, entries);
            if nargout > 0, varargout{1} = entries; end

        case "clear"
            entries = emptyEntries();
            saveEntries(STORE_PATH, entries);
            varargout{1} = entries;

        case "add"
            entry   = normalizeEntries(varargin{1});
            assert(isscalar(entry), 'fermiViewer:calibrationStore:addScalar', ...
                '''add'' takes a single entry struct.');
            entries = loadEntries(STORE_PATH);
            dupIdx  = findMatchIdx(entries, entry.instrument, entry.keyType, ...
                                   entry.keyValue, MATCH_TOL);
            if isempty(dupIdx)
                entries(end+1) = entry;
            else
                entries(dupIdx(1)) = entry;   % overwrite the matching mode
            end
            saveEntries(STORE_PATH, entries);
            varargout{1} = entries;

        case "remove"
            idx     = varargin{1};
            entries = loadEntries(STORE_PATH);
            keep    = true(1, numel(entries));
            idx     = idx(idx >= 1 & idx <= numel(entries));
            keep(idx) = false;
            entries = entries(keep);
            saveEntries(STORE_PATH, entries);
            varargout{1} = entries;

        case "match"
            [instrument, keyType, keyValue] = deal(varargin{1}, varargin{2}, varargin{3});
            entries = loadEntries(STORE_PATH);
            mIdx    = findMatchIdx(entries, instrument, keyType, keyValue, MATCH_TOL);
            if isempty(mIdx)
                varargout{1} = [];
            else
                varargout{1} = entries(mIdx(1));
            end

        otherwise
            error('fermiViewer:calibrationStore:badAction', ...
                'Unknown action ''%s''.', char(action));
    end
end

% ════════════════════════════════════════════════════════════════════════
function p = defaultPath()
    p = fullfile(prefdir, 'fermi_calibration_store.mat');
end

function tmpl = entryTemplate()
%ENTRYTEMPLATE  Scalar struct with canonical fields and default values.
    tmpl = struct( ...
        'instrument', '', ...
        'mode',       'imaging', ...
        'keyType',    'mag', ...
        'keyValue',   NaN, ...
        'pixelSize',  NaN, ...
        'pixelUnit',  'nm', ...
        'detector',   '', ...
        'dateAdded',  '');
end

function e = emptyEntries()
%EMPTYENTRIES  1x0 struct array carrying the canonical fields.
    e = entryTemplate();
    e = e(false);
end

function entries = loadEntries(p)
    entries = emptyEntries();
    try
        if isfile(p)
            s = load(p, 'entries');
            if isfield(s, 'entries')
                entries = normalizeEntries(s.entries);
            end
        end
    catch
        entries = emptyEntries();   % silent fallback on corrupt file
    end
end

function saveEntries(p, entries) %#ok<INUSD>
    try
        save(p, 'entries');
    catch
        % Best-effort: silent on write failure (read-only prefdir, etc.)
    end
end

function out = normalizeEntries(in)
%NORMALIZEENTRIES  Coerce arbitrary input to a canonical struct array.
%   Tolerates missing fields, extra fields, and row/column orientation.
    if isempty(in)
        out = emptyEntries();
        return;
    end
    if ~isstruct(in)
        error('fermiViewer:calibrationStore:badEntry', ...
            'Entries must be a struct or struct array.');
    end
    tmpl   = entryTemplate();
    fnames = fieldnames(tmpl);
    out    = emptyEntries();
    for k = 1:numel(in)
        e = tmpl;
        for f = 1:numel(fnames)
            fn = fnames{f};
            if isfield(in, fn) && ~isempty(in(k).(fn))
                e.(fn) = in(k).(fn);
            end
        end
        % Light type coercion for the fields we sort/compare on.
        e.instrument = char(string(e.instrument));
        e.mode       = char(string(e.mode));
        e.keyType    = char(string(e.keyType));
        e.pixelUnit  = char(string(e.pixelUnit));
        e.detector   = char(string(e.detector));
        e.dateAdded  = char(string(e.dateAdded));
        e.keyValue   = double(e.keyValue);
        e.pixelSize  = double(e.pixelSize);
        out(end+1) = e; %#ok<AGROW>
    end
end

function idx = findMatchIdx(entries, instrument, keyType, keyValue, tol)
%FINDMATCHIDX  Indices of entries matching (instrument, keyType, keyValue).
%   Sorted by ascending key-value distance so idx(1) is the closest.
%   instrument matches case-insensitively; a stored empty instrument is a
%   wildcard that matches any query instrument.
    idx = [];
    if isempty(entries) || ~fermiViewer.calibration.isValidPixelSize(keyValue)
        return;
    end
    instrument = char(string(instrument));
    keyType    = char(string(keyType));
    dist       = inf(1, numel(entries));
    for k = 1:numel(entries)
        e = entries(k);
        if ~strcmpi(e.keyType, keyType),           continue; end
        if ~isempty(e.instrument) && ~strcmpi(e.instrument, instrument)
            continue;
        end
        if ~fermiViewer.calibration.isValidPixelSize(e.keyValue), continue; end
        rel = abs(e.keyValue - keyValue) / max(abs(keyValue), eps);
        if rel <= tol
            dist(k) = rel;
        end
    end
    cand = find(isfinite(dist));
    if isempty(cand), return; end
    [~, order] = sort(dist(cand));
    idx = cand(order);
end
