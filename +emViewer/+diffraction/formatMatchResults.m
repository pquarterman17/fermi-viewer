function r = formatMatchResults(result)
%FORMATMATCHRESULTS  Format diffraction indexing results for display.
%   r = formatMatchResults(result)
%   result: struct from imaging.indexDiffraction with .candidates array
%   Returns r with .items (cell of strings), .zoneAxisStr, .statusMsg
    arguments
        result struct
    end

    items = cell(1, numel(result.candidates));
    for k = 1:numel(result.candidates)
        c = result.candidates(k);
        items{k} = sprintf('%s (%s) — %d/%d matched, score=%.2f', ...
            c.phaseName, c.formula, c.nMatched, c.nSpots, c.score);
    end

    if ~isempty(result.candidates) && ~any(isnan(result.candidates(1).zoneAxis))
        za = result.candidates(1).zoneAxis;
        r.zoneAxisStr = sprintf('[%d %d %d]', za(1), za(2), za(3));
    else
        r.zoneAxisStr = 'N/A';
    end

    r.items = items;
    r.statusMsg = sprintf('Indexed: top=%s (score=%.2f)', ...
        result.candidates(1).phaseName, result.candidates(1).score);
end
