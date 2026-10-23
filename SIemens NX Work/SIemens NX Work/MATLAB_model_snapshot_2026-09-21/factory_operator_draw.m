function P = factory_operator_draw(P, seed)
%FACTORY_OPERATOR_DRAW  Replace the operator times with one sampled dwell.
%
%   P = FACTORY_OPERATOR_DRAW(P, SEED) returns P with t_op_notice, t_engrave
%   and t_op_confirm set from ONE draw of the seven measured platform dwells
%   in P.OP.samples. SEED makes the draw reproducible.
%
%   FACTORYPARAMS deliberately does not do this itself: it takes no arguments
%   and much of the project calls it expecting the same struct every time. A
%   parameter file that returned a different answer per call would be a trap.
%
%   WHAT IS MEASURED AND WHAT IS NOT
%     MEASURED   the TOTAL dwell, seven real cycles, and the confirm delay
%                (n=1). See FACTORYPARAMS section 10.
%     NOT        how the remainder splits between noticing and engraving. That
%                was observed once, and one observation cannot support a ratio,
%                so P.OP.notice_frac stays [PLH] at 3/11.
%
%   The draw is WITH REPLACEMENT from the seven observations - a bootstrap, not
%   a fitted distribution. With n = 7 a fitted shape would be an artefact of
%   seven points.
%
%   Example
%     P = factory_operator_draw(FactoryParams(), 12);
%     L = run_factory_simulation('Params', P);
%
%   See also OPERATOR_DISTRIBUTION, FACTORYPARAMS.

if nargin < 2 || isempty(seed); seed = 0; end

% A LOCAL stream. Seeding the global generator would silently change any other
% random work in the session - action at a distance this project avoids.
rs    = RandStream('twister', 'Seed', seed);
total = P.OP.samples(randi(rs, numel(P.OP.samples)));

P.t_op_confirm = P.OP.confirm;
rest           = total - P.OP.confirm;
P.t_op_notice  = rest * P.OP.notice_frac;
P.t_engrave    = rest * (1 - P.OP.notice_frac);
P.op_mode      = 'sample';
P.op_seed      = seed;
P.op_total     = total;          % what was drawn, for the caller to record
end
