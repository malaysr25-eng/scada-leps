# BITS Pilani WILP — NX Mechatronics Concept Designer (MCD) Master Reference & Learning Guide
**Version**: 3.0 (Comprehensive Master Reference for Claude Code & Student Learning)  
**Target Platform**: Siemens NX MCD & S7-1200/1500 PLC Virtual Commissioning  
**Physics Reference**: Validated MATLAB Physics Model (Physics of Record)  
**Primary Project Assembly**: `Engraving/Engraving_Process_07-01-26_Additional.prt` (Save As: `Engraving_Process_2026-09-21_build.prt`)  
**Target PLC OPC UA Endpoint**: `opc.tcp://192.168.0.102`

---

## 1. Executive Summary & System Overview
The BITS Pilani WILP Mechatronics Concept Designer (MCD) digital twin models an automated manufacturing and laser engraving cell. Workpieces (100 x 100 x 40 mm blocks weighing 0.300 kg) are stored in multi-magazine feeders, pushed onto Belt 1, transferred to Belt 2, positioned for laser engraving on a 50 mm vertical lift platform, transferred to Belt 3, and ejected into an outfeed storage bin. A second product flow allows blocks to bypass engraving directly via SV11.

While the **MATLAB model serves as the physics of record**, NX MCD provides 3D kinematic motion, collision handling, visual validation, and virtual commissioning capabilities over OPC UA.

---

## 2. Quantitative System Specifications

### 2.1 Workpiece Dynamics
- **Dimensions**: 100 x 100 x 40 mm
- **Mass**: 0.300 kg (300 g)
- **Physics**: Rigid Body with standard collision surfaces against conveyor belts and pneumatic stops.

### 2.2 Conveyor Belts & Speed Discrepancies
- **Belt 1 (Magazine Feed)**:
  - *Centerline*: y = 918 mm
  - *Measured Speed*: **210 mm/s** (derived from 4 empirical PLC cycle recordings)
  - *Discrepancy Note*: The physical PLC setpoint and initial MCD CAD author used 180 mm/s. Type 210 mm/s in MCD for accurate physics timing.
- **Belt 2 (Engraving Transfer)**:
  - *Centerline*: x = 792 mm
  - *Measured Speed*: **310 mm/s** (measured via physical tape timing during manual run)
- **Belt 3 (Outfeed Transport)**:
  - *Centerline*: y = 387 mm
  - *Estimated Speed*: **150 mm/s** (engineering assumption, unmeasured)

### 2.3 Engraving Platform
- **Motion Axis**: Vertical Sliding Joint along +z axis.
- **Stroke / Travel**: 50 mm total travel (physically measured at ~45 mm).
- **Rise Duration**: 7.63 s (~6.55 mm/s)
- **Lower Duration**: 8.01 s (~6.24 mm/s)

---

## 3. Hardware Inventory: Actuators & Sensors

### 3.1 Actuator Inventory (11 Pneumatic Cylinders + Platform)
All cylinder rods operate as sliding joints in MCD with defined stroke limiters, travel targets, and model pneumatic speeds:

| Actuator ID | Description | PLC Coil / Solenoid | Motion Axis | Stroke (mm) | Travel (mm) | Speed (mm/s) | Coordinate Reference | Valve Type |
| :--- | :--- | :--- | :---: | :---: | :---: | :---: | :--- | :--- |
| **MAG1_PUSH** | Magazine 1 Dispense | `Solenoid_valve1` | -y | 160 | 82 | 148 | x = 160 mm | Single Solenoid |
| **MAG2_PUSH** | Magazine 2 Dispense | `Solenoid_valve2` | -y | 160 | 82 | 148 | x = 270 mm | Single Solenoid |
| **MAG3_PUSH** | Magazine 3 Dispense | `Solenoid_valve3` | -y | 160 | 82 | 148 | x = 380 mm | Single Solenoid |
| **MAG4_PUSH** | Magazine 4 Dispense | `Solenoid_valve4` | -y | 160 | 82 | 148 | x = 490 mm | Single Solenoid |
| **MAG5_PUSH** | Magazine 5 Dispense | `Solenoid_valve5` | -y | 160 | 82 | 148 | x = 600 mm | Single Solenoid |
| **XFER_CV1_CV2** | Transfer Belt 1 -> Belt 2 | `Solenoid_valve6` | -y | 160 | 108 | 131 | x = 792 mm | Single Solenoid |
| **CYL_A** | Extend into Engraver | `Solenoid_valve7` (out)<br>`Solenoid_valve8` (back) | +x | 300 | 252 | 78 | y = 590 mm | **Double-Solenoid Latching** |
| **CYL_B** | Engraver -> Belt 3 | `Solenoid_valve9` (out)<br>`Solenoid_valve10` (back) | -y | 300 | 204 | 97 | x = 1045 mm | **Double-Solenoid Latching** |
| **MOVE_TO_CV3** | Bypass Push to Belt 3 | `Solenoid_valve11` | +x | 160 | 118 | 146 | y = 387 mm | Single Solenoid |
| **OUTFEED_A** | Eject to Outfeed Bin | `Solenoid_valve12` | -y | 160 | 150 | 135 | x = 1290 mm | Single Solenoid |
| **OUTFEED_B** | Secondary Outfeed | `Solenoid_valve13` | -y | 160 | 150 | 135 | x = 1410 mm | Single Solenoid |

