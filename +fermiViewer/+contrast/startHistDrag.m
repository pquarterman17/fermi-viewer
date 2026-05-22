function startHistDrag(which, ui, cb)
%STARTHISTDRAG  Begin drag interaction on a histogram contrast handle.
%
%   fermiViewer.contrast.startHistDrag(which, ui, cb)
%
%   `which` is one of 'lo' (low handle), 'hi' (high handle), 'bc'
%   (brightness/contrast — drag the centre and span), or '' (gamma —
%   drag a midpoint to adjust gamma curve).
%
%   ui struct fields:
%       fig, histAx, sldLow, sldHigh, sldGamma
%   cb struct fields:
%       onContrastChanged - @(action, src) — called on lo/hi/bc moves
%       onGammaChanged    - @(src, evt)    — called on gamma drag
%
%   Sets fig.WindowButtonMotionFcn / WindowButtonUpFcn to nested handlers
%   that mutate ui.sldLow/sldHigh/sldGamma during the drag and restore the
%   original callbacks on release.

    origMotionFcn  = ui.fig.WindowButtonMotionFcn;
    origReleaseFcn = ui.fig.WindowButtonUpFcn;
    ui.fig.Pointer = 'left';
    ui.fig.WindowButtonMotionFcn = @histDragMotion;
    ui.fig.WindowButtonUpFcn    = @histDragRelease;

    bcStartFigPt = ui.fig.CurrentPoint;
    bcStartLo    = ui.sldLow.Value;
    bcStartHi    = ui.sldHigh.Value;

    function histDragMotion(~, ~)
        cp_ = ui.histAx.CurrentPoint;
        newVal = cp_(1,1);
        lims_ = ui.sldLow.Limits;
        gap = (lims_(2) - lims_(1)) * 0.001;
        newVal = max(lims_(1), min(lims_(2), newVal));
        if strcmp(which, 'lo')
            ui.sldLow.Value = min(newVal, ui.sldHigh.Value - gap);
            cb.onContrastChanged('changed', []);
        elseif strcmp(which, 'hi')
            ui.sldHigh.Value = max(newVal, ui.sldLow.Value + gap);
            cb.onContrastChanged('changed', []);
        elseif strcmp(which, 'bc')
            axPos = getpixelposition(ui.histAx, true);
            if axPos(3) <= 0 || axPos(4) <= 0, return; end
            curPt = ui.fig.CurrentPoint;
            dxPx = curPt(1) - bcStartFigPt(1);
            dyPx = curPt(2) - bcStartFigPt(2);
            origSpan  = max(bcStartHi - bcStartLo, gap);
            dataPerPx = (lims_(2) - lims_(1)) / axPos(3);
            shift     = dxPx * dataPerPx;
            scale     = exp(-0.005 * dyPx);
            newSpan = max(gap, min(lims_(2) - lims_(1), origSpan * scale));
            centre  = bcStartLo + origSpan/2 + shift;
            newLo   = centre - newSpan/2;
            newHi   = centre + newSpan/2;
            if newLo < lims_(1)
                newLo = lims_(1); newHi = newLo + newSpan;
            end
            if newHi > lims_(2)
                newHi = lims_(2); newLo = newHi - newSpan;
            end
            ui.sldLow.Value  = newLo;
            ui.sldHigh.Value = newHi;
            cb.onContrastChanged('changed', []);
        else
            lo_ = ui.sldLow.Value;
            hi_ = ui.sldHigh.Value;
            if hi_ <= lo_, return; end
            t = (newVal - lo_) / (hi_ - lo_);
            t = max(0.01, min(0.99, t));
            newGamma = log(0.5) / log(t);
            newGamma = max(ui.sldGamma.Limits(1), min(ui.sldGamma.Limits(2), newGamma));
            ui.sldGamma.Value = newGamma;
            cb.onGammaChanged([], []);
        end
    end

    function histDragRelease(~, ~)
        ui.fig.WindowButtonMotionFcn = origMotionFcn;
        ui.fig.WindowButtonUpFcn    = origReleaseFcn;
        ui.fig.Pointer = 'arrow';
    end
end
