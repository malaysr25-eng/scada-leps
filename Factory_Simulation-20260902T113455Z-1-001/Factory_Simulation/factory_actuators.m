function A = factory_actuators(variant)
%FACTORY_ACTUATORS  The one definition of the cell's pneumatic actuators.
%
%   A = FACTORY_ACTUATORS() returns an 11-element struct array, one entry per
%   pneumatic actuator on the real machine, IN THE MACHINE'S OWN NUMBERING.
%
%   A = FACTORY_ACTUATORS('historical5') returns the FIVE spring-return
%   cylinders the model carried before 2026-09-02, coils renumbered 1-5.
%
%   The historical variant exists for one reason and is used in one place.
%   PLCIOLATENCYTEST reproduces Simulink runs measured before the actuation-
%   latency defect was fixed, and reproducing a measurement means restoring
%   the conditions it was taken under. It already restores the old workpiece;
%   the old PLANT is now part of those conditions too. Re-pinning those
%   figures to the current plant instead would turn the project's strongest
%   piece of diagnostic evidence into a self-referential regression pin.
%
%   It is NOT a supported configuration and nothing else may use it.
%
%   WHY THIS FILE EXISTS
%
%   Until 2026-09-02 the plant was five cylinders, each with one spring-return
%   valve, declared in a `cdef` cell array inside INITIALIZE_FACTORY. The
%   machine has ELEVEN pneumatic actuators driven by THIRTEEN solenoid coils,
%   and two of those actuators are DOUBLE-SOLENOID. Those are not the same
%   shape of thing, so the table moved out of INITIALIZE_FACTORY and into its
%   own file, for the same reason FACTORY_SENSOR_BUS exists: the actuator set
%   is now read by the plant, the sequencer, the sensor bus, the Simulink
%   builder and the Python reference port, and a set of facts read from five
%   places must be written in one.
%
%   Source for the coil numbers, the valve types and the roles: the machine's
%   own TIA Portal program listing, plc/abc.pdf, decoded 2026-08-30. FC3
%   solenoid_manual writes every coil; FC8 Fc_IO mirrors them to the HMI; the
%   two agree, which is why the addresses are trusted. See FACTORYPARAMS
%   section 13C and FACTORY_IO_MAP for the address-by-address map.
%
%   FIELDS
%     name      char    the machine's name for it
%     alias     char    the name Sequence.xlsx uses, '' if the sequence never
%                       mentions it. Set for the magazine pusher that
%                       P.mag_choice selects, by INITIALIZE_FACTORY.
%     role      char    what the sequencer asks for, e.g. 'eng_in'. Roles are
%                       resolved to indices in P.ACT.
%     dbl       logical true for a DOUBLE-SOLENOID valve
%     coil_ext  double  coil number (1..13) that drives the spool to 1
%     coil_ret  double  coil number that drives it to 0; 0 for spring-return
%     branch    double  distribution-valve branch 1..4 that feeds it
%     axis      char    'x', 'y', or '-' when the placement is not known
%     dir       double  push direction +1 / -1, 0 when unplaced
%     from,to   char    waypoint names bounding the stroke, '' when unplaced
%     mag       double  magazine compartment number, 0 if not a pusher
%     stroke_of char    name of the actuator whose stroke this one BORROWS,
%                       '' when the stroke is derived from its own geometry
%     excel     char    Sequence.xlsx step reference, '-' if it has none
%     short     char    compact label for diagrams. Lives here rather than in
%                       the drawing code so that the visualiser cannot invent
%                       a naming scheme of its own - which is exactly what the
%                       old hard-coded layout did, printing "Actuator 1" three
%                       times for three different barrels.
%
%   THE TWO VALVE TYPES, AND WHY THE DIFFERENCE MATTERS
%
%   A SPRING-RETURN valve follows its single coil: energised the spool goes to
%   1, de-energised the spring puts it back to 0. That is all the model could
%   express before this change.
%
%   A DOUBLE-SOLENOID valve is a LATCH. The extend coil drives the spool to 1,
%   the retract coil drives it to 0, and with BOTH COILS OFF THE SPOOL HOLDS
%   WHERE IT IS. That hold is why the machine can PULSE these coils - FC6
%   networks 4, 7 and 15 energise for T#2S and release, P.PLC.t_valve_pulse -
%   instead of holding them energised for the whole stroke. A spring-return
%   valve pulsed that way would snap back the instant the coil dropped.
%
%   FACTORY_DERIVATIVES implements the latch. FACTORY_PLC drives every coil
%   MAINTAINED rather than pulsed, which for a latching valve produces exactly
%   the same spool trajectory - and that is why widening the valve model did
%   not move the pinned baseline on its own. What did move it is the air; see
%   the note on branches below.
%
%   CORRECTED 2026-09-02 BY THE MACHINE'S OWNER. Read this before trusting
%   any earlier description of cylinders A and B.
%
%   The table first assigned CYL_B (coils 9/10) the role 'eng_out', the
%   engraver-to-belt-3 transfer, because the sequence needs that motion and the
%   two double-solenoid cylinders were the plausible pair. That was an
%   assumption and it was WRONG. The owner states:
%
%       "cylinder B is energised when engraving is NOT to be done
%        (50 mm is selected on the interface)"
%
%   and, second:
%
%       "solenoid 9 is for extending the cylinder and solenoid 10 is for
%        retracting it FOR ENGRAVING MACHINE"
%
%   Taken together: cylinder B belongs to the ENGRAVING MACHINE, coil 9 drives
%   it out and coil 10 back, and it is energised on the no-engrave path. The
%   coil polarity is what this table already had; the LOCATION is the
%   correction, and it is the second one this row has taken in a day.
%
%   The first reading of "engraving is not to be done" put cylinder B at the
%   end of conveyor 2 as a diverter that carried the part past the engraver.
%   That is superseded: it is at the engraver. Both statements are kept in
%   FactoryParams 13E in the owner's words, because the reading changed and the
%   words did not.
%
%   Either way solenoid 11 is what makes the engraver-to-belt-3 move - the
%   owner said cylinders A and B both do not - which is what its own PLC name
%   said all along: FC6 N15 fires it on `Wp_move_cv3`, "workpiece move to
%   conveyor 3", with conveyor 3 on and conveyor 2 off. It is renamed
%   MOVE_TO_CV3 here because XFER_CV2_CV3 was this model's guess at what it did
%   and the guess was the thing that was wrong.
%
%   This also gives the two products a consequence. Section 13C records
%   PRODUCT_HEIGHT 50 and 25 with separate counters and notes the model has one
%   product against the machine's two; a 50 mm part that is NOT engraved is
%   what those counters are counting.
%
%   NOT YET MODELLED: the model has no product selection and no bypass branch,
%   so nothing ever commands CYL_B. It is placed, it breathes and it is drawn;
%   the sequence that would use it is question 3c.
%
%   AND ITS ROD IS NOT ALLOWED TO TOUCH THE WORKPIECE. On the current reading
%   that is not a workaround but the physics: a cylinder that belongs to the
%   engraving machine actuates the MACHINE, and what it moves is not the
%   workpiece. Whether it moves a head, a clamp or a stop is not stated, so no
%   stroke is claimed - it borrows CYL_A's, the other half of the same
%   double-solenoid pair at the same station, [ASM].
%
%   It was ALSO the fix for a real defect under the first reading, and that is
%   worth keeping. Placed as a diverter at the END of conveyor 2 pushing in -y,
%   it was COLLINEAR with that belt's own travel: its retracted rod tip sat in
%   the path of the block coming down the belt, the contact model read the
%   approach as interference, and the cycle diverged to NaN and timed out at
%   transition 10. A rod that must not touch the workpiece cannot do that.
%
%   THE THIRD PLACEMENT STATE. CYL_B has a POSITION and no PATH, which is
%   neither "fully placed" nor "unplaced". So a row may now give `from` without
%   `to`: the actuator stands at that waypoint, borrows a stroke, and is drawn.
%   Question 3c asks what it actually moves and how far.
%
%   NO ACTUATOR IS UNPLACED ANY MORE
%
%   All eleven now carry geometry, and the borrowed-stroke mechanism has no
%   users left. It is kept because the reason it existed has not gone away: an
%   actuator whose position nobody can state should get full pneumatics and no
%   contact geometry rather than an invented coordinate.
%
%   OUTFEED_B (coil 13) was placed by symmetry - FC6 N16 runs prox 9 to a 5 s
%   TP on solenoid 12 and prox 10 to a 5 s TP on solenoid 13, and outfeed A
%   stands at its own sensor, so outfeed B stands at PX10. [ASM], inferred from
%   the program's structure rather than from the layout.
%
%   INPUTS_REQUIRED.md questions 3b, 3c, 17 and 17d close what is left. Each
%   changes one row or one waypoint, not the structure.
%
%   WHAT THE BRANCH COLUMN IS, AND WHAT IT IS NOT
%
%   The four distribution branches are a SEQUENCE.XLSX construct. The machine
%   has one FRL and a manifold, and the PLC listing shows no distribution-valve
%   coil at all. So a branch number here says which of the model's four
%   supply groups feeds the actuator, and for the five actuators the sequence
%   drives it is [SRC] from the Excel step that selects it. For the other six
%   it is [ASM], chosen as the branch already serving that station.
%
%   This is where the baseline moved. Branch 1 fed two rod-side chambers and
%   now feeds six, so it charges more slowly and the CHG / BR_RDY waits gate
%   later. There is no way to put six more real actuators on a shared manifold
%   and keep the air dynamics identical, and pretending otherwise would be the
%   fiction, not the shift.
%
%   See also INITIALIZE_FACTORY, FACTORY_DERIVATIVES, FACTORY_IO_MAP,
%   FACTORY_SENSOR_BUS, FACTORYPARAMS.

