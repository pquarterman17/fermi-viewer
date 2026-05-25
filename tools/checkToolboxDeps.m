function offenders = checkToolboxDeps(opts)
%CHECKTOOLBOXDEPS  Locate files that pull in a non-MATLAB toolbox.
%
%   checkToolboxDeps                 % scan all packages, print offenders
%   offenders = checkToolboxDeps     % return a table of file -> product(s)
%
%   The fast gate (tests/imaging/test_noToolboxDependency.m) tells you
%   WHETHER any add-on toolbox is required; this per-file scan tells you
%   WHICH file does it (the leaf caller). Slower (one
%   requiredFilesAndProducts call per file), so it's a diagnostic, not the
%   gate. Run from the repo root after the fast test fails.
%
%   Why this and not codeIssues/checkcode: those resolve whatever toolboxes
%   are installed, so a missing-toolbox dependency is invisible on a dev
%   machine that has the toolbox. requiredFilesAndProducts reports the
%   PRODUCTS a file needs, which is the real "MATLAB built-ins only" check.

    arguments
        opts.Roots (1,:) string = ["+parser", "+imaging", "+fermiViewer", "+calc"]
    end

    files = strings(0,1);
    for r = opts.Roots
        d = dir(fullfile(char(r), '**', '*.m'));
        for i = 1:numel(d)
            files(end+1) = string(fullfile(d(i).folder, d(i).name)); %#ok<AGROW>
        end
    end
    if isfile('FermiViewer.m'), files(end+1) = "FermiViewer.m"; end

    fprintf('Scanning %d files (this is slow — one analysis per file)...\n', numel(files));
    name = strings(0,1); prod = strings(0,1);
    for i = 1:numel(files)
        try
            [~, p] = matlab.codetools.requiredFilesAndProducts(char(files(i)));
            ns = string({p.Name});
            bad = ns(ns ~= "MATLAB");
            if ~isempty(bad)
                [~, n, e] = fileparts(files(i));
                name(end+1) = n + e;                 %#ok<AGROW>
                prod(end+1) = strjoin(bad, ", ");     %#ok<AGROW>
            end
        catch
        end
    end

    offenders = table(name(:), prod(:), 'VariableNames', {'File', 'RequiredProduct'});
    if isempty(name)
        fprintf('✓ No file requires a non-MATLAB toolbox.\n');
    else
        fprintf('\nFiles requiring add-on toolboxes:\n');
        disp(offenders);
    end
end
