%TEST_FV_EXPORT_OPTIONS  Exercise every export option end-to-end (headless).
%
%   Drives all FermiViewer export paths and asserts each produces non-empty
%   output. Dialog-based exports run via the tests/shadows stubs
%   (uiputfile / uigetdir / listdlg / inputdlg presets).
%
%   Covered: exportImage PNG, exportImage TIFF, Save Image button,
%   Burn Overlays, Copy to clipboard, Batch Export, exportMeasurements CSV,
%   Export Profile CSV, Journal Export, Create GIF.
%
%   Requires real DM4 data in +test_datasets/Microscopy. Auto-skips if
%   absent.
%
%   Run standalone:  run tests/smoke/test_fv_export_options
%   Run via group :  runAllTests(Group="smoke")

clear; clc;
thisDir = fileparts(mfilename('fullpath'));
rootDir = fileparts(fileparts(thisDir));
if ~contains(path, rootDir), addpath(rootDir); end
shadowDir = fullfile(rootDir, 'tests', 'shadows');
if ~contains(path, shadowDir), addpath(shadowDir, '-begin'); end

fprintf('\n=== test_fv_export_options ===\n');

micro = fullfile(rootDir, '+test_datasets', 'Microscopy');
f1 = fullfile(micro, 'Overview_0001.dm4');
f2 = fullfile(micro, 'Overview_0002.dm4');
if ~isfile(f1) || ~isfile(f2)
    fprintf('  SKIP (need 2 DM4 files in +test_datasets/Microscopy)\n');
    return;
end

outDir = fullfile(tempdir, sprintf('fvexp_%d', randi(1e9)));
mkdir(outDir);
cleanupDir = onCleanup(@() rmdir(outDir, 's'));
cleanupAppd = onCleanup(@() clearShadowAppdata());

api = FermiViewer(); api.fig.Visible = 'off';
cleanupApi = onCleanup(@() safeCloseEx(api));
drawnow;
api.loadImages({f1, f2}); drawnow;
api.setActiveIdx(1); drawnow;
fig = api.fig;

passed = 0; failed = 0;
fkb = @(p) ternKB(p);

% 1-2. API image export (PNG, TIFF)
p = fullfile(outDir,'img.png'); api.exportImage(p);
[passed,failed] = chk('exportImage PNG',  fkb(p)>0, passed, failed);
p = fullfile(outDir,'img.tif'); api.exportImage(p);
[passed,failed] = chk('exportImage TIFF', fkb(p)>0, passed, failed);

% 3. Save Image button
p = fullfile(outDir,'save.png'); setappdata(0,'SHADOW_UIPUTFILE',p);
fireBtn(fig,'Save Image');
[passed,failed] = chk('Save Image button', fkb(p)>0, passed, failed);

% 4. Burn Overlays
p = fullfile(outDir,'burn.png'); setappdata(0,'SHADOW_UIPUTFILE',p);
fireBtn(fig,'Burn Overlays');
[passed,failed] = chk('Burn Overlays', fkb(p)>0, passed, failed);

% 5. Copy to clipboard (no file)
ok = true; try, fireBtn(fig,'Copy'); catch, ok=false; end
[passed,failed] = chk('Copy clipboard', ok, passed, failed);

% 6. Batch Export
bd = fullfile(outDir,'batch'); mkdir(bd); setappdata(0,'SHADOW_UIGETDIR',bd);
fireBtn(fig,'Batch Export');
n = numel(dir(fullfile(bd,'*.png'))) + numel(dir(fullfile(bd,'*.tif')));
[passed,failed] = chk('Batch Export', n>=2, passed, failed);

% 7. exportMeasurements CSV (make a distance measurement first)
api.cancelCapture(); fireBtn(fig,'Distance');
api.simulateClick(40,40); api.simulateClick(120,90); drawnow;
p = fullfile(outDir,'meas.csv'); api.exportMeasurements(p);
[passed,failed] = chk('exportMeasurements CSV', isfile(p), passed, failed);

