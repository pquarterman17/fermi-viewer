function deleteAnnotHandles(a)
%DELETEANNOTHANDLES  Delete all graphics handles of an annotation struct.
    for fk = {'hText','hLine','hHead','hRect','hCircle'}
        fn = fk{1};
        if isfield(a, fn) && ~isempty(a.(fn)) && isvalid(a.(fn))
            delete(a.(fn));
        end
    end
end
