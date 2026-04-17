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

### Implementation

| Function | What it does |
|----------|--------------|
| `imaging.measureDistance(X1, Y1, X2, Y2, TiltAngle=θ, TiltAxis=A, Geometry=G)` | Returns the true sample-frame Euclidean distance between two image points. |
| `imaging.lineProfile(img, X1, Y1, X2, Y2, TiltAngle=θ, Geometry=G)` | Returns a line-profile whose distance axis is already rescaled to the true sample frame. |
| `imaging.getStageTilt(imgInfo)` | Parses FEI `StageT` / Bruker `Tilt` metadata into a degree value usable by the above. |

The FermiViewer **Tilt corr.** checkbox turns the correction on/off, the **spinner** sets $\theta$ (auto-populated from metadata when available), and the **Geometry** dropdown selects Surface vs Cross-section. Tilt-corrected distance labels on the image are marked with an asterisk ($\ast$); hovering the asterisk shows the exact $1/\sin$ or $1/\cos$ factor applied.
