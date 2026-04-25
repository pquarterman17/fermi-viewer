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

## Implementation Map

| Function | One-line description | Governing equation |
|----------|---------------------|--------------------|
| `imaging.eelsAlignZLP` | Per-pixel ZLP cross-correlation alignment of a spectrum image | $\Delta_i = \arg\max_\tau \sum s_i(E+\tau)\,r(E)$ |
| `imaging.eelsBackground` | Power-law (or exponential) pre-edge background fit and subtraction | $I_\mathrm{bg} = A\,E^{-r}$ |
| `imaging.eelsThicknessMap` | Per-pixel relative thickness via the Malis log-ratio method | $t/\lambda = \ln(I_\mathrm{total}/I_\mathrm{ZLP})$ |
| `imaging.eelsFourierLog` | Single-scattering distribution by Fourier-log deconvolution | $\tilde S = \ln(\tilde J / \tilde Z)$ |
| `imaging.eelsKramersKronig` | Complex dielectric function $\varepsilon(E)$ from low-loss EELS | $\mathrm{Im}(-1/\varepsilon)$ + KK transform |
| `imaging.eelsExtractMap` | Core-loss edge integration with optional background subtraction | $\int_{E_1}^{E_2}[I_\mathrm{meas}(E) - I_\mathrm{bg}(E)]\,dE$ |
| `imaging.eelsELNES` | Background-subtracted near-edge structure normalized to edge jump | Fermi golden rule: $d\sigma/dE \propto \rho_f(E)$ |
| `imaging.eelsSVD` | SVD/MSA decomposition of a spectrum image into eigenspectra and eigenimages | $X = U\Sigma V^T$ |
| `imaging.eelsEdgeTable` | Reference table of K, $L_{2,3}$, $M_{4,5}$ edge onsets (Egerton 2011) | --- |
| `imaging.cliffLorimer` | Thin-film EDS quantification by the Cliff-Lorimer ratio method | $w_i = k_i I_i / \sum_j k_j I_j$ |
| `imaging.edsKFactorTable` | Built-in 200 kV Cliff-Lorimer $k$-factors relative to Si | --- (lookup) |
| `imaging.edsCompositionProfile` | Bilinear-interpolated composition line profile across atomic-% maps | $x_i(s) = \mathrm{interp2}(\text{map}_i, x(s), y(s))$ |
| `imaging.massAbsorptionCoeff` | Mass absorption coefficient $\mu/\rho$ from Heinrich empirical formula | $\mu/\rho \approx C\,Z^4\lambda^3/A$ |
| `imaging.zafCorrection` | Iterative ZAF (atomic number, absorption, fluorescence) correction for bulk EDS | $C_i = Z_i A_i F_i\,k_i I_i$ (iterated) |

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
