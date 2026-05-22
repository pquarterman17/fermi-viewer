function data = createDataStruct(timeVec, valuesMatrix, varargin)
%CREATEDATASTRUCT  Build the standard toolbox data struct.
%
%   data = createDataStruct(timeVec, valuesMatrix, ...
%               'labels', labels, 'units', units, 'metadata', meta)
%
%   All name-value pairs are optional.
%
%   OUTPUT fields:
%       .time     - [Nx1] x-axis / independent variable
%       .values   - [NxM] data matrix  (N samples, M channels)
%       .labels   - {1xM} channel name strings
%       .units    - {1xM} unit strings
%       .metadata - struct of import metadata

    % Accept empty [] as a valid "0-row dataset" — required by callers
    % that construct a placeholder struct before loading (e.g. session
    % restore, unit-test harnesses). isvector([]) is false in MATLAB,
    % so an explicit isempty bypass is needed.
    assert(isempty(timeVec) || isvector(timeVec), ...
        'parser:createDataStruct:badTime', 'timeVec must be a vector (or empty).');
    assert(ndims(valuesMatrix) <= 2, ...
        'parser:createDataStruct:badValues', 'valuesMatrix must be 2-D.');
    assert(numel(timeVec) == size(valuesMatrix, 1), ...
        'parser:createDataStruct:sizeMismatch', ...
        'timeVec length (%d) must equal valuesMatrix row count (%d).', ...
        numel(timeVec), size(valuesMatrix, 1));

    p = inputParser();
    p.addParameter('labels',   {});
    p.addParameter('units',    {});
    p.addParameter('metadata', struct());
    p.parse(varargin{:});

    M      = size(valuesMatrix, 2);
    labels = p.Results.labels;
    units  = p.Results.units;

    if isempty(labels)
        labels = arrayfun(@(k) sprintf('ch%d', k), 1:M, 'UniformOutput', false);
    end
    if isempty(units)
        units = repmat({''}, 1, M);
    end

    assert(numel(labels) == M, ...
        'parser:createDataStruct:labelCountMismatch', ...
        'Expected %d labels for %d columns, got %d.', M, M, numel(labels));
    assert(numel(units) == M, ...
        'parser:createDataStruct:unitCountMismatch', ...
        'Expected %d units for %d columns, got %d.', M, M, numel(units));

    % Deduplicate labels: append " (2)", " (3)", ... to repeated names so
    % that GUI list-box selection always maps to a unique column.
    labels = deduplicateLabels(labels);

    data.time     = timeVec;
    data.values   = valuesMatrix;
    data.labels   = labels;
    data.units    = units;
    data.metadata = p.Results.metadata;
end


function labels = deduplicateLabels(labels)
%DEDUPLICATELABELS  Append numeric suffixes to repeated label strings.
%   {'A','B','A','A'} → {'A','B','A (2)','A (3)'}
    seen = dictionary(string.empty, double.empty);
    for k = 1:numel(labels)
        lbl = labels{k};
        if isKey(seen, lbl)
            seen(lbl) = seen(lbl) + 1;
            labels{k} = sprintf('%s (%d)', lbl, seen(lbl));
        else
            seen(lbl) = 1;
        end
    end
end
