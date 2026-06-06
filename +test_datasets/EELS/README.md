# EELS real-instrument test data (local-only, not in git)

Real DM4 EELS spectrum images used by `tests/imaging/test_eels_real_dm4.m`
(run via `runAllTests(Group="eels_adv")`). These files are **gitignored** to
keep the repository small — the test skips gracefully when they are absent.

**To fetch them on a new machine, run:**

```matlab
tests.fetchRealEelsData   % or: run tests/fetchRealEelsData.m
```

## Files and provenance

### Zenodo record 8403583 — CC-BY 4.0

Burgess, K.D., Cymes, B.A., Stroud, R.M., *"Hydrogen-bearing vesicles in
space weathered lunar calcium-phosphates"* — STEM-EELS of lunar sample
79221. <https://doi.org/10.5281/zenodo.8403583>

| File | Size | Contents |
|---|---|---|
| `FigS6_apatite_ZLP.dm4` | 20.7 MB | Low-loss SI with ZLP, 50×52 px × 2024 ch, −9.2…91.9 eV @ 0.05 eV/ch. ZLP at 0.01 eV — calibration oracle. |
| `Fig4_apatite79221_OKedge_vesicle.dm4` | 20.9 MB | Core-loss SI, O-K edge (532 eV), 50×52 px × 2048 ch, 490…592 eV |
| `Fig4_apatite79221_lowloss_vesicle.dm4` | 20.9 MB | Low-loss SI (ZLP cut off at 2 eV), plasmon ~23 eV |
| `FigS4_apatite79221_F_Fe.dm4` | 19.0 MB | Core-loss SI, F-K (685 eV) + Fe-L23 (708 eV), 30×80 px × 2048 ch |

Also fetched from the same record into sibling folders (likewise gitignored):

| File | Location | Contents |
|---|---|---|
| `Fig3c_apatite_HAADF.dm4` | `../Microscopy/` | 2D HAADF image, 1024×1024, 0.122 nm/px — joins the real-DM GUI sweep |
| `Fig4b_EDSmap_Bruker.bcf` | `../BCF/` | Real Esprit EDS map, 512×512 px × 4096 ch. Regression file for the SFS multi-chunk pointer-table fix (any internal file > ~4 MB). |

### rosettasciio (hyperspy) test corpus

| File | Size | Contents |
|---|---|---|
| `rosettasciio_EELS_SI.dm4` | 0.3 MB | Tiny GMS EELS SI, 2×2 px × 2048 ch, 300…2347 eV — fast CI-grade fixture |

Source: <https://github.com/hyperspy/rosettasciio>
(`rsciio/tests/data/digitalmicrograph/3D/EELS_SI.dm4`), same origin as the
already-present `../Microscopy/rosettasciio_2D_test1.dm4`.

## Why these files matter

The 2026-06-06 import of this corpus exposed two parser bugs invisible to
synthetic data:

1. **DM4/DM3 3D SI dimension mapping** — energy is the *last* (slowest)
   dimension in real GMS spectrum images, not the first; plus the DM
   calibration convention is `value = (index − origin) × scale`. Every SI
   cube previously imported transposed with a channel-index energy axis.
2. **BCF SFS chunk chain** — the pointer table of any internal file over
   ~4 MB spans multiple chunks chained through chunk headers; reading it
   contiguously crashed on real Esprit maps.
