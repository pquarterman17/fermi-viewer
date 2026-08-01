# Electron Spectroscopy

This document covers the physics behind the EELS (electron energy-loss spectroscopy), EDS (energy-dispersive X-ray spectroscopy), and ZAF quantification routines in the `+imaging/` package. The target reader is a graduate student or postdoc working in TEM or STEM who needs to extract quantitative information — thickness maps, dielectric functions, oxidation states, elemental compositions — from spectral data acquired alongside imaging.

Throughout this document, energies are quoted in **eV** (electron-volts) unless explicitly stated otherwise; intensities are in **counts** (photon or electron count, integrated over the dwell time per pixel) and are converted to count rates (cps) only when comparing across acquisitions. EELS spectra are referenced to the zero-loss peak (ZLP) at $E = 0$, so the energy axis can extend slightly negative. EDS spectra are referenced to the noise floor below the lowest detectable line ($\sim 0.1$ keV).

The two techniques are complementary: EELS excels for light elements ($Z < 11$), provides chemical-state information through near-edge fine structure, and yields dielectric and thickness data; EDS excels for medium-$Z$ elements, gives a robust quantitative composition with simple peak integration, and works for bulk specimens at all electron-microscope voltages.

---

## Zero-Loss Peak Alignment

### Theory

In a STEM spectrum image, each pixel has its own energy axis offset because the high-tension supply, electron source, and spectrometer all drift on the time scale of a long acquisition (minutes to hours). A 1-eV drift over a $128 \times 128$ scan is enough to wash out a $\sim 1$-eV near-edge feature when pixels are averaged. The ZLP — the unscattered electron beam at $E = 0$ — provides a per-pixel reference because it is the brightest, narrowest feature in every spectrum.

**Cross-correlation alignment.** Given a reference spectrum $r(E)$ and a measured spectrum $s_i(E)$ for pixel $i$, the integer shift $\Delta_i$ is found from the location of the cross-correlation maximum:

$$\Delta_i = \arg\max_\tau \sum_{E \in W} s_i(E + \tau)\,r(E)$$

where $W$ is a narrow window centered on the ZLP (typically $[-20, +20]$ eV). The alignment is then applied with `circshift` along the energy dimension. Cross-correlation is robust to ZLP shape variations (asymmetric tails, slight broadening from sample interactions) because it integrates over the entire ZLP, not just its peak channel.

**Centroid alternative.** When the ZLP is well-isolated and approximately symmetric, the centroid (intensity-weighted mean position) gives a sub-pixel shift estimate:

$$\bar{E}_i = \frac{\sum_{E \in W} E\,s_i(E)}{\sum_{E \in W} s_i(E)}$$

The shift $\Delta_i = \bar{E}_i - \bar{E}_\mathrm{ref}$ can be applied via Fourier shift theorem (multiply the FFT by $e^{-i 2\pi k \Delta}$) for sub-channel registration. The trade-off: centroid is faster but biased when the ZLP has plural-scattering tails or asymmetric instrumental broadening.

**When to use which.** Use cross-correlation as the default — it is the gold standard for spectrum-image alignment. Use the centroid only when (a) you need sub-pixel accuracy and (b) you have verified the ZLP is symmetric within the alignment window (e.g., by overplotting individual pixel ZLPs).

**Sub-pixel refinement (`SubPixel=true`).** Cross-correlation as described above is evaluated only at integer channel lags, so its native precision is one channel — usually enough to register core-loss edges, but not always enough for a narrow low-loss feature (a sharp bulk plasmon, a phonon-loss peak a few channels wide). `imaging.eels.eelsAlignZLP`'s `SubPixel=true` option adds two refinements on top of the *same* cross-correlation, rather than switching to the centroid:

1. **Parabolic peak interpolation.** A parabola is fit through the correlation values at the integer peak and its two circular neighbours, $y_0, y_1, y_2$ at lags $\mathrm{pk}-1, \mathrm{pk}, \mathrm{pk}+1$, giving the standard closed-form vertex offset

   $$\delta = \frac{1}{2}\,\frac{y_0 - y_2}{y_0 - 2y_1 + y_2}, \qquad \delta \in [-0.5,\, 0.5].$$

   The fractional shift is $\Delta_i = \Delta_i^{(\mathrm{int})} - \delta$, where $\Delta_i^{(\mathrm{int})}$ is the integer shift already found from the correlation peak.

2. **FFT phase-ramp shift.** Rather than rounding $\Delta_i$ to the nearest integer for `circshift`, the fractional shift is applied exactly in the frequency domain, $\tilde s_i'(k) = \tilde s_i(k)\,e^{-i 2\pi k \Delta_i}$, then inverse-transformed — the same Fourier-shift-theorem idea as the centroid alternative above, applied here to the more shape-robust cross-correlation shift instead of a centroid.

   Because $\delta$ is clamped to $[-0.5, 0.5]$ and vanishes exactly when the correlation peak already sits on an integer lag, `SubPixel=true` reproduces the default integer-shift path whenever the true shift is integer, and only interpolates the remainder otherwise.

### Worked example

A 200 kV STEM spectrum image of a 50 nm Si film, acquired at 1024 channels with 0.05 eV/channel dispersion, shows ZLP centroid drift of $\sim 0.4$ eV across the $256 \times 256$ map. Cross-correlation with the spatial-mean ZLP as reference recovers integer shifts of $-8$ to $+8$ channels (matching the 0.4 eV drift); after alignment, the Si-$L_{2,3}$ edge at 99 eV sharpens by a factor of 2 and shows the characteristic doublet that was previously washed out.

### References

- Egerton, R.F., *Electron Energy-Loss Spectroscopy in the Electron Microscope*, 3rd ed., Springer, 2011, Ch. 4.4.
- Schaffer, B., Grogger, W., & Kothleitner, G., "Automated spatial drift correction for EFTEM image series," *Ultramicroscopy* **102** (2004) 27--36.

---

## Power-Law Background Subtraction

### Theory

Above any EELS core-loss edge, the spectrum sits on a slowly decreasing background that originates from the high-energy tail of the valence-loss continuum and from plural scattering of lower-energy edges. Empirically, this background is well described over a limited energy window (50--200 eV wide) by an inverse power law:

$$I_\mathrm{bg}(E) = A\,E^{-r}$$

where $A$ is an amplitude (counts) and $r$ is the exponent (typically $r \in [2, 6]$, increasing with $E$). The form is motivated by the energy dependence of the inelastic mean free path and the fact that core-loss edges exhibit approximately $\sigma(E) \propto E^{-r}$ tails far above threshold.

**Log-log linearization.** Taking the logarithm:

$$\ln I_\mathrm{bg} = \ln A - r \ln E$$

so a least-squares fit of $\ln I$ vs $\ln E$ in a pre-edge window $[E_1, E_2]$ recovers the slope $-r$ and intercept $\ln A$. The fitted background is then extrapolated across the full energy range and subtracted:

$$I_\mathrm{signal}(E) = I_\mathrm{meas}(E) - A\,E^{-r}$$

Negative values after subtraction (which can arise from noise) are clamped to zero in the toolbox implementation.

**Two-window method.** A more robust variant fits two adjacent pre-edge windows and uses the difference of integrals to extract $A$ and $r$ analytically. This avoids local minima in the log-log fit when the pre-edge contains a weak unrelated feature. The toolbox uses single-window log-log fitting, which is sufficient when the pre-edge window is chosen carefully (50--100 eV wide, well-isolated from neighbouring edges).

**Uncertainty propagation.** From the linear least-squares fit, the standard errors $\sigma_{\ln A}$ and $\sigma_r$ are obtained from the covariance matrix. Translating to the multiplicative amplitude:

$$\sigma_A = A \cdot \sigma_{\ln A}, \qquad \sigma_{I_\mathrm{bg}}(E) = I_\mathrm{bg}(E)\sqrt{\sigma_{\ln A}^2 + (\ln E)^2 \sigma_r^2}$$

**Caveats.** The DigitalMicrograph (DM)-style power law (`A * E^-r`) extrapolates poorly when the pre-edge window is narrow or when the spectrum has been gain-corrected with an imperfect detector flat field. Two known failure modes:

- **Narrow window**: $r$ is poorly constrained, and the extrapolated background can swing by 50% across a 200-eV signal window. Diagnostic: $r$ outside $[1.5, 6]$ is suspicious.
- **Polynomial alternative**: when the pre-edge has structure (a smaller edge or detector artifact), a low-order polynomial fit in $\log E$ vs $\log I$ space (or a 2-parameter exponential $A\,e^{bE}$) can be more robust. The exponential form is implemented as the `Method='exponential'` option.

### When to use

- All quantitative core-loss EELS analysis. The power-law subtraction is the first step before peak integration, ELNES extraction, or Fourier-log deconvolution.
- Choose the pre-edge window to be 50--100 eV wide, ending 5--10 eV before the edge onset (to avoid contamination from pre-edge peaks like the white lines of $L_{2,3}$ edges).

### References

- Egerton, R.F., *Electron Energy-Loss Spectroscopy in the Electron Microscope*, 3rd ed., Springer, 2011, Ch. 4.5.
- Verbeeck, J. & Van Aert, S., "Model based quantification of EELS spectra," *Ultramicroscopy* **101** (2004) 207--224.

---

## EELS Thickness Mapping (Log-Ratio Method)

### Theory

The probability that an electron passes through a specimen of thickness $t$ without any inelastic scattering event follows Poisson statistics with mean number of events $t/\lambda$:

$$\frac{I_0}{I_\mathrm{total}} = e^{-t/\lambda}$$

where $I_0$ is the unscattered (zero-loss) intensity, $I_\mathrm{total}$ is the total transmitted intensity (ZLP + all loss events combined), and $\lambda$ is the **total inelastic mean free path** of the specimen at the operating beam voltage. Solving for the relative thickness:

$$\boxed{\frac{t}{\lambda} = \ln\!\left(\frac{I_\mathrm{total}}{I_0}\right)}$$

This is the **Malis log-ratio method** (Malis, Cheng & Egerton, 1988). It requires only two integrals from each pixel spectrum: the ZLP integral $I_0$ over a narrow window (e.g., $[-5, +5]$ eV) and the total spectrum integral $I_\mathrm{total}$. No background fitting, no edge identification — just two sums per pixel. This makes it the fastest and most robust EELS thickness measure.

**Absolute thickness via the inelastic mean free path.** To convert $t/\lambda$ to a thickness in nanometres, $\lambda$ must be estimated. Two parametrizations are in common use:

**Iakoubovskii's empirical formula** (Iakoubovskii et al. 2008), valid at 200 kV:

$$\lambda\,[\text{nm}] = \frac{200\, F}{11 \ln\!\left(\dfrac{\theta_C^2 + \theta_E^2}{\theta_E^2}\right)}\,\left(\frac{2}{1 + \rho/\rho_0}\right)$$

where $\rho$ is the specimen mass density (g/cm$^3$), $\rho_0 = 1$ g/cm$^3$, $F$ is the relativistic factor ($\approx 0.768$ at 200 kV), $\theta_C$ is the collection semi-angle (mrad), and $\theta_E = E_p/2E_0$ with $E_p \approx 7.6\,Z_\mathrm{eff}^{0.36}$ eV the mean energy loss.

**Malis-Egerton parametrization** (Malis et al. 1988), more widely used:

$$\lambda\,[\text{nm}] = \frac{106 F (E_0/E_m)}{\ln(2\beta E_0/E_m)}$$

with $E_0$ in keV, $\beta$ the collection semi-angle (mrad), $E_m \approx 7.6 Z^{0.36}$ eV. For Si at 200 kV, $\beta = 10$ mrad: $\lambda \approx 113$ nm. So $t/\lambda = 0.43$ corresponds to $t \approx 49$ nm — a typical TEM specimen thickness.

**Error propagation.** From shot noise, $\sigma_{I_0}/I_0 \approx 1/\sqrt{I_0}$ and similarly for $I_\mathrm{total}$. The relative error on $t/\lambda$ is:

$$\sigma_{t/\lambda} = \sqrt{\frac{1}{I_0} + \frac{1}{I_\mathrm{total}}} \approx \frac{1}{\sqrt{I_0}}$$

(since $I_\mathrm{total} \gg I_0$ except in very thin specimens). For $I_0 = 10^4$ counts, $\sigma_{t/\lambda} \approx 0.01$ — excellent precision.

### Worked example

A 100 nm Si film at 200 kV, $\beta = 10$ mrad: Malis-Egerton gives $\lambda \approx 113$ nm, so $t/\lambda \approx 0.88$. The ZLP carries $e^{-0.88} \approx 41\%$ of the total transmitted intensity. A thicker region with $t = 200$ nm shows $t/\lambda \approx 1.77$ and only 17% in the ZLP — beyond $t/\lambda \sim 1$ the data become significantly contaminated by plural scattering and Fourier-log deconvolution should be applied before quantitative core-loss analysis. The rule of thumb: $t/\lambda < 0.5$ is "thin", $0.5$--$1.0$ is "useable but apply Fourier-log", $> 1$ is "too thick for quantitative EELS."

### When to use

- Mapping specimen thickness across a STEM spectrum image — useful for distinguishing genuine compositional contrast from thickness artifacts in EELS or EDS maps.
- Pre-screening a specimen region before EFTEM mapping (which fails at $t/\lambda > 1.5$).
- Estimating absolute thickness when no other geometric measurement (CBED, t-EELS-EDS cross-check) is available.

### References

- Malis, T., Cheng, S.C., & Egerton, R.F., "EELS log-ratio technique for specimen-thickness measurement in the TEM," *J. Electron Microsc. Tech.* **8** (1988) 193--200.
- Iakoubovskii, K., Mitsuishi, K., Nakayama, Y., & Furuya, K., "Thickness measurements with electron energy loss spectroscopy," *Microsc. Res. Tech.* **71** (2008) 626--631.
- Egerton, R.F., *Electron Energy-Loss Spectroscopy in the Electron Microscope*, 3rd ed., Springer, 2011, Ch. 5.1.

---

## Fourier-Log Deconvolution

### Theory

A measured low-loss EELS spectrum $J(E)$ is the convolution of the **single-scattering distribution** (SSD) $S(E)$ — what the spectrum would look like if every electron had at most one inelastic collision — with multiple-scattering replicas. For Poisson-distributed events, the relation in the energy domain is:

$$J(E) = Z(E) + S(E) + \frac{1}{2!}S \otimes S(E) + \frac{1}{3!}S \otimes S \otimes S(E) + \cdots$$

where $Z(E)$ is the zero-loss peak and $\otimes$ denotes convolution. Taking the Fourier transform $\nu \to \tilde\nu$ (energy $\to$ inverse-energy domain) the convolutions become products:

$$\tilde J = \tilde Z\left(1 + \tilde S + \frac{\tilde S^2}{2!} + \cdots\right) = \tilde Z\,e^{\tilde S}$$

so the SSD is recovered by:

$$\boxed{\tilde S = \ln\!\left(\frac{\tilde J}{\tilde Z}\right), \qquad S(E) = \mathcal{F}^{-1}[\tilde S]}$$

This is the **Fourier-log method** (Spence 1979; Egerton 2011, Ch. 4.2). It has the elegant property of returning both the SSD and $t/\lambda$ in a single pass: $t/\lambda = \tilde S(\nu = 0) - \ln(\tilde J/\tilde Z)|_{\nu=0}$ is the integral of $S$, which equals $\ln(I_\mathrm{total}/I_\mathrm{ZLP})$ — recovering the log-ratio formula.

**Regularization.** The division $\tilde J / \tilde Z$ is ill-conditioned at high frequencies $\nu$ where $|\tilde Z(\nu)| \to 0$ (the ZLP is narrow in energy, hence broad in frequency, and noise-limited at the Nyquist edge). The toolbox applies a multiplicative floor:

