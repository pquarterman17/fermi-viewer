# FermiViewer — Detailed Feature Reference

> Extracted from CLAUDE.md. For core conventions and quick-start workflows, see the main [CLAUDE.md](../CLAUDE.md).

## Usage

```matlab
% Launch the GUI interactively
FermiViewer

% Programmatic usage (e.g. in scripts or tests)
api = FermiViewer();
api.loadImages({'sem_image.tif'});
api.autoContrast();
api.getLineProfile(10, 10, 200, 200);
api.rotateFlip('rot90cw');       % rotate/flip: 'rot90cw','rot90ccw','fliph','flipv'
api.setPixelSize(2.4, 'nm');     % override pixel calibration

% EDS multi-channel composite mode
api.loadImages({'Fe_Ka.tif', 'O_Ka.tif', 'Si_Ka.tif'});
api.enterEDS();                          % auto-populates channels from loaded images
chs = api.getEDSChannels();              % cell array of channel structs
api.setEDSChannel(1, 'color', 'red');    % assign pseudo-color
api.setEDSChannel(2, 'color', 'green');
api.setEDSChannel(3, 'color', 'blue');
api.setEDSChannel(2, 'intensity', 0.8); % scale channel brightness
api.setEDSChannel(3, 'visible', false);  % hide a channel
comp = api.getEDSComposite();            % [H x W x 3] RGB double
api.exportImage('eds_composite.png');    % save blended composite
api.exitEDS();                           % return to normal view
api.close();
```

## EM Image Import

```matlab
% TIFF
data = parser.importTIFF('sem_image.tif');
img = data.metadata.parserSpecific.imageData;
imagesc(img.pixels); colormap gray; axis equal tight;

% Gatan DM3/DM4 (auto-dispatched by importAuto)
data = parser.importDM3('hrstem_image.dm3');
img = data.metadata.parserSpecific.imageData;
imagesc(img.pixels); colormap gray; axis image;
if img.calibrated
    title(sprintf('Pixel size: %.4g %s', img.pixelSize, img.pixelUnit));
end

% Headerless RAW — dimensions must be specified explicitly
data = parser.importRawImage('raw_image.raw', 'Width', 1024, 'Height', 768, 'BitDepth', 16);

% Imaging utilities
adjusted = imaging.adjustContrast(img.pixels, 100, 3000);
smoothed = imaging.applyGaussian(img.pixels, Sigma=2);
[mag, phase] = imaging.computeFFT(img.pixels);
[dist, intensity] = imaging.lineProfile(img.pixels, 1, 1, 100, 100, PixelSize=2.4, PixelUnit='nm');
thumb = imaging.generateThumbnail(img.pixels, MaxSize=256);
```

## Feature Summary

**Contrast & Display:** Auto-contrast (2nd/98th percentile), manual Low/High sliders, CLAHE (no-toolbox), colormap selection, colorbar toggle, histogram panel.

**Measurements:** Line profile with export, point-to-point distance, angle (3-click), polyline (multi-click, double-click to finish), ROI statistics (mean/std/min/max/area + mini-histogram).

**Distance label interactions:** Labels are placed perpendicular to the measurement line at FontSize 13 bold, transparent background. **Drag** any label to reposition it without affecting the measurement. **Right-click → Font size...** opens a dialog that applies the new size to all labels. The **"Label font:"** spinner in the Measurements panel does the same live. Tilt-corrected labels (marked with `*`) show the correction formula (1/cos or 1/sin) as a disabled context-menu item explaining the asterisk.

**Processing:** Gaussian filter, median filter, CLAHE, rotate 90°CW/CCW, flip H/V, FFT display, FFT masking with inverse FFT (interactive mask placement via ButtonDownFcn), crop, zoom box.

