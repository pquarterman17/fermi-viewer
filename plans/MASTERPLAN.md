# MASTERPLAN — FermiViewer Work Backlog

Single backlog for FermiViewer-specific work. Inherits the live items
from quantized_matlab's MASTERPLAN W5 (the only workstream that survived
the 2026-05-21 split); the rest of qm's W1–W9 stay in qm.

**Status:** Active
**Created:** 2026-05-22
**Updated:** 2026-05-23 (#3 `<6,000-line` goal closed at 5,257 lines / 287 nested fns; ratchet ceilings now 5,260 / 286 / 0)

---

## Context

### How the pieces fit together

FermiViewer's only active backlog as of the split is the decomposition
work that drives `FermiViewer.m` toward the 6,000-line ratchet target.
That work has two layers:

1. **Workshop conversions** — replicate the BosonPlotter playbook (state
   handle class + functional view + hook API) across the heavy features
   (measurements, EELS, EDS, annotation, contrast, calibration,
   diffraction, processing). 8 workshop models + facades + sync are
   shipped; only the callback body extraction remains for each.
2. **Callback extraction** — move dispatcher bodies from `FermiViewer.m`
   into `+fermiViewer/+<feature>/` callbacks files. This is the part
   that actually reclaims lines (the workshop models bought parser-slot
   headroom but barely changed line count).

Detailed sub-tasks live in `plans/fermiviewer-workshop-conversion.md`,
which was migrated intact from qm.

### Dependency map

```
#1 measurement subsystem
   └─ feeds #2 workshop pattern
            └─ feeds #3 <6,000-line goal
```

#3 is the ratchet target; #1 and #2 are the means.

### Migration history

Items #1/#2/#3 are descendants of qm MASTERPLAN W5 #28/#65/#69
respectively. The line-count starting point at fork was 6,082 lines /
330 nested fns / `<6,000` target. The qm side stops tracking these once
W4 of the split (qm cleanup) lands.

---

## W1 — Decomposition

### Tier 1 — High Impact

*(none open — #3 closed 2026-05-23.)*

~~**#3 Drive `FermiViewer.m` below 6,000 lines**~~ (2026-05-23) —
   MET. Final: **5,257 lines / 287 top-level nested fns / 0 doubly-
   nested.** Ratchet ceilings: 5,260 / 286 / 0. Achieved via the
   2026-05-22 first decomposition pass (5,892 → 5,203) plus follow-on
   callback extractions (`attachContextMenu`, `startHistDrag`,
   `endpointDrag`, `updateStatusBar`, `panelResize`,
   `promptAndLoadRaw`, `sessionSave`, `templateMatch`, `stitchImages`,
   `noiseEstimate`, `dragModeToggle`, `runBatchMeasurement`,
   `promptCalibrateBar`, `buildBigUI` UI-cache helper hoist, full
   doubly-nested elimination). Per-workshop callback-body extraction
   continues under #2 but is no longer gated on the line-count goal.

~~**#4 Eliminate 6 doubly-nested fns in `FermiViewer.m`**~~
   (2026-05-22) — DONE. All 6 cleared:
   - `histDragMotion` + `histDragRelease` moved into
     `+contrast/startHistDrag.m` (live as child-nested fns inside the
     package fn, no longer FermiViewer's parser budget).
   - `applyThreshResult`, `beginROICapture`, `gridJump`,
     `applyPrefsFromDialog` promoted from 8-space-indent to 4-space-
     indent top-level nested fns (closure semantics unchanged;
     parent-fn relationship changed). Doubly-nested ceiling now 0.

### Tier 2 — Medium Impact

1. **Extract FermiViewer measurement subsystem** — ~10 nested fns;
   partial via `+fermiViewer/measurements.m`. Drives #3. Original source:
   qm `plans/fermiviewer-decomposition-2026-04-16.md` #7. Promoted T3→T2
   on 2026-05-01 to drive the `<6k` goal.
   - [ ] Identify remaining 10 measurement-related nested fns in
         FermiViewer.m
   - [ ] Move each into `+fermiViewer/+measurement/` with the workshop
         hook contract
   - [ ] Cross-link to MeasurementWorkshop callback extraction (W1 #3)

2. **Apply workshop pattern to FermiViewer heavy features** — detailed in
   `plans/fermiviewer-workshop-conversion.md`. 8 workshop models +
   facades + sync shipped; the remaining work is callback body extraction
   per workshop. Drives #3.
   - [ ] See sub-tasks under #3 (callback extraction batches)
   - [ ] Cross-check the workshop test suite stays green after each batch

---

## Completed

- ~~Full first decomposition pass~~ (2026-05-22) — comprehensive
  callback-extraction + architectural ui-cache + doubly-nested
  elimination session. **FermiViewer.m: 5,892 → 5,203 lines
  (-689, -11.7%). Doubly-nested fns: 6 → 0.** Test suite green
  throughout (fv 16/16, fvgui 17/17).

  19 callback bodies extracted across 11 subpackages:
  - +annotation/attachContextMenu
  - +contrast/startHistDrag (includes 2 child-nested fns formerly
    doubly-nested in FermiViewer)
  - +measurement/endpointDrag
  - +visualization/runColorOverlay
  - +analysis/runParticleCount + runNoiseEstimate + runBatchMeasurement
  - +eds/runQuantifyCL
  - +calibration/promptSetPixelSize + autoDetectAndCalibrate +
    promptCalibrateBar
  - +display/updateStatusBar
  - +interaction/panelResize + dragModeToggle
  - +session/promptAndLoadRaw + sessionSave
  - +processing/runTemplateMatch + runStitchImages

  Architectural fix: **`buildBigUI()` nested helper** consolidates
  ~200 unique UI handles into a single union struct used by the 4
  heaviest delegates (displayImage, clearDisplay, setToolsEnabled,
  applyTheme). The 4 delegates collapsed from 275 lines of
  struct-construction to 4 tiny 3-line bodies. One MATLAB gotcha
  caught: struct('field', cellValue) creates a non-scalar struct —
  wrap with extra braces (`{cellValue}`) for scalar.

  Doubly-nested cleanup: `histDragMotion`/`histDragRelease` lifted
  via startHistDrag extraction; `applyThreshResult`/`beginROICapture`/
  `gridJump`/`applyPrefsFromDialog` promoted to top-level nested.

  Reverted: `onStackMIP` extraction. Discovered the
  callback-into-closure hazard — extracting a fn that mutates appData
  AND calls back into a closure callback (`@onContrastOp`) breaks
  the accept-and-return ordering. See memory
  `feedback_callback_closure_hazard`. The same pattern blocks
  `applyCalibration`, `onAlignStack`, `onCLAHE`, `onImageMath`,
  several other candidates until the project shifts callbacks to
  accept-and-return signatures (would require touching every
  callback's signature project-wide).

  Ratchet test (`test_fermiViewerSize`): LINE_CEILING 5,892 → 5,220;
  DOUBLY_NESTED_CEILING 6 → 0; NESTED_FN_CEILING 280 → 280 (1
  helper added (buildBigUI), 4 doubly→top-level → net 280 still).
