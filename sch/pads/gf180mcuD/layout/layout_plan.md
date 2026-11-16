# gf180mcuD layout plan (GENERATED)

Mode: **symbolic**. drc_clean: **false**. NOT A TAPEOUT LAYOUT.

## Composite constraint status

| constraint | class | severity | status | upstream inputs |
|---|---|---|---|---|
| cell_width_fits_pitch | geometry | blocking | unresolved | GUARD_RING_SPACING, M_DEVICE, NF_N_OUT, NF_P_OUT |
| cell_height_fits_open | geometry | blocking | unresolved | ESD_AREA_DN, ESD_AREA_UP, GUARD_RING_WIDTH, L_N_OUT |
| driver_width_drc | drc | blocking | unresolved | DRC_MIN_WIDTH, M_DEVICE, NF_N_OUT, NF_P_OUT |
| esd_up_area | esd | blocking | unresolved | ESD_AREA_MIN, ESD_AREA_UP |
| esd_dn_area | esd | blocking | unresolved | ESD_AREA_DN, ESD_AREA_MIN |
| latchup_spacing | latch_up | blocking | unresolved | DRC_MIN_SPACING, GUARD_RING_SPACING |
| latchup_ring_width | latch_up | advisory | unresolved | GUARD_RING_RULE_MIN, GUARD_RING_WIDTH |
| rail_em | power_em | blocking | unresolved | IO_CURRENT, METAL_JMAX, RAIL_WIDTH |
| pad_pitch_drc | pad_ring | advisory | unresolved | DRC_MIN_SPACING, PAD_PITCH |
| dq_lane_identity | matching | blocking | structural | - |
| separate_io_rails | pad_ring | advisory | structural | - |

Unresolved inputs: 39 (of 41).
Derived quantities unresolved: 11.

## Why composite

CELL_WIDTH and CELL_HEIGHT are derived from W/NF/M, guard-ring
spacing/width, rail width and ESD diode sides. One parameter
therefore drives geometry, ESD, latch-up and power-EM checks
at the same time; see constraint_graph.dot.

## Files

- layout_constraints.json - evaluated composite constraints
- placement.json - device instances, nets, rails, symbolic boxes
- constraint_graph.dot - composite dependency graph
- draw_layout.py - KLayout batch script (pya)
- sdr_bidir_pad_topology.gds - symbolic topology sketch only

## Not a layout yet

- fill the 8 deferred pdk_rules: EM/ESD/latch-up/package data and design specs (see reports/pdk_rule_evidence.md)
- fill all 31 design params from load simulation
- define PAD_OE_CTRL and expand the pre-driver to PDRV_STAGES
- confirm diode orientation, bulk ties and resistor third terminal
- run PEX/SPICE, EM/IR, latch-up and ESD checks
- produce DRC/LVS-clean GDS and a pad-ring integration

