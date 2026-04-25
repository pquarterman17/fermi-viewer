# Electron Microscopy Imaging

This document collects the geometric / physical theory behind the `+imaging/` utilities in the toolbox. The current focus is on stage-tilt corrections applied by `imaging.measureDistance` and `imaging.lineProfile`, which affect every distance / line-profile / polyline / angle measurement made in `FermiViewer` when the **Tilt corr.** checkbox is active.

---

## Tilt Correction in SEM / FIB Imaging

Electron microscope images are two-dimensional projections of a three-dimensional sample. Whenever the sample is imaged at a non-zero stage tilt $\theta$, in-plane or through-thickness distances on the sample no longer map one-to-one onto pixel distances in the image — one axis is foreshortened by a factor that depends on the imaging geometry. Pressing the **Tilt corr.** button in FermiViewer rescales the foreshortened axis so that a measurement readout reflects the true sample-frame length.

The toolbox supports two distinct tilt geometries, chosen via the **Geometry** dropdown in the Measurement panel (or via the `Geometry` name-value argument to `imaging.measureDistance` / `imaging.lineProfile`):

* `"CrossSection"` (default) — FIB cross-section viewing geometry. Apply $1/\sin\theta$.
* `"Surface"` — plan-view of a tilted top surface. Apply $1/\cos\theta$.

In both cases the correction is applied to a single image axis (the axis perpendicular to the stage tilt rotation axis). The axis parallel to the rotation axis is unaffected.

### Geometry 1 — Plan-View Surface Imaging (`"Surface"`)

**Setup.** The electron beam is vertical. The specimen is a planar surface, and the stage is tilted about an in-plane axis (call it the image $x$-axis) by angle $\theta$. A feature on the (flat) top surface of the specimen sits at sample-frame position $(x_s, y_s, 0)$.

**Projection.** Rotating the sample frame about the $x$-axis by $\theta$ maps the feature to lab-frame coordinates

$$
(x,\,y,\,z) = \bigl(x_s,\; y_s\cos\theta,\; y_s\sin\theta\bigr).
$$

Projection onto the image plane (the plane perpendicular to the electron beam) simply drops the $z$ coordinate, giving image position $(x_s,\, y_s\cos\theta)$. The two in-plane displacements therefore transform as

$$
\Delta x_\text{img} = \Delta x_s, \qquad
\Delta y_\text{img} = \Delta y_s\,\cos\theta.
$$

The axis parallel to the tilt rotation axis ($x$) is unchanged. The perpendicular axis ($y$) is foreshortened by $\cos\theta$. Recovering true lateral lengths from measured pixel displacements then requires

$$
\boxed{\;\Delta y_s = \dfrac{\Delta y_\text{img}}{\cos\theta}, \qquad \Delta x_s = \Delta x_\text{img}\;}
$$

so the true Euclidean length between two points on the tilted surface is

$$
L_\text{true} \;=\; \sqrt{\,\Delta x_\text{img}^2 + \Bigl(\dfrac{\Delta y_\text{img}}{\cos\theta}\Bigr)^{\!2}\,}.
$$

**Important caveat.** The foreshortening is **not** isotropic. A line drawn along the image $x$-axis (parallel to the stage tilt axis) measures its true length directly; only lines with a component along the perpendicular axis are foreshortened. The toolbox applies the $1/\cos\theta$ factor only to the axis specified by `TiltAxis` (default `'Y'`).

### Geometry 2 — FIB Cross-Section (`"CrossSection"`)

**Setup.** In a focused-ion-beam (FIB) dual-beam instrument, a trench is milled into the top surface to expose a vertical cross-section of the sample. The SEM column images through the tilted stage at an angle $\theta$ relative to horizontal (most commonly $\theta = 52°$, the standard FEI dual-beam geometry). The sample is not re-positioned after milling — the electron beam looks *down onto* the tilted top surface, and "into" the cross-section face that was freshly exposed by the ion milling.

**Projection.** Consider a feature at sample-frame depth $D$ below the original top surface, located at $(0, 0, -D)$ before tilt. Rotating the sample about the $x$-axis by $\theta$ maps it to

$$
(x,\,y,\,z) = \bigl(0,\; D\sin\theta,\; -D\cos\theta\bigr).
$$

Projection onto the image plane gives image position $(0,\, D\sin\theta)$. The depth direction projects onto the image $y$-axis with a factor of $\sin\theta$, and recovering true depth from a measured pixel displacement requires

$$
\boxed{\;\Delta y_s^\text{(depth)} = \dfrac{\Delta y_\text{img}}{\sin\theta}\;}
$$

so the true Euclidean length of a cross-section feature is

$$
L_\text{true} \;=\; \sqrt{\,\Delta x_\text{img}^2 + \Bigl(\dfrac{\Delta y_\text{img}}{\sin\theta}\Bigr)^{\!2}\,}.
$$

At the standard $\theta = 52°$ the correction factor is $1/\sin(52°) \approx 1.269$ — the depth axis needs to be stretched by ~27 % to recover the true cross-section dimension.

As with the Surface geometry, the correction applies only to the axis perpendicular to the stage tilt rotation axis (parameter `TiltAxis`). Lateral displacements parallel to the rotation axis pass through unchanged.

### Which Geometry to Pick

| Scenario | Geometry | Typical $\theta$ | Correction |
|----------|----------|------------------|------------|
| Plan-view SEM of a surface feature with the stage tilted toward the column (e.g. to enhance topographic contrast) | `Surface` | 10° – 70° | $1/\cos\theta$ |
| FIB cross-section imaged in-situ without re-positioning the specimen (most common workflow) | `CrossSection` | $\sim 52°$ | $1/\sin\theta$ |
| Tilt-series tomography (each slice imaged at a different stage tilt) | `Surface` per slice, or upstream reconstruction | varies | $1/\cos\theta$ |
| Cross-section where the specimen has been manually re-tilted to present the cross-section face perpendicular to the beam | no correction ($\theta_\text{eff} \approx 0$) | $\sim 0°$ | identity |

The FermiViewer default is `CrossSection` because that matches the SEM/FIB workflow most commonly producing stage-tilt metadata (FEI `StageT`, Bruker `Tilt`).

### Worked Example

Suppose a feature appears in an SEM image with a vertical extent (perpendicular to the tilt axis) of $\Delta y_\text{img} = 100\ \text{nm}$ (after pixel-size calibration). The stage tilt is $\theta = 45°$.

* Interpreted as a **plan-view surface** feature ($1/\cos$):

$$
\Delta y_\text{true} = \frac{100}{\cos 45°} \approx 141.4\ \text{nm}
$$

