# +imaging/ — EM Image Processing Utilities

No external toolboxes required. All functions use MATLAB built-ins.

## Core Image Processing

| Function | Description |
|----------|-------------|
| `adjustContrast` | Window/level linear stretch; clamps to [Low, High] |
| `applyGaussian` | 2D Gaussian filter via `conv2` with manual kernel |
| `applyMedian` | 2D median filter (vectorised sort; window 3–7) |
| `computeFFT` | FFT magnitude/phase display; `fft2` + `fftshift` + log scaling |
| `lineProfile` | Intensity along a line via `interp2`; optional pixel calibration |
| `measureDistance` | Calibrated point-to-point Euclidean distance |
| `addScaleBar` | Scale bar rectangle + label overlay on axes |
| `addColorbar` | Colorbar with label overlay |
| `generateThumbnail` | Downsample via block-averaging or bilinear `interp2` |
| `unsharpMask` | Sharpen via unsharp mask |
| `morphOp` | Morphological operations (erode/dilate/open/close) |
| `multiOtsu` | Multi-level Otsu thresholding |
| `planeLevel` | Plane-fit background leveling |
| `binImage` | Pixel binning for noise reduction |
| `noiseEstimate` | MAD/local-variance noise estimation |
| `butterworthFilter` | Butterworth frequency-domain filter |
| `surfaceRoughness` | Surface roughness metrics (Ra, Rq, Rz) |
| `radialProfile` | Radial average from center |
| `azimuthalIntegrate` | Azimuthal integration of diffraction patterns |
| `buildFigurePanel` | Multi-panel figure layout helper |

## EELS Analysis

| Function | Description |
|----------|-------------|
| `eelsEdgeTable` | Built-in core-loss edge database (~50 edges) |
| `eelsBackground` | Power-law/exponential background subtraction |
| `eelsThicknessMap` | Log-ratio t/λ thickness from spectrum image |
| `eelsAlignZLP` | Zero-loss peak alignment via cross-correlation |
| `eelsExtractMap` | Elemental map extraction from spectrum image |
| `eelsFourierLog` | Fourier-log deconvolution for plural scattering removal |
| `eelsELNES` | ELNES fine structure analysis |
| `eelsKramersKronig` | Kramers-Kronig analysis for dielectric function |
| `eelsSVD(cube, energyAxis)` | SVD decomposition of an EELS spectrum image cube to extract spectral components |

## Diffraction

| Function | Description |
|----------|-------------|
| `calcElectronWavelength` | Relativistic electron wavelength (kV → Å) |
| `findDiffractionSpots` | Auto-detect spots in FFT/diffraction patterns |
| `indexDiffraction` | Match spots to crystal phase database |
| `simulateDiffraction` | Simulate diffraction pattern for a crystal phase |
| `virtualDarkField` | Virtual dark-field imaging from diffraction spots |
| `latticeMeasure` | Lattice spacing measurement from HRTEM/FFT |
| `geometricPhaseAnalysis` | GPA strain mapping |
| `estimateCTF` | CTF estimation from FFT |
| `countDefectLines` | Defect line density measurement |
| `fitInterfaceWidth` | Interface width fitting from profiles |
| `backProject` | Back-projection for tomographic reconstruction |

## EDS Quantification

| Function | Description |
|----------|-------------|
| `cliffLorimer` | Cliff-Lorimer thin-film EDS quantification |
| `edsKFactorTable` | Built-in k-factors (47 elements, 200 kV) |
| `edsCompositionProfile` | Composition line profile from EDS maps |
| `massAbsorptionCoeff` | Mass absorption coefficients |
| `zafCorrection` | ZAF matrix correction for bulk EDS |

## Morphology and Segmentation

| Function | Description |
|----------|-------------|
| `clahe(img)` | Contrast-Limited Adaptive Histogram Equalization (no toolbox) |
| `connectedComponents(bw)` | Label connected regions in a binary mask; returns label matrix L and count |
| `distanceTransform(bw)` | Chamfer distance transform of a binary mask |
| `particleAnalysis(img)` | Threshold an image and measure per-particle statistics (area, centroid, aspect ratio) |
| `watershed(bw)` | Marker-controlled watershed segmentation to split touching particles |

#### Example
```matlab
% Segment and measure nanoparticles in a HAADF image
img = parser.importTIFF('nanoparticles.tif');
enhanced  = imaging.clahe(img.values, TileSize=64, ClipLimit=0.02);
[L, n]    = imaging.connectedComponents(enhanced > 0.5);
result    = imaging.particleAnalysis(enhanced, MinArea=10);
fprintf('%d particles detected, mean diameter = %.1f nm\n', ...
    result.count, mean(result.diameter_nm));
```

---

## Other

| Function | Description |
|----------|-------------|
| `templateMatch` | NCC-based template matching |
| `stitchImages` | Panoramic mosaic from overlapping tiles |
