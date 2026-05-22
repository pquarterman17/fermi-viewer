# CLAUDE.md — FermiViewer

This file provides guidance to Claude Code (claude.ai/code) when working with
this repository.

## Project Overview

MATLAB GUI for electron-microscopy image analysis. Imports TEM/STEM images from
Gatan (DM3/DM4), FEI/Thermo (SER), Bruker (BCF), MRC, and generic
TIFF/PNG/JPG/RAW. Supports EELS background subtraction and edge ID, EDS
multi-channel composite + Cliff-Lorimer quantification, electron-diffraction
indexing against a ~50-phase crystal database, FFT analysis, measurements, and
common image processing (CLAHE, Gaussian, median, FFT masking).

Split from [quantized_matlab](https://github.com/paigequarterman/quantized_matlab)
on 2026-05-21 to give the EM tooling its own home and a single-focus
open-source surface.

## Repository Structure

```
fermi-viewer/
├── setupToolbox.m            # Adds toolbox root to MATLAB path
├── devReload.m               # Close + flush + relaunch a GUI after code edits
├── FermiViewer.m             # Main GUI: TEM/STEM viewer + EELS/EDS/diffraction
├── runAllTests.m             # Master test runner
├── tests/                    # Test suites
│   ├── imaging/              # EM parsers, imaging utils, GUI API tests
│   ├── parser/               # Parser smoke tests (BCF, DM3, DM4)
│   ├── gui/                  # Annotation + measurement widget tests
│   └── smoke/                # Headless smoke tests (test_fv_smoke.m)
├── +parser/                  # EM data import (DM3/DM4, MRC, SER, BCF, TIFF, RAW)
│   ├── importAuto.m          # Extension dispatch entry point
│   ├── resolveParser.m       # Extension → parser-name table
│   └── createDataStruct.m    # Canonical data-struct factory
├── +imaging/                 # Image processing algorithms (no toolboxes)
├── +fermiViewer/             # Extracted FermiViewer subsystems
│   ├── themePref.m           # Theme preference read/write
│   ├── resolveTheme.m        # Dark/Light/Auto resolver
│   ├── uxTokens.m            # Colour-token source (single source of truth)
│   ├── quietAlert.m          # Headless-aware uialert
│   ├── quietConfirm.m        # Headless-aware uiconfirm
│   ├── resolveVisible.m      # Headless figure visibility
│   ├── isHeadless.m          # Detect headless test runs
│   ├── sectionHeader.m       # Section header widget
│   ├── +analysis/            # Particle count, drift correction, stitching, ...
│   ├── +annotation/          # Text annotation tools
│   ├── +calibration/         # Pixel-size calibration
│   ├── +contrast/            # Contrast sliders, CLAHE, histogram
│   ├── +diffraction/         # Spot detection + crystal-database matching
│   ├── +display/             # Image pipeline (raw → filtered → display)
│   ├── +eds/                 # EDS multi-channel composite + quantification
│   ├── +eels/                # EELS background subtraction + edge ID
│   ├── +measurement/         # Line profile, distance, angle, polyline, ROI
│   └── +export/              # PNG/TIFF/CSV export
├── +test_datasets/           # Real instrument files for runAllTests
│   ├── Microscopy/           # dm3, dm4, jpg, tif reference data (~210 MB)
│   └── BCF/                  # Bruker EDS spectrum-image samples
├── docs/                     # Detailed feature documentation
│   ├── gui_emviewer.md       # FermiViewer features, EELS, EDS, diffraction
│   ├── theory/spectroscopy.md   # EELS / EDS theory + LaTeX formulas
│   ├── theory/imaging.md     # FFT, CLAHE, drift correction, GPA
│   └── tutorials/eels-analysis-workflow.md
├── LICENSE                   # Apache 2.0
├── NOTICE                    # Copyright + attribution
├── CHANGELOG.md
├── CITATION.cff
├── CONTRIBUTING.md
└── BACKLOG.md                # Single source of truth for open work
```

## Conventions

- **Functions:** `PascalCase` — **Variables:** `camelCase` — **Struct fields:** lowercase
- **Parameters:** named arguments via `arguments` block (R2021b+)
- **No external toolboxes** — MATLAB built-ins only. Image processing,
  optimization, and statistics functionality is implemented in-package
- **Minimum version:** R2022b. If backward compatibility to R2022b would
  require a significantly inferior solution, use version detection
  (`isMATLABReleaseOlderThan('R20XXx')`) to branch
- **Unified data struct:** all parsers return `.time`, `.values`, `.labels`,
  `.units`, `.metadata` via `parser.createDataStruct()`
- **Section dividers:** `% ════════...` style
- **Pipeline:** parse → process → display (each stage independent)

## Quick Start

```matlab
setupToolbox                                              % add to path (once)
data = parser.importAuto('hrstem.dm3');                   % auto-detect format
data = parser.importDM3('image.dm3');
data = parser.importBCF('eds_map.bcf');
data = parser.importRawImage('raw.bin', Width=1024, Height=768, BitDepth=16);
FermiViewer                                                % interactive GUI
api = FermiViewer(Visible='off')                          % headless / scripted use
devReload FermiViewer                                      % close+flush+relaunch after edits
```

## Testing

```matlab
runAllTests                          % full suite
runAllTests(Group="fv")              % EM parsers + imaging utilities (fast)
runAllTests(Group="fvgui")           % headless FermiViewer API tests
runAllTests(Group="eds")             % EDS Cliff-Lorimer + composite tests
runAllTests(Group="eels")            % EELS background + edge ID tests
runAllTests(Group="eels_adv")        % EELS spectrum-image / thickness tests
runAllTests(Group="diffindex")       % diffraction indexing + crystal DB
runAllTests(Group="diff_sim")        % diffraction simulation tests
runAllTests(Group="edsquant")        % EDS quantification tests
runAllTests(Group="contour")         % contour / ring overlay tests
runAllTests(Group="spectral")        % shared spectral utilities
```

GUI tests run in MATLAB's headless mode — see `tests/run_gui_hidden.ps1`
(Windows) and `tests/run_gui_hidden.sh` (macOS/Linux). Real-data tests
(`test_fv_gui_real_dm`, `test_fv_parsers`, `test_importBCF`) read from
`+test_datasets/`.

## Tracking Work

**`BACKLOG.md`** at the repo root is the single source of truth for what's
open right now. It aggregates every open top-level item from active plans in
`plans/*.md` (grouped by tier, then by plan). Tracked in git.

`plans/*.md` files are gitignored working documents — detailed context and
sub-task checklists per workstream. Plans are per-machine; BACKLOG.md is
shared.

When completing an item: strike it in `plans/<plan>.md`, remove the matching
line from `BACKLOG.md`, in the same commit.

## Key Design Decisions

- **Functional approach** — pure functions returning structs; the orchestrator
  (`FermiViewer.m`) stays procedural. `handle` classes are used only for state
  containers (`AppState`, `UndoManager`) — the rule prohibits class-ifying the
  orchestrator script, not all classes.
- **Workshop pattern** — heavy GUI features (EELS, EDS, Diffraction,
  Annotation, Contrast, Calibration, Measurement) live in their own
  `+fermiViewer/+<feature>/` subpackage with three pieces: a
  `<Feature>WorkshopModel` handle class owning the feature's state, a
  functional view builder (e.g. `buildEdsPanel.m`), and callbacks that operate
  on `(model, hook)` rather than the parent's closure. The parent passes a
  small hook API (~9 named function handles for getActiveImage / setStatus /
  drawOverlay / etc.) so workshops never reach into the parent's state
  directly.
- **Accept-and-return pattern** — extracted package functions hold LOCAL
  copies of `appData`. Any callback that modifies `appData` (e.g.
  `refreshDisplay`, `rebuildScaleBar`) must accept it as input and return it
  as output: `appData = cb.refreshDisplay(appData)`, never
  `cb.refreshDisplay()`. For `displayImage.m`, bidirectional sync uses
  `pushAppData`/`pullAppData` via the `closureReturn_` bridge.
- **Unified data struct** — parser-agnostic GUI and display code.
- **Image pipeline** — `rawPixels` → `filteredPixels` → `displayImg`.
  Enable/disable triad: `displayImage()`, `clearDisplay()`,
  `setToolsEnabled()`. `undoPush()` inside `try` blocks only — prevents
  phantom undo on failure.
- **FFT masking** — uses `ButtonDownFcn`, not `ginput()` (`ginput` is
  unreliable in `uifigure`).

## Interop with quantized_matlab

Two MATLAB sessions can't share variables; file-based exchange is the bridge.

- **Line profile → BosonPlotter:** export profile as CSV from FermiViewer;
  import with `parser.importCSV` in BosonPlotter.
- **EELS spectrum → BosonPlotter:** same path. The CSV writer preserves
  calibrated x-axis units (eV).

No code dependency between the two repos.

## GUI Development Notes

### Reloading the GUI after code edits

MATLAB caches function definitions once loaded. After editing `FermiViewer.m`,
running `FermiViewer` again re-runs the *old* cached code unless the function
is flushed. Use `devReload`:

```matlab
devReload FermiViewer    % close all figures + clear function cache + relaunch
devReload                % defaults to FermiViewer
```

Preferred over `clear classes` (slower, also destroys class state) and
restarting MATLAB.

### Size ratchet — never raise the ceiling

`FermiViewer.m` has a ratchet test (`tests/imaging/test_fermiViewerSize.m`)
enforcing line-count and nested-function ceilings. These move **only
downward** as extractions shrink the file. New features must extract enough
existing code into `+fermiViewer/` (or consolidate nested-function callbacks)
to offset added lines — same commit or branch. **Never adjust
`LINE_CEILING` or `NESTED_FN_CEILING` upward.**

When adding code to FermiViewer, default to a public `+fermiViewer/<feature>.m`
package function that takes the handles/state it needs (typically the `ui`
struct + callback structs like `corrCb_`, `anaCb_`). Call it from a minimal
nested dispatcher in `FermiViewer.m`. Do not add new nested functions to
`FermiViewer.m` unless they are one- or two-liners that forward to a package
helper.

**Never add doubly-nested functions** (8-space indent) to `FermiViewer.m` —
parser-slot cost and worse refactorability. Use anonymous-function callbacks
(`@(~,~) ...`) for motion/release patterns instead.

### Layout integrity — catch clipped widgets early

MATLAB silently allows `uigridlayout` clipping: if a parent row allocates 22 px
and a nested grid needs 44 px, the widget renders but is partially or fully
invisible with no warning.

- **Detection helper:** `tests/gui/checkClippedLayouts.m` walks every
  `uigridlayout` and flags nested grids whose fixed pixel row/column spec
  overflows the slot the parent allocates. Also flags leaf widgets with
  `Position(3|4) == 0` after `drawnow`.
- **Regression test:** `tests/gui/test_layoutIntegrity.m` — run via
  `runAllTests(Group="fvgui")`.
- **Workflow:** after editing any `uigridlayout` `RowHeight` / `ColumnWidth`
  in `FermiViewer.m` or `+fermiViewer/*.m`, run `runAllTests(Group="fvgui")`
  before assuming the layout works.

### Theme system (Dark / Light / Auto)

`+fermiViewer/themePref.m` reads/writes a persisted theme preference
(`prefdir/fermi_theme.mat`). `+fermiViewer/resolveTheme.m` turns `'Auto'`
into a concrete `'Dark'` or `'Light'` value at apply time (MATLAB R2025a+
`MATLABTheme` setting → Windows registry → macOS defaults → Dark fallback).

Two layers always need updating together:
1. `theme(fig, 'dark'|'light')` — built-in MATLAB chrome (uitable empty
   viewport, scrollbars, dropdown overlays)
2. Per-widget `BackgroundColor` / `FontColor` — cells, panels, buttons

All colour tokens come from `+fermiViewer/uxTokens.m` — the single source of
truth.

### Cross-platform paths

This codebase runs on Windows and macOS:

- Never hardcode absolute paths — use `fullfile()` or environment variables
- Use forward slashes in Git Bash on Windows (it handles them fine)
- For MATLAB-launch helpers, check both `C:\Program Files\MATLAB\` and
  `/Applications/MATLAB_*.app/`

## Detailed Documentation

| Topic | File |
|-------|------|
| FermiViewer features, EELS, EDS, diffraction | [docs/gui_emviewer.md](docs/gui_emviewer.md) |
| EELS/EDS physics theory (LaTeX formulas) | [docs/theory/spectroscopy.md](docs/theory/spectroscopy.md) |
| Image processing theory | [docs/theory/imaging.md](docs/theory/imaging.md) |
| EELS analysis tutorial | [docs/tutorials/eels-analysis-workflow.md](docs/tutorials/eels-analysis-workflow.md) |

## Open Migration Notes

The split from `quantized_matlab` is in progress. The legacy `+fermiViewer/`
package directory has been renamed to `+fermiViewer/` (matching the chrome
namespace) and all call sites updated in a consolidated sweep — see
`plans/fermi-viewer-split-2026-05.md` in the qm repo for the full history.
If you find a stale `fermiViewer.X` reference in source or docs, treat it as a
bug and open a PR.
