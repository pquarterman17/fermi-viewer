# Backlog — Open Work

Single-source dashboard aggregating every open top-level item from
`plans/*.md`. Regenerate whenever a plan changes.

**Last regenerated:** 2026-08-01 (Tier 3 cleared — skip-guard ratchet, image-list renderer, Processing-tab reorg all shipped; then booked EM-parity T1 #8/#9 after the v0.49.0 backport left 12 of 15 new analysis functions unreachable from the GUI)

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
- [ ] **#8** Surface the v0.49.0 spectroscopy library in the GUI — 12 of the 15 EDS/EELS functions backported 2026-08-01 have **zero callers outside tests**; the library is done but no GUI user can reach it. Start with the EELS at% ± column (`openEELSQuantWorkshop.m:229` already has the sigma, just doesn't print it).
- [ ] **#9** Spectrum-image cubes can't reach the EDS entry points — `toKeV`/`Units` shipped but is a no-op: no parser attaches units to `edsData`, and DM4 SI `.energyUnit` lives under a metadata path the launch never reads. Needs EDS-vs-EELS signal typing first.

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

*(none open. MASTERPLAN W2 #5 skip-guard ratchet, gui-redesign #7
image-list renderer, and gui-redesign #8 Processing-tab reorg all
shipped 2026-08-01 — see dashboard.)*

---

## Plans dashboard

| Plan | Status | Open items | Notes |
|---|---|---|---|
| `plans/MASTERPLAN.md` | Active | 0 T1 / 1 T2 / 0 T3 | #3 closed 2026-05-23; #1 closed 2026-06-06 (measInteract + stackOps, 4,959 lines). #2 (per-workshop callback extraction) open in W1. W2 #5 (skip-guard ratchet) shipped 2026-08-01 → `test_skipGuards.m`. |
| `plans/fermiviewer-workshop-conversion.md` | Active | — | Sub-task detail for fv MASTERPLAN #2 + #3 (8 workshops, callback extraction). |
| `plans/grain-deep-sidecar.md` | Paused | — | Optional SAM deep sidecar. Shelved 2026-05-25 in favour of the all-MATLAB path. Fully specified; revisit if the classical path proves insufficient on real data. |
| `plans/gui-redesign.md` | Active | 0 T1 / 1 T2 / 0 T3 | Variant A chrome. Shipped: palette GUI-wide, menu 9→6, command palette, workbar regroup, 4-tab Processing restyle, status-bar zoom%/N-of-M readouts, #8 Processing-tab reorg + #7 image-list thumbnails/rail (2026-08-01). Only #5 capture banner remains — deferred for interactive dev. |
| `plans/em-feature-parity.md` | Active | 2 T1 / 2 T2 | Close DigitalMicrograph gaps. ✓ atom-column suite (PRs #19/#20), quant EELS (PRs #21/#22), calibration DB (2026-05-28) shipped. **New T1 (2026-08-01): #8 surface the v0.49.0 spectroscopy library in the GUI (12/15 functions have no GUI caller), #9 SI-cube unit plumbing.** Open T2: ring phase ID, HRTEM Wiener/ABSF. T3 (4D-STEM, tomography) recorded as eventual — not scheduled. |

---

## Source plan references

Items above descend from work that started in quantized_matlab:

- `plans/MASTERPLAN.md` fv #1 ← qm MASTERPLAN W5 #28 (Extract measurement subsystem)
- `plans/MASTERPLAN.md` fv #2 ← qm MASTERPLAN W5 #65 (Workshop pattern)
- `plans/MASTERPLAN.md` fv #3 ← qm MASTERPLAN W5 #69 (`<6,000` lines)
- `plans/fermiviewer-workshop-conversion.md` ← qm `plans/fermiviewer-workshop-conversion.md` (carried forward intact)
