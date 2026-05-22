# FermiViewer Workshop Conversion

Convert FermiViewer's heavy feature subsystems into workshops — each owns
its state via a `handle` class, talks to FermiViewer through a small hook
API, and can be reasoned about and tested without the parent's closure
soup. Modelled directly on `plans/workshop-conversion-plan.md` (the
BosonPlotter playbook that landed four conversions in days).

This is the work that drives **MASTERPLAN W5 #69 (FermiViewer < 6,000
lines)** and **W5 #65 (apply workshop pattern to FermiViewer heavy
features)**. The 2026-04-16 archived plan rescued parser-slot headroom
via Pattern A dispatchers; that work is now the foundation this builds
on, not a substitute for it.

**Status:** Active
**Created:** 2026-05-01
**Updated:** 2026-05-10 (Reconciliation: two callback extraction batches shipped (-860 lines total). FermiViewer.m now 13,188 lines / 326 nested fns. All 8 workshop models + facades + sync + tests complete. Callback body extraction (sub-task c) remains for each workshop.)

---

## Context

### Why this exists

`FermiViewer.m` is **13,985 lines**, ~330 nested fns, and has had no
systematic workshop-style decomposition pass yet. The 2026-04-17
extraction batch (EELS, EDS, diffraction, annotation, ROI, export) used
**Pattern A** — multiple callbacks consolidated into one dispatcher
nested fn. That bought back ~28 nested-fn slots but barely changed the
line count, because the dispatcher bodies still live inside FermiViewer.m.