% 8. Export Profile CSV (draw a line profile first)
api.cancelCapture(); fireBtn(fig,'Line Profile');
api.simulateClick(30,30); api.simulateClick(150,120); drawnow;
p = fullfile(outDir,'prof.csv'); setappdata(0,'SHADOW_UIPUTFILE',p);
fireBtn(fig,'Export CSV');
[passed,failed] = chk('Export Profile CSV', fkb(p)>0, passed, failed);

% 8b. Profile -> BosonPlotter (repointed to CSV export; was a hard crash on
%     a malformed createDataStruct call + dead BosonPlotter launch). Match
%     by substring to avoid the unicode arrow in the button label.
p = fullfile(outDir,'prof_bp.csv'); setappdata(0,'SHADOW_UIPUTFILE',p);
bpBtns = findall(fig,'Type','uibutton');
bpBtns = bpBtns(arrayfun(@(b) contains(char(b.Text),'BosonPlotter'), bpBtns));
if ~isempty(bpBtns), bpBtns(1).ButtonPushedFcn(bpBtns(1),[]); end
[passed,failed] = chk('Profile -> BosonPlotter CSV', fkb(p)>0, passed, failed);

% 9. Journal Export (listdlg + inputdlg + uiputfile presets)
p = fullfile(outDir,'journal.png');
setappdata(0,'SHADOW_LISTDLG',8);   % 'Custom' preset -> uses inputdlg
setappdata(0,'SHADOW_INPUTDLG',{'80','300','png'});
setappdata(0,'SHADOW_UIPUTFILE',p);
fireBtn(fig,'Journal Export');
setappdata(0,'SHADOW_INPUTDLG',''); setappdata(0,'SHADOW_LISTDLG','');
[passed,failed] = chk('Journal Export', fkb(p)>0, passed, failed);

% 10. Create GIF (open dialog, fire its create button)
p = fullfile(outDir,'anim.gif'); setappdata(0,'SHADOW_UIPUTFILE',p);
try
    fireBtn(fig,'Create GIF'); drawnow;
    dlgs = findall(groot,'Type','figure'); dlgs = dlgs(dlgs ~= fig);
    for d = dlgs(:)'
        bb = findall(d,'Type','uibutton');
        hit = bb(arrayfun(@(x) any(strcmpi(x.Text,{'Create','Export','Create GIF','Save','OK'})), bb));
        if ~isempty(hit), hit(1).ButtonPushedFcn(hit(1),[]); drawnow; break; end
    end
catch ME
    fprintf('  gif err: %s\n', ME.message);
end
[passed,failed] = chk('Create GIF', fkb(p)>0, passed, failed);

fprintf('\n============================================================\n');
fprintf('  Export options: %d passed, %d failed\n', passed, failed);
fprintf('============================================================\n');
if failed > 0
    error('test_fv_export_options:failed', '%d export option(s) failed.', failed);
end


function [p,f] = chk(name, cond, p, f)
    if cond, p=p+1; fprintf('  [OK]   %s\n', name);
    else,    f=f+1; fprintf('  [FAIL] %s\n', name); end
end
function fireBtn(fig, label)
    b = findall(fig, 'Type','uibutton','Text',label);
    if ~isempty(b) && ~isempty(b(1).ButtonPushedFcn)
        b(1).ButtonPushedFcn(b(1),[]); drawnow;
    end
end
function kb = ternKB(p)
    if isfile(p), d=dir(p); kb=d.bytes/1024; else, kb=0; end
end
function clearShadowAppdata()
    for k = {'SHADOW_UIPUTFILE','SHADOW_UIGETDIR','SHADOW_LISTDLG','SHADOW_INPUTDLG'}
        try, setappdata(0, k{1}, ''); catch, end
    end
end
function safeCloseEx(api)
    try
        if isstruct(api) && isfield(api,'close') && isvalid(api.fig), api.close(); end
    catch
    end
end
