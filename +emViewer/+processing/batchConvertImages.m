function result = batchConvertImages(images, fmt, outDir)
%BATCHCONVERTIMAGES  Convert loaded images to a standard format.
    arguments
        images  cell
        fmt     char
        outDir  char = ''
    end

    nConverted = 0;
    for ki = 1:numel(images)
        try
            ds = images{ki};
            gray = imaging.getGrayscale(ds);
            pL = imaging.percentile(gray(:), 2);
            pH = imaging.percentile(gray(:), 98);
            if pH <= pL, pH = pL + 1; end
            outImg = max(0, min(1, (gray - pL) / (pH - pL)));

            [srcDir, srcName, ~] = fileparts(ds.metadata.source);
            if ~isempty(outDir), srcDir = outDir; end
            if ~isfolder(srcDir), mkdir(srcDir); end
            outPath = fullfile(srcDir, [srcName '.' fmt]);
            imwrite(uint8(outImg * 255), outPath, fmt);
            nConverted = nConverted + 1;
        catch
        end
    end

    result.nConverted = nConverted;
    result.statusMsg = sprintf('Converted %d / %d images to %s.', ...
        nConverted, numel(images), fmt);
end