* Interpreted as a **FIB cross-section** depth ($1/\sin$):

$$
\Delta y_\text{true} = \frac{100}{\sin 45°} \approx 141.4\ \text{nm}
$$

At $\theta = 45°$ the two corrections coincide because $\sin\theta = \cos\theta$. Away from 45° they diverge strongly. At $\theta = 30°$ the same 100 nm image extent corresponds to 115.5 nm (surface) vs 200 nm (cross-section); at $\theta = 70°$ it corresponds to 292 nm (surface) vs 106 nm (cross-section). **Picking the wrong geometry can easily give a 2–3× error** — selecting the right dropdown value is mandatory, not optional.

### Limitations

1. **Single tilt axis only.** The toolbox assumes the stage is tilted about a single in-plane axis (either the image $x$ or $y$ axis, specified via `TiltAxis`). Compound tilt (simultaneous $\alpha$ and $\beta$ rotations) is not modelled.
2. **Planar features.** Both corrections assume the true feature lives entirely in the sample plane (Surface) or along the sample depth axis (CrossSection). Features with out-of-plane structure will not be corrected exactly by either formula.
3. **Angles near $\pm 90°$.** The correction factors diverge as $\theta \to 90°$ (Surface) or $\theta \to 0°$ (CrossSection). The toolbox enforces $|\theta| < 90°$ to avoid singularities; for $\theta \lesssim 5°$ in cross-section geometry the 1/sin correction becomes numerically ill-conditioned and measurements at nearly-zero tilt should simply disable tilt correction.
4. **Tilt axis orientation.** The convention is that `TiltAxis` names the *foreshortened* image axis (perpendicular to the rotation axis). Flipping the image upside down or mirroring it does not flip the tilt axis identification — users should set the axis based on sample orientation, not display orientation.

### References

* Goldstein, J. I., *et al.*, **Scanning Electron Microscopy and X-Ray Microanalysis**, 4th ed., Springer (2018). Chapter 4 discusses geometric distortions in tilted-stage SEM imaging and the $\cos\theta$ surface-projection formula.
* Giannuzzi, L. A., and Stevie, F. A. (eds.), **Introduction to Focused Ion Beams: Instrumentation, Theory, Techniques and Practice**, Springer (2005). Chapter 10 covers cross-section metrology and derives the $\sin\theta$ depth-projection formula for the standard 52° dual-beam workflow.
* Kizilyaprak, C., *et al.*, "Focused ion beam scanning electron microscopy in biology," *J. Microsc.* **254**, 109–114 (2014). A practical review of tilt-correction factors in cross-section imaging.

### Implementation (tilt correction)

