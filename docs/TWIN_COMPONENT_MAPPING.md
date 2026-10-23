# DIGITAL TWIN — REAL MACHINE vs DIGITAL COMPONENT MAPPING

Required by Part 14: compare the existing model against the reference
photographs *before* changing anything, and record what has to change.

---

## 1. What the existing twin actually is

**Finding: there was no 3-D model.** The brief refers to "the existing 3D
digital-twin representation", but the visualisation in the codebase is a
hand-authored **2-D SVG schematic**
(`frontend/src/components/digitalTwin/FactorySchematic.tsx`, 1000 × 460 user
units) with placements in `layout.ts`.

It is topological, not dimensioned. It was built to answer "which sensor just
fired?", and it does that well. It was never intended to resemble the machine.

So this is not a correction of an inaccurate 3-D model — it is the addition of
one. The 2-D schematic **stays**, because it remains the better view for sensor
diagnostics, and because removing a working diagnostic tool to gain a prettier
one would be a bad trade.

---

## 2. What the photographs establish

Ten photographs from six viewpoints. Read together they settle the layout;
individually several are ambiguous.

### Confirmed by two or more views

| Observation | Views |
|---|---|
| Roughly **T-shaped** cell on a rectangular extrusion table | top-down ×2, overview ×2 |
| **Three blue belt conveyors**, two roughly parallel, one perpendicular | all overviews |
| **Transparent acrylic magazine** with vertical compartments and a tan plywood top cover, elevated at one end | top-down ×2, ×3 close, ×2 overview |
| **Wooden blocks** stored in the magazine compartments | close ×2, overview ×2 |
| **Row of ~5 pneumatic cylinders** along one edge, aimed at the magazine | close ×1, overview ×2, top-down ×1 |
| **Red/orange tinted acrylic enclosure** (laser engraver, DAJA) elevated on a platform, mid-cell | all except the cabinet view |
| **Cream/beige junction and motor boxes** distributed along the machine | all |
| **Blue polyurethane pneumatic tubing** routed throughout | all |
| **Silver aluminium extrusion** frame and legs | all |
| **Navy/dark-blue base panels** under the conveyor runs | top-down ×2, overview ×2 |
| **Blue plastic crate** as the output bin, containing a wooden block | overview ×3 |
| **Cream electrical cabinet** with a large transparent window, separate, on a black rolling base | cabinet view, overview ×1 |
| **Siemens S7-1200 + power supply + rows of terminal blocks** inside the cabinet | cabinet view |
| **Horizontal cylindrical air receiver** at the base near the cabinet | cabinet view, side view |
| **Red mushroom E-stop** | overview ×2 |
| **Green + orange pushbuttons** on the conveyor motor boxes | overview ×2 |
| **Valve manifold bank** with multiple solenoid bodies | side view ×1 |
| Monitor and keyboard on an adjacent desk | overview ×2 |

### Deliberately NOT inferred

| Unknown | Why it cannot be settled from photographs |
|---|---|
| Absolute dimensions | No scale reference in any frame. The lab data sheet gives conveyor length 76 cm, which is used; everything else is proportioned relative to that. |
| Exact cylinder bore/stroke | Not legible. Drawn to plausible proportion. |
| Which valve drives which cylinder | Not visible, and recorded in no supplied document. |
| Tubing routing behind panels | Occluded. Only visible runs are drawn. |
| Cabinet internals beyond the visible front | Only the front face is glazed. |
| Sensor mounting positions | Not identifiable in any view. Only PX1–PX4 are placed, from the Sequencing sheet. |

Every approximated item is tagged `APPROX` in the component table and shows a
"geometry approximated" note in the UI inspector.

---

## 3. Component mapping table

`Confidence`:
**PHOTO** — geometry read directly from the photographs ·
**PROP** — proportioned relative to a confirmed dimension ·
**APPROX** — plausible geometry, exact form unknown ·
**DOC** — placement from the Sequencing sheet, not from a photograph

