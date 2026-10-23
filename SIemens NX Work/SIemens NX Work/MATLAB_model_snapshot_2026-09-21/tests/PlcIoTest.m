classdef PlcIoTest < matlab.unittest.TestCase
    %PLCIOTEST  The real PLC tag register and the model's mapping to it.
    %
    %   PLCTAGLIST is the only file in this project holding OBSERVED FACTS
    %   about the installed machine rather than assumptions. These tests keep
    %   it that way, and keep FACTORY_IO_MAP honest about the difference
    %   between what is known and what is guessed.
    %
    %   The load-bearing assertion is coverage: every physical I/O tag the PLC
    %   publishes must appear in the mapping, even if only as UNMAPPED. A tag
    %   that is simply absent from the map is a signal the model has silently
    %   ignored, which is exactly how a digital twin drifts away from its
    %   machine without anyone noticing.
    %
    %   Fast: reads two files, runs no simulation.
    %
    %   See also PLCTAGLIST, FACTORY_IO_MAP.

    properties
        T   % tag register
        M   % mapping
    end

    methods (TestClassSetup)
        function load(tc)
            tc.T = PlcTagList();
            tc.M = factory_io_map();
        end
    end

    methods (Test)

        % ---- the register itself --------------------------------------------

        function theRegisterMatchesTheSuppliedCounts(tc)
            % Transcribed mechanically from plc/PLC_Tag_List.xlsx on
            % 2026-08-24. If these change, the machine changed, or the
            % transcription broke.
            tc.verifyEqual(height(tc.T), 121, ...
                'the tag register no longer holds the 121 supplied tags');
            tc.verifyEqual(unique(tc.T.DB), 59, ...
                'every supplied tag lives in DB59');
        end

        function theRealIoCountsAreWhatTheMachineReports(tc)
            % Count within a GROUP. Short alone is ambiguous: every solenoid and
            % conveyor appears twice, once as a Digital_Outputs coil and once as
            % its manual_commands mirror. They are the same physical coil.
            % CASE-INSENSITIVE deliberately. The machine's own tags are
            % inconsistent: the output coil is "Solenoid_valve7" and its manual
            % mirror is "Solenoid_Valve7". Anyone matching tags by name across
            % the two blocks will trip over this, so it is recorded here.
            n = @(grp, pat) sum(strcmp(tc.T.Group, grp) & ...
                    ~cellfun(@isempty, regexpi(tc.T.Short, pat, 'once')));
            % These are the numbers that contradict the model as built, and are
            % the reason the I/O layer is being rebuilt.
            tc.verifyEqual(n('din',  '^Proximity_sensor\d+$'), 10, '10 proximity sensors');
            tc.verifyEqual(n('dout', '^Solenoid_valve\d+$'),   13, '13 solenoid valves');
            tc.verifyEqual(n('dout', '^Conveyor\d+$'),          3, '3 conveyor run commands');
            % and the mirrors really are mirrors, one per coil
            tc.verifyEqual(n('manual','^Solenoid_valve\d+$'),  13, '13 manual valve mirrors');
            tc.verifyEqual(n('manual','^Conveyor\d+$'),         3, '3 manual conveyor mirrors');
        end

        function everyTagHasAUsableAddress(tc)
            tc.verifyTrue(all(ismember(tc.T.Kind, {'X','W','D'})), ...
                'a tag has an address kind that is not bit, word or dword');
            tc.verifyTrue(all(tc.T.Byte >= 0), 'negative byte offset');
            isBit = strcmp(tc.T.Kind, 'X');
            tc.verifyTrue(all(tc.T.Bit(isBit) >= 0 & tc.T.Bit(isBit) <= 7), ...
                'a bit tag has a bit offset outside 0..7');
            tc.verifyTrue(all(tc.T.Bit(~isBit) == 0), ...
                'a word or dword tag carries a non-zero bit offset');
        end

        function boolTagsAreBitsAndRealTagsAreDwords(tc)
            isBool = strcmpi(tc.T.Type, 'Bool');
            tc.verifyTrue(all(strcmp(tc.T.Kind(isBool), 'X')), ...
                'a Bool tag is not addressed as a bit');
            isReal = strcmpi(tc.T.Type, 'Real');
            tc.verifyTrue(all(strcmp(tc.T.Kind(isReal), 'D')), ...
                'a Real tag is not addressed as a dword');
        end

        function noTwoTagsShareAnAddress(tc)
            key = strcat(string(tc.T.Byte), "_", string(tc.T.Bit), "_", string(tc.T.Kind));
            % Manual commands intentionally mirror the outputs, but at their
            % own addresses, so every address should still be distinct.
            [u, ~, ic] = unique(key);
            counts = accumarray(ic, 1);
            dup = u(counts > 1);
            tc.verifyEmpty(dup, sprintf('addresses reused: %s', ...
                strjoin(cellstr(dup), ', ')));
        end

        % ---- the mapping -----------------------------------------------------

        function everyPhysicalIoTagAppearsInTheMap(tc)
            % The guard that matters. 'axis' tags are
            % stepper internals handled structurally, and 'manual' tags mirror
            % coils already covered by their 'dout' row.
            PHYS = {'interlock','system','magazine','din','dout','analog'};
            phys = tc.T(ismember(tc.T.Group, PHYS), :);
            missing = unique(setdiff(phys.Short, tc.M.PlcShort));
            tc.verifyEmpty(missing, sprintf(...
                ['these real PLC tags appear nowhere in factory_io_map: %s\n' ...
                 'Add them, as UNMAPPED if their meaning is not known. A tag ' ...
                 'absent from the map is one the model silently ignores.'], ...
                strjoin(missing, ', ')));
        end

        function everyMappingStatusIsOneOfTheThree(tc)
            tc.verifyTrue(all(ismember(tc.M.Status, ...
                {'CONFIRMED','PROVISIONAL','UNMAPPED'})), ...
                'a mapping row carries a status outside the allowed three');
        end

        function confirmedRowsNameAModelSignalAndUnmappedRowsDoNot(tc)
            isConf = strcmp(tc.M.Status, 'CONFIRMED');
            tc.verifyTrue(all(~cellfun(@isempty, tc.M.ModelSignal(isConf))), ...
                'a CONFIRMED row names no model signal');
            isUn = strcmp(tc.M.Status, 'UNMAPPED');
            tc.verifyTrue(all(cellfun(@isempty, tc.M.ModelSignal(isUn))), ...
                'an UNMAPPED row names a model signal, so it is not unmapped');
        end

        function thePlcListingClosedTheSensorAndValveGap(tc)
            % SUPERSEDES theMappingGapIsStillTheSensorsAndValves, which
            % asserted 10 proximity sensors and 13 solenoids UNMAPPED and
            % said in its own comment that closing the gap should make it
            % fail. On 2026-08-30 the TIA Portal program listing was decoded
            % and it did close. This is the narrowed replacement.
            %
            % The listing settles each signal's ROLE. It does not settle
            % where a sensor is bolted or which barrel is cylinder A, so the
            % rows that still need someone at the machine are PROVISIONAL,
            % and this pins how many of them there are.
            u = tc.M.PlcShort(strcmp(tc.M.Status,'UNMAPPED'));
            tc.verifyEmpty(u, sprintf(...
                ['a physical I/O tag went back to UNMAPPED: %s\n' ...
                 'The PLC listing mapped all 23. If one is genuinely ' ...
                 'unknown again, say why in INPUTS_REQUIRED.md.'], ...
                strjoin(u, ', ')));

            pv = tc.M.PlcShort(strcmp(tc.M.Status,'PROVISIONAL'));
            tc.verifyEqual(sum(startsWith(pv,'Proximity_sensor')), 4, ...
                ['proximity rows still provisional changed - reconcile ' ...
                 'INPUTS_REQUIRED.md item 4']);
            % Was 4. Solenoid 11 became CONFIRMED on 2026-09-02 when the
            % machine's owner said cylinders A and B both make no
            % engraver-to-belt-3 move, which leaves it - and `Wp_move_cv3` is
            % the program's own name for exactly that. The three still
            % provisional are 6, 12 and 13: role known, placement inferred.
            tc.verifyEqual(sum(startsWith(pv,'Solenoid_valve')), 3, ...
                ['solenoid rows still provisional changed - reconcile ' ...
                 'INPUTS_REQUIRED.md item 3']);
        end

        function theFourDoubleSolenoidCoilsAreMappedInPairs(tc)
            % The structural finding out of the listing. Solenoids 7/8 and
            % 9/10 are extend and retract coils on TWO cylinders, not four
            % cylinders. FC3 solenoid_manual is the only place an output
            % coil is written, and it writes these four from pgm_cylA_Ext,
            % pgm_cylA_Ret, pgm_cylB_Ext and pgm_cylB_Ret.
            %
            % The model USED to give each of its five cylinders one
            % spring-return valve, so it could not represent a rod that holds
            % position with both coils off. Since 2026-09-02 it can: CYL_A and
            % CYL_B are declared double-solenoid in FACTORY_ACTUATORS and
            % FACTORY_DERIVATIVES latches the spool. Pinned here so the
            % pairing is not quietly flattened back into four independent
            % valves.
            %
            % The signal names moved with that change, from `cylA.ext` - which
            % named nothing that existed - to the element of the command
            % vector that now actually carries the coil.
            want = {'Solenoid_valve7',  'u.sol(7)  CYL_A ext'
                    'Solenoid_valve8',  'u.sol(8)  CYL_A ret'
                    'Solenoid_valve9',  'u.sol(9)  CYL_B ext'
                    'Solenoid_valve10', 'u.sol(10) CYL_B ret'};
            for k = 1:size(want,1)
                row = tc.M(strcmp(tc.M.PlcShort, want{k,1}), :);
                tc.assertNotEmpty(row, sprintf('%s vanished from the map', want{k,1}));
                tc.verifyEqual(row.ModelSignal{1}, want{k,2}, sprintf( ...
                    '%s no longer maps to %s', want{k,1}, want{k,2}));
                tc.verifyEqual(row.Status{1}, 'CONFIRMED', sprintf( ...
                    '%s is no longer CONFIRMED; the program text fixes it', want{k,1}));
            end
        end

        function theFiveMagazinePushersMatchTheFiveCompartments(tc)
            % FC7 N3: mag_push_on AND workpiece_choice = N -> solenoid N,
            % for N = 1..5. The compartment rows were already CONFIRMED by
            % name, so the two numberings are the same numbering.
            for k = 1:5
                sv = tc.M(strcmp(tc.M.PlcShort, sprintf('Solenoid_valve%d',k)), :);
                px = tc.M(strcmp(tc.M.PlcShort, sprintf('Proximity_sensor%d',k)), :);
                % Since 2026-09-02 these name a real element of the command
                % vector - u.sol(k) drives MAGk_PUSH - rather than the
                % aspirational `mag(k).push`, which was never built. What is
                % pinned is unchanged: pusher k, compartment k and dispense
                % sensor k are the same k.
                tc.verifyEqual(sv.ModelSignal{1}, ...
                    sprintf('u.sol(%d)  MAG%d_PUSH',k,k), ...
                    'magazine pusher numbering drifted from the compartments');
                tc.verifyEqual(px.ModelSignal{1}, sprintf('y.PX(%d)',k), ...
                    ['magazine dispense sensor numbering drifted. Since ' ...
                     '2026-09-02 these are MODELLED signals, not aspirational ' ...
                     'names: y.PX is ten wide, in the machine numbering.']);
            end
        end

        function theMachineSpellsSolenoidTagsInconsistently(tc)
            % Not a defect in this model - a property of the real PLC, pinned
            % so that nobody later "fixes" the register to make it tidy. The
            % register must mirror the machine, warts included.
            dout = tc.T.Short(strcmp(tc.T.Group,'dout'));
            man  = tc.T.Short(strcmp(tc.T.Group,'manual'));
            tc.verifyTrue(any(startsWith(dout, 'Solenoid_valve')), ...
                'output coils are no longer spelled Solenoid_valve');
            tc.verifyTrue(any(startsWith(man,  'Solenoid_Valve')), ...
                'manual mirrors are no longer spelled Solenoid_Valve');
            tc.verifyEmpty(intersect(dout, man(startsWith(man,'Solenoid'))), ...
                'the two spellings now collide, so Group is no longer needed');
        end

        % ---- P.REAL must not drift from the register -------------------------

        function factoryParamsRealBlockMatchesTheRegister(tc)
            % FactoryParams.P.REAL restates observed counts so the physics can
            % see them without parsing the register. Restating invites drift,
            % so the two are tied together here.
            P = FactoryParams();
            n = @(grp, pat) sum(strcmp(tc.T.Group, grp) & ...
                    ~cellfun(@isempty, regexpi(tc.T.Short, pat, 'once')));
            tc.verifyEqual(P.REAL.n_prox,     n('din', '^Proximity_sensor\d+$'), ...
                'P.REAL.n_prox disagrees with PlcTagList');
            tc.verifyEqual(P.REAL.n_solenoid, n('dout','^Solenoid_valve\d+$'), ...
                'P.REAL.n_solenoid disagrees with PlcTagList');
            tc.verifyEqual(P.REAL.n_conveyor, n('dout','^Conveyor\d+$'), ...
                'P.REAL.n_conveyor disagrees with PlcTagList');
            tc.verifyEqual(P.REAL.n_magazine, ...
                sum(strcmp(tc.T.Group,'magazine') & endsWith(tc.T.Short,'.Ok')), ...
                'P.REAL.n_magazine disagrees with PlcTagList');
        end

        function theSignalsPRealClaimsToExistDoExist(tc)
            % Each of these underpins a statement made in FactoryParams section
            % 12. If the tag vanishes, the claim is no longer true.
            P = FactoryParams();
            has = @(s) any(strcmpi(tc.T.Short, s));
            if P.REAL.engrave_has_done_signal
                tc.verifyTrue(has('Engraving_Completed'), ...
                    'P.REAL claims an engrave-done signal that is not in the register');
            end
            if P.REAL.axis_position_controlled
                tc.verifyTrue(any(contains(tc.T.Short,'Goto_Position')), ...
                    'P.REAL claims position-controlled axes but no Goto_Position tag exists');
                tc.verifyTrue(any(contains(tc.T.Short,'Current_Position_Fb')), ...
                    'no encoder position feedback tag exists');
            end
            for i = 1:numel(P.REAL.interlocks)
                tc.verifyTrue(has(P.REAL.interlocks{i}), sprintf( ...
                    'P.REAL lists interlock "%s", absent from the register', ...
                    P.REAL.interlocks{i}));
            end
        end

        function theModelNowAgreesWithTheMachine(tc)
            % SUPERSEDES theModelStillDisagreesWithTheMachine, whose comment
            % said: "When the plant is rebuilt to the real I/O this test
            % SHOULD fail, and be updated to assert agreement." On 2026-09-02
            % the proximity sensors were rebuilt to the machine's ten, in the
            % machine's own numbering, and it did fail. This is that update.
            %
            % SUPERSEDED IN TURN, 2026-09-02 (second entry that day). The
            % VALVE half used to be excluded here with the note "that is a
            % re-model of the plant, not a renumbering of its sensors, and it
            % is not done". It is now done: 11 actuators on 13 coils, CYL_A
            % and CYL_B double-solenoid. So this asserts BOTH halves.
            %
            % Note which count goes with which. The machine has 13 SOLENOID
            % COILS and 11 PNEUMATIC ACTUATORS, and those are different
            % numbers for a real reason - two actuators take two coils each.
            % Comparing NCYL to n_solenoid, as the old assertion did, would
            % now fail against a correct model.
            %
            % NCYL, NCONV and PROX are DERIVED, so the raw FactoryParams
            % struct does not carry them - initialize_factory has to run.
            P = initialize_factory(FactoryParams());

            tc.verifyEqual(size(P.PROX,1), P.REAL.n_prox, ...
                ['the model no longer carries one proximity sensor per ' ...
                 'sensor on the machine']);
            tc.verifyEqual(numel(P.PROX_NAME), P.REAL.n_prox, ...
                'every modelled sensor must be named');

            tc.verifyEqual(P.NCYL, P.PLC.n_pneu_act, ...
                'the model no longer carries one cylinder per pneumatic actuator');
            tc.verifyEqual(P.NSOL, P.REAL.n_solenoid, ...
                'the model no longer drives one coil per solenoid on the machine');
            tc.verifyEqual(sum([P.CYL.dbl]), P.PLC.n_dbl_sol, ...
                'the double-solenoid count disagrees with the PLC listing');
            tc.verifyEqual(P.NCONV, P.REAL.n_conveyor, ...
                'conveyor count agreed before and must still agree');
        end

        function theSequencerGuardsPointAtRealSensors(tc)
            % The four guards the sequence actually gates on now name the
            % MACHINE's sensor numbers, not the model's old 1-2-3-4. Their
            % physical trip points did not move - that is why the pinned
            % cycle time survived the renumbering - but the numbers did, and
            % nothing else checks that P.PROX_GUARD stayed in range.
            P = initialize_factory(FactoryParams());
            g = P.PROX_GUARD;
            tc.verifyNumElements(g, 4, ...
                'four sequence states gate on a proximity sensor');
            tc.verifyTrue(all(g >= 1 & g <= size(P.PROX,1)), ...
                sprintf('a guard indexes sensor %s, outside 1..%d', ...
                        mat2str(g), size(P.PROX,1)));
            tc.verifyEqual(numel(unique(g)), 4, ...
                'two sequence states gate on the same sensor');

            % The magazine guard must be the compartment the model feeds from,
            % or the block is dispensed from one slot and confirmed by
            % another's sensor.
            tc.verifyEqual(g(1), P.mag_choice, ...
                'the feed guard watches a compartment the model does not feed from');
        end

        function theSensorBusIsOneDefinition(tc)
            % FACTORY_SENSOR_BUS exists because this layout was written out by
            % hand in three files that had to agree and nothing checked them.
            % This is that check.
            P = initialize_factory(FactoryParams());
            B = factory_sensor_bus(P);

            tc.verifyEqual(numel(B.PX),  size(P.PROX,1), 'PX width');
            tc.verifyEqual(numel(B.EXT), P.NCYL, 'EXT width');
            tc.verifyEqual(numel(B.RET), P.NCYL, 'RET width');
            tc.verifyEqual(numel(B.CHG), P.NCYL, 'CHG width');

            % No channel may overlap another, and together they must tile
            % 1..width with no gap. A gap means a channel silently reads zero.
            idx = sort([B.CAM B.PX B.EXT B.RET B.HS_TOP B.HS_BOT ...
                        B.P_res B.P_READY B.BR_RDY B.CHG B.ESTOP_OK]);
            tc.verifyEqual(idx, 1:B.width, ...
                'the sensor bus has an overlap or a gap');

            % And what the plant actually packs must be that wide.
            [~, s0] = factory_params_cached();
            y = factory_sensors(s0, P);
            v = [y.CAM; y.PX(:); y.EXT(:); y.RET(:); y.HS_TOP; y.HS_BOT; ...
                 y.P_res; y.P_READY; y.BR_RDY(:); y.CHG(:); y.ESTOP_OK];
            tc.verifyEqual(numel(v), B.width, ...
                'FACTORY_SENSORS produces a different number of channels than the bus declares');
        end

        function noModelSignalIsClaimedTwice(tc)
            sig = tc.M.ModelSignal(~cellfun(@isempty, tc.M.ModelSignal));
            [u, ~, ic] = unique(sig);
            dup = u(accumarray(ic,1) > 1);
            tc.verifyEmpty(dup, sprintf(...
                'two PLC tags both drive the same model signal: %s', ...
                strjoin(dup, ', ')));
        end

    end
end
