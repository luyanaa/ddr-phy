# Chip-top routing specification (verified facts + architecture)

## Verified geometric facts (probe-measured, do NOT re-derive)
1. Cavity (x/y 210.16..1589.84) is 100% empty of ring metal on ALL layers.
2. Ring power metal hugs die edge + bond pads; cavity-facing entry zone is CLEAR on M4/M5.
3. Core M5 negligible (8um2). Core M4 power straps are INSIDE core bbox only.
4. Core bbox die coords: x 763.26..1037.30, y 754.02..1045.98. NEVER route inside it.
5. Core pin edges: E=25 pins (most cmd_o, dq_o[0,3,4,7], dq_oe, ck_o) at x=1036.74 M3;
   W=6 (dq_i[1,2,3,5,6,7]) x=763.26 M3; N=5 (dq_o[1,2,5,6], dq_i[0]) y=1045.7 M2;
   S=3 (cmd_o[11,12], dq_i[4]) y=754.3 M2.

## Pad assignment (site -> net, side)
B(1-7): cmd_o[11,12,13],ck_o,cmd_o[14,15,16]
R(9-15): dq[0..6]  (each dq[i] is 3 wires: dq_o[i]->OUT, dq_i[i]->IN, dq_oe_b->OE_N)
T(16-24): dq[7],cmd_o[20,19,18,17,10,9,8,7]
L(25-31): cmd_o[6,5,4,3,2,1,0]
Pad OUT pin die pos: bottom pads x=74.5+190*(site-1)+190... actually x=140+190*site-65.5, y=145.5.
   Left/right pads share x or y coordinates -> vertical/horizontal trunks COLLIDE if same coord.

## Pad pin die positions (bottom example, y=145.5): x = 140+190*index - 65.5 for bottom.
   Left pads (R270 at x=90): OUT pins at x~90-155, distinct y per pad.
   KEY: pads on the SAME side share one coordinate. Bottom/top share nothing (distinct x).
   Left/right share x-band. So a vertical trunk at x=pad_x is fine for bottom/top but
   all LEFT pads have nearly the same x -> their vertical trunks overlap.

## Routing architecture that avoids collisions
- Horizontal segments on Metal4, vertical on Metal5. M4-horizontal crossing M5-vertical
  is layer-safe. Same-layer overlap is the ONLY hard failure.
- Each net needs: unique x for every vertical M5 trunk, unique y for every horizontal M4 trunk.
- Since most core pins are EAST but pads are on all sides, nets must route around the core
  through the cavity channels (E channel x1039-1589, but also N/S/W channels).
- The correct structure per net: pad entry -> cavity channel -> approach core edge perpendicular.
  Vertical trunks for nets on the same side MUST be at distinct x (use per-net channel offset).
  Horizontal trunks at distinct y (core pin y is often unique already, or offset).

## dq_oe inverter (physical, in cavity east of core)
- inv_2 at INVERTER_X=CORE_X+CORE_W+5, INVERTER_Y. Pins A(in) Y(out) VDD VSS VNW VPW.
- n_dq_oe: core dq_oe(E edge) -> inverter A. 1 wire.
- n_dq_oe_b: inverter Y -> 8x pad OE_N (dq[0..7]). Fanout, 8 wires, all same net n_dq_oe_b.
- core VDD->inv VDD+VNW, core VSS->inv VSS+VPW.

## Power
- VDDIO ring mesh on M3 at perimeter, VSSIO on M4. Connect to each tile's rail pins.
- core VDD/VSS labels on M4.

## Checker is the arbiter: generator/check_chip_top.py. Goal 0 FAIL.


## STATUS UPDATE (verified this session)
- Checker failures reduced 703 -> 27.  Connectivity is CORRECT (multi-layer
  graph check reports 0 failures: every net reaches both terminals).
- Fixed bugs: abstract core regenerated to 117 pins (was 43); signoff LVS
  deep-mode; pad-opening labels moved to tile-local (0,0) where M2 exists;
  inverter instance reuse (was creating `$1` duplicate); checker false-positive
  single-layer-M5 continuity check removed (2-layer routing is correct);
  net labels added to all nets incl. power/inverter.

## REMAINING 27 FAILURES - precise diagnosis
The core unresolved problem is GLOBAL routing congestion.  Root cause:
  * dq input pins dq_i[1,2,3,5,6,7] are on the core WEST face (x=763.26)
    but their pads dq[1..7] are on the RIGHT/TOP sides.  Routes must travel
    right->west across the whole die, and straight-line channels pass through
    the core interior (x763-1037, y754-1046) or congest shared channels.
  * core power pins VDD/VSS are at local x23/26 (west interior, die x786/789)
    but the inverter is EAST of the core (x1042).  Power routes cross the core.
  * The cavity channels are shared by all 39 nets; iterative channel patching
    oscillates because every lane is congested.
CONCLUSION: the remaining routing needs a proper obstacle-aware maze router
(grid A* over the cavity avoiding imported metal + already-routed nets), not
channel patching.  Obstruction model `_build_obstructions` already exists.
Verified-correct infrastructure (abstract, signoff, fill, lvs-view) is intact.
