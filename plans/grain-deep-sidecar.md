# Grain ID — Deep-Learning Sidecar (SAM)

Optional deep-learning grain segmentation for FermiViewer via a bundled,
pretrained **SAM** (Segment Anything) sidecar. Complements — does not replace —
the shipped pure-MATLAB grain pipeline (`plans/archive/grain-id.md`). The goal
is a **zero-setup** experience for external users (install the toolbox, click a
grain, get a mask) with **no Python/pip step**, achieved by bundling a frozen,
codesigned inference binary in the distributed `.mltbx`.

This document is the authoritative spec. It exists so a future session can pick
the work up cold without re-deriving the architecture or the decisions below.

**Status:** Paused
**Created:** 2026-05-25
**Updated:** 2026-05-25

> **Paused 2026-05-25** — deliberately deferred in favour of the shipped
> pure-MATLAB grain pipeline (`plans/archive/grain-id.md`), which already
> handles orientation-defined grains that SAM cannot see. This plan is kept
> fully specified for future pickup. **Revisit trigger:** the all-MATLAB path
> proves insufficient on real DM3/DM4 microstructure (low-contrast / noisy
> boundaries) — at which point start at Tier 1 #1–3 (prototype + the #3
> GO/NO-GO benchmark) before any packaging work.

---

## Decisions locked 2026-05-25

These were settled in discussion with the user. Do not silently revisit them;
if a constraint forces a change, note it here with a date.

| Decision | Choice | Why |
|---|---|---|
| Audience | **External users, zero setup** | Distribute to people who only have MATLAB — no Python/pip. |
| Model | **Pretrained SAM** (tiny variant: MobileSAM / EdgeSAM) | Zero-shot, no training set required; tiny variant is CPU-runnable. |
| Packaging effort | **Invest in "just works"** | Willing to build + sign + maintain per-platform binaries. |
| Delivery | **Bundle in the distributed `.mltbx`** (NOT in git source) | Offline / air-gapped friendly. Binaries via Git LFS / Release assets + CI assembly so git history + no-toolbox CI stay clean. |
| First interaction mode | **Interactive click-to-segment** | Natural fit for SAM's promptable design; fast (encoder once, decoder per click). |
| Runtime | **ONNX + onnxruntime**, frozen with PyInstaller | Avoids shipping a full PyTorch install; one self-contained exe. |

---

## Context

### How the pieces fit together

```
+fermiViewer/+grains/+deep/        MATLAB client (NEW)
   launchSidecar.m    — locate + start the bundled binary, health-check
   deepClient.m       — handshake: send image / click, receive mask
   isSidecarAvailable.m — graceful detection (absent → hide Deep mode)
sidecar/ (Python source, NOT shipped as source to users)
   grainseg_server.py — persistent server: MobileSAM-ONNX, holds embedding
   protocol.md        — the MATLAB↔sidecar wire format
bin/ (Git LFS / Release assets, assembled into .mltbx by CI — NOT committed)
   grainseg-win64.exe, grainseg-macos-arm64, grainseg-macos-x64, *.onnx
```

Reused unchanged from the completed pure-MATLAB feature
(`plans/archive/grain-id.md`):
`imaging.grains.grainStats` (masks → counts/boundaries/size dist),
`imaging.grains.labelOverlay`, `imaging.grains.exportGrainCSV`, and the
`GrainWorkshop` window (a "Deep (SAM)" mode is added alongside Automatic/Trained).

### Data / control flow (interactive mode)

```
GrainWorkshop "Deep (SAM)" mode
   │  on image load: deepClient sends the image ONCE
   ▼
grainseg_server (persistent)
   │  MobileSAM ENCODER runs once → caches the image embedding
   │  ◄── each user click sends a point prompt (x,y,label)
   │  ──► MASK DECODER returns that grain's mask (<100 ms)
   ▼
MATLAB: accumulate click-masks into a label map (resolve overlaps)
   ▼
imaging.grains.grainStats → counts / boundaries / size dist
imaging.grains.labelOverlay + exportGrainCSV  (existing back-end)
```

Performance hinge: SAM = heavy encoder + cheap decoder. Pay the encoder once
per image (server caches the embedding); every click is decoder-only. This is
why the sidecar is a **persistent server**, not a one-shot subprocess.

### Dependency map

- Items 1 + 2 (server + client) are the prototype; build together.
- **Item 3 (benchmark) is a GO/NO-GO gate** — if SAM doesn't beat the existing
  structure-tensor/forest path on real images, STOP. Do not start Tier 2.
- Item 4 (GrainWorkshop deep mode) needs 1 + 2.
- All of Tier 2 (5–9) is gated on item 3 = GO. Order: 5 → 6 → 7 → 8; 9 alongside.
- Tier 3 (10–13) is independent polish, after Tier 1 works.

### Integration invariants (must hold at all times)

- **Optional + graceful.** The pure-MATLAB grain pipeline stays the default and
  works with zero Python/binary. If the sidecar is absent/incompatible, the
  GrainWorkshop hides "Deep (SAM)" and falls back to softmax/forest — never
  crashes, never a scary error.
- **No-toolbox CI gate intact.** The sidecar is an external `.exe` invoked via
  `system()`/socket — NOT a MATLAB toolbox. `test_noToolboxDependency` must stay
  green. Never call a MATLAB add-on (Deep Learning Toolbox, etc.).
