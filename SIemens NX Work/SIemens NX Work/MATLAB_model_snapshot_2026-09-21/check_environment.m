function env = check_environment(varargin)
%CHECK_ENVIRONMENT  Verify everything the simulation needs is present.
%
%   env = CHECK_ENVIRONMENT()                    check the MATLAB-only path
%   env = CHECK_ENVIRONMENT('Simulink', true)    also check the Simulink path
%   env = CHECK_ENVIRONMENT('Quiet', true)       no printing, just the struct
%   env = CHECK_ENVIRONMENT('Toolboxes', true)   also audit LICENSED toolboxes
%
%   THE TOOLBOX AUDIT IS WORTH RUNNING ONCE. On 2026-08-24 it found nine
%   toolboxes LICENSED BUT NOT INSTALLED - Stateflow, Simscape, Simulink Test,
%   Simulink Coverage, OPC, Design Verifier, Embedded Coder, Control System and
%   Instrument Control. The project had spent its whole life documenting
%   workarounds for tools it already owned. A licensed-but-absent toolbox is an
%   Add-On Manager download, not a purchase.
%
%   Returns a struct with a logical .ok and one field per check. Run this
%   FIRST if anything misbehaves - it answers "what is missing" before you
%   start reading error messages.
%
%   WHAT IS ACTUALLY REQUIRED
%     MATLAB-only path (run_factory_simulation):  base MATLAB, no toolboxes.
%     Simulink path (run_simulink_model):         + Simulink.
%     Stateflow PLC variant (optional):           + Stateflow.
%     Simscape / Simscape Fluids / Multibody:     NOT used by this model.
%
%   See also RUN_FACTORY_SIMULATION, RUN_SIMULINK_MODEL, VERIFY_MODEL.

o = struct('Simulink', false, 'Quiet', false, 'Toolboxes', false);
o = parse_options(o, varargin, mfilename);

rows = {};   % {label, pass, detail}

%% ---- MATLAB version ----------------------------------------------------
% R2018b is the floor because the code uses yline, sgtitle and
% Simulink.BlockDiagram.arrangeSystem. Nothing needs anything newer.
v = version('-release');
try
    oldMatlab = verLessThan('matlab','9.5');   % 9.5 = R2018b
catch
    oldMatlab = false;
end
rows(end+1,:) = {'MATLAB R2018b or newer', ~oldMatlab, ['found R' v]};

%% ---- required project files -------------------------------------------
need = {'FactoryParams','JanaticsData','initialize_factory', ...
        'factory_derivatives','factory_sensors','factory_states', ...
        'factory_plc','factory_plc_init','support_region', ...
        'run_factory_simulation','plot_factory_results','visualize_factory', ...
        'factory_params_cached','reset_factory'};
missing = need(cellfun(@(f) isempty(which(f)), need));
rows(end+1,:) = {'core MATLAB files on the path', isempty(missing), ...
                 ternary(isempty(missing),'all 14 found', ...
                         ['missing: ' strjoin(missing, ', ')])};

%% ---- parameters actually build ----------------------------------------
okP = false; detP = '';
try
    [P, s0] = initialize_factory(FactoryParams());
    okP = numel(s0) == P.NS && all(isfinite(s0));
    detP = sprintf('%d states, %d cylinders, %d conveyors', ...
                   P.NS, P.NCYL, P.NCONV);
catch ME
    detP = ME.message;
end
rows(end+1,:) = {'parameters initialise', okP, detP};

%% ---- one derivative evaluation ----------------------------------------
okD = false; detD = '';
if okP
    try
        u  = struct('pump_on',false,'dv',[0 0 0 0], ...
                    'sol',zeros(1,P.NSOL),'conv',[0 0 0],'base',0);
        ds = factory_derivatives(s0, u, P);
        okD = numel(ds) == P.NS && all(isfinite(ds));
        detD = ternary(okD, 'finite derivative at t = 0', ...
                       'non-finite or wrong length');
    catch ME
        detD = ME.message;
    end
end
rows(end+1,:) = {'physics evaluates', okD, detD};

%% ---- Simulink path ----------------------------------------------------
if o.Simulink
    hasSL = license('test','Simulink') && ~isempty(ver('simulink'));
    rows(end+1,:) = {'Simulink', hasSL, ternary(hasSL,'licensed and installed', ...
                     'not available - use run_factory_simulation instead')};

    slFiles = {'factory_plant_sfun','factory_plc_sfun', ...
               'build_factory_model','run_simulink_model'};
    missSL = slFiles(cellfun(@(f) isempty(which(f)), slFiles));
    rows(end+1,:) = {'Simulink files on the path', isempty(missSL), ...
                     ternary(isempty(missSL),'all 4 found', ...
                             ['missing: ' strjoin(missSL, ', ')])};

    hasMdl = ~isempty(which('Factory_Physics_Model.slx'));
    rows(end+1,:) = {'Factory_Physics_Model.slx', true, ...
                     ternary(hasMdl,'present', ...
                             'not built yet - run_simulink_model builds it')};

    hasSF = ~isempty(ver('stateflow'));
    rows(end+1,:) = {'Stateflow (optional)', true, ...
                     ternary(hasSF,'available - the stateflow PLC variant can be built', ...
                             'absent - not needed, the default PLC does not use it')};
