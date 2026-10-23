function [idx, name] = support_region(bx, by, P)
%SUPPORT_REGION  Which surface currently carries the workpiece.
%
%   [idx, name] = SUPPORT_REGION(bx, by, P) returns the index into P.REG of
%   the first region containing the workpiece centre, or 0 ('plate') if the
%   workpiece is on a static transfer plate.
%
%   P.REG is PRIORITY ORDERED. Conveyor 3 precedes the engraver because their
%   footprints overlap in y = 4.30..4.54 drawing units; the workpiece there
%   has already been transferred to the belt.

idx = 0; name = 'plate';
for i = 1:numel(P.REG)
    b = P.REG(i).box;                       % [x0 x1 y0 y1]
    if bx >= b(1) && bx <= b(2) && by >= b(3) && by <= b(4)
        idx = i; name = P.REG(i).name; return;
    end
end
end
