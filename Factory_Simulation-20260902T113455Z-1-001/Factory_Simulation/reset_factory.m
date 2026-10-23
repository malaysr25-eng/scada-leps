function reset_factory(varargin)
%RESET_FACTORY  Return the project to a clean pre-simulation state.
%
%   RESET_FACTORY()                 clear caches and controller state
%   RESET_FACTORY('Model', true)    also close the Simulink model
%   RESET_FACTORY('Quiet', true)    no printing
%
%   WHY YOU NEED THIS
%   Three things survive between runs and can make a simulation appear to
%   ignore your edits:
%     1. FACTORY_PARAMS_CACHED holds the parameter struct in a persistent
%        variable. Edit FactoryParams.m or JanaticsData.m without clearing
%        it and the Simulink model keeps the OLD numbers, silently.
%     2. FACTORY_PLC_SFUN holds the controller state in a persistent
%        variable. After an aborted run it can be left mid-cycle.
%     3. FACTORY_LOG caches a simulation RESULT. It holds no parameters, so a
%        parameter edit does not invalidate it on its own - which is exactly
%        why clearing it here is mandatory rather than optional.
%     4. A loaded .slx keeps whatever settings were last applied to it.
%
%   The pure-MATLAB driver RUN_FACTORY_SIMULATION builds its parameters
%   fresh on every call and is never affected by any of this. Only the
%   Simulink path needs resetting.
%
%   See also FACTORY_PARAMS_CACHED, RUN_SIMULINK_MODEL.

o = struct('Model', false, 'Quiet', false, 'Workspace', false);
o = parse_options(o, varargin, mfilename);

clear factory_params_cached
clear factory_plc_sfun
clear factory_plant_sfun
factory_log('clear');   % the cached simulation RESULT, see FACTORY_LOG

if o.Model
    mdl = 'Factory_Physics_Model';
    if bdIsLoaded(mdl); close_system(mdl, 0); end
end

if o.Workspace
    evalin('base', 'clear plant_state sensors commands plc_state LOG out');
end

if ~o.Quiet
    fprintf('Reset: parameter cache cleared, PLC state cleared.\n');
    if o.Model; fprintf('       Simulink model closed without saving.\n'); end
    fprintf('Next simulation will rebuild parameters from FactoryParams.m.\n');
end
end
