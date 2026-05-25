function tests = test_fv_analysis_roi
%TEST_FV_ANALYSIS_ROI  Analysis ROI: helper math + headless capture flow.
%
%   Covers fermiViewer.analysis.analysisRegion (rect/circle/full/clamp) and
%   the end-to-end capture flow (arm ROI mode -> two clicks -> ROI stored +
%   overlay drawn + FFT/diffraction scoped) through the real GUI in
%   Visible='off' mode.
    tests = functiontests(localfunctions);
end

% ── analysisRegion unit math ──────────────────────────────────────────────
function testRegionFullImage(t)
    appData.filteredPixels = reshape(1:100, 10, 10);
    appData.analysisROI = [];
    [px, info] = fermiViewer.analysis.analysisRegion(appData);
    verifyEqual(t, size(px), [10 10]);
    verifyFalse(t, info.roi);
    verifyEqual(t, info.type, 'full');
end

function testRegionRect(t)
    appData.filteredPixels = zeros(100, 100);
    appData.analysisROI = struct('type','rect','x1',20,'x2',60,'y1',30,'y2',70);
    [px, info] = fermiViewer.analysis.analysisRegion(appData);
    verifyEqual(t, size(px), [41 41]);
    verifyTrue(t, info.roi);
    verifyEqual(t, info.type, 'rect');
end

function testRegionCircleSoftAperture(t)
    appData.filteredPixels = rand(80, 80);
    appData.analysisROI = struct('type','circle','cx',40,'cy',40,'r',15);
    [px, ~] = fermiViewer.analysis.analysisRegion(appData);
    verifyEqual(t, size(px), [31 31]);   % bbox = 2r+1
    % Corner (outside the circle) equals the in-circle mean, not zero, so the
    % FFT sees a soft aperture rather than a hard zero edge.
    verifyGreaterThan(t, px(1,1), 0);
end

function testRegionClampsOutOfBounds(t)
    appData.filteredPixels = zeros(50, 50);
    appData.analysisROI = struct('type','rect','x1',-10,'x2',999,'y1',-5,'y2',999);
    [px, ~] = fermiViewer.analysis.analysisRegion(appData);
    verifyEqual(t, size(px), [50 50]);   % clamped to image
end

% ── End-to-end capture flow through the GUI ────────────────────────────────
function testRoiCaptureFlowHeadless(t)
    here   = fileparts(mfilename('fullpath'));
    root   = fileparts(fileparts(here));
    srcDir = fullfile(root, '+test_datasets', 'Microscopy');
    dm = dir(fullfile(srcDir, '*.dm3'));
    if isempty(dm)
        assumeFail(t, 'No reference DM3 in +test_datasets/Microscopy');
    end

    api = FermiViewer('Visible', 'off');
    c = onCleanup(@() api.close());
    api.loadImages({fullfile(srcDir, dm(1).name)});

    dims = api.getImageDimensions();   % [H W]
    H = dims(1); W = dims(2);

    % ROI buttons must enable on load — they live in the Diffraction panel but
    % are enabled in the general-tools tier (regression: diffraction-tier
    % enablement silently aborts headless, leaving them dead).
    %
    % Also asserts the diffraction-indexing + Enter EELS buttons enable on a
    % normal load (regression: these were enabled ONLY by setToolsEnabled('on'),
    % which fires only on EDS/EELS mode entry, so they were dead until the user
    % bounced through EDS/EELS — now enabled directly in displayImage).
    mustEnable = {'ROI Rect','ROI Circle','Clear ROI', ...
        'Auto-detect Spots','Match Phases','Clear Spots','Virtual Dark-Field', ...
        'Simulate','Enter EELS'};
    for nm = mustEnable
        b = findall(api.fig, 'Type', 'uibutton', 'Text', nm{1});
        verifyNotEmpty(t, b, sprintf('%s button missing', nm{1}));
        verifyEqual(t, char(b(1).Enable), 'on', sprintf('%s should enable on load', nm{1}));
    end

    % Arm rectangular ROI, then drive two corner clicks through the real flow
    api.onDiffractionAction('setAnalysisROIRect');
    verifyEqual(t, api.getCaptureMode(), 'analysisroi_rect');

    api.simulateClick(round(0.2*W), round(0.2*H));
    api.simulateClick(round(0.7*W), round(0.7*H));

    roi = api.getAnalysisROI();
    verifyTrue(t, ~isempty(roi));
    verifyEqual(t, roi.type, 'rect');
    verifyEmpty(t, api.getCaptureMode());            % capture finished
    verifyNotEmpty(t, findall(api.fig, 'Tag', 'analysisROI'));

    % FFT/diffraction now scope to the ROI sub-image (< full image)
    px = api.getPixels();
    ad = struct('filteredPixels', px.filtered, 'analysisROI', roi);
    [roiPx, roiInfo] = fermiViewer.analysis.analysisRegion(ad);
    verifyTrue(t, roiInfo.roi);
    verifyLessThan(t, numel(roiPx), H*W);

    % Clear ROI reverts to full image + removes the overlay
    api.onDiffractionAction('clearAnalysisROI');
    verifyEmpty(t, api.getAnalysisROI());
    verifyEmpty(t, findall(api.fig, 'Tag', 'analysisROI'));
end
