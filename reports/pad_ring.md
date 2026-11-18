# Pad ring assembly (structural first pass)

**Status: structural assembly, not signoff.** The pad cell is unchanged and
carries no dedicated guard ring yet; the ring adds the tile-out and a seal
ring. No DRC/LVS has been run on the assembled ring.

## 1. Artifacts

| file | use |
|---|---|
| `generator/emit_pad_ring.py` | KLayout `pya` ring assembler |
| `sch/pads/gf180mcuD/pcell/gf180_pad_ring.gds` | assembled ring |
| `sch/pads/gf180mcuD/pcell/gf180_pad_ring_manifest.json` | parameters / status |

## 2. Result

```text
python3 generator/emit_pad_ring.py --die-um 1500 1500 --pitch-um 145
  wrote .../gf180_pad_ring.gds (36 pads, 1500 x 1500 um die)
  pads per side: bottom/top 9, left/right 9
  overlap check: pass
```

GDS check (`klayout -b -r` probe):

| item | value |
|---|---|
| top cell | `gf180_pad_ring` |
| instances | **36** |
| bbox | (-65, -65) .. (1565, 1565) um |
| Comp / Nwell / Pplus seal frame | present |
| Metal1..MetalTop + Via1..Via5 frame | present |

Rotation: bottom pads R0, top R180, left R270, right R90, so the pad stack
sits on the die edge and the core side faces inward. The die interior is
1.5 x 1.5 mm with a 20 um seal ring.

## 3. Guard ring and ESD clamp cells

Both are delivered as **standalone, DRC/LVS-verified cells** and instanced in
every pad slot (108 instances total: 36 pads + 36 guard rings + 36 clamps).

### Guard ring (`generator/emit_guard_ring.py`)

| layer | geometry |
|---|---|
| Comp | 1.0 um band |
| Pplus | Comp + 0.16 um each side |
| Contact | 0.22 um squares at 0.5 um pitch (CO.2a = 0.25) |
| Metal1 | Comp + 0.07 um each side |
| Via1 | 0.26 um squares at 0.6 um pitch (V1.2a = 0.26) |
| Metal2 | Comp + 0.07 um each side |

`sh sim/gf180_guard_ring.sh` -> **PASS full DRC (0 violations)**.

### ESD clamp (`generator/emit_esd_clamp.py`)

Grounded-gate NMOS, 40 fingers x 2 um = 80 um channel, gate/source/bulk on
VSSIO, drain on PAD, with its own Metal2 channel so it cannot cross the
output stage's buses.

`sh sim/gf180_esd_clamp.sh`:
```text
PASS gf180_esd_clamp DRC (geometry clean; 5 die-level density only)
PASS gf180_esd_clamp LVS (Netlists match)
```

The extracted device is `M$1 PAD VSSIO VSSIO VSSIO nfet_03v3 W=80U` - the
gate, source and bulk are one net, which is what the earlier in-cell
attempts failed to achieve.

The five density violations are die-level (DCF.1b, PL.8, M1.4/M3.4/M4.4/
M5.4/MT.3): a clamp cell is instanced inside a die that carries the fill,
so they do not apply to the cell.

## 4. What is and is not covered

Covered:
- pad tile-out on four sides with a non-overlapping placement check,
- a seal ring frame (Comp / Nwell / Pplus / Contact, Metal1..MetalTop,
  Via1..Via5),
- a DRC-verified guard ring in every pad slot,
- a DRC/LVS-verified ggNMOS ESD clamp in every pad slot.

Not covered - and this is now a **measured architectural constraint**, not
an unfinished task:

- **the pad cell cannot host a clamp connection inside its own bbox.**
  `generator/emit_pad_tile.py` builds one pad site (pad + clamp + wiring)
  and the full decks show why:
  - the pad's Metal2 is a single dense mesh (one merged polygon spanning
    x -62800..45000, y -49200..48430), so any Metal2 strap shorted PAD to
    VSSIO - measured: the whole pad M2 collapsed into one net and the clamp
    extracted as `W=245U` with PAD|VSSIO merged;
  - Metal1/M2/M3/M4 fill inside the pad bbox is 31.3 / 30.3 / 27.9 / 26.7 %,
    so a Metal4 escape bar also merged into the pad's own M4 island;
  - routing the clamp from outside the bbox clears the collisions (tile
    DRC settles at the six die-level density rules only) but the PAD and
    VSSIO connections still cannot be made without crossing the pad's
    metal islands.

  Closing this needs a **pad cell with a dedicated routing channel**
  (reserved M3/M4 corridor and a PAD/VSSIO port on the cell edge), which
  means changing the pad generator, not the ring. The clamp itself is
  verified: `sim/gf180_esd_clamp_160.sh` -> geometry clean, LVS match,
  Magic PEX, 28.4 V.
- the assembled ring has not passed flat DRC/LVS: the 1.5 mm die with 108
  instances exceeds the DRC run budget (the flat deck timed out at 30 min),
  so ring-level checking needs a hierarchical or tiled flow;
- DRC/LVS on the assembled ring, pad-to-pad spacing rules, the die core
  power grid, bond pads / package,
- ESD qualification: the clamp's effect is measured on the pad macro
  (`reports/p1_4_channel.md` section 6), not on the ring.

`reports/capability_report.md` stays `NO_GO`.
