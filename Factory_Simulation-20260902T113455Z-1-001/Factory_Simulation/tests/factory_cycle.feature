# --- front-matter:toml ---
model = "Factory_Physics_Model.slx"
[inputs]
CmdExt1 = "cmd_ext(1)"
[outputs]
PlcState = "plc_state_out"
# --- end front-matter ---
#
# The first Simulink Test coverage this model has ever had. It became possible
# on 2026-08-25, when the model gained root Inports and Outports and
# ModelReferenceNumInstancesAllowed was set to Single. Before that, model_test
# refused the model outright.
#
# CmdExt1 is declared but inert. The model picks its command source from the
# model-workspace variable FACTORY_EXT_CMD, which defaults to 0, meaning the PLC
# drives the plant and cmd_ext is ignored. This scenario therefore exercises the
# real closed-loop cell. The input is declared only because the dialect requires
# a line for every declared input.
#
# KNOWN LIMITATION - VECTOR ELEMENTS DO NOT EVALUATE HERE.
# Two further scenarios were written and are held back. They assert that the
# workpiece stays inside the cell and that the receiver stays between
# atmosphere and the relief setting. Both need an element of a wide vector:
#
#     BlockX   = "plant_state_out(47)"     workpiece x, from a 51-wide port
#     BlockY   = "plant_state_out(48)"     workpiece y
#     Receiver = "plant_state_out(1)"      receiver pressure
#
# That is the documented syntax and it VALIDATES, but every assessment using it
# then fails at run time with "Error evaluating assessment", while the scalar
# plc_state_out below resolves and passes. The ":1(N)" form that the harness
# itself prints is rejected as a block name, so it is not the answer either.
#
# The fix is probably not in this file: give the model scalar root Outports for
# the few quantities worth asserting, rather than indexing a 51-wide bus. That
# is a small change to build_factory_model, and is the next thing to try.
#
# Written down rather than deleted, so the scenarios do not have to be
# reinvented and nobody repeats the ":1(N)" experiment.

Feature: Factory cell invariants under Simulink Test
  Absolute bounds that hold for any valid parameter set, checked as Simulink
  signals rather than as logged data.

Scenario: The sequencer stays inside its declared state range
  factory_states declares exactly 40 states, so a state number outside 1..40 is
  an index error waiting to happen. Nothing else in the suite watches the PLC
  state as a Simulink signal rather than as logged data.
  Given inputs
    * CmdExt1 = const(0)
  When simulate for 0.5s in Normal mode
  Then outputs
    * StateWithinTable: PlcState == [1 .. 40]
