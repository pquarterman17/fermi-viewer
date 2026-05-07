function v = percentile(data, p)
%PERCENTILE  Compute the p-th percentile without Statistics Toolbox.
    arguments
        data    double
        p       double
    end
    x = sort(double(data(:)));
    n = numel(x);
    if n == 0, v = NaN; return; end
    if n == 1, v = x(1); return; end
    h = (p / 100) * (n - 1) + 1;
    lo = max(1, min(n, floor(h)));
    hi = max(1, min(n, ceil(h)));
    if lo == hi
        v = x(lo);
    else
        frac = h - lo;
        v = x(lo) * (1 - frac) + x(hi) * frac;
    end
end
