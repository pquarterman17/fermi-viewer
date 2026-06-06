function writeMiniDM4(targetPath, spec)
%WRITEMINIDM4  Generate a minimal synthetic Gatan DM4 file for parser tests.
%   writeMiniDM4(path, spec) writes a valid DM4 tag tree containing one
%   ImageList entry, so importDM4's format contracts (dimension order,
%   energy-dimension detection, calibration conventions) can be tested in
%   CI without large real instrument files. The writer was validated
%   against importDM4 after importDM4 itself was verified on real GMS
%   files (Zenodo 8403583, 2026-06-06) — the parser is the oracle.
%
%   spec fields:
%       .dims      [d0] | [d0 d1] | [d0 d1 d2]  Dimensions.0/.1/.2 sizes
%       .data      numeric array, FILE order (d0 varies fastest), numel
%                  == prod(dims). uint16 or single.
%       .dataType  DM DataType code: 10 (uint16) or 2 (single)
%       .cal       struct array, one per dim (may be shorter):
%                    .scale  double   .origin double   .units  char
%
%   Layout written (DM4 = version 4, 8-byte structural ints, big-endian
%   structure / little-endian data):
%       ImageList.0.ImageData.{DataType, Dimensions.K, Data,
%                              Calibrations.Dimension.K.{Scale,Origin,Units}}
%
%   See tests/parser/test_dm_si_contract.m for usage.

    arguments
        targetPath (1,1) string
        spec       (1,1) struct
    end

    dims = spec.dims(:)';
    assert(numel(spec.data) == prod(dims), ...
        'writeMiniDM4: numel(data)=%d but prod(dims)=%d', numel(spec.data), prod(dims));

    switch spec.dataType
        case 10, elemType = 4;  payloadFn = @(v) typecast(uint16(v), 'uint8');
        case 2,  elemType = 6;  payloadFn = @(v) typecast(single(v), 'uint8');
        otherwise
            error('writeMiniDM4: unsupported dataType %d (use 10 or 2)', spec.dataType);
    end

    % ── ImageData children ────────────────────────────────────────────
    dimTags = uint8([]);
    for k = 1:numel(dims)
        dimTags = [dimTags, scalarTag(sprintf('%d', k-1), 5, dims(k))]; %#ok<AGROW>
    end

    calDimTags = uint8([]);
    nCal = 0;
    if isfield(spec, 'cal')
        nCal = numel(spec.cal);
        for k = 1:nCal
            c = spec.cal(k);
            inner = [scalarTag('Scale', 7, c.scale), ...
                     scalarTag('Origin', 7, c.origin), ...
                     stringTag('Units', c.units)];
            calDimTags = [calDimTags, groupTag(sprintf('%d', k-1), inner, 3)]; %#ok<AGROW>
        end
    end

    imageDataChildren = [ ...
        scalarTag('DataType', 5, spec.dataType), ...
        groupTag('Dimensions', dimTags, numel(dims)), ...
        groupTag('Calibrations', ...
            groupTag('Dimension', calDimTags, nCal), 1), ...
        arrayTag('Data', elemType, payloadFn(spec.data(:)'))];

    imageData = groupTag('ImageData', imageDataChildren, 4);
    entry0    = groupTag('0', imageData, 1);
    imageList = groupTag('ImageList', entry0, 1);

    % ── Root: version 4, rootDirSize (skipped by parser), LE data flag,
    %    then a depth-0 group: sorted, open, nTags, entries ─────────────
    root = [be32(4), be64(numel(imageList) + 10), be32(1), ...
            uint8(1), uint8(1), be64(1), imageList];

    fid = fopen(char(targetPath), 'wb');
    assert(fid ~= -1, 'writeMiniDM4: cannot open "%s" for writing', targetPath);
    fwrite(fid, root, 'uint8');
    fclose(fid);
end


% ════════════════════════════════════════════════════════════════════
%  Tag serializers — structural fields big-endian, payloads little-endian
% ════════════════════════════════════════════════════════════════════

function bytes = groupTag(label, childBytes, nChildren)
%GROUPTAG  Type-20 entry: label + groupDirSize + sorted/open + nTags + children.
    content = [be64(numel(childBytes) + 10), uint8(1), uint8(1), ...
               be64(nChildren), childBytes];
    bytes = [uint8(20), labelBytes(label), content];
end

function bytes = dataTag(label, info, payload)
%DATATAG  Type-21 leaf: label + totalSize + '%%%%' + info array + payload.
    body = [uint8('%%%%'), be64(numel(info)), ...
            reshape(cell2mat(arrayfun(@be64, info, 'UniformOutput', false)), 1, []), ...
            payload];
    bytes = [uint8(21), labelBytes(label), be64(numel(body)), body];
end

function bytes = scalarTag(label, typeCode, value)
%SCALARTAG  Leaf holding one numeric value (payload little-endian).
    switch typeCode
        case 5, payload = typecast(uint32(value), 'uint8');
        case 7, payload = typecast(double(value), 'uint8');
        otherwise, error('scalarTag: unsupported type code %d', typeCode);
    end
    bytes = dataTag(label, typeCode, payload);
end

function bytes = stringTag(label, str)
%STRINGTAG  Type-18 string leaf (uint16 chars, little-endian).
    payload = typecast(uint16(char(str)), 'uint8');
    bytes = dataTag(label, [18, numel(char(str))], payload);
end

function bytes = arrayTag(label, elemType, payload)
%ARRAYTAG  Type-20 array leaf; arrayLen derived from payload bytes.
    bytesPer = containers.Map({2,3,4,5,6,7}, {2,4,2,4,4,8});
    n = numel(payload) / bytesPer(elemType);
    bytes = dataTag(label, [20, elemType, n], payload);
end

function bytes = labelBytes(label)
    s = char(label);
    bytes = [be16(numel(s)), uint8(s)];
end

function b = be16(v), b = typecast(swapbytes(uint16(v)), 'uint8'); end
function b = be32(v), b = typecast(swapbytes(uint32(v)), 'uint8'); end
function b = be64(v), b = typecast(swapbytes(uint64(v)), 'uint8'); end
