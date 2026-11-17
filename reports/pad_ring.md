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

## 3. What is and is not covered

Covered:
- pad tile-out on four sides with a non-overlapping placement check,
- a seal ring frame (Comp / Nwell / Pplus / Contact, Metal1..MetalTop,
  Via1..Via5).

Not covered:
- **guard ring per pad**: the pad cell still has no Nwell/Pplus guard ring
  around its devices. This is the remaining half of the "guard ring" item.
- DRC/LVS on the assembled ring, pad-to-pad spacing rules, the die core
  power grid, bond pads / package.
- ESD qualification (see `reports/p1_4_channel.md` section 6: the clamp is
  still inadequate).

`reports/capability_report.md` stays `NO_GO`.
