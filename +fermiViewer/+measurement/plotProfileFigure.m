function plotProfileFigure(dist, intensity, unit, titleStr, opts)
%PLOTPROFILEFIGURE  Open or reuse the Line Profile figure and plot data.
    arguments
        dist      double
        intensity double
        unit      char         = 'px'
        titleStr  char         = 'Line Profile'
        opts.YLabel char       = 'Intensity'
        opts.Color  (1,3) double = [0 0.4 0.8]
    end

    pfig = findobj(0, 'Type', 'figure', 'Name', 'Line Profile');
    if isempty(pfig)
        pfig = figure('Name', 'Line Profile', 'NumberTitle', 'off', ...
            'Units', 'pixels', 'Position', [200 200 560 300]);
    else
        figure(pfig(1));
        pfig = pfig(1);
    end
    pax = findobj(pfig, 'Type', 'axes');
    if isempty(pax)
        pax = axes(pfig);
    else
        cla(pax(1));
        pax = pax(1);
    end
    plot(pax, dist, intensity, 'Color', opts.Color, 'LineWidth', 1.2);
    grid(pax, 'on');
    xlabel(pax, sprintf('Distance (%s)', unit));
    ylabel(pax, opts.YLabel);
    title(pax, titleStr, 'Interpreter', 'none');
    box(pax, 'on');
end
