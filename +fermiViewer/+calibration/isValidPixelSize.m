function tf = isValidPixelSize(sz)
%ISVALIDPIXELSIZE  True for a usable pixel-size value (positive finite scalar).
%
%   tf = fermiViewer.calibration.isValidPixelSize(sz)
%
%   A pixel size that is non-numeric, non-scalar, non-finite, zero, or
%   negative must not be stored with calibrated=true: the scale-bar
%   rebuild then calls imaging.addScaleBar(0,...) whose {mustBePositive}
%   validator throws uncaught on the next redisplay. Callers should reject
%   the value when this returns false.
    tf = isnumeric(sz) && isscalar(sz) && isfinite(sz) && sz > 0;
end