$$\tilde Z_\mathrm{reg}(\nu) = \max\!\left(|\tilde Z(\nu)|,\,\epsilon\,\max_\nu|\tilde Z|\right)$$

with $\epsilon = 10^{-6}$ by default. Reducing $\epsilon$ recovers more high-frequency detail in $S(E)$ but amplifies noise; increasing $\epsilon$ smooths the result. A common alternative is **Wiener filtering**, which weights the inverse by an SNR estimate.

**ZLP source.** The ZLP $Z(E)$ used in the deconvolution can either be (a) extracted from the spectrum itself by truncating $J(E)$ outside a narrow window around $E = 0$, or (b) supplied externally from a vacuum acquisition. The external ZLP is preferred when the specimen is thick enough that the measured ZLP shape is contaminated by phonon scattering or by finite spectrometer broadening that varies between vacuum and specimen acquisition.

### Caveats

- Fourier-log assumes Poisson statistics and thus a **homogeneous** specimen along the beam path. For granular specimens or interfaces along the beam direction, the assumption fails and the SSD has artifacts.
- The method does **not** work above $t/\lambda \sim 5$ where higher-order convolutions become so dense that the logarithm is numerically unstable.
- The output SSD has zero baseline only if the ZLP integral matches the total ZLP intensity exactly; small residual baselines should be subtracted before further analysis.

### When to use

- Low-loss spectra (0--50 eV) where you want to recover the intrinsic dielectric loss before applying Kramers-Kronig.
- Core-loss spectra at $t/\lambda \in [0.7, 2.0]$ where plural scattering distorts the edge shape and quantitative thickness extraction.
- As a preprocessing step before any near-edge fine-structure (ELNES) analysis on thicker specimens.

### References

- Spence, J.C.H., "The post-deconvolution problem in EELS," *Ultramicroscopy* **4** (1979) 9--12.
- Egerton, R.F., *Electron Energy-Loss Spectroscopy in the Electron Microscope*, 3rd ed., Springer, 2011, Ch. 4.2.

---

## Fourier-Ratio Deconvolution (Core-Loss)

### Theory

Above $\sim 50$ eV, a measured core-loss edge on a specimen thick enough to matter ($t/\lambda \gtrsim 0.5$) is plurally scattered by the *same* low-loss processes recorded separately in the low-loss spectrum. To leading order, the measured core-loss spectrum $J_\mathrm{core}(E)$ is the convolution of the intrinsic **single-scattering core-loss distribution** $S_\mathrm{core}(E)$ with the entire measured low-loss spectrum $J_\mathrm{low}(E)$ (which already contains the ZLP plus its own plural-scattering series):

$$J_\mathrm{core}(E) \approx S_\mathrm{core}(E) \otimes J_\mathrm{low}(E).$$

Fourier transforming turns the convolution into a product, $\tilde S_\mathrm{core} = \tilde J_\mathrm{core}/\tilde J_\mathrm{low}$ — this is the **Fourier-ratio method** (Egerton, *EELS in the Electron Microscope*, 3rd ed., §4.3; Egerton & Wang 1990), and it removes plural scattering from a core-loss edge the same way Fourier-log removes it from the low-loss spectrum itself. A bare inverse transform of that ratio is not what the toolbox returns, though: dividing by $\tilde J_\mathrm{low}$ also undoes the convolution with the **instrument response**, because the ZLP's own transform is a hidden factor inside $\tilde J_\mathrm{low}$. The naive ratio therefore has no resolution limit at all — every frequency is weighted equally, including the ones where both spectra are pure shot noise. `imaging.eels.eelsFourierRatio` **reconvolves** the ratio with the zero-loss peak's own transform $\tilde Z$ before inverting:

$$\boxed{\mathrm{SSD} = \mathcal F^{-1}\!\left[\frac{\tilde J_\mathrm{core}}{\tilde J_\mathrm{low}}\,\tilde Z\right]}$$

Multiplying by $\tilde Z$ restores the instrument's *actual* energy resolution and, at the same time, damps the noise the bare division amplified: the ZLP is the narrowest, highest-SNR feature in the whole dataset, so its transform re-imposes a physically meaningful, well-measured bandwidth limit exactly where the naive ratio was dominated by noise. This "deconvolve, then reconvolve with something well-measured" pattern reappears below in Richardson-Lucy's PSF centring and is the same logic behind Wiener-style regularised deconvolution generally.

**Phase-preserving regularisation.** As in Fourier-log, dividing by $\tilde J_\mathrm{low}$ is ill-conditioned wherever $|\tilde J_\mathrm{low}(\nu)|$ is small. The denominator's *magnitude* is floored while its *phase* is left untouched:

$$\tilde J_{\mathrm{low},\mathrm{reg}}(\nu) = \max\!\big(|\tilde J_\mathrm{low}(\nu)|,\ \epsilon\max_\nu|\tilde J_\mathrm{low}|\big)\,e^{i\arg \tilde J_\mathrm{low}(\nu)}, \qquad \epsilon = 10^{-6}\ \text{(default)},$$

identically to `eelsFourierLog`'s regularisation of $\tilde Z$. Preserving phase matters because the ratio's phase carries peak-position information; replacing the whole complex value with a constant instead of just flooring its magnitude would inject spurious energy shifts into the recovered SSD rather than just controlling noise amplitude.

**Where the reconvolution ZLP comes from.** By default $Z(E)$ is extracted from `lowLossSpectrum` itself over a narrow window (`ZLPWindow`, default $[-5, +5]$ eV), with everything outside that window zeroed; an externally measured ZLP (`ZLPRef`, e.g. a vacuum acquisition) can be supplied instead — for the same reason discussed under Fourier-log: it avoids specimen-induced ZLP broadening contaminating the very kernel meant to restore resolution.

### When to use

- Removing plural-scattering distortion from a **core-loss edge**'s shape and integrated intensity on a specimen with $t/\lambda \gtrsim 0.5$–1, before edge integration (`eelsExtractMap`), model-based fitting (`eelsFitEdges`, below), or ELNES analysis. Fourier-log (above) recovers the *low-loss* single-scattering distribution and thickness from the low-loss spectrum alone; Fourier-ratio instead uses the *entire measured low-loss spectrum* as an external point-spread function to deconvolve a separately identified **core-loss** region — the two are complementary, not interchangeable.
- Requires the core-loss and low-loss spectra to share a common, correctly registered energy axis (align both with `imaging.eels.eelsAlignZLP` first if they were not acquired simultaneously on a dual-EELS system); residual misregistration between them shows up as unphysical derivative-like ripples straddling the edge onset in the recovered SSD.
- Not a substitute for background subtraction: it removes plural-scattering distortion of the edge shape, but the ordinary pre-edge power-law background must still be fit and subtracted from the deconvolved SSD before integrating or fitting.

### References

- Egerton, R.F., *Electron Energy-Loss Spectroscopy in the Electron Microscope*, 3rd ed., Springer, 2011, Ch. 4.3.
- Egerton, R.F. & Wang, Z.L., "Fourier-ratio deconvolution techniques for electron energy-loss spectroscopy (EELS)," *Ultramicroscopy* **32** (1990) 137--148.
- Johnson, D.W. & Spence, J.C.H., "Determination of the single-scattering probability distribution from plural-scattering data," *J. Phys. D: Appl. Phys.* **7** (1974) 771--780.

---

## Richardson-Lucy Deconvolution (Poisson Maximum-Likelihood)

### Theory

Fourier-based deconvolution (Fourier-log, Fourier-ratio, above) divides spectra in the frequency domain, which implicitly treats the noise as Gaussian and frequency-independent. Real EELS spectra are **Poisson**-distributed counts, and the Richardson-Lucy (RL) algorithm is the multiplicative fixed-point iteration that maximises the Poisson likelihood of the measured spectrum $d(E)$ given a deconvolved estimate $u(E)$ convolved with a known point-spread function $p(E)$ (Richardson 1972; Lucy 1974):

$$\boxed{u_{k+1} = u_k \cdot \left[\frac{d}{u_k \otimes p} \otimes p^{\mathrm{flip}}\right]}, \qquad p^\mathrm{flip}(E) = p(-E),$$

started from $u_0 = d$ and normalised so $p$ sums to unity. Each iteration re-weights the current estimate by the ratio of the measured data to the estimate's own forward-blurred prediction, back-projected through the flipped PSF — an expectation-maximisation update that, unlike an FFT division, stays non-negative by construction (`imaging.eels.eelsRichardsonLucy` additionally floors the intermediate blurred estimate at `eps` before dividing, and clamps the final output at 0). The routine runs a **fixed** number of iterations (`Iterations`, default 15) rather than iterating to a convergence tolerance: RL has no natural stopping point, because it converges toward an increasingly noisy maximum-likelihood estimate as $k \to \infty$ (semi-convergence). More iterations sharpen real features but also amplify noise, so the iteration count is itself a de facto regularisation parameter that the user chooses for the resolution/noise trade-off of a given dataset.

**PSF centring is not optional.** `conv(..., 'same')` implicitly assumes its kernel is centred on the array midpoint. A PSF extracted as, say, an asymmetrically cropped ZLP window is peaked somewhere else in the array — and every iteration then silently shifts the *entire* deconvolved spectrum by that same channel offset, with no error, warning, or visible sign beyond edge onsets landing a few channels away from their true energies. `eelsRichardsonLucy` guards against this by circularly shifting the supplied PSF so its peak channel lands at $\lfloor N/2 \rfloor + 1$ before the first iteration (mirroring the centring rule the Python port applies via `np.roll`), and normalises it to unit sum so the iteration conserves total counts.

### When to use

- Sharpening a spectrum against a **known, well-sampled PSF** — typically the spectrum's own ZLP window, or an externally measured vacuum ZLP — when Poisson noise (low counts, short dwell times) makes the frequency-domain division of Fourier-log/Fourier-ratio noisy or unstable. RL's multiplicative, non-negativity-preserving update behaves noticeably better than a bare FFT ratio at low counts, at the cost of no closed form and a user-chosen iteration count.
- Improving energy resolution beyond the instrument's native ZLP width when a much narrower reference PSF is available (e.g. from a monochromated source or a separate vacuum measurement) — the classical EELS use case (Gloter et al. 2003).
- **Not** a substitute for Fourier-ratio's *specimen* plural-scattering removal: RL here removes *instrumental* blur given a PSF the user supplies, whereas Fourier-ratio's PSF is the specimen's own low-loss spectrum. The two solve different deconvolution problems and can be combined (RL for instrumental sharpening after Fourier-ratio for plural-scattering removal).
- Choose `Iterations` empirically: too few under-sharpens, too many amplifies noise into ringing artifacts (Gibbs-like overshoot) near sharp features. Inspect the result at a few iteration counts before committing to one for a full spectrum image.

### References

- Richardson, W.H., "Bayesian-based iterative method of image restoration," *J. Opt. Soc. Am.* **62** (1972) 55--59.
- Lucy, L.B., "An iterative technique for the rectification of observed distributions," *Astron. J.* **79** (1974) 745--754.
- Gloter, A., Douiri, A., Tencé, M., & Colliex, C., "Improving energy resolution of EELS spectra: an alternative to the monochromator solution," *Ultramicroscopy* **96** (2003) 385--400.
- Egerton, R.F., *Electron Energy-Loss Spectroscopy in the Electron Microscope*, 3rd ed., Springer, 2011, Ch. 4.3.

---

## Kramers-Kronig Analysis

### Theory

Below $\sim 50$ eV, the EELS single-scattering distribution probes the **dielectric function** $\varepsilon(E) = \varepsilon_1(E) + i\,\varepsilon_2(E)$ of the specimen via the energy-loss function (ELF):

$$\frac{dI}{dE\,d\Omega} \propto \frac{1}{\pi a_0 m_0 v^2}\,\mathrm{Im}\!\left(\frac{-1}{\varepsilon(E)}\right)\,\frac{1}{\theta^2 + \theta_E^2}$$

where $a_0$ is the Bohr radius, $m_0 v^2$ is twice the beam kinetic energy, $\theta$ is the scattering angle, and $\theta_E = E/(\gamma m_0 v^2)$ is the characteristic angle. Integrating over the spectrometer collection aperture gives the SSD as a constant times $\mathrm{Im}(-1/\varepsilon)$. The **complex dielectric function** is then recovered by Kramers-Kronig dispersion relations.

**Sum-rule normalization.** The SSD has an unknown overall scale (depending on incident current, dwell time, detector gain). The Kramers-Kronig sum rule fixes it:

$$\int_0^\infty \frac{2}{\pi E}\,\mathrm{Im}\!\left(\frac{-1}{\varepsilon(E)}\right)\,dE = 1 - \frac{1}{n^2}$$

where $n$ is the real refractive index in the optical limit ($E \to 0$). This determines the prefactor that converts the un-normalized SSD into an absolute ELF.

**Hilbert transform.** Once $\mathrm{Im}(-1/\varepsilon)$ is known, the real part $\mathrm{Re}(1/\varepsilon)$ is obtained from the Kramers-Kronig relation:

