function [P, s0] = factory_params_cached(force)
%FACTORY_PARAMS_CACHED  Parameter struct, built once and cached.
%
%   [P, s0] = FACTORY_PARAMS_CACHED()       cached (build on first call)
%   [P, s0] = FACTORY_PARAMS_CACHED(true)   force a rebuild
%
%   WHY THIS EXISTS
%   Iteration 01's S-function called
%       P = initialize_factory(FactoryParams());
%   inside Outputs() and inside Derivatives(). Those run four times per solver
%   step for ode4, i.e. about 720,000 times over a 45 s run at dt = 5e-4.
%   Rebuilding the whole parameter struct, cylinder table, region table and
%   index map that many times made the Simulink model unusable - it was not
%   wrong, it was simply too slow to finish. This caches it.
%
%   IMPORTANT - THE CACHE IS THE THING YOU MUST CLEAR AFTER EDITING PARAMETERS
%   MATLAB keeps the cached struct in memory between simulation runs. After
%   editing FactoryParams.m or JanaticsData.m you MUST run:
%
%       clear factory_params_cached
%
%   or the Simulink model will silently keep using the OLD values. RESET_
%   FACTORY does this for you. The pure-MATLAB driver
%   RUN_FACTORY_SIMULATION does not use this cache and is never stale.
%
%   See also RESET_FACTORY, FACTORYPARAMS, INITIALIZE_FACTORY.

persistent Pc s0c
if nargin > 0 && force
    Pc = []; s0c = [];
end
if isempty(Pc)
    [Pc, s0c] = initialize_factory(FactoryParams());
end
P  = Pc;
s0 = s0c;
end
