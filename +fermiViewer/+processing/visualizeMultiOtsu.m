function result = visualizeMultiOtsu(pixels, nClass)
%VISUALIZEMULTIOTSU  Run multi-Otsu and display segmentation figure.
    arguments
        pixels  double
        nClass  (1,1) double
    end

    segResult = imaging.multiOtsu(pixels, NumClasses=nClass);

    classColors = [0 0 0.7; 0 0.7 0; 0.7 0 0; 0.7 0.7 0; 0.7 0 0.7];
    [H, W] = size(segResult.labelMap);
    rgb = zeros(H, W, 3);
    for ci = 1:nClass
        mask = segResult.labelMap == ci;
        for ch = 1:3
            rgb(:,:,ch) = rgb(:,:,ch) + classColors(ci,ch) * double(mask);
        end
    end

    figure('Name', 'Multi-class Segmentation', 'NumberTitle', 'off');
    subplot(1,2,1); imagesc(pixels); colormap(gca, gray(256));
    axis equal tight; title('Original');
    subplot(1,2,2); image(rgb); axis equal tight;
    title(sprintf('%d-class Otsu', nClass));

    result.statusMsg = strjoin(arrayfun(@(i) sprintf('Class %d: %.1f%%', i, ...
        segResult.classFractions(i)*100), 1:nClass, 'UniformOutput', false), ', ');
end