end

%% ---- write permission --------------------------------------------------
okW = false;
try
    tf = fullfile(pwd, ['.write_test_' num2str(feature('getpid')) '.tmp']);
    fid = fopen(tf,'w');
    if fid > 0; fclose(fid); delete(tf); okW = true; end
catch
end
rows(end+1,:) = {'current folder is writable', okW, pwd};

%% ---- optional toolbox audit --------------------------------------------
% Kept OUT of env.ok on purpose. None of these is needed to run the model as it
% stands, so a missing one is an opportunity, not a failure.
env.toolboxes = struct([]);
if o.Toolboxes
    tb = { 'Stateflow',               'Stateflow', ...
              'sequencer as a real chart, not an S-function'
           'Simscape',                'Simscape', ...
              'native physical networks for the pneumatics'
           'Simulink Test',           'Simulink_Test', ...
              'model_test - see Project_Notes/HANDOFF.md issue 10'
           'Simulink Coverage',       'Simulink_Coverage', ...
              'model coverage metrics'
           'Industrial Communication', 'OPC_Toolbox', ...
              'LIVE link to the real PLC - what makes this a twin'
           'Simulink Design Verifier','Simulink_Design_Verifier', ...
              'formal property proving on the sequencer'
           'Embedded Coder',          'RTW_Embedded_Coder', ...
              'code generation from the model'
           'Control System Toolbox',  'Control_Toolbox', ...
              'linearisation and controller tuning'
           'Instrument Control Toolbox','Instr_Control_Toolbox', ...
              'direct instrument I/O' };
    nm = string({ver().Name});
    % PRODUCTS GET RENAMED. OPC Toolbox became Industrial Communication Toolbox
    % in R2022b while keeping the licence feature OPC_Toolbox, so a name-only
    % match reported it missing on a machine where it was installed and working.
    % Match on any known alias, and confirm with a function the product owns.
    alias = containers.Map( ...
        {'Industrial Communication'}, ...
        {{'Industrial Communication','OPC Toolbox'}});
    probe = containers.Map( ...
        {'Industrial Communication'}, {'opcua'});
    for i = 1:size(tb,1)
        try
            lic = logical(license('test', tb{i,2}));
        catch
            lic = false;
        end
        key = tb{i,1};
        if isKey(alias, key); cand = alias(key); else; cand = {key}; end
        inst = any(cellfun(@(c) any(contains(nm, c)), cand));
        if ~inst && isKey(probe, key); inst = exist(probe(key), 'file') > 0; end
        env.toolboxes(i).name      = tb{i,1};
        env.toolboxes(i).installed = inst;
        env.toolboxes(i).licensed  = lic;
        env.toolboxes(i).unblocks  = tb{i,3};
    end
end

%% ---- assemble ----------------------------------------------------------
env.ok = all([rows{:,2}]);
for i = 1:size(rows,1)
    env.checks(i).name   = rows{i,1};
    env.checks(i).pass   = rows{i,2};
    env.checks(i).detail = rows{i,3};
end

if ~o.Quiet
    fprintf('\n  ENVIRONMENT CHECK\n');
    fprintf('  %s\n', repmat('-',1,72));
    for i = 1:size(rows,1)
        mark = ternary(rows{i,2}, 'OK  ', 'FAIL');
        fprintf('  [%s] %-32s %s\n', mark, rows{i,1}, rows{i,3});
    end
    fprintf('  %s\n', repmat('-',1,72));

    if o.Toolboxes && ~isempty(env.toolboxes)
        T = env.toolboxes;
        gap = T([T.licensed] & ~[T.installed]);
        fprintf('\n  TOOLBOX AUDIT\n');
        fprintf('  %s\n', repmat('-',1,72));
        fprintf('  %-26s %-10s %-9s %s\n','toolbox','installed','licensed','unblocks');
        for i = 1:numel(T)
            fprintf('  %-26s %-10s %-9s %s\n', T(i).name, ...
                    ternary(T(i).installed,'yes','no'), ...
                    ternary(T(i).licensed,'yes','no'), T(i).unblocks);
        end
        fprintf('  %s\n', repmat('-',1,72));
        if isempty(gap)
            fprintf('  Nothing licensed is missing.\n');
        else
            fprintf(['  %d toolbox(es) are LICENSED BUT NOT INSTALLED. That is a\n' ...
                     '  download, not a purchase. Add-On Manager:\n' ...
                     '      Home tab > Add-Ons > Get Add-Ons\n'], numel(gap));
            for i = 1:numel(gap)
                fprintf('      %-26s %s\n', gap(i).name, gap(i).unblocks);
            end
        end
        fprintf('\n');
    end

    if env.ok
        fprintf('  Ready. Next:  LOG = run_factory_simulation;\n\n');
    else
        fprintf(['  Not ready. See README.md section 12 (Troubleshooting) ' ...
                 '(common errors).\n\n']);
    end
end
end

%% ========================================================================
function out = ternary(c, a, b)
if c; out = a; else; out = b; end
end
