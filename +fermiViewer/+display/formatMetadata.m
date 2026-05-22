function lines = formatMetadata(dataStruct)
%FORMATMETADATA  Build cell array of metadata strings for display.
%   lines = formatMetadata(dataStruct)
%   dataStruct: unified parser output with .metadata.parserSpecific.imageData
    arguments
        dataStruct struct
    end

    imgInfo = dataStruct.metadata.parserSpecific.imageData;
    lines   = {};

    [~, fname, fext] = fileparts(dataStruct.metadata.source);
    lines{end+1} = sprintf('File:   %s%s', fname, fext);
    lines{end+1} = sprintf('Parser: %s', dataStruct.metadata.parserName);
    lines{end+1} = '';

    lines{end+1} = sprintf('Width:  %d px', imgInfo.width);
    lines{end+1} = sprintf('Height: %d px', imgInfo.height);
    lines{end+1} = sprintf('Depth:  %d-bit', imgInfo.bitDepth);
    lines{end+1} = sprintf('Chans:  %d', imgInfo.numChannels);
    lines{end+1} = sprintf('Frames: %d', imgInfo.numFrames);
    lines{end+1} = '';

    if imgInfo.calibrated && ~isnan(imgInfo.pixelSize)
        lines{end+1} = sprintf('Pixel:  %.4g %s', imgInfo.pixelSize, imgInfo.pixelUnit);
    else
        lines{end+1} = 'Pixel:  uncalibrated';
    end
    lines{end+1} = '';

    if isstruct(imgInfo.acquiParams) && ~isempty(fieldnames(imgInfo.acquiParams))
        lines{end+1} = '── Acquisition ──';

        if isfield(imgInfo.acquiParams, 'feiMetadata')
            fei = imgInfo.acquiParams.feiMetadata;
            sections = fieldnames(fei);
            for si = 1:numel(sections)
                sec = sections{si};
                secData = fei.(sec);
                if ~isstruct(secData), continue; end
                lines{end+1} = sprintf('[%s]', sec); %#ok<AGROW>
                keys = fieldnames(secData);
                for ki = 1:numel(keys)
                    k = keys{ki};
                    v = secData.(k);
                    if ischar(v) || isstring(v)
                        lines{end+1} = sprintf('  %s: %s', k, v); %#ok<AGROW>
                    elseif isnumeric(v)
                        lines{end+1} = sprintf('  %s: %g', k, v); %#ok<AGROW>
                    end
                end
            end
        else
            keys = fieldnames(imgInfo.acquiParams);
            for ki = 1:numel(keys)
                k = keys{ki};
                v = imgInfo.acquiParams.(k);
                if ischar(v) || isstring(v)
                    lines{end+1} = sprintf('  %s: %s', k, v); %#ok<AGROW>
                elseif isnumeric(v) && isscalar(v)
                    lines{end+1} = sprintf('  %s: %g', k, v); %#ok<AGROW>
                end
            end
        end
    end
end
