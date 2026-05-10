function openFFTMaskEditor(filteredPixels, hook)
%OPENFFTMASKEDITOR  Open FFT mask editor with interactive circle placement.
%   hook.undoPush()          — push undo state before modifying pixels
%   hook.applyResult(pixels) — write filtered pixels back and refresh
%   hook.setStatus(msg)      — status bar message
%   hook.btnPrimary          — [R G B] primary button colour
%   hook.btnFg               — [R G B] button font colour
    arguments
        filteredPixels  double
        hook            struct
    end

    F = fft2(double(filteredPixels));
    Fshift = fftshift(F);
    magImg = log10(abs(Fshift) + 1);

    fftFig = figure('Name', 'FFT Mask Editor', 'NumberTitle', 'off', ...
        'Units', 'pixels', 'Position', [200 150 700 560]);
    fftLayout = uigridlayout(fftFig, [2 1], ...
        'RowHeight', {'1x', 30}, 'Padding', [6 6 6 6]);

    fftAx = axes('Parent', uipanel(fftLayout));
    fftAx.Parent.Layout.Row = 1;
    imagesc(fftAx, magImg);
    colormap(fftAx, parula(256));
    axis(fftAx, 'image');
    fftAx.XTick = []; fftAx.YTick = [];
    title(fftAx, 'Click to place circular masks, then Apply', 'Interpreter', 'none');

    btnRow = uigridlayout(fftLayout, [1 5], ...
        'ColumnWidth', {60, 80, 80, 80, 80}, 'Padding', [0 0 0 0]);
    btnRow.Layout.Row = 2;

    lblRadius = uilabel(btnRow, 'Text', 'Radius:', 'HorizontalAlignment', 'right');
    lblRadius.Layout.Column = 1;
    spnRadius = uispinner(btnRow, 'Value', 15, 'Limits', [3 200], 'Step', 2);
    spnRadius.Layout.Column = 2;

    btnPrimary = [0.2 0.5 0.9];
    btnFg = [1 1 1];
    if isfield(hook, 'btnPrimary'), btnPrimary = hook.btnPrimary; end
    if isfield(hook, 'btnFg'), btnFg = hook.btnFg; end

    btnAddMask = uibutton(btnRow, 'Text', 'Add Mask', ...
        'ButtonPushedFcn', @(~,~) fftAddMask());
    btnAddMask.Layout.Column = 3;

    btnApply = uibutton(btnRow, 'Text', 'Apply', ...
        'BackgroundColor', btnPrimary, 'FontColor', btnFg, ...
        'ButtonPushedFcn', @(~,~) fftApplyMask());
    btnApply.Layout.Column = 4;

    btnCancel = uibutton(btnRow, 'Text', 'Cancel', ...
        'ButtonPushedFcn', @(~,~) close(fftFig));
    btnCancel.Layout.Column = 5;

    maskCircles = {};

    function fftAddMask()
        title(fftAx, 'Click on the FFT image to place mask center...', ...
            'Interpreter', 'none');
        fftAx.ButtonDownFcn = @captureMaskClick;
    end

    function captureMaskClick(~, evt)
        fftAx.ButtonDownFcn = [];
        cx = evt.IntersectionPoint(1);
        cy = evt.IntersectionPoint(2);
        r = spnRadius.Value;
        th = linspace(0, 2*pi, 60);
        xc = cx + r * cos(th);
        yc = cy + r * sin(th);
        hold(fftAx, 'on');
        plot(fftAx, xc, yc, 'r-', 'LineWidth', 1.5, 'HitTest', 'off');
        hold(fftAx, 'off');
        maskCircles{end+1} = [cx, cy, r];
        title(fftAx, sprintf('%d mask(s) placed — Add more or Apply', ...
            numel(maskCircles)), 'Interpreter', 'none');
    end

    function fftApplyMask()
        if isempty(maskCircles), return; end
        hook.undoPush();

        [H2, W2] = size(Fshift);
        mask = ones(H2, W2);
        [XX, YY] = meshgrid(1:W2, 1:H2);
        for mi = 1:numel(maskCircles)
            mc = maskCircles{mi};
            dist2 = (XX - mc(1)).^2 + (YY - mc(2)).^2;
            mask(dist2 <= mc(3)^2) = 0;
            mcx = W2 + 1 - mc(1);
            mcy = H2 + 1 - mc(2);
            dist2m = (XX - mcx).^2 + (YY - mcy).^2;
            mask(dist2m <= mc(3)^2) = 0;
        end

        Fmasked = Fshift .* mask;
        recovered = real(ifft2(ifftshift(Fmasked)));

        hook.applyResult(recovered);
        close(fftFig);
        hook.setStatus(sprintf('FFT mask applied (%d regions masked)', numel(maskCircles)));
    end
end
