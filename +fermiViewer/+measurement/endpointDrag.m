function appData = endpointDrag(action, varargin)
%ENDPOINTDRAG  Live motion/release handlers for measurement endpoint dragging.
%
%   fermiViewer.measurement.endpointDrag('motion', targAx, ad, whichEnd, measRef)
%   appData = fermiViewer.measurement.endpointDrag('release', appData, ctx, measIdx, measRef)
%
%   The 'motion' branch mutates the measurement struct in measRef but does
%   not touch appData. The 'release' branch follows the accept-and-return
%   pattern: caller must capture the returned appData.
%
%   'motion' inputs:
%       targAx, ad, whichEnd, measRef
%   'release' inputs:
%       appData (returned), ctx (fig + callbacks), measIdx, measRef
%
%   ctx struct (release only):
%       .fig                 - parent figure (drag-target callbacks restored on)
%       .origMotionFcn       - prior fig.WindowButtonMotionFcn to restore
%       .origReleaseFcn      - prior fig.WindowButtonUpFcn to restore
%       .runProfile(x1,y1,x2,y2)        - re-run profile after drag for 'profile' type
%       .createDistanceLabel(x1,y1,x2,y2) - rebuild label text for 'distance' type
%       .setStatus(msg)
%       .deselectMeasurement()

    switch action
        case 'motion'
            motion(varargin{:});
            appData = [];  % motion doesn't return state
        case 'release'
            appData = release(varargin{:});
        otherwise
            error('fermiViewer:measurement:endpointDrag:unknownAction', ...
                'Unknown action "%s".', action);
    end
end

function motion(targAx, ad, whichEnd, measRef)
    cp = targAx.CurrentPoint;
    nx = cp(1,1); ny = cp(1,2);
    if ~isempty(ad.displayImg)
        [H, W] = size(ad.filteredPixels);
        nx = max(0.5, min(W + 0.5, nx));
        ny = max(0.5, min(H + 0.5, ny));
    end
    m = measRef{1};

    if isfield(m, 'type') && strcmp(m.type, 'boxprofile')
        measRef{1} = boxMotion(m, whichEnd, nx, ny);
        return;
    end

    if whichEnd == 1
        rTick = (m.hP1.XData(end) - m.hP1.XData(1)) / 2;
        m.hP1.XData = [nx-rTick, nx, nx+rTick];
        m.hP1.YData = [ny, ny, ny];
        m.hLine.XData(1) = nx; m.hLine.YData(1) = ny;
    else
        rTick = (m.hP2.XData(end) - m.hP2.XData(1)) / 2;
        m.hP2.XData = [nx-rTick, nx, nx+rTick];
        m.hP2.YData = [ny, ny, ny];
        m.hLine.XData(2) = nx; m.hLine.YData(2) = ny;
    end
    if ~isempty(m.hText) && isvalid(m.hText)
        x1d_ = m.hLine.XData(1); y1d_ = m.hLine.YData(1);
        x2d_ = m.hLine.XData(2); y2d_ = m.hLine.YData(2);
        mx_ = (x1d_+x2d_)/2; my_ = (y1d_+y2d_)/2;
        dx_ = x2d_-x1d_; dy_ = y2d_-y1d_;
        len_ = hypot(dx_, dy_);
        if len_ < eps, nx_ = 0; ny_ = -1;
        else
            nx_ = -dy_/len_; ny_ = dx_/len_;
            if ny_ > 0, nx_ = -nx_; ny_ = -ny_; end
        end
        lx_ = mx_+14*nx_; ly_ = my_+14*ny_;
        if ~isempty(ad.filteredPixels)
            [H_,W_] = size(ad.filteredPixels);
            if lx_<1||lx_>W_||ly_<1||ly_>H_
                lx_ = mx_-14*nx_; ly_ = my_-14*ny_;
            end
        end
        m.hText.Position = [lx_, ly_, 0];
    end
    measRef{1} = m;
end

