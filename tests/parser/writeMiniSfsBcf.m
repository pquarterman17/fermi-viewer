function writeMiniSfsBcf(targetPath, xmlBytes, opts)
%WRITEMINISFSBCF  Generate a minimal synthetic Bruker SFS/BCF container.
%   writeMiniSfsBcf(path, xmlBytes) writes a valid single-file SFS
%   container holding xmlBytes as 'EDSDatabase/HeaderData', for testing
%   parser.importBCF's SFS plumbing without real instrument files.
%
%   The layout exercises the parts of the format that real Esprit maps
%   exposed as fragile (2026-06-06):
%     - small ChunkSize (default 512) so even modest payloads need a
%       pointer table spanning MULTIPLE chunks, chained through the
%       first uint32 of each table chunk's 32-byte header;
%     - data chunks written in SHUFFLED file order (deterministic
%       interleave), so any "chunks are sequential" assumption corrupts
%       the payload and fails the caller's content assertions.
%
%   Options:
%       ChunkSize      — SFS chunk size in bytes (default 512; min 64)
%       Shuffle        — interleave data-chunk placement (default true)
%       BreakTableAt   — 1-based table-chunk index whose next-pointer is
%                        corrupted to an out-of-bounds chunk (default 0
%                        = none). Used to test badChunkChain errors.
%
%   SFS layout written (all offsets 0-based; chunk i at 280 + i*ChunkSize):
%       header   : 'AAMVHFSS' magic, ChunkSize @0x128, treeAddress @0x140,
%                  itemCount @0x144
%       chunks   : [32-byte header: uint32 nextChunk + 28 pad][data]
%       tree     : one 512-byte entry — ptrTable int32 @0x00,
%                  fileSize uint64 @0x04, isDir @0xDC, name @0xE0
%
%   See tests/parser/test_importBCF.m for usage.

    arguments
        targetPath (1,1) string
        xmlBytes   (1,:) uint8
        opts.ChunkSize    (1,1) double {mustBeInteger, mustBeGreaterThanOrEqual(opts.ChunkSize, 64)} = 512
        opts.Shuffle      (1,1) logical = true
        opts.BreakTableAt (1,1) double {mustBeInteger, mustBeNonnegative} = 0
    end

    chunkSize = opts.ChunkSize;
    usable    = chunkSize - 32;
    fileSize  = numel(xmlBytes);

    nData = ceil(fileSize / usable);
    nTab  = ceil(nData * 4 / usable);

    % Chunk index assignment (0-based). Chunk 0 is NEVER used for data:
    % its region starts at 0x118 = 280, which overlaps the SFS header
    % fields at 0x128-0x147 (chunkSize/treeAddress/itemCount) — writing
    % into chunk 0 clobbers the header. Real Esprit files leave it to
    % the header too.
    %   data chunks   : 1 .. nData          (placement possibly shuffled)
    %   table chunks  : nData+1 .. nData+nTab
    %   tree chunk    : nData+nTab+1
    firstTab  = nData + 1;
    treeChunk = nData + nTab + 1;

    % pointer table: file-order slice k lives in chunk dataIdx(k)
    if opts.Shuffle && nData > 1
        % Deterministic interleave: file slice k lands on chunk
        % [1 3 5 ... 2 4 6 ...](k) — non-sequential but reproducible.
        dataIdx = [1:2:nData, 2:2:nData];
    else
        dataIdx = 1:nData;
    end

    % ── Assemble whole file in memory ────────────────────────────────
    totalLen = 280 + treeChunk*chunkSize + 32 + 512;
    buf = zeros(1, totalLen, 'uint8');

    % SFS header
    buf(1:8)        = uint8('AAMVHFSS');
    buf(297:300)    = typecast(uint32(chunkSize), 'uint8');   % 0x128
    buf(321:324)    = typecast(uint32(treeChunk), 'uint8');   % 0x140 treeAddress
    buf(325:328)    = typecast(uint32(1), 'uint8');           % 0x144 itemCount

    % Data chunks (header next-pointer unused for data chunks)
    for k = 1:nData
        cIdx  = dataIdx(k);
        cBase = 280 + cIdx*chunkSize;                          % 0-based
        buf(cBase+1 : cBase+4) = typecast(uint32(0xFFFFFFFF), 'uint8');
        lo = (k-1)*usable + 1;
        hi = min(k*usable, fileSize);
        buf(cBase+32+1 : cBase+32+(hi-lo+1)) = xmlBytes(lo:hi);
    end

    % Pointer table (uint32 chunk indices, file order), split over the
    % table chunks and chained through their headers.
    ptrBytes = typecast(uint32(dataIdx), 'uint8');
    for t = 1:nTab
        cIdx  = firstTab + (t-1);
        cBase = 280 + cIdx*chunkSize;
        if t < nTab
            nextIdx = uint32(cIdx + 1);
        else
            nextIdx = uint32(0xFFFFFFFF);                      % end of chain
        end
        if opts.BreakTableAt == t
            nextIdx = uint32(1e6);                              % out-of-bounds
        end
        buf(cBase+1 : cBase+4) = typecast(nextIdx, 'uint8');
        lo = (t-1)*usable + 1;
        hi = min(t*usable, numel(ptrBytes));
        if hi >= lo
            buf(cBase+32+1 : cBase+32+(hi-lo+1)) = ptrBytes(lo:hi);
        end
    end

    % Tree chunk: 32-byte chunk header, then one 512-byte entry read
    % contiguously by the parser (it is the last region in the file).
    tBase = 280 + treeChunk*chunkSize;
    buf(tBase+1 : tBase+4) = typecast(uint32(0xFFFFFFFF), 'uint8');
    eBase = tBase + 32;                                        % entry start, 0-based
    buf(eBase+1 : eBase+4)   = typecast(int32(firstTab), 'uint8');      % ptrTable
    buf(eBase+5 : eBase+12)  = typecast(uint64(fileSize), 'uint8');     % fileSize
    buf(eBase+220+1)         = uint8(0);                                % isDir
    name = uint8('EDSDatabase/HeaderData');
    buf(eBase+224+1 : eBase+224+numel(name)) = name;                    % name (NUL-padded)

    fid = fopen(char(targetPath), 'wb');
    assert(fid ~= -1, 'writeMiniSfsBcf: cannot open "%s" for writing', targetPath);
    fwrite(fid, buf, 'uint8');
    fclose(fid);
end
