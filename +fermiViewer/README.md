# +emViewer/ — Extracted FermiViewer Subsystems

Extracted package functions that implement FermiViewer's core logic. Each function
takes `(action, appData, ctx/fig/cb, varargin)` and returns updated `appData`.
The parent `FermiViewer.m` builds context structs and delegates here.

## Architecture Pattern

```
FermiViewer.m (orchestrator, ~6k lines)
    │
    ├── builds ctx/cb structs from closure variables
    │
    └── delegates to +emViewer/ package functions
         │
         └── returns modified appData back to closure
```

**Critical pattern — accept-and-return:** Because MATLAB structs are value-type,
extracted functions hold LOCAL copies of appData. Any callback that modifies
appData (e.g. `refreshDisplay`, `rebuildScaleBar`) must accept appData as input
and return it as output. Callers MUST capture the return:
`appData = cb.refreshDisplay(appData)` — never `cb.refreshDisplay()`.

For `displayImage.m`, bidirectional sync uses `pushAppData`/`pullAppData` via
the `closureReturn_` bridge in FermiViewer.m.

## Function Index

### UI Construction (panels and layout)

| Module | Description |
|--------|-------------|
| `buildToolbar.m` | Transform toolbar (8 icon buttons above image) |
| `buildContrastPanel.m` | Contrast sliders, transform dropdown, histogram controls |
| `buildTransformPanel.m` | Transform tab (rotate/flip/crop/zoom controls) |
| `buildEDSPanel.m` | EDS multi-channel composite panel |
| `buildEELSPanel.m` | EELS background subtraction and edge ID panel |
| `buildAnnotationsPanel.m` | Text annotation controls |
| `buildMeasurementPanel.m` | Measurement tools (profile, distance, angle, ROI) |
| `buildExportPanel.m` | Export and batch conversion controls |
| `buildSingleViewPanel.m` | Single-image view layout container |
| `buildMenuBar.m` | File/Edit/View/Tools menu bar |
| `buildPreferencesDialog.m` | Preferences dialog (theme, defaults) |

### Display Pipeline

| Module | Description |
|--------|-------------|
| `displayImage.m` | Master display: contrast stretch, colormap, imagesc, overlays |
| `displayHelpers.m` | refresh, resetZoom, zoomToDimensions, prepareBuffer |
| `displayStackFrame.m` | Navigate multi-frame stacks (prev/next/slider) |
| `prepareDisplayBuffer.m` | Allocate display buffer from filteredPixels |
| `clearDisplay.m` | Clear axes and reset display state |
| `drawHistogramOverlay.m` | Histogram panel overlays (handles, ramp, clipping) |
| `histogramOps.m` | Histogram interactions (drag handles, B/C mode) |
| `applyTheme.m` | Dark/Light theme application |

### Image Operations

| Module | Description |
|--------|-------------|
| `imageOps.m` | Image load/navigate/metadata dispatcher |
| `loadImages.m` | File loading, format detection, metadata extraction |
| `rotateFlip.m` | Rotate 90 CW/CCW, flip H/V |
| `processActions.m` | Processing menu: invert, sharpen, bin, morph, butterworth |
| `filterOps.m` | Gaussian, median, FFT, undo, live FFT, FFT mask |
| `contrastOps.m` | Contrast adjustments (auto, CLAHE, gamma, invert, transform) |

### Measurements & Interactions

| Module | Description |
|--------|-------------|
| `mouseOps.m` | Mouse event dispatcher (click, drag, scroll, hover) |
| `measInteract.m` | Measurement mouse interactions (start, drag, finish) |
| `measExecute.m` | Measurement execution (line profile, distance, angle, ROI) |
| `measurements.m` | Measurement utilities (statistics, export, formatting) |
| `rectROI.m` | Rectangle ROI drawing and statistics |

### Scale Bar

| Module | Description |
|--------|-------------|
| `scaleBarOps.m` | Scale bar create/update/toggle/style dispatcher |
| `applyScaleBarPos.m` | Position scale bar (9 anchor points) |
| `snapScaleBarPos.m` | Snap scale bar to nearest anchor on drag-end |

### Capture & Compare

| Module | Description |
|--------|-------------|
| `captureDispatch.m` | Capture mode dispatcher (zoom, crop, annotation clicks) |
| `compareImage.m` | Compare mode (side-by-side, overlay, difference) |
| `compareDispatch.m` | Compare mode mouse/keyboard dispatcher |

### Session & Navigation

| Module | Description |
|--------|-------------|
| `sessionOps.m` | Session save/load, recent files |
| `onKeyPress.m` | Keyboard shortcut dispatcher |

### Domain-Specific

| Module | Description |
|--------|-------------|
| `onDiffractionAction.m` | Diffraction indexing (spot detection, phase matching) |
| `onAnnotationAction.m` | Annotation CRUD (add, edit, delete, style) |
| `export.m` | Export dispatcher (image, crop, with-overlays, batch, clipboard) |
| `applyColorChannel.m` | EDS channel color assignment and blending |

### Utilities

| Module | Description |
|--------|-------------|
| `setToolsEnabled.m` | Enable/disable toolbar and panel controls |
| `computeActualZoomLimits.m` | Compute zoom limits respecting image bounds |
| `computePanLimits.m` | Compute pan limits for zoomed view |
| `zoomToDimensions.m` | Zoom to specific pixel dimensions |
| `shortcutsText.m` | Keyboard shortcuts help text |

## Dependencies

```
+emViewer/ ← depends on +imaging/, +parser/ (for import)
FermiViewer.m ← depends on +emViewer/, +imaging/, +parser/
```

## Adding New Features

1. Implement in a new `+emViewer/<feature>.m` file
2. Add a minimal dispatcher wrapper in `FermiViewer.m` (1-3 lines)
3. Never add nested functions to `FermiViewer.m` directly
4. Use the ctx/cb struct pattern for closure access
5. Ensure all state-mutating callbacks use accept-and-return
