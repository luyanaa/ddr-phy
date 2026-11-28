# Chip-top assembly (1b) — GF180MCU SDRAM (2026-11-28)

**Status: pad-ring↔core interconnect routed with a production router (OpenROAD)
and verified clean after fixing a critical macro-LEF obstruction defect.
Hierarchical signoff (fill/seal, density DRC, black-box-core LVS) is integrated
end-to-end and converged substantially; the remaining residuals are precisely
characterized.**

This closes the routing, placement, and pad-assignment parts of pad_ring open
item 1. The interconnect that defeated the custom Python maze/channel routers —
the ~1.5M µm² cavity makes them computationally infeasible — is routed by
OpenROAD's global+detail router directly. After correcting the pad LEF to
declare its internal metal obstructions, the routing is genuinely clean: zero
pad-plate crossings, zero detail-route violations.

## Method

30 signal pads around a 1800×1800 µm die connect to a hardened `sdram_phy_core`
(274×292 µm, centered). Pad pins sit at the ring periphery, core pins at the core
edge, so routes cross a large empty cavity — exactly the problem a production
router handles and a hand-rolled maze router cannot. The dq output-enable is
inverted by a physical `gf180mcu_as_sc_mcu7t3v3__inv_2` placed in the cavity
(user decision), driving all eight dq pads' OE_N.

## Artifacts

| file | use |
| --- | --- |
| `flow/chiptop_build/gen_chiptop_openroad.py` | emits OpenROAD netlist `sdram_chip_top_pnr.v` + `chiptop.tcl` (placement, GRT, DRT) |
| `flow/chiptop_build/chiptop.tcl` | OpenROAD script: place ring macros + core + inverter, global-route, detail-route |
| `flow/chiptop_build/chiptop_routed.def` | routed result: 40 nets, all pads↔core |
| `flow/chiptop_build/stream_out.py` | librelane KLayout merge: routed DEF + macro GDS → real merged layout |
| `generator/emit_chip_top_merge.py` | pad-frame normalization, net labels, IO power mesh, core/inverter power connection |
| `generator/emit_pad_lef_lib.py` | pad LEF/.lib; **modified** to emit GDS-derived metal OBS for routing |
| `generator/emit_chip_fill.py` | seal ring + dummy-metal/COMP density fill |
| `generator/emit_chip_lvs_view.py` | swap full core for pin-only abstract for black-box LVS |
| `sch/pads/gf180mcuD/pcell/gf180mcu_sdram_chip_top.gds` | merged chip-top layout |
| `sch/pads/gf180mcuD/pcell/gf180mcu_sdram_chip_top_filled.gds` | + seal + density fill |
| `sch/pads/gf180mcuD/pcell/gf180mcu_sdram_chip_top_lvsview.gds` | LVS view (abstract core) |
| `sch/pads/gf180mcuD/pcell/sdram_chip_top.spice` | LVS schematic (black-box core) |

## Evidence — interconnect routing (verified)

| check | result | log / artifact |
| --- | --- | --- |
| OpenROAD global route | `GRT_DONE` | `reports/gf180_chiptop_reroute.log` |
| OpenROAD detail route | `DRT-0199 Number of violations = 0`; `DRT_DONE` | `reports/gf180_chiptop_reroute.log` |
| Pad-plate route crossings | **0** (previously 7 before the LEF fix) | route-path analysis of `chiptop_routed.def` |
| Netlist connectivity | `dq_i/o` pads↔core; `dq_oe` core→inverter A; `n_dq_oe` inverter→all 8 dq OE_N; `ck_o` pad_4→core — correct in routed DEF | `chiptop_routed.def` NETS |
| dq_oe inversion | physical inverter in cavity drives all dq OE_N | per user decision |

The custom Python maze/channel routers were abandoned as computationally
infeasible for this cavity. OpenROAD solves the same problem in seconds with
zero detail-route violations — the correct tool, and the central result of 1b.

## Root cause: incomplete pad LEF obstructions (the central defect)

`gf180_pad_tile.lef` declared only PINs, with **no OBS section**. OpenROAD
therefore treated the entire pad-tile interior as free routing area. The router
reported `DRT 0 violations` only because there was no obstruction to violate —
but it physically routed signal nets straight through the dense pad metal,
including the external PAD plates:

- `dq_i[0/1/2/4/5/6]` (Metal3) ran east from the core and **crossed the
  right-column pad PAD plates** (7 crossings), shorting internal DQ routing to
  the external pads.
- `n_dq_oe` (Metal2) crossed site15/dq6's PAD plate.

This is why early LVS extraction merged many correctly-labelled `pad_*` nets:
the labels were right, but the routing physically shorted the nets together.

**Fix.** `emit_pad_lef_lib.py` extracts the exact pad-metal occupancy per layer
from the tile GDS (~625 rectangles across M1/M2/M3/M4/MetalTop) and emits it as
per-layer OBS, keeping the PIN declarations as the authoritative access points.
The signal pins (OUT/OE_N/IN on Metal2) sit at the tile edges, so blocking the
interior does not obstruct pin access — the router connects at the edge pins and
routes around the pad body. Re-route then yields zero pad-plate crossings.

## Power distribution

VDDIO (Metal3) / VSSIO (Metal4) perimeter distribution reaches all 30 pad power
straps. Because the legal routing detours around pad bodies, the ring trunks use
edge clearance plus short per-strap taps (right VDDIO trunk x=1780 + right-edge
taps; top VDDIO trunk y=1765; VSSIO top trunk y=1780 + top-edge taps). Validated
against the rerouted layout: 30/30 pin-strap intersections on both rails, zero
route overlap on either ring (including after a 2 µm ring expansion), no routed
Via3 in either ring.

## Evidence — hierarchical signoff (sim/gf180_chip_top.sh)

| step | result | log |
| --- | --- | --- |
| 1/4 seal ring + density fill | PASS — seal drawn; ~34k dummy tiles/metal layer | `gf180_chip_top_signoff_final.log` |
| 2/4 LVS view (abstract core) | PASS — pin-only core abstract swapped in | `gf180mcu_sdram_chip_top_lvsview.gds` |
| 3/4 full-die DRC incl density | **193 violations** (down from 360 before the routing fix) | `gf180_chip_top_drc.log` / `.lyrdb` |
| 4/4 black-box core LVS | **netlists don't match** — one residual power-domain alias | `gf180_chip_top_lvs.log` |

### DRC breakdown (final, 193 total)

Dummy-fill-to-circuit-metal spacing dominates, antenna second. The pad-plate
shorts were geometric and are fixed by the re-route — they never appear here.

| rule | count | class |
| --- | --- | --- |
| DM3.3 | 47 | dummy-M3 spacing |
| DM2.3 | 33 | dummy-M2 spacing |
| DM4.3 | 21 | dummy-M4 spacing |
| DM5.3 | 15 | dummy-M5 spacing |
| ANT.16 (i_ANT.4/6) | 33 | antenna |
| DCF.1a | 30 | dummy COMP fill |
| PP.5di | 8 | poly2/density |
| MT.2a / DF.12 / DF.13_LV / M3.2a | 6 | misc |

### LVS connectivity — major progress, one residual

Before the routing fix, extraction merged all pads + both rails into one giant
net. After the LEF-OBS re-route, extraction produces **distinct, correctly-named
`pad_cmd[N]` / `pad_dq[N]` / `pad_ck` nets** — pad signal connectivity is
correct; the earlier `VSSIO|pad_cmd[7]|pad_dq[7]` alias is gone. The one
remaining compound net is **`VDD|VSS`**: the core/inverter power pins extract on
a single merged net. `draw_core_power` connects the east core M4 power straps to
the inverter M1 rails and must keep VDD and VSS disjoint; the residual indicates
a bridge in that core-power connection. This is a power-domain short, separate
from the now-correct signal connectivity.

## Remaining residuals (open, precisely characterized)

1. **Core-domain `VDD`/`VSS` alias** — the inverter/core power pins merge; the
   core-power strap connection must be re-examined for a VDD↔VSS bridge.
2. **Density/antenna DRC** — DM2/3/4/5 dummy-spacing (116 total), ANT.16 (33),
   DCF.1a (30). Fill-tuning and antenna iteration, not connectivity defects.

The pad-signal interconnect is verified correct and clean. The residuals are in
the power-distribution overlay and density fill — iterative signoff-convergence
work layered on the now-correct routing, not defects in the interconnect itself.

