# Pad ring assembly — GF180MCU (2026-11-27)

**Status: 1a closed at tile and ring-structure level; chip-top assembly (1b)
and ESD/latch-up qualification (1c) remain open.**

The earlier note that the pad's dense M2 mesh had no accessible PAD/VSSIO
port is obsolete.  `generator/gf180_pad_layout.py` now carries explicit
M3/M4 corridors, an internal 160 µm ggNMOS clamp and a VSSIO Metal4 lane
that reaches the top cell edge.  `generator/emit_pad_tile.py` adds the
VSSIO guard-ring strip and via stack, so one `gf180_pad_tile` is the
DRC/LVS-clean unit that the ring places.

## 1. Artifacts

| file | use |
|---|---|
| `generator/gf180_pad_layout.py` | pad macro + M3/M4 corridor + edge port |
| `generator/emit_pad_tile.py` | pad + VSSIO guard ring + via stack |
| `generator/emit_pad_ring.py` | ring assembler (tiles only, no seal) |
| `generator/emit_pad_lef_lib.py` | LEF + Liberty views for the tile |
| `sch/pads/gf180mcuD/pcell/gf180_pad_core.gds` | pad macro, 111.5 × 151.3 µm |
| `sch/pads/gf180mcuD/pcell/gf180_pad_tile.gds` | pad + ring, 111.5 × 185 µm |
| `sch/pads/gf180mcuD/pcell/gf180_pad_ring.gds` | 32-tile ring, 1800 × 1800 µm |
| `sch/pads/gf180mcuD/pcell/gf180_pad_tile.lef` / `.lib` | PnR and STA views |

## 2. Evidence

| check | result | log |
|---|---|---|
| pad core flat DRC | **0 violations** | `reports/gf180_pad_core_drc.log` |
| pad core LVS | **netlists match** (34 devices) | `reports/gf180_pad_core_lvs.log` |
| pad tile flat DRC | **0 violations** | `reports/gf180_pad_tile_drc.log` |
| pad tile LVS (wrapper `gf180_pad_tile` + `gf180_pad_core`) | **netlists match** | `reports/gf180_pad_tile_lvs.log` |
| ring flat DRC, `decks=all,-density` | **0 violations** | `reports/gf180_pad_ring_drc.log` |

The ring DRC excludes the die-level density deck on purpose: density is
computed over the whole die, and an empty 1.8 mm ring with no core and no
chip fill cannot meet 25–30 % coverage.  Density must be re-run on the
complete chip top once the core and fill exist.  That is part of 1b.

## 3. Ring parameters

```text
python3 generator/emit_pad_ring.py
  wrote .../gf180_pad_ring.gds (32 tiles, 1800 x 1800 um die)
  tiles per side: bottom/top 9, left/right 7
  overlap / inside-seal checks: pass
```

* pitch 190 µm, tile height 185 µm, 5 µm corner clearance (DCF.4/DPF.4).
* tile bbox `(-66.5,-65) .. (45,120)` µm; pad origin is not the bbox corner.
* 32 signal/power positions.  The 30 PHY signals (21 cmd + 8 dq + 1 ck)
  plus 2 power positions fit; corners are deliberately empty.
* no seal ring in this GDS: a chip-level seal is drawn at assembly.  The
  seal frames that were present in the first pass were removed because a
  20 µm-wide contact/via frame violated CO.1/V1.1 and the metal frames
  violated the density deck.

## 4. Pad tile views (1b prerequisite)

`gf180_pad_tile.lef` / `gf180_pad_tile.lib` are generated from the same pin
table as the GDS:

| pin | direction | layer / note |
|---|---|---|
| OUT, OE_N, PU_OK | input | Metal2 pads on the core side |
| IN | output | Metal2 receiver output |
| PAD | inout | MetalTop 64 µm bond pad + Metal3 corridor |
| VDDIO | power | Metal2/Metal3 |
| VSSIO | ground | Metal4 edge lane + Metal2 guard-ring bar |

Liberty timing is the SPICE characterization already in
`reports/pad_char_gf180mcuD_*.json` and `reports/pad_delay_gf180mcuD_*.json`
(out→pad 0.441 ns max, pad→in 0.096 ns max, OE on 0.608 ns, OE off
3.299 ns).  It is a design-assumption model: no IBIS, no package, no ESD
qualification.

## 5. Open items and user decisions (2026-11-27)

1. **Chip top (1b)**: **routing, placement, pad assignment, and hierarchical
   DRC/LVS are now built** — see `reports/chip_top.md`.  The hardened core is
   placed inside the ring, all 30 signal pads are assigned, VDDIO/VSSIO and
   core PDN are added, and the pad pins are routed to the core pins by
   OpenROAD's global+detail router.  After correcting the pad LEF to declare
   its internal metal obstructions, the interconnect is verified clean: zero
   pad-plate crossings, zero detail-route violations.  Hierarchical signoff
   (fill/seal, density DRC, black-box-core LVS) is integrated end-to-end; the
   remaining residuals — a core-domain `VDD`/`VSS` power alias and
   density/antenna DRC — are precisely characterized in `reports/chip_top.md`.
   The custom Python maze/channel routers are permanently abandoned as
   computationally infeasible for the cavity.
2. **ESD/latch-up (1c)**: **user accepted the current evidence** — BSIM
   pulse stress (32.2 V @ 1 A/100 ns, no snapback) plus GF180 DRC ESD/LU
   rules.  This is not TLP/HBM silicon qualification, so `esd_verified`
   remains false and the formal capability decision remains **NO_GO**.
3. **Density**: rerun `gf180mcu.drc` without `-density` exclusion on the
   finished chip top.
4. **Timing**: `t_uncertainty = 0.60 ns` is **held by user decision**; S3 is
   `deferred` until the measured value is supplied.  Do not change the SDC
   for this item.