function m = boxMotion(m, whichEnd, nx, ny)
%BOXMOTION  Live update of an interactive box-profile during a drag.
%   whichEnd: 1,2 = endpoints; 3 = body move; 4,5 = width side handles.
    x1 = m.hLine.XData(1); y1 = m.hLine.YData(1);
    x2 = m.hLine.XData(2); y2 = m.hLine.YData(2);

    switch whichEnd
        case 1
            x1 = nx; y1 = ny;
        case 2
            x2 = nx; y2 = ny;
        case 3
            % Body move: translate by cursor delta from last position.
            if isfield(m, 'boxLast') && ~isempty(m.boxLast)
                dxm = nx - m.boxLast(1);
                dym = ny - m.boxLast(2);
            else
                dxm = 0; dym = 0;
            end
            x1 = x1 + dxm; y1 = y1 + dym;
            x2 = x2 + dxm; y2 = y2 + dym;
        case {4, 5}
            % Width handle: project cursor onto the box perpendicular axis
            % to set the half-width.
            [ux, uy] = fermiViewer.measurement.boxGeom('perpUnit', x1, y1, x2, y2);
            mx = (x1 + x2) / 2; my = (y1 + y2) / 2;
            halfW = abs((nx - mx) * ux + (ny - my) * uy);
            m.width = max(1, 2 * halfW);
    end
    m.boxLast = [nx, ny];

    % Update center line + endpoints
    m.hLine.XData = [x1 x2];
    m.hLine.YData = [y1 y2];
    if isfield(m, 'hP1') && ~isempty(m.hP1) && isvalid(m.hP1)
        r = (m.hP1.XData(end) - m.hP1.XData(1)) / 2;
        m.hP1.XData = [x1-r, x1, x1+r]; m.hP1.YData = [y1, y1, y1];
    end
    if isfield(m, 'hP2') && ~isempty(m.hP2) && isvalid(m.hP2)
        r = (m.hP2.XData(end) - m.hP2.XData(1)) / 2;
        m.hP2.XData = [x2-r, x2, x2+r]; m.hP2.YData = [y2, y2, y2];
    end

    % Recompute patch corners + width-handle positions
    corners = fermiViewer.measurement.boxGeom('corners', x1, y1, x2, y2, m.width);
    if isfield(m, 'hPatch') && isvalid(m.hPatch)
        m.hPatch.XData = corners(:,1);
        m.hPatch.YData = corners(:,2);
    end
    [w1, w2] = fermiViewer.measurement.boxGeom('widthHandles', x1, y1, x2, y2, m.width);
    if isfield(m, 'hW1') && ~isempty(m.hW1) && isvalid(m.hW1)
        r = (m.hW1.XData(end) - m.hW1.XData(1)) / 2;
        m.hW1.XData = [w1(1)-r, w1(1), w1(1)+r]; m.hW1.YData = [w1(2), w1(2), w1(2)];
    end
    if isfield(m, 'hW2') && ~isempty(m.hW2) && isvalid(m.hW2)
        r = (m.hW2.XData(end) - m.hW2.XData(1)) / 2;
        m.hW2.XData = [w2(1)-r, w2(1), w2(1)+r]; m.hW2.YData = [w2(2), w2(2), w2(2)];
    end
end

function appData = release(appData, ctx, measIdx, measRef)
    ctx.fig.WindowButtonMotionFcn = ctx.origMotionFcn;
    ctx.fig.WindowButtonUpFcn    = ctx.origReleaseFcn;
    ctx.fig.Pointer = 'arrow';
    meas = measRef{1};
    x1 = meas.hLine.XData(1); y1 = meas.hLine.YData(1);
    x2 = meas.hLine.XData(2); y2 = meas.hLine.YData(2);
    if isfield(meas, 'boxLast'), meas.boxLast = []; end
    appData.overlays.measurements{measIdx} = meas;
    switch meas.type
        case 'profile'
            % Accept-and-return: ctx.runProfile() is a fire-and-forget
            % closure cb that writes the closure's appData.lastProfile,
            % which this function's returned local appData would clobber.
            % Re-run through measExecute on the local appData instead.
            appData = fermiViewer.measurement.measExecute('runProfile', ...
                appData, ctx.measCtx, x1, y1, x2, y2);
        case 'boxprofile'
            appData = fermiViewer.measurement.measExecute('recomputeBox', ...
                appData, ctx.measCtx, measIdx);
        case 'distance'
            if ~isempty(meas.hText) && isvalid(meas.hText)
                delete(meas.hText);
            end
            newTxt = ctx.createDistanceLabel(x1, y1, x2, y2);
            meas.hText = newTxt;
            appData.overlays.measurements{measIdx} = meas;
            ctx.setStatus(sprintf('Distance: %s', newTxt.String));
            % Prune the just-deleted label's stale entry (and any other dead
            % handles) before appending, so distLabels doesn't grow without
            % bound across repeated endpoint drags on the same measurement.
            dl = appData.overlays.distLabels;
            appData.overlays.distLabels = dl(cellfun(@isvalid, dl));
            appData.overlays.distLabels{end+1} = newTxt;
    end
    appData.measWorkshop.sync(appData.overlays.measurements);
    ctx.deselectMeasurement();
end
