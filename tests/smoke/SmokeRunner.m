classdef SmokeRunner < handle
%SMOKERUNNER  Framework for GUI interaction smoke tests.
%
%   sr = SmokeRunner(fig)  — create a runner bound to a uifigure
%   sr = SmokeRunner(fig, SnapshotDir=dir)  — custom screenshot output
%
%   Interaction methods (each returns true on success, false on failure):
%     sr.fireButton(text)
%     sr.fireStateButton(text, value)
%     sr.setDropdown(identifier, value)
%     sr.setEditField(identifier, value)
%     sr.setCheckbox(text, value)
%     sr.pressKey(key)
%     sr.pressKey(key, Modifier="control")
%
%   Snapshot methods:
%     path = sr.captureSnapshot(name)
%
%   Sequence runner:
%     sr.runSequence(steps)  — cell array of {action, args...} tuples
%
%   Results:
%     sr.summary()   — print pass/fail counts + failure list
%     sr.assertAllPassed()  — error if any failures
%     sr.passed, sr.failed, sr.failures  — direct access
%
%   Example:
%     api = FermiViewer('Visible','off'); drawnow;
%     sr = SmokeRunner(api.fig);
%     sr.fireButton('Zoom In');
%     sr.setDropdown('Linear', 'Log');
%     sr.pressKey('z');
%     sr.captureSnapshot('after_zoom');
%     sr.summary();
%     api.close();

    properties (SetAccess = private)
        fig
        passed   (1,1) double = 0
        failed   (1,1) double = 0
        failures cell   = {}
        snapshots cell  = {}
        snapshotDir char
    end

    properties (Access = private)
        dialogTimer
    end

    methods
        function obj = SmokeRunner(fig, options)
            arguments
                fig (1,1) matlab.ui.Figure
                options.SnapshotDir char = ''
            end
            obj.fig = fig;
            if isempty(options.SnapshotDir)
                obj.snapshotDir = fullfile(fileparts(mfilename('fullpath')), ...
                    'screenshots');
            else
                obj.snapshotDir = options.SnapshotDir;
            end
            if ~isfolder(obj.snapshotDir)
                mkdir(obj.snapshotDir);
            end
        end

        % ════════════════════════════════════════════════════════════════
        %  Button interactions
        % ════════════════════════════════════════════════════════════════

        function ok = fireButton(obj, text, options)
        %FIREBUTTON  Find a uibutton by Text, assert enabled, fire callback.
            arguments
                obj
                text char
                options.Scope = []
            end
            label = sprintf('fireButton("%s")', text);
            scope = obj.resolveScope(options.Scope);
            btn = obj.findByTypeAndText('uibutton', text, scope);
            if isempty(btn)
                ok = obj.recordFail(label, 'button not found');
                return;
            end
            if ~strcmp(btn.Enable, 'on')
                ok = obj.recordFail(label, sprintf('Enable=%s', btn.Enable));
                return;
            end
            if isempty(btn.ButtonPushedFcn)
                ok = obj.recordFail(label, 'callback is empty');
                return;
            end
            ok = obj.safeCall(label, @() obj.invokeCallback(btn, 'ButtonPushedFcn'));
        end

        function ok = fireButtonByTooltip(obj, tooltipFragment, options)
        %FIREBUTTONBYTOOLTIP  Find a uibutton by Tooltip substring, fire it.
        %   Use for icon-only buttons (empty Text) that have a Tooltip.
            arguments
                obj
                tooltipFragment char
                options.Scope = []
            end
            label = sprintf('fireButton(tooltip~"%s")', tooltipFragment);
            scope = obj.resolveScope(options.Scope);
            allBtns = findall(scope, 'Type', 'uibutton');
            btn = [];
            for k = 1:numel(allBtns)
                tip = allBtns(k).Tooltip;
                if ischar(tip) || isstring(tip)
                    if contains(string(tip), tooltipFragment, 'IgnoreCase', true)
                        btn = allBtns(k); break;
                    end
                end
            end
            if isempty(btn)
                ok = obj.recordFail(label, 'button not found');
                return;
            end
            if ~strcmp(btn.Enable, 'on')
                ok = obj.recordFail(label, sprintf('Enable=%s', btn.Enable));
                return;
            end
            if isempty(btn.ButtonPushedFcn)
                ok = obj.recordFail(label, 'callback is empty');
                return;
            end
            ok = obj.safeCall(label, @() obj.invokeCallback(btn, 'ButtonPushedFcn'));
        end

        function ok = fireButtonByTag(obj, tag, options)
        %FIREBUTTONBYTAG  Find a uibutton by Tag, fire it.
            arguments
                obj
                tag char
                options.Scope = []
            end
            label = sprintf('fireButton(tag="%s")', tag);
            scope = obj.resolveScope(options.Scope);
            btn = findall(scope, 'Type', 'uibutton', 'Tag', tag);
            if numel(btn) > 1, btn = btn(1); end
            if isempty(btn)
                ok = obj.recordFail(label, 'button not found');
                return;
            end
            if ~strcmp(btn.Enable, 'on')
                ok = obj.recordFail(label, sprintf('Enable=%s', btn.Enable));
                return;
            end
            if isempty(btn.ButtonPushedFcn)
                ok = obj.recordFail(label, 'callback is empty');
                return;
            end
            ok = obj.safeCall(label, @() obj.invokeCallback(btn, 'ButtonPushedFcn'));
        end

        function ok = fireStateButton(obj, text, value, options)
        %FIRESTATEBUTTON  Toggle a uistatebutton and fire its callback.
            arguments
                obj
                text char
                value (1,1) logical
                options.Scope = []
            end
            label = sprintf('fireStateButton("%s", %d)', text, value);
            scope = obj.resolveScope(options.Scope);
            btn = obj.findByTypeAndText('uistatebutton', text, scope);
            if isempty(btn)
                ok = obj.recordFail(label, 'state button not found');
                return;
            end
            if ~strcmp(btn.Enable, 'on')
                ok = obj.recordFail(label, sprintf('Enable=%s', btn.Enable));
                return;
            end
            btn.Value = value;
            ok = obj.safeCall(label, @() obj.invokeCallback(btn, 'ValueChangedFcn'));
        end

        % ════════════════════════════════════════════════════════════════
        %  Value-change interactions
        % ════════════════════════════════════════════════════════════════

        function ok = setDropdown(obj, identifier, value, options)
        %SETDROPDOWN  Find a dropdown by item content or Tag, set value, fire callback.
        %   identifier can be:
        %     - a string that appears in the dropdown's Items (partial match)
        %     - a Tag string (prefix with '#' to force tag lookup: '#myTag')
            arguments
                obj
                identifier char
                value
                options.Scope = []
            end
            label = sprintf('setDropdown("%s" → "%s")', identifier, string(value));
            scope = obj.resolveScope(options.Scope);

            if startsWith(identifier, '#')
                dd = findall(scope, 'Type', 'uidropdown', 'Tag', identifier(2:end));
                if numel(dd) > 1, dd = dd(1); end
            else
                dd = obj.findDropdownByItem(identifier, scope);
            end

            if isempty(dd)
                ok = obj.recordFail(label, 'dropdown not found');
                return;
            end
            if ~any(strcmp(dd.Items, value))
                ok = obj.recordFail(label, sprintf('"%s" not in Items', string(value)));
                return;
            end
            dd.Value = value;
            ok = obj.safeCall(label, @() obj.invokeCallback(dd, 'ValueChangedFcn'));
        end

        function ok = setEditField(obj, identifier, value, options)
        %SETEDITFIELD  Find an edit field by Tag or adjacent label, set value, fire callback.
        %   identifier: Tag string (prefix '#') or label text of adjacent uilabel.
            arguments
                obj
                identifier char
                value
                options.Scope = []
            end
            label = sprintf('setEditField("%s" → "%s")', identifier, string(value));
            scope = obj.resolveScope(options.Scope);

            if startsWith(identifier, '#')
                ef = findall(scope, 'Type', 'uieditfield', 'Tag', identifier(2:end));
                if isempty(ef)
                    ef = findall(scope, 'Type', 'uinumericeditfield', 'Tag', identifier(2:end));
                end
                if numel(ef) > 1, ef = ef(1); end
            else
                ef = obj.findEditFieldByLabel(identifier, scope);
            end

            if isempty(ef)
                ok = obj.recordFail(label, 'edit field not found');
                return;
            end
            ef.Value = value;
            ok = obj.safeCall(label, @() obj.invokeCallback(ef, 'ValueChangedFcn'));
        end

        function ok = setCheckbox(obj, text, value, options)
        %SETCHECKBOX  Find a checkbox by Text, set value, fire callback.
            arguments
                obj
                text char
                value (1,1) logical
                options.Scope = []
            end
            label = sprintf('setCheckbox("%s", %d)', text, value);
            scope = obj.resolveScope(options.Scope);
            cb = obj.findByTypeAndText('uicheckbox', text, scope);
            if isempty(cb)
                ok = obj.recordFail(label, 'checkbox not found');
                return;
            end
            cb.Value = value;
            ok = obj.safeCall(label, @() obj.invokeCallback(cb, 'ValueChangedFcn'));
        end

        % ════════════════════════════════════════════════════════════════
        %  Keyboard simulation
        % ════════════════════════════════════════════════════════════════

        function ok = pressKey(obj, key, options)
        %PRESSKEY  Simulate a key press on the figure.
            arguments
                obj
                key char
                options.Modifier char = ''
            end
            if isempty(options.Modifier)
                label = sprintf('pressKey("%s")', key);
            else
                label = sprintf('pressKey("%s+%s")', options.Modifier, key);
            end
            % Prefer WindowKeyPressFcn (fires when ANY child has focus),
            % fall back to KeyPressFcn (fires only when figure itself
            % has focus — older / less-robust pattern, but still valid).
            kpf = obj.fig.WindowKeyPressFcn;
            if isempty(kpf)
                kpf = obj.fig.KeyPressFcn;
            end
            if isempty(kpf)
                ok = obj.recordFail(label, 'WindowKeyPressFcn and KeyPressFcn both empty');
                return;
            end

            evt.Key = key;
            evt.Character = key;
            if isempty(options.Modifier)
                evt.Modifier = {};
            else
                evt.Modifier = {options.Modifier};
            end
            evt.Source = obj.fig;
            evt.EventName = 'WindowKeyPress';

            ok = obj.safeCall(label, @() feval(kpf, obj.fig, evt));
        end

        % ════════════════════════════════════════════════════════════════
        %  Snapshots
        % ════════════════════════════════════════════════════════════════

        function outPath = captureSnapshot(obj, name)
        %CAPTURESNAPSHOT  Save a screenshot of the figure via exportapp.
        %   Skips cleanly where the env can't render (headless + older
        %   MATLAB), so it doesn't spam SNAP FAIL on the R2022b CI leg.
            outPath = '';
            if ~fermiViewer.chrome.figureCaptureAvailable()
                fprintf('  SNAP SKIP  %s (figure capture unavailable)\n', name);
                return;
            end
            outPath = fullfile(obj.snapshotDir, [name '.png']);
            try
                exportapp(obj.fig, outPath);
                obj.snapshots{end+1} = outPath;
                fprintf('  SNAP  %s\n', name);
            catch ME
                fprintf('  SNAP FAIL  %s — %s\n', name, ME.message);
                outPath = '';
            end
        end

        % ════════════════════════════════════════════════════════════════
        %  Dialog auto-responder
        % ════════════════════════════════════════════════════════════════

        function startDialogAutoClose(obj, options)
        %STARTDIALOGAUTOCLOSE  Start a timer that auto-closes popup dialogs.
        %   Polls for new figures every 200ms. When a new figure appears
        %   that isn't the main figure, it looks for OK/Apply/Close buttons
        %   and fires the first one found, or just deletes the figure.
            arguments
                obj
                options.Timeout (1,1) double = 5
                options.Interval (1,1) double = 0.2
            end
            obj.stopDialogAutoClose();
            mainFig = obj.fig;
            startFigs = findall(groot, 'Type', 'figure');
            maxTicks = ceil(options.Timeout / options.Interval);
            ticks = 0;
            obj.dialogTimer = timer( ...
                'ExecutionMode', 'fixedRate', ...
                'Period', options.Interval, ...
                'TimerFcn', @onTick, ...
                'ErrorFcn', @(~,~) []);

            start(obj.dialogTimer);

            function onTick(~, ~)
                ticks = ticks + 1;
                if ticks > maxTicks
                    obj.stopDialogAutoClose();
                    return;
                end
                allFigs = findall(groot, 'Type', 'figure');
                for ii = 1:numel(allFigs)
                    f = allFigs(ii);
                    if ~isvalid(f) || isequal(f, mainFig), continue; end
                    if any(arrayfun(@(s) isequal(f, s), startFigs)), continue; end
                    tryCloseDialog(f);
                    obj.stopDialogAutoClose();
                    return;
                end
            end

            function tryCloseDialog(dlgFig)
                drawnow;
                closeLabels = {'OK', 'Close', 'Cancel', 'Apply', 'Done'};
                btns = findall(dlgFig, 'Type', 'uibutton');
                for ii = 1:numel(closeLabels)
                    for jj = 1:numel(btns)
                        if isvalid(btns(jj)) && strcmp(btns(jj).Text, closeLabels{ii})
                            try
                                btns(jj).ButtonPushedFcn(btns(jj), []);
                            catch
                            end
                            drawnow;
                            if isvalid(dlgFig)
                                delete(dlgFig);
                            end
                            return;
                        end
                    end
                end
                delete(dlgFig);
            end
        end

        function stopDialogAutoClose(obj)
        %STOPDIALOGAUTOCLOSE  Stop the dialog auto-close timer if running.
            if ~isempty(obj.dialogTimer) && isvalid(obj.dialogTimer)
                stop(obj.dialogTimer);
                delete(obj.dialogTimer);
            end
            obj.dialogTimer = [];
        end

        % ════════════════════════════════════════════════════════════════
        %  Popup cleanup
        % ════════════════════════════════════════════════════════════════

        function closePopups(obj)
        %CLOSEPOPUPS  Close any figures that aren't the main figure.
            allFigs = findall(groot, 'Type', 'figure');
            for ii = 1:numel(allFigs)
                f = allFigs(ii);
                if isvalid(f) && ~isequal(f, obj.fig)
                    delete(f);
                end
            end
            drawnow;
        end

        % ════════════════════════════════════════════════════════════════
        %  Sequence runner
        % ════════════════════════════════════════════════════════════════

        function runSequence(obj, steps)
        %RUNSEQUENCE  Execute a cell array of interaction steps.
        %   Each step is a cell: {action, arg1, arg2, ...}
        %   Actions: 'button', 'state', 'dropdown', 'edit', 'checkbox',
        %            'key', 'snap', 'pause', 'popups', 'dialogWatch'
        %
        %   Example:
        %     steps = {
        %         {'button',   'Zoom In'}
        %         {'dropdown', 'Linear', 'Log'}
        %         {'key',      'z'}
        %         {'snap',     'after_zoom'}
        %         {'pause',    0.5}
        %     };
        %     sr.runSequence(steps);
            for ii = 1:numel(steps)
                s = steps{ii};
                action = s{1};
                args = s(2:end);
                switch action
                    case 'button'
                        obj.fireButton(args{:});
                    case 'tooltipBtn'
                        obj.fireButtonByTooltip(args{:});
                    case 'tagBtn'
                        obj.fireButtonByTag(args{:});
                    case 'state'
                        obj.fireStateButton(args{:});
                    case 'dropdown'
                        obj.setDropdown(args{:});
                    case 'edit'
                        obj.setEditField(args{:});
                    case 'checkbox'
                        obj.setCheckbox(args{:});
                    case 'key'
                        obj.pressKey(args{:});
                    case 'snap'
                        obj.captureSnapshot(args{:});
                    case 'pause'
                        pause(args{1});
                    case 'popups'
                        obj.closePopups();
                    case 'dialogWatch'
                        obj.startDialogAutoClose(args{:});
                    otherwise
                        obj.recordFail(sprintf('step %d', ii), ...
                            sprintf('unknown action "%s"', action));
                end
            end
        end

        % ════════════════════════════════════════════════════════════════
        %  Results
        % ════════════════════════════════════════════════════════════════

        function summary(obj)
        %SUMMARY  Print pass/fail counts and failure details.
            fprintf('\n%s\n', repmat('=', 1, 60));
            fprintf('  SmokeRunner: %d passed, %d failed\n', obj.passed, obj.failed);
            if ~isempty(obj.snapshots)
                fprintf('  Snapshots: %d captured → %s\n', ...
                    numel(obj.snapshots), obj.snapshotDir);
            end
            if obj.failed > 0
                fprintf('\n  Failures:\n');
                for ii = 1:numel(obj.failures)
                    fprintf('    - %s\n', obj.failures{ii});
                end
            end
            fprintf('%s\n', repmat('=', 1, 60));
        end

        function ok = manualCheck(obj, label, fcn)
        %MANUALCHECK  Run a custom check that doesn't fit the standard patterns.
        %   fcn is a zero-arg function that should not throw on success.
            ok = obj.safeCall(label, fcn);
        end

        function assertAllPassed(obj)
        %ASSERTALLPASSED  Error if any test failed.
            if obj.failed > 0
                obj.summary();
                error('SmokeRunner:failed', '%d smoke test(s) failed', obj.failed);
            end
        end

        function delete(obj)
            obj.stopDialogAutoClose();
        end
    end

    % ════════════════════════════════════════════════════════════════════
    %  Private helpers
    % ════════════════════════════════════════════════════════════════════

    methods (Access = private)
        function scope = resolveScope(obj, scopeArg)
            if isempty(scopeArg)
                scope = obj.fig;
            else
                scope = scopeArg;
            end
        end

        function h = findByTypeAndText(~, type, text, scope)
            hits = findall(scope, 'Type', type, 'Text', text);
            if numel(hits) >= 1
                h = hits(1);
            else
                h = [];
            end
        end

        function dd = findDropdownByItem(~, itemText, scope)
            allDd = findall(scope, 'Type', 'uidropdown');
            dd = [];
            for k = 1:numel(allDd)
                if any(strcmp(allDd(k).Items, itemText))
                    dd = allDd(k);
                    return;
                end
            end
        end

        function ef = findEditFieldByLabel(~, labelText, scope)
            allLabels = findall(scope, 'Type', 'uilabel');
            ef = [];
            for k = 1:numel(allLabels)
                if contains(allLabels(k).Text, labelText)
                    parent = allLabels(k).Parent;
                    candidates = findall(parent, 'Type', 'uieditfield');
                    if isempty(candidates)
                        candidates = findall(parent, 'Type', 'uinumericeditfield');
                    end
                    if ~isempty(candidates)
                        ef = candidates(1);
                        return;
                    end
                end
            end
        end

        function invokeCallback(~, widget, callbackProp)
            cb = widget.(callbackProp);
            if ~isempty(cb)
                if isa(cb, 'function_handle')
                    cb(widget, []);
                elseif iscell(cb)
                    cb{1}(widget, [], cb{2:end});
                end
                drawnow;
            end
        end

        function ok = safeCall(obj, label, fcn)
            try
                fcn();
                drawnow;
                obj.passed = obj.passed + 1;
                fprintf('  PASS  %s\n', label);
                ok = true;
            catch ME
                ok = obj.recordFail(label, ME.message);
            end
        end

        function ok = recordFail(obj, label, msg)
            obj.failed = obj.failed + 1;
            entry = sprintf('%s — %s', label, msg);
            obj.failures{end+1} = entry;
            fprintf('  FAIL  %s\n', entry);
            ok = false;
        end
    end
end
