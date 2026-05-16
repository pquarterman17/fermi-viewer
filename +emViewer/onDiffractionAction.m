function appData = onDiffractionAction(action, appData, ui, callbacks)
%ONDIFFRACTIONACTION  Dispatcher for FermiViewer diffraction-analysis actions.
%
% Syntax:
%   appData = emViewer.onDiffractionAction(action, appData, ui, callbacks)
%
% Inputs:
%   action    — char, one of: 'rings', 'dspacing', 'latticeMeasure',
%               'latticeExecute', 'autoDetect', 'clickSpot', 'clearSpots',
%               'drawSpots', 'match', 'overlayRings', 'simulate'
%   appData   — struct, FermiViewer application state (modified in place)
%   ui        — struct of UI handles with fields:
%                 .fig           — uifigure
%                 .ax            — main image uiaxes
%                 .lblSpotCount  — uilabel for spot count display
%                 .lblZoneAxis   — uilabel for zone axis display
%                 .lbxDiffResults— uilistbox for match candidates
%                 .edtCameraLen  — uieditfield for camera length (mm)
%                 .ddAccVoltage  — uidropdown for accelerating voltage
%                 .edtZoneAxis   — uieditfield for zone axis string
%   callbacks — struct of function handles with fields:
%                 .setStatus           — @(msg) update status bar
%                 .guiPixelSize        — @() return pixel size in calibrated units
%                 .guiPixelUnit        — @() return pixel unit string
%                 .startTwoClickCapture— @(mode) arm two-click capture mode
%                 .onCaptureClick      — @(src,evt) WindowButtonDownFcn for spots
%
% Outputs:
%   appData   — modified struct; callers must assign the return value back
%
% Examples:
%   appData = emViewer.onDiffractionAction('clearSpots', appData, ui, cb);
%   appData = emViewer.onDiffractionAction('match', appData, ui, cb);

% ════════════════════════════════════════════════════════════════════════
% Unpack callbacks for readability
setStatus            = callbacks.setStatus;
guiPixelSize         = callbacks.guiPixelSize;
guiPixelUnit         = callbacks.guiPixelUnit;
startTwoClickCapture = callbacks.startTwoClickCapture;

% Unpack UI handles
fig            = ui.fig;
ax             = ui.ax;
lblSpotCount   = ui.lblSpotCount;
lblZoneAxis    = ui.lblZoneAxis;
lbxDiffResults = ui.lbxDiffResults;
edtCameraLen   = ui.edtCameraLen;
ddAccVoltage   = ui.ddAccVoltage;
edtZoneAxis    = ui.edtZoneAxis;

