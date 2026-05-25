# Backlog — Open Work

Single-source dashboard aggregating every open top-level item from
`plans/*.md`. Regenerate whenever a plan changes.

**Last regenerated:** 2026-05-25 (added `plans/grain-deep-sidecar.md` — optional SAM deep sidecar, 13 items, Tier 1 not started, #3 is a GO/NO-GO gate)

**How to read this file:**
- Items are grouped by **tier** (impact), then by **plan source**.
- Each line: `[ ] #<num>` plan → `title` — optional one-line context.
- Strike an item (`~~[ ] ...~~`) when it's done, and move the line to
  the plan's `## Completed` section in the same commit.
- If a plan's remaining items all ship, set its header `**Status:**
  Complete` and move the plan to `plans/archive/`.

---

## Tier 1 — High Impact (open)

### Grain ID deep sidecar — `plans/grain-deep-sidecar.md`
- [ ] **#1** MobileSAM-ONNX prototype server (`sidecar/grainseg_server.py`) — persistent encoder-once + decoder-per-click.
- [ ] **#2** MATLAB deep client (`+fermiViewer/+grains/+deep/`) — launch, handshake, graceful absent-detection.
- [ ] **#3** Accuracy benchmark (GO/NO-GO) — SAM vs structure-tensor/forest on real DM3/DM4 before any packaging.
- [ ] **#4** GrainWorkshop "Deep (SAM)" interactive click-to-segment mode (reuses grainStats back-end).

*(FermiViewer.m `<6,000`-line goal closed 2026-05-23 at 5,257 lines.)*

---

## Tier 2 — Medium Impact (open)

### MASTERPLAN — `plans/MASTERPLAN.md`
- [ ] **#1** W1 Decomposition → Extract FermiViewer measurement subsystem (~10 nested fns; `+fermiViewer/measurements.m` partial). Drives further ratchet headroom.
- [ ] **#2** W1 Decomposition → Apply workshop pattern to FermiViewer heavy features (measurements / EELS / EDS / annotations / contrast). 8 workshops + facades + sync shipped; callback body extraction (sub-task c) remains for each.

### Grain ID deep sidecar — `plans/grain-deep-sidecar.md` (all gated on #3 GO/NO-GO)
- [ ] **#5** Freeze sidecar (PyInstaller) → one self-contained binary per platform (win64 / macOS arm64 + x64).
- [ ] **#6** Sign + notarize (macOS Apple notarization, Windows Authenticode) so bundled binaries aren't quarantined.
- [ ] **#7** CI build pipeline — GitHub Actions per-platform build + sign → Release assets / Git LFS + manifest.
- [ ] **#8** `.mltbx` packaging — CI assembles binaries into one universal toolbox; runtime sha256 verify.
- [ ] **#9** Graceful degradation + first-run UX — present→enable Deep mode, absent→hide + fall back (headless-tested).

---

## Tier 3 — Nice-to-Have (open)

### Grain ID deep sidecar — `plans/grain-deep-sidecar.md` (gated on #3 GO/NO-GO)
- [ ] **#10** Automatic "segment everything" mode — SAM grid-prompt → merge/filter → one-shot counts.
- [ ] **#11** Prompt refinement — box + positive/negative multi-click mask editing.
- [ ] **#12** Accelerated execution providers (CUDA/CoreML) with CPU fallback.
- [ ] **#13** Model upgrade path — EdgeSAM / SAM-HQ / FastSAM behind the same protocol.

---

## Plans dashboard

| Plan | Status | Open items | Notes |
|---|---|---|---|
| `plans/MASTERPLAN.md` | Active | 0 T1 / 2 T2 | #3 closed 2026-05-23 (5,257 lines, target met). #1 and #2 remain. |
| `plans/fermiviewer-workshop-conversion.md` | Active | — | Sub-task detail for fv MASTERPLAN #2 + #3 (8 workshops, callback extraction). |
| `plans/grain-deep-sidecar.md` | Active | 4 T1 / 5 T2 / 4 T3 | Optional SAM deep sidecar (bundled, zero-setup, interactive). Not started — #3 is a GO/NO-GO benchmark gating all of Tier 2. |

---

## Source plan references

Items above descend from work that started in quantized_matlab:

- `plans/MASTERPLAN.md` fv #1 ← qm MASTERPLAN W5 #28 (Extract measurement subsystem)
- `plans/MASTERPLAN.md` fv #2 ← qm MASTERPLAN W5 #65 (Workshop pattern)
- `plans/MASTERPLAN.md` fv #3 ← qm MASTERPLAN W5 #69 (`<6,000` lines)
- `plans/fermiviewer-workshop-conversion.md` ← qm `plans/fermiviewer-workshop-conversion.md` (carried forward intact)
