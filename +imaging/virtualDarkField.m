function vdf = virtualDarkField(img, opts)
%VIRTUALDARKFIELD  Compute a virtual dark-field image from an FFT spot selection.
%
%   Syntax:
%       vdf = imaging.virtualDarkField(img, MaskCenter=[r, c])
%       vdf = imaging.virtualDarkField(img, MaskCenter=[r, c], MaskRadius=15, ...
%                 MaskShape='annulus', InnerRadius=5)
%
%   Applies a real-space mask in the FFT (frequency) domain by selecting a
%   circular or annular aperture centred on a diffraction spot, then
%   reconstructing the real-space image via the inverse FFT.  The output
%   highlights regions of the original image that give rise to the selected
%   diffraction frequency.
%
%   Coordinates are in the fftshift convention: the DC component sits at
%   floor(size/2)+1, matching imaging.computeFFT and imaging.indexDiffraction.
%
%   Inputs:
%       img — [H x W] numeric matrix (grayscale image, any numeric type)
%
%   Required Name-Value:
%       MaskCenter — [1 x 2] double [row, col] centre of aperture mask
%                    in FFT (fftshift) coordinates
%
%   Optional Name-Value:
%       MaskRadius  — outer aperture radius in pixels (default 10)
%       MaskShape   — 'circle' or 'annulus' (default 'circle')
%       InnerRadius — inner radius for 'annulus' mask, in pixels (default 0)
%
%   Output:
%       vdf — [H x W] double, virtual dark-field image (magnitude of
%             inverse FFT after masking; values >= 0)
%
%   Examples:
%       % Bright-field / single-spot VDF from a known diffraction spot
%       [mag, ~] = imaging.computeFFT(img);
%       spots = imaging.findDiffractionSpots(mag, MinRadius=20);
%       vdf = imaging.virtualDarkField(img, MaskCenter=spots(1,:), MaskRadius=12);
%       imagesc(vdf); colormap hot; axis equal tight; colorbar;
%       title('Virtual dark-field (spot 1)');
%
%       % Annular mask to exclude the direct beam
%       [H, W] = size(img);
%       centre = [floor(H/2)+1, floor(W/2)+1];
%       vdf = imaging.virtualDarkField(img, MaskCenter=centre, ...
%                 MaskShape='annulus', InnerRadius=20, MaskRadius=60);
%
%   See also imaging.computeFFT, imaging.indexDiffraction,
%            imaging.simulateDiffraction

% ════════════════════════════════════════════════════════════════════════
%  Arguments
% ════════════════════════════════════════════════════════════════════════
arguments
    img                  (:,:) {mustBeNumeric}
    opts.MaskCenter      (1,2) double
    opts.MaskRadius      (1,1) double {mustBePositive} = 10
    opts.MaskShape       (1,1) string = 'circle'
    opts.InnerRadius     (1,1) double {mustBeNonnegative} = 0
end

opts.MaskShape = validatestring(opts.MaskShape, {'circle', 'annulus'}, ...
    'virtualDarkField', 'MaskShape');

% ════════════════════════════════════════════════════════════════════════
%  Forward FFT with DC at centre
% ════════════════════════════════════════════════════════════════════════
F = fft2(double(img));
F = fftshift(F);

% ════════════════════════════════════════════════════════════════════════
%  Build aperture mask
% ════════════════════════════════════════════════════════════════════════
[H, W] = size(F);

[CC, RR] = meshgrid(1:W, 1:H);

dist = sqrt((RR - opts.MaskCenter(1)).^2 + (CC - opts.MaskCenter(2)).^2);

switch opts.MaskShape
    case 'circle'
        mask = dist <= opts.MaskRadius;
    case 'annulus'
        mask = dist >= opts.InnerRadius & dist <= opts.MaskRadius;
end

% ════════════════════════════════════════════════════════════════════════
%  Apply mask and inverse FFT
% ════════════════════════════════════════════════════════════════════════
F_masked = F .* double(mask);

vdf = abs(ifft2(ifftshift(F_masked)));

end
