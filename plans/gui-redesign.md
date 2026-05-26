# GUI Redesign — Variant A (chrome layer)

Implements the assistant Design "Variant A" redesign (`design/2026-05-redesign/
handoff.html` + screenshots). Chrome/view-layer only — the parser→process→
display pipeline and the workshop pattern are untouched. Branch:
`feat/gui-redesign`. Safety rollback point: tag **v0.46.0**.

This plan tracks what shipped autonomously (fully tested) vs what is
**deferred for human visual review** — work whose correctness is fundamentally
visual or event-routing-based and therefore cannot be certified from MATLAB's
headless `-batch` mode (per the project lesson that headless tests bypass real
event routing; see memory `feedback_simulate_click_blind_spot`).

**Status:** Active
**Created:** 2026-05-25
**Updated:** 2026-05-25

---

## Context

### Why this split

A coding agent running headless cannot *see* the GUI. Two classes of change
are therefore not safely certifiable autonomously:
1. **Live-layout edits** to `FermiViewer.m` / `buildToolbar` / the axes panel —
   `test_layoutIntegrity` catches gross clipping but not "looks wrong."
2. **Capture-mode / event-routing** wiring — headless tests can't fire the real
   `image.ButtonDownFcn` → capture pipeline, the exact blind spot that has
   produced silent-swallow bugs before.

So: ship the value-substitution + standalone-widget work (verifiable); defer
the layout/event work to a session where the user can watch the screen.

### What propagates for free

`+fermiViewer/+display/applyTheme.m` already walks every themed widget and
pulls colours from `fermiViewer.chrome.uxTokens`. Because Phase 1 refreshed the
token *values* (preserving all token *names*), the new Variant A palette
propagates GUI-wide automatically — panels, status bar, list, headers — with no
per-widget edits. This is why Phase 1 delivers most of the visible restyle.

### Open questions — resolved 2026-05-25 (user approved)

1. Image-list thumbnails → **easy path** (keep uitable + StyleConfigurations).
2. Fonts → **OS-default monospace** (`Consolas`/`Menlo`), no bundled font.
3. Modal command palette → **yes** (shipped).
4. Capture-banner positioning → **grid-row approach** (not floating pixel panel).
5. Light-theme axes stays dark → **confirmed** (`tk.color.axesBg` dark in both).

---

## Tier 1 — High Impact

1. **Phase 1 — token refresh + menu 9→6** — see Completed.
2. **Command palette (⌘K) + captureModeTable** — see Completed.

---

## Tier 2 — Medium Impact (deferred — needs visual review)

3. **Status-bar readouts** — zoom / scene / theme readouts (capture-MODE
   readout shipped — see Completed). Add the remaining columns to `statusGL`.

5. **Capture-mode banner** — `+fermiViewer/+chrome/captureBanner.m` (new).
   - [ ] **Grid-row approach** (open Q4): a row at the top of the axes grid
         whose `RowHeight` toggles `{38,'1x'}` → `{0,'1x'}` on capture enter/exit.
         Robust vs the brittle pixel-positioned float.
   - [ ] Render label / step pill / hint / Esc from `captureModeTable`.
   - [ ] Hook `appData.captureMode` set/clear + `appData.captureModeStep` bump in
         the mouse-down handler; mirror in the status-bar mode readout.
   - **Why deferred:** correctness is event-routing — must be click-tested with
     a real mouse, not headless.

---

## Tier 3 — Nice-to-Have

7. **Image-list custom cell renderer** — thumbnails + accent rail (open Q1 easy
   path keeps uitable; defer the custom-panel renderer).

---

## Completed

- ~~**#1 Phase 1 — token refresh + menu 9→6**~~ (2026-05-25) —
  `uxTokens.m` dark+light refreshed to the Variant A neutral-cool palette,
  mapped onto the EXISTING token names (no call site broke) + new tokens
  (border/borderSoft, accentBg, capture/captureBg, axesBg, bgHover/bgActive).
  Propagates GUI-wide via `applyTheme`. `buttonPalette.m` neutral tool aligned.
  `buildMenuBar.m` 9→6 (Filter→Image, Spectroscopy+stack/macro→Analysis,
  scale-bar/annotation/publication→Image; dropped 3 workbar-duplicate zoom
  items). fast 18/18, fvgui 23/23, ratchet 3/3, checkcode clean. Commit e217433.
- ~~**devReload package-flush fix**~~ (2026-05-25) — `devReload` now runs
  `clear functions` (+rehash), not just `clear FermiViewer`, so edits to
  `+fermiViewer/*` package functions actually appear on reload. This was the
  reason the redesign looked absent in the running session. Commit 509c0ae.
- ~~**#3 (partial) Status-bar capture-mode readout**~~ (2026-05-25) — amber
  ●  MODE readout in the status bar from `captureModeTable`; refreshes on the
  mouse-op path. Commit 201a755. Zoom/scene/theme readouts remain.
- ~~**#6 Right panel → collapsible sections**~~ (2026-05-25, **REVERTED 2026-05-25**) —
  shipped then reverted on user feedback: the nested collapsible sub-sections
  under Processing were a step back; the 4-tab selector (Transform/Filter/
  FFT & Analysis/Surface & Stack) was restored (PR #12). The button-colour
  normalisation was kept. Original entry below for history.
- ~~**#6 (original) Right panel → collapsible sections**~~ (2026-05-25) —
  `buildTransformPanel.m` 4-tab uitabgroup → scrollable column of 4 collapsible
  sections; container-only swap, all buttons/callbacks/`processTabGrids`
  preserved. `test_fv_gui_button_wiring` rewritten (tab-ancestry → section
  headers). fvgui 24/24 (67/67 controls wired, all enable after load), smoke
  14/14, ratchet 3/3. Commit 4263113. (Workshop strip + Contrast/Measurements/
  Annotations sections beyond the 4 former tabs left as future refinement.)
- ~~**#4 Workbar hairline groups + accent Open**~~ (2026-05-25) —
  `buildToolbar.m` regrouped into 5 hairline-separated groups; Open button →
  accent blue; uses the reserved uxTokens param. fvgui 24/24 (layout-integrity
  validated the 17-col grid), ratchet 3/3. Commit e1c10cf. (Path/scene chip
  dropped — the OS title bar can't be replaced in uifigure; handoff gap #2.)
- ~~**#2 Command palette (⌘K) + captureModeTable**~~ (2026-05-25) —
  `buildCommandPalette.m` modal search-and-run over a curated action registry
  derived from `menuCb_` (single source of truth); `captureModeTable.m`
  single-source mode labels/steps; `FermiViewer.m onKeyPress` opens it on ⌘K
  (inline, lazy — no new nested fn, ratchet green). `tests/gui/test_commandPalette.m`.
  fast 18/18, fvgui 24/24. Commit 079aef7.
