function result = executeBackgroundFit(E, I, fitWindow, method)
%EXECUTEBACKGROUNDFIT  Fit and subtract EELS background.
    arguments
        E          double
        I          double
        fitWindow  (1,2) double
        method     char
    end

    [signal, bg, params] = imaging.eelsBackground(E, I, ...
        'FitWindow', fitWindow, 'Method', method);

    result.signal = signal;
    result.bg     = bg;
    result.params = params;
    result.method = method;

    if strcmp(method, 'powerlaw') && isstruct(params) && isfield(params, 'A')
        result.titleStr = sprintf('BG: A=%.2g, r=%.3f', params.A, params.r);
    else
        result.titleStr = '';
    end
    result.statusMsg = sprintf('Background fit: %s', method);
end
