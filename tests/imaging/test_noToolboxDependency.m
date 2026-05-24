%TEST_NOTOOLBOXDEPENDENCY  Enforce the "MATLAB built-ins only" rule.
%
%   Run from root:  runAllTests(Group="fast")
%
%   FermiViewer must depend on base MATLAB ONLY — no add-on toolboxes — so
%   the .mltbx and CI (which run with products:"") work without extra
%   licenses. This is THE guard that would have caught the 2026-05-24
%   regression where bwlabel/bwdist/imresize/padarray (Image Processing
%   Toolbox) crept in and only "passed" locally because the dev machine had
%   IPT installed; CI (no toolboxes) and any IPT-free install failed.
%
%   Uses matlab.codetools.requiredFilesAndProducts over every package file
%   in one call (the union of required products). codeIssues / checkcode
%   CANNOT catch this — they resolve whatever toolboxes happen to be
%   installed. Run tools/checkToolboxDeps to locate the offending file when
%   this fails.

clear; clc;
thisDir = fileparts(mfilename('fullpath'));
ROOT    = fileparts(fileparts(thisDir));
if ~contains(path, ROOT), addpath(ROOT); end

% Gather every shipping/source .m file (packages + the GUI entry point).
roots = {'+parser', '+imaging', '+fermiViewer', '+calc'};
files = {};
for r = 1:numel(roots)
    d = dir(fullfile(ROOT, roots{r}, '**', '*.m'));
    for i = 1:numel(d)
        files{end+1} = fullfile(d(i).folder, d(i).name); %#ok<AGROW>
    end
end
files{end+1} = fullfile(ROOT, 'FermiViewer.m');

fprintf('Checking product dependencies of %d files...\n', numel(files));
[~, products] = matlab.codetools.requiredFilesAndProducts(files);
names = string({products.Name});
extra = names(names ~= "MATLAB");

if isempty(extra)
    fprintf('✓ MATLAB built-ins only (no add-on toolboxes).\n');
else
    fprintf('✗ Required add-on toolbox(es): %s\n', strjoin(extra, ', '));
    fprintf('  Run tools/checkToolboxDeps to find the offending file(s).\n');
    error('test_noToolboxDependency:toolboxRequired', ...
        'Code requires non-MATLAB product(s): %s', strjoin(extra, ', '));
end
