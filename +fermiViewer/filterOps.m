function appData = filterOps(action, appData, fig, cb, varargin)
%FILTEROPS  Dispatcher for filter/FFT/undo operations.
%
%   Syntax
%   ------
%   appData = emViewer.filterOps(action, appData, fig, cb)
%   appData = emViewer.filterOps(action, appData, fig, cb, ...)
%
%   Actions
%   -------
%   'gaussian'     - prompt and apply Gaussian blur
%   'median'       - prompt and apply median filter
%   'showFFT'      - display FFT magnitude in new figure
%   'undoFilters'  - undo stack or revert to raw
%   'liveFFTToggle'- toggle live FFT window (pass src as varargin{1})
%   'updateLiveFFT'- update live FFT figure if open
%   'fftMask'      - open interactive FFT mask editor
%   'applyFFTResult'- store result pixels and refresh (pass pixels as varargin{1})
%   'fftMaskAPI'   - headless multi-circle FFT mask (pass masks as varargin{1})
%   'applyFilter'  - programmatic filter (type, params in varargin)
%   'computeFFT'   - return FFT result struct (nargout > 0 returns struct)
%
%   Inputs
%   ------
%   action   - string action name
%   appData  - FermiViewer appData struct
%   fig      - figure handle (for alerts, pointer, btn colors)
%   cb       - struct: undoPush, undoPop, refreshDisplay, setStatus
%              Also: BTN_PRIMARY, BTN_FG (color consts for fftMask)
%   varargin - action-specific arguments
%
%   Examples
%   --------
%   appData = emViewer.filterOps('gaussian', appData, fig, cb);
%   appData = emViewer.filterOps('fftMaskAPI', appData, fig, cb, masks);

    switch action

        % ── Gaussian blur ────────────────────────────────────────────────
        case 'gaussian'
            if isempty(appData.filteredPixels), return; end
            answer = inputdlg({'Sigma (pixels):  [positive number, e.g. 1.5]'}, ...
                'Gaussian Filter', [1 44], {'1.5'});
            if isempty(answer), return; end
            sigma = str2double(answer{1});
            if isnan(sigma) || sigma <= 0
                bosonPlotter.quietAlert(fig, 'Sigma must be a positive number.', 'Invalid Input', 'Icon', 'error');
                return;
            end
            fig.Pointer = 'watch'; drawnow;
            try
                cb.undoPush();
                r = emViewer.processing.executeFilter(appData.filteredPixels, ...
                    'gaussian', struct('sigma', sigma));
                appData.filteredPixels = r.pixels;
                appData = cb.refreshDisplay(appData);
                cb.setStatus(r.statusMsg);
            catch ME
                bosonPlotter.quietAlert(fig, sprintf('Gaussian filter failed:\n%s', ME.message), ...
                    'Filter Error', 'Icon', 'error');
            end
            fig.Pointer = 'arrow';

        % ── Median filter ────────────────────────────────────────────────
        case 'median'
            if isempty(appData.filteredPixels), return; end
            answer = inputdlg({'Window size (3, 5, or 7):'}, 'Median Filter', [1 36], {'3'});
            if isempty(answer), return; end
            wSize = round(str2double(answer{1}));
            if isnan(wSize) || ~ismember(wSize, [3 5 7])
                bosonPlotter.quietAlert(fig, 'Window size must be 3, 5, or 7.', 'Invalid Input', 'Icon', 'error');
                return;
            end
            fig.Pointer = 'watch'; drawnow;
            try
                cb.undoPush();
                r = emViewer.processing.executeFilter(appData.filteredPixels, ...
                    'median', struct('windowSize', wSize));
                appData.filteredPixels = r.pixels;
                appData = cb.refreshDisplay(appData);
                cb.setStatus(r.statusMsg);
            catch ME
                bosonPlotter.quietAlert(fig, sprintf('Median filter failed:\n%s', ME.message), ...
                    'Filter Error', 'Icon', 'error');
            end
            fig.Pointer = 'arrow';

        % ── Show FFT magnitude in new figure ────────────────────────────
        case 'showFFT'
            if isempty(appData.filteredPixels), return; end
            fig.Pointer = 'watch'; drawnow;
            titleStr = 'FFT';
            if appData.activeIdx >= 1
                [~, fname, fext] = fileparts(appData.images{appData.activeIdx}.metadata.source);
                titleStr = sprintf('FFT — %s%s', fname, fext);
            end
            emViewer.processing.showFFT(appData.filteredPixels, titleStr);
            fig.Pointer = 'arrow';
            cb.setStatus('FFT displayed in new figure.');

        % ── Undo filters ─────────────────────────────────────────────────
        case 'undoFilters'
            if isempty(appData.rawPixels), return; end
            if ~isempty(appData.undoStack)
                cb.undoPop();
                return;
            end
            appData.filteredPixels = appData.rawPixels;
            appData = cb.refreshDisplay(appData);
            cb.setStatus('Filters undone — reverted to original image.');

        % ── Toggle live FFT window ───────────────────────────────────────
        case 'liveFFTToggle'
            src = varargin{1};
            if src.Value
                appData.liveFFTFig = figure('Name', 'Live FFT', 'NumberTitle', 'off', ...
                    'Units', 'pixels', 'Position', [250 200 400 400], ...
                    'Tag', 'fermiViewerLiveFFT', ...
                    'DeleteFcn', @(~,~) set(src, 'Value', false));
                appData = emViewer.filterOps('updateLiveFFT', appData, fig, cb);
            else
                if ~isempty(appData.liveFFTFig) && isvalid(appData.liveFFTFig)
                    delete(appData.liveFFTFig);
                end
                appData.liveFFTFig = [];
            end
            appData.procWorkshop.setLiveFFT(src.Value);

        % ── Update live FFT display ──────────────────────────────────────
        case 'updateLiveFFT'
            if isempty(appData.liveFFTFig) || ~isvalid(appData.liveFFTFig), return; end
            if isempty(appData.filteredPixels), return; end
            fftAx = findobj(appData.liveFFTFig, 'Type', 'axes');
            if isempty(fftAx)
                fftAx = axes(appData.liveFFTFig);
            end
            F      = fft2(double(appData.filteredPixels));
            Fshift = fftshift(F);
            mag    = log10(1 + abs(Fshift));
            imagesc(fftAx, mag);
            axis(fftAx, 'image');
            colormap(fftAx, gray(256));
            fftAx.XTick = []; fftAx.YTick = [];
            title(fftAx, 'Live FFT (log magnitude)');

        % ── Open interactive FFT mask editor ─────────────────────────────
        case 'fftMask'
            if isempty(appData.filteredPixels), return; end
            fig.Pointer = 'watch'; drawnow;
            fftHook = struct( ...
                'undoPush',    cb.undoPush, ...
                'applyResult', cb.applyResult, ...
                'setStatus',   cb.setStatus, ...
                'btnPrimary',  cb.BTN_PRIMARY, ...
                'btnFg',       cb.BTN_FG);
            emViewer.processing.openFFTMaskEditor(appData.filteredPixels, fftHook);
            fig.Pointer = 'arrow';

        % ── Apply FFT result pixels ───────────────────────────────────────
        case 'applyFFTResult'
            pixels = varargin{1};
            appData.filteredPixels = pixels;
            appData = cb.refreshDisplay(appData);

        % ── Headless FFT mask API ─────────────────────────────────────────
        case 'fftMaskAPI'
            masks = varargin{1};
            if isempty(appData.filteredPixels), return; end
            if isempty(masks) || size(masks, 2) ~= 3
                cb.setStatus('fftMask: masks must be N-by-3 [cx cy r].');
                return;
            end
            cb.undoPush();
            pixels  = double(appData.filteredPixels);
            F       = fft2(pixels);
            Fshift  = fftshift(F);
            [H2, W2] = size(Fshift);
            mask    = ones(H2, W2);
            [XX, YY] = meshgrid(1:W2, 1:H2);
            for mi = 1:size(masks, 1)
                cx = masks(mi, 1);
                cy = masks(mi, 2);
                r  = masks(mi, 3);
                if r <= 0, continue; end
                d2  = (XX - cx).^2 + (YY - cy).^2;
                mask(d2 <= r^2) = 0;
                mcx = W2 + 1 - cx;
                mcy = H2 + 1 - cy;
                d2m = (XX - mcx).^2 + (YY - mcy).^2;
                mask(d2m <= r^2) = 0;
            end
            Fmasked = Fshift .* mask;
            recovered = real(ifft2(ifftshift(Fmasked)));
            appData.filteredPixels = recovered;
            appData = cb.refreshDisplay(appData);
            cb.setStatus(sprintf('FFT mask applied (%d region(s))', size(masks, 1)));

        % ── Programmatic filter application ──────────────────────────────
        case 'applyFilter'
            type   = varargin{1};
            params = varargin{2};
            if isempty(appData.filteredPixels)
                warning('FermiViewer:noImage', 'No image loaded.');
                return;
            end
            switch lower(type)
                case 'gaussian'
                    sigma = 1.0;
                    if isstruct(params) && isfield(params, 'Sigma'), sigma = params.Sigma; end
                    p = struct('sigma', sigma);
                case 'median'
                    wSize = 3;
                    if isstruct(params) && isfield(params, 'WindowSize'), wSize = params.WindowSize; end
                    p = struct('windowSize', wSize);
                otherwise
                    warning('FermiViewer:unknownFilter', 'Unknown filter type "%s".', type);
                    return;
            end
            r = emViewer.processing.executeFilter(appData.filteredPixels, type, p);
            appData.filteredPixels = r.pixels;
            appData = cb.refreshDisplay(appData);

        % ── Programmatic FFT computation (no figure) ─────────────────────
        case 'computeFFT'
            result = struct('magnitude', [], 'phase', []);
            if isempty(appData.filteredPixels)
                warning('FermiViewer:noImage', 'No image loaded.');
                appData = result;  % caller reads this if nargout > 0 in wrapper
                return;
            end
            [mag, ph] = imaging.computeFFT(appData.filteredPixels);
            result.magnitude = mag;
            result.phase     = ph;
            appData = result;  % caller wrapper returns this

        otherwise
            warning('emViewer:filterOps:unknownAction', ...
                'Unknown action "%s" — ignored.', action);
    end
end
