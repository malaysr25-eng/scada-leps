MATLAB MODEL - SNAPSHOT OF 2026-09-21 (git commit 2590215)

A copy of Factory_Simulation/Factory_Simulation for use at the lab PC.
DO NOT EDIT HERE. The repository on the laptop (and GitHub) is the model of
record; changes made in this copy are not tracked and will be lost.

To run the model at the lab PC (MATLAB R2018b or newer; Simulink only for the
Simulink path), open MATLAB in this folder and at the prompt:

    factory_help                                            % what everything does
    run_factory_simulation('Operator', 'console', 'Live', true)
    Q = FactoryParams(); Q.engrave_selected = false; run_factory_simulation('Params', Q)

Build artefacts (slprj/, __pycache__/) were left out; MATLAB and Python
regenerate them.