if nargin < 1 || isempty(variant); variant = 'machine'; end

%   name           alias   role         dbl ext ret br axis dir  from       to          mag stroke_of       excel     short
adef = { ...
 'MAG1_PUSH'    , '' , 'mag_push'  , 0,  1,  0, 1, 'y', -1, 'feed'    , 'c1_load' , 1, ''             , '7-8'   , 'MAG1'     ; ...
 'MAG2_PUSH'    , '' , 'mag_push'  , 0,  2,  0, 1, 'y', -1, 'feed'    , 'c1_load' , 2, ''             , '-'     , 'MAG2'     ; ...
 'MAG3_PUSH'    , '' , 'mag_push'  , 0,  3,  0, 1, 'y', -1, 'feed'    , 'c1_load' , 3, ''             , '-'     , 'MAG3'     ; ...
 'MAG4_PUSH'    , '' , 'mag_push'  , 0,  4,  0, 1, 'y', -1, 'feed'    , 'c1_load' , 4, ''             , '-'     , 'MAG4'     ; ...
 'MAG5_PUSH'    , '' , 'mag_push'  , 0,  5,  0, 1, 'y', -1, 'feed'    , 'c1_load' , 5, ''             , '-'     , 'MAG5'     ; ...
 'XFER_CV1_CV2' , 'A6'  , 'xfer1'  , 0,  6,  0, 1, 'y', -1, 'c1_end'  , 'c2_load' , 0, ''             , '15-16' , 'XFER 1>2' ; ...
 'CYL_A'        , 'S2A1', 'eng_in' , 1,  7,  8, 2, 'x', +1, 'c2_end'  , 'engrave' , 0, ''             , '22-23' , 'CYL A'    ; ...
 'CYL_B'        , '' , 'bypass'    , 1,  9, 10, 3, 'y', -1, 'engrave' , ''        , 0, 'CYL_A'        , '-'     , 'CYL B'    ; ...
 'MOVE_TO_CV3'  , 'S3A1', 'eng_out', 0, 11,  0, 3, 'y', -1, 'engrave' , 'c3_load' , 0, ''             , '33-34' , 'MOVE>CV3' ; ...
 'OUTFEED_A'    , 'S3A2', 'eject'  , 0, 12,  0, 4, 'y', -1, 'c3_end'  , 'bin'     , 0, ''             , '41-42' , 'OUT A'    ; ...
 'OUTFEED_B'    , '' , 'outfeed_b' , 0, 13,  0, 4, 'y', -1, 'c3_out_b', 'bin_b'   , 0, ''             , '-'     , 'OUT B'    };

