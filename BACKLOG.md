# Backlog — Open Work

Single-source dashboard aggregating every open top-level item from
`plans/*.md`. Regenerate whenever a plan changes.

**Last regenerated:** 2026-05-26 (added `plans/em-feature-parity.md` — atom columns, EELS quant, ring-ID, HRTEM denoise, calibration DB; gui-redesign #3 status readouts shipped)

**How to read this file:**
- Items are grouped by **tier** (impact), then by **plan source**.
- Each line: `[ ] #<num>` plan → `title` — optional one-line context.
- Strike an item (`~~[ ] ...~~`) when it's done, and move the line to
  the plan's `## Completed` section in the same commit.
- If a plan's remaining items all ship, set its header `**Status:**
  Complete` and move the plan to `plans/archive/`.

---

## Tier 1 — High Impact (open)

### EM feature parity — `plans/em-feature-parity.md`
- [ ] **#1** Atom-column analysis suite — detect → 2D-Gaussian sub-pixel fit → peak-pair-analysis strain → sublattice (`+imaging/+atoms/` + `+fermiViewer/+atomcolumns/` workshop). Headline modern-STEM gap vs DigitalMicrograph; real-space complement to fringe-GPA.
- [ ] **#2** Quantitative EELS composition (at.%) — Egerton hydrogenic cross-sections (`eelsCrossSection.m`) + `eelsQuantify.m`, folded into the existing EELS workshop. Capstone on the existing background/edges chain.

*(FermiViewer.m `<6,000`-line goal closed 2026-05-23 at 5,257 lines;
grain-id deep sidecar paused 2026-05-25, see dashboard.)*

---

## Tier 2 — Medium Impact (open)

### MASTERPLAN — `plans/MASTERPLAN.md`
- [ ] **#1** W1 Decomposition → Extract FermiViewer measurement subsystem (~10 nested fns; `+fermiViewer/measurements.m` partial). Drives further ratchet headroom.
- [ ] **#2** W1 Decomposition → Apply workshop pattern to FermiViewer heavy features (measurements / EELS / EDS / annotations / contrast). 8 workshops + facades + sync shipped; callback body extraction (sub-task c) remains for each.

### EM feature parity — `plans/em-feature-parity.md`
- [ ] **#3** Ring / powder diffraction phase ID — radial-integrate → ring d-spacings → crystal-DB match (`indexRings.m`, extends `indexDiffraction` geometry). Dialog, not workshop.
- [ ] **#4** HRTEM denoising filters — adaptive Wiener (`wienerFilter.m`) + Average Background Subtraction Filter (`absf.m`) into the Filter tab. Small, high-use.
- [ ] **#5** Calibration database — persistent mag/camera-length → pixel-size store (`+fermiViewer/+calibration/calibrationStore.m`), vs current per-image-only.

### GUI redesign (Variant A) — `plans/gui-redesign.md` (deferred — needs visual review)
- [ ] **#5** Capture-mode banner — over-axes amber banner. Needs dual axes-build-path edit (inline + buildSingleViewPanel) + capture hooks + real-mouse test → interactive dev.

---

## Tier 3 — Nice-to-Have (open)

### GUI redesign (Variant A) — `plans/gui-redesign.md`
- [ ] **#7** Image-list custom cell renderer (thumbnails + accent rail).
- [ ] **#8** Reorganize Processing sub-tabs + menus by intent. The 4th tab ("Stack") is a grab-bag of 3 themes (surface topography / segmentation / multi-image stacking); decide a coherent split (relocate segmentation to Analysis menu, or rename). Panel width fits ~4 tabs only — see PRs #15–17. No functionality is missing; this is purely organization.

---

## Plans dashboard

| Plan | Status | Open items | Notes |
|---|---|---|---|
| `plans/MASTERPLAN.md` | Active | 0 T1 / 2 T2 | #3 closed 2026-05-23 (5,257 lines, target met). #1 and #2 remain. |
| `plans/fermiviewer-workshop-conversion.md` | Active | — | Sub-task detail for fv MASTERPLAN #2 + #3 (8 workshops, callback extraction). |
| `plans/grain-deep-sidecar.md` | Paused | — | Optional SAM deep sidecar. Shelved 2026-05-25 in favour of the all-MATLAB path. Fully specified; revisit if the classical path proves insufficient on real data. |
| `plans/gui-redesign.md` | Active | 0 T1 / 1 T2 / 2 T3 | Variant A chrome. Shipped: palette GUI-wide, menu 9→6, command palette, workbar regroup, 4-tab Processing restyle, status-bar zoom%/N-of-M readouts. Capture banner deferred for interactive dev; image-list renderer + Processing-tab reorg optional. |
| `plans/em-feature-parity.md` | Active | 2 T1 / 3 T2 | Close DigitalMicrograph gaps. T1: atom-column suite (detect/fit/PPA strain), quant EELS (hydrogenic σ). T2: ring phase ID, HRTEM Wiener/ABSF, calibration DB. T3 (4D-STEM, tomography) recorded as eventual — not scheduled. |

---

## Source plan references

Items above descend from work that started in quantized_matlab:

- `plans/MASTERPLAN.md` fv #1 ← qm MASTERPLAN W5 #28 (Extract measurement subsystem)
- `plans/MASTERPLAN.md` fv #2 ← qm MASTERPLAN W5 #65 (Workshop pattern)
- `plans/MASTERPLAN.md` fv #3 ← qm MASTERPLAN W5 #69 (`<6,000` lines)
- `plans/fermiviewer-workshop-conversion.md` ← qm `plans/fermiviewer-workshop-conversion.md` (carried forward intact)
