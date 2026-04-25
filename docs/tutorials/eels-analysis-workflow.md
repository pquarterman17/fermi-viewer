# Tutorial: EELS Spectrum-Image Analysis Workflow

This tutorial walks through the complete Electron Energy-Loss Spectroscopy (EELS) workflow for a 3-D spectrum image (SI): load a Gatan DM3/DM4 datacube, align the zero-loss peak (ZLP), build a relative thickness map, background-subtract a core-loss edge, extract elemental intensity maps, fingerprint near-edge fine structure (ELNES), and quantify composition.

**Research question:** "I have an EELS spectrum image (3-D cube: $x$, $y$, energy) acquired in a STEM. How do I align the zero-loss peak, build a thickness map, extract a core-loss edge, and quantify composition?"

The physics derivations behind every formula used here (power-law backgrounds, log-ratio thickness, ionisation cross-sections, Fourier-log, Kramers-Kronig) live in [`docs/theory/spectroscopy.md`](../theory/spectroscopy.md). The electron-optics context (relativistic wavelength, convergence/collection angles, contrast transfer) is in [`docs/theory/imaging.md`](../theory/imaging.md). This tutorial focuses on the toolbox workflow.

---

## 1. Physics background in 60 seconds

An EELS spectrum from a thin specimen is a histogram of the energy lost by beam electrons that scatter inelastically in the sample. Three regimes dominate:

- **Zero-loss peak (ZLP)** near $E = 0$: electrons that passed through quasi-elastically. Its FWHM (0.3–1 eV for a cold FEG, 0.02–0.1 eV with a monochromator) sets the energy resolution.
- **Low-loss region** (0–50 eV): plasmons and inter-band transitions encode the dielectric function $\varepsilon(E) = \varepsilon_1 + i\varepsilon_2$.
- **Core-loss region** ($\gtrsim 100$ eV): element-specific ionisation edges. Above each edge onset, intensity follows approximately a power-law decay $I \propto E^{-r}$ with $r \approx 2$–6.

**Relative thickness** comes from the log-ratio estimator (Malis–Egerton):

$$\frac{t}{\lambda} = \ln\!\left(\frac{I_\mathrm{total}}{I_\mathrm{ZLP}}\right)$$

where $\lambda$ is the total inelastic mean free path. Multiplying by $\lambda$ (tabulated or computed from the Iakoubovskii or Malis formula) gives absolute thickness.

**Core-loss intensity** after power-law background removal obeys

$$I_k = N \cdot \sigma_k(\beta, \Delta) \cdot I_\mathrm{LL}$$

where $N$ is the areal density (atoms/area), $\sigma_k$ is the partial ionisation cross-section integrated over collection semi-angle $\beta$ and energy window $\Delta$, and $I_\mathrm{LL}$ is the low-loss integral (including ZLP) used to normalise against the incident intensity. Cross-section ratios turn integrated intensities into atomic ratios — the same Cliff–Lorimer bookkeeping used for EDS.

**ELNES** (energy-loss near-edge structure, the first $\sim$30 eV above an edge) reflects the local unoccupied density of states: oxidation state, coordination, and bonding. The Fe-L₃/L₂ white-line ratio, for example, jumps from $\sim$3.5 (Fe²⁺) to $\sim$5.5 (Fe³⁺).

See [`spectroscopy.md`](../theory/spectroscopy.md) for the Bethe theory derivation, hydrogenic vs Hartree–Slater cross-sections, and the full Kramers–Kronig algorithm.

---

## 2. What you need

