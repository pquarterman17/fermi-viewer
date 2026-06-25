%TEST_EDS_CUBE_CHANNELS  Cube-derived EDS composite channels (BCF -> element maps).
%
%   Covers the fix that makes "Enter EDS Mode" show real element maps for a
%   freshly-opened BCF instead of the (often blank) SEM survey image:
%     - parser.importBCF default cap now loads a 512x512x4096 (4.3 GB) cube
%     - imaging.eds.identifyPeaks finds element lines in a sum spectrum
%     - fermiViewer.eds.buildCubeChannels turns a cube into colored channels
%       (both the "elements listed" and the "auto-detect peaks" paths)
%     - fermiViewer.eds.computeComposite renders channels that carry a .map
%
%   Run:
%       run tests/imaging/test_eds_cube_channels
%       runAllTests(Group="eds")
%
%   Uses the real sample BCF files in +test_datasets/BCF/. Results are
%   accumulated inline (RES) so the suite is safe under run()'s shared
%   workspace — no caller-workspace helpers.

fprintf('\n');
fprintf('╔══════════════════════════════════════════════════════════════╗\n');
fprintf('║      EDS Cube-Derived Composite Channels — Test Suite      ║\n');
fprintf('╚══════════════════════════════════════════════════════════════╝\n');

ROOT = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(ROOT);

bcfDir   = fullfile(ROOT, '+test_datasets', 'BCF');
fHitachi = fullfile(bcfDir, 'Hitachi_TM3030Plus.bcf');   % elements listed: Cu,Al,C,O
fFig4b   = fullfile(bcfDir, 'Fig4b_EDSmap_Bruker.bcf');   % 512^2, NO elements listed

EDS_COLORS = {'red', 'green', 'blue', 'cyan', 'magenta', 'yellow', 'white'};

RES = cell(0, 2);   % each row: {label, condition}

% ════════════════════════════════════════════════════════════════════════
%  TEST 1: default cap loads a 512x512x4096 (~4.3 GB) cube
% ════════════════════════════════════════════════════════════════════════
fprintf('\n-- TEST 1: importBCF default cap loads a large cube --\n');
try
    d1 = parser.importBCF(fFig4b);         % no MaxCubeBytes override
    eds1 = d1.metadata.parserSpecific.edsData;
    RES(end+1,:) = {'Fig4b 512x512x4096 cube loaded at default cap', ...
        ~isempty(eds1.cube) && isequal(eds1.cubeSize, [512 512 4096])};
catch ME
    RES(end+1,:) = {sprintf('Fig4b import crashed: %s', ME.message), false};
end

% ════════════════════════════════════════════════════════════════════════
%  TEST 2: identifyPeaks finds the listed elements in the Hitachi spectrum
% ════════════════════════════════════════════════════════════════════════
fprintf('-- TEST 2: identifyPeaks matches element lines --\n');
try
    d2 = parser.importBCF(fHitachi);
    eds2 = d2.metadata.parserSpecific.edsData;
    pk = imaging.eds.identifyPeaks(eds2.sumSpectrum, eds2.energyAxis, BeamKV=15);
    syms2 = {pk.symbol};
    syms2 = syms2(~cellfun(@isempty, syms2));
    RES(end+1,:) = {sprintf('identifyPeaks found %d labeled peaks', numel(syms2)), ...
        ~isempty(syms2)};
    RES(end+1,:) = {'identifyPeaks found Cu (strongest Hitachi line)', ...
        any(strcmp(syms2, 'Cu'))};
catch ME
    RES(end+1,:) = {sprintf('identifyPeaks crashed: %s', ME.message), false};
end