$$\mathrm{Re}\!\left(\frac{1}{\varepsilon(E)}\right) - 1 = \frac{2}{\pi}\,\mathcal{P}\!\int_0^\infty \frac{E'\,\mathrm{Im}(1/\varepsilon(E'))}{E'^2 - E^2}\,dE'$$

where $\mathcal{P}$ denotes the principal value. Numerically this is implemented as an FFT-based Hilbert transform on the symmetrically extended (even and odd) ELF. Once $1/\varepsilon = \mathrm{Re}(1/\varepsilon) + i\,\mathrm{Im}(1/\varepsilon)$ is known, inversion gives $\varepsilon = \varepsilon_1 + i\,\varepsilon_2$.

**Surface-loss correction.** At interfaces, additional plasmonic surface modes contribute to the SSD without representing the bulk dielectric. The Ritchie-Howie surface-loss correction subtracts a $1/(t E)$ term from the SSD before KK transformation. The toolbox applies this when both `Thickness` and `CollectionAngle` are supplied; otherwise the bulk-only SSD is used and surface artifacts may appear as small $\varepsilon_2$ peaks at low energy.

**Derived quantities.**

- **Optical conductivity** (S/m): $\sigma_1(E) = \varepsilon_0\,E\,\varepsilon_2(E)/\hbar$
- **Refractive index**: $n(E) = \sqrt{(|\varepsilon| + \varepsilon_1)/2}$
- **Extinction coefficient**: $k(E) = \sqrt{(|\varepsilon| - \varepsilon_1)/2}$

### Assumptions

1. **Dipole approximation**: valid for $\theta \ll \theta_E$, i.e., small collection angle. Typical $\theta_C = 10$ mrad satisfies this for $E < 50$ eV.
2. **Isotropic medium**: the ELF is assumed scalar. Anisotropic crystals (graphite, layered materials) require tensor analysis with momentum-resolved EELS.
3. **No retardation effects**: ignored Cherenkov losses; valid below the Cherenkov threshold $E < (n^2 - 1)^{1/2} c/v_e$.

### When to use

- Optical-property mapping in materials with complicated band structures (oxides, intermetallics) where ellipsometry is impractical at the relevant length scale.
- Plasmon-resonance characterization in nanoparticles and thin films.
- Cross-validation of optical-constant tables (CXRO, Palik) at energies above the UV cutoff of laboratory ellipsometers.

### References

- Egerton, R.F., *Electron Energy-Loss Spectroscopy in the Electron Microscope*, 3rd ed., Springer, 2011, Ch. 4.6.
- Ritchie, R.H. & Howie, A., "Inelastic scattering probabilities in scanning transmission electron microscopy," *Phil. Mag. A* **58** (1988) 753--767.
- Stoger-Pollach, M., "Optical properties and bandgaps from low loss EELS," *Micron* **39** (2008) 1092--1110.

---

## Core-Loss Edge Integration and Quantification

### Theory

The number of atoms of element $X$ per unit area in the analyzed region, $N_X$, is related to the integrated core-loss edge intensity $I_X$ by:

$$\boxed{N_X = \frac{I_X(\Delta, \beta)}{I_0(\beta)\,\sigma_X(\Delta, \beta)}}$$

where $\Delta$ is the energy integration window, $\beta$ is the collection semi-angle, $I_0$ is the low-loss + ZLP integral over the same $\beta$, and $\sigma_X$ is the **partial cross-section** for ionization in $\Delta$ at angles up to $\beta$. The ratio $I_X / I_0$ removes the dependence on incident current, dwell time, and detector gain.

**Partial cross-sections.** Two common models for $\sigma_X$:

- **Hydrogenic (SIGMAK, SIGMAL)**: closed-form expressions for K and L edges based on the hydrogen-like wavefunction approximation. Fast, accurate to $\sim 10\%$ for K edges of light elements (B--Ne) and L$_{2,3}$ edges of medium-Z elements.
- **Hartree-Slater (DFT-based)**: tabulated cross-sections from numerical atomic-structure calculations. More accurate ($\sim 5\%$) but requires lookup tables and interpolation. Standard in commercial EELS software (DigitalMicrograph SI, HyperSpy).

The toolbox uses a simpler **k-factor approach** (analogous to EDS): integrated edge intensities $I_X$ are converted to relative atomic concentrations using element-specific $k_X$ factors, with the ZLP-normalization absorbed into the calibration. This avoids angular integrations but requires that all measurements use a consistent $\beta$ and integration window.

**Energy window choice.** The integration window $\Delta$ above the edge onset trades off signal (larger $\Delta$ captures more counts) against background (larger $\Delta$ extrapolates the power-law background further). A standard choice is $\Delta = 50$--100 eV. For $L_{2,3}$ edges the window must include both white lines plus the broader continuum to give a stable measurement.

### Worked example

Fe-$L_{2,3}$ edge at 708 eV: pre-edge fit window $[640, 700]$ eV; signal window $[700, 800]$ eV ($\Delta = 100$ eV); $\beta = 10$ mrad. Integrated edge intensity $I_\mathrm{Fe} = 1.5 \times 10^4$ counts after background subtraction; ZLP intensity $I_0 = 5 \times 10^7$ counts; partial cross-section $\sigma_\mathrm{Fe}(100, 10) \approx 9.0 \times 10^{-22}$ cm$^2$ from the SIGMAL2 hydrogenic table. Then $N_\mathrm{Fe} = 1.5\times 10^4 / (5 \times 10^7 \times 9.0 \times 10^{-22}) \approx 3.3 \times 10^{17}$ atoms/cm$^2$ — consistent with $\sim 5$ nm of pure Fe at $n_\mathrm{Fe} = 8.5\times 10^{22}$ atoms/cm$^3$.

### When to use

- Mapping elemental concentrations from STEM-EELS spectrum images, especially for light elements ($Z < 11$) where EDS is weak.
- Cross-validating EDS quantification on the same specimen, since EELS and EDS sample different physical processes (inner-shell ionization vs. characteristic X-ray emission).
- Characterizing dilute dopants or interfacial layers below the EDS detection limit.

### References

- Egerton, R.F., *Electron Energy-Loss Spectroscopy in the Electron Microscope*, 3rd ed., Springer, 2011, Ch. 4.5--4.7.
- Egerton, R.F., "K-shell ionization cross-sections for use in microanalysis," *Ultramicroscopy* **4** (1979) 169--179.
- Leapman, R.D., Rez, P., & Mayers, D.F., "K, L, and M generalized oscillator strengths," *J. Chem. Phys.* **72** (1980) 1232--1243.

---

## Hydrogenic Partial Cross-Sections and at% Quantification

The toolbox's quantitative-EELS path (`imaging.eels.eelsQuantify` + `imaging.eels.eelsCrossSection`) closes the loop opened by the section above: it computes the partial ionisation cross-section $\sigma(\beta, \Delta)$ from a hydrogenic continuum model and divides the measured edge intensity by it to recover *relative* atomic composition (at%). This section documents that model exactly as implemented — including the places where the implementation simplifies the textbook result.

### Theory — the quantification relation

For two elements $A$ and $B$ measured in the same spectrum, under the same incident beam, the same collection semi-angle $\beta$, and each with its own integration window $\Delta$, the ratio of areal densities is (Egerton 2011, Eq. 4.65):

$$\boxed{\frac{N_A}{N_B} = \frac{I_A(\beta, \Delta_A)\,/\,\sigma_A(\beta, \Delta_A)}{I_B(\beta, \Delta_B)\,/\,\sigma_B(\beta, \Delta_B)}}$$

where $I_X$ is the **background-subtracted** core-loss intensity integrated over the window $[E_\mathrm{onset}^X,\,E_\mathrm{onset}^X + \Delta_X]$, and $\sigma_X(\beta, \Delta_X)$ is the partial ionisation cross-section integrated over the *same* angle and window. This follows directly from the single-edge relation $I_X = N_X\,\sigma_X(\beta, \Delta_X)\,I_0(\beta)$: the low-loss / zero-loss normalisation $I_0(\beta)$ is common to every element in the spectrum, so it **cancels in the ratio**. The practical consequence is that quantitative EELS gives *relative* composition for free — you never need to measure $I_0$ absolutely, calibrate the incident current, or know the dwell time. Generalising to $M$ elements, the atomic percentages are

$$\mathrm{at\%}_X = 100 \cdot \frac{I_X / \sigma_X}{\displaystyle\sum_{j=1}^{M} I_j / \sigma_j}, \qquad \sum_X \mathrm{at\%}_X = 100.$$

The implementation forms the per-element **areal ratio** $r_X = I_X / \sigma_X$ (proportional to $N_X$) and normalises by $\sum_j r_j$. Note the asymmetry between $I$ and $\sigma$: $I_X$ comes from integrating the measured spectrum, $\sigma_X$ from the model — and the two integrations **must use the same $\beta$ and the same $\Delta_X$**, or the cancellation is incomplete and the at% values are biased. The code enforces this by passing $\Delta_X = E_2 - E_1$ of the signal window into `eelsCrossSection` for every element; the user only has to keep $\beta$ fixed across the edges (which it physically is, for a single acquisition).

### Theory — the partial cross-section as implemented

`eelsCrossSection` follows Egerton's hydrogenic recipe (the "SIGMAK2 / SIGMAL2" family) but with a deliberately simplified, onset-anchored generalized oscillator strength (GOS). The differential cross-section per atom per unit energy loss, already integrated in scattering angle from $0$ to the collection semi-angle $\beta$, is

$$\frac{d\sigma}{dE} = 4\pi a_0^2 \left(\frac{R}{E}\right)\!\left(\frac{R}{T}\right) \bar{g}(E)\,\ln\!\left(1 + \frac{\beta^2}{\theta_E^2}\right),$$

where $a_0$ is the Bohr radius, $R = 13.606$ eV is the Rydberg energy, and the partial cross-section is the energy integral over the window,

$$\sigma(\beta, \Delta) = \int_{E_\mathrm{onset}}^{E_\mathrm{onset} + \Delta} \frac{d\sigma}{dE}\,dE \quad [\mathrm{m}^2].$$

**Relativistic incident kinematics.** The beam energy $E_0$ enters through the Lorentz factor and an effective non-relativistic kinetic energy $T$ built from the relativistic velocity:

$$\gamma = 1 + \frac{E_0}{m_0 c^2}, \qquad \frac{v^2}{c^2} = 1 - \frac{1}{\gamma^2}, \qquad T = \tfrac{1}{2} m_0 v^2 = \tfrac{1}{2}\,m_0 c^2\left(1 - \frac{1}{\gamma^2}\right),$$

with $m_0 c^2 = 511$ keV. The $(R/T)$ prefactor carries the familiar $\sim 1/v^2$ Bethe falloff of the cross-section with beam voltage.

**Characteristic inelastic angle and the aperture logarithm.** The angular integration out to $\beta$ produces the dipole logarithm

$$\theta_E = \frac{E}{2\gamma T} = \frac{E}{\gamma m_0 v^2}, \qquad \ln\!\left(1 + \frac{\beta^2}{\theta_E^2}\right),$$

which for $\beta \gg \theta_E$ grows as $\ln\beta$ — the well-known weak (logarithmic) dependence of inner-shell cross-sections on collection angle. This is why $\sigma$ and $I$ must share the same $\beta$: a $\sigma$ computed at $\beta = 10$ mrad does not describe data collected at $\beta = 30$ mrad.

**The onset-anchored GOS.** The dipole oscillator-strength density is taken as a smooth continuum shape that turns on at the *measured* edge onset and decays as a hydrogenic power law:

$$g(E) = \left(\frac{E}{E_\mathrm{onset}}\right)\left(\frac{E_\mathrm{onset}}{E}\right)^{s}, \qquad E \ge E_\mathrm{onset},$$

normalised by trapezoidal integration so that the integrated oscillator strength equals the shell occupancy,

$$\int_{E_\mathrm{onset}}^{\infty} \bar{g}(E)\,dE = n_\mathrm{shell}, \qquad n_K = 2, \quad n_{L_{2,3}} = 4.$$

The first factor $(E/E_\mathrm{onset})$ is a near-threshold phase-space rise; the second is the high-energy hydrogenic tail with falloff exponent $s$. The implementation uses $s \approx 3.7$ for the steeply falling **K** edge and a smaller $s \approx 2.7$ for the **delayed L$_{2,3}$** edge (whose maximum sits well above threshold, so it falls off more slowly). The normalisation integral is taken over a wide range ($E_\mathrm{onset}$ to $E_\mathrm{onset} + \max(50\Delta,\,5000\,\mathrm{eV})$) to capture essentially the full oscillator strength before truncating to the user's window.

**Where the $Z$-dependence lives.** Crucially, there is **no explicit Slater screening** and no per-element effective charge in this model. The atomic-number dependence enters *only* through the measured onset $E_\mathrm{onset}$ — via the $(R/E)$ and $(E/E_\mathrm{onset})$ factors and the placement of the integration window. A heavier element has a higher onset, which pushes $1/E$ down and shifts the window to where $g(E)$ is smaller, so $\sigma$ falls with $Z$ as it should — but the magnitude of that trend is set by the hydrogenic shape, not by a tabulated atomic calculation.

### Accuracy and when to trust it

This is a **smooth-continuum hydrogenic approximation**. It reproduces the right order of magnitude ($\sigma \sim 10^{-24}$–$10^{-22}\ \mathrm{m}^2$ for K and L$_{2,3}$ edges under typical 100–300 kV, $\beta = 5$–10 mrad, $\Delta = 50$–100 eV conditions) and the right monotonic trends ($\sigma$ falls with increasing onset/$Z$, rises with $\Delta$, rises as $\ln\beta$). What it does **not** capture:

- **No ELNES, no white lines.** The model is a featureless continuum. For $L_{2,3}$ edges of the 3$d$ transition metals — where 60–80% of the near-edge intensity is in the two spin-orbit white lines — the smooth continuum mis-estimates how much signal falls inside a short window. Use a window wide enough ($\Delta \gtrsim 50$–100 eV) to integrate *past* the white lines so that the ratio of measured-to-modelled intensity is less sensitive to the missing fine structure.
- **No solid-state effects.** Crystal field, hybridisation, and band structure are absent.
- **No Slater screening / no Hartree-Slater GOS.** Absolute cross-sections are therefore only as good as the hydrogenic shape; expect **~10–20% typical error** for K edges of light elements and L$_{2,3}$ edges of medium-$Z$ elements, larger for $M$ edges (not supported) and for $Z \gtrsim 30$ at L edges where the delayed shape and screening corrections matter more.
- **Relative, not absolute.** Because $I_0$ cancels, the model is built for **at% ratios**, not areal densities. The systematic error in any *single* $\sigma$ partially cancels in the ratio of two chemically similar edges (e.g. two K edges of neighbouring light elements), which is why the at% of O:Ti or C:N is more trustworthy than the absolute $N_X$ would be.
- **"L" means L$_{2,3}$ only.** The L$_1$ (2$s$) contribution is not modelled; the occupancy used is the 2$p$ count ($n = 4$).

Treat the hydrogenic cross-section the way you treat an EDS $k$-factor with no standard: good for ratios, good for trends across a map, good for distinguishing magnetite-like from hematite-like stoichiometry — but cross-check stoichiometry against ELNES (oxidation state) and, where ~5% accuracy is required, against a tabulated Hartree-Slater GOS (DigitalMicrograph, HyperSpy). Always **deconvolve plural scattering first** ($t/\lambda > 1$ distorts both the edge shape and the apparent intensity); see [Fourier-Log Deconvolution](#fourier-log-deconvolution).

### Worked example

Quantify the cation:anion ratio of a TiO$_2$ region at 200 kV, $\beta = 10$ mrad. The two edges are O-K (onset 532 eV, signal window $[532, 632]$, $\Delta = 100$ eV) and Ti-L$_{2,3}$ (onset 456 eV, signal window $[456, 556]$, $\Delta = 100$ eV). After power-law background subtraction over the respective pre-edge windows ($[478, 528]$ and $[402, 452]$), suppose $I_\mathrm{O} = 3.0 \times 10^4$ and $I_\mathrm{Ti} = 1.1 \times 10^4$ (counts·eV). The hydrogenic model gives $\sigma_\mathrm{O,K}(10,100) \approx 5.5 \times 10^{-23}\ \mathrm{m}^2$ and $\sigma_\mathrm{Ti,L}(10,100) \approx 9.5 \times 10^{-23}\ \mathrm{m}^2$. Then

$$r_\mathrm{O} = \frac{3.0\times 10^4}{5.5\times 10^{-23}} = 5.5\times 10^{26}, \qquad r_\mathrm{Ti} = \frac{1.1\times 10^4}{9.5\times 10^{-23}} = 1.16\times 10^{26},$$

so $\mathrm{at\%}_\mathrm{O} = 100 \cdot 5.5 / (5.5 + 1.16) = 83\%$ and $\mathrm{at\%}_\mathrm{Ti} = 17\%$, i.e. an O:Ti ratio of $\approx 4.7$ — high versus the ideal stoichiometric $2.0$. A discrepancy this large flags a likely problem (background fit catching the Ti-L tail under the O pre-edge, plural scattering, or the white-line bias above): the right response is to widen the windows, deconvolve, and re-fit — not to trust the number. A clean measurement on stoichiometric rutile should land near O:Ti $= 2.0 \pm 0.3$ (the ~15% spread being the hydrogenic-model floor).

### Spectrum-image composition maps

`imaging.eels.eelsQuantifyMap` applies the identical quantification relation at every spatial pixel of an $N_y \times N_x \times N_E$ spectrum image, producing per-pixel at% maps. Nothing in the physics changes — the cross-section $\sigma_X(\beta, \Delta)$ depends only on the edge and the optics, so it is computed **once per element** and shared by all pixels; only the background fit and edge integration are per-pixel. The background fit is vectorised: the power-law (or exponential) model is linear in log space, so all $N_y N_x$ pixels are fit simultaneously with a single least-squares solve per element (the same approach as `imaging.eels.eelsExtractMap`), rather than looping a per-pixel `polyfit`.

Two practical caveats specific to maps:

- **Per-pixel counting statistics are much worse than the summed spectrum.** A pixel's pre-edge window may contain so few counts that the power-law fit returns an extreme exponent; the routine clamps the resulting background-subtracted signal at zero and reports at% $= 0$ where no element shows signal. Spatially bin the cube (or SVD-denoise it first with `imaging.eelsSVD`) before reading quantitative numbers off single pixels.
- **The normalisation is per-pixel.** Each pixel's at% values sum to 100 independently, so thickness variations cancel pixel-by-pixel to first order — but plural scattering still distorts edge shapes wherever $t/\lambda \gtrsim 1$, and the deconvolution caveat above applies per pixel, not just to the sum spectrum.

### Counting statistics — how much can you trust an at% number?

Everything above concerns *systematic* error: how wrong the hydrogenic $\sigma$ is. It says nothing about the other half of the budget — the *statistical* error, set by how many electrons you actually counted. `imaging.eels.eelsAtomicSigma` supplies that half. `eelsQuantify` calls it automatically and returns a 1-$\sigma$ error bar per element in `result.atomicPercentSigma`, in **percentage points**, so that a composition is reported as $33.4 \pm 0.3$ at% rather than as a bare number. The propagation runs in three steps.

**Step 1 — from Poisson channels to the variance of an integral.** Each recorded channel is an independent Poisson count, so its variance equals its own value:

$$\mathrm{var}(N_k) = N_k .$$

The edge intensity is a trapezoid integral over the signal window, which can be written as a fixed linear combination of those channels,

$$I_X = \sum_k w_k N_k, \qquad w_k = \frac{E_{k+1} - E_{k-1}}{2}\ \ \text{(interior)}, \qquad w_1 = \frac{E_2 - E_1}{2}, \quad w_n = \frac{E_n - E_{n-1}}{2},$$

where the endpoint samples carry half of their single adjacent interval. These are the *exact* trapezoid weights — $\sum_k w_k y_k$ reproduces `trapz(E, y)` identically, including on a non-uniform energy axis — so no approximation enters here. Because the $N_k$ are independent, variances add in quadrature with the weights:

$$\boxed{\mathrm{var}(I_X) = \sum_k w_k^2\,N_k}$$

**Why the *gross* spectrum.** The $N_k$ above are the **gross**, pre-background-subtraction counts. Shot noise is set by the events the detector actually recorded; subtracting a fitted background removes the background's *mean*, not its *variance*. Using gross counts is exactly Egerton's leading-order net-signal variance,

$$\mathrm{var}(I_\mathrm{net}) \approx I_\mathrm{net} + I_\mathrm{bg},$$

the same approximation underlying his detection-limit expression $\mathrm{SNR} = I_\mathrm{net}/\sqrt{I_\mathrm{net} + h\,I_\mathrm{bg}}$ (Egerton 2011, Ch. 4.4). The dimensionless $h \ge 1$ there absorbs the *extra* variance contributed by extrapolating the fitted background underneath the edge; it grows as the pre-edge fit window narrows and as the extrapolation reaches further beyond it. `eelsAtomicSigma` takes $h = 1$, i.e. it treats the background as perfectly known. **The reported $\sigma$ is therefore a floor**, not a complete error bar.

For the common case of a uniform dispersion $d$ (eV/channel), $w_k = d$ except at the two ends, and the result collapses to a familiar form:

$$\frac{\sigma(I_X)}{I_X} \approx \frac{\sqrt{\sum_k N_k^\mathrm{gross}}}{\sum_k N_k^\mathrm{net}},$$

that is, $1/\sqrt{N}$ on the total counts in the window, degraded by however much background sits under the edge.

**Step 2 — through the cross-section.** For a fixed $\beta$, $\Delta$, and onset, $\sigma_X$ is a deterministic model number carrying no shot noise, so dividing by it simply rescales the variance:

$$r_X = \frac{I_X}{\sigma_X} \quad \Longrightarrow \quad \mathrm{var}(r_X) = \frac{\mathrm{var}(I_X)}{\sigma_X^2}.$$

The ~10–20% *model* error in $\sigma_X$ (previous subsection) is deliberately **not** folded in — it is a bias shared by every pixel and every repeat measurement, and quoting it as though it were noise would misrepresent both.

**Step 3 — through the at% normalisation (delta method).** With $S = \sum_j r_j$ and $f_i = r_i/S$, the at% values are $\mathrm{at\%}_i = 100\,r_i/S$, whose Jacobian with respect to the areal ratios is

$$J_{ij} = \frac{\partial}{\partial r_j}\!\left(\frac{r_i}{S}\right) = \frac{\delta_{ij} - f_i}{S}.$$

Different edges are separate counting experiments in disjoint energy windows, so $\mathrm{cov}(\mathbf{r})$ is diagonal and the delta method reduces to a single sum:

$$\boxed{\mathrm{var}(\mathrm{at\%}_i) = 100^2 \sum_j J_{ij}^2\,\mathrm{var}(r_j)}$$

Written in terms of the per-edge relative errors $\varepsilon_j = \sigma(I_j)/I_j$ — where $S$ and the cross-sections cancel — this is the form to use for a back-of-envelope estimate:

$$\sigma(\mathrm{at\%}_i) = 100\,\sqrt{\sum_j \left[(\delta_{ij} - f_i)\,f_j\,\varepsilon_j\right]^2}.$$

**The sum rule survives.** Note $\sum_i J_{ij} = (1 - \sum_i f_i)/S = 0$, so the rows and columns of the at% covariance matrix sum to zero. The $M$ error bars are *correlated*, not independent — necessarily so, since $\sum_i \mathrm{at\%}_i = 100$ holds exactly for every realisation of the noise. Never add at% error bars in quadrature as if they were independent measurements.

**Two-edge corollary.** For $M = 2$ every $|(\delta_{ij} - f_i)f_j|$ equals $f_A f_B$, so

$$\sigma(\mathrm{at\%}_A) = \sigma(\mathrm{at\%}_B) = 100\,f_A f_B \sqrt{\varepsilon_A^2 + \varepsilon_B^2}.$$

Both elements carry the *same* absolute error bar — they must, since one is $100$ minus the other. It is largest at 50:50 ($f_A f_B = 1/4$) and shrinks toward either end member. The *relative* error on a minor element does not shrink, however: $\sigma(\mathrm{at\%}_i)/\mathrm{at\%}_i = f_j\sqrt{\varepsilon_A^2 + \varepsilon_B^2} \to \sqrt{\varepsilon_A^2 + \varepsilon_B^2}$ as $f_i \to 0$, and $\varepsilon$ for a weak edge is exactly where the counting error is worst.

**Worked number.** Continue the TiO$_2$ example above (at% O $= 83$, Ti $= 17$). Suppose the gross spectrum gives relative intensity errors of $\varepsilon_\mathrm{O} = 0.6\%$ and $\varepsilon_\mathrm{Ti} = 1.1\%$ in their windows. Then

$$\sigma(\mathrm{at\%}) = 100 \times 0.83 \times 0.17 \times \sqrt{0.006^2 + 0.011^2} = 0.18\ \text{percentage points},$$

so you report **O $= 83.0 \pm 0.2$ at%, Ti $= 17.0 \pm 0.2$ at%** (1$\sigma$, counting statistics only). Set that against the ~15% hydrogenic model floor, which is $\pm 2.5$ percentage points on the Ti value: the statistical error is more than an order of magnitude smaller. That is the routine outcome for a well-exposed core-loss spectrum, and it carries the practical message — **if your at% is not precise enough, a longer exposure will not fix it.** A better cross-section, a standard, or a chemically closer edge pair will.

**When the error bar is NaN.** A non-positive or non-finite total $S$, a zero or undefined cross-section for any edge, or a signal window holding fewer than two channels yields NaN for **all** elements, not just the offending one. This is deliberate: through $S$, every at% value depends on every areal ratio, so one unknown variance makes all $M$ error bars unknown.

**What the error bar does not include.** It is a counting-statistics floor, and it is silent about:

- **Cross-section model error** (~10–20%, above) — systematic, and usually dominant.
- **Background-model bias.** $h = 1$ omits the extrapolation variance; a *wrong* power-law exponent is a bias, not noise, and no Poisson term will reveal it.
- **Plural scattering and edge overlap** — both distort $I_X$ itself.
- **Detector response.** The whole derivation assumes the spectrum is in **raw counts**. A spectrum converted to counts/s, gain-normalised, drift-corrected, or channel-binned no longer satisfies $\mathrm{var}(N) = N$, and the error bar is rescaled by whatever factor was applied. Real cameras also have DQE $< 1$, so the true variance exceeds $N$ — one more reason to read the reported $\sigma$ as a lower bound.

### When to use

- Quick cation/anion stoichiometry from a single core-loss spectrum (O:Ti, O:Fe, C:N, B:N) when EDS is weak (light elements) or unavailable.
- Relative composition trends across a region — from a 1-D spectrum (`eelsQuantify`) or as per-pixel at% maps over a spectrum image (`eelsQuantifyMap`).
- Deciding whether a composition difference between two regions is real or is dose-limited noise — compare the difference against `result.atomicPercentSigma` (`eelsAtomicSigma`).
- A first-pass sanity check before committing to a full Hartree-Slater quantification in dedicated EELS software.

### References

- Egerton, R.F., *Electron Energy-Loss Spectroscopy in the Electron Microscope*, 3rd ed., Springer, 2011, Ch. 3 (Bethe theory, hydrogenic SIGMAK2 / SIGMAL2 cross-sections), Ch. 4.4 (signal/noise ratio, detection limits, the background-extrapolation factor $h$), and Ch. 4.5–4.7 (quantification, Eq. 4.65).
- Bevington, P.R. & Robinson, D.K., *Data Reduction and Error Analysis for the Physical Sciences*, 3rd ed., McGraw-Hill, 2003, Ch. 2–3 (Poisson counting statistics, propagation of error).
- Egerton, R.F., "K-shell ionization cross-sections for use in microanalysis," *Ultramicroscopy* **4** (1979) 169–179.
- Leapman, R.D., Rez, P., & Mayers, D.F., "K, L, and M generalized oscillator strengths," *J. Chem. Phys.* **72** (1980) 1232–1243.

---

## Model-Based Multi-Edge EELS Fitting

`imaging.eels.eelsQuantify` (above) integrates one energy window per edge and divides by a separately-computed cross-section — a **sequential** approach that silently mis-assigns intensity when two edges overlap (neighbouring 3$d$ transition-metal $L_{2,3}$ edges such as Mn/Fe, adjacent rare-earth $M_{4,5}$ edges, or any pair whose onsets sit closer than the sum of their signal-window widths). `imaging.eels.eelsFitEdges` (with its per-channel building block `imaging.eels.eelsEdgeShape` and its spectrum-image companion `imaging.eels.eelsFitEdgesMap`) instead fits **one joint model to the whole spectrum**.

### Theory

The joint model is a shared power-law background plus, per element, its hydrogenic differential ionisation cross-section shape scaled by a fitted amplitude:

$$\boxed{I(E) \approx A\,E^{-r} \;+\; \sum_{X=1}^{M} a_X\,\frac{d\sigma_X}{dE}(E)}$$

where $d\sigma_X/dE$ (`eelsEdgeShape`) is the per-channel form of the same onset-anchored hydrogenic GOS used by `eelsCrossSection` two sections above,

$$\frac{d\sigma}{dE}(E) = 4\pi a_0^2\,\frac{R}{E}\,\frac{R}{T}\,\bar g(E)\,\ln\!\left(1 + \frac{\beta^2}{\theta_E^2}\right), \qquad E \ge E_\mathrm{onset},$$

normalised so $\int_{E_\mathrm{onset}}^\infty \bar g(E)\,dE$ equals the shell occupancy ($n_K = 2$, $n_{L_{2,3}} = 4$). Integrating `eelsEdgeShape`'s output with `trapz` over any window reproduces `eelsCrossSection`'s window integral to $\sim 10^{-9}$ relative — **provided the window is no wider than $\sim 100$ eV**. `eelsEdgeShape` has no window at construction time, so its normalisation grid always spans a fixed 5000 eV above onset, whereas `eelsCrossSection` sizes its own normalisation grid to $\max(50\Delta, 5000\ \mathrm{eV})$ for its window $\Delta$; the two floors coincide for $\Delta \le 100$ eV (the practical range for EELS signal windows) and diverge slightly for wider ones.

Because each shape already carries the cross-section's physical magnitude (m$^2$/eV), the fitted amplitudes are directly proportional to areal density, so

$$\mathrm{at\%}_X = 100\,\frac{a_X}{\sum_j a_j}$$

— the same at% construction as `eelsQuantify`'s $I_X/\sigma_X$ ratio, but here the "intensity" and "cross-section" are determined *simultaneously* by one fit rather than measured (integration) and computed (the cross-section model) independently. When two edges overlap, joint fitting can still separate them because their *shapes* differ (different onset, different high-energy falloff exponent $s$) even where their intensities add on top of each other — exactly the information a rectangular integration window throws away.

**Fitting algorithm (MATLAB built-ins only).** For a *fixed* background exponent $r$, the model above is linear in $(A, a_1, \ldots, a_M)$, so `eelsFitEdges` reduces the problem to a 1-D outer search over $r$ (`fminbnd`, bounded to the physically plausible range $[0.5, 8]$) wrapping an inner linear least-squares solve at each trial $r$ — a core-MATLAB substitute for the Python port's joint nonlinear `scipy.optimize.least_squares` fit. A log-log pre-edge polyfit seeds a sanity-check estimate $r_0$ (a warning fires if $|\hat r - r_0| > 3$), but that seed is deliberately **not** used to narrow `fminbnd`'s search interval, so a poor seed can never trap the search in a spurious local minimum.

The inner linear solve uses `pinv` throughout rather than `\`, because closely-spaced — overlapping, the exact case this fit targets — edge shapes routinely leave the design matrix near-collinear at some trial $r$; `pinv` returns the stable minimum-norm solution there instead of a noisy "rank deficient" warning. Non-negativity is enforced by a **one-pass active-set approximation**: any negative amplitude from the unconstrained `pinv` solve is clamped to zero and its column dropped, then the reduced system is solved once more. This is *not* iterated to full Lawson-Hanson NNLS convergence (as MATLAB's own `lsqnonneg` would give) and is *not* the exact bound-constrained solution the Python port's trust-region fit produces — a documented, deliberate simplification, adequate because the edge shapes used in practice are well-separated enough in energy that more than one column rarely needs dropping.

**What the reported uncertainty does and does not include.** Per-amplitude 1-$\sigma$ errors come from the linear sub-problem's covariance at the optimal $\hat r$, $\mathrm{cov} = \mathrm{pinv}(X^TX)\cdot\chi^2_\nu$, using the same $(M{+}1)$-column design matrix as the final solve. **This is a documented simplification relative to the Python port**: because $r$ is found by an *outer* scalar search rather than fit jointly with the amplitudes, its own uncertainty is never propagated into $\sigma(a_X)$ — the Python port gets an $r$ uncertainty "for free" from one joint nonlinear covariance matrix, and this MATLAB port does not. Treat `amplitudeSigma` as a lower bound on the true per-element uncertainty, particularly when the fitted $r$ is only loosely constrained by the pre-edge data.

**Spectrum-image companion (`eelsFitEdgesMap`).** Re-running the nonlinear $r$-search at every pixel of a spectrum image would be prohibitively slow, so `eelsFitEdgesMap` fits the **summed** spectrum once with `eelsFitEdges` to fix $r$; with $r$ fixed, the per-pixel model is linear for every pixel simultaneously, and the whole cube is solved with **one** multi-right-hand-side backslash ($[n_E \times (1{+}M)]$ design against $[n_E \times N_yN_x]$ data). There is no per-pixel active-set re-solve here — that would force a pixel loop, defeating the point of the vectorised solve — so negative edge amplitudes are simply clamped to zero post-hoc, matching the Python port's own map-fitting simplification. The background amplitude row is left unclamped in both the scalar and map routines.

### When to use

- **Overlapping edges** that a rectangular energy window cannot cleanly separate — the case `eelsQuantify`'s window-integration approach is documented to mis-assign. Common examples: neighbouring 3$d$ transition-metal $L_{2,3}$ edges, adjacent rare-earth $M_{4,5}$ edges, or any edge sitting on the extended fine structure of a lower-onset neighbour.
- As a cross-check on `eelsQuantify` even for well-separated edges: agreement between the sequential (window + $\sigma$ division) and joint (one shared model) approaches is reassuring; disagreement usually points to a background or window-choice problem in the simpler method.
- Not a substitute for ELNES analysis or a Hartree-Slater cross-section when absolute accuracy is required — the underlying shape is the same simplified onset-anchored hydrogenic model documented above, with the same $\sim$10--20% systematic floor.

### References

- Egerton, R.F., *Electron Energy-Loss Spectroscopy in the Electron Microscope*, 3rd ed., Springer, 2011, Ch. 3 (hydrogenic cross-sections) and Ch. 4.5--4.7 (quantification).
- Verbeeck, J. & Van Aert, S., "Model based quantification of EELS spectra," *Ultramicroscopy* **101** (2004) 207--224.
- Lawson, C.L. & Hanson, R.J., *Solving Least Squares Problems*, SIAM, 1995 (the active-set NNLS algorithm the one-pass clamp approximates).

---

## ELNES Fingerprinting

### Theory

The 30 eV immediately above a core-loss edge onset contains **energy-loss near-edge structure** (ELNES) — modulations that reflect the local density of unoccupied electronic states, projected onto the symmetry of the excited core hole. Per Fermi's golden rule, the transition probability is:

$$\frac{d^2\sigma}{d\Omega\,dE} \propto |\langle f | \hat H_\mathrm{int} | i\rangle|^2 \,\rho_f(E)$$

with selection rules $\Delta\ell = \pm 1$ (dipole) for small momentum transfer. ELNES is therefore complementary to XANES (X-ray absorption near-edge structure) and gives:

- **Oxidation state**: chemical shifts of the edge onset (e.g., Mn-$L_{2,3}$ at 640 eV in MnO$_2$, 642 eV in Mn$_2$O$_3$, 644 eV in Mn$_3$O$_4$).
- **Coordination**: tetrahedral vs. octahedral environments produce distinct white-line ratios and pre-edge features.
- **Bonding character**: the energy splitting of the white lines reflects crystal-field and ligand-field interactions.

**White-line ratio.** For 3$d$ transition metals, the $L_3$ peak (excitation from $2p_{3/2}$) and $L_2$ peak (from $2p_{1/2}$) are separated by spin-orbit coupling. The intensity ratio:

$$R_{L_3/L_2} = \frac{I(L_3)}{I(L_2)}$$

deviates from the statistical value of $2$ (i.e., the $2p$-state degeneracy ratio) when the $3d$ band has spin-imbalanced occupancy. Empirical calibrations relate $R$ to oxidation state for Mn, Fe, Co, Ni, Cu (Cave et al. 2006; Tan et al. 2012). For example, Fe$^{2+}$ gives $R \approx 4.5$ while Fe$^{3+}$ gives $R \approx 5.5$.

**Implementation note.** ELNES extraction in the toolbox normalizes the post-edge intensity to the **edge jump** — the difference between the intensity averaged in a 5--10 eV window above the onset and the extrapolated background at that point. This makes white-line ratios comparable across spectra with different incident currents or thicknesses.

### When to use

- Determining oxidation state in transition-metal oxides at sub-nanometre spatial resolution (impossible with XPS or XANES on a microbeam).
- Characterizing local bonding environments at grain boundaries, interfaces, or defects.
- Confirming compositional analysis with chemical-state information — e.g., distinguishing FeO vs. Fe$_2$O$_3$ when both give the same Fe-to-O atomic ratio.

### Caveats

- ELNES is qualitative without reference standards. For new materials, acquire the same edges from known references at the same beam conditions.
- Plural scattering at $t/\lambda > 0.5$ broadens ELNES features; apply Fourier-log first.
- Beam damage can alter oxidation state in seconds (especially for Mn, Cu, Ti). Use minimum-dose acquisition.

### References

- Egerton, R.F., *Electron Energy-Loss Spectroscopy in the Electron Microscope*, 3rd ed., Springer, 2011, Ch. 4.7.
- Tan, H., Verbeeck, J., Abakumov, A., & Van Tendeloo, G., "Oxidation state and chemical shift investigation in transition metal oxides by EELS," *Ultramicroscopy* **116** (2012) 24--33.
- Cave, L., Al-Sharab, J.F., Greenlee, L., Riman, R.E., & Hill, D.E., "A STEM/EELS method for mapping iron valence ratios in oxide minerals," *Micron* **37** (2006) 301--309.

---

## EDS Cliff-Lorimer Quantification

### Theory

For a thin specimen (negligible absorption and fluorescence within the foil), the ratio of characteristic X-ray intensities from elements $A$ and $B$ is proportional to the ratio of their weight fractions:

$$\boxed{\frac{C_A}{C_B} = k_{AB}\,\frac{I_A}{I_B}}$$

This is the **Cliff-Lorimer ratio method** (Cliff & Lorimer 1975). The proportionality constant $k_{AB}$ — the **Cliff-Lorimer factor** — depends on the X-ray production efficiencies, fluorescence yields, and detector responses for the two elements. It is approximately independent of specimen composition (the great practical virtue of the method), so a single calibration per voltage and detector serves for all specimens.

By convention $k_{AB}$ is decomposed as $k_{AB} = k_A / k_B$ where $k_X$ is referenced to a standard element (Si is the toolbox convention, so $k_\mathrm{Si} \equiv 1$). Then for a multi-element specimen the **normalized weight fractions** are:

$$w_i = \frac{k_i\,I_i}{\sum_j k_j\,I_j}$$

with $\sum_i w_i = 1$ enforced by construction. **Atomic fractions** follow from dividing by atomic mass and renormalizing:

$$x_i = \frac{w_i / M_i}{\sum_j w_j / M_j}$$

**k-factor sources.** The toolbox tabulates 200 kV $k$-factors from Williams & Carter (2009, Table 36.1) for common elements. They scale weakly with voltage (10--20% from 100 to 300 kV), so use the operating-voltage table when available; the built-in fallback warns when an off-200-kV voltage is requested.

### Thin-film criterion

Cliff-Lorimer assumes that **absorption and fluorescence are negligible** within the specimen volume. Quantitatively, the criterion for absorption to be ignorable is:

$$\frac{(\mu/\rho)\,\rho\,t}{\sin\alpha} < 0.1$$

where $\mu/\rho$ is the mass absorption coefficient (cm$^2$/g) of the absorbing matrix for the emitter's characteristic line, $\rho t$ is the mass-thickness (g/cm$^2$), and $\alpha$ is the X-ray take-off angle (typically 20°--35° in TEM). For a 100 nm Fe-O specimen at $\alpha = 35°$: $\mu/\rho = 1500$ cm$^2$/g (O-K absorbed by Fe), $\rho t = 8 \times 10^{-5}$ g/cm$^2$, giving $\mu\rho t/\sin\alpha \approx 0.21$ — borderline, so ZAF correction should be applied for accuracy better than $\sim 10\%$.

### Worked example

A three-element EDS map of Fe$_3$O$_4$/Si at 200 kV with a Si(Li) detector:
- $I_\mathrm{Fe} = 1.0 \times 10^4$ counts (Fe-K$\alpha$ at 6.40 keV), $k_\mathrm{Fe} = 1.21$
- $I_\mathrm{O} = 0.6 \times 10^4$ counts (O-K$\alpha$ at 0.525 keV), $k_\mathrm{O} = 1.80$
- $I_\mathrm{Si} = 0.3 \times 10^4$ counts (Si-K$\alpha$ at 1.74 keV), $k_\mathrm{Si} = 1.00$

Weight-% normalized: $w_\mathrm{Fe} = 1.21 \times 1.0\times 10^4 / (1.21 + 1.08 + 0.30)\times 10^4 = 0.467$, similarly $w_\mathrm{O} = 0.417$, $w_\mathrm{Si} = 0.116$. Atomic-% follows from dividing by $M$ (Fe:55.85, O:16.00, Si:28.09): $x_\mathrm{Fe} = 0.20$, $x_\mathrm{O} = 0.79$, $x_\mathrm{Si} = 0.07$ — close to the expected stoichiometry of magnetite with Si substrate signal.

### When to use

- Thin TEM specimens ($t < 100$ nm) where absorption corrections are small.
- Quick stoichiometry checks during STEM-EDS mapping.
- Mapping compositional gradients where the absolute accuracy is less important than the relative spatial variation.

### References

- Cliff, G. & Lorimer, G.W., "The quantitative analysis of thin specimens," *J. Microsc.* **103** (1975) 203--207.
- Williams, D.B. & Carter, C.B., *Transmission Electron Microscopy*, 2nd ed., Springer, 2009, Ch. 35--36.
- Watanabe, M. & Williams, D.B., "The quantitative analysis of thin specimens: a review of progress from the Cliff-Lorimer to the new $\zeta$-factor methods," *J. Microsc.* **221** (2006) 89--109.

---

## ZAF Correction (Bulk EDS)

### Theory

For bulk specimens (SEM-EDS or thick TEM cross-sections), three matrix effects must be corrected before the Cliff-Lorimer ratio method gives accurate weight fractions:

$$\boxed{\frac{C_A^\mathrm{true}}{C_A^\mathrm{measured}} = Z_A \cdot A_A \cdot F_A}$$

The three factors are:

**Atomic-number correction $Z$**. Heavier matrices stop incident electrons more efficiently (raising X-ray yield per incident electron) but also backscatter a larger fraction (lowering it). The net effect is parametrized as:

$$Z_i = \frac{R_i^\mathrm{unk}/S_i^\mathrm{unk}}{R_i^\mathrm{std}/S_i^\mathrm{std}}$$

where $S$ is the electron stopping power $\propto Z/(A\,E)\ln(1.166\,E/J)$ ($J$ being the mean ionization potential, $\approx 9.76\,Z + 58.5\,Z^{-0.19}$ eV per Berger-Seltzer), and $R$ is the backscatter coefficient $\propto Z^{0.5}/(1 + 0.008\,Z)$. For light elements in heavy matrices, $Z < 1$ (electron stopping reduced); for heavy elements in light matrices, $Z > 1$.

**Absorption correction $A$**. X-rays generated at depth $z$ are attenuated on their path to the detector:

$$A_i = \frac{1 - \exp(-\chi_i\,\rho z_\mathrm{max})}{\chi_i\,\rho z_\mathrm{max}}\Big/A_\mathrm{std}$$

where $\chi_i = (\mu/\rho)_i^\mathrm{matrix} / \sin\alpha$ is the absorption parameter (cm$^2$/g divided by sine of take-off angle). The $A$ correction is the dominant effect for light elements ($Z < 11$) in heavy matrices: O-K$\alpha$ at 525 eV is absorbed by Fe with $\mu/\rho \sim 4400$ cm$^2$/g, requiring $A \sim 0.5$ for a typical SEM specimen. Without it, oxygen is dramatically underestimated.

**Fluorescence correction $F$**. Characteristic X-rays from element $j$ can ionize element $i$ if $E_j > E_\mathrm{abs}^i$, producing additional element-$i$ X-rays beyond the direct beam-induced count. The Reed (1965) formula gives:

$$F_i = 1 + \sum_j \frac{C_j}{C_i}\,P_{ji}\,\frac{(\mu/\rho)_i^j}{(\mu/\rho)_j^\mathrm{tot}}\,\omega_j\,\frac{r_j - 1}{r_j}$$

where $\omega_j$ is the fluorescence yield, $r_j$ is the absorption-edge jump ratio, and $P_{ji}$ is a geometric factor. Fluorescence is typically a small correction ($F$ within a few percent of unity), exceeding 5% only in special cases like Cr-Fe steels (Fe-K$\alpha$ at 6.40 keV strongly fluoresces Cr-K$\alpha$ at 5.41 keV).

### Iterative solution

Because the corrections depend on the unknown composition (matrix mass-absorption coefficients, mean atomic number, etc.), ZAF is solved iteratively:

1. Initial guess: $C_i^{(0)} = $ Cliff-Lorimer thin-film result.
2. Compute $Z^{(n)}, A^{(n)}, F^{(n)}$ from $C_i^{(n)}$.
3. Update: $C_i^{(n+1)} = Z_i^{(n)} A_i^{(n)} F_i^{(n)} \cdot k_i I_i$, then renormalize $\sum C_i^{(n+1)} = 1$.
4. Iterate until $\max |C_i^{(n+1)} - C_i^{(n)}| < 10^{-4}$.

Convergence typically takes 3--5 iterations. The toolbox defaults to 3 iterations, which is sufficient for compositions within $\sim 30\%$ of the Cliff-Lorimer starting point.

### When ZAF vs. PAP/$\varphi(\rho z)$

ZAF assumes the X-ray production depth distribution is approximately exponential. Modern EDS analysis at low voltages ($< 10$ kV) or for large $Z$-contrast specimens uses the more accurate **$\varphi(\rho z)$ method** (Pouchou & Pichoir, the "PAP" model), which integrates an empirical depth-distribution function $\varphi(\rho z)$ to give the X-ray yield. Use ZAF when:

- Operating voltage is 15--30 kV (standard SEM-EDS conditions).
- Specimen is reasonably homogeneous on the X-ray generation scale ($\sim 1\,\mu$m).
- Required accuracy is $\sim 5\%$ relative.

Switch to PAP when accuracy below 2% is needed, when working at sub-10 kV, or when light elements are critical.

### When to use

- Bulk specimen EDS in an SEM (mounted polished sections, standardless or standards-based).
- Thick TEM specimens ($t > 200$ nm at 200 kV) where the Cliff-Lorimer thin-film criterion is violated.
- Cross-validation of TEM thin-film Cliff-Lorimer results when consistency with bulk SEM-EDS is required.

### References

- Goldstein, J.I., Newbury, D.E., Michael, J.R., Ritchie, N.W.M., Scott, J.H.J., & Joy, D.C., *Scanning Electron Microscopy and X-Ray Microanalysis*, 4th ed., Springer, 2018, Ch. 19.
- Reed, S.J.B., "Characteristic fluorescence corrections in electron-probe microanalysis," *Brit. J. Appl. Phys.* **16** (1965) 913--926.
- Heinrich, K.F.J. & Newbury, D.E. (eds.), *Electron Probe Quantitation*, Plenum, 1991.
- Pouchou, J.-L. & Pichoir, F., "Quantitative analysis of homogeneous or stratified microvolumes applying the model 'PAP'," in *Electron Probe Quantitation*, eds. Heinrich & Newbury, Plenum, 1991, pp. 31--75.

---

## Mass Absorption Coefficients

### Theory

The **mass absorption coefficient** $\mu/\rho$ (cm$^2$/g) parametrizes the photoelectric attenuation of an X-ray of given energy in a given absorber material:

$$I(t) = I_0\,\exp\!\left(-\frac{\mu}{\rho}\,\rho t\right)$$

For elemental absorbers, $(\mu/\rho)(E)$ exhibits absorption edges at the binding energies of K, L, and M shells, with smooth $\propto 1/E^3$ behaviour between edges. For compounds, the Bragg additivity rule applies:

$$\left(\frac{\mu}{\rho}\right)_\mathrm{compound} = \sum_i w_i\,\left(\frac{\mu}{\rho}\right)_i$$

with $w_i$ the weight fractions.

**Heinrich empirical formula.** The toolbox uses a simplified empirical parametrization (Heinrich 1986) for X-ray energies from 0.1 to 30 keV:

$$\frac{\mu}{\rho} \approx C\,\frac{Z^4 \lambda^3}{A}$$

where $C \approx 3.2 \times 10^{-20}$ (cgs units), $Z$ and $A$ are the absorber atomic number and mass, and $\lambda = hc/E$ is the wavelength of the absorbed X-ray. This captures the gross $Z^4 / E^3$ scaling but ignores the absorption edges; for accurate work near edges (within a few hundred eV), tabulated values from CXRO or NIST FFAST should be used instead.

**Energy range of validity.** The $Z^4 \lambda^3$ scaling is accurate to $\sim 20\%$ between absorption edges in the energy range 1--20 keV — sufficient for first-order ZAF corrections on most TEM and SEM specimens. Below 1 keV (light-element K lines like O-K, N-K) the empirical formula breaks down due to outer-shell binding-energy effects; for these cases the toolbox falls back to special-case values.

### Sources

- **CXRO database** (Henke, Gullikson & Davis 1993): $\mu/\rho$ for Z=1--92 from 30 eV to 30 keV. Online at https://henke.lbl.gov/optical_constants/.
- **NIST FFAST** (Chantler 1995): updated tabulation with improved accuracy near edges; includes anomalous scattering factors.
- **Heinrich 1986**: the empirical $Z^4\lambda^3/A$ formula used here for general-purpose ZAF calculations.

### Interpolation method

Within a given absorber, $\mu/\rho$ is a smooth function of energy between absorption edges. Linear interpolation in $(\log E, \log\mu)$ space is accurate to $< 1\%$ between tabulated points. Across an absorption edge, no interpolation is meaningful; the discontinuity (jump factor 5--8) must be handled explicitly by selecting the correct branch.

### When to use

- Inside the ZAF correction loop.
- Estimating absorption corrections for the Cliff-Lorimer thin-film criterion.
- Designing EDS experiments: choosing detector geometry to minimize $\mu\rho t/\sin\alpha$ for sensitive light-element analysis.

### References

- Heinrich, K.F.J., "Mass absorption coefficients for electron probe microanalysis," in *Proc. 11th ICXOM*, ed. J.D. Brown & R.H. Packwood, Univ. Western Ontario Press, 1986, pp. 67--119.
- Henke, B.L., Gullikson, E.M., & Davis, J.C., "X-ray interactions: photoabsorption, scattering, transmission, and reflection at $E = 50$--$30000$ eV, $Z = 1$--$92$," *At. Data Nucl. Data Tables* **54** (1993) 181--342.
- Chantler, C.T., "Theoretical form factor, attenuation, and scattering tabulation for $Z = 1$--$92$ from $E = 1$--$10$ eV to $E = 0.4$--$1.0$ MeV," *J. Phys. Chem. Ref. Data* **24** (1995) 71--643.

---

## EDS Spectrum Imaging and Element Mapping

### Theory

An EDS *spectrum image* (hypercube) stores a full X-ray spectrum at every
pixel: a data array $C(y, x, k)$ of counts, where $k$ indexes energy channels
calibrated linearly as

$$E_k = a + b\,k \quad\text{(keV)},$$

with $a$ the channel-zero offset (`CalibAbs`) and $b$ the dispersion
(`CalibLin`, keV/channel). The **sum spectrum** is the integral over all
pixels, $S(k) = \sum_{y,x} C(y,x,k)$, and is the quantity displayed for the
whole field of view.

An **element map** isolates one element's spatial distribution by integrating
each pixel's spectrum over an energy window $[E_1, E_2]$ bracketing a
characteristic line:

$$M(y, x) = \sum_{k : E_1 \le E_k \le E_2} C(y, x, k).$$

This raw window sum includes the bremsstrahlung **continuum** (background). To
recover the net characteristic signal, a **linear two-window background** is
estimated from side windows just below ($[E_1 - g - w,\; E_1 - g]$) and above
($[E_2 + g,\; E_2 + g + w]$) the peak (gap $g$, width $w$), and the
interpolated continuum under the peak is subtracted:

$$
b_\text{pp}(y,x) = \tfrac{1}{2}\!\left(
  \frac{1}{n_\text{lo}}\!\!\sum_{k \in \text{lo}}\!\! C
  + \frac{1}{n_\text{hi}}\!\!\sum_{k \in \text{hi}}\!\! C
\right),
\qquad
M_\text{net}(y,x) = \max\!\Big(0,\; M(y,x) - n_\text{peak}\, b_\text{pp}(y,x)\Big),
$$

where $b_\text{pp}$ is the mean background counts *per channel* (the midpoint
of the straight line joining the two side windows) and $n_\text{peak}$ is the
number of channels in the peak window. This is the standard window-type
background used for rapid mapping; for quantitative work the Cliff-Lorimer or
ZAF routines (above) operate on extracted peak intensities.

### Characteristic line selection

The principal line energies (K$\alpha_1$, L$\alpha_1$, M$\alpha_1$) are
tabulated from Bearden (1967), cross-checked against the NIST X-ray
Transition Energies database. When the accelerating voltage $E_0$ is known,
the line family is chosen by **overvoltage** $U = E_0 / E_c$, where the
critical excitation energy (absorption edge) $E_c$ is approximated from the
line energy by a per-family factor ($E_\text{K} \approx 0.90\,E_c$,
$E_\text{L} \approx 0.80\,E_c$, $E_\text{M} \approx 0.93\,E_c$). The
highest-energy family with $U \ge 1.5$ is preferred (adequate ionisation);
if none qualifies, the most-excited family is used. This reproduces standard
practice, e.g. W and Au map on their M$\alpha$ lines at 15 kV but their
L$\alpha$ lines at 300 kV.

### Worked example

```matlab
d   = parser.importBCF('eds_map.bcf');         % LoadCube=true by default
eds = d.metadata.parserSpecific.edsData;        % .cube, .energyAxis, .elements
e   = imaging.eds.lineEnergy('Cu');             % 8.048 keV (Kα)
Cu  = imaging.eds.elementMap(eds.cube, eds.energyAxis, e-0.085, e+0.085, ...
        Background='linear');
imagesc(Cu); axis image; colormap hot;          % Cu distribution, continuum removed
```

### When to use

Window maps are for **fast, qualitative** element distribution and phase
discrimination. Always sanity-check the window against the sum spectrum so it
brackets the intended line and avoids overlaps (e.g. the classic
S K$\alpha$ / Mo L$\alpha$ / Pb M$\alpha$ overlap near 2.3 keV). For
composition, feed extracted peak intensities to `imaging.cliffLorimer`
(thin film) or `imaging.zafCorrection` (bulk).

### References

The BCF hypercube byte layout (SFS container, AACS/zlib block compression,
and the per-pixel 16-bit / 12-bit / instructive packing of `SpectrumData0`)
follows the open-source reference implementation in HyperSpy / RosettaSciIO
(`rsciio/bruker`); see refs. 23-24. Line energies: refs. 25-26.

---

## EDS Detector Energy Resolution (Fano / Fiori-Newbury Model)

### Theory

A Si(Li) or SDD detector converts each absorbed X-ray photon of energy $E$ into $N = E/\varepsilon$ electron-hole pairs, $\varepsilon = 3.85$ eV per pair in Si. If pair creation were an independent Poisson process, the relative energy resolution would scale as $1/\sqrt N$; in reality the ionisation energy is shared among competing decay channels, which **suppresses** the fluctuation below the pure-Poisson value by the **Fano factor** $F$ (Fano 1947), $F \approx 0.12$ for Si. Combined with an energy-independent electronic (preamplifier) noise term, the **Fiori-Newbury detector-resolution model** (Fiori & Newbury 1978) gives the detector's Gaussian FWHM at energy $E$ as

$$\boxed{\mathrm{FWHM}(E)^2 = \mathrm{FWHM}_\mathrm{noise}^2 + k\,F\,\varepsilon\,E}, \qquad k = \big(2\sqrt{2\ln 2}\big)^2 \approx 5.545,$$

i.e. a noise floor adding in quadrature with a Fano-limited term growing as $\sqrt E$. `imaging.eds.fanoResolution` fixes the free noise term by back-solving it so the curve passes exactly through one anchor point — by convention the Mn-K$\alpha$ line at 5.899 keV with $\mathrm{FWHM} = 130$ eV, the standard SDD/Si(Li) resolution specification:

$$\mathrm{FWHM}_\mathrm{noise}^2 = \mathrm{FWHM}_\mathrm{ref}^2 - k F \varepsilon E_\mathrm{ref}.$$

The value under the square root is clamped at zero, so energies far below the anchor (where the fitted noise term would otherwise go negative, giving a complex FWHM) instead return a small, real, physically sensible width. The Gaussian $\sigma$ follows from the usual conversion, $\sigma\,[\mathrm{keV}] = \mathrm{FWHM}\,[\mathrm{eV}]/(2\sqrt{2\ln 2})/1000$. At 2.3 keV (the S-K$\alpha$/Mo-L$\alpha$/Pb-M$\alpha$ region below) this model gives $\mathrm{FWHM} \approx 88$ eV.

**Why one width model has to serve every downstream routine.** A detector has exactly one resolution curve; every routine that needs a peak width — constrained Gaussian peak fitting, the exclusion windows for continuum fitting, the clearance test that decides whether an escape or sum peak can be resolved from a real line — must use the *same* curve, or the boundary between "resolvable" and "not resolvable" becomes inconsistent from one tool to the next. `fanoResolution` is therefore the single source of truth for peak width throughout `+imaging/+eds`: `fitPeaks` uses it as each Gaussian's fixed $\sigma$, `fitContinuum` uses it to size the peak-exclusion mask, and `predictArtifacts`/`removeArtifacts` use it both to decide whether a predicted escape/sum peak is *blocked* by a real line and to fix the width of the Gaussian used to measure or model it.

### When to use

- Anywhere a Gaussian peak width is needed from energy alone, with no fitted-width parameter to spend: constrained multi-Gaussian peak fitting, continuum peak-masking, and artifact clearance testing (below).
- Sanity-checking whether two nearby lines are close enough that a detector could never resolve them regardless of fitting method — if their separation is smaller than a few $\sigma$, only fixed-position/fixed-width fitting (not window integration, and not a free-width fit) stands a chance.
- The default Fano factor and $\varepsilon$ are for **Si**; a Ge or CdTe detector needs different values and a different anchor resolution — override `Fano`/`EpsilonEV`/`RefFwhmEV` for those.

### References

- Fiori, C.E. & Newbury, D.E., in *Scanning Electron Microscopy/1978*, Vol. I (SEM Inc., AMF O'Hare, IL, 1978) p. 401.
- Fano, U., "Ionization yield of radiations. II. The fluctuations of the number of ions," *Phys. Rev.* **72** (1947) 26--29.
- Goldstein, J.I., Newbury, D.E., Michael, J.R., Ritchie, N.W.M., Scott, J.H.J., & Joy, D.C., *Scanning Electron Microscopy and X-Ray Microanalysis*, 4th ed., Springer, 2018, Ch. 7.

---

## Constrained Multi-Gaussian EDS Peak Fitting and Quantification

### Theory

Window integration cannot separate two lines whose windows overlap — the canonical trap is S-K$\alpha$ (2.307 keV), Mo-L$\alpha$ (2.293 keV), and Pb-M$\alpha$ (2.342 keV), three lines spanning under 50 eV, well inside a single detector resolution element ($\approx 88$ eV FWHM there, previous section). `imaging.eds.fitPeaks` resolves this the same way `eelsFitEdges` resolves overlapping EELS edges: fit every requested element's peak **jointly**, with strong physical constraints that leave only the amplitudes (and a shared linear background) free:

$$\boxed{N(E) = \sum_{i=1}^{M} A_i\,\exp\!\left[-\tfrac12\left(\frac{E - E_i}{\sigma_i}\right)^2\right] + mE + c}$$

Each Gaussian's **center** $E_i$ is the element's known characteristic-line energy (`imaging.eds.lineEnergy`, overvoltage-aware for the K/L/M family) and its **width** $\sigma_i$ is the fixed Fano detector width at that energy (`imaging.eds.fanoResolution`, previous section) — nothing here is inferred from the noisy data itself. With centers and widths fixed, the model is **linear** in the remaining parameters $(A_1,\ldots,A_M, m, c)$, so the fit is a single weighted least-squares solve (`\`) against a design matrix of unit-height Gaussians plus an $[E,\,1]$ background pair — no nonlinear optimizer, no initial-guess sensitivity. Each element's **net peak area** is then the closed-form Gaussian integral,

$$\mathrm{netArea}_i = A_i\,\sigma_i\sqrt{2\pi},$$

and these areas feed `imaging.eds.cliffLorimer` exactly as a window-integrated intensity would — `imaging.eds.quantifyPeaks` is precisely this pass-through: fit peaks, then Cliff-Lorimer quantify the resulting areas.

**Optional center refinement.** A small residual energy-calibration error (a few eV) can be absorbed by letting each center wander within $\pm$`CenterTolKeV` via a *variable-projection* search: `fminsearch` adjusts only the handful of center offsets, and for every trial offset the (much larger) linear amplitude-and-background system is re-solved in closed form before scoring the weighted sum of squares. This keeps the search low-dimensional (one free parameter per element, not one per data point) while still letting the peak positions track a real miscalibration rather than absorbing it into the amplitudes.

**Weighting.** `Weights="poisson"` (channel weight $1/\max(N,1)$, an approximate counting-statistics weight) down-weights the high-count channels near a peak relative to the background, closer to how a maximum-likelihood Poisson fit would behave; the default `Weights="uniform"` treats every channel equally. (The Python port defaults the other way, to `"poisson"` — a documented difference between the two implementations, not a bug in either.)

**Non-negativity is a documented approximation, not an exact constraint.** The unconstrained weighted least-squares solve can return a negative amplitude for a weak or absent element; with no bundled bounded linear solver without the Optimization Toolbox, `fitPeaks` clamps any negative amplitude to zero *after* solving, rather than re-solving under an explicit $A_i \ge 0$ constraint. For the physically realistic case this tool targets — well-separated-or-overlapping but genuinely *positive* peaks — the clamped and truly-constrained solutions agree to numerical precision; the clamp only under-reports the covariance of a parameter sitting exactly on the zero boundary, which is why this is documented explicitly rather than left implicit.

### Worked example

Three lines separated by under 50 eV — S-K$\alpha$ (2.307 keV), Mo-L$\alpha$ (2.293 keV), and Pb-M$\alpha$ (2.342 keV) — are planted with true net areas 3000, 5000, and 2000 counts on a 4001-channel, 0–20 keV synthetic spectrum (5 eV/channel) at a 15 kV beam energy. This particular triplet only appears together at a low enough beam voltage: at 15 kV the overvoltage rule (`imaging.eds.lineEnergy`) drops Mo and Pb to their L and M families respectively, whereas at 200 kV the same rule would select Mo-K$\alpha$ (17.479 keV) and Pb-L$\alpha$ (10.551 keV) instead — three well-separated lines that no fitting method needs to disentangle. `fitPeaks(e, counts, {'S','Mo','Pb'}, BeamKV=15)` recovers all three net areas to within 5%, despite the triplet spanning less than one detector resolution element — because the joint fit never has to *decide* how to split an ambiguous window, it only has to solve a well-posed linear system whose three columns (fixed centers, fixed widths) are known in advance. Window integration applied to the same synthetic spectrum would instead report one blended "2.3 keV" intensity with no way to separate S from Mo from Pb.

### When to use

- Any spectrum with characteristic-line overlap the detector resolution cannot separate by window alone: S-K$\alpha$/Mo-L$\alpha$/Pb-M$\alpha$ near 2.3 keV, Ti-K$\beta$/V-K$\alpha$ near 4.9 keV, and any rare-earth or high-$Z$ spectrum with dense L/M line families.
- As the net-intensity source feeding `quantifyPeaks` (Cliff-Lorimer) or `zetaQuantify` (below) whenever overlaps would otherwise bias a window-integrated composition.
- Combine with `predictArtifacts`/`removeArtifacts` (next section) before trusting a fitted area for an element whose line coincides with a Si-escape or sum peak from another element in the same spectrum.

### References

- Fiori, C.E. & Newbury, D.E., in *Scanning Electron Microscopy/1978*, Vol. I (SEM Inc., AMF O'Hare, IL, 1978) p. 401.
- Goldstein, J.I., Newbury, D.E., Michael, J.R., Ritchie, N.W.M., Scott, J.H.J., & Joy, D.C., *Scanning Electron Microscopy and X-Ray Microanalysis*, 4th ed., Springer, 2018, Ch. 7.
- Cliff, G. & Lorimer, G.W., "The quantitative analysis of thin specimens," *J. Microsc.* **103** (1975) 203--207.

---

## EDS Spectral Artifacts: Escape Peaks and Pile-Up

### Theory

Two detector artifacts routinely masquerade as element lines in an EDS spectrum:

**Si escape peaks.** When an incident X-ray of energy $E$ (above the Si-K edge, 1.839 keV) photoionises a Si atom *within the detector crystal itself*, the resulting Si-K$\alpha$ fluorescence photon (1.740 keV) can escape the active volume before being reabsorbed, so the event is recorded with a reduced energy:

$$E_\mathrm{escape} = E_\mathrm{parent} - 1.740\ \mathrm{keV}.$$

**Sum (pile-up) peaks.** When two photons arrive within one pulse-processing window, the electronics cannot resolve them as separate events and records their summed energy, $E_i + E_j$ (including self-sums $2E_i$ at high count rate).

Both are predicted purely from the analysed elements' known line energies — `imaging.eds.predictArtifacts` enumerates one escape peak per parent line above the Si-K edge and every unordered pair (including self-sums) for sum peaks, then **partitions** each predicted artifact by whether it can, in principle, be resolved from a real line: an artifact is **blocked** when it falls within

$$\mathrm{ClearanceSigmas}\times(\sigma_\mathrm{artifact} + \sigma_\mathrm{line})$$

of any analysed element's own line, with both $\sigma$'s from the Fano detector-resolution model (previous section) and `ClearanceSigmas = 2.0` by default. This single flag is enough to decide how `imaging.eds.removeArtifacts` treats each artifact:

- **Free** artifacts (clear of every real line — usually the high-energy sum peaks, since that region is typically empty) are **measured**: fit as free-amplitude Gaussians at their fixed positions and Fano widths, jointly with a linear background, over the *residual* spectrum (counts with the characteristic-peak model already subtracted, i.e. `counts - fitPeaks(...).fittedCurve`) so a genuine peak underneath is not mistaken for background.
- **Blocked** artifacts cannot be separated by fitting at all — a free-amplitude Gaussian at that position would simply steal counts from the real line sitting on top of it. Blocked **escape** peaks are instead **modelled** from a fixed escape probability and the parent line's own fitted net area,

  $$I_\mathrm{escape} = \mathrm{EscapeFraction} \times I_\mathrm{parent}, \qquad \mathrm{EscapeFraction} = 0.01\ \text{(default)},$$

  and subtracted as a Gaussian of that area at the escape energy. Blocked **sum** peaks cannot be modelled this way (there is no single "parent area" to scale) and are left untouched, but reported in `.skipped` so a caller or the GUI can flag the affected region.

**The canonical trap: Cu escape sitting on Fe-K$\alpha$.** At a 20 kV beam energy, Fe-K$\alpha$ sits at 6.404 keV and Cu-K$\alpha$ at 8.048 keV. The Cu escape peak falls at $8.048 - 1.740 = 6.308$ keV — only 96 eV from Fe-K$\alpha$, well inside the $\approx 228$ eV ($2\times(\sigma_\mathrm{esc}+\sigma_\mathrm{Fe})$) clearance threshold at this energy — so `predictArtifacts` reports it **blocked**, not free. A naive fit that let a free-amplitude "Cu escape" Gaussian sit at 6.308 keV would instead absorb some of the genuine Fe-K$\alpha$ signal (or vice versa), silently biasing the Fe net area low. Because `predictArtifacts` flags this pairing automatically, the correct handling — model the Cu escape from the Cu-K$\alpha$ area and subtract it, rather than fitting it freely — happens without the analyst having to recognise the coincidence by eye.

### When to use

- Any spectrum containing an element whose K/L line lies close (within a few detector-resolution widths) to another analysed element's escape or sum-peak energy — check with `predictArtifacts` *before* trusting a fitted or window-integrated net area for either element.
- As a pre-pass ahead of `fitPeaks`/`quantifyPeaks`/`zetaQuantify` whenever the sample contains elements spanning a wide-enough energy range that self- or cross-sums fall inside another line's window (common with a Fe/Cu, Cu/Zn, or any pair separated by roughly the lower element's own line energy).
- The default `EscapeFraction = 0.01` and `ClearanceSigmas = 2.0` are typical Si(Li)/SDD values; a detector with a different escape probability (e.g. a windowless detector, or a different crystal) should recalibrate `EscapeFraction` against a measured spectrum before relying on the modelled correction.

### References

- Goldstein, J.I., Newbury, D.E., Michael, J.R., Ritchie, N.W.M., Scott, J.H.J., & Joy, D.C., *Scanning Electron Microscopy and X-Ray Microanalysis*, 4th ed., Springer, 2018, Ch. 7.
- Statham, P.J., "Limitations to accuracy in extracting characteristic line intensities from X-ray spectra," *J. Res. Natl. Inst. Stand. Technol.* **107** (2002) 531--539.

---

## Physical (Kramers) Continuum Modeling for EDS

### Theory

Bremsstrahlung (continuum) X-rays are produced whenever an incident electron is decelerated in the specimen's Coulomb field, with a photon energy anywhere from 0 up to the full beam energy $E_0$ (the Duane-Hunt limit). Kramers' classical result (Kramers 1923) gives the continuum intensity as

$$I_\mathrm{Kramers}(E) \propto \frac{E_0 - E}{E}, \qquad 0 < E < E_0,$$

diverging, in this idealised form, as $E \to 0$ and vanishing exactly at $E_0$. `imaging.eds.fitContinuum` fits a **detector-shaped** version of this,

$$\boxed{I(E) = \mathrm{amp}\,\frac{E_0-E}{E}\,\exp\!\left(-\frac{\mathrm{absorption}}{E}\right)}, \qquad 0 < E < E_0,$$

where the optional $\exp(-\mathrm{absorption}/E)$ rolloff approximates the low-energy suppression from the detector window and dead layer that keeps the bare Kramers divergence from dominating the fit; `absorption = 0` recovers pure Kramers. Both `amp` and `absorption` are recovered by an unconstrained `fminsearch` search in a positivity-guaranteeing reparametrisation, $\mathrm{amp} = e^{\theta_1}$ and $\mathrm{absorption} = \mathrm{expm1}(\theta_2^2)$: squaring $\theta_2$ makes the argument to `expm1` non-negative for *any* real $\theta_2$, and $\theta_2 = 0$ recovers `absorption = 0` exactly, so the default seed starts precisely on the pure-Kramers curve.

**Peak masking.** Characteristic peaks of the requested elements (every tabulated K/L/M line) are excluded from the fit over a window of $\pm(\mathrm{ExcludeWidthFactor}\times\mathrm{FWHM}(E))$ around each line (the same Fano detector-resolution model as peak fitting and artifact clearance), with `ExcludeWidthFactor = 3.0` by default — i.e. a $\pm 3$-FWHM (roughly $\pm 7\sigma$) exclusion window, wide enough that a characteristic peak's own tails do not pull the continuum fit. Only the remaining "continuum-only" channels are weighted into the fit (Poisson weighting, $1/\max(N,1)$, by default), so the smooth curve is fit **through** the peak regions rather than distorted by them.

**Why the linear two-window background over-subtracts.** The simple `Background='linear'` map background (see "EDS Spectrum Imaging and Element Mapping" above) interpolates a straight chord between two flanking windows. The true continuum $(E_0-E)/E$ is **convex** ($d^2I/dE^2 = 2E_0/E^3 > 0$), so it lies *below* any chord connecting two points on it — a linear interpolation therefore **overestimates** the continuum in between, and subtracting it **over-subtracts**, biasing the net peak area low (worse the steeper the low-energy rise or the narrower the peak window). `imaging.eds.elementMap(..., Background='bremsstrahlung', E0KeV=...)` fixes the continuum's **shape** to the true (pure) Kramers curve $c(E) = \max(E_0-E,0)/\max(E,\epsilon)$ and solves only its per-pixel **amplitude** in closed form — a least-squares scale of that fixed shape against the flanking windows,

$$\mathrm{amp}(y,x) = \frac{\sum_{\text{side}} C(y,x,\cdot)\,c(\cdot)}{\sum_{\text{side}} c(\cdot)^2}, \qquad \mathrm{net}(y,x) = M_\mathrm{peak}(y,x) - \mathrm{amp}(y,x)\sum_{\text{peak}} c(\cdot),$$

vectorised as one dot product over the whole map rather than a per-pixel curve fit — because the shape is fixed, this needs no `fminsearch`; only `fitContinuum`'s more general (amplitude *and* absorption both free) fit does. Tracking the correct convexity removes the systematic over-subtraction a linear chord introduces near a steep low-energy continuum rise, at the cost of requiring the beam energy $E_0$, which the linear method does not need.

### When to use

- Extracting a net characteristic peak area or map when the linear two-window background is suspected of over- or under-subtracting — particularly at low photon energy (large $(E_0-E)/E$ curvature) or for elements whose line sits close to the beam-energy cutoff (a narrow window on a steeply falling continuum).
- The background underneath `fitPeaks`'/`quantifyPeaks`'s Gaussians is a simple linear background fit jointly with the peaks, *not* this physical continuum. Use `subtractContinuum` first (on the full spectrum, with the analysed elements masked) when the bremsstrahlung curvature across the fitted range is large enough that a local linear background is a poor approximation over the peak-fitting window.
- `elementMap(..., Background='bremsstrahlung')` for element maps specifically; `fitContinuum`/`subtractContinuum` for 1-D spectra (sum spectra, ROI spectra, or a pre-pass before quantification).
- Requires a known beam energy $E_0$ strictly above the window of interest; without it, fall back to the linear two-window method.

### References

- Kramers, H.A., "On the theory of X-ray absorption and of the continuous X-ray spectrum," *Philos. Mag.* **46** (1923) 836--871.
- Goldstein, J.I., Newbury, D.E., Michael, J.R., Ritchie, N.W.M., Scott, J.H.J., & Joy, D.C., *Scanning Electron Microscopy and X-Ray Microanalysis*, 4th ed., Springer, 2018, Ch. 6.

---

## Zeta-Factor EDS Quantification

### Theory

Cliff-Lorimer (above) is built entirely from intensity *ratios* — the incident dose, detector solid angle, and acquisition time all cancel, which is its great practical convenience, but it also means Cliff-Lorimer reports composition and nothing else: no specimen thickness, and no way to correct its own absorption (which requires knowing the mass-thickness the X-rays traversed, exactly the information the ratio method discards). The **zeta-factor method** (Watanabe & Williams 2006) keeps the dose instead of cancelling it, relating each element's measured net intensity **absolutely** to mass-thickness via the total electron dose $D_e$:

$$\boxed{C_i\,\rho t = \zeta_i\,\frac{I_i}{D_e}}$$

where $\zeta_i$ (kg/m$^2$, Watanabe's SI convention) is element $i$'s zeta-factor and $D_e = I_\mathrm{beam}\tau/e$ is the number of electrons that struck the specimen during the live time $\tau$ (`imaging.eds.doseElectrons`). Summing over elements ($\sum_i C_i = 1$) gives the mass-thickness **for free**, with composition following immediately:

$$\rho t = \frac{\sum_j \zeta_j I_j}{D_e}, \qquad C_i = \frac{\zeta_i I_i}{\sum_j \zeta_j I_j}.$$

Composition and mass-thickness therefore come out of the *same* measurement simultaneously — something Cliff-Lorimer cannot do at all, since it never retains an absolute intensity scale.

**Self-consistent absorption correction.** Because $\rho t$ is now known (rather than assumed negligible, as in thin-film Cliff-Lorimer), it can drive its own thin-film absorption correction. Each element's *measured* intensity relates to its *generated* (unabsorbed) intensity through an absorption factor $A_i \ge 1$,

$$A_i = \frac{\chi_i\,\rho t}{1 - \exp(-\chi_i\,\rho t)}, \qquad \chi_i = \csc\alpha \sum_j \left(\frac{\mu}{\rho}\right)_i^j w_j,$$

with $\alpha$ the X-ray take-off angle, $(\mu/\rho)_i^j$ the mass absorption coefficient of element $i$'s line in element $j$'s matrix, and $w_j$ the (evolving) weight fraction. Because $\chi_i\rho t$ and $w_j$ both depend on the composition the correction is meant to refine, `imaging.eds.zetaQuantify` **iterates** a fixed point — generated intensity $\to$ $(w,\rho t)$ $\to$ absorption factors $A_i$ $\to$ restored generated intensity $\to$ repeat — for `NIter` passes (default 5; `NIter=0` or `Absorption=false` skips the correction entirely and returns the single-pass closed-form answer). $A_i \to 1$ wherever $|\chi_i\rho t| < 10^{-6}$ (a thin/light specimen needs no correction), matching the $x/(1-e^{-x}) \to 1$ limit as $x \to 0$.

**The k-factor bridge (`zetaFromKFactors`).** Cliff-Lorimer's $k$-factor and the zeta-factor are tied exactly, since both quantification schemes are linear in intensity: $k_{ij} = \zeta_i/\zeta_j$. Given **one** absolute zeta-factor from a real measured standard (conventionally Si, $\zeta_\mathrm{Si}$, from a foil of known mass-thickness) and the toolbox's built-in 200 kV $k$-factor table (already referenced to Si, $k_\mathrm{Si} \equiv 1$),

$$\zeta_i = k_i\,\zeta_\mathrm{Si}$$

scales the entire table into an estimated zeta-factor set. This is an estimate — rigorous zeta-factor work measures every element's $\zeta$ against real thin-film standards — but it lets a single calibration measurement unlock mass-thickness mapping for every element the k-factor table already covers.

### Worked example

Two elements, no absorption correction, hand-checkable arithmetic: $I_\mathrm{Fe} = 2000$, $I_\mathrm{O} = 1000$ counts, $\zeta_\mathrm{Fe} = 500$, $\zeta_\mathrm{O} = 1000$ kg/m$^2$, dose $D_e = 10^{10}$ electrons. Then $\zeta_\mathrm{Fe}I_\mathrm{Fe} = 10^6$ and $\zeta_\mathrm{O}I_\mathrm{O} = 10^6$, so $w_\mathrm{Fe} = w_\mathrm{O} = 0.5$ exactly and $\rho t = 2\times10^6/10^{10} = 2\times10^{-4}\ \mathrm{kg/m^2}$ ($= 20\ \mu\mathrm{g/cm^2}$). Composition is **dose-independent** by construction (both $\zeta_jI_j$ terms scale the same way with dose, so their ratio $C_i$ is unaffected), while $\rho t$ scales inversely with $D_e$ — halving the assumed dose doubles the inferred mass-thickness. With a known specimen density, `Density=...` converts $\rho t$ directly to a thickness in nm.

### When to use

- Whenever specimen **thickness or mass-thickness is itself wanted**, not just composition — zeta-factor gives both from one spectrum image, where Cliff-Lorimer gives neither.
- Thicker TEM specimens where the thin-film absorption assumption is marginal: the self-consistent absorption correction here is possible *because* zeta-factor retains the absolute intensity scale Cliff-Lorimer discards.
- Feed it net intensities from `fitPeaks`/`quantifyPeaks` (overlapping lines) after an artifact check (`predictArtifacts`/`removeArtifacts`), the same way Cliff-Lorimer consumes them — `zetaQuantify` accepts the identical `[1 x N]` scalar or `[H x W x N]` map intensity shapes.
- Requires knowing (or estimating) per-element zeta-factors and the electron dose; when neither is available and only relative composition matters, Cliff-Lorimer remains the simpler tool.

### References

- Watanabe, M. & Williams, D.B., "The quantitative analysis of thin specimens: a review of progress from the Cliff-Lorimer to the new $\zeta$-factor methods," *J. Microsc.* **221** (2006) 89--109.
- Cliff, G. & Lorimer, G.W., "The quantitative analysis of thin specimens," *J. Microsc.* **103** (1975) 203--207.
- Williams, D.B. & Carter, C.B., *Transmission Electron Microscopy*, 2nd ed., Springer, 2009, Ch. 35--36.

---

## Implementation Map

| Function | One-line description | Governing equation |
|----------|---------------------|--------------------|
| `parser.decodeBcfCube` | Decode a Bruker `SpectrumData0` packed map into a dense cube | per-pixel 16-bit / 12-bit / instructive unpacking |
| `imaging.eds.lineEnergy` | Principal K/L/M line energy with overvoltage-aware auto-selection | $U = E_0/E_c \ge 1.5$ |
| `imaging.eds.elementMap` | Energy-window integration → 2-D map with optional linear background | $M=\sum_{E_1}^{E_2} C - n_\text{peak} b_\text{pp}$ |
| `imaging.eds.extractElementMaps` | Per-element maps for a list of symbols | window = $E_\text{line} \pm \Delta$ |
| `imaging.eds.pixelSpectrum` | Single-pixel / ROI-summed / masked spectrum from a cube | $\sum_{(y,x)\in\text{ROI}} C(y,x,k)$ |
| `imaging.eelsAlignZLP` | Per-pixel ZLP cross-correlation alignment of a spectrum image, optional sub-pixel refinement | $\Delta_i = \arg\max_\tau \sum s_i(E+\tau)\,r(E)$; sub-pixel: parabolic peak fit + FFT phase-ramp shift |
| `imaging.eelsBackground` | Power-law (or exponential) pre-edge background fit and subtraction | $I_\mathrm{bg} = A\,E^{-r}$ |
| `imaging.eelsThicknessMap` | Per-pixel relative thickness via the Malis log-ratio method | $t/\lambda = \ln(I_\mathrm{total}/I_\mathrm{ZLP})$ |
| `imaging.eelsFourierLog` | Single-scattering distribution by Fourier-log deconvolution | $\tilde S = \ln(\tilde J / \tilde Z)$ |
| `imaging.eels.eelsFourierRatio` | Core-loss deconvolution using the low-loss spectrum as PSF, reconvolved with the ZLP | $\mathrm{SSD} = \mathcal F^{-1}[\tilde J_\mathrm{core}/\tilde J_\mathrm{low}\cdot\tilde Z]$ |
| `imaging.eels.eelsRichardsonLucy` | Poisson maximum-likelihood iterative deconvolution against a known, self-centring PSF | $u_{k+1}=u_k\cdot[(d/(u_k\otimes p))\otimes p^\mathrm{flip}]$ |
| `imaging.eelsKramersKronig` | Complex dielectric function $\varepsilon(E)$ from low-loss EELS | $\mathrm{Im}(-1/\varepsilon)$ + KK transform |
| `imaging.eelsExtractMap` | Core-loss edge integration with optional background subtraction | $\int_{E_1}^{E_2}[I_\mathrm{meas}(E) - I_\mathrm{bg}(E)]\,dE$ |
| `imaging.eels.eelsCrossSection` | Hydrogenic partial ionisation cross-section $\sigma(\beta, \Delta)$ (onset-anchored GOS) | $\frac{d\sigma}{dE} = 4\pi a_0^2 \frac{R}{E}\frac{R}{T}\bar{g}(E)\ln(1 + \beta^2/\theta_E^2)$ |
| `imaging.eels.eelsQuantify` | Relative atomic composition (at%) from core-loss edges | $\mathrm{at\%}_X = 100\,\frac{I_X/\sigma_X}{\sum_j I_j/\sigma_j}$ (Eq. 4.65) |
| `imaging.eels.eelsQuantifyMap` | Per-pixel at% composition maps over a spectrum image (vectorised background fit, $\sigma$ shared across pixels) | Eq. 4.65 applied per pixel |
| `imaging.eels.eelsAtomicSigma` | 1-$\sigma$ Poisson counting-statistics error on at% (percentage points), from the gross spectrum | $\mathrm{var}(\mathrm{at\%}_i) = 100^2\sum_j J_{ij}^2\,\mathrm{var}(r_j)$, $J_{ij} = (\delta_{ij} - f_i)/S$ |
| `imaging.eels.eelsEdgeShape` | Per-channel hydrogenic differential ionisation cross-section (onset-anchored GOS) | $d\sigma/dE(E)$; integrates to `eelsCrossSection` to $\sim 10^{-9}$ relative |
| `imaging.eels.eelsFitEdges` | Joint background + multi-edge fit resolving overlapping core-loss edges | $I(E)\approx A\,E^{-r}+\sum_X a_X\,d\sigma_X/dE$ |
| `imaging.eels.eelsFitEdgesMap` | Per-pixel version of eelsFitEdges ($r$ fixed from the summed spectrum) | same model; one multi-RHS backslash over all pixels |
| `imaging.eelsELNES` | Background-subtracted near-edge structure normalized to edge jump | Fermi golden rule: $d\sigma/dE \propto \rho_f(E)$ |
| `imaging.eelsSVD` | SVD/MSA decomposition of a spectrum image into eigenspectra and eigenimages | $X = U\Sigma V^T$ |
| `imaging.eelsEdgeTable` | Reference table of K, $L_{2,3}$, $M_{4,5}$ edge onsets (Egerton 2011) | --- |
| `imaging.cliffLorimer` | Thin-film EDS quantification by the Cliff-Lorimer ratio method | $w_i = k_i I_i / \sum_j k_j I_j$ |
| `imaging.edsKFactorTable` | Built-in 200 kV Cliff-Lorimer $k$-factors relative to Si | --- (lookup) |
| `imaging.edsCompositionProfile` | Bilinear-interpolated composition line profile across atomic-% maps | $x_i(s) = \mathrm{interp2}(\text{map}_i, x(s), y(s))$ |
| `imaging.massAbsorptionCoeff` | Mass absorption coefficient $\mu/\rho$ from Heinrich empirical formula | $\mu/\rho \approx C\,Z^4\lambda^3/A$ |
| `imaging.zafCorrection` | Iterative ZAF (atomic number, absorption, fluorescence) correction for bulk EDS | $C_i = Z_i A_i F_i\,k_i I_i$ (iterated) |
| `imaging.eds.fanoResolution` | Fiori-Newbury detector energy resolution (Fano-limited term + electronic noise floor) | $\mathrm{FWHM}^2 = \mathrm{FWHM}_\mathrm{noise}^2 + kF\varepsilon E$ |
| `imaging.eds.fitPeaks` | Constrained multi-Gaussian peak fit: fixed centers/Fano widths, linear amplitude+background solve | $N(E)=\sum_i A_i\,\mathcal N(E;E_i,\sigma_i) + mE+c$ |
| `imaging.eds.quantifyPeaks` | fitPeaks net areas fed unchanged into Cliff-Lorimer | pass-through to $w_i = k_i I_i/\sum_j k_j I_j$ |
| `imaging.eds.predictArtifacts` | Predict Si-escape + sum/pile-up peaks; flag which are resolvable from a real line | $E_\mathrm{esc}=E_\mathrm{parent}-1.740$ keV; blocked if within $\mathrm{ClearanceSigmas}\cdot(\sigma_a+\sigma_L)$ |
| `imaging.eds.removeArtifacts` | Measure (free) or model (blocked escapes) predicted artifacts and subtract | $I_\mathrm{esc}=\mathrm{EscapeFraction}\times I_\mathrm{parent}$ (blocked case) |
| `imaging.eds.fitContinuum` | Fit a detector-shaped Kramers continuum through masked characteristic peaks | $I(E)=\mathrm{amp}\,(E_0-E)/E\cdot e^{-\mathrm{absorption}/E}$ |
| `imaging.eds.subtractContinuum` | Background-subtract the fitted Kramers continuum | $\mathrm{net}=\mathrm{counts}-I_\mathrm{Kramers}$, clamped $\ge 0$ |
| `imaging.eds.zetaQuantify` | Zeta-factor quantification: composition + mass-thickness simultaneously, iterated absorption | $C_i\,\rho t=\zeta_i I_i/D_e$ |
| `imaging.eds.zetaFromKFactors` | Estimate zeta-factors from one absolute standard + the built-in k-factor table | $\zeta_i=k_i\,\zeta_\mathrm{Si}$ |
| `imaging.eds.doseElectrons` | Total electron dose from beam current and acquisition live time | $D_e = I\tau/e$ |

---

## Consolidated References

1. Cave, L., Al-Sharab, J.F., Greenlee, L., Riman, R.E., & Hill, D.E., "A STEM/EELS method for mapping iron valence ratios in oxide minerals," *Micron* **37** (2006) 301--309.
2. Chantler, C.T., "Theoretical form factor, attenuation, and scattering tabulation for $Z = 1$--$92$," *J. Phys. Chem. Ref. Data* **24** (1995) 71--643.
3. Cliff, G. & Lorimer, G.W., "The quantitative analysis of thin specimens," *J. Microsc.* **103** (1975) 203--207.
4. Egerton, R.F., "K-shell ionization cross-sections for use in microanalysis," *Ultramicroscopy* **4** (1979) 169--179.
5. Egerton, R.F., *Electron Energy-Loss Spectroscopy in the Electron Microscope*, 3rd ed., Springer, 2011.
6. Goldstein, J.I., Newbury, D.E., Michael, J.R., Ritchie, N.W.M., Scott, J.H.J., & Joy, D.C., *Scanning Electron Microscopy and X-Ray Microanalysis*, 4th ed., Springer, 2018.
7. Heinrich, K.F.J., "Mass absorption coefficients for electron probe microanalysis," *Proc. 11th ICXOM*, Univ. Western Ontario, 1986, pp. 67--119.
8. Heinrich, K.F.J. & Newbury, D.E. (eds.), *Electron Probe Quantitation*, Plenum, 1991.
9. Henke, B.L., Gullikson, E.M., & Davis, J.C., "X-ray interactions: photoabsorption, scattering, transmission, and reflection at $E = 50$--$30000$ eV, $Z = 1$--$92$," *At. Data Nucl. Data Tables* **54** (1993) 181--342.
10. Iakoubovskii, K., Mitsuishi, K., Nakayama, Y., & Furuya, K., "Thickness measurements with electron energy loss spectroscopy," *Microsc. Res. Tech.* **71** (2008) 626--631.
11. Leapman, R.D., Rez, P., & Mayers, D.F., "K, L, and M generalized oscillator strengths," *J. Chem. Phys.* **72** (1980) 1232--1243.
12. Malis, T., Cheng, S.C., & Egerton, R.F., "EELS log-ratio technique for specimen-thickness measurement in the TEM," *J. Electron Microsc. Tech.* **8** (1988) 193--200.
13. Pouchou, J.-L. & Pichoir, F., "Quantitative analysis of homogeneous or stratified microvolumes applying the model 'PAP'," in *Electron Probe Quantitation*, Plenum, 1991.
14. Reed, S.J.B., "Characteristic fluorescence corrections in electron-probe microanalysis," *Brit. J. Appl. Phys.* **16** (1965) 913--926.
15. Ritchie, R.H. & Howie, A., "Inelastic scattering probabilities in scanning transmission electron microscopy," *Phil. Mag. A* **58** (1988) 753--767.
16. Schaffer, B., Grogger, W., & Kothleitner, G., "Automated spatial drift correction for EFTEM image series," *Ultramicroscopy* **102** (2004) 27--36.
17. Spence, J.C.H., "The post-deconvolution problem in EELS," *Ultramicroscopy* **4** (1979) 9--12.
18. Stoger-Pollach, M., "Optical properties and bandgaps from low loss EELS," *Micron* **39** (2008) 1092--1110.
19. Tan, H., Verbeeck, J., Abakumov, A., & Van Tendeloo, G., "Oxidation state and chemical shift investigation in transition metal oxides by EELS," *Ultramicroscopy* **116** (2012) 24--33.
20. Verbeeck, J. & Van Aert, S., "Model based quantification of EELS spectra," *Ultramicroscopy* **101** (2004) 207--224.
21. Watanabe, M. & Williams, D.B., "The quantitative analysis of thin specimens: a review of progress from the Cliff-Lorimer to the new $\zeta$-factor methods," *J. Microsc.* **221** (2006) 89--109.
22. Williams, D.B. & Carter, C.B., *Transmission Electron Microscopy*, 2nd ed., Springer, 2009.
23. HyperSpy developers, *RosettaSciIO* — Bruker `.bcf`/`.spx` reader (`rsciio/bruker`), https://hyperspy.org/rosettasciio (reference for the SFS container and `SpectrumData0` packed-map format).
24. Burdet, P. et al., "HyperSpy: multidimensional data analysis toolbox," and the community reverse-engineering of the Bruker SFS/BCF format documented therein.
25. Bearden, J.A., "X-Ray Wavelengths," *Rev. Mod. Phys.* **39** (1967) 78--124.
26. Deslattes, R.D. et al., "X-ray transition energies: new approach to a comprehensive evaluation," *Rev. Mod. Phys.* **75** (2003) 35--99 (NIST X-Ray Transition Energies Database).
27. Bevington, P.R. & Robinson, D.K., *Data Reduction and Error Analysis for the Physical Sciences*, 3rd ed., McGraw-Hill, 2003 (Poisson counting statistics and propagation of error).
28. Egerton, R.F. & Wang, Z.L., "Fourier-ratio deconvolution techniques for electron energy-loss spectroscopy (EELS)," *Ultramicroscopy* **32** (1990) 137--148.
29. Johnson, D.W. & Spence, J.C.H., "Determination of the single-scattering probability distribution from plural-scattering data," *J. Phys. D: Appl. Phys.* **7** (1974) 771--780.
30. Richardson, W.H., "Bayesian-based iterative method of image restoration," *J. Opt. Soc. Am.* **62** (1972) 55--59.
31. Lucy, L.B., "An iterative technique for the rectification of observed distributions," *Astron. J.* **79** (1974) 745--754.
32. Gloter, A., Douiri, A., Tencé, M., & Colliex, C., "Improving energy resolution of EELS spectra: an alternative to the monochromator solution," *Ultramicroscopy* **96** (2003) 385--400.
33. Lawson, C.L. & Hanson, R.J., *Solving Least Squares Problems*, SIAM, 1995.
34. Fiori, C.E. & Newbury, D.E., in *Scanning Electron Microscopy/1978*, Vol. I (SEM Inc., AMF O'Hare, IL, 1978) p. 401.
35. Fano, U., "Ionization yield of radiations. II. The fluctuations of the number of ions," *Phys. Rev.* **72** (1947) 26--29.
36. Statham, P.J., "Limitations to accuracy in extracting characteristic line intensities from X-ray spectra," *J. Res. Natl. Inst. Stand. Technol.* **107** (2002) 531--539.
37. Kramers, H.A., "On the theory of X-ray absorption and of the continuous X-ray spectrum," *Philos. Mag.* **46** (1923) 836--871.
