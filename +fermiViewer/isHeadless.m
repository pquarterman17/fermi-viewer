function tf = isHeadless()
%ISHEADLESS  True when the QUANTIZED_MATLAB_HEADLESS env var is set.
%   Used by every GUI launcher (FermiViewer, BosonPlotter, DiraCulator,
%   DataWorkspace) and by quietAlert / quietConfirm to suppress popups,
%   dialogs, and focus-stealing figure windows during automated tests.
%
%   The env var is set by tests/run_gui_hidden.ps1 / .sh. A test that
%   needs to force-show a window can call FermiViewer(Visible='on')
%   explicitly, which overrides the headless default.
%
%   Returns a logical scalar (never errors).
    tf = strcmp(getenv('QUANTIZED_MATLAB_HEADLESS'), '1');
end
