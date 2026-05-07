function result = executeSVD(eelsCube, energyAxis, fig)
%EXECUTESVD  SVD decomposition + optional denoise of EELS spectrum image.
    arguments
        eelsCube    double
        energyAxis  double
        fig                 = []
    end

    [Ny, Nx, nE] = size(eelsCube);
    nPix = Ny * Nx;
    kDefault = min(10, min(nPix, nE));

    res = imaging.eelsSVD(eelsCube, energyAxis, NumComponents=kDefault);

    % Build results figure
    nShow = min(4, kDefault);
    svdFig = figure('Name', 'EELS SVD Decomposition', ...
        'NumberTitle', 'off', 'Color', [0.12 0.12 0.14], ...
        'Position', [100 100 900 700]);

    axScree = subplot(nShow+1, 2, 1, 'Parent', svdFig);
    bar(axScree, res.explained(1:kDefault), 'FaceColor', [0.30 0.55 0.85]);
    xlabel(axScree, 'Component'); ylabel(axScree, 'Variance (%)');
    title(axScree, 'Scree Plot');
    axScree.Color = [0.18 0.18 0.20]; axScree.XColor = 'w'; axScree.YColor = 'w';
    axScree.Title.Color = 'w';

    axCum = subplot(nShow+1, 2, 2, 'Parent', svdFig);
    plot(axCum, 1:kDefault, res.cumulative(1:kDefault), 'o-', ...
        'Color', [0.85 0.35 0.15], 'LineWidth', 1.5, 'MarkerFaceColor', [0.85 0.35 0.15]);
    xlabel(axCum, 'Components'); ylabel(axCum, 'Cumulative (%)');
    title(axCum, 'Cumulative Variance');
    axCum.Color = [0.18 0.18 0.20]; axCum.XColor = 'w'; axCum.YColor = 'w';
    axCum.Title.Color = 'w';
    ylim(axCum, [0 100]);

    cmpColors = lines(nShow);
    for ci = 1:nShow
        axSpec = subplot(nShow+1, 2, 2*ci+1, 'Parent', svdFig);
        plot(axSpec, energyAxis, res.eigenspectra(:,ci), '-', ...
            'Color', cmpColors(ci,:), 'LineWidth', 1.2);
        xlabel(axSpec, 'Energy (eV)'); ylabel(axSpec, 'Weight');
        title(axSpec, sprintf('Eigenspectrum %d  (%.1f%%)', ci, res.explained(ci)));
        axSpec.Color = [0.18 0.18 0.20]; axSpec.XColor = 'w'; axSpec.YColor = 'w';
        axSpec.Title.Color = 'w';

        axMap = subplot(nShow+1, 2, 2*ci+2, 'Parent', svdFig);
        imagesc(axMap, res.scoreMaps(:,:,ci));
        axis(axMap, 'image'); colorbar(axMap);
        title(axMap, sprintf('Score Map %d', ci));
        axMap.Color = [0.18 0.18 0.20]; axMap.XColor = 'w'; axMap.YColor = 'w';
        axMap.Title.Color = 'w';
        colormap(axMap, 'parula');
    end

    % Find the knee: first k where cumulative > 95%
    kneeK = find(res.cumulative >= 95, 1);
    if isempty(kneeK), kneeK = kDefault; end

    % Offer to denoise (needs fig for uiconfirm; skip in headless mode)
    result.svdResult = res;
    result.svdFig = svdFig;
    result.denoised = false;
    result.denoisedCube = [];
    result.sumSpectrum = [];

    if ~isempty(fig) && isvalid(fig)
        sel = uiconfirm(fig, ...
            sprintf(['SVD complete: top %d components explain %.1f%% of variance.\n\n' ...
                     'Denoise the spectrum image using the top %d components?\n' ...
                     '(This replaces the current EELS cube — undo via reload)'], ...
                kDefault, res.cumulative(end), kneeK), ...
            'SVD Denoise', ...
            'Options', {'Denoise', 'Skip'}, ...
            'DefaultOption', 2, 'CancelOption', 2);

        if strcmp(sel, 'Denoise')
            resDenoise = imaging.eelsSVD(eelsCube, energyAxis, ...
                NumComponents=kneeK, Denoise=true);
            result.denoised = true;
            result.denoisedCube = resDenoise.denoisedCube;
            result.sumSpectrum = squeeze(sum(sum(double(resDenoise.denoisedCube), 1), 2));
            result.statusMsg = sprintf('Denoised with %d components (%.1f%% variance)', ...
                kneeK, resDenoise.cumulative(end));
        else
            result.statusMsg = sprintf('SVD: %d components, top explains %.1f%%', ...
                kDefault, res.explained(1));
        end
    else
        result.statusMsg = sprintf('SVD: %d components, top explains %.1f%%', ...
            kDefault, res.explained(1));
    end
end