- **Binaries never in git source.** Raw binaries + `.onnx` weights live in Git
  LFS or as GitHub Release assets and are assembled into the `.mltbx` by a CI
  packaging step. Committing them to normal git history is forbidden (permanent
  bloat, choked clones).
- **Reuse the back-end.** Masks always flow through `imaging.grains.grainStats`
  / `labelOverlay` / `exportGrainCSV`. Do not fork a second measurement path.
- **Determinism where it matters.** Inference is deterministic for a given model
  + prompt; pin the onnxruntime + model version and record it in the sidecar
  handshake so results are reproducible across releases.

---

## Tier 1 — High Impact (prototype + prove worth + core capability)

1. **MobileSAM-ONNX prototype server** — `sidecar/grainseg_server.py`.
   - [ ] Export MobileSAM (or EdgeSAM) encoder + decoder to ONNX; pin versions.
   - [ ] Persistent server (stdin/stdout JSON or localhost socket): `load_image`
         (run encoder, cache embedding), `point_prompt` (decoder → mask), `ping`.
   - [ ] Document the wire protocol in `sidecar/protocol.md`.

2. **MATLAB deep client** — `+fermiViewer/+grains/+deep/`.
   - [ ] `launchSidecar` (start process, health-check, hold handle),
         `deepClient` (send image / click, receive mask as logical [H×W]),
         `isSidecarAvailable` (detect binary; never error if absent).
   - [ ] Temp-file or stdin image transfer; mask back as PNG/NPY or raw bytes.

3. **Accuracy benchmark (GO/NO-GO)** — SAM vs the existing path on real data.
   - [ ] Run on representative DM3/DM4 from `+test_datasets/Microscopy/`.
   - [ ] Compare SAM click-masks → `grainStats` against
         `segmentAuto`/`segmentTrained`. Record where SAM wins (intensity/texture
         grains) and where it loses (orientation-defined grains it cannot see).
   - [ ] **Decision recorded here before any Tier 2 work begins.**

4. **GrainWorkshop "Deep (SAM)" interactive mode** — click → mask → grains.
   - [ ] New mode in `openGrainWorkshop`; on image load, push to sidecar (encoder
         once). Click on axes → point prompt → mask → accumulate into label map.
   - [ ] Overlap resolution (later click wins / new grain id); undo last click.
   - [ ] Feed label map to existing `grainStats` → readout + overlay + CSV.

---

## Tier 2 — Medium Impact (zero-setup distribution)

5. **Freeze the sidecar** — PyInstaller → one self-contained binary per platform
   (bundles Python + onnxruntime + numpy + the `.onnx` weights). Targets:
   win64, macOS arm64, macOS x64.

6. **Sign + notarize** — macOS codesign + Apple notarization (needs Apple
   Developer account); Windows Authenticode signing. Required so a bundled,
   downloaded binary isn't quarantined by Gatekeeper / flagged by SmartScreen.

7. **CI build pipeline** — GitHub Actions on `windows-latest` + macOS runners;
   build + sign each binary; publish as Release assets (or push to Git LFS).
   Pin model + onnxruntime versions; emit a manifest (version, sha256).

8. **`.mltbx` packaging step** — CI assembles the platform binaries into the
   distributed toolbox (one fat universal `.mltbx`, ~0.5–1 GB). Toolbox locates
   the bundled binary at runtime; verify sha256 against the manifest.

9. **Graceful degradation + first-run UX** — sidecar present + compatible →
   enable Deep mode; absent/incompatible/wrong-platform → hide it with a one-line
   note. Never block startup. Covered by a headless test that stubs the client.

---

## Tier 3 — Nice-to-Have

10. **Automatic "segment everything" mode** — SAM grid-prompt over-segmentation →
    merge/filter into grains → one-shot counts (no clicking). Slower on CPU.

11. **Prompt refinement** — box prompts + positive/negative multi-click to fix
    a mask before committing it as a grain.

12. **Accelerated execution providers** — use CUDA / CoreML onnxruntime providers
    when present; CPU fallback otherwise. Detect at server start.

13. **Model upgrade path** — keep the wire protocol model-agnostic so EdgeSAM /
    SAM-HQ / FastSAM can be swapped behind the same client without MATLAB changes.

---

## Open risks / gotchas (read before estimating)

- **macOS notarization** is mandatory for "just works" — unsigned downloaded
  binaries are Gatekeeper-quarantined. Apple Developer account ($99/yr).
- **CPU speed / memory** — encoder is seconds on CPU for large images; fine for
  interactive (run once), painful for whole-image auto (Tier 3, item 10).
- **The scientific caveat** — SAM segments by *appearance*. Grains defined by
  *crystallographic orientation* (same brightness, different lattice) are exactly
  what SAM cannot see, but the existing structure-tensor path *can*. SAM
  complements; it does not replace. This is why item 3 is a hard gate.
- **`.mltbx` size** — bundling all platforms → ~0.5–1 GB download. Accepted for
  the offline/air-gapped priority. Revisit fetch-on-first-use if size hurts.
- **Dependency churn** — onnxruntime + OS + signing toolchains move; the CI
  pipeline (item 7) is ongoing maintenance, not one-and-done.

---

## Completed

*(none yet — Tier 1 not started)*