*Important Latching Valve Note*: `CYL_A` (`SV7`/`SV8`) and `CYL_B` (`SV9`/`SV10`) are driven by double-solenoid 5/2 latching valves without spring returns. In MCD, each cylinder is modeled as **one** sliding joint where `Solenoid_valve7`/`Solenoid_valve9` set target to extended travel, and `Solenoid_valve8`/`Solenoid_valve10` set target to 0 mm.

### 3.2 Proximity Sensor Inventory (10 Collision Sensors)
All sensors are modeled in MCD as collision sensors with a **30 mm sensing range**:

| Sensor Tag Name | X Coord (mm) | Y Coord (mm) | Monitored Station / Action |
| :--- | :---: | :---: | :--- |
| `Proximity_sensor1` | 160 | 918 | Magazine 1 Dispense Detection |
| `Proximity_sensor2` | 270 | 918 | Magazine 2 Dispense Detection |
| `Proximity_sensor3` | 380 | 918 | Magazine 3 Dispense Detection |
| `Proximity_sensor4` | 490 | 918 | Magazine 4 Dispense Detection |
| `Proximity_sensor5` | 600 | 918 | Magazine 5 Dispense Detection |
| `Proximity_sensor6` | 792 | 918 | End of Belt 1 / Transfer Trigger |
| `Proximity_sensor7` | 792 | 590 | Belt 2 Engraving Stop Station |
| `Proximity_sensor8` | 792 | 387 | Belt 2 Bypass Stop Station |
| `Proximity_sensor9` | 1290 | 387 | Belt 3 Outfeed A Ejection Trigger |
| `Proximity_sensor10` | 1410 | 387 | Belt 3 Outfeed B Ejection Trigger |

---

## 4. Key Spatial Waypoints & Centerlines
- **Origin**: Magazine end (x=0, y=0).
- **Waypoints Vector (x, y)**:
  - Load Position: (160, 1000)
  - Belt 1 End: (792, 918)
  - Belt 2 Stop: (792, 590)
  - Engraver Center: (1045, 590)
  - Belt 3 Load Point: (1045, 387)
  - Outfeed Position: (1290, 387)
  - Storage Bin: (1290, 237)

---

## 5. Sequence & Cycle Timings

### 5.1 Engraved Route Cycle Sequence (Total Duration: 75.64 s)
| Elapsed Time t (s) | Event / Operational Step | Actuators / Signals Modified |
| :---: | :--- | :--- |
| **0.00** | Block camera detection triggered | Block present at magazine load |
| **10.24** | SV1 magazine pusher extends (PLC start delay `T#10S`) | `Solenoid_valve1` = HIGH |
| **13.29** | Belt 1 conveyor starts | `Conveyor1` = HIGH (210 mm/s) |
| **16.44** | `Proximity_sensor6` tripped; Belt 1 stops | `Conveyor1` = LOW, `Proximity_sensor6` = HIGH |
| **18.58** | SV6 transfer pusher extends; Belt 2 starts | `Solenoid_valve6` = HIGH, `Conveyor2` = HIGH |
| **20.02** | `Proximity_sensor7` tripped; Belt 2 stops | `Conveyor2` = LOW, `Proximity_sensor7` = HIGH |
| **21.50** | SV7 extends Cylinder A into engraver | `Solenoid_valve7` = HIGH |
| **29.56** | SV8 retracts Cylinder A | `Solenoid_valve8` = HIGH |
| **31.51** | Engraving platform begins rising (+z) | Platform motor active (~6.55 mm/s) |
| **39.15** | Platform reaches top (50 mm) | Upper limit switch active |
| **39.15–51.67** | Laser engraving performed (12.5 s operator window) | `Engraving_Completed` issued at 51.67 s |
| **51.67** | Platform lowers (-z) | Platform motor lowering |
| **59.69** | Platform reaches bottom (0 mm) | Lower limit switch active |
| **59.87** | SV9 extends Cylinder B to Belt 3 | `Solenoid_valve9` = HIGH |
| **68.07** | SV10 retracts Cylinder B; Belt 3 starts | `Solenoid_valve10` = HIGH, `Conveyor3` = HIGH |
| **69.72** | `Proximity_sensor9` tripped; Belt 3 stops | `Conveyor3` = LOW, `Proximity_sensor9` = HIGH |
| **69.85** | SV12 Outfeed A ejects block to bin (`T#5S` hold) | `Solenoid_valve12` = HIGH |
| **75.64** | Cycle complete; all signals reset | Full cycle complete |

