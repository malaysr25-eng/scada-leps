classdef CompareToRecordingTest < matlab.unittest.TestCase
    %COMPARETORECORDINGTEST  compare_to_recording: routes, and that each mapping holds.
    %
    %   Two things are checked.
    %
    %   1. Every mapped state pair measures what its recorded interval
    %      measures. Each is timed a second way, from the LOG's own conveyor
    %      commands and sensor edges, without the state trace. That is the
    %      "confirmed two ways" rule in COMPARE_TO_RECORDING's header, made
    %      mechanical, for both the engraved and the bypass route.
    %   2. A schema-3 extraction, which labels each cycle's route, feeds a
    %      route's intervals only from cycles that took that route, and the
    %      intervals before the split from every cycle. An older file with no
    %      routes behaves exactly as before.
    %
    %   The extractions are synthetic, written to a temporary folder, so nothing
    %   here depends on Project_Notes. Two shared runs, about 80 s.
    %
    %   See also COMPARE_TO_RECORDING, BYPASSROUTETEST.

    properties
        Leng    % engraved run
        Lbyp    % bypass run
        Tmp     % folder for the synthetic extractions
    end

    properties (Constant)
        % A scan to command, a scan to sense, and the log's own step.
        TOL = 0.03
    end

    methods (TestClassSetup)
        function runBoth(tc)
            reset_factory('Quiet', true);
            tc.Leng = run_factory_simulation('Plot', false, 'Verbose', false);
            Q = FactoryParams(); Q.engrave_selected = false;
            tc.Lbyp = run_factory_simulation('Params', Q, 'Plot', false, ...
                                             'Verbose', false);
            tc.Tmp = tempname; mkdir(tc.Tmp);
        end
    end

    methods (TestClassTeardown)
        function clean(tc)
            if isfolder(tc.Tmp); rmdir(tc.Tmp, 's'); end
        end
    end

    methods (Access = private)
        function f = extraction(tc, name, withRoutes)
            % Three real cycles, one per route, with made-up intervals chosen
            % so each mean says which cycles went into it.
            c1 = cyc('C1', 'engraved', struct('cycle_conveyor1_run', 3.0, ...
                     'cycle_conveyor2_run', 1.5, 'platform_rise', 7.7));
            c2 = cyc('C2', 'bypass', struct('cycle_conveyor1_run', 3.2, ...
                     'cycle_conveyor2_run', 2.1, 'pulse_solenoid_valve11', 2.0, ...
                     'cycle_conveyor3_run', 3.3));
            c3 = cyc('C3', 'neither', struct('cycle_conveyor1_run', 3.1, ...
                     'cycle_conveyor2_run', 2.7));
            cs = {c1, c2, c3};
            if ~withRoutes
                cs = cellfun(@(c) rmfield(c, 'route'), cs, 'UniformOutput', false);
            end
            f = fullfile(tc.Tmp, [name '.json']);
            fid = fopen(f, 'w');
            fprintf(fid, '%s', jsonencode(struct('schemaVersion', 2 + withRoutes, ...
                                                 'cycles', {cs})));
            fclose(fid);
        end
    end

    methods (Test)

        function theEngravedMappingMatchesTheLoggedEdges(tc)
            L = tc.Leng;
            T = compare_to_recording('Log', L, 'File', tc.extraction('e', true), ...
                                     'Verbose', false);
            tc.verifyEqual(row(T, 'cycle_conveyor1_run').Model, ...
                fall(L, L.cmd_conv(:,1)) - rise(L, L.cmd_conv(:,1)), 'AbsTol', tc.TOL);
            tc.verifyEqual(row(T, 'cycle_conveyor2_run').Model, ...
                fall(L, L.cmd_conv(:,2)) - rise(L, L.cmd_conv(:,2)), 'AbsTol', tc.TOL);
            tc.verifyEqual(row(T, 'cycle_conveyor3_run').Model, ...
                rise(L, prox(L, L.P.PROX_GUARD(4))) - rise(L, L.cmd_conv(:,3)), ...
                'AbsTol', tc.TOL);
        end

        function theBypassMappingMatchesTheLoggedEdges(tc)
            L = tc.Lbyp;
            T = compare_to_recording('Log', L, 'File', tc.extraction('b', true), ...
                                     'Verbose', false);
            c2on = rise(L, L.cmd_conv(:,2));
            tc.verifyEqual(row(T, 'cycle_conveyor2_run').Model, ...
                fall(L, L.cmd_conv(:,2)) - c2on, 'AbsTol', tc.TOL);
            tc.verifyEqual(row(T, 'conveyor2_to_prox8').Model, ...
                rise(L, prox(L, L.P.PROX_BYPASS)) - c2on, 'AbsTol', tc.TOL);
            tc.verifyEqual(row(T, 'cycle_conveyor3_run').Model, ...
                rise(L, prox(L, L.P.PROX_GUARD(4))) - rise(L, L.cmd_conv(:,3)), ...
                'AbsTol', tc.TOL);
            % SV11 is held for the PLC's T#2S pulse (FC6 N15).
            tc.verifyEqual(row(T, 'pulse_solenoid_valve11').Model, ...
                L.P.PLC.t_valve_pulse, 'AbsTol', tc.TOL);
            p = row(T, 'prox8_to_sv11').Model;
            tc.verifyGreaterThanOrEqual(p, 0);
            tc.verifyLessThan(p, 0.5, 'SV11 should follow prox 8 within a few scans');
            % Intervals of the engraved route are not rows on the bypass.
            tc.verifyFalse(any(strcmp(T.Interval, 'platform_rise')));
        end

        function eachRouteUsesOnlyItsOwnCycles(tc)
            f  = tc.extraction('r', true);
            Te = compare_to_recording('Log', tc.Leng, 'File', f, 'Verbose', false);
            tc.verifyEqual(row(Te, 'cycle_conveyor1_run').N, 3, ...
                'belt 1 comes before the split, so every cycle counts');
            tc.verifyEqual(row(Te, 'cycle_conveyor1_run').Meas, 3.1, 'AbsTol', 1e-12);
            tc.verifyEqual(row(Te, 'cycle_conveyor2_run').N, 1);
            tc.verifyEqual(row(Te, 'cycle_conveyor2_run').Meas, 1.5, 'AbsTol', 1e-12, ...
                'the engraved belt-2 run must come from the engraved cycle only');
            tc.verifyEqual(row(Te, 'platform_rise').N, 1);
            tc.verifyFalse(any(strcmp(Te.Interval, 'pulse_solenoid_valve11')));

            Tb = compare_to_recording('Log', tc.Lbyp, 'File', f, 'Verbose', false);
            tc.verifyEqual(row(Tb, 'cycle_conveyor1_run').N, 3);
            tc.verifyEqual(row(Tb, 'cycle_conveyor2_run').Meas, 2.1, 'AbsTol', 1e-12);
            tc.verifyEqual(row(Tb, 'pulse_solenoid_valve11').Meas, 2.0, 'AbsTol', 1e-12);
            tc.verifyEqual(row(Tb, 'cycle_conveyor3_run').Meas, 3.3, 'AbsTol', 1e-12);
        end

        function aFileWithoutRoutesBehavesAsBefore(tc)
            f  = tc.extraction('legacy', false);
            Te = compare_to_recording('Log', tc.Leng, 'File', f, 'Verbose', false);
            tc.verifyEqual(row(Te, 'cycle_conveyor2_run').N, 3, ...
                'with no routes in the file, every real cycle counts, as before');
            tc.verifyEqual(row(Te, 'cycle_conveyor2_run').Meas, 2.1, 'AbsTol', 1e-12);
            % No bypass was ever recorded before routes were labelled, so the
            % bypass compares only what comes before the split.
            Tb = compare_to_recording('Log', tc.Lbyp, 'File', f, 'Verbose', false);
            tc.verifyEqual(row(Tb, 'cycle_conveyor1_run').N, 3);
            tc.verifyEqual(row(Tb, 'cycle_conveyor2_run').N, 0);
        end

        function aWrongRouteIsRejected(tc)
            f = tc.extraction('x', true);
            tc.verifyError(@() compare_to_recording('Log', tc.Leng, 'Route', 'bypass', ...
                'File', f, 'Verbose', false), 'compare_to_recording:routeLog');
            tc.verifyError(@() compare_to_recording('Log', tc.Leng, 'Route', 'sideways', ...
                'File', f, 'Verbose', false), 'compare_to_recording:route');
        end

        function theReportNamesTheRoute(tc)
            f = tc.extraction('v', true);
            g = tc.extraction('w', false);
            L = tc.Lbyp; %#ok<NASGU> used inside evalc
            out = evalc('compare_to_recording(''Log'', L, ''File'', f);');
            tc.verifySubstring(out, 'route     : bypass');
            L = tc.Leng; %#ok<NASGU>
            out = evalc('compare_to_recording(''Log'', L, ''File'', g);');
            tc.verifySubstring(out, 'not labelled');
        end
    end
end

%% ------------------------------------------------------------------------
function c = cyc(id, route, iv)
c = struct('cycle_id', id, 'source_id', 'plc', 'mode', 'AUTO', ...
           'route', route, 'intervals', iv);
end

function r = row(T, name)
r = T(strcmp(T.Interval, name), :);
assert(height(r) == 1, 'no single row for %s', name);
end

function x = prox(L, k)
x = L.sens(:, strcmp(L.sens_name, L.P.PROX_NAME{k}));
end

function t = rise(L, x)
t = L.t(find(diff([false; x(:) ~= 0]) == 1, 1));
end

function t = fall(L, x)
t = L.t(find(diff([false; x(:) ~= 0]) == -1, 1));
end
