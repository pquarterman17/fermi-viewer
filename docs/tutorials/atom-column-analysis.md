# Tutorial: Atom-Column Analysis and Real-Space Strain Mapping

This tutorial walks through the complete atom-column workflow in FermiViewer: from a single atomic-resolution HR(S)TEM image, detect every atomic column, refine each to sub-pixel precision, optionally split the columns into chemical sublattices, and map the local strain field by real-space peak-pair analysis (PPA) — then read off and export the result.

**Research question:** "I have an aberration-corrected HAADF-STEM image of a thin-film heterointerface (or a dislocation core). How do I measure the local lattice strain — $\varepsilon_{xx}$, $\varepsilon_{yy}$, $\varepsilon_{xy}$, and the rigid rotation — at the resolution of individual atomic columns, and how do I get a number per column rather than a smoothed map?"

The physics behind every step — the rotated 2-D Gaussian model, lattice-vector voting, the displacement-gradient → strain-tensor derivation, and how real-space PPA differs from Fourier-space GPA — lives in [`docs/theory/imaging.md`](../theory/imaging.md#atom-column-analysis-and-real-space-peak-pair-strain). This tutorial focuses on the workflow and on interpreting the result.

---

## 1. Physics background in 60 seconds

In an HAADF-STEM image, each atomic column is a bright blob whose intensity scales roughly as $Z^{1.7}$, so heavy (cation) columns are brighter than light (anion) columns. The position of each blob encodes where the atoms are; the *shifts* of those positions away from a perfect periodic lattice encode strain.

The chain is:

1. **Detect** column seeds (integer-pixel local maxima).
2. **Fit** a rotated elliptical 2-D Gaussian to each, giving sub-pixel centers $(x_0, y_0)$ good to a few picometres — essential because strain is a *gradient* of position.
3. **Index** every column to its ideal site $(m,n)$ on a reference lattice, measure its displacement $\mathbf{u} = \mathbf{r} - \mathbf{r}^\text{ideal}$.
4. **Differentiate** $\mathbf{u}$ locally to get the displacement-gradient tensor $\mathbf{J}$, then split it into the symmetric strain tensor and antisymmetric rotation:

$$\varepsilon_{ij} = \tfrac{1}{2}\!\left(\frac{\partial u_i}{\partial x_j} + \frac{\partial u_j}{\partial x_i}\right),\qquad \omega = \tfrac{1}{2}\!\left(\frac{\partial u_y}{\partial x} - \frac{\partial u_x}{\partial y}\right).$$

This is the same strain definition as Geometric Phase Analysis (GPA), but obtained in real space directly from column coordinates. PPA wins where GPA struggles — large displacements (no $2\pi$ phase wrap), sublattice-resolved chemistry, and per-column statistics. See the [theory section](../theory/imaging.md#real-space-ppa-vs-fourier-space-gpa--when-to-use-each) for the full comparison.

---

## 2. What you need

- An **atomic-resolution image** where individual columns are visibly resolved: HAADF-STEM (cleanest, since intensity is monotonic in $Z$), or HRTEM near a defocus where columns are distinct peaks (not just fringes).
- **Adequate sampling.** Aim for $\ge 4$–5 pixels across each column FWHM. A 2 Å lattice at 0.2 Å/pixel gives $\sim$10 px column spacing — comfortable. If columns are only 2–3 px wide, sub-pixel fitting gains little over the integer seed and strain is buried in fit noise; magnify more or bin less at acquisition.
- **A pixel-size calibration** (optional but recommended). Strain itself is dimensionless and needs no calibration, but the workshop reads the GUI's pixel size to label distances; set it via *Tools ▸ Calibrate Pixel Size…* first if you want physical units on exports.
- **A mental note of which region is unstrained.** PPA strain is *relative* to a reference lattice. The workshop uses the **average lattice over the whole field of view** as its reference, so the strain map is measured against that average — keep that in mind when interpreting absolute values (see § 7).

---

## 3. Stage 1 — Open the image and launch the workshop

Load an atomic-resolution image into FermiViewer as usual:

```matlab
setupToolbox            % run once to add packages to path
FermiViewer             % launch the GUI, then File ▸ Open… your DM3/DM4/TIFF
```

With the image displayed, open the workshop from **Analysis ▸ Atom Columns…**. A standalone window titled *Atom Columns* appears with the image on the left and a control column on the right. The workshop operates on FermiViewer's *filtered* pixels, so any CLAHE / Gaussian / median pre-processing you applied carries through — a light Gaussian (σ ≈ 1 px) or CLAHE often helps detection on noisy data without hurting the fit.

> **Scripted / headless use.** Everything below is also reachable programmatically. The workshop returns an `api` struct; tests and batch scripts drive it without mouse events:
> ```matlab
> img = api0.getFilteredPixels();      % from a headless FermiViewer
> w = fermiViewer.atomcolumns.openAtomColumnWorkshop(img);
> w.setPolarity('bright'); w.detect(); w.computeStrain();
> res = w.getResult();                 % struct with positions, sublattice, strain
> w.exportCSV('columns.csv');
> ```
> You can also call the underlying `+imaging/+atoms/` functions directly (see § 9).

---

## 4. Stage 2 — Detect and fit columns

Set the detection parameters in the control column, then press **Detect + Fit**. The five knobs:

| Control | Meaning | Typical value |
|---|---|---|
| **Polarity** | `Bright` for HAADF / bright columns; `Dark` for dark-column HRTEM defoci | `Bright` |
| **Pre-smooth σ** | Gaussian smoothing (px) before local-max detection — suppresses pixel noise | 1.5 – 3 |
| **Threshold** | Accept maxima ≥ Threshold × (smoothed dynamic range), in [0, 1] | 0.15 – 0.3 |
| **Min spacing (px)** | Non-maximum-suppression radius — minimum allowed distance between columns | 0.7–0.9 × the column spacing |
| **Fit window (px)** | Half-size of the Gaussian-fit ROI per column | ≈ 0.4 × the column spacing |

Press **Detect + Fit**. The status bar reports the column count and the **median $R^2$** of the Gaussian fits, e.g. *"Detected 1,284 columns (median R²=0.981)."* The overlay shows one marker per fitted column.

**What good looks like:**

- One marker per column, no doubles, no missing columns in well-resolved regions.
- Median $R^2 \gtrsim 0.95$. Lower values mean the model is fitting noise or overlapping columns.
- Markers sit visually centered on the blobs (zoom in to check).

**What bad looks like, and the fix:**

| Symptom | Cause | Fix |
|---|---|---|
| Two markers on one column | `Min spacing` too small | Raise it toward the lattice spacing |
| Columns merged / missed | `Min spacing` too large | Lower it |
| Spurious markers in vacuum / noise | `Threshold` too low | Raise it (0.25–0.35) |
| Real columns missing | `Threshold` too high, or wrong **Polarity** | Lower threshold; check Bright vs Dark |
| Low median $R^2$, off-center markers | `Fit window` overlapping neighbours | Shrink it to ≈ 0.4 × spacing |
| Edge columns un-refined | Window runs off the image | Expected — edge seeds are kept un-fitted |

Iterate the threshold and spacing until detection is clean *before* moving on — strain quality is capped by fit quality.

---

## 5. Stage 3 — Sublattices (optional)

Many structures have two or more chemically distinct columns (e.g. the B-site cation and the A-site / oxygen columns in a perovskite). Set **Sublattices** to the number of distinct column brightnesses (1–4) and the workshop runs k-means on the fitted amplitudes, then re-runs detect with that setting. Switch the **Overlay** dropdown to **Sublattice** to colour columns by group — label 1 is always the brightest sublattice.

Use this when:

- You want strain on one sublattice only (the cation cage, say), uncontaminated by a fainter interleaved sublattice.
- You are measuring **ferroelectric polar displacements** — the relative shift between two sublattices. Run the analysis once, note the sublattice labels, and compare the displacement fields.

If your structure is a simple single-element net (Si, Au, graphene), leave **Sublattices = 1**.

---

## 6. Stage 4 — Strain (PPA)

Press **Strain (PPA)**. The workshop estimates the primitive lattice vectors $\mathbf{a}_1, \mathbf{a}_2$ from the column cloud (angle-histogram voting — robust to a few missing columns), indexes every column to its nearest ideal site on that **average lattice**, measures the displacement, and fits a local displacement gradient over each column's nearest neighbours to produce per-column $\varepsilon_{xx}$, $\varepsilon_{yy}$, $\varepsilon_{xy}$, and rotation.

Then use the **Overlay** dropdown to render the field:

- **εxx** — normal strain along the image $x$-axis.
- **εyy** — normal strain along the image $y$-axis.
- **εxy** — shear strain.
- **Rotation** — rigid lattice rotation $\omega$ (rad), independent of strain.

Each column is coloured by the chosen component on a diverging scale (zero strain ≈ neutral; tension and compression to opposite ends). The results text area summarises the lattice vectors, column count, and mean/range of each component.

---

## 7. Stage 5 — Interpreting the overlays

PPA strain is **relative to the average lattice** of the field of view. Read the maps accordingly:

- **A heterointerface.** Across a coherently strained film-on-substrate interface, $\varepsilon_{xx}$ (or $\varepsilon_{yy}$, whichever is the out-of-plane growth direction) shows a **step**: one side near zero, the other side offset by the misfit. For a SiGe-on-Si example with 4 % mismatch fully accommodated out-of-plane, expect a $\sim$4–5 % step in the out-of-plane component and near-zero in-plane (pseudomorphic). Because the *reference is the average*, both sides are shifted so the field-average is zero — the physically meaningful quantity is the **step height** between the two regions, not either absolute value. (If you need the substrate as an explicit zero, call `imaging.atoms.peakPairStrain` directly with a `RefRegion` over the substrate — see § 9.)
- **A dislocation core.** Expect a localised, sign-changing lobe pattern in the strain components and a sharp feature in the **Rotation** map. This is exactly the regime where PPA beats GPA: the large displacements near the core would wrap GPA's Bragg phase, but PPA reads the displacement directly with no $2\pi$ ambiguity.
- **A defect-free region.** Should be uniformly near zero (neutral colour) with only fit-noise speckle. The speckle amplitude is your noise floor — typically $\sim$0.2–0.5 % for a clean HAADF image. Any feature smaller than that is not significant.

**Sanity checks before you believe a map:**

1. **Displacement field has no full-lattice-vector jumps.** A dropped or misindexed column produces a spurious displacement of $\sim$one whole lattice vector and a single wild strain pixel. If you see isolated extreme-value columns, a missing neighbour is the likely cause — re-tune detection.
2. **Rotation ≈ strain magnitude** is a red flag. A large uniform rotation usually means a slight scan-rotation / drift artefact, not real lattice rotation.
3. **Cross-check against GPA.** Run `imaging.geometricPhaseAnalysis` on the same image. Where both work, the maps should agree; disagreement points to a method-specific artefact (PPA: detection errors; GPA: phase-unwrap / mask issues).

---

## 8. Stage 6 — Export

Two export buttons:

- **Export CSV…** writes one row per column: position $(x, y)$, sublattice label, lattice indices $(m, n)$, displacement $(u_x, u_y)$, and $\varepsilon_{xx}, \varepsilon_{yy}, \varepsilon_{xy}$, rotation. This is the per-column table for downstream statistics, plotting, or comparison between datasets. The CSV preserves calibrated units when a pixel size is set.
- **Save overlay…** writes the current coloured overlay as a PNG for figures.

The CSV is the natural hand-off to a notebook or to `quantized_matlab`'s BosonPlotter (import with `parser.importCSV`) for histogram and line-profile analysis of the strain across an interface.

---

## 9. Scripting the pipeline directly

For batch processing or reproducible analysis, skip the GUI and call the `+imaging/+atoms/` functions:

```matlab
img = double(parser.importDM3('hrstem.dm3').values);   % atomic-resolution image

% 1. Detect integer-pixel seeds
det = imaging.atoms.detectColumns(img, ...
        Sigma=2, Threshold=0.2, MinSeparation=9, Polarity="bright");

% 2. Sub-pixel refine (rotated 2-D Gaussian, Levenberg-Marquardt)
fit = imaging.atoms.fitGaussian2D(img, det.positions, WinRadius=5);
fprintf('Median fit R^2 = %.3f\n', median(fit.rsquared,'omitnan'));

% 3. (optional) sublattices by amplitude
sub = imaging.atoms.assignSublattice(fit.amplitude, 2);   % e.g. cation/anion

% 4a. Strain vs the AVERAGE lattice (what the GUI does)
strain = imaging.atoms.peakPairStrain(fit.positions);

% 4b. ...or strain vs an explicit unstrained REFERENCE region
%     (substrate occupies the bottom 200 px, say)
ref    = imaging.atoms.findLatticeVectors(fit.positions( ...
                 fit.positions(:,2) > size(img,1)-200, :));
strain = imaging.atoms.peakPairStrain(fit.positions, ...
            RefVectors=[ref.a1; ref.a2], Origin=ref.origin);

% Scatter the strain field, coloured by exx
figure;
scatter(fit.positions(:,1), fit.positions(:,2), 20, strain.exx, 'filled');
axis image ij; colorbar; colormap(turbo); clim([-0.05 0.05]);
title('\epsilon_{xx}  (PPA, reference = substrate)');
```

Variant 4b is the way to get strain referenced to a known-unstrained region rather than the field average — the single most common reason to script instead of using the workshop.

---

## 10. Common pitfalls

- **Under-sampled columns.** Below $\sim$4 px FWHM the Gaussian fit barely improves on the integer seed, and strain (a gradient) is dominated by fit noise. The cure is at acquisition: higher magnification or less binning.
- **Wrong `Min spacing`.** Too small → double-counts a column; too large → merges neighbours. Set it to 0.7–0.9 × the visible column spacing.
- **`Fit window` too large.** A window that spills onto the next column drags the fitted center off and tanks $R^2$. Keep it ≈ 0.4 × spacing.
- **Reference confusion.** The workshop references the *average* lattice. If part of your field is heavily strained, the "zero" of the map is pulled toward that region's lattice. For an absolute zero, reference an explicit unstrained region via the scripted `RefRegion` / `RefVectors` path.
- **Missing columns corrupt indexing.** One dropped column can misindex its neighbours to the wrong $(m,n)$ site, producing a spurious one-lattice-vector displacement. Inspect the displacement field for full-vector jumps before trusting the strain.
- **Treating PPA noise as signal.** The per-column speckle in a defect-free region is your noise floor (typically 0.2–0.5 %). Features below it are not real; average over several columns or compare to GPA.
- **Forgetting it's relative.** Neither PPA nor GPA gives absolute strain. Always state the reference region in figures and methods text.

---

## 11. Reporting template

For a publication-ready methods paragraph, report:

1. **Image and sampling.** Microscope, voltage, detector (HAADF inner/outer angles), pixel size (pm/px), and image dimensions.
2. **Detection / fit.** Pre-smooth σ, threshold, min spacing, fit window; number of columns detected and the median fit $R^2$.
3. **Sublattices.** Number of sublattices and the clustering feature (amplitude).
4. **Strain method.** "Real-space peak-pair analysis (PPA) on 2-D-Gaussian-fitted column positions," the neighbour count for the gradient fit, and — critically — **the reference lattice** (average field, or a named unstrained region).
5. **Result.** Strain step / peak values with the noise floor stated (e.g. "$\varepsilon_{zz} = 4.6 \pm 0.4$ % across the interface, noise floor 0.3 %").
6. **Cross-check.** Whether the map was corroborated by GPA.
7. **Software.** "Analysis performed with the FermiViewer toolbox (`+imaging/+atoms/` package), MATLAB R202Xy."

Example:

> HAADF-STEM images (2048 × 2048 px, 8.6 pm/px) were analysed with the FermiViewer atom-column suite. Columns were detected (pre-smooth σ = 2 px, threshold 0.2, minimum spacing 9 px) and refined by rotated-elliptical 2-D-Gaussian fitting (window radius 5 px), yielding 4,310 columns with a median fit $R^2$ of 0.98. Real-space peak-pair analysis against the substrate lattice (lower 200 px) gave a $4.6 \pm 0.4$ % step in the out-of-plane normal strain across the heterointerface (noise floor 0.3 %, estimated from the substrate region), in agreement with a Fourier GPA map of the same field.

---

## 12. References

- Nord, M., Vullum, P. E., MacLaren, I., Tybell, T. & Holmestad, R., "Atomap: a new software tool for the automated analysis of atomic resolution images using two-dimensional Gaussian fitting," *Adv. Struct. Chem. Imaging* **3**, 9 (2017). DOI: [10.1186/s40679-017-0042-5](https://doi.org/10.1186/s40679-017-0042-5)
- Galindo, P. L., et al., "The Peak Pairs algorithm for strain mapping from HRTEM images," *Ultramicroscopy* **107**, 1186–1193 (2007). DOI: [10.1016/j.ultramic.2007.01.019](https://doi.org/10.1016/j.ultramic.2007.01.019)
- Hÿtch, M. J., Snoeck, E. & Kilaas, R., "Quantitative measurement of displacement and strain fields from HREM micrographs," *Ultramicroscopy* **74**, 131–146 (1998). The Fourier-space (GPA) counterpart.
- Yankovich, A. B., et al., "Picometre-precision analysis of scanning transmission electron microscopy images of platinum nanocatalysts," *Nat. Commun.* **5**, 4155 (2014). DOI: [10.1038/ncomms5155](https://doi.org/10.1038/ncomms5155)

For the full derivations behind every formula here — the rotated Gaussian model and its LM/ridge solver, the lattice-vector voting algorithm, and the displacement-gradient → strain-tensor decomposition — see [`docs/theory/imaging.md`](../theory/imaging.md#atom-column-analysis-and-real-space-peak-pair-strain). For the Fourier-space alternative, see the [Geometric Phase Analysis](../theory/imaging.md#geometric-phase-analysis-gpa) section of the same file.
