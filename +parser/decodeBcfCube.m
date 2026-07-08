function [cube, height, width] = decodeBcfCube(buf, maxChan)
%DECODEBCFCUBE  Decode a Bruker BCF SpectrumData0 hypercube buffer.
%
%   [cube, H, W] = parser.decodeBcfCube(buf, maxChan) unpacks the
%   Delphi/Bruker packed spectral map held in BUF (a uint8 vector — the
%   *decompressed* contents of the SFS internal file "SpectrumData0") into
%   a dense hyperspectral cube of size [H x W x maxChan].
%
%   Inputs
%   ──────
%   buf      (1,:) uint8   Decompressed SpectrumData0 bytes.
%   maxChan  (1,1) double  Number of energy channels to keep per pixel
%                          (typically <ChCount> from the XML header, e.g. 4096).
%
%   Output
%   ──────
%   cube     [H x W x maxChan]  Counts per pixel per channel. Returned as
%                               uint16 when all values fit, otherwise uint32.
%                               Index order is (row y, col x, channel E).
%   height, width              Map dimensions parsed from the 8-byte header.
%
%   Packing formats (per-pixel `flag`)
%   ──────────────────────────────────
%     flag == 0  : raw list of 16-bit channel indices (one entry per pulse)
%     flag == 1  : 12-bit nibble-packed pulse list
%     flag >  1  : "instructive" run-length: (size_p, channels) then a gain
%                  and `channels` delta values; size_p selects the delta width.
%   Channels with zero counts are omitted from the stream, so each pixel is
%   variable length. See docs/theory/spectroscopy.md for the byte layout.
%
%   This is a faithful, full-buffer port of HyperSpy/RosettaSciIO's
%   py_parse_hypermap (downsample=1). Correctness is pinned by a
%   self-consistency oracle: summing the cube over all pixels reproduces the
%   <Channels> sum spectrum embedded in the XML header (see test_importBCF).
%
%   See also IMPORTBCF, IMAGING.EDS.ELEMENTMAP

    arguments
        buf     (1,:) uint8
        maxChan (1,1) double {mustBePositive}
    end

    cube = []; height = 0; width = 0;
    nBuf = numel(buf);
    if nBuf < 8
        return;
    end

    height = double(typecast(buf(1:4), 'int32'));
    width  = double(typecast(buf(5:8), 'int32'));
    if height <= 0 || width <= 0 || height > 1e5 || width > 1e5
        height = max(height, 0); width = max(width, 0);
        return;
    end

    maxChan = round(maxChan);
    vfa = zeros(height * width * maxChan, 1, 'uint32');   % flat, C-order (E fastest)

    offset = 416;          % 0x1A0 — first line header (0-based)
    for lineCnt = 0 : height - 1
        if offset + 4 > nBuf, break; end
        lineHead = double(typecast(buf(offset+1 : offset+4), 'int32'));
        offset = offset + 4;
        if lineHead < 0, lineHead = 0; end

        for px = 1 : lineHead
            if offset + 22 > nBuf, offset = nBuf + 1; break; end
            % ---- 22-byte pixel header: <IHHIHHHI> ----
            %   x_pix u32 @0 | chan1 u16 @4 | chan2 u16 @6 | dummy u32 @8
            %   flag u16 @12 | dummy_size u16 @14 | n_of_pulses u16 @16
            %   data_size2 u32 @18   (0-based byte offsets within the pixel)
            xPix      = double(typecast(buf(offset+1  : offset+4),  'uint32'));
            chan1     = double(typecast(buf(offset+5  : offset+6),  'uint16'));
            chan2     = double(typecast(buf(offset+7  : offset+8),  'uint16'));
            flag      = double(typecast(buf(offset+13 : offset+14), 'uint16'));
            nPulses   = double(typecast(buf(offset+17 : offset+18), 'uint16'));
            dataSize2 = double(typecast(buf(offset+19 : offset+22), 'uint32'));
            offset = offset + 22;
            if chan1 < 1, chan1 = maxChan; end

            if flag == 0
                % ---- raw 16-bit channel indices ----
                if dataSize2 >= 2 && offset + dataSize2 <= nBuf
                    arr16 = typecast(buf(offset+1 : offset+dataSize2), 'uint16');
                    pixel = bincountTo(double(arr16(:)) + 1, chan1);
                else
                    pixel = zeros(chan1, 1);
                end
                offset = offset + dataSize2;

            elseif flag == 1
                % ---- 12-bit nibble-packed pulse list ----
                if nPulses > 0 && offset + dataSize2 <= nBuf
                    d = buf(offset+1 : offset+dataSize2);
                    n2 = floor(numel(d)/2) * 2;
                    pairs   = flipud(reshape(d(1:n2), 2, []));   % byteswap within pairs
                    swbytes = pairs(:).';
                    data2   = repelem(swbytes, 2);
                    i0      = 0 : numel(data2)-1;
                    keep    = ~(mod(i0,6)==0 | mod(i0,6)==5);
                    masked  = data2(keep);
                    need    = 2 * nPulses;
                    if numel(masked) >= need
                        masked = masked(1:need);
                        hi  = uint16(masked(1:2:end));
                        lo  = uint16(masked(2:2:end));
                        e16 = bitshift(hi, 8) + lo;              % big-endian u16
                        e16(1:2:end) = bitshift(e16(1:2:end), -4);
                        e16 = bitand(e16, uint16(4095));         % 12-bit mask
                        pixel = bincountTo(double(e16(:)) + 1, chan1);
                    else
                        pixel = zeros(chan1, 1);
                    end
                else
                    pixel = zeros(chan1, 1);
                end
                offset = offset + dataSize2;

            else
                % ---- instructive run-length (delta + gain) ----
                pixel = zeros(chan1 + 32, 1);
                pp = 0;
                theEnd = offset + dataSize2 - 4;
                while offset < theEnd && offset + 2 <= nBuf
                    sizeP    = double(buf(offset+1));
                    channels = double(buf(offset+2));
                    offset = offset + 2;
                    if sizeP == 0
                        pixel(pp+1 : pp+channels) = 0;
                        pp = pp + channels;
                    elseif ~ismember(sizeP, [1 2 4 8]) || offset + sizeP > nBuf
                        % Corrupt/desynced delta width (or truncated buffer):
                        % undecodable — skip to the pixel boundary instead of
                        % crashing the whole import (ports Python fix 3b036cb;
                        % valid streams only use sizeP in {0,1,2,4,8}).
                        offset = theEnd;
                    else
                        gain = leUint(buf, offset, sizeP, 1);     % sizeP bytes
                        offset = offset + sizeP;
                        if sizeP == 1
                            len = ceil(channels/2);
                            if offset + len > nBuf, offset = theEnd; continue; end
                            a  = double(buf(offset+1 : offset+len));
                            lo = bitand(a, 15) + gain;
                            hiv = bitshift(a, -4) + gain;
                            g  = reshape([lo(:).'; hiv(:).'], 1, []);
                            g  = g(1:channels);
                            pixel(pp+1 : pp+channels) = g;
                        else
                            esz = sizeP / 2;                      % element byte size
                            len = channels * esz;
                            if offset + len > nBuf, offset = theEnd; continue; end
                            temp = leUint(buf, offset, esz, channels);
                            pixel(pp+1 : pp+channels) = temp(:) + gain;
                        end
                        pp = pp + channels;
                        offset = offset + len;
                    end
                end
                if pp < chan1 && chan2 < chan1
                    pixel(pp+1 : chan1) = 0;
                    pp = chan1;
                end
                pixel = pixel(1 : max(pp, 0));
                % ---- additional pulses (sparse increments) ----
                if nPulses > 0 && offset + 4 <= nBuf
                    addS = double(typecast(buf(offset+1 : offset+4), 'uint32'));
                    offset = offset + 4;
                    if offset + addS <= nBuf && addS >= 2
                        addPulses = double(typecast(buf(offset+1 : offset+addS), 'uint16'));
                        ai = addPulses(:) + 1;
                        ai = ai(ai >= 1 & ai <= numel(pixel));
                        if ~isempty(ai)
                            pixel = pixel + bincountTo(ai, numel(pixel));
                        end
                    end
                    offset = offset + addS;
                else
                    offset = offset + 4;
                end
            end

            % ---- scatter into the flat cube ----
            cc = min(chan1, maxChan);
            vlen = min(cc, numel(pixel));
            if vlen > 0
                pixIdx = xPix + width * lineCnt;             % 0-based
                base = maxChan * pixIdx;
                if base >= 0 && base + vlen <= numel(vfa)
                    vfa(base+1 : base+vlen) = uint32(pixel(1:vlen));
                end
            end
        end
        if offset > nBuf, break; end
    end

    % Flat C-order (E,x,y fastest→slowest) → MATLAB (y,x,E).
    cube = permute(reshape(vfa, [maxChan, width, height]), [3 2 1]);
    if max(vfa) <= double(intmax('uint16'))
        cube = uint16(cube);
    end
end


% ════════════════════════════════════════════════════════════════════════
function v = bincountTo(idx1, n)
%BINCOUNTTO  Tally 1-based indices into a length-max(n, max(idx)) column.
    if isempty(idx1)
        v = zeros(n, 1);
        return;
    end
    v = accumarray(idx1, 1, [max(n, max(idx1)) 1]);
end


function out = leUint(buf, offset, elemBytes, count)
%LEUINT  Read COUNT little-endian unsigned integers of ELEMBYTES bytes each.
    nbytes = elemBytes * count;
    slice = buf(offset+1 : offset+nbytes);
    switch elemBytes
        case 1, out = double(slice);
        case 2, out = double(typecast(slice, 'uint16'));
        case 4, out = double(typecast(slice, 'uint32'));
        case 8, out = double(typecast(slice, 'uint64'));
        otherwise, out = double(slice);   % defensive
    end
end