### 5.2 Bypass Route Cycle Sequence (Total Duration: 29.74 s)
1. Belt 2 carries workpiece past `Proximity_sensor7` down to `Proximity_sensor8` (1.97 s).
2. `Solenoid_valve11` extends to push block straight across to Belt 3 (held for 2.00 s).
3. Belt 3 transports block to `Proximity_sensor9`.
4. `Solenoid_valve12` ejects block to outfeed bin.

---

## 6. One-Month Student Learning Plan & Weekly Roadmap

### Week 1: Basic Physics & Geometry Setup
- **Goal**: Verify licensing and build rigid body physics and transport surfaces.
- **Tasks**:
  1. Open NX -> Help -> About NX -> Application tab -> Check **Mechatronics Concept Designer** license.
  2. Open `Engraving/Engraving_Process_07-01-26_Additional.prt`; Save As `Engraving_Process_2026-09-21_build.prt`.
  3. Define workpiece (100x100x40 mm, 0.300 kg) as Rigid Body.
  4. Create Collision Bodies on workpiece, conveyor bed tops, and physical stops.
  5. Add Transport Surfaces on Belt 1 (210 mm/s), Belt 2 (310 mm/s), and Belt 3 (150 mm/s).
- **Verification**: Press Play — workpiece must drop due to gravity, land on Belt 1, and travel smoothly.

### Week 2: Kinematics & Motion Controls
- **Goal**: Model all 11 pneumatic cylinders and vertical engraving platform.
- **Tasks**:
  1. Create 11 Sliding Joints for cylinder rods and 1 vertical joint (+z) for the platform.
  2. Configure Position Controls: set stroke limits, travel targets, and model pneumatic speeds from Section 3.1.
  3. Define 10 Collision Sensors (Collision Sensors, 30 mm sensing range) at exact coordinates from Section 3.2.
- **Verification**: Drag joints manually in Physics Navigator to confirm correct stroke limits and collision sensor trip states.

### Week 3: Automation Signals & Sequence Editor
- **Goal**: Establish signal mapping and internal sequence logic.
- **Tasks**:
  1. Create 27 MCD signals named exactly after PLC tags (`Solenoid_valve1..13`, `Conveyor1..3`, `Proximity_sensor1..10`, `Engraving_Completed`).
  2. Build Signal Adapters mapping collision sensors to output signals, and input signals to Position Control targets.
  3. Construct offline sequence in Sequence Editor following Section 5 timeline.
- **Verification**: Run Sequence Editor offline — verify the full 75.64 s Engraved cycle and 29.74 s Bypass cycle without external PLC.

### Week 4: OPC UA Virtual Commissioning & Viva Preparation
- **Goal**: Establish live OPC UA communications and prepare defense presentation.
- **Tasks**:
  1. Launch `mcd_opc_ua_mock_server.py` locally to test OPC UA signal streaming against MCD client.
  2. Connect MCD OPC UA client to live PLC at `opc.tcp://192.168.0.102`.
  3. Capture high-definition screen recordings of the digital twin in full motion.
  4. Prepare Viva Voce questions and answers covering speed discrepancies, double-solenoid latching logic, and OPC UA signal mapping.

---

## 7. Lecture Recordings & Resource Catalog

### 7.1 SharePoint Lecture Recordings (BITS Pilani WILP)
The source material references 6 Microsoft SharePoint Stream lecture recordings hosted by Prof. Vasu (`vasu_wilp_bits-pilani_ac_in`).
*Note on Transcripts*: The source repository contains direct video stream URLs to all 6 recordings. Full verbatim written text transcripts are not embedded in the sources, but the links below provide direct video access:

