function out = factory_operator_console(kind, info)
%FACTORY_OPERATOR_CONSOLE  The operator's side of a manual-input cycle, at the console.
%
%   out = FACTORY_OPERATOR_CONSOLE(KIND, INFO)
%
%   RUN_FACTORY_SIMULATION calls this when it is run with 'Operator','console'.
%   It is the default 'OperatorInput' and asks for the same things the
%   machine's HMI does:
%
%     'engrave?'  before the cycle. Engrave this part (the 50 mm job), or skip
%                 engraving and send it through the SV11 bypass? Returns
%                 true or false. Enter alone means engrave.
%     'laser'     at S25, once the platform is up. Waits in REAL time while
%                 the laser runs, printing progress, and returns []. INFO is
%                 the laser time in seconds, or a struct with fields
%                   t     the laser time
%                   tick  a function called with the elapsed seconds about 10
%                         times a second (the live figure's countdown)
%     'eng_done'  straight after the laser. Waits for ENG DONE and returns
%                 how long you took in seconds. That reaction time becomes
%                 the operator part of the dwell. INFO is [] for Enter in the
%                 Command Window, or a struct with fields
%                   fig       the live figure: ANY KEY on it is ENG DONE
%                             (modifier keys alone - Shift, Ctrl, Alt - are not)
%                   fallback  optional; called if the figure is closed while
%                             waiting. Default: Enter in the Command Window.
%
%   WHY THE FIGURE AND THE COMMAND WINDOW ARE NOT BOTH LISTENING. MATLAB's
%   input() blocks until Enter, and nothing on a figure can cancel it. So in
%   a live run the figure takes ENG DONE, and the Command Window takes over
%   only if the figure is closed.
%
%   WHAT IS REAL TIME AND WHAT IS NOT. Only the laser wait and your reaction
%   run on the wall clock (and, with 'Live', the replay of the machine's
%   motion). The laser time is P.OP.t_laser_50, a PLACEHOLDER (FACTORYPARAMS
%   section 10). Only the 50 mm job exists here: no 25 mm engraving has ever
%   been recorded.
%
%   It needs an interactive MATLAB session, because 'matlab -batch' has no
%   keyboard. Tests pass their own 'OperatorInput' instead of calling this.
%
%   Example
%     LOG = run_factory_simulation('Operator', 'console');
%     LOG = run_factory_simulation('Operator', 'console', 'Live', true);
%
%   See also RUN_FACTORY_SIMULATION, FACTORY_VIEW, FACTORYPARAMS.

if nargin < 2; info = []; end
switch kind
    case 'engrave?'
        a = ask(['\n  Engrave this part? [Y] engrave the 50 mm job, ' ...
                 '[n] skip engraving (SV11 bypass): ']);
        out = ~any(strcmpi(strtrim(a), {'n', 'no'}));
        if out
            fprintf('  Engraving selected: 50 mm job.\n');
        else
            fprintf('  Engraving skipped: the part takes the SV11 bypass.\n');
        end

    case 'laser'
        tick = [];
        if isstruct(info)
            L = info.t;
            if isfield(info, 'tick'); tick = info.tick; end
        else
            L = info;
        end
        validateattributes(L, {'numeric'}, {'scalar', 'real', 'finite', 'nonnegative'}, ...
            mfilename, 'laser time');
        fprintf('\n  Platform up. Engraving 50 mm ... %.2f s (placeholder time)\n  ', L);
        t0 = tic; last = -1;
        while toc(t0) < L
            k = floor(toc(t0));
            if k > last; fprintf('%d ', k); last = k; end
            if ~isempty(tick); tick(toc(t0)); end
            pause(min(0.1, max(0, L - toc(t0))));
        end
        if ~isempty(tick); tick(L); end
        fprintf('done.\n');
        out = [];

    case 'eng_done'
        fig = []; fallback = @() ask('  Press Enter here for ENG DONE: ');
        if isstruct(info)
            if isfield(info, 'fig');      fig = info.fig; end
            if isfield(info, 'fallback'); fallback = info.fallback; end
        end
        t0 = tic;
        if ~isempty(fig) && isgraphics(fig)
            fprintf('  Engraving finished. Press any key ON THE FIGURE for ENG DONE.\n');
            if ~waitForFigureKey(fig)
                fprintf('  The figure was closed.\n');
                fallback();
            end
        else
            ask('  Engraving finished. Press Enter for ENG DONE: ');
        end
        out = toc(t0);
        fprintf('  ENG DONE after %.2f s.\n', out);

    otherwise
        error('factory_operator_console:kind', ...
            ['Unknown request ''%s''. FACTORY_OPERATOR_CONSOLE answers ' ...
             '''engrave?'', ''laser'' and ''eng_done''.'], char(kind));
end
end

%% ------------------------------------------------------------------------
function a = ask(prompt)
%ASK  input() that explains itself when there is no keyboard.
try
    a = input(sprintf(prompt), 's');
catch ME
    error('factory_operator_console:noConsole', ...
        ['Manual input needs an interactive MATLAB session, and this one ' ...
         'could not read the keyboard (%s).\nRun it from the MATLAB desktop, ' ...
         'or pass your own ''OperatorInput'' function.'], ME.message);
end
end

function pressed = waitForFigureKey(fig)
%WAITFORFIGUREKEY  True on a key press on FIG; false if FIG is closed first.
flag = 'factory_operator_console_engdone';
setappdata(fig, flag, false);
old = get(fig, 'KeyPressFcn');
set(fig, 'KeyPressFcn', @(src, ev) onKey(src, ev, flag));
% Bring it forward for the key, but only if it is already showing. figure()
% also makes a hidden figure visible, which is how the tests' hidden figures
% reached the screen until 2026-09-15.
if strcmp(get(fig, 'Visible'), 'on')
    figure(fig);
end
while isgraphics(fig) && ~getappdata(fig, flag)
    pause(0.05);                            % lets the key callback run
end
pressed = isgraphics(fig);
if pressed
    set(fig, 'KeyPressFcn', old);
    rmappdata(fig, flag);
end
end

function onKey(src, ev, flag)
if any(strcmpi(ev.Key, {'shift', 'control', 'alt', 'command', 'windows', 'capslock'}))
    return                                  % a modifier alone is not ENG DONE
end
setappdata(src, flag, true);
end
