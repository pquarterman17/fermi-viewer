function results = checkCode(opts)
%CHECKCODE  Local static analysis over the whole repo (fast pre-push gate).
%
%   checkCode                      % analyze the repo, print a summary
%   checkCode(ErrorsOnly=true)     % only error-severity findings
%   checkCode(Path="+imaging")     % restrict to a subtree
%   results = checkCode(...)       % return the codeIssues object
%
%   Runs MATLAB's programmatic linter (codeIssues, R2023a+) recursively
%   over every .m file and prints findings grouped by severity. This is the
%   local equivalent of the CI 'lint' job, but comprehensive and instant —
%   run it before pushing to catch undefined names, dead code, suspect
%   syntax, and parse errors without waiting for a CI round-trip.
%
%   SCOPE NOTE — what this does NOT catch: backward minimum-release
%   compatibility (e.g. "this uses an R2023a feature so it breaks on
%   R2022b"). MATLAB has no reliable local linter for that; the R2022b
%   matrix leg in CI (.github/workflows/ci.yml) is the oracle for the
%   documented minimum. analyzeCodeCompatibility only looks FORWARD
%   (deprecated/removed APIs), not backward.
%
%   Exits with error('checkCode:findings') when error-severity issues
%   exist, so it can gate a pre-push hook.

    arguments
        opts.Path       (1,1) string  = "."
        opts.ErrorsOnly (1,1) logical = false
    end

    root = char(opts.Path);
    fprintf('Analyzing %s with codeIssues...\n', root);
    results = codeIssues(root);
    T = results.Issues;

    if isempty(T)
        fprintf('✓ No code issues found.\n');
        return;
    end

    % codeIssues severities: "error" | "warning" | "info"
    isErr  = T.Severity == "error";
    isWarn = T.Severity == "warning";
    nErr   = nnz(isErr);
    nWarn  = nnz(isWarn);
    nInfo  = height(T) - nErr - nWarn;

    show = T(isErr, :);
    if ~opts.ErrorsOnly
        show = T;
    end
    show = sortrows(show, "Severity");   % errors first

    fprintf('\n%-9s %-6s %s\n', 'SEVERITY', 'LINE', 'FILE :: DESCRIPTION');
    fprintf('%s\n', repmat('-', 1, 78));
    for k = 1:height(show)
        [~, fn, ext] = fileparts(show.FullFilename(k));
        fprintf('%-9s %-6d %s%s :: %s\n', ...
            upper(string(show.Severity(k))), show.LineStart(k), ...
            fn, ext, show.Description(k));
    end

    fprintf('\n%s\nSummary: %d error(s), %d warning(s), %d info\n', ...
        repmat('=', 1, 78), nErr, nWarn, nInfo);

    if nErr > 0
        error('checkCode:findings', '%d error-severity code issue(s).', nErr);
    end
end
