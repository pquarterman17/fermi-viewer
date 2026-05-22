function data = promptAndLoadRaw(fig, fp)
%PROMPTANDLOADRAW  Dialog flow for parsing a headerless RAW image file.
%
%   data = fermiViewer.session.promptAndLoadRaw(fig, fp)
%
%   RAW image files have no dimensions in the file; we must ask the user
%   for width, height, and bit depth. Returns [] on cancel or invalid
%   input (with a warn dialog parented at fig); otherwise the parser data
%   struct from parser.importRawImage.

    data = [];

    [~, fname, fext] = fileparts(fp);
    prompt  = {'Width (pixels):', 'Height (pixels):', 'Bit Depth (8, 16, or 32):'};
    dlgTitle = sprintf('RAW Image Parameters — %s%s', fname, fext);
    defaults = {'512', '512', '16'};

    answer = inputdlg(prompt, dlgTitle, [1 40], defaults);
    if isempty(answer)
        return;
    end

    W = str2double(answer{1});
    H = str2double(answer{2});
    B = str2double(answer{3});

    if isnan(W) || isnan(H) || isnan(B) || W < 1 || H < 1
        fermiViewer.chrome.quietAlert(fig, 'Invalid dimensions. Width and Height must be positive integers.', ...
            'Invalid Input', 'Icon', 'error');
        return;
    end

    if ~ismember(B, [8 16 32])
        fermiViewer.chrome.quietAlert(fig, 'BitDepth must be 8, 16, or 32.', ...
            'Invalid Input', 'Icon', 'error');
        return;
    end

    data = parser.importRawImage(fp, Width=W, Height=H, BitDepth=B);
end