- A **low-loss SI** (DM3 or DM4) covering roughly $-5$ to $+50$ eV so both the ZLP and the plasmons are visible. Used for alignment, the thickness map, and optional Kramers–Kronig.
- A **core-loss SI** of the same region covering the edges of interest (e.g. 650–900 eV for Fe-L₂,₃ and O-K). In drift-corrected dual-EELS mode the two are acquired simultaneously; otherwise, register them spatially after import.
- Microscope parameters (from the DM metadata or the operator's log):
  - Accelerating voltage $V_0$ (typically 80, 200, or 300 kV).
  - Convergence semi-angle $\alpha$ (mrad) — set by the C2 aperture.
  - Collection semi-angle $\beta$ (mrad) — set by the EELS entrance aperture and camera length. Needed for any absolute cross-section.
- For quantification, **$k$-factors or partial cross-sections** for the chosen edges.

If you only have a 1-D spectrum (single pixel, not a cube), the workflow still works — skip the alignment and map stages and apply the background/extraction steps directly.

---

## 3. Stage 1 — Load the data

```matlab
setupToolbox                       % run once to add packages to path

ll  = parser.importDM3('lowloss_si.dm3');
cl  = parser.importDM3('coreloss_si.dm3');    % or .dm4 — same parser family
```

Both `importDM3` and `importDM4` return the unified data struct. For a 3-D spectrum image, the cube lives in `metadata.parserSpecific.spectrumImage.cube` and the energy axis in `metadata.parserSpecific.spectrumData.energyAxis`:

```matlab
lowLossCube  = ll.metadata.parserSpecific.spectrumImage.cube;    % [Ny x Nx x nE]
lowLossE     = ll.metadata.parserSpecific.spectrumData.energyAxis;

coreLossCube = cl.metadata.parserSpecific.spectrumImage.cube;
coreLossE    = cl.metadata.parserSpecific.spectrumData.energyAxis;

[Ny, Nx, nE] = size(lowLossCube);
fprintf('Low-loss: %d x %d pixels, %d channels, %.3f eV/channel\n', ...
        Ny, Nx, nE, ...
        ll.metadata.parserSpecific.spectrumData.energyScale);
```

(For FEI/TIA `.ser` spectrum files, use `parser.importSER` instead — the struct layout is the same.)

Sanity-check with a single-pixel spectrum and a spatial-sum view:

```matlab
figure;
subplot(2,1,1);
plot(lowLossE, squeeze(lowLossCube(round(Ny/2), round(Nx/2), :)));
xlabel('Energy loss (eV)'); ylabel('Counts');
title('Low-loss: centre pixel'); xlim([-5, 50]); grid on;

subplot(2,1,2);
sumSpec = squeeze(sum(sum(coreLossCube, 1), 2));
semilogy(coreLossE, sumSpec);
xlabel('Energy loss (eV)'); ylabel('Sum counts');
title('Core-loss: spatial sum'); grid on;
```

Edges stand out as step + power-law-tail features on the semilog view. Match them against `imaging.eelsEdgeTable()` to identify which elements are present.

```matlab
edges = imaging.eelsEdgeTable();
nearBy = edges([edges.onsetEV] > 500 & [edges.onsetEV] < 900);
disp({nearBy.symbol});    % e.g. {'O-K','V-L23','Cr-L23','Mn-L23','Fe-L23', ...}
```

---

## 4. Stage 2 — Align the zero-loss peak

Drift, optics instabilities, and detector noise shift the ZLP by fractions of an eV to several eV between pixels. Unaligned data smears every downstream analysis: the thickness integral mixes ZLP counts with plasmons, the power-law fit sits at the wrong onset, and ELNES features blur.

```matlab
[lowLossAligned, shifts] = imaging.eelsAlignZLP(lowLossCube, lowLossE, ...
    Window=[-5, 5], Reference='mean');
```

The function cross-correlates each pixel spectrum (restricted to `Window`) with a reference ZLP (mean over all spatial pixels by default; use `'max'` for the brightest pixel, or pass a custom vector). The returned `shifts` is the $[N_y \times N_x]$ integer channel shift applied to each pixel.

Apply the same shifts to the core-loss cube when the two SIs were acquired simultaneously (dual-EELS) — the drift is common-mode:

```matlab
coreLossAligned = coreLossCube;
for iy = 1:Ny
    for ix = 1:Nx
        coreLossAligned(iy, ix, :) = circshift(coreLossAligned(iy, ix, :), ...
                                               shifts(iy, ix), 3);
    end
end
```

Verify alignment with a line scan across the SI. Pick a single row, plot ZLP regions before and after:

```matlab
rowIdx = round(Ny/2);
figure;
subplot(1,2,1);
imagesc(lowLossE, 1:Nx, squeeze(lowLossCube(rowIdx, :, :)));
xlim([-3, 3]); xlabel('E (eV)'); ylabel('x pixel'); title('Before align');

subplot(1,2,2);
imagesc(lowLossE, 1:Nx, squeeze(lowLossAligned(rowIdx, :, :)));
xlim([-3, 3]); xlabel('E (eV)'); ylabel('x pixel'); title('After align');
colormap(parula);
```

A properly aligned image shows the ZLP as a single vertical stripe at $E = 0$; before alignment the stripe wanders.

**Choosing the reference and window.** For noisy or plasmon-contaminated data, a `'max'` reference often gives more robust cross-correlation than `'mean'`. Shrink `Window` to $[-2, 2]$ eV when the ZLP is narrow and plasmons encroach; widen to $[-10, 10]$ when the ZLP is broad (older LaB₆ guns).

---

## 5. Stage 3 — Relative and absolute thickness map

Build the $t/\lambda$ map in one call:

```matlab
[tOverLambda, validMask] = imaging.eelsThicknessMap(lowLossAligned, lowLossE, ...
    ZLPWindow=[-3, 3], MinCounts=500);

figure;
imagesc(tOverLambda);
axis image; colorbar; title('t / \lambda');
colormap(parula);
```

The function computes $t/\lambda = \ln(I_\mathrm{total} / I_\mathrm{ZLP})$ per pixel. `ZLPWindow` should just contain the ZLP after alignment — use $[-2, 2]$ or $[-3, 3]$ eV for a cold-FEG instrument, wider for LaB₆. `MinCounts` screens out vacuum pixels (set to `NaN` in the output, `false` in `validMask`) so they don't contaminate the statistics.

**Converting to absolute thickness.** Pick a $\lambda$ estimate for your sample and voltage:

- **Iakoubovskii (2008)** — empirical, $\lambda = 106 F / \ln(2\beta E_0 / E_m)$ nm at 200 kV with $F$ a relativistic factor and $E_m$ the mean energy loss; works for most materials within $\sim$10%.
- **Malis–Egerton (1988)** — $\lambda_\mathrm{MFP} \approx 106 F / \ln(2\beta E_0 / E_m)$ with $E_m \approx 7.6\, Z_\mathrm{eff}^{0.36}$ eV; slightly less accurate for low-$Z$ but faster.

Both are given with full derivations in [`spectroscopy.md`](../theory/spectroscopy.md#inelastic-mean-free-path). For Si at 200 kV with $\beta = 10$ mrad, $\lambda \approx 110$ nm. A measured $t/\lambda = 0.5$ then corresponds to:

$$t = (t/\lambda) \cdot \lambda = 0.5 \cdot 110\;\mathrm{nm} = 55\;\mathrm{nm}$$

Worked example:

```matlab
lambda_nm = 110;                          % Si at 200 kV, beta = 10 mrad
thickness_nm = tOverLambda * lambda_nm;
figure; imagesc(thickness_nm);
axis image; colorbar;
title(sprintf('Thickness (nm)  mean = %.1f  std = %.1f', ...
              mean(thickness_nm(validMask), 'omitnan'), ...
              std(thickness_nm(validMask), 'omitnan')));
```

Regions with $t/\lambda > 1.0$ should raise a flag: plural scattering starts to distort the spectrum noticeably. Above $t/\lambda \sim 1.5$ the log-ratio estimator itself becomes biased, and you should apply Fourier-log deconvolution (Stage 8) before any quantification.

---

## 6. Stage 4 — Background-subtract a core-loss edge

Pick an edge. For this example we use Fe-L₂,₃ with onset at 708 eV (from `eelsEdgeTable`):

```matlab
edgeOnset   = 708;                         % Fe-L23 (eV)
preEdgeWin  = [650, 700];                  % ~50 eV window ending ~10 eV below onset
signalWin   = [710, 760];                  % 50 eV above onset

centrePix = squeeze(coreLossAligned(round(Ny/2), round(Nx/2), :));

[signal, background, params] = imaging.eelsBackground(coreLossE, centrePix, ...
    FitWindow=preEdgeWin, Method='powerlaw');

fprintf('Power-law fit:  A = %.3e,  r = %.2f\n', params.A, params.r);

figure;
plot(coreLossE, centrePix, 'k-', ...
     coreLossE, background, 'r--', ...
     coreLossE, signal, 'b-', 'LineWidth', 1);
xlabel('Energy loss (eV)'); ylabel('Counts');
legend('Raw', 'Power-law fit', 'Background-subtracted', 'Location','NE');
xlim([600, 800]); grid on;
title(sprintf('Fe-L_{23} edge, r = %.2f', params.r));
```

The power-law fit is done in log-log space (`polyfit` order 1 on $\log E$ vs $\log I$), so `params.A` and `params.r` come out cleanly as the fitted prefactor and exponent. Typical core-loss exponents are $r = 2$–6; outside this range the fit is probably catching an earlier edge or trying to absorb noise.

**Residuals.** Check that the residual in the pre-edge window is structureless. If you see an obvious slope, your window is too close to an underlying edge (common near the Fe-L₂,₃ pre-edge — there may be a subtle F-K or Cr-L₂,₃ contribution). Move the window earlier, or switch to `Method='exponential'` if the spectrum has a strong plural-scattering tail. For principled model comparison, wrap the fit in `fitting.curveFit` and use `fitCompare` (see the [curve-fitting tutorial](curve-fitting-workflow.md)).

---

## 7. Stage 5 — Elemental intensity map

Integrate the background-subtracted edge over `signalWin` per pixel:

```matlab
feMap = imaging.eelsExtractMap(coreLossAligned, coreLossE, signalWin, ...
    BackgroundWindow=preEdgeWin, Method='powerlaw');

figure; imagesc(feMap);
axis image; colorbar; colormap(hot);
title('Fe-L_{23} integrated intensity');
```

The result is a 2-D map in the same units as the input cube, times eV (counts · channels, or equivalently counts integrated over energy). Units cancel when you take ratios, so the absolute scale is not needed for Cliff–Lorimer quantification.

Make a second map for oxygen:

```matlab
oMap = imaging.eelsExtractMap(coreLossAligned, coreLossE, [535, 575], ...
    BackgroundWindow=[480, 525], Method='powerlaw');

figure;
subplot(1,2,1); imagesc(feMap); axis image; colorbar; title('Fe-L_{23}');
subplot(1,2,2); imagesc(oMap);  axis image; colorbar; title('O-K');
```

Overlay vs. the thickness map to separate real concentration variation from thickness-dependent intensity.

---

## 8. Stage 6 — ELNES fingerprinting (optional)

Pick a region of interest (e.g. the bright Fe pixels) and extract a high-SNR spectrum for fine-structure analysis:

```matlab
% Average spectra over a masked ROI
roi = feMap > 0.5 * max(feMap(:));
nROI = sum(roi(:));
spec = zeros(nE, 1);
coreFlat = reshape(coreLossAligned, Ny*Nx, nE);
spec = mean(coreFlat(roi(:), :), 1).';

res = imaging.eelsELNES(coreLossE, spec, ...
    EdgeOnset=708, FitWindow=[650, 700], ...
    ELNESWindow=[0, 30], Normalize=true);

figure;
plot(res.relativeEnergy, res.intensity, 'b-', 'LineWidth', 1.3);
xlabel('Energy relative to L_3 onset (eV)');
ylabel('Normalised ELNES intensity');
title('Fe-L_{23} near-edge fine structure'); grid on;
```

The Fe-L₂,₃ edge has two sharp **white lines** (L₃ at 708 eV, L₂ at 721 eV). Their integrated-intensity ratio $I(L_3)/I(L_2)$ is a workhorse Fe-oxidation-state probe:

| Compound | Formal state | $L_3/L_2$ (typical) |
|---|---|---|
| Metallic Fe | Fe⁰ | 2.0 – 3.0 |
| FeO | Fe²⁺ | 3.2 – 4.0 |
| Fe₃O₄ | mixed | 4.0 – 4.5 |
| Fe₂O₃ | Fe³⁺ | 4.5 – 5.5 |

Compute it by integrating the two white lines (after the power-law is removed):

```matlab
L3win = [706, 714];  L2win = [718, 726];
iL3 = trapz(coreLossE(coreLossE>=L3win(1) & coreLossE<=L3win(2)), ...
            spec(coreLossE>=L3win(1) & coreLossE<=L3win(2)));
iL2 = trapz(coreLossE(coreLossE>=L2win(1) & coreLossE<=L2win(2)), ...
            spec(coreLossE>=L2win(1) & coreLossE<=L2win(2)));
fprintf('L3/L2 ratio = %.2f\n', iL3/iL2);
```

Finer methods (double-arctangent continuum subtraction, second-derivative peak finding) are discussed in van Aken & Liebscher (2002) and implemented per-project; `eelsELNES` gives you the clean ELNES curve those methods start from.

---

## 9. Stage 7 — Cliff–Lorimer quantification

Cliff–Lorimer turns two (or more) integrated intensities into atomic fractions via

$$\frac{C_A}{C_B} = k_{AB}\,\frac{I_A}{I_B}$$

where $k_{AB} = k_A / k_B$ is the sensitivity ratio. For EDS, $k$-factors come from experiment; for EELS they are ratios of partial ionisation cross-sections $\sigma_k(\beta, \Delta)$ computed from a hydrogenic (Egerton) or Hartree–Slater model. Either way, the toolbox accepts a vector of $k$-factors:

```matlab
elements = {'Fe', 'O'};
maps     = {feMap, oMap};

% k-factors (example values for 200 kV, beta = 10 mrad, Delta = 50 eV):
%   k_Fe-L23 ~ 5.9,  k_O-K ~ 2.0  (Egerton 3rd ed., Appx. D — tabulate yourself
%   for the exact voltage/aperture settings; these are illustrative)
kEELS = [5.9, 2.0];

res = imaging.cliffLorimer(maps, elements, KFactors=kEELS);

figure;
subplot(1,2,1); imagesc(res.atomicPctMaps{1}); axis image; colorbar;
title('Fe at.%');
subplot(1,2,2); imagesc(res.atomicPctMaps{2}); axis image; colorbar;
title('O at.%');

fprintf('Mean composition: Fe = %.1f at%%,  O = %.1f at%%\n', ...
        res.meanAtomicPct(1), res.meanAtomicPct(2));
fprintf('Atomic ratio O/Fe = %.2f\n', ...
        res.meanAtomicPct(2) / res.meanAtomicPct(1));
```

**Worked example.** For pure Fe₂O₃ the expected O/Fe atomic ratio is $3/2 = 1.50$. A measurement returning O/Fe $= 1.48 \pm 0.05$ is consistent with hematite within one-$\sigma$; a value of 1.33 suggests magnetite (Fe₃O₄, O/Fe = $4/3$). Always combine the ratio with the ELNES $L_3/L_2$ check — stoichiometry alone can't distinguish FeO from Fe₃O₄ when the ratio falls between them.

`cliffLorimer` was originally written for EDS (where the default `imaging.edsKFactorTable` applies). For EELS, always supply your own `KFactors` computed from cross-sections at the exact $V_0$ and $\beta$ of your experiment — the table inside the toolbox is for X-ray lines, not EELS edges.

---

## 10. Stage 8 — Advanced corrections (briefly)

### Fourier-log deconvolution for plural scattering

When $t/\lambda > 1$, each measured spectrum is the Poisson superposition of single, double, triple, … scattering events. Their convolution flattens edges, shifts apparent onsets, and inflates background exponents. `imaging.eelsFourierLog` inverts this by dividing the FFT of the spectrum by the FFT of the ZLP (with a regularisation floor to control noise):

```matlab
[ssd, tL] = imaging.eelsFourierLog(lowLossE, centrePix, ...
    ZLPWindow=[-3, 3], Regularize=1e-6);
fprintf('Deconvolved t/lambda = %.3f\n', tL);
```

The output `ssd` is the single-scattering distribution, now suitable for Kramers–Kronig or quantification. Run this before Stage 4 if your thickness map shows large areas with $t/\lambda > 1$.

### Kramers–Kronig analysis of the low-loss region

With the single-scattering distribution in hand, the full complex dielectric function can be recovered:

```matlab
kk = imaging.eelsKramersKronig(lowLossE, centrePix, ...
    ZLPWindow=[-3, 3], RefractiveIndex=NaN, AccVoltage=200, ...
    CollectionAngle=10);
figure;
plot(kk.energy, kk.eps1, 'b-', kk.energy, kk.eps2, 'r-');
xlabel('Energy (eV)'); ylabel('\epsilon');
legend('\epsilon_1', '\epsilon_2');
title('Dielectric function from Kramers-Kronig');
```

This is a rich topic — see Egerton Ch. 4 and [`spectroscopy.md`](../theory/spectroscopy.md#kramers-kronig-analysis) for the sum-rule derivation and the delicate issue of absolute normalisation. In practice you need either a known refractive index, a known thickness, or both to fix the overall scale.

---

## 11. Common pitfalls

- **Misaligned ZLP.** Even sub-channel drift smears the ZLP integral, biases the thickness map, and breaks the pre-edge background fit. Always run `eelsAlignZLP` before `eelsThicknessMap`; inspect the line-scan image described in Stage 2.
- **Pre-edge window too narrow or too close to the onset.** The power-law log-log fit becomes unstable with fewer than $\sim$20 channels, and an onset leak biases the exponent toward $r \to 0$. Make the window at least 30–50 eV wide and end it $\ge 5$ eV below the onset.
- **Plural scattering in thick regions.** If $t/\lambda > 1$, the extracted edge is distorted and the power-law background exponent inflates artificially. Run `eelsFourierLog` first, then repeat stages 4–7 on the single-scattering distribution.
- **Wrong cross-section model.** Hydrogenic cross-sections (Egerton SIGMAK/SIGMAL) work well for K and L₂,₃ edges of light-to-medium $Z$ elements but fail for $M$ edges and for $Z \gtrsim 30$ at L edges, where you need Hartree–Slater. Use the appropriate model for your edge; a bad $k$-factor throws the atomic ratio off by 10%–50%.
- **Forgetting the collection-angle correction.** $\sigma_k(\beta, \Delta)$ depends on $\beta$ through the generalised oscillator strength. A $k$-factor computed for $\beta = 10$ mrad does not apply to data taken at $\beta = 30$ mrad. Re-derive whenever the aperture changes.
- **Using the ZLP window as a blanket cutoff below 5 eV.** The ZLP should be integrated only over its actual FWHM plus a few channels. Integrating $[-5, +5]$ eV for a cold-FEG ZLP (FWHM $\approx 0.3$ eV) mixes low-loss plasmon intensity into $I_\mathrm{ZLP}$ and artificially depresses $t/\lambda$. Align first, then pick a window matched to the measured ZLP width.
- **Dual-EELS registration.** If the low-loss and core-loss cubes are not drift-linked at acquisition, apply separate alignments and then register the two maps by cross-correlation of the thickness map against the spatial-sum core-loss intensity — not by blindly reusing the low-loss shifts.

---

## 12. Reporting template

For a publication-ready methods paragraph, report:

1. **Microscope and acquisition.** Accelerating voltage $V_0$, convergence $\alpha$, collection $\beta$ (all in mrad), dispersion (eV/channel), dwell time, probe current, and SI dimensions ($N_y \times N_x \times n_E$).
2. **Alignment.** Cross-correlation window used for ZLP alignment; mean and std of the applied shift in channels.
3. **Thickness.** $t/\lambda$ map mean ± std over the ROI; absolute $t$ (nm) assuming $\lambda =$ (value, source — Iakoubovskii or Malis–Egerton).
4. **Edges measured.** Edge symbols, onset energies, pre-edge windows, signal integration windows, background model used.
5. **Fine structure.** ELNES features identified (e.g. Fe-$L_3/L_2$ = 4.8 ± 0.2, consistent with Fe³⁺).
6. **Quantification.** Atomic ratios with uncertainties; cross-section model (hydrogenic / Hartree–Slater) and the exact $k$-factors used.
7. **Plural-scattering correction.** Whether Fourier-log was applied and the regularisation parameter.
8. **Software.** "Analysis performed with the `quantized_matlab` toolbox (`+imaging/` package), MATLAB R202Xy."

Example reporting paragraph:

> EELS spectrum images (64 × 64 pixels, 2048 channels at 0.25 eV/channel) were acquired on a 200 kV STEM with convergence semi-angle $\alpha = 18$ mrad and collection semi-angle $\beta = 10$ mrad. ZLPs were aligned by cross-correlation over a $[-3, +3]$ eV window (mean shift 2.1 channels, std 0.8). The log-ratio thickness map gave $t/\lambda = 0.48 \pm 0.06$ over the sample region, corresponding to $t = 53 \pm 7$ nm (assuming $\lambda = 110$ nm for Fe₂O₃ at 200 kV, Iakoubovskii 2008). Fe-L₂,₃ (708 eV) and O-K (532 eV) edges were background-subtracted with a power-law fit over 50-eV pre-edge windows and integrated over 50 eV above onset. Cliff–Lorimer quantification with hydrogenic cross-sections ($k_{Fe} = 5.9$, $k_O = 2.0$) returned an atomic ratio O/Fe = 1.49 ± 0.05, consistent with α-Fe₂O₃ stoichiometry. The $L_3/L_2$ white-line ratio of 4.9 ± 0.2 independently confirmed the Fe³⁺ oxidation state.

---

## 13. References

- Egerton, R. F., *Electron Energy-Loss Spectroscopy in the Electron Microscope*, 3rd ed., Springer (2011). The definitive reference; chapters 2, 4, and 5 cover everything in this tutorial.
- Malis, T., Cheng, S. C. & Egerton, R. F., "EELS log-ratio technique for specimen-thickness measurement in the TEM," *J. Electron Microsc. Tech.* **8**, 193 (1988).
- Iakoubovskii, K., Mitsuishi, K., Nakayama, Y. & Furuya, K., "Thickness measurements with electron energy loss spectroscopy," *Microsc. Res. Tech.* **71**, 626 (2008). DOI: [10.1002/jemt.20597](https://doi.org/10.1002/jemt.20597)
- van Aken, P. A. & Liebscher, B., "Quantification of ferrous/ferric ratios in minerals: new evaluation schemes of Fe L₂,₃ electron energy-loss near-edge spectra," *Phys. Chem. Minerals* **29**, 188 (2002). DOI: [10.1007/s00269-001-0222-6](https://doi.org/10.1007/s00269-001-0222-6)
- Ahn, C. C. & Krivanek, O. L., *EELS Atlas*, Gatan / ASU HREM Facility (1983). Reference shapes for most common edges.
- Cliff, G. & Lorimer, G. W., "The quantitative analysis of thin specimens," *J. Microsc.* **103**, 203 (1975). The original EDS paper; the same algebra applies to EELS with cross-sections in place of $k$-factors.

For the underlying physics (Bethe differential cross-section, dipole approximation, Kramers–Kronig sum rules, dielectric theory), see [`docs/theory/spectroscopy.md`](../theory/spectroscopy.md). For the electron-optics background (wavelength, aperture functions, contrast transfer), see [`docs/theory/imaging.md`](../theory/imaging.md).
