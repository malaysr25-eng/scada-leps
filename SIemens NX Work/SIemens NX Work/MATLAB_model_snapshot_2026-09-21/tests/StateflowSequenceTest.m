classdef StateflowSequenceTest < matlab.unittest.TestCase
    %STATEFLOWSEQUENCETEST  Is the Stateflow chart the same controller?
    %
    %   Open issue 8 said, for the project's whole history, that
    %   BUILD_FACTORY_MODEL('PLC','stateflow') "builds and runs" and that
    %   "nothing yet checks that the chart walks the same 40 states as
    %   FACTORY_PLC". This is that check, and the answer is NO.
    %
    %   THE MEASUREMENT, 2026-09-02
    %
    %       S-function path (validated)   31.080 s
    %       Stateflow chart               30.700 s
    %       difference                     0.380 s   = 38 x P.t_scan
    %
    %   RE-MEASURED 2026-09-07, when CYL_A took its real bore 32 from a
    %   nameplate and the S-function baseline moved to 33.840 s:
    %
    %       S-function path (validated)   33.840 s
    %       Stateflow chart               33.350 s
    %       difference                     0.490 s   = 49 x P.t_scan
    %
    %   AND AGAIN 2026-09-08, when the engraving axis became a velocity jog:
    %
    %       S-function path (validated)   49.290 s
    %       Stateflow chart               48.790 s
    %       difference                     0.500 s   = 50 x P.t_scan
    %
    %   AND ONCE MORE the same day, when four MEASURED sequencer dwells were
    %   applied from real cycles:
    %
    %       S-function path (validated)   63.160 s
    %       Stateflow chart               62.900 s
    %       difference                     0.260 s   = 26 x P.t_scan
    %
    %   AND ONCE MORE, when F3 put the engraver-to-belt-3 move on cylinder B
    %   and a FIFTH dwell went in with it:
    %
    %       S-function path (validated)   70.370 s
    %       Stateflow chart               70.160 s
    %       difference                     0.210 s   = 21 x P.t_scan
    %
    %   AND ONCE MORE, 2026-09-12, when plan H2 put the T#10S start delay on
    %   S03:
    %
    %       S-function path (validated)   78.020 s
    %       Stateflow chart               77.810 s
    %       difference                     0.210 s   = 21 x P.t_scan
    %
    %   UNCHANGED. S03's guard gained an after() timer, but its other half -
    %   receiver pressure reaching P_ready - evidently already fired on the
    %   same scan in both paths, so S03 was apparently not one of the places
    %   they disagree. That is consistent with the guard-count reading below
    %   and is not a new test of it.
    %
    %   H3 the same day (belt 3 from the tape): 76.550 / 76.340 s, 21 scans,
    %   unchanged again. H4 (belt speeds): 75.070 / 74.850 s, 22 scans - ONE
    %   MORE. The belts gate transitions through proximity sensors, and a
    %   faster belt moves where a sensor edge lands against the scan clock,
    %   so one guard now evaluates a scan apart. Still quantised.
    %
    %   H5, 2026-09-13 (push and belt together): 73.620 / 73.430 s, 19 scans -
    %   THREE FEWER. Belt 2 now starts with the transfer push and belt 3 with
    %   cylinder B's retract, instead of after each rod's RET - a physics-
    %   gated wait. Fewer physics-gated waits in series, a smaller lead: the
    %   same direction the guard-count reading predicts.
    %
    %   H6, 2026-09-13 (the wait before cylinder A - the FIRST of the three
    %   unnamed gaps below, now an after() guard): 74.930 / 74.750 s, 18 scans.
    %   ONE FEWER, not the ~5 the prediction below expects per gap. One gap of
    %   three is not the test the prediction set, so it is not abandoned yet -
    %   but the evidence so far is AGAINST it: at this rate the three gaps take
    %   the lead to ~16, not ~6.
    %
    %   H7, 2026-09-13 (nameplate bores and strokes on every barrel): 75.720 /
    %   75.510 s, 21 scans - THREE MORE. A pneumatic change moves every CHG,
    %   BR_RDY, EXT and RET guard, as CYL_A's bore did on 2026-09-07 (+11 scans
    %   then). Consistent with the guard-count reading, not a test of it.
    %
    %   H8, 2026-09-13 (room air 25 C, R*T up 1.7%): 75.650 / 75.450 s, 20
    %   scans - ONE FEWER. Every pneumatic guard moved by a few ms and one
    %   crossed a scan boundary. Recorded, not explained further.
    %
    %   THE LEAD WENT DOWN AGAIN, AND THAT IS THE POINT. The first three
    %   re-measures made it bigger; the last two shrank it, both on changes
    %   that made the cycle LONGER. No reading based on elapsed time survives
    %   that.
    %
    %   The "number of guards" reading does, and now QUANTITATIVELY. Each of
    %   those changes converted transitions from PURELY SENSOR-GATED into ones
    %   dominated by an after() timer, and a timer fires on the same discrete
    %   clock in both implementations:
    %
    %       four dwells   lead 50 -> 26   about SIX scans per guard converted
    %       a fifth       lead 26 -> 21   FIVE more
    %
    %   A dwell removes a place where the two paths can disagree, and the lead
    %   falls by a roughly constant amount per guard. Nobody set out to test
    %   that prediction; two re-baselines tested it for free.
    %
    %   A PREDICTION, recorded so it can be checked rather than admired: the
    %   three unnamed sequencer gaps in FACTORYPARAMS 13M are almost certainly
    %   dwells too. If they are implemented as after() guards, this lead should
    %   fall by roughly fifteen more scans, to somewhere near six. IF IT DOES
    %   NOT, the guard-count reading is wrong and should be abandoned rather
    %   than patched.
    %
    %   WARNING FOR THE NEXT PERSON. When those dwells were added to
    %   FACTORY_PLC alone, the chart did NOT get them - BUILD_FACTORY_MODEL
    %   carries its own hand-written guard table - and the divergence jumped to
    %   13.98 s, or 1398 scans. It stayed a whole number of scans, so the
    %   quantisation signature this file records survived a change that had
    %   nothing to do with scheduling and everything to do with the chart
    %   running a different sequence. A whole-numbered lead is necessary
    %   evidence for the scheduling diagnosis and it is not sufficient: check
    %   the SIZE too, and if it is seconds rather than tenths, suspect missing
    %   logic before suspecting the scan clock.
    %
    %   THE FINDING SURVIVES AND IT GOT SHARPER. The divergence is still
    %   EXACTLY a whole number of scans - 0.490 / 0.010 = 49.000 - and
    %   integration error cannot be quantised to the PLC clock. That is the
    %   same signature that cracked open issue 3, and it still says the cause
    %   is scheduling or chart semantics rather than physics.
    %
    %   WHAT THE RE-MEASUREMENTS ADD, and it is worth more than the
    %   re-baselines. THE LEAD IS NOT A CONSTANT, and it does NOT TRACK TIME.
    %   Three points now, none of which cost a run to get:
    %
    %       cycle 31.080 s -> lead 38 scans
    %       cycle 33.840 s -> lead 49 scans    (+2.76 s bought +11 scans)
    %       cycle 49.290 s -> lead 50 scans    (+15.45 s bought +1 scan)
    %
    %   A change that added FIFTEEN seconds to the cycle moved the lead by one
    %   scan; a change that added under three seconds moved it by eleven. So
    %   the lead is not proportional to cycle length, and the 2026-09-07 note
    %   here - that it "accumulates against physics-gated waiting" - is too
    %   loose. Waiting is not what it counts.
    %
    %   What separates the two changes is WHAT MOVED. The bore changed the
    %   PNEUMATICS, and pneumatic state gates many transitions - CHG, BR_RDY,
    %   EXT and RET all read chamber pressure or rod position. The jog added
    %   its time inside just TWO states, S23_HEIGHT_TOP and S28_HEIGHT_BOTTOM,
    %   whose guards are plain position comparisons. So the lead appears to
    %   track the NUMBER OF GUARDS whose evaluation shifts, not the seconds
    %   spent. That is a sharper constraint than the previous one and it
    %   points at per-guard transition evaluation in the chart.
    %
    %   It still rules out a fixed start-up cost, and it is still not one scan
    %   per state: 50 exceeds the cycle's 39 transitions.
    %
    %   The two hypotheses below were ruled out against the 38, and neither
    %   is rescued by the 49.
    %
    %   TWO HYPOTHESES RULED OUT, so nobody spends the afternoon again:
    %
    %     ExecuteAtInitialization    Setting it false moved the cycle from
    %                                30.700 to 30.710 s - exactly ONE scan. It
    %                                accounts for 1 of the 38 and no more.
    %
    %     transition chaining        A discrete chart follows as many valid
    %                                transitions as it can per execution,
    %                                where FACTORY_PLC fires at most one per
    %                                scan, so this was the obvious candidate.
    %                                Every transition guard was rewritten as
    %                                [after(1, tick) && (...)] to force one
    %                                scan of dwell per state. The guards were
    %                                confirmed present in the built chart -
    %                                [after(1, tick) && (sens(1) > 0.5)] - and
    %                                the cycle time did not move by one
    %                                millisecond. The change was reverted
    %                                rather than kept, because code whose
    %                                stated purpose is disproven is worse than
    %                                no code.
    %
    %   So the cause is still open. What is NOT open any more is whether the
    %   chart is equivalent: it is not, by a measured and reproducible amount.
    %
    %   WHY THIS TEST PINS A KNOWN-WRONG NUMBER. It is a characterisation
    %   test, the same pattern PLCIOTEST used while the plant disagreed with
    %   the machine: it records the disagreement so that the disagreement
    %   cannot change silently. When someone fixes the chart this test SHOULD
    %   fail, and the fix is to assert equivalence instead - exactly as
    %   theModelNowAgreesWithTheMachine replaced its predecessor.
    %
    %   Tagged Slow: it builds a chart and runs a 45 s fixed-step simulation,
    %   about four minutes.
    %
    %   See also BUILD_FACTORY_MODEL, RUN_SIMULINK_MODEL, FACTORY_PLC.

    properties (Constant)
        % RE-BASELINED 2026-09-08 (second time that day) with the four
        % measured sequencer dwells. Previous figures were 31.080/30.700/38,
        % 33.840/33.350/49 and 49.290/48.790/50; all four are kept in the
        % class comment above, because the SET of measurements says far more
        % than any one of them does - and the fourth is the one that
        % discriminates between the competing explanations.
        %
        % The S-function path, which is the validated one.
        % 70.370 until 2026-09-12, when the T#10S start delay (plan H2) added
        % 7.65 s at the front of the cycle.
        % 78.020 after H2; 76.550 after H3 (belt 3 from the tape); 75.070 after
        % H4 (belt speeds); 73.620 after H5 (push and belt together), all the
        % same day; 74.930 after H6 (the wait before cylinder A), 2026-09-13;
        % 75.720 after H7 (nameplate bores and strokes), the same day;
        % 75.650 after H8 (room air 25 C), the same day.
        REF_SFUN_CYCLE = 75.650;    % s
        % The chart, as measured. NOT a target - a record of the defect.
        % 70.160 until 2026-09-12 (plan H2), 77.810 after it, 76.340 after H3
        % (belt 3 from the tape) the same day. The lead did not move either time.
        % 74.850 after H4 (belt speeds), the same day, and the lead DID move.
        % 73.430 after H5 (push and belt together), 2026-09-13.
        % 74.750 after H6 (the wait before cylinder A), the same day.
        % 75.510 after H7 (nameplate bores and strokes), the same day.
        % 75.450 after H8 (room air 25 C), the same day.
        REF_SF_CYCLE   = 75.450;    % s
        % 0.260 s. It must stay a WHOLE NUMBER of scans - that is the finding.
        % The COUNT is plant-dependent and has now moved three times, once
        % DOWNWARD on a change that lengthened the cycle.
        % 21 -> 22 on 2026-09-12 (plan H4): the faster belts moved one
        % sensor-gated transition by a scan. Still a whole number.
        % 22 -> 19 on 2026-09-13 (plan H5): both belt starts moved off the
        % rod-home waits, which are physics-gated. Three fewer places to differ.
        % 19 -> 18 after H6: the first unnamed gap made a timer took ONE scan,
        % not the ~5 predicted. See the class comment.
        % 18 -> 21 after H7: every barrel's chambers changed, so many
        % pneumatic guards moved - as the 2026-09-07 bore change did (+11).
        % 21 -> 20 after H8: R*T moves every pneumatic guard a little.
        REF_LEAD_SCANS = 20;
    end

    properties
        P
        MDL = 'Factory_SF_SequenceCheck';
        R
    end

    methods (TestClassSetup)
        function buildAndRun(tc)
            tc.assumeNotEmpty(ver('stateflow'), ...
                'Stateflow is not installed; nothing to check.');
            tc.P = factory_params_cached();
            reset_factory;
            build_factory_model('PLC','stateflow', 'Model', tc.MDL, ...
                                'Save', true, 'Open', false);
            tc.addTeardown(@() tc.cleanup());
            % RUN_SIMULINK_MODEL returns the raw SimulationOutput and hangs
            % the standard LOG struct off it as out.LOG.
            sout = run_simulink_model('Model', tc.MDL, 'Plot', false, 'Open', false);
            tc.R = sout.LOG;
        end
    end

    methods
        function cleanup(tc)
            % The chart model is a test artefact. Leaving a second .slx in the
            % folder is how the repo grew a committed harness once before.
            if bdIsLoaded(tc.MDL); close_system(tc.MDL, 0); end
            for e = {'.slx','.slxc'}
                f = [tc.MDL e{1}];
                if isfile(f); delete(f); end
            end
        end
    end

    methods (Test, TestTags = {'Slow'})

        function theChartBuildsAndCompletesACycle(tc)
            % The part that HAS always been true, and still is. If this fails,
            % the generator is broken rather than merely inequivalent.
            tc.verifyNotEmpty(tc.R, 'the Stateflow model produced no result');
            tc.verifyGreaterThan(tc.R.cycle_time, 0, ...
                'the chart never reached S39_CYCLE_COMPLETE');
        end

        function theChartIsStillNotEquivalentToFactoryPlc(tc)
            % SHOULD FAIL when someone fixes the chart. See the class comment:
            % replace it with an equivalence assertion at that point, do not
            % re-pin it to a new wrong number.
            tc.verifyEqual(tc.R.cycle_time, tc.REF_SF_CYCLE, 'AbsTol', 0.005, ...
                sprintf(['the Stateflow chart''s cycle time moved. If it now ' ...
                         'equals the S-function path''s %.3f s the chart has ' ...
                         'been FIXED - assert equivalence here instead of ' ...
                         'this characterisation.'], tc.REF_SFUN_CYCLE));
        end

        function theDivergenceIsQuantisedToTheScanClock(tc)
            % The finding that matters, and the one that says where to look.
            % Integration error cannot land on an exact multiple of t_scan.
            lead = tc.REF_SFUN_CYCLE - tc.R.cycle_time;
            scans = lead / tc.P.t_scan;
            tc.verifyEqual(scans, round(scans), 'AbsTol', 1e-6, sprintf( ...
                ['the chart''s lead is %.4f s, which is %.3f scans - no ' ...
                 'longer a whole number. A divergence that stops being ' ...
                 'quantised to t_scan is no longer a scheduling defect and ' ...
                 'the diagnosis in this file needs redoing.'], lead, scans));
            tc.verifyEqual(round(scans), tc.REF_LEAD_SCANS, ...
                'the chart''s lead changed size; re-check the class comment');
        end

    end
end
