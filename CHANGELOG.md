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

### Fixed
- BCF files with **AACS/zlib-compressed `HeaderData`** (the common Bruker
  Esprit export) failed to load — a MATLAB→Java by-value buffer bug zeroed the
  decompressed XML. `importBCF` now decompresses via a return-value stream, so
  compressed maps open correctly.

### Changed
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