| # | Real physical component | Existing 2-D component | New 3-D component | Live state binding | Confidence |
|---|---|---|---|---|---|
| 1 | Aluminium extrusion frame + legs | *absent* | `<Frame/>` | none (static) | PHOTO |
| 2 | Navy base panels | *absent* | `<BasePanels/>` | none | PHOTO |
| 3 | Magazine enclosure, transparent, 5 compartments, plywood top | grey rect “Magazines (camera)” | `<Magazine/>` | `inventory.magazines[].cameraCount` → block count per compartment; `plcEmpty` → red edge | PHOTO |
| 4 | Wooden blocks in magazine | number in a box | `<Workpiece/>` instances | camera count | PHOTO |
| 5 | Feed pusher cylinders (×5) | *absent* | `<PneumaticCylinder/>` ×5 | `valve.N.state` → rod extension **where the mapping is known; unmapped ones stay idle and say so** | PHOTO / APPROX |
| 6 | Conveyor 1 (blue belt + cream motor box) | flat grey rect | `<Conveyor index={1}/>` | `conveyor.1.running` + `velocity_fb` → belt scroll | PHOTO |
| 7 | Conveyor 2 (perpendicular) | drawn **parallel** — wrong | `<Conveyor index={2}/>` rotated 90° | `conveyor.2.*` | PHOTO |
| 8 | Conveyor 3 | flat rect | `<Conveyor index={3}/>` | `conveyor.3.*` | PHOTO |
| 9 | Laser engraver enclosure (red/orange tinted, elevated) | plain box “Engraving station” | `<LaserEnclosure/>` + `<EngravingGantry/>` | `sensor.pgm_up_limit` / `pgm_low_limit` → platform height; `cmd.engraving_completed` → beam | PHOTO |
| 10 | Engraving platform lift | *absent* | `<EngravingPlatform/>` | both limit switches; **IN TRANSIT when neither is made** | PHOTO |
| 11 | Output bin (blue crate) | rect “Output bin” | `<OutputBin/>` | completed token count | PHOTO |
| 12 | Electrical cabinet + window + DIN gear | *absent* | `<ElectricalCabinet/>` | `connection.plc` → PLC status LED | PHOTO |
| 13 | Air receiver tank | *absent* | `<AirReceiver/>` | `pressure.value` → gauge needle | PHOTO |
| 14 | Valve manifold bank | abstract 13-tile tray | `<ValveManifold/>` | `valve.N.state` ×13 → indicator per body | PHOTO / APPROX |
| 15 | Blue pneumatic tubing | *absent* | `<PneumaticTube/>` splines | none (static) | PHOTO / APPROX |
| 16 | E-stop mushroom button | *absent* | `<EStop/>` | `safety.emergencyActive` → depressed + red glow | PHOTO |
| 17 | Motor-box pushbuttons (green/orange) | *absent* | part of `<Conveyor/>` | `conveyor.N.running` → green lamp | PHOTO |
| 18 | Proximity sensors PX1–PX4 | dots on the 2-D belt | `<ProximitySensor/>` ×4 | `sensor.proximity.1..4` → lamp | DOC |
| 19 | Proximity sensors PX5–PX10 | “unplaced” tray | **not placed in 3-D** — listed in the inspector as unplaced | `sensor.proximity.5..10` | *no source* |
| 20 | Transfer/station pushers | *absent* | `<PneumaticCylinder/>` ×4 at stations | unmapped valves | APPROX |
| 21 | Operator desk, monitor, keyboard | *absent* | `<Desk/>` | none | PHOTO |

---

## 4. Discrepancies the photographs corrected

Things the existing 2-D layout got **wrong**, now fixed in 3-D:

1. **Conveyor 2 orientation.** The schematic draws conveyors 1 and 2 parallel
   and horizontally offset. The photographs show conveyor 2 running
   **perpendicular** to conveyor 1 — this is what makes the cell T-shaped
   rather than a straight line.
2. **The magazine is elevated and angled**, feeding downward. The schematic
   drew it as a flat side-by-side block.
3. **The engraving station is raised on its own platform**, above belt height,
   with the tinted enclosure sitting on top. The schematic drew it inline at
   belt level.
4. **The feed pushers are a dense row of five**, not a single "feeder" box.
5. **The electrical cabinet is a major physical object** roughly a third the
   height of the whole cell, and was entirely absent.
6. **Conveyor 3 is offset and lower**, not collinear with conveyor 1.

---

## 5. What still needs input

| Need | Blocks | How to supply |
|---|---|---|
| **Actuator-to-valve map** | Cylinders 5, 20 cannot animate from live state | 30 min at the machine: energise one valve in Manual mode, note which cylinder moves, record in `machineLayout.ts` |
| **Cylinder bore / stroke** | Rod travel is proportioned, not dimensioned | Part number stamped on the cylinder body |
| **Sensor mounting positions for PX5–PX10** | They stay unplaced | A photograph of each sensor in situ |
| **Overall cell dimensions** | Everything is proportioned off the 76 cm conveyor length | One tape measurement of the table |
| **Cabinet position relative to the cell** | Placed from one view only | A photograph showing cabinet and cell together from above |
| **Reed switches** | No cylinder can show *confirmed* extension, only commanded | Hardware addition + PLC tags |

---

## 6. Implementation constraints honoured

- The 2-D schematic is untouched and still routed at `/factory`.
- The 3-D scene reads the **same zustand store** and the **same semantic roles**.
  No new tag mapping was invented for it.
- A component with no live binding renders in a neutral state and says
  "no live binding" in the inspector, rather than animating on invented data.
- Every `APPROX` component carries that flag through to the UI.