**Advanced:** Particle/feature counting (threshold + connected-component labeling via two-pass union-find, no toolbox), drift correction / image alignment (cross-correlation), color overlay / channel merge (assign colormaps to two images and blend), **EDS multi-channel composite** (false-color blending of element maps with per-channel color, visibility, and intensity controls), **template matching** (NCC-based feature finding), **image stitching** (panoramic mosaic from overlapping tiles), **noise characterization** (MAD/local-variance estimation with filter recommendations).

**EELS Analysis:** Background subtraction (power-law/exponential), core-loss edge identification (~50 built-in edges), elemental map extraction from spectrum images, thickness mapping (log-ratio t/λ), zero-loss peak alignment. Supports 1D spectra and 3D spectrum image datacubes from DM3/DM4 files.

**Diffraction Indexing:** Auto-detect spots in FFT/diffraction patterns, match against built-in crystal database (~50 phases), zone axis identification, ring overlay for matched phases. Supports both FFT geometry and calibrated TEM diffraction (camera length input).

**EDS Quantification:** Cliff-Lorimer thin-film quantification from EDS element maps, built-in k-factor table (47 elements, 200 kV), atomic% and weight% maps, composition line profiles, ROI composition analysis.

**Analysis Tools:** 3D surface view (height map rendering), live FFT panel (persistent, updates with filters), measurement statistics (aggregate histogram + stats), batch measurement (same profile across all images), export profile to BosonPlotter.

**Publication Tools:** Journal presets (APS/Nature/ACS/Elsevier annotation formatting), EM colormap presets (SEM/TEM/STEM-HAADF/EDS/phase/topography).

**Stack Navigator:** Multi-frame TIFF detection with frame slider, prev/next buttons, and Maximum Intensity Projection (MIP). Shown automatically when loading multi-page TIFFs.

**Undo:** Multi-level undo stack (cap 5 entries). `undoPush()` called inside `try` blocks before each destructive operation (filter, rotate, crop, FFT mask). Ctrl+Z triggers undo; handles dimension changes from rotation undo.

**Export:** Save image, save crop, export with overlays (burns scale bar, annotations, measurements into image via `copyobj`+`getframe`), batch export (all loaded images with per-image auto-contrast), copy to clipboard.

**Quality of Life:** Keyboard shortcuts (Ctrl+O open, Ctrl+S save, Ctrl+Z undo, A auto-contrast, F fit, +/- zoom), drag-and-drop file loading, recent files list (persisted to `.emviewer_recent.mat`, cap 10), pixel calibration override, linked zoom in compare mode, text annotations.

**Capture modes** (`appData.captureMode`): `'profile'`, `'distance'`, `'angle'`, `'polyline'`, `'roistats'`, `'zoom'`, `'crop'`, `'savecrop'`, `'annotation'`.

## Transform Toolbar (above the image)

A row of eight icon-only buttons sits directly above the uiaxes so the most
common geometric operations are always one click away, regardless of which
Tools-panel tab is currently visible on the right side of the window.

| # | Icon | Action | Callback |
|---|------|--------|----------|
| 1 | curved arrow CW  | Rotate 90° clockwise                          | `onRotateFlip('rot90cw')` |
| 2 | curved arrow CCW | Rotate 90° counter-clockwise                  | `onRotateFlip('rot90ccw')` |
| 3 | two triangles, dashed vertical mirror   | Flip horizontally (left-right)      | `onRotateFlip('fliph')` |
| 4 | two triangles, dashed horizontal mirror | Flip vertically (top-bottom)         | `onRotateFlip('flipv')` |
| 5 | magnifier with `+` | Zoom to rectangle (Esc cancels)             | `onZoomBox` |
| 6 | four corner arrows inward | Fit image to window / reset zoom     | `onResetZoom` |
| 7 | circular arrow   | Reset **all** transforms (reload the original image from the parser cache; clears all rotations, flips, filters, and crops) | `setActiveIdxAPI(getActiveIdxAPI())` |
| 8 | L-bracket crop marks | Crop to rectangle (destructive — use *Undo Filters* on the Filter tab to revert) | `onCropImage` |

