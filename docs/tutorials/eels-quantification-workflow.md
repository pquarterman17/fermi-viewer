# Tutorial: Quantitative EELS — Atomic Composition (at%) from Core-Loss Edges

This tutorial walks through extracting **relative atomic composition** from a core-loss EELS spectrum using FermiViewer's *Quantify EELS (at%)* dialog. The output is an at% table (e.g. O 67%, Ti 33%) that you read as a stoichiometry — the cation:anion ratio at the region you measured.

**Research question:** "I have a core-loss EELS spectrum from this region. What is the O:Ti ratio — is this rutile (TiO₂), or is it oxygen-deficient? What's the cation stoichiometry?"

The physics behind every formula here (the quantification relation $\mathrm{at\%}_X \propto I_X/\sigma_X$, the hydrogenic partial cross-section, and an honest account of its approximations) lives in [`docs/theory/spectroscopy.md`](../theory/spectroscopy.md#hydrogenic-partial-cross-sections-and-at-quantification). This tutorial focuses on the workflow. For the full spectrum-image pipeline (ZLP alignment, thickness mapping, ELNES, Cliff–Lorimer), see the companion [EELS spectrum-image tutorial](eels-analysis-workflow.md).

---

## 1. Physics in 60 seconds

After you background-subtract a core-loss edge and integrate its intensity $I_X$ over a window $\Delta$ above the onset, the number of atoms per unit area scales as $N_X \propto I_X / \sigma_X$, where $\sigma_X(\beta, \Delta)$ is the **partial ionisation cross-section** for the same collection semi-angle $\beta$ and the same window $\Delta$. Forming the ratio of two elements (Egerton 2011, Eq. 4.65):

$$\frac{N_A}{N_B} = \frac{I_A / \sigma_A}{I_B / \sigma_B}, \qquad \mathrm{at\%}_X = 100\cdot\frac{I_X/\sigma_X}{\sum_j I_j/\sigma_j}.$$

The beauty of the ratio is that the low-loss / zero-loss normalisation $I_0$ — and the incident current and dwell time — **cancel**. You get *relative* composition without ever measuring the incident beam. The catch: $I_X$ (from the data) and $\sigma_X$ (from the model) must use the **same $\beta$ and the same $\Delta$**. The dialog handles $\Delta$ automatically (it reads the signal window you set); you just keep $\beta$ fixed, which it physically is for one acquisition.

FermiViewer computes $\sigma_X$ from a **hydrogenic** model (`imaging.eels.eelsCrossSection`) anchored on the *measured* edge onset. It's fast and toolbox-free, accurate to **~10–20%** for K edges of light elements and L$_{2,3}$ edges of medium-$Z$ elements — good enough for stoichiometry and trends, not for absolute densities. Treat it like an EDS $k$-factor with no standard.

---

## 2. What you need

- A **core-loss spectrum** (1-D) covering the edges of interest with a clean pre-edge region. Load any supported format (DM3/DM4, SER) or extract a single spectrum / ROI-average from a spectrum-image cube (see the [SI tutorial](eels-analysis-workflow.md), Stage 6).
- **Accelerating voltage** $E_0$ (kV) — from the DM metadata or the operator log (80, 200, 300 kV typical).
- **Collection semi-angle** $\beta$ (mrad) — set by the EELS entrance aperture and camera length. The cross-section depends on $\beta$ through $\ln(1+\beta^2/\theta_E^2)$, so this must be the *actual* value for your acquisition.
- The **edge identities and onsets** — element symbol, shell (K or L$_{2,3}$), and onset energy (eV). `imaging.eelsEdgeTable()` lists the standard onsets.

Common onsets (eV): **C-K 284**, **N-K 401**, **O-K 532**, **Ti-L₂,₃ 456**, **Fe-L₂,₃ 708**, **B-K 188**, **Si-L₂,₃ 99**, **Mn-L₂,₃ 640**.

**Before you start:** if your region has $t/\lambda > 1$ (thick), the edges are distorted by plural scattering and the at% will be biased. Deconvolve first (`imaging.eelsFourierLog`) — see Stage 8 of the SI tutorial.

---

## 3. Open the dialog

Load your spectrum into FermiViewer, then:

**Analysis ▸ Quantify EELS (at%)…**

The dialog has three groups:

1. **Beam settings** — $E_0$ (kV) and $\beta$ (mrad). Set these once; they apply to every edge.
2. **Edge rows** — one row per element: *Element*, *Shell* (K / L), *Onset (eV)*, and the *Signal window* width $\Delta$ (eV). Add a row per element you want to quantify.
3. **Compute / Export** — runs the quantification and shows the at% table.

For each edge you add, the dialog auto-fills the **pre-edge background window** as $[\text{onset} - 54,\ \text{onset} - 4]$ — a 50-eV window ending 4 eV below the onset. This is a sensible default; widen or shift it if the pre-edge is contaminated (see §7).

---

## 4. Worked example — TiO₂ stoichiometry at 200 kV

A core-loss spectrum from a titania region acquired at $E_0 = 200$ kV, $\beta = 10$ mrad. Two edges are present: Ti-L₂,₃ (456 eV) and O-K (532 eV).

1. **Beam settings:** $E_0 = 200$, $\beta = 10$.
2. **Edge rows:**

   | Element | Shell | Onset (eV) | Δ (eV) | Pre-edge (auto) |
   |---|---|---|---|---|
   | Ti | L | 456 | 100 | [402, 452] |
   | O  | K | 532 | 80  | [478, 528] |

   Notice the Ti window ($\Delta = 100$) is deliberately wide so it integrates *past* the L₃/L₂ white lines — the hydrogenic model has no white lines, so a short window over the sharp peaks would bias the ratio (see §7).

3. **Compute.** The table fills in:

   | Element | at% | I (counts·eV) | σ (m²) |
   |---|---|---|---|
   | Ti | 33.4 | 1.10e4 | 9.5e-23 |
   | O  | 66.6 | 3.00e4 | 5.5e-23 |

4. **Read it.** O:Ti = 66.6 / 33.4 = **1.99** — essentially the ideal TiO₂ value of 2.0. The region is stoichiometric rutile/anatase within the model's ~15% floor.

A result of O:Ti ≈ 1.7 would suggest oxygen deficiency (TiO$_{2-x}$) — but only after you've ruled out a bad background fit and plural scattering (§7). The honest uncertainty on this number from the hydrogenic model alone is **±0.3 on the ratio**.

---

## 5. Choosing Δ and the pre-edge window

**Signal window Δ.** Trade-off: a wider $\Delta$ captures more signal (better SNR) and dilutes the missing-white-line bias, but extrapolates the power-law background further (so a poor background fit hurts more).

- **K edges (light elements: C, N, O, B):** $\Delta = 50$–100 eV. The continuum dominates; the hydrogenic shape fits well.
- **L₂,₃ edges (Ti, Fe, Mn, …):** use $\Delta \gtrsim 80$–100 eV so the window extends *well past* the white lines into the continuum. A short window ($\Delta < 30$ eV) sitting on the white lines is where the hydrogenic model is least reliable.
- Keep $\Delta$ similar between edges when you can — systematic cross-section error cancels best for chemically similar edges measured the same way.

**Pre-edge window.** The auto default $[\text{onset}-54,\ \text{onset}-4]$ is 50 eV wide and ends 4 eV below the onset. Adjust when:

- The power-law fit is unstable (fewer than ~20 channels) → make it wider.
- An *earlier* edge intrudes into the pre-edge (e.g. Ti-L tail under the O-K pre-edge) → shift it earlier or shorten it to stay clear of the intruding edge.
- A delayed-onset edge (L₂,₃) has a gentle pre-edge rise → end the window a bit further below onset.

---

## 6. Composition maps from a spectrum image

If you opened the dialog while a **spectrum image** is loaded (EELS mode on an SI dataset), the **Composition maps** button is enabled. With the same beam settings and edge rows, it runs the quantification at *every pixel* of the cube (`imaging.eels.eelsQuantifyMap`) and opens a tiled figure with one at% map per element, on a shared 0–100% colour scale.

Everything in §5 still applies — the windows you tuned on the summed spectrum are reused per pixel. Two map-specific cautions:

- **Single-pixel statistics are poor.** The summed spectrum that the at% table uses has $N_y \times N_x$ times the counts of any one pixel. Noisy pre-edge windows produce unstable per-pixel background fits; pixels with no usable signal show 0%. Spatially bin or SVD-denoise the cube first (`imaging.eelsSVD`, available from the EELS panel) before trusting pixel-level numbers.
- **Read maps as trends, not absolute values.** The hydrogenic ~10–20% cross-section floor applies everywhere; what the map adds is *relative spatial contrast* — an interface gradient, a deficient region — which is robust because the same $\sigma_X$ scales every pixel identically.

Programmatic access: the headless API returns the maps via `api.computeMaps()` / `api.getMapResult()`, with `result.atomicPercent` as an $N_y \times N_x \times M$ array.

---

## 7. Good-result vs bad-result tips

**Signs of a trustworthy number:**

- The **background fit** hugs the pre-edge data and the subtracted signal returns smoothly to ~0 well before the next edge. Inspect the residual: it should be structureless in the pre-edge window.
- The fitted power-law exponent $r$ lands in $[2, 6]$. Outside that, the fit is catching an earlier edge or absorbing noise.
- The at% matches a plausible stoichiometry, and an ELNES check (oxidation state, white-line ratio) is consistent.

**Common ways it goes wrong:**

- **Edge overlap.** Two edges closer than ~$\Delta$ apart contaminate each other (Ti-L₂,₃ at 456 and O-K at 532 are only 76 eV apart; a 100-eV Ti window runs *into* the O onset). Shorten the lower-edge window so it stops before the next onset, or quantify the overlapping pair with care.
- **Bad background fit.** A too-narrow or onset-leaking pre-edge window biases $r$ toward 0 and inflates or deflates $I_X$. This is the single most common source of a wrong ratio. Widen the window, move it earlier, or switch the background method to `exponential` in the dialog if there's a strong plural-scattering tail.
- **Plural scattering ($t/\lambda > 1$).** Thick regions distort edge shapes and onsets and inflate the apparent intensity. **Deconvolve first** with `imaging.eelsFourierLog`, then re-run the quantification on the single-scattering distribution. If you can't deconvolve, at least flag the result as suspect.
- **White-line bias on L edges.** The hydrogenic continuum omits white lines, so a short window over the sharp L₃/L₂ peaks over- or under-counts depending on the element. Use a wide window that integrates past them.
- **Wrong β.** A $\sigma$ computed at the wrong collection angle throws every ratio off through the $\ln(1+\beta^2/\theta_E^2)$ term. Read $\beta$ from the actual acquisition, not a default.
- **Wrong shell / wrong onset.** "L" here means L₂,₃ (the 2$p$ edge, occupancy 4); the dialog does not model M edges or L₁. A mistyped onset shifts the whole window.

When in doubt, the ratio of two *similar* edges (two K edges of neighbouring light elements) is far more trustworthy than the absolute at%, because the systematic cross-section error largely cancels.

---

## 8. Export

**Export ▸ CSV** from the dialog writes the at% table (element, at%, integrated intensity, cross-section, areal ratio) to a CSV file. The energy axis and integrated intensities are preserved so you can re-quantify externally or feed the numbers into a report.

You can also pull the same numbers programmatically:

```matlab
el(1) = struct('element','Ti','shell',"L",'Z',22,'onsetEV',456, ...
               'signalWindow',[456 556],'bgWindow',[402 452]);
el(2) = struct('element','O','shell',"K",'Z',8,'onsetEV',532, ...
               'signalWindow',[532 612],'bgWindow',[478 528]);
r = imaging.eels.eelsQuantify(energyAxis, spectrum, el, 200, 10);
fprintf('O:Ti = %.2f\n', r.atomicPercent(2) / r.atomicPercent(1));
```

---

## 9. Reporting template

For a methods paragraph, report:

1. **Acquisition.** $E_0$ (kV), collection semi-angle $\beta$ (mrad), dispersion (eV/channel), and $t/\lambda$ of the analysed region.
2. **Edges.** Symbol, shell, onset (eV), signal window $\Delta$ (eV), pre-edge background window, background model (power-law / exponential).
3. **Quantification.** at% per element and the derived ratio, with the **hydrogenic** cross-section model named explicitly and its ~10–20% accuracy floor acknowledged.
4. **Cross-checks.** ELNES oxidation state / white-line ratio; whether Fourier-log deconvolution was applied.

> Example: "A core-loss EELS spectrum (200 kV, $\beta = 10$ mrad, 0.25 eV/channel, $t/\lambda = 0.4$) was quantified in FermiViewer. The Ti-L₂,₃ (456 eV, $\Delta = 100$ eV) and O-K (532 eV, $\Delta = 80$ eV) edges were power-law background-subtracted over 50-eV pre-edge windows and converted to atomic fractions using hydrogenic partial cross-sections (Egerton 2011, Eq. 4.65; ~15% model accuracy). The measured O:Ti = 1.99 ± 0.3 is consistent with stoichiometric TiO₂."

---

## 10. References

- Egerton, R. F., *Electron Energy-Loss Spectroscopy in the Electron Microscope*, 3rd ed., Springer (2011). Ch. 3 (hydrogenic SIGMAK2 / SIGMAL2 cross-sections), Ch. 4.5–4.7 (quantification, Eq. 4.65).
- Egerton, R. F., "K-shell ionization cross-sections for use in microanalysis," *Ultramicroscopy* **4** (1979) 169–179.
- Leapman, R. D., Rez, P. & Mayers, D. F., "K, L, and M generalized oscillator strengths," *J. Chem. Phys.* **72** (1980) 1232–1243.

For the derivation of the quantification relation, the Bethe differential cross-section, and a full account of the hydrogenic model's approximations, see [`docs/theory/spectroscopy.md`](../theory/spectroscopy.md#hydrogenic-partial-cross-sections-and-at-quantification).