col = {'name','alias','role','dbl','coil_ext','coil_ret','branch', ...
       'axis','dir','from','to','mag','stroke_of','excel','short'};

A = struct();
for i = size(adef,1):-1:1
    for k = 1:numel(col)
        v = adef{i,k};
        if strcmp(col{k}, 'dbl'); v = logical(v); end
        A(i).(col{k}) = v;
    end
    A(i).placed  = ~isempty(A(i).from);            % has a position
    A(i).hasGeom = A(i).placed && ~isempty(A(i).to); % has a position AND a path
    A(i).contact = A(i).hasGeom;
end

% --- self-checks. These are cheap and they catch the edit that this table
%     exists to make safe: a coil written twice, or a borrowed stroke naming
%     an actuator that is not here.
coils = [ [A.coil_ext] [A.coil_ret] ];
coils = coils(coils > 0);
if numel(unique(coils)) ~= numel(coils)
    error('factory_actuators:coilReused', ...
        'A solenoid coil is claimed by two actuators: %s', mat2str(sort(coils)));
end
if ~isequal(sort(coils), 1:numel(coils))
    error('factory_actuators:coilGap', ...
        'Coils must number 1..N with no gap; got %s', mat2str(sort(coils)));
end
for i = 1:numel(A)
    if A(i).dbl && A(i).coil_ret == 0
        error('factory_actuators:doubleNeedsTwoCoils', ...
            '%s is double-solenoid but declares no retract coil.', A(i).name);
    end
    if ~A(i).dbl && A(i).coil_ret ~= 0
        error('factory_actuators:springHasTwoCoils', ...
            '%s is spring-return but declares a retract coil.', A(i).name);
    end
    % A row derives its own stroke exactly when it gives BOTH waypoints.
    % Anything else - one waypoint or none - must borrow one and say from whom.
    if A(i).hasGeom == isempty(A(i).stroke_of)
        continue
    end
    error('factory_actuators:strokeProvenance', ...
        ['%s must either give both waypoints (stroke from its own geometry) ' ...
         'or borrow a stroke, and not both or neither.'], A(i).name);