The toolbar delegates to exactly the same callbacks as the Transform tab in
the Tools panel; the older Transform tab is retained as a fallback. If any
PNG asset in `icons/fermiviewer/` is missing, buttons fall back to a short
text label (`CW`, `CCW`, `FH`, `FV`, `Z`, `Fit`, `Reset`, `Crop`) so the
GUI never silently breaks.

Icon assets are generated by `icons/fermiviewer/build_icons.m`, which
renders anti-aliased 24×24 RGBA PNGs via a custom pixel canvas — no
figure-capture, no external toolboxes.

## Histogram Panel

The histogram panel under **Tools → Histogram** shows the raw pixel
distribution and overlays four interactive layers that make contrast
adjustment direct rather than slider-only.

### Overlays

| Overlay | Appearance | Meaning |
|---------|------------|---------|
| Window tint | Translucent green between **Low** and **High** | Pixels in this range are mapped to the visible 0–1 display range. |
| Low handle | Solid cyan vertical line | Drag to set the dark clipping point (matches `Low` slider). |
| High handle | Solid magenta vertical line | Drag to set the bright clipping point (matches `High` slider). |
| Gamma midpoint | Dashed yellow vertical line (only when γ ≠ 1) | The pixel value that maps to display 0.5 — drag to retune γ. |
| Transfer ramp | Semi-transparent white curve | The actual contrast pipeline (transform → stretch → γ → invert) plotted across the histogram. The shape mirrors what you see on screen. |
| Clipping strips | Red strip at left, orange strip at right | Pixels saturated to 0 (red) or 1 (orange). Strip height ∝ √(clipped fraction), so 1% saturation is still visible. Threshold to draw: 1%. |

### Interactions

| Action | Effect |
|--------|--------|
| Click near Low / High line and drag | Move that handle alone (existing behaviour). |
| Click near gamma midpoint and drag | Retune γ so the new x maps to display 0.5. |
| **Click anywhere inside the window region** (away from edges) and drag | Brightness/contrast drag, ImageJ-style: horizontal motion shifts the window (brightness), vertical motion scales the span multiplicatively (`exp(-0.005·dyPx)`, so drag up 200 px halves span = doubles contrast). |
| Scroll wheel over histogram | Symmetric expand/contract of the window around its centre. |

The brightness/contrast drag uses an 8 % × span / 4 % × x-range edge
tolerance to decide between "drag the whole window" and "snap to the
nearest handle" — clicks well inside the window almost always trigger
the B/C mode.

### Headless API

The overlay drawing is in `+emViewer/drawHistogramOverlay.m` and is
fully decoupled from the GUI closures. You can render the same overlay
on any uiaxes from a script:

```matlab
fig = uifigure('Visible','off'); ax = uiaxes(fig);
ax.XLim = [0 4096]; ax.YLim = [0 200];

rawPx = randn(100000,1)*500 + 2000;            % synthetic pixels
[counts, edges] = histcounts(rawPx, 256);
bar(ax, (edges(1:end-1)+edges(2:end))/2, counts, 1, ...
    'FaceColor', [0.5 0.5 0.5], 'EdgeColor', 'none');

% Overlay contrast handles + transfer ramp + clipping strips
emViewer.drawHistogramOverlay(ax, ...
    1500, 2500, ...        % lo, hi
    1.4,   ...             % gamma
    'linear', false, ...   % transform, invert
    rawPx);
```

To suppress the new overlays (for a minimal marker-only view, e.g. for
publication figures):

```matlab
emViewer.drawHistogramOverlay(ax, lo, hi, gamma, 'linear', false, rawPx, ...
    'showRamp', false, 'showClipping', false);
```

Performance: clipping fractions subsample to 200k pixels max so drag
stays smooth on 4k+ frames. The ramp is 128 samples by default
(`nRampSamples` option).

## EELS Analysis Workflow

