# Backlog — Open Work

Single-source dashboard aggregating every open top-level item from
`plans/*.md`. Regenerate whenever a plan changes.

**Last regenerated:** 2026-05-25 (added `plans/gui-redesign.md` — Variant A chrome; Phase 1 + command palette shipped on feat/gui-redesign, layout/banner/right-panel items deferred for visual review)

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
- [ ] **#3** Status-bar readouts — add zoom / capture-mode / scene / theme columns to statusGL (existing readouts already adopt the new palette via applyTheme).
- [ ] **#4** Workbar hairline groups + path/scene chip (cosmetic regroup of buildToolbar).
- [ ] **#5** Capture-mode banner (grid-row approach) wired to appData.captureMode — needs real-mouse click-test.

---

## Tier 3 — Nice-to-Have (open)

### GUI redesign (Variant A) — `plans/gui-redesign.md` (deferred — large + unverifiable headless)
- [ ] **#6** Right-panel tabs → collapsible sections (buildToolsPanel); preserve all callbacks; update test_fv_gui_button_wiring (tab→section).
- [ ] **#7** Image-list custom cell renderer (thumbnails + accent rail).

---

## Plans dashboard

| Plan | Status | Open items | Notes |
|---|---|---|---|
| `plans/MASTERPLAN.md` | Active | 0 T1 / 2 T2 | #3 closed 2026-05-23 (5,257 lines, target met). #1 and #2 remain. |
| `plans/fermiviewer-workshop-conversion.md` | Active | — | Sub-task detail for fv MASTERPLAN #2 + #3 (8 workshops, callback extraction). |
| `plans/grain-deep-sidecar.md` | Paused | — | Optional SAM deep sidecar. Shelved 2026-05-25 in favour of the all-MATLAB path. Fully specified; revisit if the classical path proves insufficient on real data. |
| `plans/gui-redesign.md` | Active | 0 T1 / 3 T2 / 2 T3 | Variant A chrome redesign. Phase 1 (palette GUI-wide + menu 9→6) + command palette shipped on feat/gui-redesign 2026-05-25. Status bar/workbar/banner/right-panel deferred for visual review. |

---

## Source plan references

Items above descend from work that started in quantized_matlab:

- `plans/MASTERPLAN.md` fv #1 ← qm MASTERPLAN W5 #28 (Extract measurement subsystem)
- `plans/MASTERPLAN.md` fv #2 ← qm MASTERPLAN W5 #65 (Workshop pattern)
- `plans/MASTERPLAN.md` fv #3 ← qm MASTERPLAN W5 #69 (`<6,000` lines)
- `plans/fermiviewer-workshop-conversion.md` ← qm `plans/fermiviewer-workshop-conversion.md` (carried forward intact)
