function offerSaveToDatabase(fig, imgData)
%OFFERSAVETODATABASE  After a manual calibration, offer to remember it.
%
%   fermiViewer.calibration.offerSaveToDatabase(fig, imgData)
%
%   Called from FermiViewer's applyCalibration once an image has been
%   manually calibrated (scale bar / Set Pixel Size). If the image's
%   metadata names a magnification / camera length and the store does not
%   already hold this exact calibration, the user is asked whether to add
%   it to the calibration database so future imports of the same mode are
%   auto-calibrated.
%
%   Silent no-op when: the image has no usable mag/camera-length key, it
%   is uncalibrated, or a matching entry with the same pixel size already
%   exists (so the user is never re-prompted for a calibration they have
%   already saved). Never throws.
%
% See also FERMIVIEWER.CALIBRATION.CALIBRATIONSTORE,
%          FERMIVIEWER.CALIBRATION.AUTOAPPLYFROMDATABASE

    try
        if ~isstruct(imgData)
            return;
        end
        calibrated = isfield(imgData, 'calibrated') && imgData.calibrated && ...
            isfield(imgData, 'pixelSize') && ...
            fermiViewer.calibration.isValidPixelSize(imgData.pixelSize);
        if ~calibrated
            return;
        end

        key = fermiViewer.calibration.extractCalibrationKey(imgData);
        if ~key.found
            return;   % no mag/camera-length to key on — don't nag
        end

        pixelSize = imgData.pixelSize;
        if isfield(imgData, 'pixelUnit') && ~isempty(imgData.pixelUnit)
            pixelUnit = char(string(imgData.pixelUnit));
        else
            pixelUnit = 'nm';
        end

        % Already stored (same pixel size, ~0.5%)? Then stay quiet.
        existing = fermiViewer.calibration.calibrationStore( ...
            'match', key.instrument, key.keyType, key.keyValue);
        if ~isempty(existing) && ...
                fermiViewer.calibration.isValidPixelSize(existing.pixelSize) && ...
                abs(existing.pixelSize - pixelSize) / pixelSize <= 0.005
            return;
        end

        instLabel = key.instrument;
        if isempty(instLabel), instLabel = 'this instrument'; end
        if strcmpi(key.keyType, 'cameraLength')
            keyLabel = sprintf('camera length %g mm', key.keyValue);
        else
            keyLabel = sprintf('%g\x00D7 magnification', key.keyValue);
        end
        prompt = sprintf(['Remember this calibration for future imports?\n\n' ...
            '%s @ %s\n%.4g %s/px'], instLabel, keyLabel, pixelSize, pixelUnit);

        sel = fermiViewer.chrome.quietConfirm(fig, prompt, ...
            'Save to Calibration Database', ...
            'Options', {'Save', 'Not now'}, ...
            'DefaultOption', 'Not now', ...
            'CancelOption',  'Not now');
        if ~strcmp(sel, 'Save')
            return;
        end

        entry = fermiViewer.calibration.calibrationStore('template');
        entry.instrument = key.instrument;
        entry.mode       = key.mode;
        entry.keyType    = key.keyType;
        entry.keyValue   = key.keyValue;
        entry.pixelSize  = pixelSize;
        entry.pixelUnit  = pixelUnit;
        entry.dateAdded  = datestr(now, 'yyyy-mm-dd'); %#ok<TNOW1,DATST>
        fermiViewer.calibration.calibrationStore('add', entry);
    catch
        % Best-effort: a failed offer must never break calibration.
    end
end
