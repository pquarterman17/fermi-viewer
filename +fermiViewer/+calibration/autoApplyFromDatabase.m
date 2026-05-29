function [data, msg] = autoApplyFromDatabase(data)
%AUTOAPPLYFROMDATABASE  Calibrate a freshly-imported image from the store.
%
%   [data, msg] = fermiViewer.calibration.autoApplyFromDatabase(data)
%
%   If `data` is a 2-D image that is currently UNCALIBRATED and whose
%   metadata names a magnification / camera length matching a stored
%   calibration entry, the matched pixel size/unit are written into
%   data.metadata.parserSpecific.imageData and a human-readable `msg`
%   describing the auto-calibration is returned. Otherwise `data` is
%   returned unchanged and `msg` is '' (empty).
%
%   Embedded calibration is authoritative: an image the parser already
%   calibrated is left untouched. Only uncalibrated images consult the
%   database.
%
%   This is the import-time hook for the calibration database (called
%   from FermiViewer's appendImage). It never throws — any failure
%   leaves `data` unchanged.
%
% See also FERMIVIEWER.CALIBRATION.CALIBRATIONSTORE,
%          FERMIVIEWER.CALIBRATION.EXTRACTCALIBRATIONKEY

    msg = '';
    try
        if ~isstruct(data) || ~hasImageData(data)
            return;
        end
        imgData = data.metadata.parserSpecific.imageData;

        % Respect embedded calibration — only fill in uncalibrated images.
        alreadyCal = isfield(imgData, 'calibrated') && imgData.calibrated && ...
            isfield(imgData, 'pixelSize') && ...
            fermiViewer.calibration.isValidPixelSize(imgData.pixelSize);
        if alreadyCal
            return;
        end

        key = fermiViewer.calibration.extractCalibrationKey(imgData);
        if ~key.found
            return;
        end

        match = fermiViewer.calibration.calibrationStore( ...
            'match', key.instrument, key.keyType, key.keyValue);
        if isempty(match) || ~fermiViewer.calibration.isValidPixelSize(match.pixelSize)
            return;
        end

        data.metadata.parserSpecific.imageData.pixelSize  = match.pixelSize;
        data.metadata.parserSpecific.imageData.pixelUnit  = match.pixelUnit;
        data.metadata.parserSpecific.imageData.calibrated = true;

        instLabel = match.instrument;
        if isempty(instLabel), instLabel = 'database'; end
        if strcmpi(key.keyType, 'cameraLength')
            keyLabel = sprintf('camera length %g mm', key.keyValue);
        else
            keyLabel = sprintf('mag %g\x00D7', key.keyValue);
        end
        msg = sprintf('Auto-calibrated from %s: %.4g %s/px (%s)', ...
            instLabel, match.pixelSize, match.pixelUnit, keyLabel);
    catch
        msg = '';   % never let calibration lookup break an import
    end
end

% ════════════════════════════════════════════════════════════════════════
function tf = hasImageData(data)
    tf = isfield(data, 'metadata') && isstruct(data.metadata) && ...
        isfield(data.metadata, 'parserSpecific') && ...
        isstruct(data.metadata.parserSpecific) && ...
        isfield(data.metadata.parserSpecific, 'imageData') && ...
        isstruct(data.metadata.parserSpecific.imageData);
    if tf
        ps = data.metadata.parserSpecific;
        % Only true 2-D images carry a meaningful pixel size.
        if isfield(ps, 'isImage') && ~ps.isImage
            tf = false;
        end
    end
end