end
for i = 1:numel(A)
    if isempty(A(i).stroke_of); continue; end
    if ~any(strcmp({A.name}, A(i).stroke_of))
        error('factory_actuators:strokeDonorMissing', ...
            '%s borrows the stroke of "%s", which is not in this table.', ...
            A(i).name, A(i).stroke_of);
    end
end

% CYL_B is placed and must still not contact the workpiece - see the block
% comment above for the failure this prevents. Done here, once, rather than as
% a fifteenth column that ten rows would carry only to say "yes".
for i = find(strcmp({A.role}, 'bypass'))
    A(i).contact = false;
end

switch lower(variant)
    case 'machine'
        % the eleven above, as the machine has them
    case 'historical5'
        % The plant as it stood until 2026-09-02: the five actuators the
        % Sequence.xlsx cycle drives, every one of them a SINGLE spring-return
        % valve, coils numbered 1-5 in sequence order. Selected from the table
        % above rather than written out again, so the geometry cannot drift
        % from the geometry it is supposed to reproduce.
        keep = [1 6 7 8 10];      % MAG1, XFER_CV1_CV2, CYL_A, CYL_B, OUTFEED_A
        A = A(keep);
        for i = 1:numel(A)
            A(i).dbl      = false;
            A(i).coil_ext = i;
            A(i).coil_ret = 0;
        end
    otherwise
        error('factory_actuators:variant', ...
            'Unknown variant "%s". Use ''machine'' or ''historical5''.', variant);
end
end
