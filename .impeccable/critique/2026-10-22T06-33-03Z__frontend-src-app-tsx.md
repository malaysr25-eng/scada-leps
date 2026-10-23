---
target: the dashboard
total_score: 24
max_score: 40
na_heuristics: 
p0_count: 2
p1_count: 2
target_identity: "file:C:\\Users\\ADMIN\\Desktop\\smcc\\new_scada (3)\\new_scada\\scada_platform\\frontend\\src\\App.tsx"
target_fingerprint: "sha256:7c606fcf153a19692671f5669660c59b8aafeb35a025bd866014c935f321f058"
target_path: "C:\\Users\\ADMIN\\Desktop\\smcc\\new_scada (3)\\new_scada\\scada_platform\\frontend\\src\\App.tsx"
timestamp: 2026-10-22T06-33-03Z
slug: frontend-src-app-tsx
---
# Critique: Cell Control dashboard (frontend/src/App.tsx), simulated instance

Method: dual-agent (A: design review · B: detector --cdp + headless measurements)

## Heuristics: 24/40 (Acceptable)
1 Status 2 · 2 Real world 3 · 3 Control 2 · 4 Consistency 2 · 5 Error prevention 3 · 6 Recognition 3 · 7 Efficiency 2 · 8 Minimalism 2 · 9 Recovery 3 · 10 Help 2

## Priority issues
- [P0] Simulated runs report as real hardware. Data page SourcePanel shows "Siemens S7-1200 · IN CONTROL · CONNECTED · GOOD", and /api/sources reports mode PLC_CONNECTED with simulated:true. The top-bar Twin chip says CONNECTED while every prediction is "--". Fix: give SourcePanel and the badge the same simulated override as ModeBanner; make the Twin chip say "reference loaded / no prediction". (harden)
- [P0] Write-capable cellchat is presented as help. The floating "Assistant" dock on every page (App.tsx:98-121) opens AssistantChat; compact mode hides the "every write needs your yes" line; the read-only help assistant has no entry point. Fix: point the dock at the read-only help assistant labelled "Help"; rename cellchat "Cell Agent (can write)" with a persistent warning badge; move it below the operating pages in the nav. (clarify)
- [P1] Critical state is not readable from across a room. Mode pills are 12px, lifecycle and E-Stop 14px. Three stacked bands use about 30% of a 720–768px viewport. Overview has 36 texts at 10px; Tags has 679 texts at 9–10px. Fix: merge the safety strip and mode banner; add a 20–24px state block; make the disclaimer a tooltip; offer a projector density option. (adapt, typeset)
- [P1] Colour semantics collide. Violet means simulated, twin, Maint, latching and ASM; red means fault, PROTECTED and an idle 0 order; PENDING and WRITTEN are both amber; the SIMULATED chip is blue while the banner is violet. Fix: reserve state hues for state only; show taxonomy as neutral chips; use one simulated token everywhere. (colorize)
- [P2] Flat, repetitive navigation. 11 ungrouped rail items; three twin-like views scattered; the cell plan appears on 3 pages; "Factory" is really the 2-D cell plan. Fix: group as Operate / Model / Records / Assist. (layout)

## Measured evidence
- SOFTWARE STOP label contrast is 3.32:1 ("STOP") and 4.47:1 ("SOFTWARE") on every page.
- ManualControl.tsx:353 labels (opacity-70) are 3.2:1, 26 instances.
- Targets under 24px: Diagnostics unpin buttons (20px), Tags pin buttons (21px).
- No h1 on any page; no aria-live for faults or lifecycle; Lamp aria-label sits on a span with no role (Primitives.tsx:136).
- 7 inputs use focus: rather than focus-visible; mode pills and QtyInput have no visible focus style.
- Console: CORS errors polling :5052/api/status when cellchat is absent.
- Overflow: none at 1366 or 1920.
- Likely false positives: disabled-control contrast, canvas hex palettes, the SIMULATED stripe gradient.

## Strengths
Unknown is a first-class state (dashed/hollow lamps, ✓✕?). Safety is stated (SOFTWARE STOP vs read-only HW E-Stop). Honest write lifecycle with refusal reasons.

## Persona flags
- Alex: no shortcuts; 13 coil cards with no filter.
- Sam: no live regions; small targets.
- Projector operator: can't read mode or step from 3 m; Restart checklist moves when a fault fires (Overview.tsx:399/435).

## Questions
Should the cell plan be the Overview? Should Stop end in a persistent confirmed state rather than a toast? Should the write-capable agent be one click from every page?