To reach **< 6,000 lines** (W5 #69) we need to remove ~7,985 lines / ~57%.
That requires the workshop pattern: state moves to a `handle` class, view
moves to a functional builder, callbacks move to a callbacks module —
all in `+fermiViewer/+<feature>/`. Replicate the BosonPlotter playbook
seven times and the file shrinks to target.

### Existing head start

One workshop is already partially built:

- `+fermiViewer/+measurement/MeasurementWorkshopModel.m` (293 lines) — a
  `handle` class with the full state surface (measurements list,
  selection, last-profile cache, etc.) and a static
  `fromOverlayMeasurements()` factory. **But it is only used to build
  a model on demand for the headless API** (`getMeasModelAPI` in
  FermiViewer.m line 13282). Production state still lives on
  `appData.overlays.measurements`. This is the BP-equivalent of "step 1b
  shipped, step 1c not yet" — exactly where Peak Workshop was the day
  before the cutover commit.

So Measurement is the obvious first workshop: the model-only investment
is already paid, and it carries the lessons-learned.

### How the pieces fit together

Each workshop becomes a sub-package under `+fermiViewer/`:

```
+fermiViewer/+<feature>/
├── <Feature>WorkshopModel.m   handle class — owns ALL feature state
├── <Feature>Workshop.m         facade — open(), bind(imageRef), close()
├── build<Feature>Window.m       UI construction (functional)
├── <feature>Callbacks.m         callbacks taking (model, hook), no fig/ax
└── <feature>Math.m              pure computation (when separable)
```

The **hook API** FermiViewer passes to each workshop replaces today's
implicit closure over `fig`, `ax`, `appData`, `ui`. Proposed surface
(8 fields — the count BP settled on after one round of revision):

```matlab
hook.getActiveImage    = @() struct(pixels=..., calibrated=..., pixelSize=..., pixelUnit=..., metadata=...);
hook.setStatus         = @(msg) ...;             % bottom-bar status
hook.drawOverlay       = @(type, args) handle;   % measurement line, ROI rect, scale bar
hook.clearOverlays     = @(filter) ...;          % filter = 'measurements' | 'roi' | 'all' | tag
hook.enableClickMode   = @(name, callback) ...;  % start two-click capture
hook.disableClickMode  = @() ...;
hook.replot            = @() ...;                % refreshDisplay
hook.logError          = @(ME) ...;
```

A workshop **never** reaches into FermiViewer's state directly —
neither `appData` nor `fig` nor `ax`. Cross-workshop communication
goes through hook calls, mediated by the parent.

### Data / control flow

```
FermiViewer.m (orchestrator, procedural)
    │
    ├── constructs hook (closure over fig/ax/appData/refreshDisplay/etc.)
    │
    ├── creates per-workshop:
    │     measWorkshop  = fermiViewer.measurement.MeasurementWorkshop(hook)
    │     histWorkshop  = fermiViewer.histogram.HistogramWorkshop(hook)
    │     ... etc.
    │
    └── on image load: calls each workshop's bind(imageRef) so their
        models pick up the new image's state (or initialise empty).
```

### Dependency map

- **Measurement** is independent; do first (model already exists).
- **Histogram-Contrast** is independent; touches `displayPixels` only.
- **Annotations** is independent; touches axes children only.
- **EDS / EELS / Diffraction** read the active image; mostly independent
  of each other but share the "open figure on a derived dataset" pattern.
- **FFT / Particle / Align** is independent.
- **Calibration & Scale Bar** is read by every other workshop (pixel
  size determines distance/area units). Extract last so the others
  define the contract.

---

## Inventory: candidate workshops + line budgets

Measured 2026-05-01 against the current FermiViewer.m source. Numbers
are line counts of the contiguous (or named) clusters; actual extraction
yield is typically 70–85% (some lines remain as thin dispatch).

| # | Workshop                  | Source clusters in FermiViewer.m                              | Est. lines | Notes |
|---|---------------------------|---------------------------------------------------------------|-----------:|-------|
| 1 | **Measurements**          | 5059–5279 (callbacks) + 6889–7825 (capture/profile/distance/labels) + 8073–8463 (angle/polyline) + 8810–9321 (selection/highlight/marquee) | **2,061** | Model 50% built. Highest ROI per hour. |
| 2 | **Diffraction-Indexing**  | 11585–12938 (`onDiffractionAction` + indexing) + 12939–13433 (GPA + radial profile) | **1,849** | Includes simulateDiffraction overlay, lattice fit, GPA strain mapping. |
| 3 | **EELS**                  | 13434–13985 (`onEELSAction` + `onEELSAdvanced` + `onEELSNavigateToggle`) + parts of UI panel construction | **552**   | Model dispatcher already in place from 2026-04-17 — convert to model-owned. |
| 4 | **Histogram-Contrast**    | 3794–4070 (contrast callbacks + transform) + 4635–4900 (histogram + drag) | **543**   | Tightly self-contained; touches displayPixels only. |
| 5 | **Calibration-ScaleBar**  | 4954–5048 + 7656–7734 + 8466–8825 (rebuildScaleBar, calibrate, autoDetect, applyCalibration) | **534**   | Already has 2 helpers in `+fermiViewer/`. Extract last (cross-cutter). |
| 6 | **FFT-Particle-Align**    | 9322–9702 (FFT mask, particle count, align stack) + 9703–9795 (colour overlay) | **474**   | Three loosely related processing tools; one dispatcher would suffice. |
| 7 | **EDS**                   | 9796–10100 (toolbar + channel mgmt + dispatchers) + 13861–13985 (composition profile + ROI) | **430**   | Already has Pattern A dispatchers; convert to model-owned. |
| 8 | **Annotations**           | 6573–6888 (`onAnnotationAction`)                              | **316**   | Smallest workshop. Good final reference if pattern needs polish. |

**Total est. extraction yield (workshops only):** ~6,759 lines, of which ~70%
typically actually leaves the parent → **~4,700 lines removed**. Not enough
on its own.

### Supporting workstream — UI construction extractions

`FermiViewer.m` lines **1–2467** (≈ 2,467 lines, 18% of the file) are
nothing but `uifigure` / `uigridlayout` / widget construction.
This is the same opportunity that drove BosonPlotter from 8,400 to
7,641 in three commits on 2026-04-26. Mirror that:

- `+fermiViewer/buildToolbar.m` (icon transform toolbar) — already exists
  partly via `transformToolbar.m`; harvest from FV.
- `+fermiViewer/buildRightPanel.m` (Measurement / Annotation / Diffraction
  expanders) — single largest construction block, ~1,000 lines.
- `+fermiViewer/buildContrastPanel.m` (~250 lines).
- `+fermiViewer/buildEDSPanel.m` (~150 lines).
- `+fermiViewer/buildEELSPanel.m` (~200 lines).
- `+fermiViewer/buildMenuBar.m` — already exists; verify FV uses it.

**Est. yield:** ~1,800 lines moved out, ~1,500 actually leave the parent.

### Combined arithmetic

```
Current:                        13,985 lines
- Workshop conversions (8):     -4,700  (70% effective yield of 6,759)
- UI construction extraction:   -1,500  (80% effective yield of 1,800)
- Misc nested-fn cleanup:         -800  (helpers already pure: percentile, onOff, setStatus, etc.)
                                ───────
Projected:                       6,985
                                ↑ still 985 over the < 6,000 target
```

That gap closes by:
- Going deeper on the largest workshops (Measurements + Diffraction
  alone could yield 85% rather than 70% if we move all helpers, not
  just dispatchers).
- Pulling the display pipeline (`refreshDisplay`, `prepareDisplayBuffer`,
  `updateMetadataPanel`) into `+fermiViewer/display.m` — ~300 lines.
- Pulling parsers/IO (`loadImagesFromPaths`, `appendImage`,
  `promptAndLoadRaw`, file-drop handler) into `+fermiViewer/io.m` —
  ~400 lines.

So < 6k is achievable but **only** with all eight workshops shipped
plus the UI construction sweep plus one or two infrastructure
extractions. This is multi-month work — sequence by ROI, not by
ambition.

---

## Tier 1 — High Impact

1. **Measurement Workshop conversion** — reference implementation for
   FermiViewer (Peak's role for BosonPlotter).
   - [x] ~~**1a Audit existing model.**~~ (2026-05-05, branch
         `feat/fermiviewer-measurement-workshop`, commit `7aab16d`) —
         Audited; gaps identified: model only carried 7 canonical
         fields, missing `lineColor`, `endSymbol`, `vertices`,
         `totalDist`, rectROI box bounds, and `stats`. Extended
         `emptyOnePeak` / `emptyMeas` / `normalizeMeasurements` to the
         full 16-field schema. Added instance method
         `bindFromOverlays(cellArr)` that preserves every overlay
         type (distance / profile / polyline / rectROI / angle) for
         the dialog seam; the static `fromOverlayMeasurements`
         remains for headless aggregable-only stats.
   - [x] ~~**1b Define hook API.**~~ (2026-05-05, commit `0f7cec1`) —
         Created `+fermiViewer/+measurement/MeasurementWorkshop.m` facade
         documenting the 8-field hook contract (`getActiveImage`,
         `setStatus`, `drawOverlay`, `clearOverlays`,
         `enableClickMode`, `disableClickMode`, `replot`, `logError`).
         Added `hasHook(field)` guard for headless-safe draw calls.
         Operational for all model-side work today; `show()` / `hide()`
         throw `MeasurementWorkshop:notImplemented` until 1c. **No
         FermiViewer.m wiring yet** — followed BP Peak playbook of
         shipping facade + tests in 1b, FV.m wiring lands as part of
         1c. Zero production-path risk on `main` until 1c lands.
   - [x] ~~**1c Cutover.**~~ (2026-05-06, commits `1d5b629` + `866daea`,
         merged to main) — Workshop constructed at startup, `sync()`
         calls at all 10 mutation points, `getMeasModelAPI` /
         `getMeasStatsAPI` / `onMeasurementStats` rewritten to use
         persistent model. Zero new nested fns added. Line count
         14,048 (under 14,050 cap).
   - [x] ~~**1d Tests.**~~ (2026-05-05, commit `7aab16d` + `0f7cec1`)
         — Test 14 in `test_measurementWorkshopModel.m` feeds
         legacy-shaped overlay records (distance / rectROI /
         polyline) through `normalizeMeasurements`; Test 15 round-
         trips them through `bindFromOverlays`. New
         `test_measurementWorkshop.m` covers the facade. Registered
         under group `em`; `runAllTests(Group="em")` 11/11 suites
         pass. The legacy-shape regression is in place *before* 1c
         to guard the cutover. Re-verify by running
         `runAllTests(Group="emgui")` after 1c lands.

2. **Diffraction-Indexing Workshop conversion** — biggest single
   line-count yield (1,849 lines).
   - [x] **2a Inventory.** (2026-05-06) — done during model creation.
   - [x] **2b Create `+fermiViewer/+diffraction/`.** (2026-05-06) — Model
         + Facade created; sync wired at 2 mutation points in FermiViewer.m.
   - [ ] **2c Extract callback bodies into package.** Move
         `onDiffractionAction` cases, GPA helpers, radial profile,
         simulateDiffraction overlay drawing into
         `+fermiViewer/+diffraction/` as standalone functions.
   - [x] **2d Tests.** (2026-05-06) — `test_diffractionWorkshop.m`
         10 tests pass; registered under `em` group.

3. **EELS Workshop conversion** — model-owned state for spectrum
   image, ZLP alignment, edge maps, ELNES cache.
   - [x] **3a–b Model + Facade + sync.** (2026-05-06) — `EELSWorkshopModel`
         (160 lines), `EELSWorkshop` facade, sync at 7 mutation points.
   - [ ] **3c Extract callback bodies.** Move `onEELSAction`,
         `onEELSAdvanced`, `onEELSNavigateToggle` bodies into package.
   - [x] **3d Tests.** (2026-05-06) — `test_eelsWorkshop.m` 10 tests pass.

4. **EDS Workshop conversion** — channel list, k-factors, current
   composition map, ROI composition cache.
   - [x] **4a–b Model + Facade + sync.** (2026-05-06) — `EDSWorkshopModel`
         (131 lines), `EDSWorkshop` facade, sync at 3 mutation points.
   - [ ] **4c Extract callback bodies.** Move EDS toolbar, channel mgmt,
         composition profile into package.
   - [x] **4d Tests.** (2026-05-06) — `test_edsWorkshop.m` 10 tests pass.

## Tier 2 — Medium Impact

5. **Histogram-Contrast Workshop conversion** — small but tightly
   self-contained; good pattern-validation target.
   - [x] **5a–b Model + Facade + sync.** (2026-05-06) — `ContrastWorkshopModel`
         + `ContrastWorkshop` facade, sync wired.
   - [ ] **5c Extract callback bodies.**
   - [x] **5d Tests.** (2026-05-06) — `test_contrastWorkshop.m` passes.

6. **Annotations Workshop conversion** — smallest of the eight; good
   final reference if the pattern needs polish.
   - [x] **6a–b Model + Facade + sync.** (2026-05-06) —
         `AnnotationWorkshopModel` + `AnnotationWorkshop` facade, sync wired.
   - [ ] **6c Extract callback bodies.**
   - [x] **6d Tests.** (2026-05-06) — `test_annotationWorkshop.m` 9 tests pass.

7. **FFT-Particle-Align Workshop conversion** — three loosely related
   processing tools; one workshop with three actions.
   - [x] **7a–b Model + Facade + sync.** (2026-05-06) —
         `ProcessingWorkshopModel` + `ProcessingWorkshop` facade, sync at 3 points.
   - [ ] **7c Extract callback bodies.**
   - [x] **7d Tests.** (2026-05-06) — `test_processingWorkshop.m` 8 tests pass.

8. **Calibration-ScaleBar Workshop conversion** — extract last (cross-
   cutter; every other workshop reads pixel size).
   - [x] **8a–b Model + Facade + sync.** (2026-05-06) —
         `CalibrationWorkshopModel` + `CalibrationWorkshop` facade, sync at 2 points.
   - [ ] **8c Extract callback bodies.**
   - [x] **8d Tests.** (2026-05-06) — `test_calibrationWorkshop.m` 10 tests pass.

9. **UI construction extraction sweep** — mirror BosonPlotter's
   2026-04-26 batch. Five `build<Block>.m` modules, each independent.
   *(Deferred — requires closure-variable refactoring; see notes below.)*

10. **Display pipeline + IO extraction** — `+fermiViewer/display.m` for
    `refreshDisplay` / `prepareDisplayBuffer` / `updateHistogram`;
    `+fermiViewer/io.m` for `loadImagesFromPaths` / `appendImage` /
    `promptAndLoadRaw` / file-drop. Pure-function targets — no model
    needed.
    *(Deferred — same closure-variable challenge as item 9.)*

## Tier 3 — Nice-to-Have

11. **Cross-workshop test harness** — once workshops 1–4 ship, abstract
    the common model-test scaffold (mirror MASTERPLAN W5 #63 for
    BosonPlotter). Likely a `tests/imaging/+harness/` mini-package.

---

## Lessons that carry over from the BosonPlotter Peak conversion

Two contract rules every FermiViewer workshop conversion must follow.
Both came out of the user-reported "Subscripted assignment between
dissimilar structures" bug that landed on the first fit after the Peak
cutover:

1. **Normalize on bind.** The model's `bindFromOverlays(measurements)`
   (or `bindFromImage(img)`, etc.) MUST call a
   `normalize<Feature>(input)` static helper that adds any missing
   canonical fields with sentinel defaults. Without this, an image
   loaded from a session saved before the canonical shape existed will
   throw on the first array assignment in a callback. Reference:
   `PeakWorkshopModel.normalizePeaks` + the regression test in
   `tests/fitting/test_peakWorkshopModel.m`.

2. **Test against legacy-shaped input.** Unit tests that build inputs
   via the helper-constructed canonical path will silently miss the
   shape mismatch at the bind boundary. Every workshop's test suite
   must include at least one case that hand-builds legacy-shaped input
   (struct with the old field set) and feeds it through `bindFrom*`.

These rules are recorded globally in
`feedback_workshop_pattern.md` (memory) and
`plans/workshop-conversion-plan.md` (BosonPlotter plan); duplicated
here so a FermiViewer-specific session can find them without crossing
file boundaries.

---

## Sequencing rationale

Cheapest-first ordering would put **Annotations (316 lines)** first.
Don't. Annotations is the *smallest* workshop, but it's not the most
*pattern-validating* — it has no state-shape evolution risk because
annotations have always carried their canonical fields.

Best-validating ordering puts **Measurement first** because:
- Model already built (50% credit applied).
- It's the workshop that exposed the legacy-shape bug in BP via Peak.
- It exercises every hook field (drawOverlay, enableClickMode,
  clearOverlays, replot, getActiveImage, setStatus, logError) — so the
  hook contract gets its full road-test up front.
- Largest single line-count yield (2,061 lines).

After Measurement, sequence by **line-count yield**:
Diffraction (1,849) → EELS (552) → Histogram-Contrast (543) →
Calibration (534) → FFT-Align (474) → EDS (430) → Annotations (316).

UI construction extraction (item 9) and display/IO extraction (item 10)
can land **interleaved** with the workshop work — they're independent
and good candidates for filler commits between heavier workshop pushes.

---

## Completed

- ~~**Tier 1 #1 sub-task 1a — Audit + extend MeasurementWorkshopModel schema**~~ (2026-05-05, commit `7aab16d` on `feat/fermiviewer-measurement-workshop`) — extended canonical schema to 16 fields covering every per-type field the FermiViewer dialog reads (`lineColor`, `endSymbol`, `vertices`, `totalDist`, `xMin`/`xMax`/`yMin`/`yMax`, `stats`); added `bindFromOverlays` instance method preserving all 4 production overlay types; 3 new tests including a legacy-shape regression. 15/15 model tests pass.
- ~~**Tier 1 #1 sub-task 1b — MeasurementWorkshop facade + hook contract**~~ (2026-05-05, commit `0f7cec1`) — facade class with `hasHook(field)` guard, model-side methods operational, `show()`/`hide()` gated; 6 facade tests pass; registered under `em` group. **FermiViewer.m unchanged** — facade lands as a parallel state container with zero production-path risk on `main`.
- ~~**Tier 1 #1 sub-task 1d — Legacy-shape regression test**~~ (2026-05-05, commits `7aab16d` + `0f7cec1`) — Test 14 + Test 15 in `test_measurementWorkshopModel.m` feed legacy-shaped overlay records through normalize + bind; satisfies the workshop contract rule #1 *before* 1c so the cutover is guarded. Re-verify with `runAllTests(Group="emgui")` after 1c lands.
- ~~**Tier 1 #1 sub-task 1c — Cutover wiring**~~ (2026-05-06, commits `1d5b629` + `1db3ec1` + `866daea`, merged to main) — Workshop constructed at startup, `sync()` at 10 mutation points, persistent model replaces on-demand rebuild for API/stats. Also resolved stash conflicts in 3 files and updated button wiring test for no-ellipsis rule. 22/22 workshop tests pass.
- ~~**Items 2–8 sub-tasks a/b/d — All remaining workshop models + facades + sync + tests**~~ (2026-05-06, on `feat/fermiviewer-measurement-workshop`) — Created 7 workshop model+facade pairs: Diffraction, EELS (160 lines, 7 sync points), EDS (131 lines, 3 sync points), Contrast, Annotation, Processing (3 sync points), Calibration (2 sync points). All wired into FermiViewer.m construction + closeAll + API struct. 67 new headless tests across 7 suites, all pass. **Callback body extraction (sub-task c for each) remains** — that's the step that actually removes hundreds of lines per workshop.
- ~~**Callback extraction batch 1**~~ (2026-05-06, commits `312f294` + `d2c4992`) — Extracted 14 functions from FermiViewer.m into `+fermiViewer/+eels/` (executeSVD, executeKramersKronig, executeELNES), `+fermiViewer/+diffraction/` (executeGPA, drawRingOverlay, executeCTF, executeDefectCount), `+fermiViewer/+processing/` (executeBackProject, showSurfacePlot, showRadialProfile, showAzimuthalIntegration, buildFigurePanel, parseColormap), `+fermiViewer/+measurement/` (widthAveragedProfile). FermiViewer.m: 14,048 → 13,735 lines (**-313 lines**). Size ratchet lowered to 13,780.
- ~~**Callback extraction batch 2**~~ (2026-05-06, commit `fdf82ca`) — Extracted 12 more callbacks + 3 shared helpers across all 8 workshop packages. FermiViewer.m: 13,735 → 13,188 lines (**-547 lines**). Size ratchet lowered to 13,215. Combined with batch 1: **-860 lines** total from callback extractions.
