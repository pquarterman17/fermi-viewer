# Backlog — Open Work

Single-source dashboard aggregating every open top-level item from
`plans/*.md`. Regenerate whenever a plan changes.

**Last regenerated:** 2026-08-01 (closed MASTERPLAN W2 #5 — skip-guard ratchet shipped as `tests/imaging/test_skipGuards.m`)

**How to read this file:**
- Items are grouped by **tier** (impact), then by **plan source**.
- Each line: `[ ] #<num>` plan → `title` — optional one-line context.
- Strike an item (`~~[ ] ...~~`) when it's done, and move the line to
  the plan's `## Completed` section in the same commit.
- If a plan's remaining items all ship, set its header `**Status:**
  Complete` and move the plan to `plans/archive/`.

---

## Tier 1 — High Impact (open)

*(none open. EM-parity #1 atom columns + #2 quantitative EELS both shipped
2026-05-26 — see dashboard. FermiViewer.m `<6,000`-line goal closed
2026-05-23 at 5,257 lines; grain-id deep sidecar paused 2026-05-25.)*

---

## Tier 2 — Medium Impact (open)

### MASTERPLAN — `plans/MASTERPLAN.md`
- [ ] **#2** W1 Decomposition → Apply workshop pattern to FermiViewer heavy features (measurements / EELS / EDS / annotations / contrast). 8 workshops + facades + sync shipped; callback body extraction (sub-task c) remains for SOME — EELS 3c verified already-done 2026-06-07 (side-effect of `195ec98`); verify the others against code before working. Processing batch (stackOps) + follow-up-after-assignment pattern landed 2026-06-06.

### EM feature parity — `plans/em-feature-parity.md`
- [ ] **#3** Ring / powder diffraction phase ID — radial-integrate → ring d-spacings → crystal-DB match (`indexRings.m`, extends `indexDiffraction` geometry). Dialog, not workshop.
- [ ] **#4** HRTEM denoising filters — adaptive Wiener (`wienerFilter.m`) + Average Background Subtraction Filter (`absf.m`) into the Filter tab. Small, high-use.

### GUI redesign (Variant A) — `plans/gui-redesign.md` (deferred — needs visual review)
- [ ] **#5** Capture-mode banner — over-axes amber banner. Needs dual axes-build-path edit (inline + buildSingleViewPanel) + capture hooks + real-mouse test → interactive dev.

---

## Tier 3 — Nice-to-Have (open)

### GUI redesign (Variant A) — `plans/gui-redesign.md`
- [ ] **#7** Image-list custom cell renderer (thumbnails + accent rail).

---

## Plans dashboard

| Plan | Status | Open items | Notes |
|---|---|---|---|
| `plans/MASTERPLAN.md` | Active | 0 T1 / 1 T2 / 0 T3 | #3 closed 2026-05-23; #1 closed 2026-06-06 (measInteract + stackOps, 4,959 lines). #2 (per-workshop callback extraction) open in W1. W2 #5 (skip-guard ratchet) shipped 2026-08-01 → `test_skipGuards.m`. |
| `plans/fermiviewer-workshop-conversion.md` | Active | — | Sub-task detail for fv MASTERPLAN #2 + #3 (8 workshops, callback extraction). |
| `plans/grain-deep-sidecar.md` | Paused | — | Optional SAM deep sidecar. Shelved 2026-05-25 in favour of the all-MATLAB path. Fully specified; revisit if the classical path proves insufficient on real data. |
| `plans/gui-redesign.md` | Active | 0 T1 / 1 T2 / 1 T3 | Variant A chrome. Shipped: palette GUI-wide, menu 9→6, command palette, workbar regroup, 4-tab Processing restyle, status-bar zoom%/N-of-M readouts, #8 Processing-tab reorg (2026-08-01, Surface tab + segmentation→Analysis menu). Capture banner deferred for interactive dev; image-list renderer optional. |
| `plans/em-feature-parity.md` | Active | 0 T1 / 2 T2 | Close DigitalMicrograph gaps. ✓ atom-column suite (PRs #19/#20), quant EELS (PRs #21/#22), calibration DB (2026-05-28) shipped. Open T2: ring phase ID, HRTEM Wiener/ABSF. T3 (4D-STEM, tomography) recorded as eventual — not scheduled. |

---

## Source plan references

Items above descend from work that started in quantized_matlab:

- `plans/MASTERPLAN.md` fv #1 ← qm MASTERPLAN W5 #28 (Extract measurement subsystem)
- `plans/MASTERPLAN.md` fv #2 ← qm MASTERPLAN W5 #65 (Workshop pattern)
- `plans/MASTERPLAN.md` fv #3 ← qm MASTERPLAN W5 #69 (`<6,000` lines)
- `plans/fermiviewer-workshop-conversion.md` ← qm `plans/fermiviewer-workshop-conversion.md` (carried forward intact)
