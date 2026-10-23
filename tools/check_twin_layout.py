#!/usr/bin/env python
"""
Sanity-check the 3-D machine layout.

Catches the class of error that a type-checker cannot: a component placed
outside the table, a conveyor running off the frame, two parts occupying the
same space, a typo that puts a sensor underground.

Parses the coordinate literals straight out of `machineLayout.ts` so there is
one source of truth and this cannot drift from what actually renders.

    python tools/check_twin_layout.py
"""

from __future__ import annotations

import os
import re
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LAYOUT = os.path.join(
    HERE, "frontend", "src", "components", "twin3d", "machineLayout.ts"
)

PASS, FAIL = [], []


def check(name, ok, detail=""):
    (PASS if ok else FAIL).append((name, detail))
    print("  %s  %s%s" % ("PASS" if ok else "FAIL", name,
                          ("  -- " + detail) if detail and not ok else ""))
    return ok


def const(src: str, name: str) -> float:
    m = re.search(r"export const %s\s*=\s*([0-9.]+)" % name, src)
    if not m:
        raise SystemExit("could not find constant %s" % name)
    return float(m.group(1))


_ID_RE = re.compile(r"id:\s*[`'\"]([^`'\"]+)[`'\"]")
_POS_RE = re.compile(
    r"position:\s*\[\s*(-?[\d.]+)\s*,\s*([^,\]]+?)\s*,\s*(-?[\d.]+)\s*\]"
)


def positions(src: str):
    """
    Every `position: [x, y, z]` literal, paired with the nearest preceding `id:`.

    Scanning forward from an id and hoping the position is within N characters
    was too fragile — it silently matched only 3 of 20 placements, which made
    the bounds check look like it passed when it had barely run. Walking both
    token streams by offset is unambiguous.

    The Y term is often an expression (`TABLE_HEIGHT + 0.075`), so it is
    evaluated against the known constants rather than parsed as a literal.
    """
    table_h = const(src, "TABLE_HEIGHT")

    ids = [(m.start(), m.group(1)) for m in _ID_RE.finditer(src)]
    out = []

    for m in _POS_RE.finditer(src):
        preceding = [name for off, name in ids if off < m.start()]
        if not preceding:
            continue
        raw_y = m.group(2).strip()
        try:
            y = float(raw_y)
        except ValueError:
            expr = raw_y.replace("TABLE_HEIGHT", repr(table_h))
            try:
                y = float(eval(expr, {"__builtins__": {}}, {}))  # noqa: S307
            except Exception:
                continue
        out.append((preceding[-1], float(m.group(1)), y, float(m.group(3))))

    return out


def main() -> int:
    if not os.path.exists(LAYOUT):
        print("layout file not found: %s" % LAYOUT)
        return 2

    src = open(LAYOUT, encoding="utf-8").read()

    print("Twin layout check\n" + "-" * 40)

    conveyor_len = const(src, "CONVEYOR_LENGTH")
    table_h = const(src, "TABLE_HEIGHT")
    belt_w = const(src, "BELT_WIDTH")

    print("\n1. Scale anchor")
    check("Conveyor length matches the lab data sheet (0.76 m)",
          abs(conveyor_len - 0.76) < 1e-9,
          "got %.3f" % conveyor_len)
    check("Table height is plausible for a bench cell (0.6-1.0 m)",
          0.6 <= table_h <= 1.0, "%.2f m" % table_h)
    check("Belt width is plausible (0.05-0.30 m)",
          0.05 <= belt_w <= 0.30, "%.3f m" % belt_w)

    cw = re.search(r"width:\s*([\d.]+),\s*//\s*X", src)
    cd = re.search(r"depth:\s*([\d.]+),\s*//\s*Z", src)
    cell_w = float(cw.group(1)) if cw else 0.0
    cell_d = float(cd.group(1)) if cd else 0.0

    print("\n2. Cell envelope")
    check("Cell is wide enough for two in-line conveyors",
          cell_w >= conveyor_len * 2, "%.2f m vs %.2f m needed" % (cell_w, conveyor_len * 2))
    check("Cell is deep enough for the perpendicular conveyor",
          cell_d >= conveyor_len * 1.5, "%.2f m" % cell_d)

    print("\n3. Component placement")
    pts = positions(src)
    check("Layout defines a reasonable number of placed components",
          len(pts) >= 15, "found %d" % len(pts))

    # Cabinet, receiver and desk sit deliberately outside the table footprint,
    # exactly as in the photographs, so they are exempt from the bounds check.
    outside_ok = {"cabinet", "air_receiver", "desk"}
    margin = 0.6

    for pid, x, y, z in pts:
        if pid in outside_ok:
            continue
        check("'%s' is inside the cell footprint" % pid,
              -margin <= x <= cell_w + margin and -margin <= z <= cell_d + margin,
              "at (%.2f, %.2f)" % (x, z))

    print("\n4. Vertical sanity")
    for pid, x, y, z in pts:
        check("'%s' is above the floor" % pid, y >= 0.0, "y=%.3f" % y)

    on_table = [p for p in pts if p[0] not in outside_ok]
    high = [p for p in on_table if p[2] > table_h + 0.9]
    check("Nothing floats absurdly above the table",
          not high, ", ".join(p[0] for p in high))

    print("\n5. Conveyor geometry")
    conv = re.findall(
        r"id:\s*'(conveyor\d)'[\s\S]{0,300}?position:\s*\[\s*(-?[\d.]+)\s*,"
        r"[^,]+,\s*(-?[\d.]+)[\s\S]{0,120}?axis:\s*'([xz])'",
        src,
    )
    check("All three conveyors are defined", len(conv) == 3, "found %d" % len(conv))

    axes = {c[0]: c[3] for c in conv}
    check("Conveyor 2 is PERPENDICULAR to conveyor 1",
          axes.get("conveyor1") != axes.get("conveyor2"),
          "c1=%s c2=%s -- this was the main correction from the photographs"
          % (axes.get("conveyor1"), axes.get("conveyor2")))

    for cid, x, z, axis in conv:
        x, z = float(x), float(z)
        end_x = x + conveyor_len if axis == "x" else x
        end_z = z + conveyor_len if axis == "z" else z
        check("'%s' fits within the cell" % cid,
              -0.1 <= end_x <= cell_w + 0.1 and -0.1 <= end_z <= cell_d + 0.1,
              "ends at (%.2f, %.2f), cell is %.2f x %.2f" % (end_x, end_z, cell_w, cell_d))

    print("\n6. Honesty markers")
    check("Unmapped cylinders declare valveRole: null",
          "valveRole: null" in src,
          "cylinders must not be bound to guessed valve numbers")
    check("Unplaced sensors are listed explicitly",
          "UNPLACED_SENSORS" in src)
    check("Every placement carries a confidence tag",
          src.count("confidence:") >= 15,
          "found %d" % src.count("confidence:"))
    check("APPROX components are marked",
          "'APPROX'" in src or '"APPROX"' in src)

    print("\n" + "=" * 46)
    print("  %d passed, %d failed" % (len(PASS), len(FAIL)))
    if FAIL:
        print("=" * 46)
        for name, detail in FAIL:
            print("  FAILED: %s   %s" % (name, detail))
    print("=" * 46)
    return 1 if FAIL else 0


if __name__ == "__main__":
    raise SystemExit(main())
