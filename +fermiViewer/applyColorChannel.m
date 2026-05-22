function rgb = applyColorChannel(gray, colorName)
%APPLYCOLORCHANNEL  Map a [0,1] grayscale image to RGB using a named color.
%   rgb = emViewer.applyColorChannel(gray, colorName)
%
%   Supported color names: 'red', 'green', 'blue', 'cyan', 'magenta',
%   'yellow'. Any other value produces a grayscale (white) output.
%
%   Used by FermiViewer EDS composite blending and compare-mode overlay.

[H, W] = size(gray);
rgb = zeros(H, W, 3);
switch lower(colorName)
    case 'red',     rgb(:,:,1) = gray;
    case 'green',   rgb(:,:,2) = gray;
    case 'blue',    rgb(:,:,3) = gray;
    case 'cyan',    rgb(:,:,2) = gray; rgb(:,:,3) = gray;
    case 'magenta', rgb(:,:,1) = gray; rgb(:,:,3) = gray;
    case 'yellow',  rgb(:,:,1) = gray; rgb(:,:,2) = gray;
    otherwise,      rgb(:,:,1) = gray; rgb(:,:,2) = gray; rgb(:,:,3) = gray;
end
end