```matlab
% Import EELS spectrum from DM3/DM4
data = parser.importDM3('eels_spectrum.dm3');
spec = data.metadata.parserSpecific.spectrumData;
plot(spec.energyAxis, spec.counts);
xlabel('Energy Loss (eV)'); ylabel('Counts');

% Background subtraction (power-law)
[signal, bg] = imaging.eelsBackground(spec.energyAxis, spec.counts, ...
    FitWindow=[600 700]);

% Show edge markers
edges = imaging.eelsEdgeTable();
feEdge = edges(strcmp({edges.symbol}, 'Fe-L23'));
xline(feEdge.onsetEV, 'r--', feEdge.symbol);

% Spectrum image: load 3D datacube
data = parser.importDM3('spectrum_image.dm3');
si = data.metadata.parserSpecific.spectrumImage;
% si.cube = [Ny x Nx x nE], si.energyAxis = [nE x 1]

% Extract elemental map
feMap = imaging.eelsExtractMap(si.cube, si.energyAxis, [708 750], ...
    BackgroundWindow=[600 700]);
imagesc(feMap); colorbar; title('Fe-L_{2,3} map');

% Thickness mapping
[tMap, mask] = imaging.eelsThicknessMap(si.cube, si.energyAxis);

% ZLP alignment
[alignedCube, shifts] = imaging.eelsAlignZLP(si.cube, si.energyAxis);
```

## Diffraction Pattern Indexing

```matlab
% Auto-detect spots in FFT or diffraction pattern
spots = imaging.findDiffractionSpots(fftImage, MinRadius=15, Threshold=0.05);

% Match against crystal database
result = imaging.indexDiffraction(spots, size(fftImage), ...
    PixelSize=0.195, PixelUnit='nm', AccVoltage=200);

% Top candidate
fprintf('Best match: %s (score=%.0f%%)\n', ...
    result.candidates(1).phaseName, result.candidates(1).score*100);

% Electron wavelength
lambda = imaging.calcElectronWavelength(200);  % 0.02508 Å
```

## EDS Quantification

```matlab
% Cliff-Lorimer quantification from intensity maps
maps = {fe_map, o_map, ti_map};
elements = {'Fe', 'O', 'Ti'};
result = imaging.cliffLorimer(maps, elements);
% result.atomicPctMaps, result.weightPctMaps, result.meanAtomicPct

% Built-in k-factors
kTable = imaging.edsKFactorTable();
kFe = kTable('Fe');  % 1.21

% Composition line profile
profile = imaging.edsCompositionProfile(result.atomicPctMaps, elements, ...
    x1, y1, x2, y2, PixelSize=2.4, PixelUnit='nm');
plot(profile.distance, profile.atomicPct);
legend(elements);
```

## GUI Development Notes

- Image pipeline: `rawPixels` → `filteredPixels` (after filters) → `displayImg` ([0,1] after contrast).
- `displayImage()`, `clearDisplay()`, and `setToolsEnabled()` must all be updated when adding new buttons (the enable/disable triad).
- `exitCompareMode()` recreates `axGL` as `[2 1]` grid (row 1 = axes, row 2 = stack navigator). Stack controls must be recreated with full styling (`BTN_TOOL`, `BTN_FG`, tooltips).
- `undoPush()` must go **inside** `try` blocks, not before — prevents phantom undo entries on filter failure.
- `undoPop()` must detect dimension changes (e.g. undoing a rotation on non-square images) and do full axes rebuild instead of just updating CData.
- FFT mask editor uses `ButtonDownFcn` on axes, not `ginput()` — `ginput` is unreliable from uifigure callback contexts.
- Polyline double-click: `WindowButtonDownFcn` fires twice; check `fig.SelectionType == 'open'` before adding click points.
- Recent files persisted to `.emviewer_recent.mat` in the toolbox root directory.
- CLAHE: uniform tiles can produce `cdf(end) == 0`; fallback: `cdf = linspace(0, 1, nBins)`.
- Batch export uses per-image auto-contrast (2nd/98th percentile), not the active image's slider values.
