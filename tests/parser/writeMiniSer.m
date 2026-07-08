function info = writeMiniSer(path, opts)
%WRITEMINISER  Write a minimal-but-valid synthetic TIA SER file for tests.
%
%   info = writeMiniSer(path, ScanDims=[ny nx], NChannels=n, ...)
%
%   Ports the Python fermiviewer tests/fixtures/ser.py generator so the
%   MATLAB and Python SER parsers are pinned by the same synthetic files.
%
%   Kind="spectrum" (default) writes 0x4120 elements:
%     ScanDims=[]      → single spectrum
%     ScanDims=n       → line profile (n elements)
%     ScanDims=[ny nx] → 2-D spectrum image (ny*nx elements)
%   Channel c (0-based) of element k (0-based) holds value k*100 + c, so
%   per-element and total sums are analytically known.
%
%   Kind="image" writes 0x4122 elements (NElem frames of Width x Height
%   uint16, values 1..N) — for the multi-frame-warning test.
%
%   Energy calibration: value_i = CalOffset + (i - CalElement)*CalDelta.
%
%   Returns info struct with .nElem, .nChannels, .energyAxis (spectrum
%   kind) or .width/.height/.nElem (image kind).

    arguments
        path (1,1) string
        opts.Kind       (1,1) string {mustBeMember(opts.Kind, ["spectrum","image"])} = "spectrum"
        opts.ScanDims   double  = []
        opts.NChannels  (1,1) double = 8
        opts.CalOffset  (1,1) double = -20.0
        opts.CalDelta   (1,1) double = 0.2
        opts.CalElement (1,1) double = 0
        opts.Version    (1,1) double = hex2dec('0210')
        opts.Width      (1,1) double = 4
        opts.Height     (1,1) double = 3
        opts.NElem      (1,1) double = 1
    end

    fid = fopen(char(path), 'w', 'ieee-le');
    assert(fid ~= -1, 'writeMiniSer: cannot open %s', path);
    cleaner = onCleanup(@() fclose(fid));

    wide  = opts.Version >= hex2dec('0220');
    if wide, ofmt = 'uint64'; osz = 8; else, ofmt = 'uint32'; osz = 4; end

    if opts.Kind == "spectrum"
        scanDims = opts.ScanDims(:).';
        nElem = max(1, prod(scanDims));
        nCh   = opts.NChannels;
        ndim  = numel(scanDims);

        % dimension array bytes: size i32, calOff f64, calDelta f64,
        % calElement i32, descLen i32 (0), unitLen i32 (0) → 32 bytes each
        dimBytes  = 32 * ndim;
        headerLen = 26 + osz + dimBytes;
        offArr    = headerLen;
        % element payload: cal (8+8+4) + dtype i16 + len i32 + nCh*u4
        elemLen   = 20 + 2 + 4 + nCh * 4;
        dataStart = offArr + nElem * osz * 2;   % data offsets + tag offsets

        writeFixedHeader(fid, opts.Version, hex2dec('4120'), nElem, offArr, ndim, ofmt);
        for d = 1:ndim
            fwrite(fid, scanDims(d), 'int32');
            fwrite(fid, [0.0 1.0], 'float64');   % dim cal offset, delta
            fwrite(fid, 0, 'int32');             % dim cal element
            fwrite(fid, 0, 'uint32');            % description length
            fwrite(fid, 0, 'uint32');            % units length
        end
        offsets = dataStart + (0:nElem-1) * elemLen;
        fwrite(fid, offsets, ofmt);
        fwrite(fid, zeros(1, nElem), ofmt);      % tag offsets (unused)
        for k = 0:nElem-1
            fwrite(fid, opts.CalOffset,  'float64');
            fwrite(fid, opts.CalDelta,   'float64');
            fwrite(fid, opts.CalElement, 'int32');
            fwrite(fid, 3, 'int16');             % DataType 3 = uint32
            fwrite(fid, nCh, 'int32');
            fwrite(fid, k*100 + (0:nCh-1), 'uint32');
        end

        info.nElem      = nElem;
        info.nChannels  = nCh;
        info.scanDims   = scanDims;
        info.energyAxis = opts.CalOffset + ((0:nCh-1)' - opts.CalElement) * opts.CalDelta;
    else
        w = opts.Width;  h = opts.Height;  nElem = opts.NElem;
        headerLen = 26 + osz;                    % no dimension array
        offArr    = headerLen;
        elemLen   = (8+8+4)*2 + 2 + 8 + w*h*2;   % X cal + Y cal + dtype + WxH + u2 data
        dataStart = offArr + nElem * osz * 2;

        writeFixedHeader(fid, opts.Version, hex2dec('4122'), nElem, offArr, 0, ofmt);
        offsets = dataStart + (0:nElem-1) * elemLen;
        fwrite(fid, offsets, ofmt);
        fwrite(fid, zeros(1, nElem), ofmt);
        for k = 1:nElem
            fwrite(fid, [0.0 1e-9], 'float64');  % X cal offset, delta
            fwrite(fid, 0, 'int32');
            fwrite(fid, [0.0 1.0],  'float64');  % Y cal offset, delta
            fwrite(fid, 0, 'int32');
            fwrite(fid, 2, 'int16');             % DataType 2 = uint16
            fwrite(fid, [w h], 'int32');
            fwrite(fid, 1:(w*h), 'uint16');
        end

        info.width  = w;
        info.height = h;
        info.nElem  = nElem;
    end
end


function writeFixedHeader(fid, version, dataTypeID, nElem, offArr, ndim, ofmt)
    fwrite(fid, hex2dec('4949'), 'uint16');   % ByteOrder
    fwrite(fid, hex2dec('0197'), 'uint16');   % SeriesID
    fwrite(fid, version, 'uint16');           % Version
    fwrite(fid, dataTypeID, 'uint32');        % DataTypeID
    fwrite(fid, 0, 'uint32');                 % TagTypeID
    fwrite(fid, nElem, 'uint32');             % TotalElements
    fwrite(fid, nElem, 'uint32');             % ValidElements
    fwrite(fid, offArr, ofmt);                % OffsetArrayOffset
    fwrite(fid, ndim, 'uint32');              % NumberDimensions
end
