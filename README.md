# FermiViewer

Interactive MATLAB GUI for electron microscopy image analysis — TEM/STEM imaging,
EELS spectroscopy, EDS elemental mapping, electron diffraction indexing, and FFT
analysis. No external toolboxes required.

**Status:** alpha — split from
[quantized_matlab](https://github.com/pquarterman17/Quantized_matlab) on
2026-05-21. APIs may shift before v1.0.

---

## Why FermiViewer

A single MATLAB GUI that imports the raw output of every common electron
microscope (Gatan, FEI/Thermo, Bruker, JEOL, generic TIFF/RAW), shows you the
image, and lets you do real analysis on it — measurements, FFT, EELS background
subtraction, EDS quantification, diffraction indexing — without leaving the
window or installing a single extra toolbox.

If you have MATLAB R2022b and a `.dm3` file, you can run FermiViewer.

## Features

- **Image import** — Gatan DM3/DM4, FEI SER, MRC, Bruker BCF (EDS spectrum
  images), generic TIFF/PNG/JPG, headerless RAW
- **Display** — auto-contrast (2nd/98th percentile), manual Low/High sliders,
  CLAHE, colormap selection, colorbar, live histogram
- **Measurements** — line profile (with export), distance, angle, polyline, ROI
  statistics (mean/std/min/max/area + mini-histogram). Drag-to-reposition
  labels; tilt-corrected labels documented inline
- **Processing** — Gaussian, median, CLAHE, rotate/flip, FFT display, FFT
  masking with inverse, crop, zoom box
- **EELS analysis** — power-law / exponential background subtraction, ~50
  built-in core-loss edges, elemental maps from spectrum images, t/λ thickness
  mapping, zero-loss peak alignment
- **EDS quantification** — Cliff-Lorimer thin-film from element maps, 47-element
  k-factor table (200 kV), atomic%/weight% maps, composition profiles
- **Diffraction indexing** — auto spot detection, ~50-phase crystal database
  match, zone-axis ID, ring overlays. Supports FFT and calibrated TEM
  diffraction (camera length input)
- **Advanced** — particle counting, drift correction, color overlay / channel
  merge, EDS multi-channel composite, template matching, image stitching,
  noise characterization

See [docs/gui_emviewer.md](docs/gui_emviewer.md) for the full feature reference.

## Quick start

```matlab
% Add toolbox to MATLAB path (run once per session)
setupToolbox

% Launch the GUI
FermiViewer

% Programmatic / scripted use
api = FermiViewer();
api.loadImages({'sem_image.tif'});
api.autoContrast();
api.getLineProfile(10, 10, 200, 200);
api.close();
```

## Install

```
git clone https://github.com/pquarterman17/fermi-viewer
cd fermi-viewer
matlab -r "setupToolbox; FermiViewer"
```

**Requirements:** MATLAB R2022b or later. No external toolboxes — all
algorithms are implemented against MATLAB built-ins (image processing,
statistics, optimization functionality is provided in-package).

**Cross-platform:** tested on Windows 11 and macOS. Paths use forward slashes
or `fullfile()`; no hardcoded absolute paths.

## Testing

```matlab
runAllTests                       % full suite
runAllTests(Group="fv")           % EM parser + imaging utility tests
runAllTests(Group="fvgui")        % FermiViewer GUI API tests (headless)
runAllTests(Group="eels")         % EELS-specific tests
runAllTests(Group="eds")          % EDS-specific tests
runAllTests(Group="diffindex")    % diffraction indexing
```

GUI tests run in MATLAB's headless mode — see `tests/run_gui_hidden.ps1`
(Windows) and `tests/run_gui_hidden.sh` (macOS/Linux).

Sample electron-microscopy files for the real-data tests live in
`+test_datasets/Microscopy/` and `+test_datasets/BCF/` (tracked in git).
Largest individual file is ~17 MB; total ~210 MB.

## Interop with quantized_matlab

[quantized_matlab](https://github.com/pquarterman17/Quantized_matlab) (the
parent toolbox) covers magnetometry, XRD, reflectometry, transport, and other
non-imaging data. FermiViewer was split out for focus; the two interoperate
via files:

- **Line profile → BosonPlotter:** in FermiViewer, take a line profile,
  click *Export* → CSV. In BosonPlotter, *File → Import* the CSV. Profile
  intensity vs. distance plots immediately, with the calibrated pixel-unit
  on the x-axis.
- **EELS spectrum → BosonPlotter:** same path. The exported CSV is
  parser-agnostic (`parser.importCSV`).

Two MATLAB sessions can't share variables, so the CSV bridge is the
contract. No installation of qm is required to run fv, and vice versa.

## Architecture (one-paragraph orientation)

The orchestrator `FermiViewer.m` builds the GUI and dispatches to package
functions in `+fermiViewer/` (chrome: theme tokens, headless helpers, alerts)
and the EM feature subpackages (`+fermiViewer/+contrast/`, `+fermiViewer/+eds/`,
`+fermiViewer/+eels/`, `+fermiViewer/+diffraction/`, etc.). Image processing
algorithms live in `+imaging/`. Data import goes through `+parser/` and returns
a unified struct (`.time`, `.values`, `.labels`, `.units`, `.metadata`) — same
contract as quantized_matlab.

See [docs/development.md](docs/development.md) for the developer-facing details.

## License

Apache License 2.0 — see [LICENSE](LICENSE) and [NOTICE](NOTICE).

Permissive license with an express patent grant. Use it commercially, fork it,
embed it in proprietary tools — just keep the copyright notice and license
text.

## Citation

If you use FermiViewer in a publication, please cite via the
[CITATION.cff](CITATION.cff) metadata (forthcoming).

## Contributing

Bug reports and PRs welcome. Branch naming and commit-message conventions in
[CONTRIBUTING.md](CONTRIBUTING.md). Run `runAllTests` locally before pushing —
CI is lint-only.
