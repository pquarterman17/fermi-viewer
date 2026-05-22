#!/usr/bin/env bash
# Run GUI tests on macOS/Linux — MATLAB -batch is already headless on Unix,
# so no WindowStyle Hidden wrapper is needed (unlike Windows).
#
# Usage:  bash tests/run_gui_hidden.sh [group]
#   group defaults to "fvgui" if omitted.

set -euo pipefail

GROUP="${1:-fvgui}"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Find MATLAB executable
if command -v matlab &>/dev/null; then
    MATLAB_BIN="matlab"
elif [ -d "/Applications" ]; then
    # macOS: find latest MATLAB.app
    MATLAB_APP=$(ls -d /Applications/MATLAB_R*.app 2>/dev/null | sort -V | tail -1)
    if [ -n "$MATLAB_APP" ]; then
        MATLAB_BIN="$MATLAB_APP/bin/matlab"
    fi
fi

if [ -z "${MATLAB_BIN:-}" ]; then
    echo "Error: MATLAB not found on PATH or in /Applications" >&2
    exit 1
fi

echo "Running GUI tests (Group=$GROUP) via: $MATLAB_BIN"
# Headless mode: GUI launchers detect FERMI_VIEWER_HEADLESS=1 and
# default Visible='off'. tests/shadows/ is added to the path so bare
# uialert()/uiconfirm() calls in source files are intercepted by the
# path-shadow files without any source-code changes. The groot default
# catches secondary uifigures opened by callbacks.
export FERMI_VIEWER_HEADLESS=1
"$MATLAB_BIN" -batch "cd('$SCRIPT_DIR'); set(groot,'DefaultFigureVisible','off'); addpath(pwd); setupToolbox; addpath(fullfile(pwd,'tests','shadows'),'-begin'); runAllTests(Group='$GROUP')"
