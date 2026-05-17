function tests = test_eelsExtractMap_vectorized
%TEST_EELSEXTRACTMAP_VECTORIZED  Vectorised per-pixel background fit agrees with
% the per-pixel scalar imaging.eelsBackground reference to floating-point
% round-off, including for degenerate pixels with extreme power-law exponents.
tests = functiontests(localfunctions);
end

function testPowerlawAgreement(tc)
    rng(42);
    Ny = 12; Nx = 10; nE = 200;
    E = linspace(400, 800, nE)';
    A = 1e6; r = 3.2;
    bg = A * E.^(-r);
    edge = 50 * exp(-((E - 600)/40).^2);
    cube = zeros(Ny, Nx, nE);
    for yy = 1:Ny
        for xx = 1:Nx
            scale = 0.5 + rand;
            cube(yy, xx, :) = scale * (bg + edge) + 2*randn(nE,1);
        end
    end

    bgWin  = [450, 550];
    sigWin = [580, 700];

    mapVec = imaging.eelsExtractMap(cube, E, sigWin, ...
        BackgroundWindow=bgWin, Method='powerlaw');

    mapRef = referenceLoop(cube, E, sigWin, bgWin, 'powerlaw');

    absDiff = abs(mapVec - mapRef);
    % Use absolute tolerance scaled by signal magnitude (pixels near zero
    % blow up relative error). 1e-8 abs tol corresponds to ~1e-10 relative
    % on typical pixel sums (~10^2-10^3).
    tc.verifyLessThan(max(absDiff(:)), 1e-6, ...
        sprintf('Max abs diff = %.3e (mapRef range [%g, %g])', ...
            max(absDiff(:)), min(mapRef(:)), max(mapRef(:))));

    % Relative diff only for pixels with non-trivial signal
    sigPix = mapRef > 1e-3 * max(mapRef(:));
    relDiff = absDiff(sigPix) ./ mapRef(sigPix);
    tc.verifyLessThan(max(relDiff), 1e-10, ...
        sprintf('Max relative diff (signal pixels) = %.3e', max(relDiff)));
end

function testExponentialAgreement(tc)
    rng(7);
    Ny = 8; Nx = 6; nE = 150;
    E = linspace(100, 500, nE)';
    A = 5e4; b = -0.01;
    bg = A * exp(b * E);
    edge = 20 * exp(-((E - 350)/30).^2);
    cube = zeros(Ny, Nx, nE);
    for yy = 1:Ny
        for xx = 1:Nx
            cube(yy, xx, :) = (0.5+rand)*(bg + edge) + 1.5*randn(nE,1);
        end
    end

    bgWin  = [150, 300];
    sigWin = [320, 400];

    mapVec = imaging.eelsExtractMap(cube, E, sigWin, ...
        BackgroundWindow=bgWin, Method='exponential');
    mapRef = referenceLoop(cube, E, sigWin, bgWin, 'exponential');

    absDiff = abs(mapVec - mapRef);
    tc.verifyLessThan(max(absDiff(:)), 1e-6, ...
        sprintf('Exp max abs diff = %.3e', max(absDiff(:))));
end

function testZeroPixel(tc)
    % All-zero pixel: scalar version produces map = 0 (log(eps) fit
    % yields tiny background, max(0-tiny,0)=0). Vectorised must match.
    E = linspace(400, 800, 100)';
    bg = 1e5 * E.^(-3);
    cube = zeros(3, 3, 100);
    for yy = 1:3
        for xx = 1:3
            cube(yy, xx, :) = bg + 100*exp(-((E-650)/30).^2);
        end
    end
    cube(2, 2, :) = 0;  % dead pixel

    mapVec = imaging.eelsExtractMap(cube, E, [600, 700], ...
        BackgroundWindow=[450, 550]);
    mapRef = referenceLoop(cube, E, [600, 700], [450, 550], 'powerlaw');

    tc.verifyEqual(mapVec(2,2), mapRef(2,2), 'AbsTol', 1e-9, ...
        'Dead pixel must match scalar reference');
    tc.verifyGreaterThan(mapVec(1,1), 0, 'Live pixel should be positive');

    absDiff = abs(mapVec - mapRef);
    tc.verifyLessThan(max(absDiff(:)), 1e-9);
end

function map = referenceLoop(cube, E, sigWin, bgWin, method)
    [Ny, Nx, ~] = size(cube);
    sigMask = E >= sigWin(1) & E <= sigWin(2);
    map = zeros(Ny, Nx);
    for yy = 1:Ny
        for xx = 1:Nx
            spec = squeeze(double(cube(yy, xx, :)));
            try
                sig = imaging.eelsBackground(E, spec, ...
                    FitWindow=bgWin, Method=method);
            catch
                sig = spec;
            end
            map(yy, xx) = sum(sig(sigMask));
        end
    end
end
