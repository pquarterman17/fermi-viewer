# Backlog — Open Work

Single-source dashboard aggregating every open top-level item from
`plans/*.md`. Regenerate whenever a plan changes.

**Last regenerated:** 2026-05-25 (added gui-redesign #8 — Processing sub-tab/menu reorg follow-up; Variant A chrome shipped, layout/banner items deferred for visual review)

**How to read this file:**
- Items are grouped by **tier** (impact), then by **plan source**.
- Each line: `[ ] #<num>` plan → `title` — optional one-line context.
- Strike an item (`~~[ ] ...~~`) when it's done, and move the line to
  the plan's `## Completed` section in the same commit.
- If a plan's remaining items all ship, set its header `**Status:**
  Complete` and move the plan to `plans/archive/`.

---

## Tier 1 — High Impact (open)

*(none — FermiViewer.m `<6,000`-line goal closed 2026-05-23 at 5,257 lines;
grain-id deep sidecar paused 2026-05-25, see dashboard.)*

---

## Tier 2 — Medium Impact (open)

### MASTERPLAN — `plans/MASTERPLAN.md`
- [ ] **#1** W1 Decomposition → Extract FermiViewer measurement subsystem (~10 nested fns; `+fermiViewer/measurements.m` partial). Drives further ratchet headroom.
- [ ] **#2** W1 Decomposition → Apply workshop pattern to FermiViewer heavy features (measurements / EELS / EDS / annotations / contrast). 8 workshops + facades + sync shipped; callback body extraction (sub-task c) remains for each.

### GUI redesign (Variant A) — `plans/gui-redesign.md` (deferred — needs visual review)
- [ ] **#3** Status-bar readouts — zoom / scene / theme columns (capture-MODE readout shipped 2026-05-25).
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
| `plans/gui-redesign.md` | Active | 0 T1 / 2 T2 / 2 T3 | Variant A chrome. Shipped: palette GUI-wide, menu 9→6, command palette, workbar regroup, 4-tab Processing restyle. Status readouts + capture banner deferred for interactive dev; image-list renderer + Processing-tab reorg optional. |

---

## Source plan references

Items above descend from work that started in quantized_matlab:

- `plans/MASTERPLAN.md` fv #1 ← qm MASTERPLAN W5 #28 (Extract measurement subsystem)
- `plans/MASTERPLAN.md` fv #2 ← qm MASTERPLAN W5 #65 (Workshop pattern)
- `plans/MASTERPLAN.md` fv #3 ← qm MASTERPLAN W5 #69 (`<6,000` lines)
- `plans/fermiviewer-workshop-conversion.md` ← qm `plans/fermiviewer-workshop-conversion.md` (carried forward intact)