1. **Lecture Recording 1**: [SharePoint Stream Link 1](https://wilpbitspilaniacin0-my.sharepoint.com/:v:/g/personal/vasu_wilp_bits-pilani_ac_in/IQA_7Nv9iCCoSY73X_4G9PBSAVgSStT0B77KNfs4MhFDr9o?e=HSWrx0)
2. **Lecture Recording 2**: [SharePoint Stream Link 2](https://wilpbitspilaniacin0-my.sharepoint.com/:v:/g/personal/vasu_wilp_bits-pilani_ac_in/IQBBNko2_ZfLR7zu7YE1hhBJAS70BPaoyqXRCGAA11565hU)
3. **Lecture Recording 3**: [SharePoint Stream Link 3](https://wilpbitspilaniacin0-my.sharepoint.com/:v:/g/personal/vasu_wilp_bits-pilani_ac_in/IQA_7Nv9iCCoSY73X_4G9PBSAVgSStT0B77KNfs4MhFDr9o?e=3OOkE6)
4. **Lecture Recording 4**: [SharePoint Stream Link 4](https://wilpbitspilaniacin0-my.sharepoint.com/:v:/g/personal/vasu_wilp_bits-pilani_ac_in/IQCb0p8l4HcJSrUq_JoEhdL0AWMf_QjQA7RfQd201jQ4hb0?e=Ubrbwf)
5. **Lecture Recording 5**: [SharePoint Stream Link 5](https://wilpbitspilaniacin0-my.sharepoint.com/:v:/g/personal/vasu_wilp_bits-pilani_ac_in/IQCT-lW6DyXbR6rrE4Oad7LuAbkZKT20nGqf01Et2gPynMU?e=xt9hac)
6. **Lecture Recording 6**: [SharePoint Stream Link 6](https://wilpbitspilaniacin0-my.sharepoint.com/:v:/g/personal/vasu_wilp_bits-pilani_ac_in/IQCT-lW6DyXbR6rrE4Oad7LuAbkZKT20nGqf01Et2gPynMU?e=xt9hac)

### 7.2 Siemens SCE Learning Packages
- **Basic Course: TIA Factory Automation with SIMIT & NX MCD**:
  - *URL*: `https://support.industry.siemens.com/cs/document/109816550/?lc=en-ww`
  - *Package*: `https://support.industry.siemens.com/cs/attachments/109816550/lp-sce-fa-basic-course-simit-mcd-lm-17-en.zip`
- **Advanced Course: Digital Twin Virtual Commissioning**:
  - *URL*: `https://support.industry.siemens.com/cs/document/109816686/?lc=en-WW`
- **SCE Catalogue & PDF Guide**:
  - Catalogue Page: `https://www.siemens.com/global/en/company/sustainability/education/sce/learning-training-documents/digital-twin.html`
  - Full PDF Guide (3.8 MB): `https://assets.new.siemens.com/siemens/assets/api/uuid:c718963e-8c5a-4eab-8aa5-43e0a505af32/sce-guide-learn-training-guide-en.pdf`
- *Access Note*: Siemens Industry Online Support returns HTTP 403 to automated scripts due to Cloudflare. Open links directly in a web browser using a free Siemens account ID. Note that legacy links (`sce-150-00x` and FH Aachen) are permanently 404 dead.

### 7.3 Curated Video Tutorials (YouTube)
1. **Basic Physics (Rigid Body, Collision, Transport Surface)**: `https://www.youtube.com/watch?v=KIx1exS6arw`
2. **Joints & Kinematics**: `https://www.youtube.com/watch?v=UeqBTeIFAoM`
3. **Signals & Connections**: `https://www.youtube.com/watch?v=cv2Yjcx4lEk`
4. **Complete Pick & Place Conveyor Cell**: `https://www.youtube.com/watch?v=x3ncDZdelRY`
5. **Siemens MCD Tips Blog**: `https://blogs.sw.siemens.com/nx-design/nx-tips-and-tricks-mechatronics-concept-designer/`

### 7.4 Academic Reference Paper
- **Title**: "Digital Twin of sorting cell in NX MCD"
- **Journal**: EDP Sciences Manufacturing Review (2024)
- **URL**: `https://mfr.edp-open.org/articles/mfreview/full_html/2024/01/mfreview240009/mfreview240009.html`

---

## 8. Claude Code Integration & Prompting Guide

When feeding these files into Claude Code, use the following operational commands:

1. **To Generate Siemens TIA Portal SCL Logic**:
   `"Using mcd_cell_config_v3.json, write a Siemens TIA Portal SCL function block that controls double-solenoid valves CYL_A (SV7/SV8) and CYL_B (SV9/SV10) with latching logic and conveyor interlocks."`

2. **To Test OPC UA Communication**:
   `"Execute mcd_opc_ua_mock_server.py and verify that all 27 tags transition correctly during the 75.64 s engraved cycle."`

3. **To Create PLC Unit Tests**:
   `"Write a Python unittest suite using asyncua that connects to mcd_opc_ua_mock_server.py and asserts that Proximity_sensor7 triggers Conveyor2 shutdown within 100 ms."`
