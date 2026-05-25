# GUI Redesign — Variant A (chrome layer)

Implements the Claude Design "Variant A" redesign (`design/2026-05-redesign/
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

3. **Status-bar readouts** — add zoom / capture-mode / scene / theme readouts
   to the existing `statusGL` (`FermiViewer.m:1155`, currently `[1 5]`).
   - [ ] Expand `[1 5]` → `[1 9]`, keeping `ColumnWidth` element count == NumCols
         (the silent-clipping hazard — audit every `statusGL` writer).
   - [ ] Mode readout reads `fermiViewer.captureModeTable` (already built),
         coloured `tk.color.capture`.
   - [ ] Theme + colour the new labels in `+display/applyTheme.m`.
   - Note: existing 4 readouts already adopt the new palette via applyTheme;
     this item is ONLY the new columns.

4. **Workbar hairline groups + path/scene chip** — `+fermiViewer/buildToolbar.m`.
   - [ ] Regroup the 13 widgets into 5 visual groups via 1-px borderless
         `uipanel` separators (`tk.color.borderSoft`).
   - [ ] Trailing path + scene chip (custom strip — the OS title bar can't be
         replaced in uifigure; see handoff gap #2).

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

## Tier 3 — Nice-to-Have (deferred — large + unverifiable)

6. **Right-panel tabs → collapsible sections** — replace `buildTransformPanel.m`
   (4-tab uitabgroup: Transform / Filter / FFT & Analysis / Surface & Stack)
   with `buildToolsPanel.m` (scrollable collapsible sections).
   - [ ] Preserve EVERY wired callback (contrast sliders, capture-mode tiles,
         filter buttons, annotations, export) — the bug-prone part.
   - [ ] **Update `tests/imaging/test_fv_gui_button_wiring.m`** — it asserts
         buttons are parented to the 4 named TABS; it must move to section
         parentage or it fails. This is a structural test break, not optional.
   - [ ] Keep the workshop strip (Image/EELS/EDS/Diff) mounting intact.
   - **Why deferred:** ~620 lines of wired-callback surgery + a structural test
     rewrite, and the result is visual — highest blind risk in the whole redesign.

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
- ~~**#2 Command palette (⌘K) + captureModeTable**~~ (2026-05-25) —
  `buildCommandPalette.m` modal search-and-run over a curated action registry
  derived from `menuCb_` (single source of truth); `captureModeTable.m`
  single-source mode labels/steps; `FermiViewer.m onKeyPress` opens it on ⌘K
  (inline, lazy — no new nested fn, ratchet green). `tests/gui/test_commandPalette.m`.
  fast 18/18, fvgui 24/24. Commit 079aef7.
