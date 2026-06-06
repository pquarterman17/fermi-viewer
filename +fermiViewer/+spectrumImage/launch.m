function api = launch(getImages, getActiveIdx, setStatus)
%LAUNCH  Open the EDS Spectrum Image workshop for the active image.
%
%   api = fermiViewer.spectrumImage.launch(getImages, getActiveIdx, setStatus)
%
%   Thin adaptor between FermiViewer and openSpectrumImageWorkshop. It pulls
%   the active image (via the accessor handles the parent already exposes),
%   verifies it carries a decoded EDS hypercube
%   (metadata.parserSpecific.edsData.cube — populated by parser.importBCF when
%   LoadCube is true), and opens the explorer window. If there is no active
%   image or no cube, it reports via setStatus and returns [] (no error
%   dialog), so it is safe to wire directly to a menu item.
%
%   The accessor-handle signature mirrors fermiViewer.calibration.
%   openCalibrationDatabase so it can be added to FermiViewer's `cb` struct as
%   an anonymous callback without consuming a nested-function slot.
%
%   See also FERMIVIEWER.SPECTRUMIMAGE.OPENSPECTRUMIMAGEWORKSHOP, IMPORTBCF

    arguments
        getImages     (1,1) function_handle
        getActiveIdx  (1,1) function_handle
        setStatus     (1,1) function_handle = @(varargin) []
    end

    api = [];
    imgs = getImages();
    idx  = getActiveIdx();
    if isempty(imgs) || idx < 1 || idx > numel(imgs)
        setStatus('Spectrum Image: no active image.');
        return;
    end

    img = imgs{idx};
    eds = getEDS(img);
    if isempty(eds) || ~isfield(eds, 'cube') || isempty(eds.cube)
        setStatus('Spectrum Image: active image has no EDS cube (open a BCF map).');
        return;
    end

    survey = getSurvey(img);
    ctx = struct('setStatus', setStatus);
    api = fermiViewer.spectrumImage.openSpectrumImageWorkshop(eds, survey, ctx);
    setStatus('EDS Spectrum Image opened.');
end


function eds = getEDS(img)
    eds = [];
    if isstruct(img) && isfield(img, 'metadata') ...
            && isfield(img.metadata, 'parserSpecific') ...
            && isfield(img.metadata.parserSpecific, 'edsData')
        eds = img.metadata.parserSpecific.edsData;
    end
end


function survey = getSurvey(img)
    survey = [];
    try
        ps = img.metadata.parserSpecific;
        if isfield(ps, 'imageData') && isfield(ps.imageData, 'pixels')
            survey = ps.imageData.pixels;
        end
    catch
    end
end
