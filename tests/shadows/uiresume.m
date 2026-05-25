function uiresume(varargin)
%UIRESUME (test shadow)  No-op paired with the uiwait shadow.
%
%   The uiwait shadow never blocks, so production uiresume(fig) calls (e.g.
%   in zoomToDimensions's key handlers) have nothing to resume. Calling the
%   real uiresume on a figure that isn't waiting warns; this stub avoids
%   that noise. Logs so the diary records the call.

    fprintf('[shadow:uiresume]\n');
end
