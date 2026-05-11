function eelsFig = showSpectrum(E, I, existingFig)
%SHOWSPECTRUM  Open or reuse an EELS spectrum figure and plot data.
    arguments
        E           double
        I           double
        existingFig = []
    end

    if isempty(existingFig) || ~isvalid(existingFig)
        eelsFig = uifigure('Name', 'EELS Spectrum', ...
            'Position', [100 100 700 400]);
        eelsAx = uiaxes(eelsFig, 'Position', [60 50 600 320]);
    else
        eelsFig = existingFig;
        eelsFig.Visible = 'on';
        eelsAx = findobj(eelsFig, 'Type', 'axes');
        if isempty(eelsAx)
            eelsAx = uiaxes(eelsFig, 'Position', [60 50 600 320]);
        end
        eelsAx = eelsAx(1);
    end

    cla(eelsAx);
    plot(eelsAx, E, I, 'k-', 'LineWidth', 1);
    xlabel(eelsAx, 'Energy Loss (eV)');
    ylabel(eelsAx, 'Counts');
    title(eelsAx, 'EELS Spectrum');
    grid(eelsAx, 'on');
end
