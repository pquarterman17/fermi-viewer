# Changelog

All notable changes to FermiViewer will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project aims to follow [Semantic Versioning](https://semver.org/)
once it reaches v1.0.

## [0.49.0] — 2026-08-01

The EELS/EDS analysis layer catches up with the Python port: model-based
fitting, deconvolution, artifact handling, physical continuum backgrounds,
ζ-factor quantification, and counting-statistics error bars — all ported
with their test oracles, MATLAB-built-ins only. Plus the image-list
thumbnail renderer and the Processing-tab reorganization.

### Added
- **EELS model-based multi-edge fitting** (`eelsFitEdges` /
  `eelsFitEdgesMap` / `eelsEdgeShape`) — joint power-law background +
  hydrogenic edge-shape fit that separates overlapping edges
  (Mn-L/Fe-L class) where window integration mis-assigns; per-pixel SI
  maps via a fixed-exponent linearisation (one multi-RHS solve, no
  per-pixel fitting). Amplitude 1σ from the fit covariance.
- **EELS Fourier-ratio deconvolution** (`eelsFourierRatio`) — removes
  plural scattering from core-loss spectra using a low-loss PSF, with
  phase-preserving FFT regularisation; and **Richardson–Lucy**
  (`eelsRichardsonLucy`) with automatic ZLP-PSF centring (an off-centre
  PSF silently shifts the deconvolved spectrum).
- **EELS counting-statistics error bars** (`eelsAtomicSigma`;
  `atomicPercentSigma` field on `eelsQuantify`) — Poisson variance
  propagated through exact trapezoid weights and the at% normalisation
  Jacobian.
- **Sub-pixel ZLP alignment** — opt-in `SubPixel` option on
  `eelsAlignZLP` (parabolic peak refine + FFT phase-ramp fractional
  shift); `eelsKramersKronig` now flags `isNormalized` when the
  sum-rule vs peak-normalisation fallback was used.
- **EDS detector-resolution model** (`fanoResolution`) — Fiori–Newbury
  FWHM anchored at Mn-Kα 130 eV; the single source of peak widths for
  fitting, continuum masking, and artifact clearance.
- **EDS constrained peak deconvolution** (`fitPeaks` / `quantifyPeaks`)
  — multi-Gaussian fit with centers fixed at table line energies and
  Fano-model widths, amplitudes solved linearly; resolves overlapping
  lines (S-Kα/Mo-Lα/Pb-Mα at 15 kV recovered essentially exactly) and
  feeds net areas into the existing Cliff-Lorimer path.
- **EDS escape/sum-peak artifacts** (`predictArtifacts` /
  `removeArtifacts`) — predicts Si-escape and pile-up positions,
  partitions them into measure-freely vs model-as-fraction based on
  Fano-width clearance, and removes them before quantification (kills
  the Cu-escape-inflates-Fe-Kα false positive).
- **EDS physical continuum backgrounds** — `Background='bremsstrahlung'`
  on `elementMap`/`extractElementMaps` (closed-form per-pixel Kramers
  amplitude — background at the cost of a window sum), plus
  `fitContinuum`/`subtractContinuum` fitting amp + detector-absorption
  through Fano-masked characteristic peaks.
- **EDS ζ-factor quantification** (`zetaQuantify`) — composition AND
  mass-thickness with a self-consistent absorption iteration
  (Watanabe–Williams); `zetaFromKFactors` bootstraps ζ factors from the
  existing 200 kV k-table with one measured standard; `doseElectrons`.
- **EDS robustness** — `mapIsBlank` coverage heuristic suppresses the
  ~100 at% noise maps absent elements produce in per-pixel-normalised
  quantification (wired into CL/ZAF); `toKeV` + `Units` options prevent
  eV-calibrated spectrum-image axes from silently selecting zero
  channels against keV windows (blank-map bug class from the field).
- **Image-list renderer** — per-row 16 px thumbnails (stride-sampled,
  percentile-stretched) and an accent rail marking the active image;
  the list is now a 2-column table and rows map 1:1 to image indices.
- **Skip-guard ratchet** (`test_skipGuards`) — parses `.gitignore` for
  local-only test data and fails the suite anywhere a test references it
  without an `isfile`/`exist` guard (kills the green-locally/red-CI
  class at the source).
- Theory documentation for all of the above in
  `docs/theory/spectroscopy.md` (9 new sections, literature-verified
  references) and an upgraded quantification path in the EDS
  spectrum-imaging tutorial.

### Changed
- Processing panel's 4th tab reorganized by intent: retitled 'Stack' →
  **'Surface'** (topography + stacking, 7 buttons); the segmentation
  trio (Back-Project, Particles, Watershed) relocated to the Analysis
  menu beside Grain ID — all three remain menu-reachable, now asserted
  by the wiring test.
- `elementMap` no longer casts the whole spectrum cube to double —
  flanking/peak channels are sliced at native class and accumulated in
  double (matters for multi-GB EDS cubes).

### Fixed
- Burn Overlays on headless R2022b survived clamped offscreen rendering
  (CI's Xvfb leg) by re-exporting at a compensating resolution.

## [0.48.0] — 2026-07-07

### Fixed
- **Copies and exports resampled to the on-screen size ("weirdly pixelated",
  pixel counts didn't match).** Reported from an R2022b machine; reproduced
  identically on R2023b/R2025b — machine-layout dependent, not
  version-specific. Three stacked causes: `copygraphics` with
  `ContentType='vector'` silently ignores `Resolution` and rasterizes the
  image at the axes' on-screen plot-box size; `getframe` ignores
  `PaperPosition` and captures at the temp figure's screen size; and in HQ
  render mode `appData.displayImg` is an area-downsampled buffer that Save
  Image wrote straight to disk. Copy to Clipboard, Burn Overlays, Save
  Image, and `api.exportImage` now render an offscreen copy at one output
  pixel per image pixel with full-resolution contrast-processed CData —
  verified bit-identical to the source through the real Windows clipboard,
  overlays included. Burn Overlays / Save Image emit exactly native-sized
  files; the export smoke test now asserts dimensions against parser truth.
- **GIF export with "Add scale bar" degraded every frame.** The label burn
  captured a legacy figure via `getframe`, which returns wrong-size frames
  on scaled displays (799×599 for an 800×600 frame), and the bilinear
  resize-back resampled the entire frame. The burn now renders offscreen
  pixel-exact; if capture fails the frame is kept unlabeled, never resampled.
- **Atom Columns "Save overlay" exported at the on-screen panel size**
  (~600 px regardless of image size); now a 1:1 native-resolution render.
- **Journal export eps/pdf honored neither the preset width nor DPI** (and
  `-deps` dithered to 1-bit black/white). Now prints at the requested
  physical size with a full-page raster at the requested DPI — APS preset
  verified as a 244×244 pt (86 mm) color EPS with a native 1016 px raster.
- **Save Crop ignored gamma/transform/invert** (bare linear stretch); crops
  now run the same contrast pipeline as the screen and Save Image.
- **Indexed/palette PNG/GIF/BMP displayed garbage** — single-output `imread`
  returns raw LUT indices, which were treated as intensities. The palette is
  now applied via `ind2rgb`. (Backported from the Python port.)
- **Grain-boundary network length was ~2× too long** — `grainStats` summed
  the both-sides boundary mask, double-counting every seam. Each inter-grain
  edge is now counted once; `boundaryMask` still marks both sides for
  display overlays. (Backported from the Python port.)
- **Corrupt/desynced BCF "instructive" blocks crashed the whole import** —
  an undecodable delta width now skips to the pixel boundary instead of
  aborting. (Backported from the Python port.)
- **EDS map rendered as a tiny thumbnail / zoom did nothing.** Entering EDS
  mode draws the false-colour composite directly on the axes, but the
  HQ-downsample zoom listener (`fermiViewer.display.prepareDisplayBuffer`)
  kept firing and rebuilt the image from the single-view *survey* pixels,
  overwriting the composite handle's `CData`/`XData` with the survey extent —
  shrinking the map into a corner and re-clobbering it on every zoom. The
  buffer rebuild now no-ops in EDS/compare composite modes, so the map fills
  the axes and box-zoom works.
- **Could not remove a loaded BCF (or any image) from the list.**
  `fermiViewer.processing.imageOps('remove', …)` pruned its local `appData`
  copy but then refreshed the listbox via a closure callback that read the
  caller's *pre-removal* state, so the file never disappeared. The list and
  display refresh now run in `onRemoveImage` after the state is reassigned.
- **Zoom Fit/1:1/Out sized the axes from the survey image in EDS mode**
  (the "tiny composite in a huge black box"); dimension logic extracted to
  `fermiViewer.interaction.zoomOps`, which sources the composite's extent.
  Removing an image now remaps EDS channel source indices, and channel
  labels track their source files.
- **Stale EDS composite handle after display** silently broke double-click
  zoom-reset and removal; first paint now rebuilds the HQ display buffer
  (sharper first load) and Auto contrast percentiles match
  DigitalMicrograph's look.
- **Large real EDS maps opened as a blank panel**: `importBCF`'s
  `MaxCubeBytes` cap raised 1.5 → 5 GB so a typical 512² map keeps its
  spectral cube; new `imaging.eds.identifyPeaks` names channels when the
  BCF header lists no elements.
- **Compare-mode contrast/gamma edits did nothing** — the slider callbacks
  targeted the deleted single-view axes (see Added for the per-panel
  contrast windows); the Contrast section no longer clips the Link L/R row.

### Added
- **TIA SER spectra and spectrum images (DataTypeID 0x4120).**
  `parser.importSER` previously hard-rejected these files. A single element
  now imports as a 1-D spectrum (energy axis, eV); a scanned series (line
  profile or map) becomes a spectral cube published through the same
  `edsData` contract as `importBCF`, so the EDS Spectrum Image workshop
  opens SER maps unmodified, with a synthesized total-counts survey image
  for display. Multi-frame 0x4122 image series now warn that only frame 1
  is imported (was silent). Synthetic fixture generator
  (`tests/parser/writeMiniSer.m`, mirroring the Python port's fixtures) and
  suite `test_ser_spectra` pin the format.
- **Per-panel compare contrast/gamma with an L/R link toggle**
  (`+fermiViewer/+compare/panelContrast`): each side-by-side panel keeps its
  own lo/hi/gamma/transform/invert window synced onto the sliders; linking
  applies edits to both panels.
- **Image groups for compare** (`fermiViewer.groups.GroupModel` +
  "Compare Groups" bar): name groups in the file list and bind one to each
  compare panel so the arrows cycle within a group instead of the full list.
- `fermiViewer.export.captureAxesExact` — shared pixel-exact offscreen
  capture (dimension-checked `getframe`, `exportgraphics` center-crop
  fallback) used by Burn Overlays, GIF scale-bar labels, and the
  atom-column workshop overlay export.

## [0.47.0] — 2026-06-07

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
- **Atom-column analysis.** `+imaging/+atoms` compute layer —
  `detectColumns`, `fitGaussian2D` (sub-pixel 2D Gaussian refinement),
  `findLatticeVectors`, `assignSublattice`, `peakPairStrain` (PPA strain
  mapping) — plus the interactive Atom-Column Workshop
  (`+fermiViewer/+atomcolumns/`, Processing → Atom Columns…).
- **Quantitative EELS composition.** `+imaging/+eels` gains
  `eelsCrossSection` (hydrogenic K/L cross-sections), `eelsQuantify`
  (relative at% from core-loss edges), and `eelsQuantifyMap` (per-pixel
  SI composition maps); wired into the GUI as Analysis → Quantify EELS…
- **Persistent calibration database** (`+fermiViewer/+calibration/`):
  `calibrationStore` keeps pixel-size calibrations keyed by
  instrument/magnification; saved calibrations auto-apply on load
  (`autoApplyFromDatabase`), with a manager dialog
  (`openCalibrationDatabase`) and save prompts after manual calibration.
- **GUI refresh (Variant A).** Design-token refresh with light toolbar
  icons + flat dark buttons; menu bar consolidated 9 → 6 menus; command
  palette (`Ctrl`/`⌘`+`K`, `buildCommandPalette`); workbar with hairline
  groups and accent Open button; status-bar readouts for capture mode,
  zoom %, and image N-of-M.
- Theory & tutorial docs: quantitative EELS theory
  (`docs/theory/spectroscopy.md`), EELS quantification workflow tutorial,
  atom-column + PPA strain theory & tutorial, EDS spectrum-imaging
  tutorial; developer handbook promoted to `docs/development.md`.

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
- `devReload` now flushes package functions, not just the GUI — edits to
  `+fermiViewer/` / `+imaging/` code take effect without a MATLAB restart.
- GUI polish round: toolbar icons rendered invisible on some themes (icon
  background now blends with the button); Processing tab-strip overflow and
  vestigial scroll arrows (titles shortened so all 4 tabs fit, scrollbar
  lane reserved); dropdown arrows clipped by the scrollbar; hard-to-grab
  panel resize border; tools panel widened 290 → 312 px; `uitabgroup`
  `FontSize` dropped (unsupported in R2022b uifigures).
- `imaging` argument-validator fixes: invalid defaults in `radialProfile`,
  `morphOp`, and `backProject` (`OutputSize`) rejected valid calls;
  `templateMatch` FFT cross-correlation lag selection corrected.

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
- Right-panel collapsible-sections experiment reverted — the Processing
  tab selector is back (collapsible sections fought the fixed-width strip).
- LF line endings enforced repo-wide via `.gitattributes`.

## [0.46.0] — 2026-05-25

Recorded retroactively — the v0.46.0 tag and GitHub release predate
changelog upkeep.

### Added
- **Pure-MATLAB ML grain identification**: automatic segmentation,
  interactive trainable segmentation, random-forest classifier option,
  SLIC superpixel pre-segmentation, label overlay + per-grain CSV export,
  and the interactive GrainWorkshop GUI.
- Persistent Analysis ROI shared by FFT, diffraction, CTF, and defect-count
  tools.
- Apache 2.0 license + NOTICE
- README, CHANGELOG, CITATION, CONTRIBUTING
- Filtered `setupToolbox.m`, `devReload.m`, `runAllTests.m` (EM-only test groups)
- New test groups: `fv`, `fvgui` (renamed from quantized_matlab's `em`/`emgui`)
- Full CI/CD pipeline: test gate on R2022b + latest, `.mltbx` release
  packaging on tag push, docs publishing.

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

### Fixed
- Supported floor set to **R2022b** with graceful older-version warning;
  classic `figure()` hosting of UI components replaced with `uifigure`;
  Image Processing Toolbox dependency removed.
- Headless test harness: self-sufficient `runAllTests`, safe dialog
  auto-close, and blocking-dialog window-leak cleanup.

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
