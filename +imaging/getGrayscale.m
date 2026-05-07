function gray = getGrayscale(dataStruct)
%GETGRAYSCALE  Extract grayscale double from an EM data struct.
    arguments
        dataStruct  struct
    end
    imgInfo = dataStruct.metadata.parserSpecific.imageData;
    px = double(imgInfo.pixels);
    if imgInfo.numChannels == 3
        gray = 0.299*px(:,:,1) + 0.587*px(:,:,2) + 0.114*px(:,:,3);
    else
        gray = px;
    end
end
