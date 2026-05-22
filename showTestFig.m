function showTestFig(fig)
%SHOWTESTFIG  Make a test figure visible without stealing focus.
%   showTestFig(fig) positions the figure off-screen and sets Visible='on'.
%   This allows the MATLAB display pipeline to initialize (images render,
%   callbacks fire) without the window appearing on the user's desktop.
%
%   Use hideTestFig(fig) to restore Visible='off' after the test step.
%
%   Example:
%       showTestFig(api.fig);
%       drawnow;
%       % ... run test that needs rendered content ...
%       hideTestFig(api.fig);
    if ~isvalid(fig), return; end
    pos = fig.Position;
    fig.Position = [-3000, -3000, pos(3), pos(4)];
    fig.Visible = 'on';
    drawnow;
end