% ════════════════════════════════════════════════════════════════════════
%  TEST 3: buildCubeChannels — "elements listed" path (Hitachi)
% ════════════════════════════════════════════════════════════════════════
fprintf('-- TEST 3: buildCubeChannels from listed elements --\n');
try
    d3 = parser.importBCF(fHitachi);
    ch3 = fermiViewer.eds.buildCubeChannels(d3, EDS_COLORS);
    RES(end+1,:) = {sprintf('returned %d channels', numel(ch3)), ~isempty(ch3)};
    if ~isempty(ch3)
        c1 = ch3{1};
        RES(end+1,:) = {'channel has non-empty .map', isfield(c1,'map') && ~isempty(c1.map)};
        RES(end+1,:) = {'channel .imageIdx == 0 (cube-derived)', c1.imageIdx == 0};
        RES(end+1,:) = {'channel has element .symbol', isfield(c1,'symbol') && ~isempty(c1.symbol)};
        RES(end+1,:) = {'map is 2-D matching cube H,W [240 320]', isequal(size(c1.map), [240 320])};
    end
catch ME
    RES(end+1,:) = {sprintf('buildCubeChannels (listed) crashed: %s', ME.message), false};
end

% ════════════════════════════════════════════════════════════════════════
%  TEST 4: buildCubeChannels — "auto-detect peaks" path (Fig4b, no elements)
% ════════════════════════════════════════════════════════════════════════
fprintf('-- TEST 4: buildCubeChannels via peak auto-detection --\n');
try
    d4 = parser.importBCF(fFig4b);
    RES(end+1,:) = {'Fig4b has NO listed elements (auto-detect path)', ...
        isempty(d4.metadata.parserSpecific.edsData.elements)};
    ch4 = fermiViewer.eds.buildCubeChannels(d4, EDS_COLORS);
    RES(end+1,:) = {sprintf('auto-detect produced %d channels', numel(ch4)), ~isempty(ch4)};
    if ~isempty(ch4)
        RES(end+1,:) = {'auto channel has non-empty .map', ...
            isfield(ch4{1},'map') && ~isempty(ch4{1}.map)};
    end
catch ME
    RES(end+1,:) = {sprintf('buildCubeChannels (auto) crashed: %s', ME.message), false};
end

% ════════════════════════════════════════════════════════════════════════
%  TEST 5: computeComposite renders .map channels non-black
% ════════════════════════════════════════════════════════════════════════
fprintf('-- TEST 5: computeComposite of cube channels is not black --\n');
try
    d5 = parser.importBCF(fHitachi);
    ch5 = fermiViewer.eds.buildCubeChannels(d5, EDS_COLORS);
    comp = fermiViewer.eds.computeComposite({}, ch5);   % no grayImages needed
    RES(end+1,:) = {'composite is RGB HxWx3', ndims(comp) == 3 && size(comp,3) == 3};
    RES(end+1,:) = {'composite is NOT all-black', max(comp(:)) > 0};
catch ME
    RES(end+1,:) = {sprintf('computeComposite crashed: %s', ME.message), false};
end

% ════════════════════════════════════════════════════════════════════════
%  TEST 6: buildCubeChannels returns {} when there is no cube (fallback)
% ════════════════════════════════════════════════════════════════════════
fprintf('-- TEST 6: no cube -> empty channel list (caller falls back) --\n');
try
    d6 = parser.importBCF(fHitachi, 'MaxCubeBytes', 1);   % force cube skip
    ch6 = fermiViewer.eds.buildCubeChannels(d6, EDS_COLORS);
    RES(end+1,:) = {'no-cube returns {} so caller can fall back', isempty(ch6)};
catch ME
    RES(end+1,:) = {sprintf('no-cube path crashed: %s', ME.message), false};
end

% ════════════════════════════════════════════════════════════════════════
%  SUMMARY
% ════════════════════════════════════════════════════════════════════════
passed = 0; failed = 0;
fprintf('\n');
for r = 1:size(RES, 1)
    if RES{r, 2}
        passed = passed + 1;
        fprintf('  PASS  %s\n', RES{r, 1});
    else
        failed = failed + 1;
        fprintf('  FAIL  %s\n', RES{r, 1});
    end
end
fprintf('\n──────────────────────────────────────────────────────────────\n');
fprintf('EDS Cube-Channel Tests: %d passed, %d failed (of %d)\n', ...
    passed, failed, passed + failed);
fprintf('──────────────────────────────────────────────────────────────\n');

if failed > 0
    error('test_eds_cube_channels:failures', '%d test(s) FAILED', failed);
end
