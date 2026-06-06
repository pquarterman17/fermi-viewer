function fetchRealEelsData()
%FETCHREALEELSDATA  Download the local-only real-instrument test corpus.
%   Fetches the gitignored EELS/EDS real-data files used by
%   tests/imaging/test_eels_real_dm4.m (and picked up by the BCF and
%   real-DM sweep suites) into +test_datasets/. Files that already
%   exist are skipped, so re-running is cheap.
%
%   Sources (see +test_datasets/EELS/README.md for full provenance):
%     - Zenodo 8403583 (CC-BY 4.0) — Burgess et al., lunar sample 79221
%       STEM-EELS spectrum images + HAADF + Bruker Esprit EDS map
%     - hyperspy/rosettasciio test corpus — tiny GMS EELS SI
%
%   Usage:
%       run tests/fetchRealEelsData.m
%       % or, with tests/ on the path:
%       fetchRealEelsData

    thisDir = fileparts(mfilename('fullpath'));
    rootDir = fileparts(thisDir);
    dsDir   = fullfile(rootDir, '+test_datasets');

    zenodo = 'https://zenodo.org/api/records/8403583/files';

    % {relative target path, URL}
    manifest = {
        fullfile('EELS', 'FigS6_apatite_ZLP.dm4'), ...
            sprintf('%s/FigS6_apatite_ZLP.dm4/content', zenodo)
        fullfile('EELS', 'Fig4_apatite79221_OKedge_vesicle.dm4'), ...
            sprintf('%s/Fig4_apatite79221_OKedge_vesicle.dm4/content', zenodo)
        fullfile('EELS', 'Fig4_apatite79221_lowloss_vesicle.dm4'), ...
            sprintf('%s/Fig4_apatite79221_lowloss_vesicle.dm4/content', zenodo)
        fullfile('EELS', 'FigS4_apatite79221_F_Fe.dm4'), ...
            sprintf('%s/FigS4_apatite79221_F_Fe.dm4/content', zenodo)
        fullfile('Microscopy', 'Fig3c_apatite_HAADF.dm4'), ...
            sprintf('%s/Fig3c_apatite_HAADF.dm4/content', zenodo)
        fullfile('BCF', 'Fig4b_EDSmap_Bruker.bcf'), ...
            sprintf('%s/Fig4b_EDSmap_Bruker.bcf/content', zenodo)
        fullfile('EELS', 'rosettasciio_EELS_SI.dm4'), ...
            ['https://raw.githubusercontent.com/hyperspy/rosettasciio/' ...
             'main/rsciio/tests/data/digitalmicrograph/3D/EELS_SI.dm4']
    };

    fprintf('Fetching real-instrument test data into %s\n', dsDir);
    nNew = 0;
    for k = 1:size(manifest, 1)
        target = fullfile(dsDir, manifest{k, 1});
        if isfile(target)
            fprintf('  · %-45s already present\n', manifest{k, 1});
            continue;
        end
        targetDir = fileparts(target);
        if ~isfolder(targetDir)
            mkdir(targetDir);
        end
        fprintf('  ↓ %-45s ', manifest{k, 1});
        try
            websave(target, manifest{k, 2});
            d = dir(target);
            fprintf('%.1f MB\n', d.bytes / 1e6);
            nNew = nNew + 1;
        catch ME
            fprintf('FAILED (%s)\n', ME.message);
        end
    end
    fprintf('Done — %d new file(s) downloaded.\n', nNew);
end
