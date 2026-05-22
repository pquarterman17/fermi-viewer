# MASTERPLAN — FermiViewer Work Backlog

Single backlog for FermiViewer-specific work. Inherits the live items
from quantized_matlab's MASTERPLAN W5 (the only workstream that survived
the 2026-05-21 split); the rest of qm's W1–W9 stay in qm.

**Status:** Active
**Created:** 2026-05-22
**Updated:** 2026-05-22

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

3. **Drive `FermiViewer.m` below 6,000 lines** — ratchet enforced by
   `tests/imaging/test_fermiViewerSize.m`. Current 6,082 / 330 nested
   fns. Need -1.4% line reduction. 8 workshop models + facades + sync
   shipped; callback body extraction remains.
   - [ ] Callback body extraction for MeasurementWorkshop (sub-task c)
   - [ ] Callback body extraction for EELSWorkshop
   - [ ] Callback body extraction for EDSWorkshop
   - [ ] Callback body extraction for AnnotationWorkshop
   - [ ] Callback body extraction for ContrastWorkshop
   - [ ] Callback body extraction for CalibrationWorkshop
   - [ ] Callback body extraction for DiffractionWorkshop
   - [ ] Callback body extraction for ProcessingWorkshop
   - [ ] Ratchet down `LINE_CEILING` after each batch lands

4. **Eliminate 6 doubly-nested fns in `FermiViewer.m`** — violates
   `matlab-gui-complexity` rule (no doubly-nested fns; use anonymous
   callbacks or extract to package). Deferred from the
   2026-05-22 structural cleanup pass because none of these have
   direct test coverage and they drive interactive UX
   (drag handles, dialog round-trip, ROI capture state) — extracting
   them blind risks breakage only humans catch. Do these as part of
   the relevant workshop callback extraction (#3) so the test
   coverage lands first.
   - [ ] `histDragMotion` / `histDragRelease` (lines 2414/2462) —
         lives inside contrast-slider drag, belongs in
         `+fermiViewer/+contrast/` callbacks
   - [ ] `applyThreshResult` (line 4817) — threshold dialog flow,
         belongs in `+fermiViewer/+processing/`
   - [ ] `beginROICapture` (line 4885) — ROI capture state machine,
         belongs in `+fermiViewer/+measurement/`
   - [ ] `gridJump` (line 4963) — grid-view nav, top-level UI
   - [ ] `applyPrefsFromDialog` (line 5176) — preferences round-trip,
         could move into `buildPreferencesDialog.m` as a local fn

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

(empty — will fill as #1–#3 land)
