# Contributing to FermiViewer

Thanks for considering a contribution. FermiViewer is a small open-source
MATLAB toolbox; the workflow below keeps PRs predictable.

## Reporting bugs

Open a GitHub issue with:

1. **What you tried** — the MATLAB command(s) or GUI action sequence.
2. **What happened** — error message (full stack trace if you have one),
   screenshot if it's a layout/rendering issue.
3. **What you expected.**
4. **Environment** — MATLAB version (`ver` output), OS, and a sample data
   file if the bug is parser-related (DM3/DM4/SER/MRC/BCF) and you can
   share one.

## Submitting a pull request

### Branch naming

| Type | Prefix | Example |
|------|--------|---------|
| Feature | `feat/` | `feat/eels-batch-fit` |
| Bug fix | `fix/` | `fix/scale-bar-flicker` |
| Refactor | `refactor/` | `refactor/extract-fft-mask-dialog` |
| Docs | `docs/` | `docs/eels-tutorial-fixes` |
| Tests | `test/` | `test/dm4-multi-image-list` |

### Commit messages

Format: `<type>(<scope>): <description>` — imperative mood, lowercase,
no period, ≤72 chars.

Types: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `perf`, `style`.
Scope is optional but encouraged (`parser`, `gui`, `imaging`, `eels`, `eds`,
`diffraction`, `workshop`).

Examples:

```
feat(eels): add Hartree-Slater cross-section for absolute quantification
fix(diffraction): correct ring overlay alignment under non-square pixels
refactor(workshop): extract EDS quantification into ProcessingWorkshop hook
docs: add EELS thickness-mapping tutorial
```

For multi-line commits, blank line then explain *why* (not *what*).

### Workflow

1. **Fork** the repo and create a feature branch from `main`.
2. **Implement** + add tests for new behaviour.
3. **Run the test suite locally** before pushing:
   ```matlab
   setupToolbox
   runAllTests                       % full suite
   runAllTests(Group="fv")           % just EM utilities (fast)
   runAllTests(Group="fvgui")        % GUI tests (headless, slower)
   ```
   GUI tests use MATLAB's headless mode — see
   `tests/run_gui_hidden.ps1` (Windows) / `tests/run_gui_hidden.sh`
   (macOS/Linux).
4. **Push** and open a PR. CI runs `checkcode` (MATLAB lint) on
   changed `.m` files; runtime tests are local-only for now.
5. **Address review comments** by adding new commits (don't force-push
   until the PR is approved — keeps reviewer context intact).

## Code conventions

- **Functions:** `PascalCase` — **Variables:** `camelCase` — **Struct fields:** lowercase
- **Parameters:** named arguments via `arguments` block (R2021b+)
- **No external toolboxes** — implement against MATLAB built-ins only.
  This is a hard rule; image processing, optimization, and statistics
  functionality lives in-package.
- **MATLAB R2022b+** is the floor. If a newer API gives a clearly better
  result, branch with `isMATLABReleaseOlderThan('R20XXx')` and provide
  an R2022b fallback that prints a one-time upgrade hint.
- **Unified data struct:** parsers return `.time`, `.values`, `.labels`,
  `.units`, `.metadata` via `parser.createDataStruct()`. Never return
  raw matrices or ad-hoc structs.
- **Section dividers:** `% ════════...` style.
- **Default to no comments** in new code. Only add a comment when the
  *why* is non-obvious (workaround, hidden constraint, subtle invariant).
  Identifiers should carry the *what*.

### Adding a new parser

1. Implement `+parser/importXYZ.m` returning a unified data struct.
2. Register the extension in `+parser/resolveParser.m`.
3. Add a test in `tests/parser/` using either synthetic or fixture data
   from `+test_datasets/`.

### Adding a new FermiViewer feature

Heavy features go in a `+fermiViewer/+<feature>/` subpackage with the
workshop pattern: a `<Feature>WorkshopModel` handle class for state, a
functional view builder, and callbacks operating on `(model, hook)`
rather than the parent's closure. See `+fermiViewer/+contrast/`,
`+fermiViewer/+eels/`, or `+fermiViewer/+eds/` for reference patterns.

Do not add new nested functions to `FermiViewer.m` — the size ratchet
(`tests/imaging/test_fermiViewerSize.m`) enforces line and nested-function
ceilings that only ever move downward.

## License

By contributing, you agree your contribution will be licensed under the
[Apache License 2.0](LICENSE).
