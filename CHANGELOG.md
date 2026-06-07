# Changelog

All notable changes to FermiViewer will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project aims to follow [Semantic Versioning](https://semver.org/)
once it reaches v1.0.

## [Unreleased]

### Added
- **EDS spectrum imaging.** `parser.importBCF` now decodes the BCF
  `SpectrumData0` hypercube into `edsData.cube` (`parser.decodeBcfCube`,
  covering 16-bit / 12-bit / instructive packing); `LoadCube` defaults true
  with a `MaxCubeBytes` guard. Element symbols + atomic numbers are now
  extracted (`edsData.elements` / `.elementZ`).
- `+imaging/+eds` helpers: `lineEnergy` (overvoltage-aware K/L/M selection),
  `elementMap` (energy-window integration + linear background),
  `extractElementMaps`, `pixelSpectrum`.
- Interactive **EDS Spectrum Image** workshop
  (`+fermiViewer/+spectrumImage/`): Analysis → EDS Spectrum Image… and headless
  `api.openSpectrumImage()` — click a pixel/ROI for its spectrum, drag an energy
  window for a live element map, CSV export.
- Compressed-HeaderData BCF regression vector plus 12-bit and Esprit-v2 sample
  vectors in `+test_datasets/BCF/`; new tests `test_eds_hypercube`,
  `test_fv_spectrumImage`.
- Apache 2.0 license + NOTICE
- README, docs/development.md (developer handbook), CHANGELOG, CITATION, CONTRIBUTING
- Filtered `setupToolbox.m`, `devReload.m`, `runAllTests.m` (EM-only test groups)
- New test groups: `fv`, `fvgui` (renamed from quantized_matlab's `em`/`emgui`)

### Added (format-contract test fixtures)
- Synthetic fixture writers (`tests/parser/writeMiniDM4.m`,
  `writeMiniSfsBcf.m`) generating minimal valid DM4 tag trees and SFS
  containers at test time — CI-runnable regression coverage for the
  energy-dimension/origin and multi-chunk pointer-table bugs without
  large binary data. New suite `test_dm_si_contract` (group `parser`)
  uses position-encoded voxels so axis transpositions change values,
  not just shapes; `test_importBCF` gains shuffled multi-chunk
  round-trip, corrupt-chain error-path, and real-Esprit (skip-if-absent)
  tests. `test_eels_real_dm4` extended with eelsAlignZLP, Kramers-Kronig
  and SVD cross-checks on the real corpus.

### Added (real-data EELS corpus)
- Local-only real-instrument test corpus (`+test_datasets/EELS/`, gitignored):
  four lunar-sample EELS spectrum images + HAADF + real Esprit EDS map from
  Zenodo 8403583 (CC-BY 4.0) and the rosettasciio EELS SI. Fetch with
  `tests/fetchRealEelsData.m`; regression suite `test_eels_real_dm4`
  (group `eels_adv`) skips when the data is absent.

### Fixed
- **MRC files with extended headers read header bytes as pixels.**
  `importMRC` read NSYMBT from byte 208 (the `MAP ` stamp on compliant
  files) instead of the MRC2014 byte 92, then a silent fseek-past-EOF
  failure left the cursor mid-header. Offsets corrected (NSYMBT@92,
  MAP@208, MACHST@212) and the data seek now errors cleanly when the
  offset exceeds the file. Caught by the Python port's golden
  cross-validation — the port read the standard offsets and disagreed
  with the frozen MATLAB output.
- **DM3/DM4 3D spectrum images imported transposed.** Real GMS SI cubes
  store energy as the *last* (slowest-varying) dimension, but the parser
  assumed energy-first — every real SI loaded with spatial/energy axes
  swapped and a channel-index energy axis. The energy dimension is now
  detected from the per-dimension calibration units ('eV'/'keV'/'meV');
  the energy axis now follows the DM convention
  `value = (index − origin) × scale` (the ZLP in real data lands at 0 eV).
- **BCF internal files over ~4 MB crashed `importBCF`** (out-of-bounds
  read on real Esprit maps): the SFS pointer table spans multiple chunks
  chained through chunk headers, but was read contiguously. The chain is
  now walked chunk-by-chunk, with bounds checks that produce a clear
  `badChunkChain` error on corrupt files.
- BCF files with **AACS/zlib-compressed `HeaderData`** (the common Bruker
  Esprit export) failed to load — a MATLAB→Java by-value buffer bug zeroed the
  decompressed XML. `importBCF` now decompresses via a return-value stream, so
  compressed maps open correctly.

### Changed
- **FermiViewer.m decomposition: 5,193 → 4,959 lines** (ratchet ceiling
  5,209 → 4,984). Measurement selection/deletion moved into
  `+fermiViewer/+measurement/measInteract.m`; the five extractions
  previously blocked by the closure-callback ordering hazard
  (CLAHE, stack MIP, image math, align stack, batch crop) now live in
  `+fermiViewer/+processing/stackOps.m` using the
  follow-up-after-assignment pattern — the package mutates a local
  appData copy and the thin wrapper runs closure follow-ups
  (refreshDisplay / onContrastOp / displayImage) after the
  `appData =` assignment. Also extracted: annotateDSpacing,
  runCircleROI, placeShape, selectImage, activePixelUnit.
- Package `+emViewer/` renamed to `+fermiViewer/` (Fermion-era cleanup)
- Chrome utilities (`themePref`, `resolveTheme`, `uxTokens`, `quietAlert`,
  `quietConfirm`, `resolveVisible`, `isHeadless`, `sectionHeader`)
  duplicated from quantized_matlab's `+bosonPlotter/` into `+fermiViewer/`
- ~730 call sites renamed in one consolidated sweep:
  `emViewer.X` / `bosonPlotter.X` → `fermiViewer.X`
- 22 MATLAB error-ID strings renamed: `'emViewer:foo:bar'` → `'fermiViewer:...'`
- Theme preference file: `boson_theme.mat` → `fermi_theme.mat`
- 14 test files renamed: `test_em_*` → `test_fv_*`
- Workspace export variable: `emProfileData` → `profileData`

## [0.1.0] — 2026-05-21

### Added
- Initial split from
  [quantized_matlab](https://github.com/pquarterman17/Quantized_matlab) via
  `git filter-repo --paths-from-file` — full per-file history preserved.
- Forked content:
  - `FermiViewer.m` — main GUI (~6,000 lines, orchestrator)
  - `+emViewer/` — extracted feature subpackages (later renamed to `+fermiViewer/`)
  - `+imaging/` — image processing algorithms (no toolboxes required)
  - `+parser/` — EM data importers: DM3, DM4, MRC, SER, BCF, TIFF, RAW, generic image
  - `tests/imaging/` — EM parser + imaging utility tests
  - `tests/parser/test_importBCF.m`, `tests/gui/test_annotation*` /
    `test_measurement*`, `tests/smoke/test_fv_smoke.m`
  - `docs/gui_emviewer.md` — feature reference
  - `docs/theory/` — EELS, EDS, imaging theory documentation
  - `docs/tutorials/eels-analysis-workflow.md`

Forked at quantized_matlab commit `202b4f1`.