% ════════════════════════════════════════════════════════════════════════
switch action
    case 'rings'
        if isempty(appData.displayImg), return; end
        answer = inputdlg( ...
            {'d-spacings (Angstrom, comma-separated):', ...
             'Camera length (mm):', ...
             'Wavelength (Angstrom, e.g. 0.0251 for 200kV e-):'}, ...
            'Diffraction Ring Overlay', [1 50], ...
            {'2.338, 2.024, 1.431, 1.221', '500', '0.0251'});
        if isempty(answer), return; end
        dSpacings = str2double(strsplit(answer{1}, ','));
        camLength = str2double(answer{2});
        wavelength = str2double(answer{3});
        if any(isnan(dSpacings)) || isnan(camLength) || isnan(wavelength)
            uialert(fig, 'Invalid parameters.', 'Error', 'Icon', 'error');
            return;
        end
        [H, W] = size(appData.filteredPixels);
        pixSize = 1;
        if appData.activeIdx >= 1
            imgInfo = appData.images{appData.activeIdx}.metadata.parserSpecific.imageData;
            if imgInfo.calibrated && ~isnan(imgInfo.pixelSize)
                pixSize = imgInfo.pixelSize;
            end
        end
        nDrawn = emViewer.diffraction.drawRingOverlay( ...
            ax, dSpacings, camLength, wavelength, [H W], pixSize);
        setStatus(sprintf('%d diffraction rings overlaid', nDrawn));

    case 'dspacing'
        if appData.activeIdx < 1 || isempty(appData.displayImg), return; end
        if appData.compareMode, return; end
        startTwoClickCapture('dspacing');

    case 'latticeMeasure'
        if isempty(appData.rawPixels), return; end
        px = guiPixelSize();
        if px <= 0
            uialert(fig, 'Set pixel calibration first (pixel size > 0).', 'No calibration');
            return;
        end
        appData.captureMode   = 'lattice';
        appData.captureClicks = [];
        setStatus('Lattice: click two FFT spots (non-collinear). Esc to cancel.');

    case 'latticeExecute'
        pts = appData.captureClicks;
        if size(pts, 1) < 2, return; end
        try
            [H, W] = size(appData.filteredPixels);
            px = guiPixelSize();
            pu = guiPixelUnit();
            result = imaging.latticeMeasure( ...
                [pts(1,2), pts(1,1)], [pts(2,2), pts(2,1)], [H, W], ...
                PixelSize=px, PixelUnit=pu);
            msg = sprintf(['Lattice Parameters\n\n' ...
                'a = %.3f %s\nb = %.3f %s\n' char(947) ' = %.1f' char(176) '\n' ...
                'd1 = %.3f %s\nd2 = %.3f %s\nUnit cell area = %.2f %s' char(178)], ...
                result.a, pu, result.b, pu, result.gamma, ...
                result.dSpacing1, pu, result.dSpacing2, pu, result.unitCellArea, pu);
            uialert(fig, msg, 'Lattice Measurement', 'Icon', 'info');
            setStatus(sprintf('Lattice: a=%.3f, b=%.3f %s, %s=%.1f%s', ...
                result.a, result.b, pu, char(947), result.gamma, char(176)));
        catch ME
            setStatus(['Lattice error: ' ME.message]);
        end

    case 'autoDetect'
        if isempty(appData.images), return; end
        idx = appData.activeIdx;
        if idx < 1, return; end
        pixels = double(appData.images{idx}.metadata.parserSpecific.imageData.pixels);
        try
            spots = imaging.findDiffractionSpots(pixels);
        catch ME
            setStatus(['Spot detection error: ' ME.message]);
            return;
        end
        appData.diffSpots = spots;
        appData.diffWorkshop.model.spots = spots;
        appData = emViewer.onDiffractionAction('drawSpots', appData, ui, callbacks);
        lblSpotCount.Text = sprintf('%d spots', size(spots, 1));
        setStatus(sprintf('Found %d diffraction spots', size(spots, 1)));

    case 'clickSpot'
        if isempty(appData.images), return; end
        appData.captureMode   = 'diffspot';
        appData.captureClicks = [];
        fig.WindowButtonDownFcn = callbacks.onCaptureClick;
        fig.Pointer = 'crosshair';
        setStatus('Click to mark diffraction spots; press Escape when done');

    case 'clearSpots'
        appData.diffSpots   = [];
        appData.diffResults = [];
        appData.diffWorkshop.clearSpots();
        delete(findall(ax, 'Tag', 'diff_spot'));
        delete(findall(ax, 'Tag', 'diff_ring'));
        lblSpotCount.Text    = '0 spots';
        lblZoneAxis.Text     = '';
        lbxDiffResults.Items = {};
        setStatus('Spots cleared');

    case 'drawSpots'
        delete(findall(ax, 'Tag', 'diff_spot'));
        if isempty(appData.diffSpots), return; end
        hold(ax, 'on');
        plot(ax, appData.diffSpots(:,2), appData.diffSpots(:,1), ...
            'ro', 'MarkerSize', 10, 'LineWidth', 1.5, 'Tag', 'diff_spot', ...
            'HandleVisibility', 'off');
        hold(ax, 'off');

    case 'match'
        if isempty(appData.diffSpots) || size(appData.diffSpots, 1) < 2
            setStatus('Need at least 2 spots to index');
            return;
        end
        idx = appData.activeIdx;
        if idx < 1, return; end
        imgData = appData.images{idx}.metadata.parserSpecific.imageData;
        imgSz   = [size(imgData.pixels, 1), size(imgData.pixels, 2)];
        camLen  = str2double(edtCameraLen.Value);
        if isnan(camLen), camLen = NaN; end
        kVstr = ddAccVoltage.Value;
        kV    = str2double(regexp(kVstr, '\d+', 'match', 'once'));
        pxSz  = 1; pxUnit = 'px';
        if imgData.calibrated
            pxSz   = imgData.pixelSize;
            pxUnit = imgData.pixelUnit;
        end
        try
            result = imaging.indexDiffraction(appData.diffSpots, imgSz, ...
                'PixelSize', pxSz, 'PixelUnit', pxUnit, ...
                'CameraLength', camLen, 'AccVoltage', kV);
        catch ME
            setStatus(['Indexing error: ' ME.message]);
            return;
        end
        appData.diffResults = result;
        appData.diffWorkshop.model.setResults(result);
        fmt = emViewer.diffraction.formatMatchResults(result);
        lbxDiffResults.Items = fmt.items;
        if ~isempty(fmt.items), lbxDiffResults.Value = fmt.items{1}; end
        lblZoneAxis.Text = fmt.zoneAxisStr;
        setStatus(fmt.statusMsg);

    case 'overlayRings'
        if isempty(appData.diffResults), return; end
        delete(findall(ax, 'Tag', 'diff_ring'));
        selVal = lbxDiffResults.Value;
        if isempty(selVal), return; end
        selIdx = find(strcmp(lbxDiffResults.Items, selVal), 1);
        if isempty(selIdx), selIdx = 1; end
        if selIdx > numel(appData.diffResults.candidates), return; end
        emViewer.diffraction.drawMatchedRings(ax, ...
            appData.diffResults.candidates(selIdx), ...
            appData.diffResults.center, appData.diffResults.measuredR);

    case 'simulate'
        if isempty(appData.diffResults) || isempty(appData.diffResults.candidates)
            setStatus('Match phases first');
            return;
        end
        phaseName = appData.diffResults.candidates(1).phaseName;
        zaStr = edtZoneAxis.Value;
        za = sscanf(zaStr, '%d %d %d', [1 3]);
        if numel(za) ~= 3, setStatus('Invalid zone axis'); return; end
        kVstr  = ddAccVoltage.Value;
        kV     = str2double(regexprep(kVstr, '[^0-9]', ''));
        camLen = str2double(edtCameraLen.Value);
        if isnan(camLen), camLen = 200; end
        try
            res = imaging.simulateDiffraction(phaseName, 'ZoneAxis', za, ...
                'AccVoltage', kV, 'CameraLength', camLen);
            simFig = figure('Name', sprintf('Simulated: %s [%d%d%d]', phaseName, za)); %#ok<NASGU>
            imagesc(log10(res.image + 1)); colormap gray; axis image;
            title(sprintf('%s — [%d%d%d] zone axis', phaseName, za));
            setStatus(sprintf('Simulated %s [%d%d%d]: %d spots', phaseName, za, numel(res.spots)));
        catch ME
            setStatus(sprintf('Simulation failed: %s', ME.message));
        end
end
end