The tilt-correction routines plug into the unified imaging implementation table at the [end of this document](#implementation-table-all-imaging-utilities). The FermiViewer **Tilt corr.** checkbox turns the correction on/off, the **spinner** sets $\theta$ (auto-populated from metadata when available), and the **Geometry** dropdown selects Surface vs Cross-section. Tilt-corrected distance labels on the image are marked with an asterisk ($\ast$); hovering the asterisk shows the exact $1/\sin$ or $1/\cos$ factor applied.

---

## Electron Wavelength (Relativistic de Broglie)

Every reciprocal-space conversion in TEM — CTF estimation, $d$-spacing from a diffraction-spot radius, camera-length calibration — needs the electron wavelength $\lambda$ at the operating accelerating voltage. At the voltages used for TEM (80–300 kV) the kinetic energy is a non-negligible fraction of $m_0 c^2 = 511$ keV, so the non-relativistic approximation $\lambda = h/\sqrt{2 m_0 e V}$ is wrong by 5 % at 100 kV and 22 % at 300 kV. The toolbox uses the full relativistic expression.

### Theory

Equating the total relativistic energy of the accelerated electron to the rest-energy plus the work done by the potential,

$$E_\text{total} = m_0 c^2 + eV = \sqrt{(p c)^2 + (m_0 c^2)^2},$$

and solving for $p$ gives

$$p = \frac{1}{c}\sqrt{(eV)^2 + 2 m_0 c^2 \cdot eV} = \sqrt{2 m_0 e V}\,\sqrt{1 + \frac{eV}{2 m_0 c^2}}.$$

The de Broglie relation $\lambda = h/p$ then yields the canonical relativistic-electron formula

$$\boxed{\;\lambda = \dfrac{h}{\sqrt{\,2 m_0 e V\bigl(1 + eV/(2 m_0 c^2)\bigr)\,}}\;}$$

In angstroms with $V$ in volts this is conveniently approximated by

$$\lambda \;[\text{Å}] \;\approx\; \frac{12.2643}{\sqrt{V + 0.97845\times 10^{-6}\, V^2}}.$$

The non-relativistic limit $eV \ll m_0 c^2$ collapses to the textbook expression

$$\lambda_\text{NR}\;[\text{Å}] \;\approx\; \sqrt{\frac{150.4}{V\;[\text{volts}]}},$$

which is accurate to better than 0.5 % only below ~10 kV. Above 50 kV the relativistic correction must be retained.

### Worked example — common TEM voltages

| Accelerating voltage $V$ | Non-relativistic $\sqrt{150.4/V}$ | Relativistic $\lambda$ | Error of NR (%) |
|---:|---:|---:|---:|
| 80 kV | 0.0433 Å | 0.0418 Å | +3.7 % |
| 100 kV | 0.0388 Å | 0.0370 Å | +4.7 % |
| 200 kV | 0.0274 Å | 0.0251 Å | +9.2 % |
| 300 kV | 0.0224 Å | 0.0197 Å | +13.7 % |

At 200 kV the wavelength of $\lambda = 0.0251$ Å is two orders of magnitude smaller than typical lattice spacings (~2 Å), so Bragg angles in TEM are correspondingly small ($2\theta \lesssim 1°$), and the small-angle approximations used in TEM diffraction (camera-length geometry) are extremely accurate.

### When to use

- Any conversion from a real-space pixel size to a reciprocal-space $q$-axis (FFT or SAED).
- CTF computation and Scherzer-defocus estimation.
- Indexing diffraction spots: the $d$ value of a spot at radial pixel position $R$ on a TEM detector at camera length $L$ is $d = \lambda L / (R \cdot p)$, where $p$ is the detector pixel size.
- Comparing simulated and experimental nano-beam diffraction.

### References

- Williams, D. B., and Carter, C. B., **Transmission Electron Microscopy: A Textbook for Materials Science**, 2nd ed., Springer (2009). §1.4 derives the relativistic-wavelength formula and tabulates values for typical TEM voltages.
- Reimer, L., and Kohl, H., **Transmission Electron Microscopy: Physics of Image Formation**, 5th ed., Springer (2008). §2.1 collects the electron-optics constants.

---

## Contrast Transfer Function (CTF) for HRTEM

In HRTEM, a thin specimen is treated as a weak phase object: the exit wave $\psi(\mathbf{r}) \approx 1 + i\sigma V_p(\mathbf{r})$ encodes the projected potential as a small phase modulation. The microscope then forms an image whose intensity contrast at spatial frequency $\mathbf{k}$ is *not* the projected potential directly, but a filtered version where the filter — the contrast transfer function — encodes how the lens aberrations and defocus rotate the phase of each Fourier component. Understanding the CTF is what turns an HRTEM micrograph from a pretty pattern into an interpretable structural image.

### Theory

Defocus $\Delta f$ (positive = underfocus, by Scherzer's sign convention) and spherical aberration $C_s$ shift the phase of a wave with transverse spatial frequency $k = |\mathbf{k}|$ by

$$\boxed{\;\chi(k) \;=\; \pi\,\lambda\,k^{2}\,\Delta f \;-\; \tfrac{1}{2}\,\pi\,C_s\,\lambda^{3}\,k^{4}\;}$$

For a weak phase object the imaginary phase modulation is converted to amplitude contrast by the imaginary part of the aberration filter, so the (linear) image contrast in the Fourier domain is

$$\text{CTF}(k) \;=\; \sin\bigl[\chi(k)\bigr] \cdot E_t(k)\,E_s(k),$$

where $E_t$ and $E_s$ are temporal and spatial coherence envelope functions that damp $\sin\chi$ at high $k$. The temporal envelope is set by the chromatic spread $\Delta E$ via

$$E_t(k) \;=\; \exp\!\left[-\tfrac{1}{2}(\pi \lambda k^{2})^{2}\,\Delta z^{2}\right], \qquad \Delta z = C_c\,\frac{\Delta E}{E_0},$$

and the spatial envelope by the illumination semi-angle $\alpha$,

$$E_s(k) \;=\; \exp\!\left[-(\pi \alpha)^{2}\bigl(C_s \lambda^{2} k^{3} - \Delta f\,k\bigr)^{2}\right].$$

A point in reciprocal space where $\chi = n\pi$ ($n\in\mathbb{Z}$) gives $\sin\chi = 0$ — a CTF zero — meaning that spatial frequency carries no contrast. A point where $\chi = (n+\tfrac{1}{2})\pi$ has $|\sin\chi|=1$ and is faithfully transferred. Between zeros, $\sin\chi$ flips sign: bright atomic columns turn into dark columns and back, depending on $k$. This is *contrast inversion* and it is why HRTEM images cannot be interpreted by eye except near specific defoci.

#### Scherzer defocus

The optimal defocus is the one that produces the broadest band of nearly-uniform negative contrast (atoms appear as dark dots on a bright background) before the first zero. Setting $d\chi/dk = 0$ at the inflection of $\chi(k)$ and choosing the prefactor that maximizes the passband width gives the Scherzer condition,

$$\boxed{\;\Delta f_S = -1.2\sqrt{C_s\,\lambda}\;}$$

(some conventions use $-\sqrt{4 C_s\lambda/3}\approx -1.155\sqrt{C_s\lambda}$; the 1.2 prefactor is the convention adopted here). At Scherzer defocus the first CTF zero falls at

$$k_S \;=\; \frac{1.51}{(C_s\,\lambda^{3})^{1/4}}, \qquad d_S \;=\; \frac{1}{k_S} \;=\; 0.66\,(C_s\,\lambda^{3})^{1/4},$$

which defines the **point resolution** of the microscope — the finest spacing transferred without contrast inversion. Information beyond $k_S$ (the *information limit*) is still present in the image but its phase is scrambled; it can only be recovered by exit-wave reconstruction.

### Worked example — 200 kV with $C_s = 1.2$ mm

Using $\lambda = 0.0251$ Å (from the relativistic formula above) and $C_s = 1.2 \text{ mm} = 1.2\times 10^{7}$ Å:

$$\Delta f_S = -1.2\sqrt{1.2\times 10^{7}\,\cdot\,0.0251} \;\approx\; -658\,\text{Å} \;\approx\; -65.8\,\text{nm},$$

$$d_S = 0.66\,\bigl(1.2\times 10^{7}\,\cdot\,0.0251^{3}\bigr)^{1/4} \;\approx\; 1.93\,\text{Å}.$$

So a 200 kV TEM with $C_s = 1.2$ mm has a Scherzer defocus near $-65$ nm and a point resolution near 1.9 Å — sufficient to resolve, e.g., {111} silicon planes at 3.13 Å but not the 1.36 Å Si dumbbells along $\langle 110 \rangle$ (those need $C_s$-corrected microscopes or exit-wave reconstruction).

A modern $C_s$-corrected instrument with $C_s = 1\;\mu\text{m}$ gives $\Delta f_S \approx -1.9$ nm and $d_S \approx 0.6$ Å at the same voltage, well below the chemical-bond length scale.

### Identifying defocus from a Thon-ring FFT

The FFT of an HRTEM image of an amorphous region (or carbon support film) reveals concentric *Thon rings*, whose minima are the CTF zeros. Reading off two or three ring radii (in 1/Å) and solving the system

$$\chi(k_n) = n\pi \quad \Rightarrow \quad \pi\lambda k_n^{2}\,\Delta f - \tfrac{1}{2}\pi C_s\lambda^{3} k_n^{4} = n\pi$$

returns the defocus. `imaging.estimateCTF` automates this by radially averaging the power spectrum and refining $\Delta f$ with `fminsearch` to align $\sin^{2}\chi$ minima with measured ring minima.

### When to use

- Decide whether your micrograph was acquired near Scherzer or in a pass band where contrast is inverted.
- Verify post-acquisition that an as-recorded image is in a usable defocus regime before attempting structural interpretation.
- Estimate $\Delta f$ from a Thon-ring FFT for through-focal series alignment or exit-wave reconstruction.
- Sanity-check microscope tuning when a new sample produces unexpectedly fuzzy images.

### References

- Scherzer, O., "The theoretical resolution limit of the electron microscope," *J. Appl. Phys.* **20**, 20–29 (1949). The original derivation of the optimum defocus.
- Reimer, L., and Kohl, H., **Transmission Electron Microscopy**, 5th ed., Springer (2008). §6.4 derives $\chi(k)$ and the Scherzer condition with full envelope-function treatment.
- Spence, J. C. H., **High-Resolution Electron Microscopy**, 4th ed., Oxford University Press (2013). The standard graduate-level reference for HRTEM image formation.
- Thon, F., "Phase contrast electron microscopy," in **Electron Microscopy in Material Science** (Valdrè, ed., Academic Press 1971). Source of "Thon rings" in the FFT analysis.

---

## Geometric Phase Analysis (GPA)

GPA, introduced by Hÿtch and co-workers, extracts a 2-D strain field from a single HRTEM (or atomic-resolution STEM) lattice image by Fourier-filtering around two reciprocal-lattice spots and converting the resulting complex Bragg-image phases into displacement and strain maps. It is one of the few techniques that yields strain at near-atomic spatial resolution from a conventional lattice image without specialized acquisition hardware.

### Theory

A perfect lattice imaged in HRTEM gives intensity $I(\mathbf{r}) = \sum_g A_g \cos\bigl(2\pi\,\mathbf{g}\cdot\mathbf{r} + \phi_g^{(0)}\bigr)$, with each Bragg spot $\mathbf{g}$ contributing one cosine term. When the lattice is locally distorted by a slowly varying displacement field $\mathbf{u}(\mathbf{r})$, the position $\mathbf{r}$ in the cosine argument is replaced by $\mathbf{r} - \mathbf{u}(\mathbf{r})$, so the Bragg phase becomes spatially varying:

$$\phi_g(\mathbf{r}) = \phi_g^{(0)} \;-\; 2\pi\,\mathbf{g}\cdot\mathbf{u}(\mathbf{r}).$$

GPA exploits this by isolating one Bragg term in the Fourier domain and recovering its phase:

1. Compute the FFT of the lattice image.
2. For each chosen reciprocal-lattice vector $\mathbf{g}_i$ ($i=1,2$), apply a soft mask (typically Butterworth) of radius $r_m$ centred on the spot, then inverse-FFT to obtain the complex *Bragg-filtered image* $H_i(\mathbf{r})$.
3. The local phase $\phi_i(\mathbf{r}) = \arg\bigl[H_i(\mathbf{r})\bigr]$ (after 2-D unwrapping) gives a constraint on the displacement: $\phi_i(\mathbf{r}) = -2\pi\,\mathbf{g}_i \cdot \mathbf{u}(\mathbf{r})$.

Two non-collinear $\mathbf{g}_i$ provide two scalar constraints, enough to invert for the in-plane displacement vector

$$\mathbf{u}(\mathbf{r}) \;=\; -\frac{1}{2\pi}\,\mathbf{G}^{-1}\begin{pmatrix}\phi_1(\mathbf{r})\\ \phi_2(\mathbf{r})\end{pmatrix}, \qquad \mathbf{G} \;=\; \begin{pmatrix}g_{1x}&g_{1y}\\ g_{2x}&g_{2y}\end{pmatrix}.$$

The 2-D infinitesimal strain tensor is the symmetric part of the displacement-gradient,

$$\varepsilon_{ij}(\mathbf{r}) \;=\; \tfrac{1}{2}\!\left(\frac{\partial u_i}{\partial x_j} + \frac{\partial u_j}{\partial x_i}\right), \qquad i,j\in\{x,y\},$$

and the rigid-body rotation is the antisymmetric part,

$$\omega_{xy}(\mathbf{r}) \;=\; \tfrac{1}{2}\!\left(\frac{\partial u_y}{\partial x} - \frac{\partial u_x}{\partial y}\right).$$

In practice one differentiates the unwrapped phase maps directly via finite differences (and uses the relation $\partial_j\phi_i = -2\pi g_i\cdot\partial_j\mathbf{u}$) to compute $\varepsilon_{xx}, \varepsilon_{yy}, \varepsilon_{xy}, \omega_{xy}$ on the same pixel grid as the original image.

### Mask radius — resolution / SNR trade-off

The mask radius $r_m$ in the FFT directly controls the real-space resolution of the strain map:

- **Small $r_m$** → low spatial resolution (~ $1/r_m$ in image pixels) but high SNR; smooth strain maps; suitable for visualizing long-range strain in a reference region (substrate) and a thin film together.
- **Large $r_m$** → high spatial resolution (down to a few atomic columns) but more noise and risk of cross-talk between adjacent Bragg spots.

A common starting choice is $r_m \approx \tfrac{1}{3}\min(|\mathbf{g}_1|, |\mathbf{g}_2|)$, which the toolbox uses as the default `MaskRadius` in `imaging.geometricPhaseAnalysis`. The Butterworth filter (order 2 by default) gives a smoother roll-off than a hard top-hat, reducing ringing in the inverse-FFT.

### Worked example — strained SiGe on Si

A SiGe/Si heterostructure with 4 % lattice mismatch ($a_\text{SiGe}/a_\text{Si} = 1.04$) imaged in cross-section along $\langle 110 \rangle$ shows a step in $\varepsilon_{xx}$ (the in-plane strain) at the heterointerface. With Si as the reference lattice ($\mathbf{g}_1 = (1\bar11)$, $\mathbf{g}_2 = (00\bar2)$ in the imaging plane), the SiGe layer phases drift linearly across the layer at a rate that — after spatial differentiation — gives

$$\varepsilon_{xx}^\text{SiGe} \;=\; \frac{a_\text{SiGe} - a_\text{Si}}{a_\text{Si}} \;=\; 0.04.$$

For a fully strained (pseudomorphic) SiGe layer the in-plane strain matches the substrate ($\varepsilon_{xx}=0$ relative to Si), and the 4 % mismatch is accommodated entirely as out-of-plane tetragonal distortion ($\varepsilon_{zz}\approx 0.04 \cdot 2\nu/(1-\nu) \approx 0.05$ for the elastic constants of Si). GPA on a high-quality lattice image resolves this 4 % step at the interface to within $\pm 0.5$ % over a few-nm averaging window — strain-mapping resolution that is competitive with nanobeam diffraction at much shorter measurement times.

### When to use

- HRTEM or atomic-resolution STEM-HAADF lattice images of thin-film heterostructures, dislocation cores, grain boundaries, or strained nanostructures.
- Comparative strain studies between regions of a single image (the absolute strain depends on the chosen reference region).
- Identification of misfit-dislocation cores via $2\pi$ phase singularities in $\phi_i$.
- *Not* a substitute for **nanobeam-electron-diffraction** (NBED) or **4D-STEM** strain mapping when an absolute strain reference (rather than image-internal reference) is required, or when sample drift / probe scanning artefacts dominate the lattice image.

### References

- Hÿtch, M. J., Snoeck, E., and Kilaas, R., "Quantitative measurement of displacement and strain fields from HREM micrographs," *Ultramicroscopy* **74**, 131–146 (1998). The foundational GPA paper — derives the displacement-from-phase formula and discusses mask choice.
- Hÿtch, M. J., and Plamann, T., "Imaging conditions for reliable measurement of displacement and strain in high-resolution electron microscopy," *Ultramicroscopy* **87**, 199–212 (2001). Practical guide to imaging conditions, defocus effects, and lens-distortion correction.
- Hÿtch, M. J., Putaux, J.-L., and Pénisson, J.-M., "Measurement of the displacement field of dislocations to 0.03 Å by electron microscopy," *Nature* **423**, 270–273 (2003). Demonstrates dislocation-core sensitivity.

---

## Azimuthal Integration of 2-D Diffraction Patterns

A polycrystalline (powder-like) or nanocrystalline specimen under a parallel TEM beam produces a SAED pattern of concentric Debye–Scherrer rings; a synchrotron WAXS / GIWAXS detector records the same physics on a 2-D pixel array. **Azimuthal integration** collapses these rings into a 1-D intensity profile $I(q)$ that can be analysed with standard powder-diffraction tools (peak fitting, phase identification, Williamson–Hall, Rietveld).

### Theory

Each detector pixel at position $\mathbf{r}_\text{px}$ relative to the direct-beam centre $\mathbf{c}$ contributes to a radial bin indexed by

$$R \;=\; |\mathbf{r}_\text{px} - \mathbf{c}|,$$

and the measured intensity in bin $j$ is the (optionally weighted) mean of all pixels whose $R$ falls in bin $j$:

$$I_j \;=\; \frac{\sum_{p\in\text{bin}_j} w_p\,I_p}{\sum_{p\in\text{bin}_j} w_p}.$$

For a flat 2-D pixel detector at distance $L$ from the sample with pixel pitch $p$, the radial pixel coordinate $R$ converts to scattering angle and momentum transfer via

$$\tan(2\theta) \;=\; \frac{R\,p}{L}, \qquad q \;=\; \frac{4\pi\sin\theta}{\lambda}.$$

In TEM SAED the small-angle limit $2\theta \ll 1$ holds, so $q \approx 2\pi R p / (\lambda L)$ and the corresponding $d$-spacing of a ring at radius $R$ is $d = \lambda L / (R p)$ (camera-length form of Bragg's law).

For an FFT image (used by the toolbox in *FFT-mode* calibration), the centred pixel coordinate maps directly to spatial frequency: a centred FFT of an $N\times N$ real-space image with pixel size $p$ has reciprocal pixel size $\Delta k = 1/(N p)$, so the $d$-spacing of an FFT spot at radial pixel $R$ is $d = N p / R$.

### Center finding

Accurate $I(q)$ requires sub-pixel knowledge of $\mathbf{c}$. Several strategies are used in practice:

1. **Direct-beam fit** — fit a 2-D Gaussian to the unscattered direct beam (if not blocked by a beamstop).
2. **Autocorrelation symmetry** — the autocorrelation of an azimuthally symmetric pattern is itself centrosymmetric; finding its peak gives $\mathbf{c}$ to sub-pixel accuracy.
3. **Ring-fit refinement** — start from a rough centre, integrate, find ring radii, refine $\mathbf{c}$ to maximize ring sharpness, iterate.

The toolbox `imaging.azimuthalIntegrate` accepts an explicit `Center=[cx cy]` argument and defaults to the geometric image centre when none is supplied. For sub-pixel work the recommended workflow is to find the centre by autocorrelation (or by user click on the direct beam) and pass it explicitly.

### Geometric corrections (overview)

Quantitative powder diffraction usually applies two corrections to $I_j$ before profile fitting:

- **Solid-angle correction** — pixels at large $R$ subtend a smaller solid angle in the sample frame; the per-pixel solid angle scales as $\cos^{3}(2\theta)$ for a flat detector.
- **Polarization correction** — for unpolarized X-ray sources the scattered intensity carries a factor $\tfrac{1}{2}(1+\cos^{2}2\theta)$.

In SAED both corrections are negligible because $2\theta \ll 1$. The `imaging.azimuthalIntegrate` routine therefore omits them; users who need them should apply the appropriate angular factor to $I_j$ post-integration. See dedicated SAXS/WAXS toolkits (pyFAI, Dioptas) for full geometric handling.

### Worked example — gold nanocrystal SAED

A SAED pattern of a polycrystalline gold film shows three innermost rings whose radii calibrate to $d$ = 2.36, 2.04, and 1.44 Å. Indexing against the $Fm\bar{3}m$ gold structure ($a_0 = 4.078$ Å):

| Measured $d$ (Å) | $(hkl)$ | Predicted $d$ = $a_0/\sqrt{h^2+k^2+l^2}$ (Å) |
|---:|:---:|---:|
| 2.36 | (111) | 4.078/√3 = 2.355 |
| 2.04 | (200) | 4.078/2 = 2.039 |
| 1.44 | (220) | 4.078/√8 = 1.442 |

All three match to better than 0.5 %, confirming the FCC gold assignment. After azimuthal integration, the $I(q)$ profile is suitable for direct comparison with a tabulated powder pattern or for crystallite-size estimation via Scherrer broadening of the 1-D peaks (see `xrd.md` § Peak Profile Functions).

### When to use

- TEM SAED of polycrystalline thin films, nanoparticle assemblies, or amorphous materials.
- Synchrotron / lab-source 2-D X-ray detector data (Pilatus, Eiger, MAR-CCD) in WAXS / GIWAXS / GISAXS geometries.
- Converting an FFT magnitude image to a 1-D radial profile for spatial-frequency analysis (used by `imaging.estimateCTF`).

### References

- Cullity, B. D., and Stock, S. R., **Elements of X-Ray Diffraction**, 3rd ed., Prentice Hall (2001). §6 develops the powder (Debye–Scherrer) geometry and the standard intensity corrections.
- Hammersley, A. P., et al., "Two-dimensional detector software: From real detector to idealised image or two-theta scan," *High Pressure Research* **14**, 235–248 (1996). The original FIT2D paper — describes 2-D-to-1-D azimuthal integration with full geometric correction.
- Kieffer, J., and Karkoulis, D., "PyFAI, a versatile library for azimuthal regrouping," *J. Phys.: Conf. Ser.* **425**, 202012 (2013). Reference implementation for synchrotron data; useful for cross-checks.

---

## Diffraction Spot Detection and Indexing

A single-crystal SAED, CBED, or nanobeam-diffraction pattern is sparse: a small set of bright spots on a low-intensity background. Extracting the crystal structure, lattice parameters, and zone axis from such a pattern is a three-step pipeline — **detect spots → index $(hkl)$ → fit lattice** — each step of which the toolbox exposes as a separate function so they can be inspected and adjusted independently.

### Spot detection

`imaging.findDiffractionSpots` operates on a (background-subtracted, optionally Gaussian-smoothed) 2-D image and returns the brightest local maxima subject to three filters:

1. **Center exclusion** ($R > R_\text{min}$) — rejects the direct beam / DC peak.
2. **Intensity threshold** ($I > \tau \cdot \max(I)$) — drops noise pixels.
3. **Non-maximum suppression** (minimum separation $s_\text{min}$ between accepted spots) — ensures each diffraction peak yields one spot, not several.

Sub-pixel refinement (used inside the indexer) fits a 2-D Gaussian to the $3\times3$ neighborhood of each detected pixel and reports the centroid as the spot position. Sub-pixel accuracy directly improves the precision of derived lattice parameters: a 1 % d-spacing accuracy from a 200-pixel-radius spot requires the centre to be known to ~2 pixels, easily achieved by Gaussian centroiding.

### Indexing — d-spacings to (hkl)

For each detected spot at radial pixel $R$ from the centre, the $d$-spacing is computed using either FFT geometry or TEM camera geometry (see § Electron Wavelength). The indexer then matches each measured $d$ against a database of reference lattice $d$-spacings $\{d_{hkl}\}$ within a fractional tolerance $\eta$:

$$\bigl| d_\text{meas} - d_{hkl}^\text{ref} \bigr| \,/\, d_{hkl}^\text{ref} \;<\; \eta \quad (\text{typical } \eta \approx 0.05).$$

Each phase in the database is scored by the number of measured spots that find at least one valid $(hkl)$ match; the top-$N$ phases by score are returned. For ambiguous patterns, accepting smaller $\eta$ (1–2 %) and requiring more spots to match is the path to a unique assignment.

The reference $d_{hkl}^\text{ref}$ are computed from the lattice parameters using the standard d-spacing formulas — see `xrd.md` § d-Spacing Formulas by Crystal System for the full set of formulas (cubic, tetragonal, orthorhombic, hexagonal, monoclinic, triclinic) used inside the indexer.

### Lattice-parameter fitting

Once spots are indexed, the lattice parameters can be refined. For a 2-D plane image, `imaging.latticeMeasure` takes two indexed reciprocal-lattice spots $\mathbf{g}_1, \mathbf{g}_2$, builds the $2\times2$ reciprocal matrix $\mathbf{G} = [\mathbf{g}_1; \mathbf{g}_2]^{T}$, and inverts it to obtain the in-plane real-space lattice basis,

$$\bigl[\mathbf{a}_1\;\;\mathbf{a}_2\bigr] \;=\; \mathbf{G}^{-T}.$$

The basis vectors give the in-plane lattice parameters $|\mathbf{a}_1|, |\mathbf{a}_2|$ and the in-plane angle $\gamma = \arccos(\mathbf{a}_1\cdot\mathbf{a}_2 / (|\mathbf{a}_1||\mathbf{a}_2|))$. For full 3-D refinement, a least-squares fit of all measured $d_{hkl}$ values (with the indexed Miller indices) to the system-appropriate d-spacing formula yields $a, b, c, \alpha, \beta, \gamma$.

### Worked example — silicon $\langle 110 \rangle$ SAED

A silicon SAED pattern down the $[110]$ zone axis shows the characteristic rectangular array of spots. The two innermost reflections orthogonal in the pattern are $(1\bar11)$ and $(00\bar2)$:

| Reflection | $d$ (Å) for $a_0=5.43$ Å | $1/d$ (1/Å) |
|---:|---:|---:|
| $(1\bar11)$ | $5.43/\sqrt{3} = 3.135$ | 0.319 |
| $(00\bar2)$ | $5.43/2 = 2.715$ | 0.368 |
| $(2\bar20)$ | $5.43/\sqrt{8} = 1.920$ | 0.521 |

Measure $R$ for the two innermost spots, convert to $d$ via $d = \lambda L / (R p)$ with the relativistic $\lambda$ from the voltage, index against the table, and feed $\mathbf{g}_{(1\bar11)}, \mathbf{g}_{(00\bar2)}$ into `imaging.latticeMeasure`. Inverting the $2\times2$ reciprocal matrix recovers $a_0 = 5.43 \pm 0.02$ Å, with the orthogonal angle confirming the $[110]$ zone-axis assignment.

If the measured $d$ values disagree with the database by more than the tolerance, this is a strong hint that either (a) the camera-length / pixel-size calibration is off (~1 % systematic error is common), or (b) the phase assignment is wrong. The recommended response is always to re-check the calibration on a known standard (gold film SAED, see § Azimuthal Integration) before doubting the indexing.

### Kinematic vs dynamical scattering

The toolbox indexer assumes **kinematical** scattering: the diffracted-beam intensities are not used for phase assignment, only the spot *positions*. This is appropriate for thin specimens (typically $t \lesssim 50$ nm for 200 kV electrons in light-element materials). For thicker specimens, dynamical effects redistribute intensity between Bragg beams and can *extinguish* what should be the strongest reflections (e.g. the kinematically-forbidden $(002)$ in diamond can appear in dynamical thick-crystal SAED). Indexing remains valid based on positions; only intensity-based phase fingerprinting requires care.

For quantitative dynamical work (CBED for symmetry / thickness, large-angle CBED for strain), use the multi-slice or Bloch-wave simulators in dedicated packages (e.g., µSTEM, JEMS); the toolbox `imaging.simulateDiffraction` is kinematic and intended for spot-pattern overlay / verification only.

### When to use

- Single-crystal SAED, CBED, or nanobeam-diffraction patterns where zone-axis identification is needed.
- FFT analysis of an HRTEM lattice image, where the FFT spots play the same role as SAED spots and `imaging.latticeMeasure` returns the in-plane lattice basis.
- Phase identification in nanoparticle SAED when only a few spots are visible.
- Verifying a tentative space-group assignment by overlaying a kinematic simulation on top of an experimental SAED.

### References

- Williams, D. B., and Carter, C. B., **Transmission Electron Microscopy**, 2nd ed., Springer (2009). §16 (SAED) and §17 (CBED) cover spot indexing, zone-axis identification, and lattice-parameter measurement in detail.
- Edington, J. W., **Practical Electron Microscopy in Materials Science**, Vol. 2: Electron Diffraction in the Electron Microscope, Macmillan (1975). Concise practical introduction to SAED indexing.
- Morniroli, J.-P., **Large-Angle Convergent-Beam Electron Diffraction**, Société Française des Microscopies (2002). The reference for CBED-based symmetry and lattice-parameter determination.

---

## Interface Width Fitting

A line profile drawn across a chemically (HAADF, EDS, EELS) or structurally sharp interface always has a finite width — the result of intrinsic chemical interdiffusion convolved with the imaging point-spread function (PSF). Fitting an analytic transition profile to the line scan separates the *measured* width from these two physical contributions.

### Theory

#### Two equivalent transition shapes

For an ideal step interface broadened by a Gaussian PSF of width $\sigma_\text{PSF}$ and Gaussian-distributed chemical roughness of width $\sigma_\text{rough}$, the convolved profile is the integral of the Gaussian, i.e. an error function:

$$\boxed{\;I(x) \;=\; I_0 \;+\; \tfrac{A}{2}\!\left[1 + \mathrm{erf}\!\left(\frac{x - x_0}{\sigma\sqrt{2}}\right)\right]\;}$$

where $\sigma$ is the *total* Gaussian width carrying both contributions (see § Convolution below). For very thin interfaces with strong intermixing, a logistic (sigmoid) profile,

$$I(x) \;=\; I_0 \;+\; \frac{A}{1 + \exp\!\bigl(-(x-x_0)/w\bigr)},$$

is sometimes a better empirical match (e.g. spinodal interdiffusion). The two shapes are nearly indistinguishable over the central transition region; the $1/e$ characteristic widths are related by $w_\text{sig} = \sqrt{\pi/2}\,\sigma_\text{erf}$.

The toolbox fits both forms via `imaging.fitInterfaceWidth(x, y, Model='erf' | 'sigmoid')` and reports the standard 10–90 % transition width:

$$w_{10\text{–}90}^\text{erf} \;=\; 2\sqrt{2}\,\mathrm{erf}^{-1}(0.8)\,\sigma \;\approx\; 2.5631\,\sigma,$$

$$w_{10\text{–}90}^\text{sig} \;=\; 2\,\ln(9)\,w \;\approx\; 4.394\,w.$$

#### Convolution — separating PSF from intrinsic roughness

For two independent Gaussian broadening sources (instrument PSF and intrinsic chemical roughness), variances add:

$$\boxed{\;\sigma_\text{meas}^{2} \;=\; \sigma_\text{PSF}^{2} \;+\; \sigma_\text{intrinsic}^{2}\;}$$

so the intrinsic interface roughness is recovered by

$$\sigma_\text{intrinsic} \;=\; \sqrt{\,\sigma_\text{meas}^{2} \,-\, \sigma_\text{PSF}^{2}\,}.$$

This requires an independently measured PSF — typically obtained by fitting an isolated atomic column (STEM-HAADF) with a 2-D Gaussian and using the rms width. For STEM, $\sigma_\text{PSF}$ is in the 0.5–1.5 Å range on modern aberration-corrected instruments; for standard TEM bright-field imaging it is 1–3 Å.

If $\sigma_\text{PSF} \gtrsim \sigma_\text{meas}$ the deconvolution is ill-conditioned and only an upper bound on $\sigma_\text{intrinsic}$ should be reported.

### Worked example — STEM-HAADF oxide / metal interface

A line profile across a perovskite-oxide / metal interface in STEM-HAADF (200 kV, $C_s$-corrected) gives a measured 10–90 % width of 10.8 Å. Converting via $\sigma = w_{10\text{–}90}/2.5631$,

$$\sigma_\text{meas} \;=\; 10.8\,/\,2.5631 \;\approx\; 4.2\,\text{Å}.$$

A Gaussian fit to an isolated cation column on the metal side gives $\sigma_\text{PSF} = 1.5$ Å. Therefore

$$\sigma_\text{intrinsic} \;=\; \sqrt{4.2^{2} - 1.5^{2}} \;\approx\; 3.92\,\text{Å},$$

corresponding to an intrinsic chemical width of ~3.9 Å (about 1 unit cell of the perovskite). This is the figure of merit for comparing growth conditions: a sharper interface (lower $\sigma_\text{intrinsic}$) at fixed temperature and substrate cleanliness implies fewer point-defect cation hops during deposition.

### When to use

- Quantifying chemical sharpness of thin-film heterointerfaces from STEM-HAADF, EDS line scans, or EELS line scans.
- Comparing growth methods (MBE vs PLD vs sputter) on the same substrate / film system.
- Verifying claimed interface sharpness in a manuscript or thesis defense — the reported width should always be accompanied by the fit residual ($R^{2}$) and the PSF used for the deconvolution.

### References

- Sinha, S. K., Sirota, E. B., Garoff, S., and Stanley, H. B., "X-ray and neutron scattering from rough surfaces," *Phys. Rev. B* **38**, 2297–2311 (1988). Foundational paper on the erf-profile description of rough interfaces (in scattering context — same mathematics applies to imaging).
- Stemmer, S., Sane, A., Browning, N. D., and Mazanec, T. J., "Characterization of oxygen-deficient SrCoO$_{3-\delta}$ by electron energy-loss spectroscopy and Z-contrast imaging," *Solid State Ionics* **130**, 71–80 (2000). Application of erf-profile fitting to STEM line scans.
- Pennycook, S. J., and Nellist, P. D. (eds.), **Scanning Transmission Electron Microscopy: Imaging and Analysis**, Springer (2011). §6 covers the STEM PSF and its role in line-profile deconvolution.

### Common pitfalls

1. **Tilted line-scan direction.** If the line scan crosses the interface at a non-normal angle $\phi$, the apparent width is inflated by $1/\cos\phi$. Always orient the scan perpendicular to the interface (or apply the inverse correction).
2. **Background slope.** A linear baseline drift across the scan is absorbed by the $I_0$ and $A$ parameters in the erf model, so a fitted $\sigma$ remains meaningful even if the high- and low-side intensities are not equal. A *curved* background (e.g., from intensity gradient across the sample) is not, and must be subtracted before fitting.
3. **Insufficient sampling.** Reliable $\sigma$ requires at least 3–4 sample points across the transition (between the 10 % and 90 % levels). Sub-Nyquist sampling biases $\sigma$ upward.
4. **Comparing across techniques.** A STEM-HAADF interface width and an EELS-EDX interface width measure different quantities (mass-thickness contrast vs chemical concentration). Both are valid; they should not be averaged.

See also `magnetometry.md` for the analogous treatment of magnetic interface widths in PNR profiles, and `spectroscopy.md` for EELS line-profile interpretation across interfaces.

---

## Implementation table — all imaging utilities

| Function | Purpose | Key equation |
|----------|---------|--------------|
| **Geometric measurement** | | |
| `imaging.measureDistance(X1,Y1,X2,Y2,TiltAngle,TiltAxis,Geometry)` | True sample-frame distance with tilt correction | $L = \sqrt{\Delta x^{2} + (\Delta y/\sin\theta)^{2}}$ (or $\cos\theta$) |
| `imaging.lineProfile(img,X1,Y1,X2,Y2,TiltAngle,Geometry)` | Tilt-corrected 1-D line scan | as above |
| `imaging.getStageTilt(imgInfo)` | Extract stage tilt from FEI/Bruker metadata | — |
| **Electron optics** | | |
| `imaging.calcElectronWavelength(kV)` | Relativistic de Broglie $\lambda$ | $\lambda = h/\sqrt{2 m_0 e V(1+ eV/2 m_0 c^{2})}$ |
| `imaging.estimateCTF(img,Voltage_kV,Cs_mm,PixelSize)` | Defocus from Thon-ring FFT | $\chi(k) = \pi\lambda k^{2}\Delta f - \tfrac{1}{2}\pi C_s\lambda^{3}k^{4}$, CTF = $\sin\chi$ |
| **Strain mapping** | | |
| `imaging.geometricPhaseAnalysis(img,g1,g2,MaskRadius,MaskOrder,PixelSize)` | 2-D strain tensor from HRTEM lattice | $\phi_g = -2\pi\,\mathbf{g}\cdot\mathbf{u}$; $\varepsilon_{ij} = \tfrac{1}{2}(\partial_i u_j + \partial_j u_i)$ |
| **Diffraction analysis** | | |
| `imaging.azimuthalIntegrate(img,Center,NumBins,SectorMin,SectorMax,PixelSize)` | 2-D pattern → 1-D $I(q)$ | $I_j = \langle I_p\rangle_{R\in\text{bin}_j}$, $q = 4\pi\sin\theta/\lambda$ |
| `imaging.findDiffractionSpots(img,MinRadius,Threshold,MinSeparation,MaxSpots,Sigma)` | Local-max spot detection with NMS | local max + threshold + sub-pixel Gaussian centroid |
| `imaging.indexDiffraction(spotPositions,imgSize,PixelSize,CameraLength,AccVoltage,Tolerance,TopN)` | Match spots to phase database | $d = \lambda L/(R p)$ (TEM) or $d = N p/R$ (FFT); $\lvert\Delta d/d\rvert<\eta$ |
| `imaging.latticeMeasure(spot1,spot2,imgSize,PixelSize)` | Real-space lattice from 2 FFT/SAED spots | $[\mathbf{a}_1\;\mathbf{a}_2] = \mathbf{G}^{-T}$ |
| `imaging.simulateDiffraction(...)` | Forward-simulate kinematic SAED for a phase | structure factor $F_{hkl}$ |
| `imaging.virtualDarkField(...)` | Virtual-aperture image from a 4D-STEM stack | $I_\text{VDF}(\mathbf{r}) = \int_{\Omega} I(\mathbf{r},\mathbf{k})\,d^{2}k$ |
| **Profile / interface analysis** | | |
| `imaging.fitInterfaceWidth(x,y,Model)` | erf or sigmoid fit to a line scan | $I = I_0 + (A/2)[1+\mathrm{erf}((x-x_0)/\sigma\sqrt 2)]$ |
| `imaging.radialProfile(img,Center,NumBins)` | Mean intensity vs radius (analogue of azimuthalIntegrate) | $I(R) = \langle I_p\rangle_{|\mathbf{r}_p-\mathbf{c}|=R}$ |
| `imaging.surfaceRoughness(img,...)` | RMS / Ra surface-height statistics | $R_q = \sqrt{\langle(h-\bar h)^{2}\rangle}$ |
| **Image processing** | | |
| `imaging.computeFFT(img)` | Magnitude / phase FFT with shift | $\mathcal{F}\{I\}$, fftshift |
| `imaging.applyGaussian(img,Sigma)` | Gaussian blur | convolution with $\exp(-r^{2}/2\sigma^{2})$ |
| `imaging.applyMedian(img,Size)` | Median filter | rank statistics |
| `imaging.butterworthFilter(img,Cutoff,Order,Type)` | Low/high/band-pass filter | $H(k) = 1/[1+(k/k_c)^{2n}]$ |
| `imaging.unsharpMask(img,Radius,Amount)` | Edge enhancement | $I_\text{sharp} = I + \alpha(I - G_\sigma * I)$ |
| `imaging.clahe(img,...)` | Contrast-limited adaptive histogram eq. | per-tile histogram clip + interpolation |
| `imaging.adjustContrast(img,...)` | Linear contrast / gamma | $I' = (I-I_\text{lo})^{\gamma}$ |
| `imaging.noiseEstimate(img)` | Pixelwise noise std via MAD | $\sigma \approx 1.4826\,\mathrm{MAD}$ |
| `imaging.planeLevel(img)` | Plane-fit subtraction | least-squares plane removal |
| **Geometry helpers** | | |
| `imaging.binImage(img,N)`, `imaging.areaDownsample(img,N)` | Pixel binning / downsample | block averaging |
| `imaging.stitchImages(...)` | Tile stitching | phase-correlation alignment |
| `imaging.backProject(...)` | Sinogram → image (parallel beam) | inverse Radon |
| `imaging.distanceTransform(mask)` | Per-pixel distance to nearest mask edge | Euclidean DT |
| **Object analysis** | | |
| `imaging.particleAnalysis(mask)` | Connected components + per-particle stats | morphology + region props |
| `imaging.connectedComponents(mask)` | Labelled components | union-find |
| `imaging.morphOp(mask,Op)` | Dilate / erode / open / close | structuring-element morphology |
| `imaging.watershed(img)` | Watershed segmentation | meyer's algorithm |
| `imaging.multiOtsu(img,N)` | $N$-class Otsu thresholding | between-class variance maximisation |
| `imaging.templateMatch(img,template)` | Normalised cross-correlation | NCC |
| `imaging.countDefectLines(img,...)` | Count line defects (e.g., dislocations) | Hough / line-detection |

For per-function call signatures and worked examples, see `+imaging/README.md` and the docstring of each function. EELS-specific routines (`+imaging/eels*.m`) and EDS-specific routines (`+imaging/eds*.m`, `+imaging/cliffLorimer.m`, `+imaging/zafCorrection.m`) are documented in `docs/theory/spectroscopy.md`.
