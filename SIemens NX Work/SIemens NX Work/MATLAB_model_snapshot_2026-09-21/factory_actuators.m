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
%     bore_mm   double  cylinder bore, mm. See the note on bores below.
%     rod_mm    double  rod diameter, mm
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
%   and, third, with the position marked on a drawing of the cell:
%
%       "cylinder B ... basically pushes the block when cylinder A doesn't
%        push it (when there is no engraving)"
%
%   THAT IS THE ONE THAT SETTLED IT, and it makes the cell's logic plain:
%
%     engraving selected      the block stops at c2_end and CYL_A pushes it
%                             +x into the engraver
%     no engraving (50 mm)    the block runs FURTHER DOWN conveyor 2, to the
%                             height of belt 3, and CYL_B pushes it +x across
%                             onto belt 3 - past the engraver entirely
%
%   So A and B are a matched pair at the same station on the same axis, one
%   above the other, and each is the other's alternative. Their travels come
%   out at 252.5 mm apiece and both round to the same 300 mm standard cylinder,
%   [2026-09-12, plan H3: SV11 lands at belt 3's start, c3_byp. Travel
%   117.5 mm, switch at 122.5 mm, stroke 125 on the ladder - the conflict
%   is gone. The stamped 160 waits on H7 with the other nameplates.]
%   which is corroboration rather than coincidence: they are the cell's two
%   big double-solenoid barrels.
%
%   This row took THREE placements in a day and the first two were wrong. It
%   was briefly a diverter at the END of conveyor 2 pushing -y, which put a rod
%   collinear with that belt's own travel and diverged the cycle to NaN; then
%   an engraving-machine cylinder with a position and no path at all. Both are
%   superseded. All FOUR owner statements are kept verbatim in FactoryParams
%   13E, because the reading kept changing and the words never did.
%
%   ~~Either way solenoid 11 is what makes the engraver-to-belt-3 move - the
%   owner said cylinders A and B both do not - which is what its own PLC name
%   said all along: FC6 N15 fires it on `Wp_move_cv3`, "workpiece move to
%   conveyor 3", with conveyor 3 on and conveyor 2 off.~~
%
%   OVERTURNED 2026-09-08 BY THE MACHINE'S OWN TRANSITION LOG, and this is the
%   fourth reading of this row. SOLENOID 11 NEVER FIRES. In the one real cycle
%   recorded with all 158 tags watched, `solenoid_valve11` does not appear at
%   all - not once - while `solenoid_valve9` rises at 80.751 s and
%   `solenoid_valve10` at 88.950 s, exactly in the slot where the block leaves
%   the engraver for belt 3, held 8.199 s.
%
%   So CYL_B makes that move and coil 11 makes nothing that has ever been
%   observed. The role and the geometry move to CYL_B; MOVE_TO_CV3 keeps its
%   coil, keeps breathing on the manifold, and is no longer commanded by the
%   sequence - the same state OUTFEED_B has been in all along.
%
%   THIS CONTRADICTS THE OWNER AND THE CONTRADICTION IS LEFT STANDING. The
%   owner said, four times and consistently, that cylinder B fires when
%   engraving is SKIPPED. The recording says cylinder B fires on the ENGRAVED
%   path. Both cannot describe the same cylinder. The owner's words are kept
%   verbatim in FACTORYPARAMS 13E and are not edited; what changed is which
%   source the model follows for the ENGRAVING path, and it now follows the
%   recording, because a transition log is an observation and a description is
%   a memory. The bypass question - what fires on the 50 mm no-engrave path -
%   is REOPENED and unanswered. The panel test (INPUTS_REQUIRED 3b) settles it
%   in five minutes and is the reason that test is on the lab list.
%
%   Note what this does NOT claim: that solenoid 11 does nothing. It claims
%   only that nothing has ever seen it move. It fires in simulator runs, which
%   is how it acquired its role in the first place.
%
%   ANSWERED 2026-09-11 - THE BYPASS IS SOLENOID 11, AND IT IS NOW MODELLED.
%   The maintainer, verbatim:
%
%       "CYLINDER b FIRES WHEN ENGRAVING IS DONE AND IT PUSHES BLOCK TO
%        BELT 3, SV11 FIRES WHEN ENGRAVING IS SKIPPED"
%
%   The first half is what this table has said since 2026-09-08: CYL_B is
%   eng_out. The second half gives MOVE_TO_CV3 the role 'bypass' and the
%   geometry the owner once marked for cylinder B - c2_byp -> c3_load (c3_byp, belt 3's start, since 2026-09-12), +x: the
%   block runs on past c2_end to belt 3's height and is pushed straight
%   across. The owner's four statements (13E) described the right ROUTE and
%   named the wrong barrel; the route now stands on the barrel that serves it.
%   The PLC listing agrees on its own terms: FC6 N5 turns prox 8 into
%   Wp_move_cv3, and FC6 N15 fires solenoid 11 as a T#2S pulse on Wp_move_cv3
%   with conveyor 3 on and conveyor 2 off. FACTORY_PLC runs that branch,
%   states S40-S43, when P.engrave_selected is false.
%
%   What this does NOT settle:
%     - THE STROKE. The layout gives 252.5 mm of travel, which rounds up to a
%       300 mm standard stroke, and SV11's barrel is stamped A51, 160 mm
%       (CYLINDER_PHOTOS 2026-09-10). A 160 mm rod cannot cover 252.5 mm, so
%       the schematic layout is too wide here - the same disagreement CYL_B's
%       208.5 mm travel has with its stamped 300. It waits on the belt datums.
%     - THE BORE. It stays the [JAN] 20 of every row but CYL_A; the nameplate's
%       25 is part of the nameplate re-baseline, not of this change.
%
%   This also gives the two products a consequence. Section 13C records
%   PRODUCT_HEIGHT 50 and 25 with separate counters and notes the model has one
%   product against the machine's two; a 50 mm part that is NOT engraved is
%   what those counters are counting.
%
%   SUPERSEDED 2026-09-08: CYL_B is now the sequence's eng_out actuator and is
%   commanded every cycle. The sentence below described it while it was the
%   bypass. What is still true is the second half - there is no product
%   selection and no no-engrave branch, so whatever serves the bypass is
%   unmodelled; it is simply no longer CYL_B.
%
%   ~~NOT YET MODELLED: the model has no product selection and no no-engrave
%   branch, so nothing ever commands CYL_B. It is fully placed, it breathes,
%   its rod is drawn and animated, and it would push the workpiece if it were
%   ever fired. The sequence that would fire it is question 3c.
%
%   TWO WRONG PLACEMENTS BEFORE THIS ONE, both worth keeping. First it was a
%   diverter at the END of conveyor 2 pushing in -y, which put a rod COLLINEAR
%   with that belt's own travel: its retracted tip sat in the path of the block
%   coming down, the contact model read the approach as interference, and the
%   cycle diverged to NaN and timed out at transition 10. Then, reading
%   statement (2) alone, it became an engraving-machine cylinder with a
%   position and no path at all - which needed a third placement state, since
%   removed, and claimed no travel.
%
%   Statement (3) settled it, and the geometry it produces is its own
%   corroboration: CYL_A and CYL_B come out as a MATCHED PAIR on the same axis
%   at the same station, both pushing +x, travels of 252.5 mm apiece rounding
%   to the same 300 mm standard cylinder, one at the engraver's height and one
%   at belt 3's. That is what the cell's two big double-solenoid barrels should
%   look like, and neither of the earlier readings produced it.
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
%   BORES ARE PER-ACTUATOR. ONE OF THE ELEVEN IS NOW READ OFF A NAMEPLATE.
%
%   P.A_A and P.A_B were single numbers - one bore for the whole cell - so
%   applying a real bore to one barrel meant changing every barrel. Section 13B
%   of FACTORYPARAMS proves that cannot be right: the vendor CAD measures bore
%   8 AND bore 32, doubly evidenced by the part names (Ø32 FEC / Ø32 REC), and
%   JANATICSDATA assumed 20 for all. Force goes as bore SQUARED, so the real
%   barrels differ by many times and the model sat between them.
%
%   These columns carried 20/8 for every actuator, tagged [JAN] and provisional
%   exactly as JANATICSDATA was, so that applying question 14's answer would be
%   an edit to THIS TABLE, one row per barrel, instead of a re-model. That is
%   what has now happened, and it took one row.
%
%   APPLIED 2026-09-07 - CYL_A IS BORE 32 / ROD 12, FROM A NAMEPLATE.
%
%   A barrel at the cell was photographed and its label reads A120323000:
%   Janatics A12 series, bore 32, stroke 300, MAX.PR 10 bar. JANATICSDATA
%   section 1B holds the code and the four independent corroborations of how
%   it is read. Why that barrel is CYL_A and not another row:
%
%     - it is the cell's LARGE cylinder, an ISO 6431 profile body. CYL_A and
%       CYL_B are the two big double-solenoid barrels at the engraving
%       station and the only actuators in this table that need real force.
%     - the nameplate stroke is 300 mm. This model DERIVED CYL_A's stroke as
%       300 mm from the layout alone - travel 252.5 mm rounded up the
%       standard ladder - before any barrel had been read. VERIFY_MODEL has
%       pinned that 300 since 2026-09-02. A derived stroke and a stamped
%       stroke agreeing is corroboration, not coincidence.
%     - the 2026-09-07 intake sheet gives a hand-measured stroke for
%       cylinder A of 29, which read as centimetres is 290 mm against a
%       stamped 300. Be precise about how strong that is: FACTORYPARAMS 13J
%       PROVES the unit for the SENSOR column, off the magazine pitch, and
%       the stroke column is a different column on the same sheet in the same
%       hand. So cm there is an inference - a well-supported one, since 290
%       and 170 land on two standard strokes and 29 and 17 land on none.
%
%   Three lines of evidence, two of them independent of the photograph.
%
%   WHAT THIS DOES NOT SETTLE, and why the other ten rows did not move:
%
%     CYL_B          the same intake sheet measures 17 -> 170 mm, which is
%                    close to the OTHER nameplate's 160 mm stroke and is
%                    nowhere near the 252.5 mm travel this table gives CYL_B.
%                    That is a CONFLICT and it points at the PLACEMENT, not
%                    at the barrel. Recorded in 13J; not resolved here.
%     MAG1-5_PUSH    hand-measured stroke 20 -> 200 mm, which matches NEITHER
%                    nameplate. The pushers are a third barrel and nobody has
%                    read it. The CAD's bore 8 is a candidate and stays one.
%     the other four the transfers and outfeeds were never photographed.
%
%   So ten rows keep the [JAN] bore 20 they have always had. It is known to be
%   wrong - nothing in this cell is bore 20 - and it is still the honest entry,
%   because "wrong by an unknown amount" is what those barrels are until
%   somebody reads them. Marking beats inventing; INPUTS_REQUIRED question 14
%   now asks for nine labels instead of six.
%   [SUPERSEDED 2026-09-13, plan H7: all ten were read, or taken as read on
%   the maintainer's statement, and every row now carries its nameplate bore
%   and stroke. See the provenance block below.]
%
%   See also INITIALIZE_FACTORY, FACTORY_DERIVATIVES, FACTORY_IO_MAP,
%   FACTORY_SENSOR_BUS, FACTORYPARAMS.

if nargin < 1 || isempty(variant); variant = 'machine'; end

% BORE PROVENANCE, ROW BY ROW. There is no column for this because a tag per
% row would be a tenth-column of the same word repeated ten times; the split is
% clean enough to state once:
%     CYL_A            32 / 12   [MEAS] nameplate A120323000, rod from [CAD]
%     CYL_B            32 / 12   [MEAS] nameplate A280323000 (A28), rod [EST]:
%                                ISO 15552 pairs bore 32 with rod 12
%     MAG1-5, XFER, SV11 (MOVE_TO_CV3), SV12 (OUTFEED_A)
%                      25 / 10   [MEAS] nameplate A510251600 (A51), rod [EST]:
%                                ISO 6432 pairs bore 25 with rod 10. MAG1, 3,
%                                4 and 5 on the maintainer's statement that
%                                every unique barrel was photographed
%     SV13 (OUTFEED_B) 25 / 10   [MEAS] nameplate A520251600 (A52, magnetic)
%     Until 2026-09-13 every row but CYL_A carried the [JAN] 20 / 8 (plan H7).
%
% STROKES. stroke_mm is the NAMEPLATE stroke; NaN means derive it - the travel
% plus the approach gap, rounded up the Janatics ladder - which is what every
% row did until 2026-09-13. INITIALIZE_FACTORY refuses a nameplate stroke too
% short to reach its own reed switch.
%
%   name           alias   role         dbl ext ret br axis dir  from       to          mag stroke_of       excel     short        bore rod stroke
adef = { ...
 'MAG1_PUSH'    , '' , 'mag_push'  , 0,  1,  0, 1, 'y', -1, 'feed'    , 'c1_load' , 1, ''             , '7-8'   , 'MAG1', 25, 10, 160 ; ...
 'MAG2_PUSH'    , '' , 'mag_push'  , 0,  2,  0, 1, 'y', -1, 'feed'    , 'c1_load' , 2, ''             , '-'     , 'MAG2', 25, 10, 160 ; ...
 'MAG3_PUSH'    , '' , 'mag_push'  , 0,  3,  0, 1, 'y', -1, 'feed'    , 'c1_load' , 3, ''             , '-'     , 'MAG3', 25, 10, 160 ; ...
 'MAG4_PUSH'    , '' , 'mag_push'  , 0,  4,  0, 1, 'y', -1, 'feed'    , 'c1_load' , 4, ''             , '-'     , 'MAG4', 25, 10, 160 ; ...
 'MAG5_PUSH'    , '' , 'mag_push'  , 0,  5,  0, 1, 'y', -1, 'feed'    , 'c1_load' , 5, ''             , '-'     , 'MAG5', 25, 10, 160 ; ...
 'XFER_CV1_CV2' , 'A6'  , 'xfer1'  , 0,  6,  0, 1, 'y', -1, 'c1_end'  , 'c2_load' , 0, ''             , '15-16' , 'XFER 1>2', 25, 10, 160 ; ...
 'CYL_A'        , 'S2A1', 'eng_in' , 1,  7,  8, 2, 'x', +1, 'c2_end'  , 'engrave' , 0, ''             , '22-23' , 'CYL A', 32, 12, 300 ; ...
 'CYL_B'        , 'S3A1', 'eng_out', 1,  9, 10, 3, 'y', -1, 'engrave' , 'c3_load' , 0, ''             , '33-34' , 'CYL B', 32, 12, 300 ; ...
 'MOVE_TO_CV3'  , '' , 'bypass'    , 0, 11,  0, 3, 'x', +1, 'c2_byp'  , 'c3_byp'  , 0, ''             , '-'     , 'MOVE>CV3', 25, 10, 160 ; ...
 'OUTFEED_A'    , 'S3A2', 'eject'  , 0, 12,  0, 4, 'y', -1, 'c3_end'  , 'bin'     , 0, ''             , '41-42' , 'OUT A', 25, 10, 160 ; ...
 'OUTFEED_B'    , '' , 'outfeed_b' , 0, 13,  0, 4, 'y', -1, 'c3_out_b', 'bin_b'   , 0, ''             , '-'     , 'OUT B', 25, 10, 160};

col = {'name','alias','role','dbl','coil_ext','coil_ret','branch', ...
       'axis','dir','from','to','mag','stroke_of','excel','short', ...
       'bore_mm','rod_mm','stroke_mm'};

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
    if A(i).placed ~= A(i).hasGeom
        error('factory_actuators:halfPlaced', ...
            ['%s gives one waypoint and not the other. That state existed ' ...
             'briefly for CYL_B and is gone; give both or neither.'], A(i).name);
    end
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
% Bores became a per-row edit on 2026-09-07, so they now need the same cheap
% guard the coils have. A rod at least as wide as its bore gives a zero or
% negative annulus area, which the chamber equations would carry silently as a
% cylinder that cannot retract.
for i = 1:numel(A)
    if ~(A(i).rod_mm > 0 && A(i).rod_mm < A(i).bore_mm)
        error('factory_actuators:boreRod', ...
            ['%s declares bore %g mm and rod %g mm. The rod must be ' ...
             'positive and strictly narrower than the bore, or the ' ...
             'rod-side area is not a real annulus.'], ...
            A(i).name, A(i).bore_mm, A(i).rod_mm);
    end
end
for i = 1:numel(A)
    if isempty(A(i).stroke_of); continue; end
    if ~any(strcmp({A.name}, A(i).stroke_of))
        error('factory_actuators:strokeDonorMissing', ...
            '%s borrows the stroke of "%s", which is not in this table.', ...
            A(i).name, A(i).stroke_of);
    end
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
        % Selected BY ROLE, never by index. The first version of this listed
        % positions - [1 6 7 8 10] - and silently selected the wrong five the
        % moment the table was re-ordered, which happened the same day when
        % cylinder B turned out to be an engraving-machine cylinder and
        % solenoid 11 took over the engraver-to-belt-3 move. Six latency tests
        % failed at once, which is the good outcome; a role lookup cannot drift.
        want = {'mag_push','xfer1','eng_in','eng_out','eject'};
        keep = zeros(1,numel(want));
        for w = 1:numel(want)
            k = find(strcmp({A.role}, want{w}), 1);
            if isempty(k)
                error('factory_actuators:historicalRole', ...
                    ['The historical five need a "%s" actuator and the table ' ...
                     'has none.'], want{w});
            end
            keep(w) = k;
        end
        A = A(keep);
        for i = 1:numel(A)
            A(i).dbl      = false;
            A(i).coil_ext = i;
            A(i).coil_ret = 0;
            % AND THE OLD BORE, restored 2026-09-07. Every cylinder was bore
            % 20 / rod 8 when the REF_D0_* and REF_D1_* figures in
            % PLCIOLATENCYTEST were measured, so bore 20 is one of "the
            % conditions they were taken under" in exactly the way the
            % workpiece and the five-cylinder plant already are. Applying
            % CYL_A's real 32 / 12 here broke two of those tests the moment
            % the nameplate landed - correctly, and that is the whole point of
            % pinning them: a 2.6x chamber cannot reproduce a measurement made
            % on a smaller one. Re-pinning the figures to the new bore instead
            % would turn the project's strongest piece of diagnostic evidence
            % into a self-referential regression pin.
            A(i).bore_mm  = 20;
            A(i).rod_mm   = 8;
            A(i).stroke_mm = NaN;   % ...and derived strokes (plan H7, 2026-09-13)
        end
    otherwise
        error('factory_actuators:variant', ...
            'Unknown variant "%s". Use ''machine'' or ''historical5''.', variant);
end
end
