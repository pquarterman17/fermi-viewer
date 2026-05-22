function hideTestFig(fig)
%HIDETESTFIG  Hide a test figure after a visible-required test step.
%   hideTestFig(fig) sets Visible='off' and restores a normal position.
%
%   See also showTestFig
    if ~isvalid(fig), return; end
    fig.Visible = 'off';
end
