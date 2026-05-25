# Grain Identification (ML-assisted)

Pure-MATLAB grain + grain-boundary identification for EM images. Adds an
automatic (unsupervised) mode and an interactive trainable (scribble →
classifier) mode, both built on a shared feature stack and a shared
region-measurement core. Outputs grain counts, boundary counts + length,
calibrated size distribution, and a labeled-map overlay. No external
toolboxes — all "ML" is hand-rolled in base MATLAB so it ships in the
`.mltbx` and passes `test_noToolboxDependency`.

**Status:** Active
**Created:** 2026-05-25
**Updated:** 2026-05-25

---

## Context

### How the pieces fit together

Pure algorithms live in `+imaging/` (matching the `executeWatershed` →
`+imaging/watershed.m` precedent); GUI lives in `+fermiViewer/`.

- `+imaging/structureTensor.m` — flat primitive (closed-form 2×2 eigen-
  analysis → orientation angle + coherence). Sits next to
  `geometricPhaseAnalysis`. This is the orientation feature that lets us
  separate same-brightness grains that thresholding cannot.
- `+imaging/regionStats.m` — region-measurement core EXTRACTED from
  `particleAnalysis` (area / centroid / equivDiameter / calibrated). One
  measurement code path; `particleAnalysis` and `grainStats` both call it.
- `+imaging/+ml/` — reusable learning family: `kmeansLite`,
  `softmaxClassifier`, `standardizeFeatures`. Deliberately grain-agnostic
  so future EDS phase clustering / diffraction classification / defect
  detection can reuse it.
- `+imaging/+grains/` — grain-specific orchestration: `extractGrainFeatures`
  (assembles the feature stack), `segmentAuto` (unsupervised), `segmentTrained`
  (classifier apply), `grainStats` (numbers), `labelOverlay` (render).
- `+fermiViewer/+grains/` — GrainWorkshop (model + view + callbacks),
  Phase 4. Holds the feature cache and transient training scribbles.

### Data / control flow

```
image ─► extractGrainFeatures ─► feature stack [H×W×F]
                                      │
              ┌───────────────────────┴───────────────────────┐
        segmentAuto                                      segmentTrained
   (standardize → kmeansLite                        (scribbles → softmaxClassifier
    → CC per cluster → watershed)                     → per-pixel argmax)
              └───────────────────────┬───────────────────────┘
                                 label map [H×W]
                                      │
                                  grainStats ─► counts, boundary net + length,
                                      │          size distribution (via regionStats)
                                  labelOverlay ─► colored map + boundary overlay ─► GUI / CSV
```

### Feature stack (`extractGrainFeatures`)

Intensity + local mean/std (texture) + gradient magnitude (boundary ridges)
+ structure-tensor coherence & orientation (lattice) + local entropy, each at
2–3 Gaussian scales. Covers intensity-contrast AND orientation/texture grains
(user reported both occur across samples).

### Dependency map

- `regionStats` extraction (item 1) gates `grainStats` (item 6) and the
  `particleAnalysis` refactor — do it first, existing `particleAnalysis`
  tests are the safety net.
- `structureTensor` (2) + `+ml` kernels (3) are independent, parallelizable.
- `extractGrainFeatures` (4) needs `structureTensor`.
- `segmentAuto` (5) needs `+ml` + features. `grainStats` (6) needs
  `regionStats`. Items 5 + 6 = first numbers out → headless Phase 1/2.
- `segmentTrained` (7) + scribble capture (8) = trainable mode.
- GrainWorkshop GUI (9) touches everything — do last; plan the
  `FermiViewer.m` ratchet offset before wiring the dispatcher.

### ML-specific invariants (decided 2026-05-25)

- **Determinism:** every stochastic fn (`kmeansLite`, future RF) takes a
  `Seed` option, fixed default — repeatable grain counts + stable CI.
- **Feature cache:** lives in the GrainWorkshop model, keyed to image
  identity, invalidated on image change. NOT in the
  rawPixels→filtered→display pipeline.
- **Scribbles:** transient workshop-model state, rendered as a
  `HandleVisibility=off` overlay, cleared on workshop close. NOT in
  `appData.overlays` (sessions don't persist overlays; avoids
  clearImages/session field drift).
- **Test group:** new `grains` group registered in `runAllTests` AND every
  new test file registered, same commit — `test_repoIntegrity` enforces it.

---

## Tier 1 — High Impact

*(all shipped 2026-05-25 — headless automatic-mode pipeline complete and
tested. See Completed.)*

---

## Tier 2 — Medium Impact

*(all shipped 2026-05-25 — trainable mode + overlay/CSV complete. See Completed.)*

---

## Tier 3 — Nice-to-Have

10. **GrainWorkshop GUI** — wire both modes into FermiViewer.
    - [ ] `GrainWorkshopModel` (feature cache + scribbles + trained model + results)
    - [ ] `buildGrainPanel` + callbacks on `(model, hook)`
    - [ ] FermiViewer dispatcher + ratchet-offset extraction (same branch)

11. **Random-forest upgrade** — swap softmax for a hand-rolled RF if
    logistic regression underfits orientation features.

12. **SLIC superpixel pre-segmentation** — cluster superpixels instead of
    pixels for large images (speed + boundary adherence).

---

## Completed

- ~~**#1 Extract `imaging.regionStats`**~~ (2026-05-25) — measurement core
  pulled out of `particleAnalysis`; both now share one code path.
  `test_particle_clahe` 11/11 green (behavior-preserving).
- ~~**#2 `imaging.structureTensor`**~~ (2026-05-25) — closed-form 2×2 eigen
  orientation + coherence. Recovers known grating angles within 5°.
- ~~**#3 `+imaging/+ml` kernels**~~ (2026-05-25) — `kmeansLite` (k-means++,
  private `RandStream` seed → deterministic) + `standardizeFeatures`
  (z-score + constant-column guard).
- ~~**#4 `grains.extractGrainFeatures`**~~ (2026-05-25) — multi-scale stack:
  intensity/local mean+std/gradient/coherence + coherence-weighted
  (cos2θ,sin2θ) orientation. Entropy deferred (not needed for v1).
- ~~**#5 `grains.segmentAuto`**~~ (2026-05-25) — standardize → kmeansLite →
  CC-per-cluster → label map. `Features` input for cache reuse. Splits a
  two-orientation synthetic into the correct 2 grains.
- ~~**#6 `grains.grainStats` + tests + group**~~ (2026-05-25) — counts,
  boundary network (segments + length), size distribution via `regionStats`.
  New `grains` test group registered; `test_grains` 8/8; repo-integrity +
  no-toolbox gates green.
- ~~**#7 `imaging.ml.softmaxTrain` / `softmaxPredict`**~~ (2026-05-25) —
  multinomial logistic regression, batch GD + L2, standardization baked into
  the model, zero-init → deterministic. Reusable kernel.
- ~~**#8 `grains.trainFromScribbles` + `segmentTrained`**~~ (2026-05-25) —
  interactive trainable mode. Model carries its feature config so
  train-on-A/apply-to-B is feature-consistent. `BoundaryClass` excludes a
  painted boundary class from grains. `test_grains` 12/12 (incl. A→B
  generalization).
- ~~**#9 `grains.labelOverlay` + `exportGrainCSV`**~~ (2026-05-25) —
  deterministic HSV per-grain colouring blended over the base image with the
  boundary network drawn; CSV writer emits per-grain rows with calibrated
  columns (returns data+header for headless use). `test_grains` 12→14.
