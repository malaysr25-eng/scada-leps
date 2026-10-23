function LOG = factory_log(action)
%FACTORY_LOG  The current simulation result, computed once and cached.
%
%   LOG = FACTORY_LOG()         cached result, running the simulation if needed
%   FACTORY_LOG('clear')        discard the cached result
%   tf  = FACTORY_LOG('has')    true if a result is already cached
%
%   WHY THIS EXISTS
%   Half the commands in this project take a LOG, and a LOG costs about 17 s to
%   produce. That made two things happen repeatedly:
%
%     1. "Unrecognized function or variable 'LOG'" - the commonest error here.
%        MATLAB then suggests the built-in log(), which sends the reader off in
%        entirely the wrong direction.
%     2. The same 17 s simulation re-run once per view, because each viewer
%        needed its own LOG.
%
%   With this, the viewers take no argument:
%
%       visualize_processes          % gets or produces a LOG itself
%       visualize_factory
%       plot_factory_results
%
%   THE CACHE CAN GO STALE, and that matters. It holds a result, not
%   parameters, so editing FactoryParams.m or JanaticsData.m does NOT
%   invalidate it on its own. RESET_FACTORY clears it along with the parameter
%   cache, which is why RESET_FACTORY is mandatory after a parameter edit.
%
%   Same pattern, and same hazard, as FACTORY_PARAMS_CACHED - see its header.
%
%   Passing a LOG explicitly always wins; nothing here is implicit if you do
%   not want it to be:
%
%       LOG = run_factory_simulation;
%       visualize_processes(LOG)
%
%   See also RUN_FACTORY_SIMULATION, RESET_FACTORY, FACTORY_PARAMS_CACHED.

persistent Lc

if nargin > 0
    switch lower(action)
        case 'clear'
            Lc = [];
            if nargout; LOG = []; end
            return
        case 'has'
            LOG = ~isempty(Lc);
            return
        otherwise
            error('factory_log:action', ...
                ['FACTORY_LOG takes no argument, ''clear'' or ''has'', ' ...
                 'got ''%s''.'], char(string(action)));
    end
end

if isempty(Lc)
    fprintf(['No simulation result cached. Running run_factory_simulation ' ...
             '(about 17 s) ...\n']);
    Lc = run_factory_simulation('Plot', false, 'Verbose', false);
    fprintf('Cached. Cycle %.4f s. Cleared by reset_factory.\n', Lc.cycle_time);
end
LOG = Lc;
end
