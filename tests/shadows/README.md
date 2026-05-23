# tests/shadows/

Path-shadow stubs for blocking dialog functions. Added to MATLAB's path
(via `addpath(...,'-begin')`) by `tests/run_gui_hidden.ps1` and
`tests/run_gui_hidden.sh` so that any bare `uialert` / `uiconfirm` /
`inputdlg` / `questdlg` call in production code resolves to the
no-op stub here instead of blocking the headless test runner forever.

Production code should still prefer the explicit `+fermiViewer/+chrome/`
guards (`quietAlert`, `quietConfirm`) — those are the documented
contract. These shadows are belt-and-suspenders for cases where:

- A bare dialog call sneaks in (new code, third-party deps).
- A built-in MATLAB path triggers a dialog we don't control.
- A test path bypasses the chrome guard.

Each shadow returns the "user cancelled / no" sentinel the production
code expects on a missing-user scenario, and logs `[shadow:<name>]` to
the Command Window so the test diary records what would have been
shown.

| Shadow | Returns | Cancelled-path behaviour |
|---|---|---|
| `uialert.m` | nothing | callers don't await result |
| `uiconfirm.m` | `'Cancel'` | most call sites treat as no-op |
| `inputdlg.m` | `{}` | empty cell = user cancelled |
| `questdlg.m` | `''` | empty char = user closed dialog |
| `msgbox.m` | empty handle | legacy API, no caller awaits |
| `warndlg.m` | empty handle | same as msgbox |
| `errordlg.m` | empty handle | same as msgbox |

Not shadowed (intentionally): `uigetfile`, `uiputfile`, `uisetcolor` —
these are file/colour pickers; tests should pass paths/colors
explicitly, never go through the picker.
