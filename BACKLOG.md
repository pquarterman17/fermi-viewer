# Backlog — Open Work

Single-source dashboard aggregating every open top-level item from
`plans/*.md`. Regenerate whenever a plan changes.

**Last regenerated:** 2026-05-25 (grain-id plan fully shipped #1-#12 and archived → plans/archive/grain-id.md; back to MASTERPLAN #1/#2 open)

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

*(none open — grain-id plan complete + archived 2026-05-25.)*

---

## Plans dashboard

| Plan | Status | Open items | Notes |
|---|---|---|---|
| `plans/MASTERPLAN.md` | Active | 0 T1 / 2 T2 | #3 closed 2026-05-23 (5,257 lines, target met). #1 and #2 remain. |
| `plans/fermiviewer-workshop-conversion.md` | Active | — | Sub-task detail for fv MASTERPLAN #2 + #3 (8 workshops, callback extraction). |

---

## Source plan references

Items above descend from work that started in quantized_matlab:

- `plans/MASTERPLAN.md` fv #1 ← qm MASTERPLAN W5 #28 (Extract measurement subsystem)
- `plans/MASTERPLAN.md` fv #2 ← qm MASTERPLAN W5 #65 (Workshop pattern)
- `plans/MASTERPLAN.md` fv #3 ← qm MASTERPLAN W5 #69 (`<6,000` lines)
- `plans/fermiviewer-workshop-conversion.md` ← qm `plans/fermiviewer-workshop-conversion.md` (carried forward intact)
