# Backlog — Open Work

Single-source dashboard aggregating every open top-level item from
`plans/*.md`. Regenerate whenever a plan changes.

**Last regenerated:** 2026-05-25 (grain-id Tier-1 + Tier-2 + GrainWorkshop GUI #10 shipped; only optional Tier-3 #11 RF + #12 SLIC remain)

**How to read this file:**
- Items are grouped by **tier** (impact), then by **plan source**.
- Each line: `[ ] #<num>` plan → `title` — optional one-line context.
- Strike an item (`~~[ ] ...~~`) when it's done, and move the line to
  the plan's `## Completed` section in the same commit.
- If a plan's remaining items all ship, set its header `**Status:**
  Complete` and move the plan to `plans/archive/`.

---

## Tier 1 — High Impact (open)

*(none — #3 `<6,000-line` goal closed 2026-05-23 at 5,257 lines.)*

---

## Tier 2 — Medium Impact (open)

### MASTERPLAN — `plans/MASTERPLAN.md`
- [ ] **#1** W1 Decomposition → Extract FermiViewer measurement subsystem (~10 nested fns; `+fermiViewer/measurements.m` partial). Drives further ratchet headroom.
- [ ] **#2** W1 Decomposition → Apply workshop pattern to FermiViewer heavy features (measurements / EELS / EDS / annotations / contrast). 8 workshops + facades + sync shipped; callback body extraction (sub-task c) remains for each.

---

## Tier 3 — Nice-to-Have (open)

### Grain ID — `plans/grain-id.md`
- [ ] **#11** Random-forest upgrade — swap softmax for hand-rolled RF if logistic regression underfits orientation features.
- [ ] **#12** SLIC superpixel pre-segmentation — cluster superpixels for speed + boundary adherence on large images.

---

## Plans dashboard

| Plan | Status | Open items | Notes |
|---|---|---|---|
| `plans/MASTERPLAN.md` | Active | 0 T1 / 2 T2 | #3 closed 2026-05-23 (5,257 lines, target met). #1 and #2 remain. |
| `plans/fermiviewer-workshop-conversion.md` | Active | — | Sub-task detail for fv MASTERPLAN #2 + #3 (8 workshops, callback extraction). |
| `plans/grain-id.md` | Active | 0 T1 / 0 T2 / 2 T3 | Tier-1 + Tier-2 + GrainWorkshop GUI (#10) shipped 2026-05-25. Only optional RF (#11) + SLIC (#12) remain. |

---

## Source plan references

Items above descend from work that started in quantized_matlab:

- `plans/MASTERPLAN.md` fv #1 ← qm MASTERPLAN W5 #28 (Extract measurement subsystem)
- `plans/MASTERPLAN.md` fv #2 ← qm MASTERPLAN W5 #65 (Workshop pattern)
- `plans/MASTERPLAN.md` fv #3 ← qm MASTERPLAN W5 #69 (`<6,000` lines)
- `plans/fermiviewer-workshop-conversion.md` ← qm `plans/fermiviewer-workshop-conversion.md` (carried forward intact)
