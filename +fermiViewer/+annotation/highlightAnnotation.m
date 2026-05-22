function highlightAnnotation(a, on)
%HIGHLIGHTANNOTATION  Toggle selection highlight on an annotation struct.
    if on
        lw = 3.5; ls = '--';
    else
        lw = 2;   ls = '-';
    end
    for fk = {'hLine','hCircle'}
        fn = fk{1};
        if isfield(a, fn) && ~isempty(a.(fn)) && isvalid(a.(fn))
            a.(fn).LineWidth = lw;
            a.(fn).LineStyle = ls;
        end
    end
    if isfield(a, 'hText') && ~isempty(a.hText) && isvalid(a.hText)
        a.hText.EdgeColor = 'none';
        if on
            a.hText.FontAngle = 'italic';
        else
            a.hText.FontAngle = 'normal';
        end
    end
    if isfield(a, 'hRect') && ~isempty(a.hRect) && isvalid(a.hRect)
        a.hRect.LineWidth = lw;
        a.hRect.LineStyle = ls;
    end
    if isfield(a, 'hHead') && ~isempty(a.hHead) && isvalid(a.hHead)
        if on
            a.hHead.EdgeColor = [0 1 1];
        else
            a.hHead.EdgeColor = a.color;
        end
    end
end
