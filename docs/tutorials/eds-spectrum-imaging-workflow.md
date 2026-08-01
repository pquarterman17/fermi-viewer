# Tutorial: EDS Spectrum-Imaging Workflow

This tutorial walks through the complete Energy-Dispersive X-ray Spectroscopy
(EDS) spectrum-imaging workflow for a Bruker `.bcf` hypermap: load the spectral
hypercube, explore it interactively, build background-corrected element maps,
pull spectra from individual pixels and regions, and quantify composition with
Cliff–Lorimer.

**Research question:** "I have a Bruker BCF spectrum image (3-D cube: $x$, $y$,
energy) from an SEM/STEM EDS map. How do I see where each element sits, extract
clean element maps, and turn them into atomic percentages?"

The physics derivations behind every formula used here (window integration,
linear two-window background, characteristic line energies, overvoltage-based
line selection, Cliff–Lorimer, ZAF) live in
[`docs/theory/spectroscopy.md`](../theory/spectroscopy.md). This tutorial
focuses on the toolbox workflow. For the GUI feature reference see
[`docs/gui_emviewer.md`](../gui_emviewer.md); for the parser internals see the
[Parser Reference](https://github.com/pquarterman17/fermi-viewer/wiki/Parser-Reference)
wiki page.

---

## 1. Physics background in 60 seconds

When the electron beam ionises an atom, the atom relaxes by emitting a
**characteristic X-ray** whose energy is fixed by the element and the shell
involved (Kα, Lα, Mα …). An EDS detector histograms these X-rays into an energy
spectrum; acquiring one spectrum per scan pixel produces a **spectrum image**
(hypercube) $C(y, x, E)$.

Three facts drive the whole workflow:

- **Lines are element fingerprints.** Cu Kα sits at 8.048 keV, O Kα at 0.525 keV,
  Fe Kα at 6.404 keV. Mapping an element means integrating the cube over a narrow
  energy window around its line:

  $$M(y,x) = \sum_{E_1 \le E_k \le E_2} C(y,x,E_k).$$

- **There is a continuum underneath.** Bremsstrahlung (continuum X-rays) adds a
  smooth background under every peak. Subtracting a **linear two-window**
  background — estimated from side windows just below and above the peak —
  converts a raw window sum into a *net* characteristic signal:

  $$M_\text{net}(y,x) = \max\!\big(0,\; M - n_\text{peak}\,b_\text{pp}\big),$$

  where $b_\text{pp}$ is the interpolated background counts per channel.

- **Which line to map depends on voltage.** A line is only well excited when the
  beam overvoltage $U = E_0/E_c \gtrsim 1.5$ (with $E_c$ the absorption edge,
  a little above the line). So heavy elements map on their **M** lines at low kV
  and their **L** lines at high kV — W and Au map on Mα at 15 kV but Lα at
  300 kV. `imaging.eds.lineEnergy` encodes this automatically.

**Cliff–Lorimer** turns net intensities into composition. For a thin film the
weight fraction of element $i$ is

$$w_i = \frac{k_i I_i}{\sum_j k_j I_j},$$

with $k_i$ the (Si-referenced) sensitivity factor; atomic fractions follow from
$w_i/M_i$. See [`spectroscopy.md`](../theory/spectroscopy.md) for the
thin-film criterion and the bulk ZAF alternative.

---

## 2. What you need

- A **Bruker `.bcf` spectrum image** — the SFS container holding both a SEM
  reference image and the EDS hypercube (`SpectrumData0`). Modern Esprit exports
  store the metadata header **AACS/zlib-compressed**; FermiViewer decodes these
  transparently.
- MATLAB **R2024a+** (R2022b best-effort), with the toolbox on the path
  (`setupToolbox`). No external toolboxes are required.

If you do not have a file handy, the repository ships small real BCF spectrum
images you can run this entire tutorial against:

```matlab
bcf = fullfile('+test_datasets','BCF','Hitachi_TM3030Plus.bcf');  % has Cu/Al/C/O
% others: esprit_v2_50x50.bcf, over16bit_compressed.bcf, 12bit_packed_16x16.bcf
```

---

## 3. Stage 1 — Load the hypercube

`parser.importBCF` (or `parser.importAuto`) decodes the cube by default:

```matlab
d   = parser.importBCF(bcf, Verbose=true);
eds = d.metadata.parserSpecific.edsData;

eds.cube          % [H x W x N] counts per pixel per channel (uint16 or uint32)
eds.cubeSize      % [H W N]
eds.energyAxis    % [N x 1] keV per channel  (= CalibAbs + CalibLin*(0:N-1))
eds.sumSpectrum   % [N x 1] cube summed over all pixels
eds.elements      % {'Cu','Al','C','O'}  identified element symbols (may be {})
eds.elementZ      % [29 13 6 8]           matching atomic numbers
```

`Verbose=true` prints a one-line summary, e.g.:

```
importBCF: cube 240x320x4096 | total counts=171804
importBCF: image=1 | EDS channels=4096 | elements=4 | 320x240 px | HV=15.0 kV
```

**Memory control.** Large maps (e.g. 512×512×4096) can be hundreds of MB. The
cube is loaded by default but guarded by `MaxCubeBytes` (≈1.5 GB); above the cap
the image and sum spectrum still return while `eds.cube` is left empty. To skip
the cube entirely (header + image only):

```matlab
d = parser.importBCF(bcf, LoadCube=false);          % no cube
d = parser.importBCF(bcf, MaxCubeBytes=4e9);         % allow a bigger cube
```

**Sanity check** — overlay the sum spectrum and confirm the lines land where you
expect:

```matlab
plot(eds.energyAxis, eds.sumSpectrum); xlabel('Energy (keV)'); ylabel('Counts');
hold on;
for s = string(eds.elements)
    xline(imaging.eds.lineEnergy(s), ':', s);
end
```

---

## 4. Stage 2 — Explore interactively

The fastest way to understand a map is the **EDS Spectrum Image** workshop.
Launch FermiViewer, open the BCF so it is the active image, then choose
**Analysis ▸ EDS Spectrum Image…**:

- **Left axes — the element map.** Click a pixel to see *its* spectrum on the
  right; click-drag a rectangle for an **ROI-summed** spectrum (better
  statistics on a phase).
- **Right axes — the spectrum.** Click-drag horizontally to set an **energy
  window**; the map recomputes live for that window. The **Element** drop-down
  snaps the window to a chosen line (voltage-aware), and the **Background**
  drop-down toggles linear subtraction. **Export map / spectrum** writes CSV.

Everything the GUI does is scriptable for headless / reproducible use:

```matlab
api = FermiViewer(Visible='off');
api.loadImages({bcf});            % BCF becomes the active image
ws  = api.openSpectrumImage();    % [] if the active image has no cube

ws.selectElement('Cu');           % snap window to Cu Kα and remap
ws.selectROI(60, 80, 120, 160);   % ROI-summed spectrum [r0 c0 r1 c1]
ws.setWindow(7.90, 8.20);         % manual keV window
ws.setBackground('linear');       % or 'none'
cuMap   = ws.getMap();            % current 2-D map
roiSpec = ws.getSpectrum();       % current spectrum
ws.exportMapCSV('cu_map.csv');
ws.close();
```

---

## 5. Stage 3 — Build element maps from script

For batch work, go straight to the `+imaging/+eds` helpers. The core call is
`elementMap` — integrate a window with optional background subtraction:

```matlab
e   = imaging.eds.lineEnergy('Cu');               % 8.048 keV (Kα, auto)
Cu  = imaging.eds.elementMap(eds.cube, eds.energyAxis, ...
          e-0.085, e+0.085, Background='linear');  % net counts, [H x W]
imagesc(Cu); axis image; colormap hot; colorbar; title('Cu Kα');
```

The half-window of ~0.085 keV (≈ a typical EDS FWHM/2 near Mn) brackets the line
without pulling in neighbours. Use `Background='none'` to keep the raw continuum
(useful for total-count or topography-style maps).

To map every identified element in one call, `extractElementMaps` picks each
line (voltage-aware via `BeamKV`) and integrates it:

```matlab
hv   = d.metadata.parserSpecific.semParams.voltage_kV;   % e.g. 15
maps = imaging.eds.extractElementMaps(eds.cube, eds.energyAxis, eds.elements, ...
          BeamKV=hv, Background='linear');

for k = 1:numel(maps)
    subplot(2,2,k);
    imagesc(maps(k).map); axis image off; colormap hot;
    title(sprintf('%s %sα  (%.3f keV)', maps(k).symbol, maps(k).line, maps(k).energy));
end
```

Each `maps(k)` carries `.symbol`, `.line`, `.energy`, `.window`, `.map`,
`.total`. Elements whose line is unknown or falls outside the energy axis are
skipped with a warning. If `eds.elements` is empty (the map was acquired without
element IDs), just name them yourself:
`extractElementMaps(eds.cube, eds.energyAxis, {'Cu','O','Al'})`.

---

## 6. Stage 4 — Pixel and region spectra

Compare phases by summing spectra over regions and overlaying them. `pixelSpectrum`
accepts a single pixel, paired index vectors, or a logical mask:

```matlab
% Two ROIs (e.g. a particle vs. the matrix), as logical masks
particle = false(eds.cubeSize(1:2));  particle(40:70, 90:130) = true;
matrix   = false(eds.cubeSize(1:2));  matrix(150:180, 20:60)  = true;

sP = imaging.eds.pixelSpectrum(eds.cube, particle);
sM = imaging.eds.pixelSpectrum(eds.cube, matrix);

plot(eds.energyAxis, sP, eds.energyAxis, sM);
legend('particle','matrix'); xlabel('Energy (keV)'); ylabel('Counts');
xlim([0 10]);
```

A single pixel is `imaging.eds.pixelSpectrum(eds.cube, row, col)`; summing over
**all** pixels reproduces `eds.sumSpectrum` exactly — a handy self-check.

---

## 7. Stage 5 — Cliff–Lorimer quantification

Feed the net element maps straight into `imaging.eds.cliffLorimer`. Build the
cell arrays from the `maps` struct:

```matlab
intensityMaps = {maps.map};          % {1 x N} of [H x W]
elements      = {maps.symbol};       % {'Cu','Al','C','O'}

q = imaging.eds.cliffLorimer(intensityMaps, elements, Voltage=hv, ...
        MaskThreshold=20);            % ignore near-empty pixels (-> NaN)

q.atomicPctMaps     % {1 x N} per-element at% maps [H x W]
q.weightPctMaps     % {1 x N} wt% maps
q.meanAtomicPct     % [1 x N] field-of-view mean at%

% Mean composition over the field of view
for k = 1:numel(elements)
    fprintf('%-3s  %5.1f at%%\n', elements{k}, q.meanAtomicPct(k));
end
```

k-factors default to the built-in Si-referenced table for the given `Voltage`;
pass `KFactors=[...]` to override with your own standards. For **bulk** specimens
the thin-film assumption fails — use `imaging.eds.zafCorrection` instead (see
[EDS Analysis](https://github.com/pquarterman17/fermi-viewer/wiki/EDS-Analysis)).

To read composition along a line (e.g. across an interface):

```matlab
prof = imaging.eds.edsCompositionProfile(q.atomicPctMaps, elements, ...
           x1, y1, x2, y2, PixelSize=eds_pixel_nm, PixelUnit='nm');
plot(prof.distance, prof.atomicPct); legend(elements);
```

### 7.1 Upgraded path — peak-fit intensities, artifact check, then quantify

Window integration (above) mis-assigns intensity whenever two lines overlap, and
says nothing about Si-escape or sum peaks hiding under a real line. The more
rigorous path for overlapping or artifact-prone spectra is: **fit** net peak
areas → **check** for escape/pile-up artifacts → **quantify**. See
[`docs/theory/spectroscopy.md`](../theory/spectroscopy.md) for the physics
behind each step.

```matlab
elements = {'Fe','Cu'};
pf = imaging.eds.fitPeaks(eds.energyAxis, eds.sumSpectrum, elements, BeamKV=20);

art = imaging.eds.predictArtifacts(elements, pf.lineEnergyKeV);
% Fe-Kα 6.404 keV, Cu-Kα 8.048 keV -> Cu escape sits at 8.048-1.740 = 6.308 keV,
% only 96 eV from Fe-Kα: predictArtifacts flags it BLOCKED, the canonical trap
% where a free-amplitude "Cu escape" peak would otherwise steal Fe-Kα counts.

removal = imaging.eds.removeArtifacts(eds.energyAxis, eds.sumSpectrum, elements, ...
    pf.lineEnergyKeV, Residual=eds.sumSpectrum - pf.fittedCurve, ParentAreas=pf.netArea);
pf2 = imaging.eds.fitPeaks(eds.energyAxis, removal.corrected, elements, BeamKV=20);

[~, cl] = imaging.eds.quantifyPeaks(eds.energyAxis, removal.corrected, elements, ...
    BeamKV=20, Voltage=20);   % Cliff-Lorimer on artifact-corrected net areas
cl.meanAtomicPct       % -> [Fe at%, Cu at%]

% Or, when thickness/mass-thickness is also wanted:
zeta = imaging.eds.zetaFromKFactors(elements, 1000.0);   % scale from one Si standard
zq = imaging.eds.zetaQuantify(pf2.netArea, elements, zeta, ...
    BeamCurrentNA=1.0, LiveTimeS=100, Density=7.87);   % Fe density (g/cm^3), for illustration
zq.meanAtomicPct;  zq.meanRhoT_ug_cm2;  zq.meanThickness_nm
```

`quantifyPeaks` and `zetaQuantify` both accept the same net-area vector, so the
choice is composition-only (Cliff-Lorimer) vs. composition-plus-mass-thickness
(zeta-factor) — see [`docs/theory/spectroscopy.md`](../theory/spectroscopy.md)
for when each is appropriate.

---

## 8. Common pitfalls

- **Peak overlaps.** The classic trap near 2.3 keV is S Kα / Mo Lα / Pb Mα; Ti
  Kβ overlaps V Kα; O Kα overlaps several L/M lines below 0.6 keV. Always check
  your window against the sum spectrum (Stage 1) before trusting a map — a
  "high Mo" region may just be sulphur.
- **Window too wide.** A window that spills into a neighbour double-counts. Keep
  it to roughly ±1 FWHM and rely on background subtraction rather than widening.
- **Background mode.** `Background='none'` maps track total count rate (and
  thickness/topography), not the element. Use `'linear'` for quantitative
  distribution; only drop it deliberately.
- **Light elements & low kV.** C, N, O lines sit below ~0.5 keV where detector
  efficiency and absorption corrections dominate — treat their at% as
  semi-quantitative unless you have matched standards.
- **Thin-film vs bulk.** Cliff–Lorimer assumes negligible absorption/fluorescence
  (thin TEM foil). For bulk SEM EDS use ZAF.
- **Counts statistics.** Per-pixel spectra in a fast map are noisy; sum over an
  ROI (Stage 4) before quantifying a phase.

---

## 9. Reporting template

```
Specimen / map:    __________   (BCF file, HV ____ kV, pixel size ____ nm)
Cube:              H×W×N = ____ × ____ × ____
Elements mapped:   ____  (lines: ____)   window ±____ keV, background: linear
Quantification:    Cliff–Lorimer, k-factors @ ____ kV (source: built-in/standards)
Mean composition:  __ at% A, __ at% B, …   (mask threshold ____)
Notes:             overlaps checked (____); thin-film assumption valid (Y/N)
```

---

## 10. References

The BCF hypercube byte layout (SFS container, AACS/zlib block compression, and
the per-pixel 16-bit / 12-bit / instructive packing of `SpectrumData0`) follows
the open-source HyperSpy / RosettaSciIO reference (`rsciio/bruker`).
Characteristic line energies are from Bearden, *Rev. Mod. Phys.* **39** (1967)
78, cross-checked against the NIST X-ray Transition Energies database.
Quantification follows Cliff & Lorimer, *J. Microsc.* **103** (1975) 203 and
Williams & Carter, *Transmission Electron Microscopy*, 2nd ed. (2009). Full
citations and derivations are in [`docs/theory/spectroscopy.md`](../theory/spectroscopy.md).

## Related

- [`docs/theory/spectroscopy.md`](../theory/spectroscopy.md) — EDS theory (window maps, background, line selection, Cliff–Lorimer, ZAF)
- [`docs/tutorials/eels-analysis-workflow.md`](eels-analysis-workflow.md) — the EELS counterpart
- Wiki: [EDS Spectrum Imaging](https://github.com/pquarterman17/fermi-viewer/wiki/EDS-Spectrum-Imaging), [EDS Analysis](https://github.com/pquarterman17/fermi-viewer/wiki/EDS-Analysis)
